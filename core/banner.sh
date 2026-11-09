#!/bin/bash
# =========================================================================
# Módulo: Configurador de Banner HTML + Datos de Usuario y Vencimiento
# =========================================================================
export LANG=en_US.UTF-8

C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_CYAN='\033[1;36m'
C_WHITE='\033[1;37m'
C_NC='\033[0m'

ARCHIVO_BANNER="/etc/issue.net"
BASE_BANNER="/etc/vps-manager/banner_base.html"
SSHD_CONFIG="/etc/ssh/sshd_config"
SYNC_BIN="/usr/local/bin/sync-banners"

mkdir -p /etc/vps-manager

# Si existe un banner previo y aún no hay base guardada, respaldarlo como base
if [ -s "$ARCHIVO_BANNER" ] && [ ! -f "$BASE_BANNER" ]; then
    sed '/<!-- INFO_USUARIO -->/,$d' "$ARCHIVO_BANNER" > "$BASE_BANNER"
fi

instalar_motor_banners() {
    cat << 'SYNCEOF' > "$SYNC_BIN"
#!/bin/bash
export LANG=en_US.UTF-8
ARCHIVO_BANNER="/etc/issue.net"
BASE_BANNER="/etc/vps-manager/banner_base.html"
SSHD_CONFIG="/etc/ssh/sshd_config"
HASH_FILE="/etc/vps-manager/.banner_hash"

mkdir -p /etc/vps-manager
touch "$ARCHIVO_BANNER"
[ ! -f "$BASE_BANNER" ] && cp -f "$ARCHIVO_BANNER" "$BASE_BANNER"

# Calcular huella actual de usuarios, fechas de expiración y banner base
CURRENT_HASH=$( (awk -F: '$3 >= 1000 && $1 != "nobody" && $1 != "ubuntu" {print $1}' /etc/passwd | while read -r u; do
    exp=$(awk -F: -v usr="$u" '$1 == usr {print $8}' /etc/shadow 2>/dev/null)
    echo "$u:$exp"
done; cat "$BASE_BANNER" 2>/dev/null) | md5sum | awk '{print $1}' )

if [ "$1" != "--force" ] && [ -f "$HASH_FILE" ] && [ "$(cat "$HASH_FILE" 2>/dev/null)" = "$CURRENT_HASH" ]; then
    exit 0
fi

echo "$CURRENT_HASH" > "$HASH_FILE"
cp -f "$BASE_BANNER" "$ARCHIVO_BANNER"
chmod 644 "$ARCHIVO_BANNER"

# Limpiar bloque anterior de usuarios en sshd_config
sed -i '/# === INICIO BANNERS GOLBERT ===/,/# === FIN BANNERS GOLBERT ===/d' "$SSHD_CONFIG"

# Asegurar Banner general por defecto antes de los bloques Match
if grep -qE "^[[:space:]]*#?[[:space:]]*Banner[[:space:]]+" "$SSHD_CONFIG"; then
    sed -i -E "s|^[[:space:]]*#?[[:space:]]*Banner[[:space:]]+.*|Banner $ARCHIVO_BANNER|g" "$SSHD_CONFIG"
else
    echo "Banner $ARCHIVO_BANNER" >> "$SSHD_CONFIG"
fi

# Si el banner base está vacío, limpiar banners individuales y recargar
if [ ! -s "$BASE_BANNER" ]; then
    rm -f /etc/vps-manager/banner_*.net
    systemctl reload ssh sshd 2>/dev/null || systemctl restart ssh sshd 2>/dev/null
    exit 0
fi

NOW_SEC=$(date +%s)
MATCH_BLOCK="# === INICIO BANNERS GOLBERT ==="

while IFS=: read -r user _ uid _; do
    if [ "$uid" -ge 1000 ] && [ "$user" != "nobody" ] && [ "$user" != "ubuntu" ]; then
        exp_days=$(awk -F: -v u="$user" '$1 == u {print $8}' /etc/shadow 2>/dev/null)
        if [[ "$exp_days" =~ ^[0-9]+$ ]]; then
            exp_sec=$(( exp_days * 86400 ))
            exp_date=$(date -d "@$exp_sec" '+%d/%m/%Y' 2>/dev/null)
            dias_rest=$(( (exp_sec - NOW_SEC + 86399) / 86400 ))
            [ "$dias_rest" -lt 0 ] && dias_rest=0
            exp_text="${exp_date} (${dias_rest} días)"
        else
            exp_text="Ilimitado"
        fi

        bfile="/etc/vps-manager/banner_${user}.net"
        cat "$BASE_BANNER" > "$bfile"
        cat << USREOF >> "$bfile"
<!-- INFO_USUARIO -->
<font color="#00ffff"><b>=======================</b></font><br>
<font color="#ffffff"><b>👤 Usuario :</b></font> <font color="#00ff00"><b>${user}</b></font><br>
<font color="#ffffff"><b>📅 Vence   :</b></font> <font color="#ffcc00"><b>${exp_text}</b></font><br>
<font color="#00ffff"><b>=======================</b></font><br>
USREOF
        chmod 644 "$bfile"
        MATCH_BLOCK="${MATCH_BLOCK}\nMatch User ${user}\n    Banner ${bfile}"
    fi
done < /etc/passwd

MATCH_BLOCK="${MATCH_BLOCK}\n# === FIN BANNERS GOLBERT ==="
echo -e "\n$MATCH_BLOCK" >> "$SSHD_CONFIG"

systemctl reload ssh sshd 2>/dev/null || systemctl restart ssh sshd 2>/dev/null
SYNCEOF

    chmod +x "$SYNC_BIN"

    # Tarea programada cada minuto para detectar nuevos usuarios creados en el panel o bot
    cat << 'CRONEOF' > /etc/cron.d/golbert_banners
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
* * * * * root /usr/local/bin/sync-banners >/dev/null 2>&1
CRONEOF
    chmod 644 /etc/cron.d/golbert_banners
}

activar_banner_sshd() {
    instalar_motor_banners
    "$SYNC_BIN" --force
    systemctl restart ssh-ws ws-python 2>/dev/null
}

while true; do
    clear
    echo -e "${C_CYAN}========================================================${C_NC}"
    echo -e " 🎨 ${C_YELLOW}CONFIGURADOR DE BANNER HTML GOLBERT VPS${C_NC}"
    echo -e "${C_CYAN}========================================================${C_NC}"
    echo -e " ${C_CYAN}1.${C_NC} 📝 Pegar o escribir Banner HTML personalizado"
    echo -e " ${C_CYAN}2.${C_NC} ⚡ Aplicar Plantilla Oficial Golbert VPS (1 Clic)"
    echo -e " ${C_CYAN}3.${C_NC} 👁️  Ver Banner actual instalado"
    echo -e " ${C_CYAN}4.${C_NC} 🗑️  Dejar Banner en blanco (Eliminar)"
    echo -e " ${C_CYAN}5.${C_NC} 🔄 Sincronizar Usuarios y Vencimientos Ahora"
    echo -e " ${C_RED}0.${C_NC} 🚪 Volver al Menú"
    echo -e "${C_CYAN}========================================================${C_NC}"
    read -p " Selecciona una opción: " opc

    case $opc in
        1)
            clear
            echo -e "${C_CYAN}========================================================${C_NC}"
            echo -e "${C_YELLOW}Pega o escribe tu código HTML de Banner.${C_NC}"
            echo -e "Cuando termines, escribe la palabra ${C_GREEN}FIN${C_NC} en una línea"
            echo -e "nueva y presiona Enter para guardar:"
            echo -e "${C_CYAN}========================================================${C_NC}"

            > "$BASE_BANNER.tmp"
            while IFS= read -r linea; do
                [[ "${linea^^}" == "FIN" ]] && break
                echo "$linea" >> "$BASE_BANNER.tmp"
            done

            if [ -s "$BASE_BANNER.tmp" ]; then
                mv -f "$BASE_BANNER.tmp" "$BASE_BANNER"
                cp -f "$BASE_BANNER" "$ARCHIVO_BANNER"
                echo -e "\n${C_YELLOW}[*] Aplicando diseño y vinculando usuarios con su fecha de vencimiento...${C_NC}"
                activar_banner_sshd
                echo -e "${C_GREEN}[✔] ¡Banner personalizado + Datos de Usuario activados exitosamente!${C_NC}"
            else
                rm -f "$BASE_BANNER.tmp"
                echo -e "\n${C_RED}[!] No se ingresó texto. Se conservó el banner anterior.${C_NC}"
            fi
            read -p " Presiona Enter para continuar..." foo
            ;;
        2)
            clear
            cat << 'EOF' > "$BASE_BANNER"
<br>
<font color="#00ffff"><b>━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━</b></font><br>
<font color="#ffcc00"><b>   ★ GOLBERT VPS PREMIUM V7.0 ★   </b></font><br>
<font color="#00ffff"><b>━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━</b></font><br>
<font color="#00ff00"><b>✔ Servidor Ultra Rápido Activo</b></font><br>
<font color="#ffffff"><b>⛔ Prohibido Torrent / DDoS / Spam</b></font><br>
<font color="#ffffff"><b>✈️ Telegram:</b></font> <font color="#00ffff">@golbert_service</font><br>
<font color="#ffffff"><b>📢 Grupo:</b></font> <font color="#00ffff">t.me/vpsgratis2026</font><br>
<font color="#ffffff"><b>📞 WhatsApp:</b></font> <font color="#00ff00">+51960084993</font><br>
<font color="#00ffff"><b>━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━</b></font><br>
EOF
            cp -f "$BASE_BANNER" "$ARCHIVO_BANNER"
            activar_banner_sshd
            echo -e "${C_GREEN}[✔] ¡Plantilla Oficial + Información de Usuario y Vencimiento activada!${C_NC}\n"
            cat "$ARCHIVO_BANNER"
            echo -e "${C_YELLOW}(Al conectarse cada cliente, debajo del banner verá su Usuario y Fecha de Vencimiento)${C_NC}\n"
            read -p " Presiona Enter para continuar..." foo
            ;;
        3)
            clear
            echo -e "${C_CYAN}================ BANNER BASE (/etc/issue.net) ================${C_NC}\n"
            if [ -s "$ARCHIVO_BANNER" ]; then
                cat "$ARCHIVO_BANNER"
                echo -e "\n${C_CYAN}--- Ejemplo de bloque dinámico que ve cada cliente al conectar ---${C_NC}"
                echo -e '<font color="#00ffff"><b>=======================</b></font><br>'
                echo -e '<font color="#ffffff"><b>👤 Usuario :</b></font> <font color="#00ff00"><b>cliente01</b></font><br>'
                echo -e '<font color="#ffffff"><b>📅 Vence   :</b></font> <font color="#ffcc00"><b>08/12/2026 (30 días)</b></font><br>'
                echo -e '<font color="#00ffff"><b>=======================</b></font><br>'
            else
                echo -e "${C_YELLOW}(El archivo de banner está vacío actualmente)${C_NC}"
            fi
            echo -e "\n${C_CYAN}==============================================================${C_NC}"
            read -p " Presiona Enter para continuar..." foo
            ;;
        4)
            clear
            > "$BASE_BANNER"
            > "$ARCHIVO_BANNER"
            activar_banner_sshd
            echo -e "${C_GREEN}[✔] Banner eliminado correctamente de todos los usuarios.${C_NC}"
            read -p " Presiona Enter para continuar..." foo
            ;;
        5)
            clear
            echo -e "${C_YELLOW}[*] Sincronizando usuarios SSH y fechas de vencimiento...${C_NC}"
            activar_banner_sshd
            echo -e "${C_GREEN}[✔] ¡Todos los usuarios tienen su banner actualizado con su vencimiento!${C_NC}"
            read -p " Presiona Enter para continuar..." foo
            ;;
        0) break ;;
        *) echo -e "${C_RED}Opción inválida.${C_NC}"; sleep 1 ;;
    esac
done
