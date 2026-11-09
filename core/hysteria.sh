#!/bin/bash
# ==========================================
# Instalador Hysteria / Hysteria 2 UDP - Golbert VPS
# ==========================================
C_ORANGE='\033[38;5;214m'; C_BLUE='\033[1;34m'; C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_RED='\033[1;31m'; C_NC='\033[0m'

# Valores por defecto
DEFAULT_PORT=36712
DEFAULT_RANGE="10000:65000"
DEFAULT_OBFS="GolbertVps"
[ -f /etc/vps-manager/domain.txt ] && DEFAULT_DOMAIN=$(cat /etc/vps-manager/domain.txt) || DEFAULT_DOMAIN="colo.golbertvps.online"

clear
echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
echo -e "           ${C_BLUE}INSTALACIÓN DE HYSTERIA 2 (UDP)${C_NC}"
echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
echo -e "\n${C_ORANGE}Descargando binario oficial y dependencias...${C_NC}"

mkdir -p /etc/vps-manager/hysteria
systemctl stop hysteria > /dev/null 2>&1

# Instalación de iptables-persistent modo silencioso (evita bloqueos)
export DEBIAN_FRONTEND=noninteractive
apt-get update > /dev/null 2>&1
apt-get install -yq iptables iptables-persistent netfilter-persistent iproute2 > /dev/null 2>&1

# Detección de Arquitectura
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    SYS_ARCH="amd64"
elif [[ "$ARCH" == "aarch64" ]]; then
    SYS_ARCH="arm64"
else
    echo -e " ${C_RED}[!] Arquitectura no soportada: $ARCH${C_NC}"
    exit 1
fi

# Descarga del binario de Hysteria 2
wget -qO /usr/local/bin/hysteria "https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-${SYS_ARCH}"
chmod +x /usr/local/bin/hysteria

sleep 1.5 
echo -e "${C_CYAN}[OK] Binario instalado correctamente (${SYS_ARCH})${C_NC}\n"

# ---------------------------------------------------------
# RECOPILACIÓN DE DATOS INTERACTIVA
# ---------------------------------------------------------
read -p "$(echo -e "${C_ORANGE}Dominio/SNI [Default $DEFAULT_DOMAIN]: ${C_NC}")" INPUT_DOMAIN
FINAL_DOMAIN=${INPUT_DOMAIN:-$DEFAULT_DOMAIN}

while true; do
    read -p "$(echo -e "${C_ORANGE}Puerto de escucha principal [Default $DEFAULT_PORT]: ${C_NC}")" INPUT_PORT
    FINAL_PORT=${INPUT_PORT:-$DEFAULT_PORT}
    if ! [[ "$FINAL_PORT" =~ ^[0-9]+$ ]]; then echo -e " ${C_RED}[!] Número inválido.${C_NC}"; continue; fi
    
    # Verificación de puerto con 'ss' (más confiable que netstat)
    if ss -tuln | grep -qE ":$FINAL_PORT\b"; then echo -e " ${C_RED}[!] Puerto en uso.${C_NC}"; else break; fi
done

read -p "$(echo -e "${C_ORANGE}Rango de Puertos (Port Hopping) [Default $DEFAULT_RANGE]: ${C_NC}")" INPUT_RANGE
FINAL_RANGE=${INPUT_RANGE:-$DEFAULT_RANGE}

read -p "$(echo -e "${C_ORANGE}Contraseña OBFS y Autenticación [Default $DEFAULT_OBFS]: ${C_NC}")" INPUT_OBFS
FINAL_OBFS=${INPUT_OBFS:-$DEFAULT_OBFS}

echo -e "\n${C_GREEN}[OK] Generando Certificados y Configurando...${C_NC}"

# 1. Generar Certificado Self-Signed para el Dominio
openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/vps-manager/hysteria/server.key -out /etc/vps-manager/hysteria/server.crt -days 3650 -subj "/CN=$FINAL_DOMAIN" > /dev/null 2>&1

# 2. Crear archivo config.yaml de Hysteria 2 (Sintaxis Corregida)
cat << EOF > /etc/vps-manager/hysteria/config.yaml
listen: :$FINAL_PORT

tls:
  cert: /etc/vps-manager/hysteria/server.crt
  key: /etc/vps-manager/hysteria/server.key

auth:
  type: password
  password: $FINAL_OBFS

obfs:
  type: salamander
  salamander:
    password: $FINAL_OBFS
EOF

# 3. Aplicar reglas de Iptables para el Port Hopping (Rango de Puertos)
iptables -t nat -D PREROUTING -p udp --dport $FINAL_RANGE -j REDIRECT --to-ports $FINAL_PORT 2>/dev/null
iptables -t nat -A PREROUTING -p udp --dport $FINAL_RANGE -j REDIRECT --to-ports $FINAL_PORT
netfilter-persistent save > /dev/null 2>&1

# 4. Crear Servicio Systemd
cat << EOF > /etc/systemd/system/hysteria.service
[Unit]
Description=Hysteria 2 VPN Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/vps-manager/hysteria
ExecStart=/usr/local/bin/hysteria server -c /etc/vps-manager/hysteria/config.yaml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hysteria >/dev/null 2>&1
systemctl restart hysteria

# Obtener IP Pública para el resumen y enlace
IP_ADDR=$(curl -sS ifconfig.me 2>/dev/null)
LINK_HY2="hy2://$FINAL_OBFS@$IP_ADDR:$FINAL_PORT?insecure=1&sni=$FINAL_DOMAIN&obfs=salamander&obfs-password=$FINAL_OBFS#Golbert_UDP"

clear
echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
echo -e " ${C_GREEN}✅ INSTALACIÓN DE HYSTERIA COMPLETADA${C_NC}"
echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
echo -e " ${C_CYAN}IP             :${C_NC} $IP_ADDR"
echo -e " ${C_CYAN}DOMINIO/SNI    :${C_NC} $FINAL_DOMAIN"
echo -e " ${C_CYAN}OBFS (Pass)    :${C_NC} $FINAL_OBFS"
echo -e " ${C_CYAN}PUERTO MAIN    :${C_NC} $FINAL_PORT"
echo -e " ${C_CYAN}RANGO PUERTOS  :${C_NC} $FINAL_RANGE"
echo -e " ${C_CYAN}ALPN           :${C_NC} h3"
echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
echo -e " ${C_GREEN}🔗 LINK DE CONEXIÓN HYSTERIA 2:${C_NC}"
echo -e " \033[4;37m$LINK_HY2\033[0m"
echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
read -p " Presiona Enter para volver al menú..."
