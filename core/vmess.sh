#!/bin/bash
# ==========================================
# Módulo de Gestión: VMess (WS, gRPC & SlowDNS)
# Requiere el Xray Manager Maestro Instalado
# ==========================================
C_RED='\033[1;31m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_CYAN='\033[1;36m'; C_NC='\033[0m'
XRAY_DIR="/usr/local/etc/xray"
CONF_FILE="$XRAY_DIR/config.json"
DOM_FILE="/etc/vps-manager/dominio"
DOM_FILE_ALT="/etc/vps-manager/domain.txt"
LIMIT_FILE="/etc/vps-manager/limites_vmess"

if [ ! -f "$CONF_FILE" ]; then
    clear
    echo -e "${C_RED}[!] Motor Xray no encontrado o archivo config.json faltante.${C_NC}"
    echo -e "${C_YELLOW}Por favor, instala primero el núcleo desde:${C_NC}"
    echo -e "Opción 4 (Installers) -> 1 (HAProxy TCP + Xray + SSH-WS)"
    read -p "Presiona ENTER para salir..." foo
    exit 1
fi

get_domain() {
    local dom
    dom=$(cat "$DOM_FILE" 2>/dev/null \vert{}\vert{} cat "$DOM_FILE_ALT" 2>/dev/null | tr -d ' \r\n')
    [ -z "$dom" ] && dom=$(curl -4 -sS ipv4.icanhazip.com 2>/dev/null)
    echo "$dom"
}

generar_link_vmess_ntls() {
    local alias=$1 dom=$2 uuid=$3
    local json="{\"v\":\"2\",\"ps\":\"$alias\",\"add\":\"$dom\",\"port\":\"80\",\"id\":\"$uuid\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$dom\",\"path\":\"/vmess\",\"tls\":\"none\"}"
    echo "vmess://$(echo -n "$json" | base64 -w 0)"
}

generar_link_vmess_tls() {
    local alias=$1 dom=$2 uuid=$3
    local json="{\"v\":\"2\",\"ps\":\"$alias\",\"add\":\"$dom\",\"port\":\"443\",\"id\":\"$uuid\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$dom\",\"path\":\"/vmess\",\"tls\":\"tls\",\"sni\":\"$dom\"}"
    echo "vmess://$(echo -n "$json" | base64 -w 0)"
}

generar_link_vmess_grpc() {
    local alias=$1 dom=$2 uuid=$3
    local json="{\"v\":\"2\",\"ps\":\"$alias\",\"add\":\"$dom\",\"port\":\"443\",\"id\":\"$uuid\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"grpc\",\"type\":\"gun\",\"host\":\"$dom\",\"path\":\"vmess-grpc\",\"tls\":\"tls\",\"sni\":\"$dom\"}"
    echo "vmess://$(echo -n "$json" | base64 -w 0)"
}

menu_vmess() {
    while true; do
        clear
        echo -e "${C_YELLOW}      GESTIÓN DE VMESS (WS, gRPC & SLOWDNS)     ${C_NC}"
        echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
        echo -e "${C_CYAN}[1] >${C_NC} Crear Cuenta Vmess (Genera WS, gRPC y SlowDNS)"
        echo -e "${C_CYAN}[2] >${C_NC} Eliminar Cuenta Vmess"
        echo -e "${C_CYAN}[3] >${C_NC} Renovar Días de Cuenta"
        echo -e "${C_CYAN}[4] >${C_NC} Bloquear / Suspender Cuenta"
        echo -e "${C_CYAN}[5] >${C_NC} Configurar Límite de Dispositivos"
        echo -e "${C_CYAN}[6] >${C_NC} Ver Estado del Servicio Xray"
        echo -e "${C_CYAN}[x] >${C_NC} Salir del Gestor"
        echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
        read -p "Digite su opción: " opc

        case $opc in
            1)
                clear
                echo -e "${C_YELLOW}      CREAR USUARIO XRAY VMESS${C_NC}"
                echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
                read -p "Nombre de usuario: " user
                [ -z "$user" ] && continue
                read -p "Duración (días) [Enter = 30]: " dias
                dias=${dias:-30}

                UUID=$(cat /proc/sys/kernel/random/uuid)
                EXP_DATE=$(date -d "+$dias days" +"%Y-%m-%d")
                DOM=$(get_domain)

                jq --arg u "$user" --arg id "$UUID" '
                    (.inbounds[] | select(.tag=="vmess-ws" or .tag=="vmess-grpc") | .settings.clients) += [{"id": $id, "email": $u, "alterId": 0}]
                ' "$CONF_FILE" > "${CONF_FILE}.tmp" && mv -f "${CONF_FILE}.tmp" "$CONF_FILE"
                systemctl restart xray

                LINK_TLS=$(generar_link_vmess_tls "$user-WS-TLS" "$DOM" "$UUID")
                LINK_NTLS=$(generar_link_vmess_ntls "$user-WS-NTLS" "$DOM" "$UUID")
                LINK_GRPC=$(generar_link_vmess_grpc "$user-gRPC" "$DOM" "$UUID")

                clear
                echo -e "${C_YELLOW}   CUENTA VMESS CREADA (WS & gRPC ACTIVOS)${C_NC}"
                echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
                echo -e " Alias       : ${C_CYAN}$user${C_NC}"
                echo -e " Dominio     : ${C_CYAN}$DOM${C_NC}"
                echo -e " UUID        : ${C_CYAN}$UUID${C_NC}"
                echo -e " Expira      : ${C_CYAN}$EXP_DATE${C_NC}"
                echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
                echo -e "\n ${C_GREEN}1. LINK WS TLS (Puerto 443) :${C_NC}\n$LINK_TLS\n"
                echo -e " ${C_GREEN}2. LINK WS NTLS (Puerto 80 / V2Ray+SlowDNS) :${C_NC}\n$LINK_NTLS\n"
                echo -e " ${C_GREEN}3. LINK gRPC (Puerto 443)   :${C_NC}\n$LINK_GRPC\n"

                if systemctl is-active --quiet slowdns; then
                    SL_NS=$(cat /etc/slowdns/domain.ns 2>/dev/null || echo "No configurado")
                    SL_PUB=$(cat /etc/slowdns/server.pub 2>/dev/null || echo "No configurada")
                    echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
                    echo -e " 🐢 ${C_CYAN}PARÁMETROS V2RAY + SLOWDNS (HTTP CUSTOM):${C_NC}"
                    echo -e " 🌍 NS Domain : ${C_YELLOW}$SL_NS${C_NC}"
                    echo -e " 🔑 Pub Key   : ${C_YELLOW}$SL_PUB${C_NC}"
                    echo -e " 📥 Link V2Ray: Usa el ${C_GREEN}LINK 2 (WS NTLS Puerto 80)${C_NC}"
                fi

                echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
                read -p "Presiona ENTER para volver al menú " foo
                ;;
            2)
                clear
                echo -e "${C_YELLOW}     ELIMINAR USUARIO XRAY VMESS${C_NC}"
                echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
                read -p "Usuario a eliminar: " user
                [ -z "$user" ] && continue

                jq --arg u "$user" '
                    (.inbounds[] | select(.settings.clients != null) | .settings.clients) |= map(select(.email != $u))
                ' "$CONF_FILE" > "${CONF_FILE}.tmp" && mv -f "${CONF_FILE}.tmp" "$CONF_FILE"
                systemctl restart xray

                echo -e "${C_GREEN}[✔] Cuenta $user eliminada de WebSocket y gRPC correctamente.${C_NC}"
                read -p "Presiona ENTER para continuar..." foo
                ;;
            3)
                clear
                echo -e "${C_YELLOW}      RENOVAR CUENTA XRAY VMESS${C_NC}"
                echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
                read -p "Nombre del usuario a renovar: " user
                read -p "Días a sumar: " dias_extras
                if [ -z "$user" ] \vert{}\vert{} [ -z "$dias_extras" ]; then continue; fi

                NUEVA_EXP=$(date -d "+$dias_extras days" +"%Y-%m-%d")
                echo -e "${C_GREEN}[✔] Cuenta$user renovada. Nueva vigencia estimada hasta: $NUEVA_EXP${C_NC}"
                read -p "Presiona ENTER para continuar..." foo
                ;;
            4)
                clear
                echo -e "${C_YELLOW}     BLOQUEAR / SUSPENDER USUARIO${C_NC}"
                echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
                read -p "Nombre del usuario a bloquear: " user
                [ -z "$user" ] && continue

                jq --arg u "$user" '
                    (.inbounds[] | select(.settings.clients != null) | .settings.clients) |= map(select(.email != $u))
                ' "$CONF_FILE" > "${CONF_FILE}.tmp" && mv -f "${CONF_FILE}.tmp" "$CONF_FILE"
                systemctl restart xray

                echo -e "${C_GREEN}[✔] El usuario $user ha sido bloqueado del servidor.${C_NC}"
                read -p "Presiona ENTER para continuar..." foo
                ;;
            5)
                clear
                echo -e "${C_YELLOW}      LÍMITE DE DISPOSITIVOS (IPs)      ${C_NC}"
                echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
                read -p "Nombre del usuario: " user
                read -p "Máximo de dispositivos permitidos: " max_disp
                if [ -z "$user" ] \vert{}\vert{} [ -z "$max_disp" ]; then continue; fi

                mkdir -p /etc/vps-manager
                echo "$user $max_disp" >> "$LIMIT_FILE"
                echo -e "${C_GREEN}[✔] Límite de $max_disp dispositivos configurado para $user.${C_NC}"
                read -p "Presiona ENTER para continuar..." foo
                ;;
            6)
                clear
                echo -e "${C_CYAN}ESTADO ACTUAL DEL SERVICIO XRAY:${C_NC}\n"
                systemctl status xray --no-pager | grep -E "Active:|Main PID:"
                echo ""
                read -p "Presiona ENTER para volver al menú " foo
                ;;
            x|X|"") break ;;
        esac
    done
}

menu_vmess
