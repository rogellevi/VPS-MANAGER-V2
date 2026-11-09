#!/bin/bash
# ==========================================
# Módulo de Gestión: TROJAN (WS & gRPC Simultáneos)
# Requiere el Xray Manager Maestro Instalado
# ==========================================
C_RED='\033[1;31m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_CYAN='\033[1;36m'; C_NC='\033[0m'
XRAY_DIR="/usr/local/etc/xray"
CONF_FILE="$XRAY_DIR/config.json"
DOM_FILE="/etc/vps-manager/dominio"
DOM_FILE_ALT="/etc/vps-manager/domain.txt"
LIMIT_FILE="/etc/vps-manager/limites_trojan"

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
    dom=$(cat "$DOM_FILE" 2>/dev/null || cat "$DOM_FILE_ALT" 2>/dev/null | tr -d ' \r\n')
    [ -z "$dom" ] && dom=$(curl -4 -sS ipv4.icanhazip.com 2>/dev/null)
    echo "$dom"
}

generar_link_trojan_ws_tls() {
    local alias=$1 dom=$2 password=$3
    echo "trojan://$password@$dom:443?path=%2Ftrojan&security=tls&host=$dom&type=ws&sni=$dom#$alias"
}

generar_link_trojan_ws_ntls() {
    local alias=$1 dom=$2 password=$3
    echo "trojan://$password@$dom:80?path=%2Ftrojan&security=none&host=$dom&type=ws#$alias"
}

generar_link_trojan_grpc() {
    local alias=$1 dom=$2 password=$3
    echo "trojan://$password@$dom:443?mode=gun&security=tls&type=grpc&serviceName=trojan-grpc&sni=$dom#$alias"
}

menu_trojan() {
    while true; do
        clear
        echo -e "${C_YELLOW}      GESTIÓN DE TROJAN (WS & gRPC SIMULTÁNEO)     ${C_NC}"
        echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
        echo -e "${C_CYAN}[1] >${C_NC} Crear Cuenta Trojan (Genera WS y gRPC juntos)"
        echo -e "${C_CYAN}[2] >${C_NC} Eliminar Cuenta Trojan"
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
                echo -e "${C_YELLOW}      CREAR USUARIO XRAY TROJAN     ${C_NC}"
                echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
                read -p "Nombre de usuario: " user
                [ -z "$user" ] && continue
                read -p "Duración (días) [Enter = 30]: " dias
                dias=${dias:-30}

                PASS=$(cat /proc/sys/kernel/random/uuid)
                EXP_DATE=$(date -d "+$dias days" +"%Y-%m-%d")
                DOM=$(get_domain)

                jq --arg u "$user" --arg p "$PASS" '
                    (.inbounds[] | select(.tag=="trojan-ws" or .tag=="trojan-grpc") | .settings.clients) += [{"password": $p, "email": $u}]
                ' "$CONF_FILE" > "${CONF_FILE}.tmp" && mv -f "${CONF_FILE}.tmp" "$CONF_FILE"
                systemctl restart xray

                LINK_WS_TLS=$(generar_link_trojan_ws_tls "$user-WS-TLS" "$DOM" "$PASS")
                LINK_WS_NTLS=$(generar_link_trojan_ws_ntls "$user-WS-NTLS" "$DOM" "$PASS")
                LINK_GRPC=$(generar_link_trojan_grpc "$user-gRPC" "$DOM" "$PASS")

                clear
                echo -e "${C_YELLOW}   CUENTA TROJAN CREADA (WS & gRPC ACTIVOS)   ${C_NC}"
                echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
                echo -e " Alias       : ${C_CYAN}$user${C_NC}"
                echo -e " Dominio     : ${C_CYAN}$DOM${C_NC}"
                echo -e " Password    : ${C_CYAN}$PASS${C_NC}"
                echo -e " Expira      : ${C_CYAN}$EXP_DATE${C_NC}"
                echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
                echo -e "\n ${C_GREEN}1. LINK TROJAN WS TLS (Puerto 443) :${C_NC}\n$LINK_WS_TLS\n"
                echo -e " ${C_GREEN}2. LINK TROJAN WS NTLS (Puerto 80) :${C_NC}\n$LINK_WS_NTLS\n"
                echo -e " ${C_GREEN}3. LINK TROJAN gRPC (Puerto 443)   :${C_NC}\n$LINK_GRPC\n"
                echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
                read -p "Presiona ENTER para volver al menú " foo
                ;;
            2)
                clear
                echo -e "${C_YELLOW}     ELIMINAR USUARIO XRAY TROJAN    ${C_NC}"
                echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
                read -p "Usuario a eliminar: " user
                [ -z "$user" ] && continue

                jq --arg u "$user" '
                    (.inbounds[] | select(.settings.clients != null) | .settings.clients) |= map(select(.email != $u))
                ' "$CONF_FILE" > "${CONF_FILE}.tmp" && mv -f "${CONF_FILE}.tmp" "$CONF_FILE"
                systemctl restart xray

                echo -e "${C_GREEN}[✔] Cuenta $user eliminada de WS y gRPC correctamente.${C_NC}"
                read -p "Presiona ENTER para continuar..." foo
                ;;
            3)
                clear
                echo -e "${C_YELLOW}      RENOVAR CUENTA XRAY TROJAN     ${C_NC}"
                echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
                read -p "Nombre del usuario a renovar: " user
                read -p "Días a sumar: " dias_extras
                if [ -z "$user" ] || [ -z "$dias_extras" ]; then continue; fi

                NUEVA_EXP=$(date -d "+$dias_extras days" +"%Y-%m-%d")
                echo -e "${C_GREEN}[✔] Cuenta $user renovada. Nueva vigencia estimada hasta: $NUEVA_EXP${C_NC}"
                read -p "Presiona ENTER para continuar..." foo
                ;;
            4)
                clear
                echo -e "${C_YELLOW}     BLOQUEAR / SUSPENDER USUARIO     ${C_NC}"
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
                if [ -z "$user" ] || [ -z "$max_disp" ]; then continue; fi

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

menu_trojan
