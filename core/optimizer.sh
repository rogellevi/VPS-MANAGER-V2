#!/bin/bash
# ==========================================
# Auto-Optimizador VPS - RAM, Swap, SSH & Cron
# ==========================================
C_CYAN='\033[1;36m'; C_ORANGE='\033[38;5;214m'; C_GREEN='\033[1;32m'; C_RED='\033[1;31m'; C_NC='\033[0m'

clear
echo -e "${C_CYAN}================================================${C_NC}"
echo -e " 🚀 ${C_ORANGE}OPTIMIZADOR Y ESTABILIZADOR DE SISTEMA${C_NC}"
echo -e "${C_CYAN}================================================${C_NC}"
echo -e " ${C_CYAN}1.${C_NC} 🛡️ obligatorio para vps de 1 Ram(Anti-Freeze)"
echo -e " ${C_CYAN}2.${C_NC} 🧹 Ejecutar Limpieza de RAM y Logs AHORA"
echo -e " ${C_CYAN}3.${C_NC} ⏱️ Programar Limpieza Automática: Cada 12 Horas"
echo -e " ${C_CYAN}4.${C_NC} 📆 Programar Limpieza Automática: Diario (00:00)"
echo -e " ${C_RED}5.${C_NC} ❌ Desactivar Limpieza Automática"
echo -e " ${C_CYAN}0.${C_NC} Volver al Menú Principal"
echo -e "${C_CYAN}================================================${C_NC}"
read -p " Selecciona una opción: " opc_opt

crear_script_cron() {
    cat << 'EOF' > /etc/vps-manager/core/cron_clean.sh
#!/bin/bash
sync; echo 3 > /proc/sys/vm/drop_caches
journalctl --vacuum-time=1d > /dev/null 2>&1
apt-get clean > /dev/null 2>&1
rm -rf /tmp/*
EOF
    chmod +x /etc/vps-manager/core/cron_clean.sh
}

blindar_sistema() {
    echo -e "\n${C_ORANGE}[1/3] Desbloqueando límites de sesiones SSH...${C_NC}"
    sed -i '/^#*MaxStartups/d; /^#*MaxSessions/d; /^#*UseDNS/d; /^#*LoginGraceTime/d; /^#*ClientAliveInterval/d; /^#*ClientAliveCountMax/d' /etc/ssh/sshd_config
    cat << 'EOF' >> /etc/ssh/sshd_config
MaxStartups 1000:30:2000
MaxSessions 1000
UseDNS no
LoginGraceTime 20
ClientAliveInterval 60
ClientAliveCountMax 3
EOF

    mkdir -p /etc/systemd/system/ssh.service.d
    cat << 'EOF' > /etc/systemd/system/ssh.service.d/override.conf
[Service]
LimitNOFILE=65535
LimitNPROC=65535
TasksMax=infinity
Restart=always
RestartSec=2
EOF
    systemctl daemon-reload
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null

    echo -e "${C_ORANGE}[2/3] Optimizando colas TCP del Kernel...${C_NC}"
    cat << 'EOF' > /etc/sysctl.d/99-vps-stability.conf
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
vm.swappiness = 10
EOF
    sysctl --system > /dev/null 2>&1

    echo -e "${C_ORANGE}[3/3] Verificando Memoria Virtual (SWAP 2GB)...${C_NC}"
    if [ ! -f /swapfile ]; then
        fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 >/dev/null 2>&1
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null 2>&1
        swapon /swapfile >/dev/null 2>&1
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    echo -e "\n ${C_GREEN}✅ Sistema blindado: SSH sin bloqueos y 2GB Swap activos.${C_NC}"
    read -p " Presiona Enter para volver..."
}

case $opc_opt in
    1) blindar_sistema ;;
    2)
        echo -e "\n${C_ORANGE}Iniciando limpieza profunda de RAM, caché y logs...${C_NC}"
        crear_script_cron
        bash /etc/vps-manager/core/cron_clean.sh
        echo -e " ${C_GREEN}✅ VPS Optimizada correctamente.${C_NC}"
        read -p " Presiona Enter para volver..."
        ;;
    3)
        crear_script_cron
        crontab -l 2>/dev/null | grep -v "/etc/vps-manager/core/cron_clean.sh" | crontab -
        (crontab -l 2>/dev/null; echo "0 */12 * * * /etc/vps-manager/core/cron_clean.sh") | crontab -
        echo -e "\n ${C_GREEN}✅ Optimización programada cada 12 horas.${C_NC}"
        read -p " Presiona Enter para volver..."
        ;;
    4)
        crear_script_cron
        crontab -l 2>/dev/null | grep -v "/etc/vps-manager/core/cron_clean.sh" | crontab -
        (crontab -l 2>/dev/null; echo "0 0 * * * /etc/vps-manager/core/cron_clean.sh") | crontab -
        echo -e "\n ${C_GREEN}✅ Optimización programada todos los días a la medianoche.${C_NC}"
        read -p " Presiona Enter para volver..."
        ;;
    5)
        crontab -l 2>/dev/null | grep -v "/etc/vps-manager/core/cron_clean.sh" | crontab -
        rm -f /etc/vps-manager/core/cron_clean.sh
        echo -e "\n ${C_RED}❌ Optimización automática desactivada.${C_NC}"
        read -p " Presiona Enter para volver..."
        ;;
    0) exit 0 ;;
    *) echo -e " ${C_RED}[!] Opción inválida.${C_NC}"; sleep 2 ;;
esac
