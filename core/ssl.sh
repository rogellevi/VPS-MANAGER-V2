#!/bin/bash
# ==========================================
# Instalador SSL/TLS - Golbert VPS V5.0 LTS
# ==========================================
C_ORANGE='\033[38;5;214m'; C_BLUE='\033[1;34m'; C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_RED='\033[1;31m'; C_NC='\033[0m'

DEFAULT_PORT=444

clear
echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
echo -e "               ${C_BLUE}INSTALACIÓN DE SSL/TLS STUNNEL${C_NC}"
echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
echo -e "\n${C_ORANGE}Instalando paquetes SSL y generando certificados...${C_NC}"

apt-get install stunnel4 openssl -y > /dev/null 2>&1
systemctl stop stunnel4 > /dev/null 2>&1

openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -subj "/C=PE/ST=Lima/L=Lima/O=GolbertVPS/CN=golbertvps.net.pe" -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem > /dev/null 2>&1

sleep 1.5 
echo -e "${C_CYAN}[OK] Paquetes y certificados instalados${C_NC}\n"

while true; do
    read -p "$(echo -e "${C_ORANGE}Puerto de escucha (--port) [Default $DEFAULT_PORT]: ${C_NC}")" INPUT_PORT
    FINAL_PORT=${INPUT_PORT:-$DEFAULT_PORT}

    if ! [[ "$FINAL_PORT" =~ ^[0-9]+$ ]]; then
        echo -e " ${C_RED}[!] Error: Debes ingresar un número válido.${C_NC}\n"
        continue
    fi
    if netstat -tuln | grep -qE ":$FINAL_PORT\b"; then
        echo -e " ${C_RED}[!] Error: El puerto $FINAL_PORT ya está en uso. Elige otro.${C_NC}\n"
    else
        break
    fi
done

echo -e "\n${C_GREEN}[OK] Configurando Stunnel4 en el puerto $FINAL_PORT...${C_NC}"

cat << EOF > /etc/stunnel/stunnel.conf
cert = /etc/stunnel/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[stunnel]
accept = $FINAL_PORT
connect = 127.0.0.1:22
EOF

sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/stunnel4
systemctl daemon-reload
systemctl enable stunnel4 >/dev/null 2>&1
systemctl restart stunnel4

echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
echo -e " ${C_GREEN}✅ INSTALACIÓN COMPLETADA EXITOSAMENTE${C_NC}"
echo -e " ${C_CYAN}▶️ Protocolo corriendo en el puerto : $FINAL_PORT${C_NC}"
echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
read -p " Presiona Enter para volver al menú..."
