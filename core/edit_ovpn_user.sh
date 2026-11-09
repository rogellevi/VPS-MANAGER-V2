#!/bin/bash
# ==========================================
# Instalador Real de OpenVPN + Certificados
# ==========================================
C_RED='\033[1;31m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_CYAN='\033[1;36m'; C_NC='\033[0m'

instalar_ovpn() {
    clear
    echo -e "${C_YELLOW}[+] Instalando y configurando OpenVPN...${C_NC}"
    apt update -y && apt install -y openvpn iptables python3 curl openssl >/dev/null 2>&1

    PAM_PLUGIN=$(find /usr/lib -type f -name "openvpn-plugin-auth-pam.so" | head -n 1)

    cd /etc/openvpn
    if [ ! -f "ca.crt" ]; then
        openssl req -nodes -new -x509 -keyout ca.key -out ca.crt -days 3650 -subj "/CN=GolbertVPN" >/dev/null 2>&1
        openssl req -nodes -new -keyout server.key -out server.csr -subj "/CN=GolbertServer" >/dev/null 2>&1
        openssl x509 -req -in server.csr -out server.crt -CA ca.crt -CAkey ca.key -CAcreateserial -days 3650 >/dev/null 2>&1
        openssl dhparam -out dh.pem 2048 >/dev/null 2>&1
    fi

    cat <<EOF > /etc/openvpn/server-tcp.conf
port 1194
proto tcp
dev tun
ca /etc/openvpn/ca.crt
cert /etc/openvpn/server.crt
key /etc/openvpn/server.key
dh /etc/openvpn/dh.pem
plugin $PAM_PLUGIN login
verify-client-cert none
username-as-common-name
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 1.1.1.1"
keepalive 10 120
cipher AES-256-CBC
persist-key
persist-tun
verb 3
EOF

    echo 1 > /proc/sys/net/ipv4/ip_forward
    sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j MASQUERADE
    iptables-save > /etc/iptables.up.rules

    systemctl restart openvpn@server-tcp
    systemctl enable openvpn@server-tcp >/dev/null 2>&1

    IP_ACTUAL=$(curl -s ipv4.icanhazip.com)
    # CORRECCIÓN SINTAXIS (||) PARA EVITAR ERROR CAT
    DOM=$( [ -f /etc/vps-manager/dominio ] && cat /etc/vps-manager/dominio || echo "$IP_ACTUAL" )
    
    OVPN_DIR="/etc/vps-manager/openvpn_files"
    mkdir -p "$OVPN_DIR"
    CA_CERT=$(cat /etc/openvpn/ca.crt)

    cat <<EOF > "$OVPN_DIR/cliente-tcp-1194.ovpn"
client
dev tun
proto tcp
remote $DOM 1194
resolv-retry infinite
nobind
persist-key
persist-tun
auth-user-pass
cipher AES-256-CBC
verb 3
<ca>
$CA_CERT
</ca>
EOF

    # CORRECCIÓN RUTAS: Enviar copia a /root para que el script user.sh lo detecte
    cp -f "$OVPN_DIR/cliente-tcp-1194.ovpn" "/root/cliente-tcp-1194.ovpn"

    cat << 'EOF' > /etc/vps-manager/server_web.py
import http.server
import socketserver
PORT = 2081
DIRECTORY = "/etc/vps-manager/openvpn_files"
class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)
with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
    httpd.serve_forever()
EOF

    cat << 'EOF' > /etc/systemd/system/openvpn-web.service
[Unit]
Description=Web OpenVPN
After=network.target
[Service]
ExecStart=/usr/bin/python3 /etc/vps-manager/server_web.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable openvpn-web >/dev/null 2>&1
    systemctl restart openvpn-web

    echo -e "\n${C_GREEN}[✔] Servidor OpenVPN y Certificados configurados exitosamente.${C_NC}"
    read -p "Presione Enter para regresar..."
}

desinstalar_ovpn() {
    clear
    echo -e "${C_YELLOW}[+] Desinstalando OpenVPN Server...${C_NC}"
    systemctl stop openvpn@server-tcp >/dev/null 2>&1
    systemctl disable openvpn@server-tcp >/dev/null 2>&1
    systemctl stop openvpn-web >/dev/null 2>&1
    systemctl disable openvpn-web >/dev/null 2>&1
    
    apt-get purge -y openvpn >/dev/null 2>&1
    rm -rf /etc/openvpn
    rm -rf /etc/vps-manager/openvpn_files
    rm -f /etc/systemd/system/openvpn-web.service
    rm -f /etc/vps-manager/server_web.py
    rm -f /root/cliente-tcp-1194.ovpn
    
    systemctl daemon-reload
    echo -e "\n${C_GREEN}[✔] OpenVPN eliminado por completo del sistema.${C_NC}"
    read -p "Presione Enter para regresar..."
}

clear
echo -e "${C_CYAN}================================================${C_NC}"
echo -e " 🛡️ GESTIÓN DE OPENVPN SERVER"
echo -e "${C_CYAN}================================================${C_NC}"
echo -e " 1. 🟢 Instalar OpenVPN"
echo -e " 2. 🔴 Desinstalar OpenVPN"
echo -e " 0. 🚪 Volver al Menú"
echo -e "${C_CYAN}================================================${C_NC}"
read -p " Opción: " opc

case $opc in
    1) instalar_ovpn ;;
    2) desinstalar_ovpn ;;
    0) exit 0 ;;
    *) echo -e "${C_RED}Opción inválida.${C_NC}"; sleep 1 ;;
esac
