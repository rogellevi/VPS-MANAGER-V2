#!/bin/bash
# ==========================================
# Módulo: Instalador SlowDNS (SSH & V2Ray/Xray)
# ==========================================
C_RED='\033[1;31m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_CYAN='\033[1;36m'; C_WHITE='\033[1;37m'; C_NC='\033[0m'
SLOW_DIR="/etc/slowdns"

instalar_slowdns() {
    local MODO_DESTINO=${1:-"22"}
    clear
    if [ "$MODO_DESTINO" = "80" ]; then
        echo -e "${C_CYAN}================================================${C_NC}"
        echo -e " ⚡ ${C_YELLOW}INSTALANDO SLOWDNS PARA V2RAY / XRAY (PORT 80)${C_NC}"
        echo -e "${C_CYAN}================================================${C_NC}"
        if ! systemctl is-active --quiet xray; then
            echo -e "${C_RED}[!] Advertencia: El servicio Xray no está activo.${C_NC}"
            echo -e "${C_YELLOW}Recuerda instalar el Núcleo Maestro Xray (Opción 1) para que responda en el puerto 80.${C_NC}\n"
        fi
    else
        echo -e "${C_CYAN}================================================${C_NC}"
        echo -e " 🐢 ${C_YELLOW}INSTALANDO SLOWDNS PARA SSH (PORT 22)${C_NC}"
        echo -e "${C_CYAN}================================================${C_NC}"
    fi

    echo -e "${C_YELLOW}[1/4] Obteniendo Dominio NS...${C_NC}"
    DEFAULT_NS="ns-colo.golbertvps.online"
    [ -f "$SLOW_DIR/domain.ns" ] && DEFAULT_NS=$(cat "$SLOW_DIR/domain.ns")
    read -p " Ingresa tu NS Domain [Enter = $DEFAULT_NS]: " NS_DOMAIN
    [ -z "$NS_DOMAIN" ] && NS_DOMAIN="$DEFAULT_NS"

    echo -e "${C_YELLOW}[2/4] Instalando dependencias (Evitando menús bloqueantes)...${C_NC}"
    export DEBIAN_FRONTEND=noninteractive
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections

    if ! grep -q "1.1.1.1" /etc/resolv.conf 2>/dev/null; then
        echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" > /etc/resolv.conf
    fi

    apt-get update -y >/dev/null 2>&1
    apt-get install -y iptables iptables-persistent dnsutils wget curl psmisc >/dev/null 2>&1

    systemctl stop slowdns >/dev/null 2>&1
    killall -9 sldns-server >/dev/null 2>&1

    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null
    iptables -D INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null

    echo -e "${C_YELLOW}[3/4] Descargando motor DNSTT del repositorio público oficial...${C_NC}"
    mkdir -p "$SLOW_DIR"
    cd "$SLOW_DIR" || exit 1

    if [ ! -s "$SLOW_DIR/sldns-server" ]; then
        wget --no-check-certificate -qO "$SLOW_DIR/sldns-server" "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server"
    fi
    if [ ! -s "$SLOW_DIR/server.key" ] || [ ! -s "$SLOW_DIR/server.pub" ]; then
        wget --no-check-certificate -qO "$SLOW_DIR/server.key" "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/server.key"
        wget --no-check-certificate -qO "$SLOW_DIR/server.pub" "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/server.pub"
    fi

    chmod +x "$SLOW_DIR/sldns-server"

    if [ ! -s "$SLOW_DIR/sldns-server" ] || grep -q "404: Not Found" "$SLOW_DIR/sldns-server"; then
        echo -e "\n${C_RED}[✘] Error crítico: No se pudo descargar el binario sldns-server.${C_NC}"
        read -p "Presione Enter para regresar..."
        return 1
    fi

    if [ ! -s "$SLOW_DIR/server.key" ] || [ ! -s "$SLOW_DIR/server.pub" ] || grep -q "404" "$SLOW_DIR/server.key"; then
        rm -f "$SLOW_DIR/server.key" "$SLOW_DIR/server.pub"
        "$SLOW_DIR/sldns-server" -gen-key -privkey-file "$SLOW_DIR/server.key" -pubkey-file "$SLOW_DIR/server.pub" >/dev/null 2>&1
    fi

    chmod 600 "$SLOW_DIR/server.key"
    chmod 644 "$SLOW_DIR/server.pub"
    echo "$NS_DOMAIN" > "$SLOW_DIR/domain.ns"
    echo "$MODO_DESTINO" > "$SLOW_DIR/modo.port"

    echo -e "${C_YELLOW}[4/4] Configurando red e iniciando Servicio SlowDNS (Destino 127.0.0.1:$MODO_DESTINO)...${C_NC}"
    fuser -k -9 5300/udp >/dev/null 2>&1

    iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
    iptables -I INPUT -p udp --dport 5300 -j ACCEPT
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4 2>/dev/null

    cat << EOF > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS Server (DNSTT Público)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$SLOW_DIR
ExecStart=$SLOW_DIR/sldns-server -udp :5300 -privkey-file $SLOW_DIR/server.key $NS_DOMAIN 127.0.0.1:$MODO_DESTINO
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable slowdns >/dev/null 2>&1
    systemctl restart slowdns
    sleep 2

    if systemctl is-active --quiet slowdns; then
        PUB=$(cat "$SLOW_DIR/server.pub")
        echo -e "\n${C_GREEN}[✔] ¡SlowDNS instalado exitosamente!${C_NC}"
        if [ "$MODO_DESTINO" = "80" ]; then
            echo -e " ⚡ Modalidad : ${C_CYAN}V2Ray / Xray + SlowDNS (Puerto 80)${C_NC}"
        else
            echo -e " 🐢 Modalidad : ${C_GREEN}SSH Directo + SlowDNS (Puerto 22)${C_NC}"
        fi
        echo -e " 🌍 NS Domain : ${C_YELLOW}$NS_DOMAIN${C_NC}"
        echo -e " 🗝️ Pub Key   : ${C_YELLOW}$PUB${C_NC}"
    else
        echo -e "\n${C_RED}[✘] Error al iniciar SlowDNS Server.${C_NC}"
        journalctl -u slowdns -n 10 --no-pager
    fi
    read -p "Presione Enter para regresar..."
}

cambiar_modo_rapido() {
    local NUEVO_PUERTO=$1
    if [ ! -f /etc/systemd/system/slowdns.service ] || [ ! -f "$SLOW_DIR/domain.ns" ]; then
        instalar_slowdns "$NUEVO_PUERTO"
        return
    fi
    NS_DOMAIN=$(cat "$SLOW_DIR/domain.ns")
    sed -i "s|127.0.0.1:[0-9]*|127.0.0.1:$NUEVO_PUERTO|g" /etc/systemd/system/slowdns.service
    echo "$NUEVO_PUERTO" > "$SLOW_DIR/modo.port"
    systemctl daemon-reload
    systemctl restart slowdns
    PUB=$(cat "$SLOW_DIR/server.pub" 2>/dev/null)
    echo -e "\n${C_GREEN}[✔] SlowDNS cambiado exitosamente a 127.0.0.1:$NUEVO_PUERTO${C_NC}"
    echo -e " 🌍 NS Domain : ${C_YELLOW}$NS_DOMAIN${C_NC}"
    echo -e " 🗝️ Pub Key   : ${C_YELLOW}$PUB${C_NC}"
    read -p "Presione Enter para continuar..."
}

desinstalar_slowdns() {
    clear
    echo -e "${C_YELLOW}[+] Desinstalando SlowDNS...${C_NC}"
    systemctl stop slowdns >/dev/null 2>&1
    systemctl disable slowdns >/dev/null 2>&1
    killall -9 sldns-server >/dev/null 2>&1
    fuser -k -9 5300/udp >/dev/null 2>&1

    rm -f /etc/systemd/system/slowdns.service
    rm -rf "$SLOW_DIR"

    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null
    iptables -D INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null
    iptables-save > /etc/iptables/rules.v4 2>/dev/null

    systemctl daemon-reload
    echo -e "\n${C_GREEN}[✔] SlowDNS eliminado exitosamente.${C_NC}"
    read -p "Presione Enter para regresar..."
}

# Si se llama con parámetro desde el Gestor 80/443 (ej: bash slowdns.sh v2ray)
if [ "$1" = "v2ray" ]; then
    cambiar_modo_rapido "80"
    exit 0
fi

clear
MODO_ACTUAL="No instalado"
if systemctl is-active --quiet slowdns; then
    if grep -q "127.0.0.1:80" /etc/systemd/system/slowdns.service 2>/dev/null; then
        MODO_ACTUAL="${C_CYAN}ACTIVO -> V2RAY / XRAY (Puerto 80)${C_NC}"
    else
        MODO_ACTUAL="${C_GREEN}ACTIVO -> SSH DIRECTO (Puerto 22)${C_NC}"
    fi
fi

echo -e "${C_CYAN}================================================${C_NC}"
echo -e " 🐢 GESTIÓN DE SLOWDNS V5.0 (SSH & V2RAY)"
echo -e " Estado: $MODO_ACTUAL"
echo -e "${C_CYAN}================================================${C_NC}"
echo -e " 1. 🟢 Instalar SlowDNS Modo SSH (Puerto 22)"
echo -e " 2. ⚡ Instalar SlowDNS Modo V2Ray/Xray (Puerto 80)"
echo -e " 3. 🔄 Cambiar Modo en Caliente (SSH 22 <-> V2Ray 80)"
echo -e " 4. 🔴 Desinstalar SlowDNS"
echo -e " 0. 🚪 Volver al Menú"
echo -e "${C_CYAN}================================================${C_NC}"
read -p " Opción: " opc

case $opc in
    1) instalar_slowdns "22" ;;
    2) instalar_slowdns "80" ;;
    3)
        if grep -q "127.0.0.1:80" /etc/systemd/system/slowdns.service 2>/dev/null; then
            cambiar_modo_rapido "22"
        else
            cambiar_modo_rapido "80"
        fi
        ;;
    4) desinstalar_slowdns ;;
    0) exit 0 ;;
    *) echo -e "${C_RED}Opción inválida.${C_NC}"; sleep 1 ;;
esac
