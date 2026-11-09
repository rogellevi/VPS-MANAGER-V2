#!/bin/bash
# =========================================================================
# Módulo: Optimizador y Activador TCP BBR + Buffers de Red - Golbert VPS
# =========================================================================
C_RED='\033[1;31m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'
C_CYAN='\033[1;36m'; C_WHITE='\033[1;37m'; C_NC='\033[0m'

clear
echo -e "${C_CYAN}========================================================${C_NC}"
echo -e "${C_GREEN}      ACELERADOR TCP BBR & OPTIMIZADOR DE RED KERNEL    ${C_NC}"
echo -e "${C_CYAN}========================================================${C_NC}"

current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
current_qd=$(sysctl -n net.core.default_qdisc 2>/dev/null)

echo -e " 📊 ${C_WHITE}Estado actual en Kernel :${C_NC} ${C_YELLOW}${current_cc:-Desconocido} (${current_qd:-pfifo_fast})${C_NC}"
echo -e "${C_CYAN}--------------------------------------------------------${C_NC}"

if [[ "$current_cc" == "bbr" ]] && [[ "$current_qd" == "fq" ]]; then
    echo -e "\n${C_GREEN}[✔] ¡TCP BBR y la cola FQ ya se encuentran activos en este VPS!${C_NC}"
    sleep 2
    return 2>/dev/null || exit 0
fi

echo -e "${C_YELLOW}[1/3] Cargando módulo tcp_bbr en el Kernel...${C_NC}"
modprobe tcp_bbr 2>/dev/null
mkdir -p /etc/modules-load.d
if ! grep -q "tcp_bbr" /etc/modules-load.d/modules.conf 2>/dev/null; then
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf 2>/dev/null
fi

echo -e "${C_YELLOW}[2/3] Aplicando parámetros TCP BBR y aceleración de buffers...${C_NC}"
sed -i '/# --- Optimización TCP BBR Golbert VPS ---/d' /etc/sysctl.conf 2>/dev/null
sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf 2>/dev/null
sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf 2>/dev/null
sed -i '/net.ipv4.tcp_fastopen/d' /etc/sysctl.conf 2>/dev/null
sed -i '/net.core.rmem_max/d' /etc/sysctl.conf 2>/dev/null
sed -i '/net.core.wmem_max/d' /etc/sysctl.conf 2>/dev/null

cat << 'EOF' >> /etc/sysctl.conf

# --- Optimización TCP BBR Golbert VPS ---
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.core.rmem_max=67108864
net.core.wmem_max=67108864
EOF

echo -e "${C_YELLOW}[3/3] Recargando configuración del sistema...${C_NC}"
sysctl -p >/dev/null 2>&1
sysctl --system >/dev/null 2>&1

new_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
if [[ "$new_cc" == "bbr" ]]; then
    echo -e "\n${C_GREEN}[✔] ¡TCP BBR y optimización de red activados con éxito!${C_NC}"
    echo -e " 🚀 ${C_WHITE}Algoritmo Activo :${C_NC} ${C_GREEN}$new_cc (fq)${C_NC}"
else
    echo -e "\n${C_RED}[!] No se pudo activar BBR automáticamente (virtualización restringida).${C_NC}"
fi
sleep 2
