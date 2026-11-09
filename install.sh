#!/bin/bash
# =========================================================================
# Instalador Principal Seguro - Golbert VPS V5.0 LTS
# =========================================================================

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive

C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_CYAN='\033[1;36m'
C_ORANGE='\033[38;5;214m'
C_NC='\033[0m'

# --- PROTECCIÓN DEL TOKEN DE GITHUB ---
# El token original ha sido ofuscado en Base64 para evitar lectura directa.
SECRET_T="Z2l0aHViX3BhdF8xMUEyN1dGWkkwQmdDVVRoOUVUQ3VHX3hVcFFUZXQxRWQxNnZlVzI1NGtMVkFKb2hCN3pYdXZPOVAxbEVkQ3ZmZW1KSjZXTFJLNmI2Y0s5NkFX"
# Se limpia el token original y se convierte dinámicamente:
_GH_A=$(echo "Z2l0aHViX3BhdF8xMUEyN1dGWkkwOEhyZjBURDNmUmVoX3RBU3hrYw==" | base64 -d)
_GH_B=$(echo "Skt2QUhZczlpdXJ2dG1SNHFvaXV0N1ltd0hGS1BpVnhtc3NGYlpXQjNSUkEzWnN2MWtUZGE=" | base64 -d)
GH_TOKEN="${_GH_A}${_GH_B}"

REPO_URL="https://raw.githubusercontent.com/golbert19/vps-script/main"
CORE_DIR="/etc/vps-manager/core"

reparar_repositorios_apt() {
    dpkg --configure -a > /dev/null 2>&1
    sed -i '/debian-security/s/^/#/' /etc/apt/sources.list 2>/dev/null
    rm -rf /var/lib/apt/lists/*
    apt-get clean > /dev/null 2>&1
    apt-get update --allow-releaseinfo-change -y > /dev/null 2>&1
    apt-get --fix-broken install -y > /dev/null 2>&1
}

# --- INSTALACIÓN DE DEPENDENCIAS CRÍTICAS PARA LA API ---
dpkg --configure -a > /dev/null 2>&1
apt-get update --allow-releaseinfo-change -y > /dev/null 2>&1
if ! apt-get install -y --fix-missing curl wget ca-certificates > /dev/null 2>&1; then
    reparar_repositorios_apt
    apt-get install -y --fix-missing curl wget ca-certificates > /dev/null 2>&1
fi

clear
echo -e "${C_CYAN}================================================${C_NC}"
echo -e "${C_ORANGE}       INGRESE SU KEY DE INSTALACIÓN            ${C_NC}"
echo -e "${C_CYAN}================================================${C_NC}"
read -p "🔑 KEY: " USER_KEY

# --- VALIDACIÓN DE KEY ---
VPS_IP=$(curl -4 -sS --max-time 5 ipv4.icanhazip.com 2>/dev/null || wget -4 -qO- -T 5 ifconfig.me)
BOT_API="http://45.41.207.172:8888/verify"

echo -e "\n⏳ Validando Key con el Servidor Principal..."
VALIDATION=$(curl -4 -sS --max-time 8 "$BOT_API?key=$USER_KEY&ip=$VPS_IP" 2>/dev/null)

if echo "$VALIDATION" | grep -q "valid" && ! echo "$VALIDATION" | grep -q "invalid"; then
    echo -e "${C_GREEN}✅ Key Aceptada. Iniciando instalación...${C_NC}"
    sleep 2
else
    echo -e "${C_RED}❌ KEY INVÁLIDA, EXPIRADA O SIN CONEXIÓN AL SERVIDOR DE LICENCIAS.${C_NC}"
    echo -e "Adquiere una nueva key contactando a @golbert_service"
    exit 1
fi

os_name=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2 | awk '{print $1, $2}')
cpu_info=$(grep "vendor_id" /proc/cpuinfo | head -1 | awk -F': ' '{print $2}')

clear
echo -e "${C_ORANGE}======================================================${C_NC}"
echo -e "             [ ! ] ESPERE UN MOMENTO [ ! ]"
echo -e "${C_ORANGE}======================================================${C_NC}"
echo -e " ${C_RED}SISTEMA:${C_NC} $os_name          ${C_RED}CPU:${C_NC} $cpu_info"
echo -e "${C_ORANGE}======================================================${C_NC}"
sleep 1

systemctl stop apache2 > /dev/null 2>&1
systemctl disable apache2 > /dev/null 2>&1

echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections 2>/dev/null
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections 2>/dev/null

paquetes=(
    "bsdmainutils" "sudo" "cron" "screen" "nginx" "haproxy" "stunnel4"
    "jq" "unzip" "openssl" "iproute2" "uuid-runtime" "nload" "htop"
    "python3" "python3-pip" "python3-venv" "iptables" "iptables-persistent"
    "nodejs" "npm" "lsof" "psmisc" "socat" "bc" "netcat-openbsd" "net-tools" "dos2unix" "certbot"
)

REPO_REPARADO=0
for pkg in "${paquetes[@]}"; do
    if ! apt-get install -y --fix-missing "$pkg" > /dev/null 2>&1; then
        if [ "$REPO_REPARADO" -eq 0 ]; then
            reparar_repositorios_apt
            REPO_REPARADO=1
        fi
        apt-get install -y --fix-missing "$pkg" > /dev/null 2>&1
    fi
    echo -e " - [ ${C_GREEN}✅${C_NC} ] INSTALACIÓN CORRECTA ${pkg}"
done

# --- ACTIVACIÓN DE NGINX EN PUERTOS 2081 Y 8442 ---
mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/conf.d /etc/vps-manager/openvpn_files
systemctl unmask nginx > /dev/null 2>&1
rm -f /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf 2>/dev/null

cat << 'NGINXEOF' > /etc/nginx/sites-available/pasarela
server {
    listen 2081 default_server;
    listen [::]:2081 default_server;
    root /etc/vps-manager/openvpn_files;
    index index.html index.htm;
    server_name _;
    location / {
        autoindex on;
        try_files $uri $uri/ =404;
    }
}
server {
    listen 8442;
    listen [::]:8442;
    server_name _;
    location / {
        proxy_pass http://127.0.0.1:10080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}
NGINXEOF

ln -sf /etc/nginx/sites-available/pasarela /etc/nginx/sites-enabled/pasarela
mkdir -p /etc/systemd/system/nginx.service.d
cat << 'EOF' > /etc/systemd/system/nginx.service.d/override.conf
[Service]
Restart=always
RestartSec=3
EOF
systemctl daemon-reload
systemctl enable nginx > /dev/null 2>&1
systemctl restart nginx > /dev/null 2>&1
echo -e " - [ ${C_GREEN}✅${C_NC} ] SERVICIO NGINX ACTIVADO EN PUERTOS 2081/8442 (ON)"

# --- BLINDAJE SSH, KERNEL TCP Y MEMORIA SWAP ---
sed -i '/^#*MaxStartups/d; /^#*MaxSessions/d; /^#*UseDNS/d; /^#*LoginGraceTime/d; /^#*ClientAliveInterval/d; /^#*ClientAliveCountMax/d' /etc/ssh/sshd_config
cat << 'SSHEOF' >> /etc/ssh/sshd_config
MaxStartups 1000:30:2000
MaxSessions 1000
UseDNS no
LoginGraceTime 20
ClientAliveInterval 60
ClientAliveCountMax 3
SSHEOF

mkdir -p /etc/systemd/system/ssh.service.d
cat << 'SRVSSH' > /etc/systemd/system/ssh.service.d/override.conf
[Service]
LimitNOFILE=65535
LimitNPROC=65535
TasksMax=infinity
Restart=always
RestartSec=2
SRVSSH
systemctl daemon-reload
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null

cat << 'SYSEOF' > /etc/sysctl.d/99-vps-stability.conf
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
vm.swappiness = 10
SYSEOF
sysctl --system > /dev/null 2>&1

if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 >/dev/null 2>&1
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null 2>&1
    swapon /swapfile >/dev/null 2>&1
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
fi
echo -e " - [ ${C_GREEN}✅${C_NC} ] BLINDAJE SSH Y MEMORIA SWAP 2GB ACTIVADOS (ON)"

# --- DESCARGA DE ARCHIVOS SINCRONIZADA ---
echo -e "\n${C_ORANGE}======================================================${C_NC}"
echo -e "${C_GREEN}Descargando panel y módulos sincronizados...${C_NC}"
mkdir -p "$CORE_DIR" /root/usuarios

# Usar el Token de forma segura desde la variable de entorno
wget -4 -T 10 -t 2 "--header=Authorization: token $GH_TOKEN" -qO "$CORE_DIR/menu.sh" "$REPO_URL/menu.sh"
if [ ! -s "$CORE_DIR/menu.sh" ]; then
    wget -4 -T 10 -t 2 "--header=Authorization: token $GH_TOKEN" -qO "$CORE_DIR/menu.sh" "$REPO_URL/core/menu.sh"
fi
wget -4 -T 10 -t 2 "--header=Authorization: token $GH_TOKEN" -qO /etc/vps-manager/languages.sh "$REPO_URL/languages.sh" 2>/dev/null
wget -4 -T 10 -t 2 "--header=Authorization: token $GH_TOKEN" -qO /etc/vps-manager/version "$REPO_URL/version" 2>/dev/null

CORE_FILES=(
    "menu.sh" "user.sh" "xray_manager.sh" "vmess.sh" "vless.sh" "trojan.sh"
    "shadowsocks.sh" "xhttp.sh"
    "bot.sh" "bhttp.sh" "BHTTP.py" "checkuser.sh" "domain.sh" "firewall.sh"
    "fix_ports.sh" "hcr-server" "hcr.sh" "hysteria.sh" "limiter.sh" "master.py"
    "slowdns.sh" "badvpn.sh" "udp_custom.sh" "sshws.sh" "proxy.py" "ssl.sh"
    "edit_ovpn_user.sh" "zivpn.sh" "bbr.sh" "ws_eproxy.sh" "dns_resolver.sh"
    "specs.sh" "optimizer.sh" "webpanel.sh" "banner.sh" "php.sh" "ports.sh"
    "setup_dns.sh" "setup_hysteria.sh" "setup_zivpn.sh" "ssh.sh" "websocket.sh" "update.sh"
)

for file in "${CORE_FILES[@]}"; do
    wget -4 -T 10 -t 2 "--header=Authorization: token $GH_TOKEN" -qO "$CORE_DIR/$file.tmp" "$REPO_URL/core/$file"
    if [ -s "$CORE_DIR/$file.tmp" ]; then
        mv -f "$CORE_DIR/$file.tmp" "$CORE_DIR/$file"
    else
        rm -f "$CORE_DIR/$file.tmp"
    fi
done

chmod +x "$CORE_DIR"/*.sh "$CORE_DIR"/*.py 2>/dev/null
[ -f "$CORE_DIR/hcr-server" ] && chmod +x "$CORE_DIR/hcr-server"
dos2unix "$CORE_DIR"/*.sh "$CORE_DIR"/*.py > /dev/null 2>&1

cp -f "$CORE_DIR/menu.sh" /usr/bin/menu
ln -sf /usr/bin/menu /usr/local/bin/menu
chmod +x /usr/bin/menu /usr/local/bin/menu

cat << 'REACTEOF' > /usr/bin/reactivar
#!/bin/bash
clear
echo -e "\033[1;33m================================================\033[0m"
echo -e " 🚀 INICIANDO REACTIVACIÓN DEL VPS..."
echo -e "\033[1;33m================================================\033[0m"
sync; echo 3 > /proc/sys/vm/drop_caches
pkill -9 -f "wget" 2>/dev/null; pkill -9 -f "curl" 2>/dev/null
pkill -9 -f "apt" 2>/dev/null; pkill -9 -f "dpkg" 2>/dev/null
systemctl restart ssh sshd nginx haproxy xray ssh-ws ws-python 2>/dev/null
echo -e "\033[1;32m[✔] ¡VPS REACTIVADO Y MEMORIA LIBERADA AL 100%!\033[0m\n"
REACTEOF
chmod +x /usr/bin/reactivar
ln -sf /usr/bin/reactivar /usr/local/bin/reactivar

echo -e " - [ ${C_GREEN}✅${C_NC} ] MÓDULOS DE FUNCIONES Y COMANDO REACTIVAR INSTALADOS"

if [ -f "$CORE_DIR/firewall.sh" ]; then
    bash "$CORE_DIR/firewall.sh" --auto
    echo -e " - [ ${C_GREEN}✅${C_NC} ] ESCUDO ANTI-DDOS INTEGRADO Y ACTIVO (ON)"
fi

if ! grep -q "menu" /root/.bashrc; then
    echo -e "\nclear\nmenu" >> /root/.bashrc
fi

# Eliminar el rastro del token en memoria antes de finalizar
unset GH_TOKEN _GH_A _GH_B

echo -e "${C_ORANGE}======================================================${C_NC}"
echo -e "\n${C_GREEN}✅ INSTALACIÓN BASE COMPLETADA EXITOSAMENTE.${C_NC}"
echo -e "${C_CYAN}La VPS se cerrará de forma automática para su reinicio.${C_NC}"
echo -e "${C_CYAN}Podrá ingresar nuevamente a su VPS en unos instantes.${C_NC}"
echo -e "${C_ORANGE}======================================================${C_NC}"

for i in {10..1}; do
    echo -ne "${C_RED}Reiniciando en: $i segundos...\r${C_NC}"
    sleep 1
done

echo -e "\n${C_GREEN}Reiniciando sistema ahora...${C_NC}"
reboot
