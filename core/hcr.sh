#!/bin/bash
# ==========================================
# Gestor HCR Plain - Instalación y Desinstalación
# ==========================================
C_ORANGE='\033[38;5;214m'; C_BLUE='\033[1;34m'; C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_RED='\033[1;31m'; C_NC='\033[0m'
DEFAULT_PORT=8880
GH_TOKEN="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"

clear
echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
echo -e "               ${C_BLUE}GESTOR DE HCR PLAIN${C_NC}"
echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
echo -e " ${C_CYAN}1.${C_NC} Instalar / Cambiar Puerto HCR"
echo -e " ${C_RED}2.${C_NC} Desinstalar y Liberar Puerto"
echo -e " ${C_CYAN}0.${C_NC} Volver al Menú Principal"
echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
read -p " Selecciona una opción: " opcion

case $opcion in
    2)
        echo -e "\n${C_ORANGE}Desinstalando HCR y liberando puerto...${C_NC}"
        systemctl stop hcr > /dev/null 2>&1
        systemctl disable hcr > /dev/null 2>&1
        rm -f /etc/systemd/system/hcr.service
        rm -rf /etc/vps-manager/hcr
        systemctl daemon-reload
        echo -e " ${C_GREEN}✅ HCR desinstalado correctamente.${C_NC}"
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

mkdir -p /etc/vps-manager/hcr
systemctl stop hcr > /dev/null 2>&1

wget --header="Authorization: token $GH_TOKEN" -qO /etc/vps-manager/hcr/hcr-server "https://raw.githubusercontent.com/golbert19/vps-script/main/core/hcr-server"
chmod +x /etc/vps-manager/hcr/hcr-server

if grep -q "404: Not Found" /etc/vps-manager/hcr/hcr-server || [ ! -s /etc/vps-manager/hcr/hcr-server ]; then
    echo -e "\n${C_RED}[!] ERROR CRÍTICO: El archivo 'hcr-server' no fue encontrado en GitHub.${C_NC}"
    rm -f /etc/vps-manager/hcr/hcr-server
    read -p " Presiona Enter para cancelar la instalación..."
    exit 1
fi

while true; do
    read -p "$(echo -e "${C_ORANGE}Puerto de escucha [Default $DEFAULT_PORT]: ${C_NC}")" INPUT_PORT
    FINAL_PORT=${INPUT_PORT:-$DEFAULT_PORT}
    if ! [[ "$FINAL_PORT" =~ ^[0-9]+$ ]]; then echo -e " ${C_RED}[!] Número inválido.${C_NC}"; continue; fi
    if netstat -tuln | grep -qE ":$FINAL_PORT\b"; then echo -e " ${C_RED}[!] Puerto en uso.${C_NC}"; else break; fi
done

cat << EOF > /etc/systemd/system/hcr.service
[Unit]
Description=HCR Plain Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/vps-manager/hcr
ExecStart=/etc/vps-manager/hcr/hcr-server --listen :$FINAL_PORT --target 127.0.0.1:22 --transport plain --max-download-frame 6144 --download-poll-timeout 8s
LimitNOFILE=65535
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hcr >/dev/null 2>&1
systemctl restart hcr
sleep 2

if systemctl is-active --quiet hcr; then
    echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
    echo -e " ${C_GREEN}✅ HCR operando en el puerto $FINAL_PORT con éxito${C_NC}"
    echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
else
    echo -e "\n${C_RED}[!] Error: El servicio HCR colapsó.${C_NC}"
    journalctl -u hcr -n 10 --no-pager
fi
read -p " Presiona Enter para volver..."
