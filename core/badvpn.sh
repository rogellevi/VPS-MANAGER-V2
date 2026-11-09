#!/bin/bash
# =========================================================================
# Módulo: BadVPN Nativo (Ultra-Robusto para Ubuntu 22-26 y Debian 11-12)
# =========================================================================
C_RED='\033[1;31m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'
C_CYAN='\033[1;36m'; C_WHITE='\033[1;37m'; C_NC='\033[0m'

instalar_badvpn() {
    clear
    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e "${C_GREEN}    COMPILACIÓN E INSTALACIÓN DE BADVPN         ${C_NC}"
    echo -e "       (Soporte Ubuntu 22/24/26 y Debian 11/12) "
    echo -e "${C_CYAN}================================================${C_NC}"

    echo -e "\n${C_YELLOW}[1/6] Limpiando procesos y archivos de instalaciones previas...${C_NC}"
    systemctl stop badvpn-7300 badvpn-7200 badvpn >/dev/null 2>&1
    systemctl disable badvpn-7300 badvpn-7200 badvpn >/dev/null 2>&1
    pkill -9 -f "badvpn-udpgw" >/dev/null 2>&1
    rm -f /etc/systemd/system/badvpn-7300.service
    rm -f /etc/systemd/system/badvpn-7200.service
    rm -f /usr/local/bin/badvpn-udpgw /bin/badvpn-udpgw
    rm -rf /tmp/badvpn*
    systemctl daemon-reload

    echo -e "\n${C_YELLOW}[2/6] Instalando dependencias de compilación universales...${C_NC}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null 2>&1
    apt-get install -y build-essential cmake make gcc g++ git wget pkg-config >/dev/null 2>&1

    echo -e "\n${C_YELLOW}[3/6] Descargando código fuente oficial de BadVPN...${C_NC}"
    cd /tmp || exit 1
    if ! git clone --depth 1 https://github.com/ambrop72/badvpn.git; then
        echo -e "\n${C_RED}[!] Error al descargar el repositorio de BadVPN.${C_NC}"
        read -r -p "Presione Enter para volver..."
        return 1
    fi
    cd badvpn || exit 1

    echo -e "\n${C_YELLOW}[4/6] Aplicando parche de compatibilidad extremo para CMake moderno...${C_NC}"
    sed -i 's/cmake_minimum_required.*/cmake_minimum_required(VERSION 3.5)/g' CMakeLists.txt

    echo -e "\n${C_YELLOW}[5/6] Compilando el código fuente en modo Multi-Core...${C_NC}"
    mkdir -p build && cd build || exit 1
    cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    make -j"$(nproc 2>/dev/null || echo 2)"
    make install

    # Verificación de compilación exitosa
    if [ -f "/usr/local/bin/badvpn-udpgw" ]; then
        BADVPN_BIN="/usr/local/bin/badvpn-udpgw"
    elif [ -f "/tmp/badvpn/build/udpgw/badvpn-udpgw" ]; then
        cp -f /tmp/badvpn/build/udpgw/badvpn-udpgw /usr/local/bin/badvpn-udpgw
        BADVPN_BIN="/usr/local/bin/badvpn-udpgw"
    else
        echo -e "\n${C_RED}[!] Error Crítico: La compilación falló. Revisa el texto arriba para ver qué faltó.${C_NC}"
        rm -rf /tmp/badvpn*
        read -r -p "Presione Enter para salir..."
        return 1
    fi

    chmod +x "$BADVPN_BIN"
    ln -sf "$BADVPN_BIN" /bin/badvpn-udpgw
    rm -rf /tmp/badvpn*

    echo -e "\n${C_YELLOW}[6/6] Configurando e iniciando servicios Systemd (Puertos 7200 y 7300)...${C_NC}"

    cat << EOF > /etc/systemd/system/badvpn-7200.service
[Unit]
Description=BadVPN UDPGW Port 7200
After=network.target

[Service]
Type=simple
ExecStart=$BADVPN_BIN --listen-addr 127.0.0.1:7200 --max-clients 1000 --max-connections-for-client 50
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    cat << EOF > /etc/systemd/system/badvpn-7300.service
[Unit]
Description=BadVPN UDPGW Port 7300
After=network.target

[Service]
Type=simple
ExecStart=$BADVPN_BIN --listen-addr 127.0.0.1:7300 --max-clients 1000 --max-connections-for-client 50
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable badvpn-7200 badvpn-7300 >/dev/null 2>&1
    systemctl restart badvpn-7200 badvpn-7300

    sleep 2

    # Verificación de estado final en vivo (Sin barras invertidas que rompan la validación)
    ESTADO_7200=$(systemctl is-active badvpn-7200)
    ESTADO_7300=$(systemctl is-active badvpn-7300)

    if [ "$ESTADO_7200" = "active" ] && [ "$ESTADO_7300" = "active" ]; then
        echo -e "\n${C_CYAN}================================================${C_NC}"
        echo -e "${C_GREEN} [✔] INSTALACIÓN EXITOSA. BADVPN ESTÁ ACTIVO.${C_NC}"
        echo -e "     - Puerto 7200: ${C_GREEN}ACTIVO${C_NC}"
        echo -e "     - Puerto 7300: ${C_GREEN}ACTIVO${C_NC}"
        echo -e "${C_CYAN}================================================${C_NC}"
    else
        echo -e "\n${C_RED}[!] Error: Los servicios se compilaron pero no pudieron arrancar.${C_NC}"
        echo -e "${C_YELLOW}Log del puerto 7200:${C_NC}"
        journalctl -u badvpn-7200.service -n 5 --no-pager
    fi

    read -r -p "Presione Enter para continuar..."
}

while true; do
    clear
    [ "$(systemctl is-active badvpn-7200)" = "active" ] && s7200="${C_GREEN}ON${C_NC}" || s7200="${C_RED}OFF${C_NC}"
    [ "$(systemctl is-active badvpn-7300)" = "active" ] && s7300="${C_GREEN}ON${C_NC}" || s7300="${C_RED}OFF${C_NC}"

    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e " 🎮 ${C_GREEN}GESTOR BADVPN UDPGW (LLAMADAS Y JUEGOS)${C_NC}"
    echo -e "${C_CYAN}================================================${C_NC}"
    echo -e " 🔌 Puerto 7200 : [$s7200]   |   🔌 Puerto 7300 : [$s7300]"
    echo -e "${C_CYAN}------------------------------------------------${C_NC}"
    echo -e " 1. 🚀 Instalar / Recompilar BadVPN (7200 & 7300)"
    echo -e " 2. 🔄 Reiniciar Servicios BadVPN"
    echo -e " 3. 🛑 Detener y Desactivar BadVPN"
    echo -e " 0. 🚪 Volver al Menú"
    echo -e "${C_CYAN}================================================${C_NC}"
    read -r -p "Selecciona una opción: " bop

    case $bop in
        1) instalar_badvpn ;;
        2)
            systemctl restart badvpn-7200 badvpn-7300 2>/dev/null
            echo -e "\n${C_GREEN}[✔] Servicios BadVPN 7200/7300 reiniciados.${C_NC}"
            sleep 2
            ;;
        3)
            systemctl stop badvpn-7200 badvpn-7300 2>/dev/null
            systemctl disable badvpn-7200 badvpn-7300 >/dev/null 2>&1
            pkill -9 -f "badvpn-udpgw" 2>/dev/null
            echo -e "\n${C_YELLOW}[✔] BadVPN detenido correctamente.${C_NC}"
            sleep 2
            ;;
        0) break ;;
        *) echo -e "${C_RED}Opción inválida.${C_NC}"; sleep 1 ;;
    esac
done
