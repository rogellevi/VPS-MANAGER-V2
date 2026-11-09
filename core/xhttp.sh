#!/bin/bash
# =========================================================================
# Gestor de Cuentas VLESS-XHTTP (Xray Core) - Golbert VPS V7.0 LTS
# =========================================================================
C_RED='\033[1;31m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'
C_CYAN='\033[1;36m'; C_WHITE='\033[1;37m'; C_NC='\033[0m'

XRAY_CONFIG="/usr/local/etc/xray/config.json"
DOMAIN_FILE="/etc/vps-manager/dominio"
DOMAIN_FILE_ALT="/etc/vps-manager/domain.txt"

get_domain() {
    local dom
    dom=$(cat "$DOMAIN_FILE" 2>/dev/null || cat "$DOMAIN_FILE_ALT" 2>/dev/null | tr -d ' \r\n')
    [[ -z "$dom" ]] && dom=$(curl -4 -sS ipv4.icanhazip.com 2>/dev/null)
    echo "$dom"
}

crear_xhttp() {
    clear
    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e " 🚀 CREAR CUENTA VLESS XHTTP (SPLIT-HTTP)"
    echo -e "${C_CYAN}================================================${C_NC}"
    read -r -p "👤 Nombre de usuario: " user
    [[ -z "$user" ]] && { echo -e "${C_RED}Usuario inválido.${C_NC}"; sleep 2; return; }

    if jq -e --arg u "$user" '.inbounds[] | select(.tag=="vless-xhttp") | .settings.clients[]? | select(.email==$u)' "$XRAY_CONFIG" >/dev/null 2>&1; then
        echo -e "${C_RED}[!] El usuario ya existe.${C_NC}"
        sleep 2
        return
    fi

    read -r -p "⏳ Días de duración [Enter = 30]: " dias
    dias=${dias:-30}
    exp_date=$(date -d "+${dias} days" +"%Y-%m-%d")
    uuid=$(cat /proc/sys/kernel/random/uuid)
    domain=$(get_domain)

    jq --arg u "$user" --arg id "$uuid" '
        (.inbounds[] | select(.tag=="vless-xhttp") | .settings.clients) += [{"id": $id, "email": $u}]
    ' "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp" && mv -f "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"

    systemctl restart xray

    link_tls="vless://${uuid}@${domain}:443?encryption=none&security=tls&sni=${domain}&alpn=http%2F1.1&fp=chrome&type=xhttp&host=${domain}&path=%2Fxhttp&mode=auto#${user}_XHTTP_TLS"
    link_ntls="vless://${uuid}@${domain}:80?encryption=none&security=none&type=xhttp&host=${domain}&path=%2Fxhttp&mode=auto#${user}_XHTTP_80"

    clear
    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e " ✅ ${C_GREEN}CUENTA VLESS-XHTTP CREADA EXITOSAMENTE${C_NC}"
    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e " 👤 ${C_WHITE}Usuario   :${C_NC} $user"
    echo -e " 🌐 ${C_WHITE}Dominio   :${C_NC} $domain"
    echo -e " 🔑 ${C_WHITE}UUID      :${C_NC} $uuid"
    echo -e " 🔌 ${C_WHITE}Puerto TLS:${C_NC} 443"
    echo -e " 🔌 ${C_WHITE}Puerto HTTP:${C_NC} 80 / 8080"
    echo -e " 📡 ${C_WHITE}Red (Type):${C_NC} xhttp (SplitHTTP)"
    echo -e " ⚙️ ${C_WHITE}Modo      :${C_NC} auto (packet-up / stream-up)"
    echo -e " 🛣️ ${C_WHITE}Path      :${C_NC} /xhttp"
    echo -e " 📅 ${C_WHITE}Expira    :${C_NC} $exp_date"
    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e " 🔗 ${C_YELLOW}LINK XHTTP TLS (Puerto 443):${C_NC}"
    echo -e "$link_tls\n"
    echo -e " 🔗 ${C_YELLOW}LINK XHTTP SIN TLS (Puerto 80):${C_NC}"
    echo -e "$link_ntls"
    echo -e "${C_CYAN}================================================${C_NC}"
    read -r -p "Presiona Enter para continuar..."
}

eliminar_xhttp() {
    clear
    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e " 🗑️ ELIMINAR CUENTA VLESS XHTTP"
    echo -e "${C_CYAN}================================================${C_NC}"
    mapfile -t users < <(jq -r '.inbounds[] | select(.tag=="vless-xhttp") | .settings.clients[]?.email // empty' "$XRAY_CONFIG")

    if [[ ${#users[@]} -eq 0 ]]; then
        echo -e " ${C_YELLOW}No hay cuentas XHTTP registradas.${C_NC}"
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
            (.inbounds[] | select(.tag=="vless-xhttp") | .settings.clients) |= map(select(.email != $u))
        ' "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp" && mv -f "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"
        systemctl restart xray
        echo -e "\n${C_GREEN}[✔] Usuario $target eliminado.${C_NC}"
    else
        echo -e "\n${C_RED}Selección inválida.${C_NC}"
    fi
    sleep 2
}

ver_xhttp() {
    clear
    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e " 📋 LISTA DE CUENTAS VLESS XHTTP"
    echo -e "${C_CYAN}================================================${C_NC}"
    jq -r '.inbounds[] | select(.tag=="vless-xhttp") | .settings.clients[]? | "👤 Usuario: \(.email) | 🔑 UUID: \(.id)"' "$XRAY_CONFIG"
    echo -e "${C_CYAN}================================================${C_NC}"
    read -r -p "Presiona Enter para volver..."
}

while true; do
    clear
    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e " 🚀 GESTIÓN DE CUENTAS VLESS XHTTP"
    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e " 1. ➕ Crear cuenta XHTTP"
    echo -e " 2. 🗑️ Eliminar cuenta XHTTP"
    echo -e " 3. 📋 Ver cuentas activas"
    echo -e " 0. 🚪 VOLVER"
    echo -e "${C_CYAN}================================================${C_NC}"
    read -r -p "Selecciona una opción: " op
    case $op in
        1) crear_xhttp ;;
        2) eliminar_xhttp ;;
        3) ver_xhttp ;;
        0) break ;;
    esac
done
