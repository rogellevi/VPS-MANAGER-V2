#!/bin/bash
# ==========================================
# GESTIÓN DE USUARIOS SSH / VPN (DASHBOARD)
# ==========================================

C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_BLUE='\033[1;34m'
C_CYAN='\033[1;36m'
C_ORANGE='\033[38;5;214m'
C_PURPLE='\033[1;35m'
C_WHITE='\033[1;37m'
C_YELLOW='\033[1;33m'
C_GRAY='\033[1;30m'
BG_BOX='\033[44;1;37m'
C_NC='\033[0m'

# Función para convertir Bytes a KB / MB / GB / TB automáticamente
format_bytes() {
    local bytes=${1:-0}
    awk -v b="$bytes" 'BEGIN {
        if (b >= 1099511627776) printf "%.2f TB", b/1099511627776;
        else if (b >= 1073741824) printf "%.2f GB", b/1073741824;
        else if (b >= 1048576) printf "%.2f MB", b/1048576;
        else if (b >= 1024) printf "%.2f KB", b/1024;
        else printf "%d B", b;
    }'
}

# Función para sincronizar el banner individual (Usuario + Vencimiento) al instante
actualizar_banner_usuario() {
    if [ -x /usr/local/bin/sync-banners ]; then
        /usr/local/bin/sync-banners --force >/dev/null 2>&1
    fi
}

# 1. Crear Usuario
crear_usuario() {
    while true; do
        clear
        echo -e "${C_ORANGE}======================================================${C_NC}"
        echo -e "               ${C_BLUE}[ TIPO DE CUENTA A CREAR ]${C_NC}"
        echo -e "${C_ORANGE}======================================================${C_NC}"
        echo -e " 1. 👤 Crear Cuenta Normal"
        echo -e " 2. 📱 Crear Cuenta HWID (Bloqueo por Dispositivo)"
        echo -e " 3. 🎫 Crear Cuenta Token"
        echo -e " 0. 🚪 VOLVER"
        echo -e "${C_ORANGE}======================================================${C_NC}"
        read -p " Selecciona una opción: " tipo_op

        case $tipo_op in
            1) tipo_cuenta="Normal"; break ;;
            2) tipo_cuenta="HWID"; break ;;
            3) tipo_cuenta="Token"; break ;;
            0) return ;;
            *) echo -e "${C_RED}Opción inválida.${C_NC}"; sleep 1 ;;
        esac
    done

    clear
    echo -e "${C_ORANGE}======================================================${C_NC}"
    echo -e "         ${C_BLUE}[ CREANDO USUARIO - $tipo_cuenta ]${C_NC}"
    echo -e "${C_ORANGE}======================================================${C_NC}"
    read -p " Nombre de usuario: " username
    
    if id "$username" &>/dev/null; then
        echo -e "\n ${C_RED}[!] Error: El usuario '$username' ya existe.${C_NC}"
        sleep 2
        return
    fi
    
    read -p " Contraseña: " password
    read -p " Días de duración: " dias
    read -p " Límite de conexiones: " limite

    valor_extra=""
    if [ "$tipo_cuenta" = "HWID" ]; then
        read -p " Ingresa el HWID del cliente: " valor_extra
    elif [ "$tipo_cuenta" = "Token" ]; then
        read -p " Ingresa el Token del cliente: " valor_extra
    fi

    useradd -M -s /bin/false -e $(date -d "+$dias days" +%Y-%m-%d) "$username"
    echo "$username:$password" | chpasswd
    
    mkdir -p /root/usuarios
    echo "$limite" > /root/usuarios/$username.limit

    if [ "$tipo_cuenta" = "HWID" ] && [ -n "$valor_extra" ]; then
        mkdir -p /root/usuarios/hwid
        echo "$valor_extra" > /root/usuarios/hwid/$username.hwid
    elif [ "$tipo_cuenta" = "Token" ] && [ -n "$valor_extra" ]; then
        mkdir -p /root/usuarios/token
        echo "$valor_extra" > /root/usuarios/token/$username.token
    fi

    # Generar y vincular el banner con nombre de usuario y fecha de vencimiento al instante
    actualizar_banner_usuario

    IP=$(curl -sS ifconfig.me 2>/dev/null || wget -qO- ipv4.icanhazip.com)

    clear
    echo -e "${C_GREEN}✅ Usuario $tipo_cuenta creado con éxito.${C_NC}"
    echo -e "${C_CYAN}======================================================${C_NC}"
    echo -e " 👤 Usuario   : $username"
    echo -e " 🔑 Pass      : $password"
    echo -e " ⏳ Vence     : $(date -d "+$dias days" +%d/%m/%Y)"
    echo -e " ⚙️ Límite    : $limite conexión(es)"
    
    if [ "$tipo_cuenta" = "HWID" ]; then
        echo -e " 📱 HWID      : $valor_extra"
    elif [ "$tipo_cuenta" = "Token" ]; then
        echo -e " 🎫 Token     : $valor_extra"
    fi
    
    echo -e " 🌐 IP Server : $IP"
    echo -e "${C_CYAN}======================================================${C_NC}"
    echo -e "${C_ORANGE}          🚀 MÉTODOS DE CONEXIÓN ACTIVOS 🚀${C_NC}"
    echo -e "${C_CYAN}======================================================${C_NC}"

    echo -e " 🔹 SSH Directo : 22"

    # Detección de WebSocket / HAProxy / eProxy
    if systemctl is-active --quiet ssh-ws || systemctl is-active --quiet haproxy || systemctl is-active --quiet edu-proxy || systemctl is-active --quiet ws-proxy || systemctl is-active --quiet ws-stunnel || systemctl is-active --quiet ws-python || systemctl is-active --quiet ws || pgrep -f -i "proxy.py" > /dev/null || pgrep -f -i "ws.py" > /dev/null; then
        echo -e " 🔹 WS / SSL    : Activo (Puertos 80, 8080, 443)"
    fi

    if systemctl is-active --quiet bhttp; then
        PORT_BHTTP=$(grep -oP '(?<="port": )[0-9]+' /etc/vps-manager/bhttp/BHTTP.py 2>/dev/null | head -1)
        echo -e " 🔹 BHTTP Proxy : ${PORT_BHTTP:-8180}"
    fi

    if systemctl is-active --quiet hcr; then
        PORT_HCR=$(systemctl show hcr.service -p ExecStart 2>/dev/null | grep -oP '(?<=--listen :)[0-9]+' | head -1)
        echo -e " 🔹 HCR Plain   : ${PORT_HCR:-8880}"
    fi

    if systemctl is-active --quiet udp-custom; then
        echo -e " 🔹 UDP Custom  : Activo (Puertos 1-65535)"
    fi

    if systemctl is-active --quiet zivpn; then
        echo -e " 🔹 ZiVPN UDP   : Activo (Puerto 25000)"
    fi

    if systemctl is-active --quiet stunnel4; then
        echo -e " 🔹 SSL / TLS   : 443, 444"
    fi

    if systemctl is-active --quiet openvpn@server-tcp || systemctl is-active --quiet openvpn@server || systemctl is-active --quiet openvpn; then
        OVPN_PATH=$(find /root /etc/vps-manager/openvpn_files /var/www/html /home /etc/openvpn -maxdepth 3 -name "*.ovpn" 2>/dev/null | head -n 1)
        
        if [ -n "$OVPN_PATH" ]; then
            OVPN_NAME=$(basename "$OVPN_PATH")
            mkdir -p /etc/vps-manager/openvpn_files
            cp -f "$OVPN_PATH" "/etc/vps-manager/openvpn_files/$OVPN_NAME" 2>/dev/null
            chmod 644 "/etc/vps-manager/openvpn_files/$OVPN_NAME" 2>/dev/null
            PORT_WEB="2081"
            echo -e " 🔹 OpenVPN     : ACTIVO"
            echo -e " 📥 Link OVPN   : http://$IP:$PORT_WEB/$OVPN_NAME"
        else
            echo -e " 🔹 OpenVPN     : ACTIVO (Debes crear tu perfil .ovpn)"
        fi
    fi

    if pgrep -x "dns-server" > /dev/null || pgrep -f "dnstt-server" > /dev/null || systemctl is-active --quiet slowdns; then
        SL_KEY="No configurada"
        NS_DOMAIN="No configurado"
        for path in /etc/slowdns/server.pub /root/server.pub /root/Slowdns/server.pub /etc/slowdns/pub.key; do
            if [ -f "$path" ]; then SL_KEY=$(cat "$path"); break; fi
        done
        for path in /etc/slowdns/domain.ns /root/domain.ns /root/Slowdns/domain.ns; do
            if [ -f "$path" ]; then NS_DOMAIN=$(cat "$path"); break; fi
        done
        echo -e " 🔹 SlowDNS     : ACTIVO"
        echo -e " 📝 NS Domain   : $NS_DOMAIN"
        echo -e " 🔑 Pub Key     : $SL_KEY"
    fi
    
    # Detección y Generación de Link Hysteria 2
    if systemctl is-active --quiet hysteria || systemctl is-active --quiet hysteria-server; then
        HY_CONF="/etc/vps-manager/hysteria/config.yaml"
        [ ! -f "$HY_CONF" ] && HY_CONF="/etc/hysteria/config.yaml"
        if [ -f "$HY_CONF" ]; then
            HY_PORT=$(grep "listen:" "$HY_CONF" | grep -oP ':\K[0-9]+' | head -1)
            HY_OBFS=$(grep -A 2 "salamander:" "$HY_CONF" | grep "password:" | awk '{print $2}' | tr -d '"' | tr -d "'")
            
            if [ -s /etc/vps-manager/domain.txt ]; then
                HY_DOMAIN=$(cat /etc/vps-manager/domain.txt)
            elif [ -s /etc/vps-manager/dominio ]; then
                HY_DOMAIN=$(cat /etc/vps-manager/dominio)
            else
                HY_DOMAIN=$IP
            fi
            
            LINK_HY2="hy2://$HY_OBFS@$IP:$HY_PORT?insecure=1&sni=$HY_DOMAIN&obfs=salamander&obfs-password=$HY_OBFS#${username}_HY2"
            
            echo -e " 🔹 Hysteria 2  : ACTIVO (Puerto $HY_PORT)"
            echo -e " 📥 Link HY2    : \033[4;37m$LINK_HY2\033[0m"
        else
            echo -e " 🔹 Hysteria 2  : ACTIVO (Sin archivo de configuración legible)"
        fi
    fi

    echo -e "${C_CYAN}======================================================${C_NC}"
    read -p " Presiona Enter para continuar..."
}

# 2. Eliminar Usuario y Purga
eliminar_usuario() {
    while true; do
        clear
        echo -e "${C_ORANGE}======================================================${C_NC}"
        echo -e " ❌ ${C_RED}MENÚ DE ELIMINACIÓN DE USUARIOS${C_NC}"
        echo -e "${C_ORANGE}======================================================${C_NC}"
        echo -e " ${C_CYAN}1.${C_NC} 🗑️  Eliminar un usuario específico"
        echo -e " ${C_CYAN}2.${C_NC} 🧹 Purga automática (Eliminar TODOS los vencidos)"
        echo -e " ${C_RED}0.${C_NC} 🚪 Volver"
        echo -e "${C_ORANGE}======================================================${C_NC}"
        read -p " Selecciona una opción: " opc_elim

        case $opc_elim in
            1)
                echo -e "\n${C_BLUE}--- Usuarios Registrados ---${C_NC}"
                awk -F: '$3>=1000 && $1!="nobody" && $1!="ubuntu" {print " 👤 " $1}' /etc/passwd
                echo -e "----------------------------"
                
                read -p " Usuario a eliminar: " user_del
                if id "$user_del" &>/dev/null; then
                    pkill -u "$user_del" 2>/dev/null
                    userdel --force "$user_del" 2>/dev/null
                    rm -f /root/usuarios/$user_del.limit
                    rm -f /root/usuarios/hwid/$user_del.hwid
                    rm -f /root/usuarios/token/$user_del.token
                    rm -f "/etc/vps-manager/banner_${user_del}.net"
                    actualizar_banner_usuario
                    echo -e "${C_GREEN}[✔] Usuario $user_del eliminado exitosamente.${C_NC}"
                else
                    echo -e "${C_RED}[✘] El usuario '$user_del' no existe.${C_NC}"
                fi
                read -p " Presiona Enter para continuar..." foo
                ;;
            2)
                echo -e "\n${C_ORANGE}Buscando y eliminando usuarios vencidos...${C_NC}"
                eliminados=0
                for user in $(awk -F: '$3>=1000 && $1!="nobody" && $1!="ubuntu" {print $1}' /etc/passwd); do
                    exp_raw=$(chage -l "$user" | grep "Account expires" | cut -d: -f2 | sed 's/^ *//')
                    if [[ "$exp_raw" != "never" ]]; then
                        exp_epoch=$(date -d "$exp_raw" +%s 2>/dev/null)
                        now_epoch=$(date -d "today 00:00:00" +%s)
                        if [[ -n "$exp_epoch" ]]; then
                            dias=$(( (exp_epoch - now_epoch) / 86400 ))
                            if (( dias <= 0 )); then
                                pkill -u "$user" 2>/dev/null
                                userdel --force "$user" 2>/dev/null
                                rm -f /root/usuarios/$user.limit
                                rm -f /root/usuarios/hwid/$user.hwid
                                rm -f /root/usuarios/token/$user.token
                                rm -f "/etc/vps-manager/banner_${user}.net"
                                echo -e " 🗑️  Usuario eliminado: ${C_RED}$user${C_NC}"
                                ((eliminados++))
                            fi
                        fi
                    fi
                done
                
                if (( eliminados > 0 )); then
                    actualizar_banner_usuario
                    echo -e "${C_GREEN}[✔] Limpieza completada. $eliminados usuario(s) vencido(s) eliminado(s).${C_NC}"
                else
                    echo -e "${C_GREEN}[✔] No se encontraron usuarios vencidos.${C_NC}"
                fi
                read -p " Presiona Enter para continuar..." foo
                ;;
            0) break ;;
            *) echo -e "${C_RED}Opción inválida${C_NC}"; sleep 1 ;;
        esac
    done
}

# 3. Renovar Usuario (Con Acumulación de Días)
renovar_usuario() {
    clear
    echo -e "${C_ORANGE}======================================================${C_NC}"
    echo -e "               ${C_GREEN}[ RENOVAR USUARIO ]${C_NC}"
    echo -e "${C_ORANGE}======================================================${C_NC}"
    read -p " Nombre de usuario: " username
    
    if ! id "$username" &>/dev/null; then
        echo -e "\n ${C_RED}[!] Error: El usuario '$username' no existe.${C_NC}"
        sleep 2
        return
    fi

    read -p " Días a agregar (se sumarán al saldo actual): " dias
    
    exp_date=$(chage -l "$username" | grep "Account expires" | cut -d: -f2 | sed 's/^[ \t]*//')
    
    if [[ "$exp_date" == "never" ]]; then
        base_date="today"
    else
        exp_epoch=$(date -d "$exp_date" +%s 2>/dev/null)
        now_epoch=$(date -d "today 00:00:00" +%s)
        
        if [[ -n "$exp_epoch" ]] && (( exp_epoch > now_epoch )); then
            base_date="$exp_date"
        else
            base_date="today"
        fi
    fi

    nueva_fecha=$(date -d "$base_date + $dias days" +%Y-%m-%d)
    fecha_visual=$(date -d "$base_date + $dias days" +%d/%m/%Y)
    
    chage -E "$nueva_fecha" "$username"
    actualizar_banner_usuario
    
    echo -e "\n ${C_GREEN}✅ Usuario renovado exitosamente (Banner actualizado).${C_NC}"
    if [[ "$base_date" == "today" ]]; then
        echo -e " 📅 Nueva fecha de vencimiento: ${C_CYAN}$fecha_visual${C_NC} (Calculado desde hoy)"
    else
        echo -e " 📅 Nueva fecha de vencimiento: ${C_CYAN}$fecha_visual${C_NC} (Días acumulados)"
    fi
    
    read -p " Presiona Enter para continuar..."
}

# 4. Cambiar Contraseña
cambiar_contrasena() {
    clear
    echo -e "${C_ORANGE}======================================================${C_NC}"
    echo -e "             ${C_CYAN}[ CAMBIAR CONTRASEÑA ]${C_NC}"
    echo -e "${C_ORANGE}======================================================${C_NC}"
    read -p " Nombre de usuario: " username
    
    if ! id "$username" &>/dev/null; then
        echo -e "\n ${C_RED}[!] Error: El usuario '$username' no existe.${C_NC}"
        sleep 2
        return
    fi

    read -p " Nueva contraseña: " password
    echo "$username:$password" | chpasswd
    
    echo -e "\n ${C_GREEN}✅ Contraseña actualizada correctamente.${C_NC}"
    read -p " Presiona Enter para continuar..."
}

# 5. Límite de Conexiones
limite_conexiones() {
    clear
    echo -e "${C_ORANGE}======================================================${C_NC}"
    echo -e "          ${C_BLUE}[ ESTABLECER LÍMITE DE CONEXIONES ]${C_NC}"
    echo -e "${C_ORANGE}======================================================${C_NC}"
    read -p " Nombre de usuario: " username
    
    if ! id "$username" &>/dev/null; then
        echo -e "\n ${C_RED}[!] Error: El usuario '$username' no existe.${C_NC}"
        sleep 2
        return
    fi

    read -p " Nuevo límite de conexiones: " limite
    mkdir -p /root/usuarios
    echo "$limite" > /root/usuarios/$username.limit
    
    echo -e "\n ${C_GREEN}✅ Límite actualizado a $limite conexión(es).${C_NC}"
    read -p " Presiona Enter para continuar..."
}

# 6. Detalles de Usuario
detalles_usuario() {
    clear
    echo -e "${C_ORANGE}======================================================${C_NC}"
    echo -e "               ${C_CYAN}[ DETALLES DE USUARIO ]${C_NC}"
    echo -e "${C_ORANGE}======================================================${C_NC}"
    read -p " Nombre de usuario: " username
    
    if ! id "$username" &>/dev/null; then
        echo -e "\n ${C_RED}[!] Error: El usuario '$username' no existe.${C_NC}"
        sleep 2
        return
    fi

    exp_date=$(chage -l "$username" | grep "Account expires" | cut -d: -f2 | sed 's/^ *//')
    status=$(passwd -S "$username" | awk '{print $2}')
    limit="Sin límite"
    
    [ -f "/root/usuarios/$username.limit" ] && limit=$(cat "/root/usuarios/$username.limit")
    [ "$status" = "L" ] && st="${C_RED}Bloqueado${C_NC}" || st="${C_GREEN}Activo${C_NC}"

    dias_str=""
    if [[ "$exp_date" != "never" ]]; then
        exp_epoch=$(date -d "$exp_date" +%s 2>/dev/null)
        now_epoch=$(date -d "today 00:00:00" +%s)
        if [[ -n "$exp_epoch" ]]; then
            dias=$(( (exp_epoch - now_epoch) / 86400 ))
            if (( dias <= 0 )); then
                dias_str="[ ${C_RED}Vencido: 0 días${C_NC} ]"
            else
                dias_str="[ ${C_GREEN}Activo: $dias días${C_NC} ]"
            fi
        fi
    else
        dias_str="[ ${C_GREEN}Ilimitado${C_NC} ]"
    fi

    echo -e "\n 👤 Usuario   : $username"
    echo -e " 📅 Vence     : $exp_date $dias_str"
    echo -e " ⚙️ Límite    : $limit"
    echo -e " 🛡️ Estado    : $st"
    
    if [ -f "/root/usuarios/hwid/$username.hwid" ]; then
        echo -e " 📱 HWID      : $(cat /root/usuarios/hwid/$username.hwid)"
    elif [ -f "/root/usuarios/token/$username.token" ]; then
        echo -e " 🎫 Token     : $(cat /root/usuarios/token/$username.token)"
    fi
    
    echo -e "${C_ORANGE}======================================================${C_NC}"
    read -p " Presiona Enter para continuar..."
}

# 7. Bloquear / Desbloquear Cuenta
bloquear_usuario() {
    clear
    echo -e "${C_ORANGE}======================================================${C_NC}"
    echo -e "          ${C_RED}[ BLOQUEAR / DESBLOQUEAR CUENTA ]${C_NC}"
    echo -e "${C_ORANGE}======================================================${C_NC}"
    read -p " Nombre de usuario: " username
    
    if ! id "$username" &>/dev/null; then
        echo -e "\n ${C_RED}[!] Error: El usuario '$username' no existe.${C_NC}"
        sleep 2
        return
    fi

    echo -e "\n 1. 🔒 Bloquear cuenta"
    echo -e " 2. 🔓 Desbloquear cuenta"
    read -p " Opción: " block_op

    if [ "$block_op" = "1" ]; then
        pkill -u "$username" 2>/dev/null
        usermod -L "$username"
        echo -e "\n ${C_GREEN}✅ Usuario '$username' bloqueado.${C_NC}"
    elif [ "$block_op" = "2" ]; then
        usermod -U "$username"
        echo -e "\n ${C_GREEN}✅ Usuario '$username' desbloqueado.${C_NC}"
    else
        echo -e "\n ${C_RED}Opción inválida.${C_NC}"
    fi
    read -p " Presiona Enter para continuar..."
}

# 8. Lista de Usuarios y Días Restantes
lista_usuarios() {
    clear
    echo -e "${C_ORANGE}======================================================${C_NC}"
    echo -e "          ${C_CYAN}[ LISTA DE USUARIOS Y VENCIMIENTOS ]${C_NC}"
    echo -e "${C_ORANGE}======================================================${C_NC}"
    
    for user in $(awk -F: '$3>=1000 && $1!="nobody" && $1!="ubuntu" {print $1}' /etc/passwd); do
        exp_raw=$(chage -l "$user" | grep "Account expires" | cut -d: -f2 | sed 's/^ *//')
        
        if [[ "$exp_raw" == "never" ]]; then
            echo -e " 👤 ${C_CYAN}$user${C_NC} -> ⏳ ${C_GREEN}Ilimitado${C_NC}"
        else
            exp_epoch=$(date -d "$exp_raw" +%s 2>/dev/null)
            now_epoch=$(date -d "today 00:00:00" +%s)
            
            if [[ -n "$exp_epoch" ]]; then
                dias=$(( (exp_epoch - now_epoch) / 86400 ))
                if (( dias <= 0 )); then
                    echo -e " 👤 ${C_CYAN}$user${C_NC} -> ⏳ $exp_raw [ ${C_RED}Vencido: 0 días${C_NC} ]"
                else
                    echo -e " 👤 ${C_CYAN}$user${C_NC} -> ⏳ $exp_raw [ ${C_GREEN}Activo: $dias días${C_NC} ]"
                fi
            else
                echo -e " 👤 ${C_CYAN}$user${C_NC} -> ⏳ Fecha inválida"
            fi
        fi
    done
    echo -e "${C_ORANGE}======================================================${C_NC}"
    read -p " Presiona Enter para continuar..."
}

# 9. Usuarios Online (Monitor Avanzado con Tráfico en Vivo)
usuarios_online() {
    local SEP="${C_ORANGE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_NC}"
    clear
    echo -e "$SEP"
    echo -e "       ${C_CYAN}[ MONITOR DE USUARIOS EN LÍNEA ]${C_NC}"
    echo -e "$SEP"

    # Detectar usuarios conectados sin cancelar el comando sshd
    local lista_conectados=$(ps -eo uid,user:30,comm | awk '$1 >= 1000 && $1 != 65534 && $2 != "ubuntu" && ($3 ~ /sshd|dropbear/) {print $2}' | sort -u)
    local count=1

    for user in $lista_conectados; do
        if id "$user" &>/dev/null; then
            
            # 1. Calcular expiración y días
            local exp_date=$(chage -l "$user" | grep "Account expires" | cut -d: -f2 | sed 's/^[ \t]*//')
            local vence=""
            local dias_restantes=""
            local estado=""
            
            if [[ "$exp_date" == "never" ]]; then
                vence="Nunca"
                dias_restantes="Ilimitado"
                estado="🔓 ${C_GREEN}ACTIVO${C_NC}"
            else
                local vence_fmt=$(date -d "$exp_date" "+%d/%b" 2>/dev/null)
                local exp_sec=$(date -d "$exp_date" +%s 2>/dev/null)
                local hoy_sec=$(date +%s)
                local diff=$((exp_sec - hoy_sec))
                local dias=$((diff / 86400))

                if [ "$dias" -lt 0 ]; then
                    vence="${C_RED}${vence_fmt}${C_NC}"
                    dias_restantes="Expirado"
                    estado="🔒 ${C_RED}VENCIDO${C_NC}"
                else
                    vence="${C_PURPLE}${vence_fmt}${C_NC}"
                    dias_restantes="${dias} días"
                    estado="🔓 ${C_GREEN}ACTIVO${C_NC}"
                fi
            fi

            # 2. Contar conexiones activas del usuario y su límite
            local num_con=$(ps -eo user:30,comm | awk -v u="$user" '$1 == u && ($2 ~ /sshd|dropbear/) {c++} END {print c+0}')
            local limite="∞"
            if [ -f "/root/usuarios/${user}.limit" ]; then
                limite=$(cat "/root/usuarios/${user}.limit")
            fi

            # 3. Medir el consumo real de datos de las sesiones del usuario (/proc/pid/io)
            local user_bytes=0
            for pid in $(ps -eo user:30,pid,comm | awk -v u="$user" '$1 == u && ($3 ~ /sshd|dropbear/) {print $2}'); do
                if [ -r "/proc/$pid/io" ]; then
                    local pio=$(awk '/^(rchar|wchar):/ {sum += $2} END {printf "%.0f", sum}' "/proc/$pid/io" 2>/dev/null)
                    user_bytes=$((user_bytes + ${pio:-0}))
                fi
            done
            local consumo=$(format_bytes "$user_bytes")

            echo -e "${C_CYAN}${count}.${C_NC} 👤 ${C_WHITE}${user}${C_NC}                 ${C_CYAN}SSH (${num_con} con.)${C_NC}"
            echo -e "   📅 ${C_GREEN}Vence:${C_NC} $vence ${C_GRAY}($dias_restantes) |${C_NC} $estado"
            echo -e "   📊 ${C_CYAN}$consumo${C_NC} ${C_GRAY}(Lim: $limite)${C_NC}   ${C_CYAN}● ONLINE${C_NC}"
            echo -e "$SEP"
            
            count=$((count + 1))
        fi
    done

    if [ "$count" -eq 1 ]; then
        echo -e "   ${C_RED}No hay usuarios conectados en este momento.${C_NC}"
        echo -e "$SEP"
    fi

    echo -e ""
    read -p " Presiona Enter para continuar..." foo
}

# ==========================================
# Menú Interactivo de Usuarios (Dashboard)
# ==========================================
while true; do
    clear
    
    # 1. Cálculos en vivo para el Dashboard (Solo usuarios del panel UID >= 1000)
    total_users=0; vencidos=0; activos=0; por_vencer=0; bloqueados=0
    ultimo_user="-"
    
    for user in $(awk -F: '$3>=1000 && $1!="nobody" && $1!="ubuntu" {print $1}' /etc/passwd); do
        ((total_users++))
        ultimo_user="$user"
        
        # Verificar si está bloqueado
        st_lock=$(passwd -S "$user" 2>/dev/null | awk '{print $2}')
        if [ "$st_lock" = "L" ] || [ "$st_lock" = "LK" ]; then
            ((bloqueados++))
        fi

        # Verificar fechas de vencimiento
        exp_raw=$(chage -l "$user" | grep "Account expires" | cut -d: -f2 | sed 's/^ *//')
        if [[ "$exp_raw" != "never" ]]; then
            exp_epoch=$(date -d "$exp_raw" +%s 2>/dev/null)
            now_epoch=$(date -d "today 00:00:00" +%s)
            if [[ -n "$exp_epoch" ]]; then
                dias=$(( (exp_epoch - now_epoch) / 86400 ))
                if (( dias <= 0 )); then
                    ((vencidos++))
                else
                    ((activos++))
                    if (( dias <= 7 )); then ((por_vencer++)); fi
                fi
            fi
        else
            ((activos++))
        fi
    done
    
    # 2. Detección real de Usuarios En Línea y Conexiones Totales
    online_users=$(ps -eo uid,user:30,comm | awk '$1 >= 1000 && $1 != 65534 && $2 != "ubuntu" && ($3 ~ /sshd|dropbear/) {print $2}' | sort -u | wc -l)
    conexiones_totales=$(ps -eo uid,user:30,comm | awk '$1 >= 1000 && $1 != 65534 && $2 != "ubuntu" && ($3 ~ /sshd|dropbear/) {print $2}' | wc -l)
    
    # 3. Verificación de excesos Multilogin en tiempo real
    excesos=0
    for u_on in $(ps -eo uid,user:30,comm | awk '$1 >= 1000 && $1 != 65534 && $2 != "ubuntu" && ($3 ~ /sshd|dropbear/) {print $2}' | sort -u); do
        u_con=$(ps -eo user:30,comm | awk -v u="$u_on" '$1 == u && ($2 ~ /sshd|dropbear/) {c++} END {print c+0}')
        if [ -f "/root/usuarios/${u_on}.limit" ]; then
            u_lim=$(cat "/root/usuarios/${u_on}.limit")
            if [[ "$u_lim" =~ ^[0-9]+$ ]] && (( u_con > u_lim )); then
                ((excesos++))
            fi
        fi
    done
    if (( excesos > 0 )); then
        multilogin="${excesos} exceso(s)"
    else
        multilogin="sin excesos"
    fi

    # 4. Cálculo nativo de Tráfico Total del Servidor (MB / GB / TB desde /proc/net/dev)
    total_net_bytes=$(awk 'NR>2 {sub(/:/, " ", $0); if ($1 != "lo" && $1 !~ /^tun|^tap|^docker|^veth/) {rx+=$2; tx+=$10}} END {printf "%.0f", rx+tx}' /proc/net/dev 2>/dev/null)
    trafico=$(format_bytes "${total_net_bytes:-0}")

    # 5. Renderizado Visual (Con bordes alineados)
    echo -e "${C_CYAN}======================================================${C_NC}"
    echo -e " 👤 ${C_CYAN}GESTIÓN DE CUENTAS SSH / VPN${C_NC}"
    echo -e "${C_CYAN}======================================================${C_NC}"
    
    printf "${C_CYAN}╭─ ${BG_BOX} CUENTAS ${C_NC}${C_CYAN} ───────────╮  ╭─ ${BG_BOX} ACTIVIDAD ${C_NC}${C_CYAN} ───────────╮\n"
    printf "${C_CYAN}│${C_NC} TOTAL        ${C_WHITE}%-9s${C_NC}${C_CYAN}│  │${C_NC} EN LÍNEA     ${C_GREEN}%-11s${C_NC}${C_CYAN}│\n" "$total_users" "$online_users"
    printf "${C_CYAN}│${C_NC} ACTIVOS      ${C_GREEN}%-9s${C_NC}${C_CYAN}│  │${C_NC} CONEXIONES   ${C_WHITE}%-11s${C_NC}${C_CYAN}│\n" "$activos" "$conexiones_totales"
    printf "${C_CYAN}│${C_NC} POR VENCER   ${C_YELLOW}%-2s${C_NC} %-6s${C_CYAN}│  │${C_NC} MULTILOGIN   ${C_WHITE}%-11s${C_NC}${C_CYAN}│\n" "$por_vencer" "en 7 d" "$multilogin"
    printf "${C_CYAN}│${C_NC} VENCIDOS     ${C_RED}%-9s${C_NC}${C_CYAN}│  │${C_NC} ÚLTIMO       ${C_CYAN}%-11s${C_NC}${C_CYAN}│\n" "$vencidos" "${ultimo_user:0:11}"
    printf "${C_CYAN}│${C_NC} BLOQUEADOS   ${C_RED}%-9s${C_NC}${C_CYAN}│  │${C_NC} TRÁFICO      ${C_WHITE}%-11s${C_NC}${C_CYAN}│\n" "$bloqueados" "$trafico"
    printf "${C_CYAN}╰───────────────────────╯  ╰─────────────────────────╯${C_NC}\n"

    echo -e "${C_CYAN}======================================================${C_NC}"
    echo -e " ${C_WHITE}1.${C_NC} ➕ Crear nuevo usuario"
    echo -e " ${C_WHITE}2.${C_NC} ❌ Eliminar usuario"
    echo -e " ${C_WHITE}3.${C_NC} 🔄 Renovar usuario (Extender días)"
    echo -e " ${C_WHITE}4.${C_NC} 🔑 Cambiar contraseña"
    echo -e " ${C_WHITE}5.${C_NC} ⚙️ Establecer límite de conexiones"
    echo -e " ${C_WHITE}6.${C_NC} 📋 Detalles de un usuario"
    echo -e " ${C_WHITE}7.${C_NC} 🔓 Bloquear / Desbloquear cuenta"
    echo -e " ${C_WHITE}8.${C_NC} 👥 Lista de usuarios y vencimientos"
    echo -e " ${C_WHITE}9.${C_NC} 📡 Ver usuarios conectados en línea"
    echo -e " ${C_RED}0.${C_NC} 🚪 VOLVER al Menú Principal"
    echo -e "${C_CYAN}======================================================${C_NC}"
    
    read -p " Selecciona una opción: " user_op
    
    case $user_op in
        1) crear_usuario ;;
        2) eliminar_usuario ;;
        3) renovar_usuario ;;
        4) cambiar_contrasena ;;
        5) limite_conexiones ;;
        6) detalles_usuario ;;
        7) bloquear_usuario ;;
        8) lista_usuarios ;;
        9) usuarios_online ;;
        0) break ;;
        *) echo -e "${C_RED}Opción inválida.${C_NC}"; sleep 1 ;;
    esac
done
