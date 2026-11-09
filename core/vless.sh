#!/bin/bash
# ==========================================
# Módulo de Gestión: VLESS (WS, gRPC & XHTTP Simultáneos)
# Requiere el Xray Manager Maestro Instalado
# ==========================================
C_RED='\033[1;31m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_CYAN='\033[1;36m'; C_NC='\033[0m'
XRAY_DIR="/usr/local/etc/xray"
CONF_FILE="$XRAY_DIR/config.json"
DOM_FILE="/etc/vps-manager/dominio"
DOM_FILE_ALT="/etc/vps-manager/domain.txt"
LIMIT_FILE="/etc/vps-manager/limites_vless"

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

generar_link_vless_ntls() {
    local alias=$1 dom=$2 uuid=$3
    echo "vless://$uuid@$dom:80?path=%2Fvless&security=none&encryption=none&host=$dom&type=ws#$alias"
}

generar_link_vless_tls() {
    local alias=$1 dom=$2 uuid=$3
    echo "vless://$uuid@$dom:443?path=%2Fvless&security=tls&encryption=none&host=$dom&type=ws&sni=$dom#$alias"
}

generar_link_vless_grpc() {
    local alias=$1 dom=$2 uuid=$3
    echo "vless://$uuid@$dom:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni=$dom#$alias"
}

generar_link_vless_xhttp() {
    local alias=$1 dom=$2 uuid=$3
    echo "vless://$uuid@$dom:443?encryption=none&security=tls&sni=$dom&alpn=http%2F1.1&fp=chrome&type=xhttp&host=$dom&path=%2Fxhttp&mode=auto#$alias"
}

menu_vless() {
    while true; do
        clear
        echo -e "${C_YELLOW}   GESTIÓN DE VLESS (WS, gRPC & XHTTP SIMULTÁNEO)   ${C_NC}"
        echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
        echo -e "${C_CYAN}[1] >${C_NC} Crear Cuenta Vless (Genera WS, gRPC y XHTTP juntos)"
        echo -e "${C_CYAN}[2] >${C_NC} Eliminar Cuenta Vless"
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
                echo -e "${C_YELLOW}      CREAR USUARIO XRAY VLESS${C_NC}"
                echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
                read -p "Nombre de usuario: " user
                [ -z "$user" ] && continue
                read -p "Duración (días) [Enter = 30]: " dias
                dias=${dias:-30}

                UUID=$(cat /proc/sys/kernel/random/uuid)
                EXP_DATE=$(date -d "+$dias days" +"%Y-%m-%d")
                DOM=$(get_domain)

                jq --arg u "$user" --arg id "$UUID" '
                    (.inbounds[] | select(.tag=="vless-ws" or .tag=="vless-grpc" or .tag=="vless-xhttp") | .settings.clients) += [{"id": $id, "email": $u}]
                ' "$CONF_FILE" > "${CONF_FILE}.tmp" && mv -f "${CONF_FILE}.tmp" "$CONF_FILE"
                systemctl restart xray

                LINK_TLS=$(generar_link_vless_tls "$user-WS-TLS" "$DOM" "$UUID")
                LINK_NTLS=$(generar_link_vless_ntls "$user-WS-NTLS" "$DOM" "$UUID")
                LINK_GRPC=$(generar_link_vless_grpc "$user-gRPC" "$DOM" "$UUID")
                LINK_XHTTP=$(generar_link_vless_xhttp "$user-XHTTP" "$DOM" "$UUID")

                clear
                echo -e "${C_YELLOW}   CUENTA VLESS CREADA (WS, gRPC & XHTTP ACTIVOS)${C_NC}"
                echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
                echo -e " Alias       : ${C_CYAN}$user${C_NC}"
                echo -e " Dominio     : ${C_CYAN}$DOM${C_NC}"
                echo -e " UUID        : ${C_CYAN}$UUID${C_NC}"
                echo -e " Expira      : ${C_CYAN}$EXP_DATE${C_NC}"
                echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
                echo -e "\n ${C_GREEN}1. LINK WS TLS (Puerto 443)   :${C_NC}\n$LINK_TLS\n"
                echo -e " ${C_GREEN}2. LINK WS NTLS (Puerto 80)   :${C_NC}\n$LINK_NTLS\n"
                echo -e " ${C_GREEN}3. LINK gRPC (Puerto 443)     :${C_NC}\n$LINK_GRPC\n"
                echo -e " ${C_GREEN}4. LINK XHTTP TLS (Puerto 443):${C_NC}\n$LINK_XHTTP\n"
                echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
                read -p "Presiona ENTER para volver al menú " foo
                ;;
            2)
                clear
                echo -e "${C_YELLOW}     ELIMINAR USUARIO XRAY VLESS${C_NC}"
                echo -e "${C_YELLOW}───────────────────────────────────────────────${C_NC}"
                read -p "Usuario a eliminar: " user
                [ -z "$user" ] && continue

                jq --arg u "$user" '
                    (.inbounds[] | select(.settings.clients != null) | .settings.clients) |= map(select(.email != $u))
                ' "$CONF_FILE" > "${CONF_FILE}.tmp" && mv -f "${CONF_FILE}.tmp" "$CONF_FILE"
                systemctl restart xray

                echo -e "${C_GREEN}[✔] Cuenta $user eliminada de WS, gRPC y XHTTP correctamente.${C_NC}"
                read -p "Presiona ENTER para continuar..." foo
                ;;
            3)
                clear
                echo -e "${C_YELLOW}      RENOVAR CUENTA XRAY VLESS${C_NC}"
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

menu_vless
