#!/bin/bash
# =========================================================================
# Motor Unificado: HAProxy (80/8080/443) + Xray (WS/Multi-gRPC/XHTTP/SS) + SSH-WS
# =========================================================================
C_RED='\033[1;31m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_CYAN='\033[1;36m'; C_WHITE='\033[1;37m'; C_NC='\033[0m'

VPS_DIR="/etc/vps-manager"
CORE_DIR="${VPS_DIR}/core"
DOMAIN_FILE="${VPS_DIR}/dominio"
DOMAIN_FILE_ALT="${VPS_DIR}/domain.txt"
XRAY_DIR="/usr/local/etc/xray"
XRAY_CONFIG="${XRAY_DIR}/config.json"
HAPROXY_CONFIG="/etc/haproxy/haproxy.cfg"
CERT_DIR="/etc/haproxy/certs"

verificar_cloudflare_ip() {
    local dom=$1
    local vps_ip dom_ip

    echo -e "\n${C_YELLOW}[*] Verificando vinculación del subdominio en Cloudflare con la IP del VPS...${C_NC}"
    vps_ip=$(curl -4 -sS --max-time 5 ipv4.icanhazip.com 2>/dev/null || wget -4 -qO- -T 5 ifconfig.me 2>/dev/null)
    vps_ip=$(echo "$vps_ip" | tr -d ' \r\n')

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
        echo -e " ${C_YELLOW}    antes de instalar el motor V2Ray + WebSocket.${C_NC}"
        echo -e "${C_RED}========================================================${C_NC}"
        return 1
    fi

    echo -e "${C_GREEN}[✔] Verificación exitosa: $dom está vinculado a la IP $vps_ip${C_NC}"
    return 0
}

install_engine() {
    clear
    mkdir -p "${VPS_DIR}" "${CORE_DIR}" "${XRAY_DIR}" "${CERT_DIR}" /var/log/xray

    echo -e "${C_CYAN}========================================================${C_NC}"
    echo -e "${C_YELLOW}  INSTALADOR MOTOR UNIFICADO: HAPROXY + XRAY + SSH-WS   ${C_NC}"
    echo -e "${C_CYAN}========================================================${C_NC}"

    local saved_domain domain
    saved_domain="$(cat "${DOMAIN_FILE}" 2>/dev/null || cat "${DOMAIN_FILE_ALT}" 2>/dev/null)"
    saved_domain="$(echo "$saved_domain" | tr -d ' \r\n')"

    # Si ya existe un dominio válido registrado en el panel, se obvia pedirlo y validarlo
    if [[ -n "${saved_domain}" && "${saved_domain}" != "Noconfigurado" && "${saved_domain}" != "No configurado" ]]; then
        domain="${saved_domain}"
        echo -e " ${C_GREEN}[✔] Subdominio ya registrado en el panel:${C_NC} ${C_YELLOW}${domain}${C_NC}"
        echo -e " ${C_CYAN}[*] Omitiendo registro manual y continuando con la instalación...${C_NC}"
        sleep 1
    else
        echo -e " ${C_YELLOW}[!] No se detectó un subdominio registrado en el panel.${C_NC}\n"
        read -r -p " 🌐 Ingresa tu Subdominio vinculado en Cloudflare: " domain
        domain="$(echo "$domain" | tr -d ' \r\n')"

        if [[ -z "${domain}" ]]; then
            echo -e "\n${C_RED}[!] Cancelado: debes ingresar un subdominio válido.${C_NC}"
            read -r -p " Presiona Enter para volver..."
            return 1
        fi

        if ! verificar_cloudflare_ip "${domain}"; then
            read -r -p " Presiona Enter para volver..."
            return 1
        fi

        echo "${domain}" > "${DOMAIN_FILE}"
        echo "${domain}" > "${DOMAIN_FILE_ALT}"
        chmod 644 "${DOMAIN_FILE}" "${DOMAIN_FILE_ALT}"
    fi

    echo -e "\n${C_YELLOW}[1/5] Liberando puertos 80, 8080 y 443...${C_NC}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null 2>&1
    apt-get install -y haproxy certbot jq python3 openssl psmisc >/dev/null 2>&1
    systemctl stop haproxy xray ssh-ws ws-python apache2 >/dev/null 2>&1
    fuser -k 80/tcp 8080/tcp 443/tcp >/dev/null 2>&1
    sleep 1

    echo -e "${C_YELLOW}[2/5] Configurando certificado SSL para ${domain}...${C_NC}"
    if [[ ! -s "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
        certbot certonly --standalone --preferred-challenges http \
            --non-interactive --agree-tos --keep-until-expiring \
            --cert-name "${domain}" -m "admin@${domain}" -d "${domain}" >/dev/null 2>&1
    fi

    if [[ -s "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
        cat "/etc/letsencrypt/live/${domain}/fullchain.pem" "/etc/letsencrypt/live/${domain}/privkey.pem" > "${CERT_DIR}/${domain}.pem"
        mkdir -p /etc/vps-manager/cert
        cp -f "/etc/letsencrypt/live/${domain}/fullchain.pem" /etc/vps-manager/cert/fullchain.crt
        cp -f "/etc/letsencrypt/live/${domain}/privkey.pem" /etc/vps-manager/cert/private.key
    else
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout /tmp/key.pem -out /tmp/crt.pem -subj "/CN=${domain}" >/dev/null 2>&1
        cat /tmp/crt.pem /tmp/key.pem > "${CERT_DIR}/${domain}.pem"
    fi
    chmod 600 "${CERT_DIR}/${domain}.pem"

    echo -e "${C_YELLOW}[3/5] Instalando/Actualizando Xray Core (WS / gRPC / XHTTP / SS)...${C_NC}"
    bash -c "$(curl -4 -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1

    cat > "${XRAY_CONFIG}.new" <<'JSONEOF'
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "dns": {
    "servers": ["1.1.1.1", "8.8.8.8", "localhost"]
  },
  "inbounds": [
    { "tag": "vless-ws", "listen": "127.0.0.1", "port": 10001, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "/vless" } }, "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] } },
    { "tag": "vmess-ws", "listen": "127.0.0.1", "port": 10002, "protocol": "vmess", "settings": { "clients": [] }, "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "/vmess" } }, "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] } },
    { "tag": "trojan-ws", "listen": "127.0.0.1", "port": 10003, "protocol": "trojan", "settings": { "clients": [] }, "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "/trojan" } }, "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] } },
    { "tag": "ss-ws", "listen": "127.0.0.1", "port": 10005, "protocol": "shadowsocks", "settings": { "clients": [], "network": "tcp,udp" }, "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "/ss" } }, "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] } },
    { "tag": "vless-xhttp", "listen": "127.0.0.1", "port": 10006, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "xhttp", "security": "none", "xhttpSettings": { "path": "/xhttp", "mode": "auto" } }, "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] } },
    { "tag": "vless-grpc", "listen": "127.0.0.1", "port": 10011, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "grpc", "security": "none", "grpcSettings": { "serviceName": "vless-grpc", "multiMode": true } }, "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] } },
    { "tag": "vmess-grpc", "listen": "127.0.0.1", "port": 10012, "protocol": "vmess", "settings": { "clients": [] }, "streamSettings": { "network": "grpc", "security": "none", "grpcSettings": { "serviceName": "vmess-grpc", "multiMode": true } }, "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] } },
    { "tag": "trojan-grpc", "listen": "127.0.0.1", "port": 10013, "protocol": "trojan", "settings": { "clients": [] }, "streamSettings": { "network": "grpc", "security": "none", "grpcSettings": { "serviceName": "trojan-grpc", "multiMode": true } }, "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] } },
    { "tag": "ss-grpc", "listen": "127.0.0.1", "port": 10014, "protocol": "shadowsocks", "settings": { "clients": [], "network": "tcp,udp" }, "streamSettings": { "network": "grpc", "security": "none", "grpcSettings": { "serviceName": "ss-grpc", "multiMode": true } }, "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] } }
  ],
  "outbounds": [
    { "tag": "direct", "protocol": "freedom", "settings": { "domainStrategy": "UseIPv4" } },
    { "tag": "blocked", "protocol": "blackhole", "settings": {} }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      { "type": "field", "protocol": ["bittorrent"], "outboundTag": "blocked" },
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "blocked" }
    ]
  }
}
JSONEOF

    if [[ -s "${XRAY_CONFIG}" ]] && jq -e . "${XRAY_CONFIG}" >/dev/null 2>&1; then
        jq --slurpfile old "${XRAY_CONFIG}" '
            .inbounds |= map(
              . as $new
              | (($old[0].inbounds // []) | map(select(.tag == $new.tag)) | .[0] // {}) as $prev
              | if (($prev.settings.clients // null) | type) == "array"
                then .settings.clients = $prev.settings.clients
                else .
                end
            )
        ' "${XRAY_CONFIG}.new" > "${XRAY_CONFIG}.merged" 2>/dev/null && mv -f "${XRAY_CONFIG}.merged" "${XRAY_CONFIG}.new"
    fi
    mv -f "${XRAY_CONFIG}.new" "${XRAY_CONFIG}"
    chmod 644 "${XRAY_CONFIG}"
    sed -i 's/User=nobody/User=root/g' /etc/systemd/system/xray.service 2>/dev/null
    systemctl daemon-reload

    echo -e "${C_YELLOW}[4/5] Activando SSH-WS interno...${C_NC}"
    bash "${CORE_DIR}/sshws.sh" install >/dev/null 2>&1

    echo -e "${C_YELLOW}[5/5] Configurando HAProxy Multi-Protocolo...${C_NC}"
    cat > "${HAPROXY_CONFIG}" <<HAPROXYEOF
global
    log /dev/log local0
    log /dev/log local1 notice
    user haproxy
    group haproxy
    daemon
    tune.bufsize 32768
    maxconn 10000

defaults
    log global
    mode tcp
    option dontlognull
    timeout connect 5s
    timeout client  24h
    timeout server  24h

frontend multi_front
    bind *:80
    bind *:8080
    bind *:443 ssl crt ${CERT_DIR}/${domain}.pem alpn h2,http/1.1
    mode tcp
    tcp-request inspect-delay 200ms
    tcp-request content accept if { req.ssl_hello_type 1 }

    acl is_h2 ssl_fc_alpn -i h2
    acl is_vless path_beg /vless
    acl is_vmess path_beg /vmess
    acl is_trojan path_beg /trojan
    acl is_ss path_beg /ss
    acl is_xhttp path_beg /xhttp

    use_backend grpc_router if is_h2
    use_backend vless_ws if is_vless
    use_backend vmess_ws if is_vmess
    use_backend trojan_ws if is_trojan
    use_backend ss_ws if is_ss
    use_backend vless_xhttp if is_xhttp
    default_backend ssh_ws

backend grpc_router
    mode tcp
    server loopback_h2 127.0.0.1:10020 send-proxy-v2

frontend grpc_front
    bind 127.0.0.1:10020 accept-proxy proto h2
    mode http
    acl is_vmess_grpc path_beg /vmess-grpc
    acl is_vless_grpc path_beg /vless-grpc
    acl is_trojan_grpc path_beg /trojan-grpc
    acl is_ss_grpc path_beg /ss-grpc

    use_backend vmess_grpc_b if is_vmess_grpc
    use_backend trojan_grpc_b if is_trojan_grpc
    use_backend ss_grpc_b if is_ss_grpc
    default_backend vless_grpc_b

backend vless_grpc_b
    mode http
    server xray_vless_g 127.0.0.1:10011 proto h2 check

backend vmess_grpc_b
    mode http
    server xray_vmess_g 127.0.0.1:10012 proto h2 check

backend trojan_grpc_b
    mode http
    server xray_trojan_g 127.0.0.1:10013 proto h2 check

backend ss_grpc_b
    mode http
    server xray_ss_g 127.0.0.1:10014 proto h2 check

backend ssh_ws
    mode tcp
    server ssh_server 127.0.0.1:10015 check

backend vless_ws
    mode tcp
    server xray_vless 127.0.0.1:10001 check

backend vmess_ws
    mode tcp
    server xray_vmess 127.0.0.1:10002 check

backend trojan_ws
    mode tcp
    server xray_trojan 127.0.0.1:10003 check

backend ss_ws
    mode tcp
    server xray_ss 127.0.0.1:10005 check

backend vless_xhttp
    mode tcp
    server xray_xhttp 127.0.0.1:10006 check
HAPROXYEOF

    systemctl enable --now haproxy xray >/dev/null 2>&1
    systemctl restart haproxy xray

    echo -e "\n${C_GREEN}[✔] ¡MOTOR UNIFICADO HAPROXY + XRAY (WS / MULTI-gRPC / XHTTP / SS) ACTIVO!${C_NC}"
    ss -ltnp | grep -E '(:80 |:443 |:10015 |:10001 |:10005 |:10006 |:10011)'
    echo ""
    read -r -p "Presiona Enter para volver al menú..."
}

case "${1:-install}" in
    install) install_engine ;;
    disable) systemctl disable --now haproxy xray ssh-ws 2>/dev/null ;;
esac
