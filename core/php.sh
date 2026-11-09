#!/bin/bash
# ==========================================
# Instalador PHP 8.5.12 - Golbert VPS
# ==========================================
C_ORANGE='\033[38;5;214m'; C_BLUE='\033[1;34m'; C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_RED='\033[1;31m'; C_NC='\033[0m'

clear
echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
echo -e "               ${C_BLUE}INSTALACIÓN DE PHP 8.5.12${C_NC}"
echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
echo -e "\n${C_CYAN}Ejecutando instalador oficial de PHP 8.5.12...${C_NC}"

# Ejecutar el instalador remoto con tu configuración exacta
curl -sSL "https://raw.githubusercontent.com/golbert19/php-8.5.12-vps/main/install.sh?t=$(date +%s)" | sed '59s/[()]//g' | bash

echo -e "\n${C_ORANGE}------------------------------------------------------${C_NC}"
if command -v php > /dev/null 2>&1; then
    php_version=$(php -v | head -n 1)
    echo -e " ${C_GREEN}✅ Versión actual instalada:${C_NC}"
    echo -e " ${C_CYAN}$php_version${C_NC}"
else
    echo -e " ${C_RED}[!] No se pudo verificar la versión de PHP.${C_NC}"
fi
echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
read -p " Presiona Enter para volver al menú..."
