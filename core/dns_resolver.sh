#!/bin/bash
# ==========================================
# Gestor de DNS (Cloudflare, Google, AdGuard)
# ==========================================
C_CYAN='\033[1;36m'; C_ORANGE='\033[38;5;214m'; C_GREEN='\033[1;32m'; C_RED='\033[1;31m'; C_NC='\033[0m'

clear
echo -e "${C_CYAN}================================================${C_NC}"
echo -e " 🌐 ${C_ORANGE}GESTOR DE RESOLUCIÓN DNS${C_NC}"
echo -e "${C_CYAN}================================================${C_NC}"
echo -e " ${C_CYAN}1.${C_NC} Cloudflare DNS (1.1.1.1) - Alta Velocidad"
echo -e " ${C_CYAN}2.${C_NC} Google DNS (8.8.8.8) - Máxima Estabilidad"
echo -e " ${C_CYAN}3.${C_NC} AdGuard DNS (94.140.14.14) - Bloqueo de Anuncios"
echo -e " ${C_RED}4.${C_NC} Restaurar DNS por Defecto del Sistema"
echo -e " ${C_CYAN}0.${C_NC} Volver al Menú Principal"
echo -e "${C_CYAN}================================================${C_NC}"
read -p " Selecciona una opción: " opc_dns

aplicar_dns() {
    local dns1=$1
    local dns2=$2
    local name=$3
    
    echo -e "\n${C_ORANGE}Configurando DNS de $name...${C_NC}"
    
    # Respaldo del archivo original si no existe
    [ ! -f /etc/systemd/resolved.conf.bak ] && cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.bak
    
    # Limpieza de reglas anteriores
    sed -i '/^#DNS=/d' /etc/systemd/resolved.conf
    sed -i '/^DNS=/d' /etc/systemd/resolved.conf
    
    if [ "$name" == "Defecto" ]; then
        echo "#DNS=" >> /etc/systemd/resolved.conf
    else
        echo "DNS=$dns1 $dns2" >> /etc/systemd/resolved.conf
    fi
    
    systemctl restart systemd-resolved
    
    # Forzar la lectura local de systemd-resolved
    rm -f /etc/resolv.conf
    ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
    
    echo -e " ${C_GREEN}✅ Resolución DNS de la VPS actualizada a $name.${C_NC}"
    read -p " Presiona Enter para volver..."
}

case $opc_dns in
    1) aplicar_dns "1.1.1.1" "1.0.0.1" "Cloudflare" ;;
    2) aplicar_dns "8.8.8.8" "8.8.4.4" "Google" ;;
    3) aplicar_dns "94.140.14.14" "94.140.15.15" "AdGuard (Bloqueo de Anuncios)" ;;
    4) aplicar_dns "" "" "Defecto" ;;
    0) exit 0 ;;
    *) echo -e " ${C_RED}[!] Opción inválida.${C_NC}"; sleep 2; exit 1 ;;
esac
