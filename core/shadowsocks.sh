#!/bin/bash
# =========================================================================
# Gestor de Cuentas Shadowsocks (WS & gRPC) - Golbert VPS V7.0 LTS
# =========================================================================
C_RED='\033[1;31m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'
C_CYAN='\033[1;36m'; C_WHITE='\033[1;37m'; C_NC='\033[0m'

XRAY_CONFIG="/usr/local/etc/xray/config.json"
DOMAIN_FILE="/etc/vps-manager/dominio"
DOMAIN_FILE_ALT="/etc/vps-manager/domain.txt"
CIPHER="chacha20-ietf-poly1305"

if [ ! -f "$XRAY_CONFIG" ]; then
    clear
    echo -e "${C_RED}[!] Motor Xray no encontrado o archivo config.json faltante.${C_NC}"
    read -p "Presiona ENTER para salir..." foo
    exit 1
fi

get_domain() {
    local dom
    dom=$(cat "$DOMAIN_FILE" 2>/dev/null || cat "$DOMAIN_FILE_ALT" 2>/dev/null | tr -d ' \r\n')
    [[ -z "$dom" ]] && dom=$(curl -4 -sS ipv4.icanhazip.com 2>/dev/null)
    echo "$dom"
}

crear_ss() {
    clear
    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e " ⚡ CREAR CUENTA SHADOWSOCKS (WS & gRPC)"
    echo -e "${C_CYAN}================================================${C_NC}"
    read -r -p "👤 Nombre de usuario: " user
    [[ -z "$user" ]] && { echo -e "${C_RED}Usuario inválido.${C_NC}"; sleep 2; return; }

    if jq -e --arg u "$user" '.inbounds[] | select(.tag=="ss-ws") | .settings.clients[]? | select(.email==$u)' "$XRAY_CONFIG" >/dev/null 2>&1; then
        echo -e "${C_RED}[!] El usuario ya existe.${C_NC}"
        sleep 2
        return
    fi

    read -r -p "⏳ Días de duración [Enter = 30]: " dias
    dias=${dias:-30}
    exp_date=$(date -d "+${dias} days" +"%Y-%m-%d")
    password=$(cat /proc/sys/kernel/random/uuid)
    domain=$(get_domain)

    jq --arg u "$user" --arg p "$password" --arg c "$CIPHER" '
        (.inbounds[] | select(.tag=="ss-ws" or .tag=="ss-grpc") | .settings.clients) += [{"password": $p, "cipher": $c, "email": $u}]
    ' "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp" && mv -f "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"

    systemctl restart xray

    raw_cred=$(echo -n "${CIPHER}:${password}" | base64 -w 0)
    plugin_tls="v2ray-plugin;tls;mux=0;mode=websocket;path=/ss;host=${domain}"
    plugin_ntls="v2ray-plugin;mux=0;mode=websocket;path=/ss;host=${domain}"
    plugin_grpc="v2ray-plugin;tls;mode=grpc;serviceName=ss-grpc;host=${domain}"

    ss_link_tls="ss://${raw_cred}@${domain}:443?plugin=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${plugin_tls}'))")#${user}_WS_TLS"
    ss_link_ws="ss://${raw_cred}@${domain}:80?plugin=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${plugin_ntls}'))")#${user}_WS_80"
    ss_link_grpc="ss://${raw_cred}@${domain}:443?plugin=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${plugin_grpc}'))")#${user}_gRPC"

    clear
    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e " ✅ ${C_GREEN}CUENTA SHADOWSOCKS CREADA (WS & gRPC)${C_NC}"
    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e " 👤 ${C_WHITE}Usuario   :${C_NC} $user"
    echo -e " 🌐 ${C_WHITE}Dominio   :${C_NC} $domain"
    echo -e " 🔌 ${C_WHITE}Puerto TLS:${C_NC} 443 (WS & gRPC)"
    echo -e " 🔌 ${C_WHITE}Puerto WS :${C_NC} 80 / 8080"
    echo -e " 🔑 ${C_WHITE}Password  :${C_NC} $password"
    echo -e " 🔒 ${C_WHITE}Cifrado   :${C_NC} $CIPHER"
    echo -e " 🛣️ ${C_WHITE}Path / SN :${C_NC} /ss (WS) | ss-grpc (gRPC)"
    echo -e " 📅 ${C_WHITE}Expira    :${C_NC} $exp_date"
    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e " 🔗 ${C_YELLOW}1. LINK WS TLS (Puerto 443):${C_NC}\n$ss_link_tls\n"
    echo -e " 🔗 ${C_YELLOW}2. LINK WS SIN TLS (Puerto 80):${C_NC}\n$ss_link_ws\n"
    echo -e " 🔗 ${C_YELLOW}3. LINK gRPC TLS (Puerto 443):${C_NC}\n$ss_link_grpc"
    echo -e "${C_CYAN}================================================${C_NC}"
    read -r -p "Presiona Enter para continuar..."
}

eliminar_ss() {
    clear
    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e " 🗑️ ELIMINAR CUENTA SHADOWSOCKS"
    echo -e "${C_CYAN}================================================${C_NC}"
    mapfile -t users < <(jq -r '.inbounds[] | select(.tag=="ss-ws") | .settings.clients[]?.email // empty' "$XRAY_CONFIG")
    
    if [[ ${#users[@]} -eq 0 ]]; then
        echo -e " ${C_YELLOW}No hay cuentas registradas.${C_NC}"
        sleep 2
        return
    fi

    for i in "${!users[@]}"; do
        echo -e " $((i+1)). ${users[$i]}"
    done
    echo -e " 0. Cancelar"
    echo -e "${C_CYAN}================================================${C_NC}"
    read -r -p "Selecciona el número a eliminar: " num
    [[ "$num" == "0" || -z "$num" ]] && return

    target="${users[$((num-1))]}"
    if [[ -n "$target" ]]; then
        jq --arg u "$target" '
            (.inbounds[] | select(.tag=="ss-ws" or .tag=="ss-grpc") | .settings.clients) |= map(select(.email != $u))
        ' "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp" && mv -f "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"
        systemctl restart xray
        echo -e "\n${C_GREEN}[✔] Usuario $target eliminado de WS y gRPC.${C_NC}"
    else
        echo -e "\n${C_RED}Selección inválida.${C_NC}"
    fi
    sleep 2
}

ver_ss() {
    clear
    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e " 📋 LISTA DE CUENTAS SHADOWSOCKS"
    echo -e "${C_CYAN}================================================${C_NC}"
    jq -r '.inbounds[] | select(.tag=="ss-ws") | .settings.clients[]? | "👤 Usuario: \(.email) | 🔑 Pass: \(.password)"' "$XRAY_CONFIG"
    echo -e "${C_CYAN}================================================${C_NC}"
    read -r -p "Presiona Enter para volver..."
}

while true; do
    clear
    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e " ⚡ GESTIÓN DE CUENTAS SHADOWSOCKS (WS & gRPC)"
    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e " 1. ➕ Crear cuenta Shadowsocks"
    echo -e " 2. 🗑️ Eliminar cuenta Shadowsocks"
    echo -e " 3. 📋 Ver cuentas activas"
    echo -e " 0. 🚪 VOLVER"
    echo -e "${C_CYAN}================================================${C_NC}"
    read -r -p "Selecciona una opción: " op
    case $op in
        1) crear_ss ;;
        2) eliminar_ss ;;
        3) ver_ss ;;
        0) break ;;
    esac
done
