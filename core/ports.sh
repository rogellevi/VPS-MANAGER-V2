#!/bin/bash
# ==========================================
# MONITOR DINÁMICO DE PUERTOS
# ==========================================
C_GREEN='\033[1;32m'
C_RED='\033[1;31m'
C_CYAN='\033[1;36m'
C_NC='\033[0m'

clear
echo -e "${C_CYAN}================================================${C_NC}"
echo -e " 🔍 ESTADO DE PROTOCOLOS Y PUERTOS EN VIVO"
echo -e "${C_CYAN}================================================${C_NC}"

# Función para extraer el puerto real del proceso en ejecución
check_port() {
    local process_name=$1
    local display_name=$2
    
    # Busca el proceso en netstat y extrae solo el número del puerto
    local port=$(netstat -tulnp 2>/dev/null | grep -w "$process_name" | awk '{print $4}' | awk -F: '{print $NF}' | sort -u | paste -sd "," -)

    if [ -n "$port" ]; then
        printf " %-22s : ${C_GREEN}ACTIVO${C_NC} (Puerto %s)\n" "$display_name" "$port"
    else
        printf " %-22s : ${C_RED}INACTIVO${C_NC}\n" "$display_name"
    fi
}

# Verificación dinámica (Lee los puertos reales del sistema)
check_port "sshd" "SSH Principal"
check_port "dropbear" "Dropbear"
check_port "stunnel4" "SSL / Stunnel Proxy"
check_port "nginx" "Nginx Gateway"
check_port "python.*" "Python WS Proxy"
check_port "bhttp" "BHTTP Proxy"
check_port "hcr-server" "HCR Server"
check_port "openvpn" "OpenVPN"
check_port "badvpn-udpgw" "BadVPN UDPGW"
check_port "udp-custom" "UDP Custom"
check_port "xray" "Xray (V2Ray)"

echo -e "${C_CYAN}================================================${C_NC}"
read -p " Presiona Enter para regresar al menú..."
