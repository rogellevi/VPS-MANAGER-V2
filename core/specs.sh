#!/bin/bash
# ==========================================
# Módulo: Especificaciones Avanzadas del Sistema
# ==========================================
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_NC='\033[0m'

clear
echo -e "${C_CYAN}================================================${C_NC}"
echo -e " 💻 ${C_YELLOW}ESPECIFICACIONES AVANZADAS - GOLBERT VPS${C_NC}"
echo -e "${C_CYAN}================================================${C_NC}"

# Obtener geolocalización e IP pública mediante API rápida
geo_data=$(curl -sS ipinfo.io 2>/dev/null)
ip_pub=$(echo "$geo_data" | grep -i '"ip"' | cut -d'"' -f4)
ciudad=$(echo "$geo_data" | grep -i '"city"' | cut -d'"' -f4)
region=$(echo "$geo_data" | grep -i '"region"' | cut -d'"' -f4)
pais=$(echo "$geo_data" | grep -i '"country"' | cut -d'"' -f4)
org=$(echo "$geo_data" | grep -i '"org"' | cut -d'"' -f4)

# Datos del sistema
os_name=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
kernel_ver=$(uname -r)
arch=$(uname -m)
cpu_model=$(grep 'model name' /proc/cpuinfo | head -n1 | cut -d':' -f2 | xargs)
cpu_cores=$(nproc)
uptime_sys=$(uptime -p | sed 's/up //')
load_avg=$(awk '{print $1", "$2", "$3}' /proc/loadavg)

# Memoria y Disco
ram_info=$(free -h | awk 'NR==2 {print "Total: " $2 " | Usada: " $3 " | Libre: " $4}')
disk_info=$(df -h / | awk 'NR==2 {print "Total: " $2 " | Usado: " $3 " | Libre: " $4 " (" $5 " usado)"}')

echo -e " 🖥️ OS Principal  : $os_name"
echo -e " ⚙️ Kernel Linux  : $kernel_ver ($arch)"
echo -e " ⏱️ Uptime        : $uptime_sys"
echo -e " 📊 Load Average  : $load_avg"
echo -e "${C_CYAN}------------------------------------------------${C_NC}"
echo -e " 🌐 IP Pública    : ${ip_pub:-No disponible}"
echo -e " 🏢 Proveedor/AS  : ${org:-Desconocido}"
echo -e " 📍 Ubicación     : ${ciudad:-N/D}, ${region:-N/D} (${pais:-N/D})"
echo -e "${C_CYAN}------------------------------------------------${C_NC}"
echo -e " 🧠 Procesador    : $cpu_model"
echo -e " 🚀 Núcleos CPU   : $cpu_cores Cores"
echo -e " 💾 Memoria RAM   : $ram_info"
echo -e " 💽 Espacio Disco : $disk_info"
echo -e "${C_CYAN}================================================${C_NC}"
read -p "Presiona Enter para regresar al menú..."
