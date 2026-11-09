#!/bin/bash
# ==========================================
# Gestor BHTTP Proxy - Instalación y Desinstalación
# ==========================================
C_ORANGE='\033[38;5;214m'; C_BLUE='\033[1;34m'; C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_RED='\033[1;31m'; C_NC='\033[0m'
DEFAULT_PORT=8180
GH_TOKEN="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"

clear
echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
echo -e "               ${C_BLUE}GESTOR DE BHTTP PROXY${C_NC}"
echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
echo -e " ${C_CYAN}1.${C_NC} Instalar / Cambiar Puerto BHTTP"
echo -e " ${C_RED}2.${C_NC} Desinstalar y Liberar Puerto"
echo -e " ${C_CYAN}0.${C_NC} Volver al Menú Principal"
echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
read -p " Selecciona una opción: " opcion

case $opcion in
    2)
        echo -e "\n${C_ORANGE}Desinstalando BHTTP y liberando puerto...${C_NC}"
        systemctl stop bhttp > /dev/null 2>&1
        systemctl disable bhttp > /dev/null 2>&1
        rm -f /etc/systemd/system/bhttp.service
        rm -rf /etc/vps-manager/bhttp
        systemctl daemon-reload
        echo -e " ${C_GREEN}✅ BHTTP desinstalado correctamente.${C_NC}"
        read -p " Presiona Enter para volver..."
        exit 0
        ;;
    0)
        exit 0
        ;;
    1)
        echo -e "\n${C_CYAN}Iniciando instalación...${C_NC}"
        ;;
    *)
        echo -e " ${C_RED}[!] Opción inválida.${C_NC}"
        sleep 2
        exit 1
        ;;
esac

mkdir -p /etc/vps-manager/bhttp
systemctl stop bhttp > /dev/null 2>&1

apt-get install -y python3-pam > /dev/null 2>&1
wget --header="Authorization: token $GH_TOKEN" -qO /etc/vps-manager/bhttp/BHTTP.py "https://raw.githubusercontent.com/golbert19/vps-script/main/core/BHTTP.py"

while true; do
    read -p "$(echo -e "${C_ORANGE}Puerto de escucha [Default $DEFAULT_PORT]: ${C_NC}")" INPUT_PORT
    FINAL_PORT=${INPUT_PORT:-$DEFAULT_PORT}
    if ! [[ "$FINAL_PORT" =~ ^[0-9]+$ ]]; then echo -e " ${C_RED}[!] Número inválido.${C_NC}"; continue; fi
    if netstat -tuln | grep -qE ":$FINAL_PORT\b"; then echo -e " ${C_RED}[!] Puerto en uso.${C_NC}"; else break; fi
done

echo -e "\n${C_GREEN}[OK] Configurando puerto $FINAL_PORT...${C_NC}"

sed -i "s/\"port\": 80/\"port\": $FINAL_PORT/g" /etc/vps-manager/bhttp/BHTTP.py
sed -i 's/"ssl": True/"ssl": False/g' /etc/vps-manager/bhttp/BHTTP.py

cat << EOF > /etc/systemd/system/bhttp.service
[Unit]
Description=BHTTP Proxy Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/vps-manager/bhttp
ExecStart=/usr/bin/python3 /etc/vps-manager/bhttp/BHTTP.py
LimitNOFILE=65535
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable bhttp >/dev/null 2>&1
systemctl restart bhttp
sleep 2

if systemctl is-active --quiet bhttp; then
    echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
    echo -e " ${C_GREEN}✅ BHTTP operando en el puerto $FINAL_PORT con éxito${C_NC}"
    echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
else
    echo -e "\n${C_RED}[!] Error crítico: El servicio BHTTP colapsó al iniciar.${C_NC}"
    journalctl -u bhttp -n 10 --no-pager
fi
read -p " Presiona Enter para volver..."
