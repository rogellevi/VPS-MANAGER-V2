#!/bin/bash
# ==========================================
# Escudo Anti-DDoS & Firewall Manager - Golbert VPS
# Soporta ejecución silenciosa (--auto) y panel interactivo
# ==========================================
C_CYAN='\033[1;36m'; C_ORANGE='\033[38;5;214m'; C_GREEN='\033[1;32m'; C_RED='\033[1;31m'; C_WHITE='\033[1;37m'; C_NC='\033[0m'

aplicar_antiddos() {
    # 1. Blindaje de Kernel contra SYN Flood, Spoofing y conexiones fantasma
    cat << 'EOF' > /etc/sysctl.d/98-antiddos.conf
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.netfilter.nf_conntrack_max = 524288
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30
EOF
    modprobe nf_conntrack >/dev/null 2>&1
    sysctl --system >/dev/null 2>&1

    # 2. Crear cadena dedicada en Mangle para limpiar intentos previos sin borrar reglas de SlowDNS
    iptables -t mangle -N GOLBERT_DDOS 2>/dev/null
    iptables -t mangle -F GOLBERT_DDOS 2>/dev/null
    iptables -t mangle -D PREROUTING -j GOLBERT_DDOS 2>/dev/null
    iptables -t mangle -I PREROUTING 1 -j GOLBERT_DDOS

    # Permitir todo el tráfico interno de los proxys locales (127.0.0.1)
    iptables -t mangle -A GOLBERT_DDOS -i lo -j RETURN

    # Descartar paquetes corruptos o inválidos
    iptables -t mangle -A GOLBERT_DDOS -m conntrack --ctstate INVALID -j DROP

    # Descartar paquetes TCP nuevos que no inicien con SYN (Ataques de saturación)
    iptables -t mangle -A GOLBERT_DDOS -p tcp ! --syn -m conntrack --ctstate NEW -j DROP

    # Descartar paquetes con banderas TCP maliciosas (XMAS, NULL, SYN+FIN, SYN+RST)
    iptables -t mangle -A GOLBERT_DDOS -p tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE -j DROP
    iptables -t mangle -A GOLBERT_DDOS -p tcp --tcp-flags FIN,SYN FIN,SYN -j DROP
    iptables -t mangle -A GOLBERT_DDOS -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
    iptables -t mangle -A GOLBERT_DDOS -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
    iptables -t mangle -A GOLBERT_DDOS -p tcp --tcp-flags FIN,ACK FIN -j DROP
    iptables -t mangle -A GOLBERT_DDOS -p tcp --tcp-flags ACK,URG URG -j DROP
    iptables -t mangle -A GOLBERT_DDOS -p tcp --tcp-flags ALL ALL -j DROP

    # Bloquear fragmentos IP sospechosos
    iptables -t mangle -A GOLBERT_DDOS -f -j DROP

    # 3. Cadena en Filter para limitar ráfagas de inundación (Flood)
    iptables -N GOLBERT_FILTER 2>/dev/null
    iptables -F GOLBERT_FILTER 2>/dev/null
    iptables -D INPUT -j GOLBERT_FILTER 2>/dev/null
    iptables -I INPUT 1 -j GOLBERT_FILTER

    iptables -A GOLBERT_FILTER -i lo -j RETURN

    # Limitar Ping Flood (ICMP)
    iptables -A GOLBERT_FILTER -p icmp --icmp-type echo-request -m limit --limit 3/s --limit-burst 6 -j RETURN
    iptables -A GOLBERT_FILTER -p icmp --icmp-type echo-request -j DROP

    # Escudo Anti-Botnet en puerto 22 externo (Frena ataques de fuerza bruta sin afectar proxys locales)
    iptables -A GOLBERT_FILTER -p tcp --dport 22 -m conntrack --ctstate NEW -m hashlimit \
        --hashlimit-above 15/min --hashlimit-burst 20 --hashlimit-mode srcip \
        --hashlimit-name ssh_brute --hashlimit-htable-expire 60000 -j DROP

    # Mitigación SYN Flood por IP (Tolerante con CGNAT móvil: hasta 150 conexiones nuevas/seg por IP)
    iptables -A GOLBERT_FILTER -p tcp --syn -m conntrack --ctstate NEW -m hashlimit \
        --hashlimit-above 150/sec --hashlimit-burst 250 --hashlimit-mode srcip \
        --hashlimit-name syn_flood --hashlimit-htable-expire 30000 -j DROP

    # Mitigación RST Flood
    iptables -A GOLBERT_FILTER -p tcp --tcp-flags RST RST -m limit --limit 5/s --limit-burst 10 -j RETURN
    iptables -A GOLBERT_FILTER -p tcp --tcp-flags RST RST -j DROP

    # Guardar reglas de forma persistente para que sobrevivan a reinicios
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4 2>/dev/null

    # Crear servicio de auto-restauración al encender la VPS
    cat << 'SRVEOF' > /etc/systemd/system/golbert-ddos.service
[Unit]
Description=Golbert VPS Anti-DDoS Shield
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash /etc/vps-manager/core/firewall.sh --auto
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SRVEOF
    systemctl daemon-reload
    systemctl enable golbert-ddos >/dev/null 2>&1
}

desactivar_antiddos() {
    iptables -t mangle -D PREROUTING -j GOLBERT_DDOS 2>/dev/null
    iptables -t mangle -F GOLBERT_DDOS 2>/dev/null
    iptables -t mangle -X GOLBERT_DDOS 2>/dev/null

    iptables -D INPUT -j GOLBERT_FILTER 2>/dev/null
    iptables -F GOLBERT_FILTER 2>/dev/null
    iptables -X GOLBERT_FILTER 2>/dev/null

    systemctl disable golbert-ddos >/dev/null 2>&1
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
}

# Si lo llama install.sh o systemd con --auto, aplica en silencio y sale
if [ "$1" == "--auto" ]; then
    aplicar_antiddos
    exit 0
fi

# Menú interactivo (Opción 5 -> 3 del panel)
while true; do
    clear
    if iptables -t mangle -L GOLBERT_DDOS >/dev/null 2>&1; then
        estado="${C_GREEN}ACTIVO (PROTEGIENDO)${C_NC}"
    else
        estado="${C_RED}INACTIVO${C_NC}"
    fi

    drop_mangle=$(iptables -t mangle -L GOLBERT_DDOS -v -n 2>/dev/null | awk '$3 == "DROP" {sum += $1} END {print sum+0}')
    drop_filter=$(iptables -L GOLBERT_FILTER -v -n 2>/dev/null | awk '$3 == "DROP" {sum += $1} END {print sum+0}')
    total_drops=$((drop_mangle + drop_filter))

    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e " 🛡️  ${C_ORANGE}ESCUDO ANTI-DDOS & FIREWALL MANAGER${C_NC}"
    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e " Estado del Escudo  : $estado"
    echo -e " Ataques Bloqueados : ${C_WHITE}$total_drops paquetes maliciosos descartados${C_NC}"
    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e " ${C_CYAN}1.${C_NC} 🟢 Activar / Recargar Blindaje Anti-DDoS"
    echo -e " ${C_CYAN}2.${C_NC} 📊 Ver Detalle de Reglas y Tráfico Filtrado"
    echo -e " ${C_RED}3.${C_NC} 🔴 Pausar Escudo Anti-DDoS"
    echo -e " ${C_CYAN}0.${C_NC} 🚪 Volver al Menú"
    echo -e "${C_CYAN}================================================${C_NC}"
    read -p " Selecciona una opción: " f_op

    case $f_op in
        1)
            echo -e "\n${C_ORANGE}Aplicando reglas Anti-DDoS en Kernel e Iptables...${C_NC}"
            aplicar_antiddos
            echo -e "${C_GREEN}✅ Escudo Anti-DDoS activado y blindado en el arranque.${C_NC}"
            read -p " Presiona Enter para continuar..."
            ;;
        2)
            clear
            echo -e "${C_CYAN}--- PAQUETES CORRUPTOS / ESCANEOS BLOQUEADOS (MANGLE) ---${C_NC}"
            iptables -t mangle -L GOLBERT_DDOS -v -n 2>/dev/null || echo "Sin reglas activas."
            echo -e "\n${C_CYAN}--- RÁFAGAS FLOOD / FUERZA BRUTA BLOQUEADAS (FILTER) ---${C_NC}"
            iptables -L GOLBERT_FILTER -v -n 2>/dev/null || echo "Sin reglas activas."
            echo ""
            read -p " Presiona Enter para volver..."
            ;;
        3)
            desactivar_antiddos
            echo -e "\n${C_RED}❌ Escudo Anti-DDoS desactivado temporalmente.${C_NC}"
            read -p " Presiona Enter para continuar..."
            ;;
        0) exit 0 ;;
        *) echo -e "${C_RED}Opción inválida.${C_NC}"; sleep 1 ;;
    esac
done
