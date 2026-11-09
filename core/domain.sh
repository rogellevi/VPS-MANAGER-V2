#!/bin/bash
# =========================================================================
# Módulo: Gestor de Dominio y Certificado SSL (Compatible HAProxy + Xray)
# =========================================================================
C_RED='\033[1;31m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_CYAN='\033[1;36m'; C_WHITE='\033[1;37m'; C_NC='\033[0m'

DOM_FILE="/etc/vps-manager/domain.txt"
DOM_FILE_ALT="/etc/vps-manager/dominio"
CERT_DIR="/etc/haproxy/certs"
HAPROXY_CFG="/etc/haproxy/haproxy.cfg"

mkdir -p /etc/vps-manager "$CERT_DIR" /usr/local/etc/xray /etc/stunnel

tramitar_ssl() {
    local dom=$1
    dom=$(echo "$dom" | tr -d ' \r\n')

    if [[ -z "$dom" ]]; then
        echo -e "${C_RED}[!] Dominio vacío o inválido.${C_NC}"
        return 1
    fi

    echo -e "\n${C_YELLOW}[*] Verificando vinculación del subdominio en Cloudflare con la IP del VPS...${C_NC}"
    local vps_ip dom_ip
    vps_ip=$(curl -4 -sS --max-time 5 ipv4.icanhazip.com 2>/dev/null || wget -4 -qO- -T 5 ifconfig.me 2>/dev/null)
    vps_ip=$(echo "$vps_ip" | tr -d ' \r\n')

    # Consulta directa a DNS de Cloudflare (1.1.1.1) y respaldo por resolución de sistema
    dom_ip=$(curl -4 -sS --max-time 5 -H "accept: application/dns-json" "https://1.1.1.1/dns-query?name=${dom}&type=A" 2>/dev/null | jq -r '.Answer[]? | select(.type==1) | .data' 2>/dev/null | head -n1 | tr -d ' \r\n')
    if [[ -z "$dom_ip" ]]; then
        dom_ip=$(getent ahostsv4 "$dom" 2>/dev/null | awk '{print $1}' | head -n1 | tr -d ' \r\n')
    fi

    if [[ -z "$dom_ip" ]] || [[ "$dom_ip" != "$vps_ip" ]]; then
        echo -e "\n${C_RED}========================================================${C_NC}"
        echo -e "${C_RED}   [✖] ERROR: EL SUBDOMINIO NO CUMPLE LOS REQUISITOS    ${C_NC}"
        echo -e "${C_RED}========================================================${C_NC}"
        echo -e " ${C_WHITE}El subdominio ${C_YELLOW}$dom${C_WHITE} no está registrado en Cloudflare${C_NC}"
        echo -e " ${C_WHITE}o no se encuentra vinculado previamente a la IP de tu VPS.${C_NC}\n"
        echo -e " 📌 ${C_CYAN}IP de tu VPS      :${C_NC} ${C_GREEN}${vps_ip:-Desconocida}${C_NC}"
        echo -e " 📌 ${C_CYAN}IP del Subdominio :${C_NC} ${C_RED}${dom_ip:-No registrado / Sin apuntar}${C_NC}\n"
        echo -e " ${C_YELLOW}[!] Vincula primero la IP de tu VPS en Cloudflare (Registro A)${C_NC}"
        echo -e " ${C_YELLOW}    antes de intentar registrarlo en el panel.${C_NC}"
        echo -e "${C_RED}========================================================${C_NC}"
        return 1
    fi

    echo -e "${C_GREEN}[✔] Verificación exitosa: $dom está vinculado a la IP $vps_ip${C_NC}"

    echo "$dom" > "$DOM_FILE"
    echo "$dom" > "$DOM_FILE_ALT"
    chmod 644 "$DOM_FILE" "$DOM_FILE_ALT"

    echo -e "\n${C_YELLOW}[1/4] Liberando temporalmente el puerto 80 para validación SSL...${C_NC}"
    systemctl stop apache2 haproxy ws-proxy http-proxy edu-proxy 2>/dev/null
    fuser -k 80/tcp 2>/dev/null
    sleep 1

    echo -e "${C_YELLOW}[2/4] Solicitando Certificado SSL Let's Encrypt para: ${C_CYAN}$dom${C_NC}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y certbot openssl psmisc >/dev/null 2>&1

    certbot certonly --standalone --preferred-challenges http \
        --non-interactive --agree-tos --keep-until-expiring \
        --cert-name "$dom" -m "admin@$dom" -d "$dom"

    if [ ! -s "/etc/letsencrypt/live/$dom/fullchain.pem" ] || [ ! -s "/etc/letsencrypt/live/$dom/privkey.pem" ]; then
        echo -e "${C_YELLOW}[!] Let's Encrypt no pudo validar el dominio (verifica Nube Gris en Cloudflare).${C_NC}"
        echo -e "${C_YELLOW}[*] Generando certificado SSL autofirmado de respaldo para no detener tus servicios...${C_NC}"
        mkdir -p "/etc/letsencrypt/live/$dom"
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "/etc/letsencrypt/live/$dom/privkey.pem" \
            -out "/etc/letsencrypt/live/$dom/fullchain.pem" \
            -subj "/CN=$dom" >/dev/null 2>&1
    fi

    echo -e "${C_YELLOW}[3/4] Distribuyendo certificado a HAProxy, Xray y Stunnel4...${C_NC}"
    # 1. Xray
    cp -f "/etc/letsencrypt/live/$dom/fullchain.pem" /usr/local/etc/xray/server.crt
    cp -f "/etc/letsencrypt/live/$dom/privkey.pem" /usr/local/etc/xray/server.key
    cat /usr/local/etc/xray/server.crt /usr/local/etc/xray/server.key > /usr/local/etc/xray/haproxy.pem
    chmod 644 /usr/local/etc/xray/server.crt /usr/local/etc/xray/server.key /usr/local/etc/xray/haproxy.pem

    # 2. Stunnel4
    cat "/etc/letsencrypt/live/$dom/fullchain.pem" "/etc/letsencrypt/live/$dom/privkey.pem" > /etc/stunnel/stunnel.pem
    chmod 600 /etc/stunnel/stunnel.pem

    # 3. HAProxy
    cat "/etc/letsencrypt/live/$dom/fullchain.pem" "/etc/letsencrypt/live/$dom/privkey.pem" > "$CERT_DIR/$dom.pem"
    chmod 600 "$CERT_DIR/$dom.pem"

    if [ -f "$HAPROXY_CFG" ]; then
        sed -i -E "s|crt /etc/haproxy/certs/[^ ]+\.pem|crt $CERT_DIR/$dom.pem|g" "$HAPROXY_CFG"
        sed -i -E "s|crt /usr/local/etc/xray/haproxy\.pem|crt $CERT_DIR/$dom.pem|g" "$HAPROXY_CFG"
    fi

    echo -e "${C_YELLOW}[4/4] Reiniciando HAProxy, Xray, SSH-WS, Stunnel y Nginx...${C_NC}"
    systemctl restart xray 2>/dev/null
    systemctl restart ssh-ws ws-python 2>/dev/null
    systemctl restart haproxy 2>/dev/null
    systemctl restart stunnel4 2>/dev/null
    systemctl restart bhttp 2>/dev/null
    systemctl restart nginx 2>/dev/null

    echo -e "\n${C_GREEN}[✔] ¡Dominio ($dom) y Certificados SSL 100% activos en todos los protocolos!${C_NC}"
}

while true; do
    clear
    ACTUAL_DOM=$(cat "$DOM_FILE" 2>/dev/null || cat "$DOM_FILE_ALT" 2>/dev/null || echo "No configurado")
    echo -e "${C_CYAN}========================================================${C_NC}"
    echo -e "${C_GREEN}        GESTOR DE DOMINIO Y CERTIFICADO SSL             ${C_NC}"
    echo -e "${C_CYAN}========================================================${C_NC}"
    echo -e " 🌍 Dominio actual : ${C_YELLOW}$ACTUAL_DOM${C_NC}"
    echo -e "${C_CYAN}--------------------------------------------------------${C_NC}"
    echo -e "  ${C_YELLOW}1.${C_NC} 🌐 Configurar Nuevo Subdominio y Certificar SSL"
    echo -e "  ${C_YELLOW}2.${C_NC} 🔄 Re-certificar Subdominio Actual (Renovar/Reparar)"
    echo -e "  ${C_YELLOW}3.${C_NC} 📋 Ver Estado del Certificado SSL"
    echo -e "  ${C_RED}0.${C_NC} 🚪 Volver al Menú"
    echo -e "${C_CYAN}========================================================${C_NC}"
    read -p " Seleccione una opción: " optdom

    case $optdom in
        1)
            echo ""
            read -p " Ingresa tu nuevo Subdominio (ej. vps.tudominio.com): " ndom
            if [ -n "$ndom" ]; then
                tramitar_ssl "$ndom"
            else
                echo -e "${C_RED}[!] Cancelado: no ingresaste ningún dominio.${C_NC}"
            fi
            read -p " Presione Enter para continuar..."
            ;;
        2)
            if [ -f "$DOM_FILE" ] || [ -f "$DOM_FILE_ALT" ]; then
                adom=$(cat "$DOM_FILE" 2>/dev/null || cat "$DOM_FILE_ALT" 2>/dev/null)
                echo -e "\n${C_YELLOW}[+] Re-certificando el dominio guardado: $adom${C_NC}"
                tramitar_ssl "$adom"
            else
                echo -e "\n${C_RED}[!] No hay dominio guardado en el VPS. Usa la opción 1.${C_NC}"
            fi
            read -p " Presione Enter para continuar..."
            ;;
        3)
            clear
            echo -e "${C_CYAN}=== ESTADO DEL CERTIFICADO SSL ($ACTUAL_DOM) ===${C_NC}\n"
            if [ -f "/etc/letsencrypt/live/$ACTUAL_DOM/fullchain.pem" ]; then
                openssl x509 -in "/etc/letsencrypt/live/$ACTUAL_DOM/fullchain.pem" -noout -subject -issuer -dates
            else
                echo -e "${C_RED}No se encontró certificado activo para $ACTUAL_DOM.${C_NC}"
            fi
            echo ""
            read -p " Presione Enter para regresar..."
            ;;
        0) break ;;
        *) echo -e "${C_RED}Opción inválida.${C_NC}"; sleep 1 ;;
    esac
done
