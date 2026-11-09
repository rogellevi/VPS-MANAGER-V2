#!/bin/bash
# ==========================================
# Módulo: ZiVPN UDP (Repositorio Privado)
# ==========================================
C_RED='\033[1;31m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_CYAN='\033[1;36m'; C_NC='\033[0m'
GH_TOKEN="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"

instalar_zivpn() {
    clear
    echo -e "${C_YELLOW}[+] Conectando con el repositorio oficial (Modo Privado)...${C_NC}"
    apt-get update -y >/dev/null 2>&1
    apt-get install -y wget curl sudo >/dev/null 2>&1
    
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        wget --header="Authorization: token $GH_TOKEN" -qO /tmp/zi.sh https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/zi.sh
        if [ -s /tmp/zi.sh ]; then
            chmod +x /tmp/zi.sh
            cd /tmp || exit
            sudo ./zi.sh
        else
            echo -e "${C_RED}[✘] Error al descargar el script público.${C_NC}"
        fi
    else
        bash <(curl -fsSL -H "Authorization: token $GH_TOKEN" https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/zi2.sh)
    fi
    
    echo -e "\n${C_GREEN}[✔] Proceso de repositorio finalizado.${C_NC}"
    read -p "Presione Enter para regresar..."
}

desinstalar_zivpn() {
    clear
    echo -e "${C_YELLOW}[+] Descargando desinstalador oficial de ZiVPN...${C_NC}"
    wget --header="Authorization: token $GH_TOKEN" -qO /tmp/ziun.sh https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/uninstall.sh
    if [ -s /tmp/ziun.sh ]; then
        chmod +x /tmp/ziun.sh
        cd /tmp || exit
        sudo ./ziun.sh
    else
        echo -e "${C_RED}[✘] Error al descargar el desinstalador.${C_NC}"
    fi
    
    echo -e "\n${C_GREEN}[✔] ZiVPN eliminado mediante script oficial.${C_NC}"
    read -p "Presione Enter para regresar..."
}

clear
echo -e "${C_CYAN}================================================${C_NC}"
echo -e " 🌐 GESTIÓN DE ZIVPN UDP (REPOSITORIO PRIVADO)"
echo -e "${C_CYAN}================================================${C_NC}"
echo -e " 1. 🟢 Instalar ZiVPN (Script Oficial)"
echo -e " 2. 🔴 Desinstalar ZiVPN"
echo -e " 0. 🚪 Volver al Menú"
echo -e "${C_CYAN}================================================${C_NC}"
read -p " Opción: " opc

case $opc in
    1) instalar_zivpn ;;
    2) desinstalar_zivpn ;;
    0) exit 0 ;;
    *) echo -e "${C_RED}Opción inválida.${C_NC}"; sleep 1 ;;
esac
