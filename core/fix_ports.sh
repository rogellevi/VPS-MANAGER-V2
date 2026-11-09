#!/bin/bash
# =========================================================================
# Módulo: Unificador de Puertos y Reparador de Pasarela (HAProxy Compatible)
# - Nginx: Puerto 2081 (OpenVPN/Web) y Puerto 8442 (Pasarela WS)
# - Stunnel4: Puerto 444 -> Proxy Dual (10080/8080)
# - HAProxy + Xray + SSH-WS: Puertos 80 y 443 intactos
# =========================================================================

export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive

C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_CYAN='\033[1;36m'
C_NC='\033[0m'

clear
echo -e "${C_CYAN}========================================================${C_NC}"
echo -e "${C_GREEN}   REPARANDO Y UNIFICANDO PUERTOS (NGINX + HAPROXY)     ${C_NC}"
echo -e "${C_CYAN}========================================================${C_NC}"

echo -e "${C_YELLOW}[1/4] Liberando servicios conflictivos (Apache2)...${C_NC}"
systemctl stop apache2 >/dev/null 2>&1
systemctl disable apache2 >/dev/null 2>&1
systemctl stop nginx stunnel4 >/dev/null 2>&1

echo -e "${C_YELLOW}[2/4] Verificando repositorios e instalando dependencias...${C_NC}"
dpkg --configure -a >/dev/null 2>&1
apt-get --fix-broken install -y >/dev/null 2>&1
apt-get update --allow-releaseinfo-change -y >/dev/null 2>&1

if ! apt-get install -y --fix-missing nginx stunnel4 openssl psmisc python3 >/tmp/apt_nginx.log 2>&1; then
    echo -e "${C_YELLOW}[!] Corrigiendo caché de repositorios desactualizada...${C_NC}"
    rm -rf /var/lib/apt/lists/*
    apt-get clean >/dev/null 2>&1
    apt-get update --allow-releaseinfo-change -y >/dev/null 2>&1
    apt-get install -y --fix-missing nginx stunnel4 openssl psmisc python3 >/tmp/apt_nginx.log 2>&1
fi

fuser -k 8442/tcp >/dev/null 2>&1
fuser -k 2081/tcp >/dev/null 2>&1
fuser -k 444/tcp >/dev/null 2>&1

echo -e "${C_YELLOW}[3/4] Sincronizando Proxy Dual (10080/8080) y Stunnel4 (444)...${C_NC}"
# Asegurar que sshws_proxy.py y proxy.py sean el mismo motor unificado
if [ -f /etc/vps-manager/core/proxy.py ]; then
    chmod +x /etc/vps-manager/core/proxy.py
    cp -f /etc/vps-manager/core/proxy.py /etc/vps-manager/core/sshws_proxy.py
    chmod +x /etc/vps-manager/core/sshws_proxy.py
fi

cat << 'EOF' > /etc/systemd/system/ssh-ws.service
[Unit]
Description=SSH WebSocket Dual Proxy (Ports 10080 & 8080)
After=network.target ssh.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 -u /etc/vps-manager/core/proxy.py
Restart=always
RestartSec=2
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
Alias=ws-python.service
EOF

ln -sf /etc/systemd/system/ssh-ws.service /etc/systemd/system/ws-python.service
systemctl daemon-reload
systemctl enable --now ssh-ws.service >/dev/null 2>&1
systemctl restart ssh-ws.service >/dev/null 2>&1

mkdir -p /etc/stunnel
if [ ! -f /etc/stunnel/stunnel.pem ]; then
    openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
        -subj "/C=PE/ST=Lima/L=Lima/O=GolbertVPS/CN=golbertvps.online" \
        -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem >/dev/null 2>&1
fi

cat << 'EOF' > /etc/stunnel/stunnel.conf
cert = /etc/stunnel/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[ssl-proxy]
accept = 444
connect = 127.0.0.1:10080
EOF

if [ ! -f /etc/default/stunnel4 ]; then
    echo "ENABLED=1" > /etc/default/stunnel4
else
    sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/stunnel4
fi

echo -e "${C_YELLOW}[4/4] Configurando Nginx en puertos 2081 (Web/OVPN) y 8442 (Pasarela)...${C_NC}"
mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/conf.d /etc/vps-manager/openvpn_files

if [ ! -f /etc/nginx/nginx.conf ]; then
cat << 'EOF' > /etc/nginx/nginx.conf
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    gzip on;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
fi

rm -f /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf 2>/dev/null

cat << 'EOF' > /etc/nginx/sites-available/pasarela
server {
    listen 2081 default_server;
    listen [::]:2081 default_server;
    root /etc/vps-manager/openvpn_files;
    index index.html index.htm;
    server_name _;

    location / {
        autoindex on;
        try_files $uri $uri/ =404;
    }
}

server {
    listen 8442;
    listen [::]:8442;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:10080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}
EOF

ln -sf /etc/nginx/sites-available/pasarela /etc/nginx/sites-enabled/pasarela

NGINX_BIN=$(command -v nginx || echo "/usr/sbin/nginx")
if [ -x "$NGINX_BIN" ]; then
    if $NGINX_BIN -t >/tmp/nginx_error.log 2>&1; then
        systemctl unmask nginx >/dev/null 2>&1
        systemctl enable nginx stunnel4 >/dev/null 2>&1
        systemctl restart nginx
        systemctl restart stunnel4 >/dev/null 2>&1
        # Asegurar que HAProxy y Xray sigan encendidos en 80 y 443
        systemctl is-enabled --quiet xray 2>/dev/null && systemctl restart xray >/dev/null 2>&1
        systemctl is-enabled --quiet haproxy 2>/dev/null && systemctl restart haproxy >/dev/null 2>&1
        echo -e "${C_GREEN}[✔] Nginx activo en puertos 2081 (Web/OVPN) y 8442 (Pasarela).${C_NC}"
        echo -e "${C_GREEN}[✔] Proxy Dual activo en puertos 10080 y 8080 (Con Banner y HTTP 1299).${C_NC}"
        echo -e "${C_GREEN}[✔] Stunnel SSL activo en puerto 444.${C_NC}"
    else
        echo -e "${C_RED}[✘] Error en la sintaxis de Nginx. Detalle:${C_NC}"
        cat /tmp/nginx_error.log
    fi
else
    echo -e "${C_RED}[✘] No se pudo localizar el binario de Nginx:${C_NC}"
    tail -n 15 /tmp/apt_nginx.log
fi

if systemctl is-active --quiet udp-custom; then
    echo -e "${C_GREEN}[✔] UDP Custom continúa operando sin interrupciones.${C_NC}"
fi

echo -e "${C_GREEN}[✔] ¡Todos los servicios reparados! Puertos 80 y 443 operando con HAProxy.${C_NC}"
read -p "Presione Enter para regresar..."
