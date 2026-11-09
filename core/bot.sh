#!/bin/bash
# ==========================================
# Módulo: Bot de Telegram (Revendedores SSH/V2Ray & Grupos Free)
# ==========================================
C_RED='\033[1;31m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_CYAN='\033[1;36m'; C_NC='\033[0m'

BOT_DIR="/etc/vps-manager/telegram_bot"
mkdir -p "$BOT_DIR"
touch "$BOT_DIR/resellers.txt"

clear
echo -e "${C_CYAN}================================================${C_NC}"
echo -e "${C_GREEN}    CONFIGURACIÓN BOT DEL PANEL (REVENDEDORES)  ${C_NC}"
echo -e "${C_CYAN}================================================${C_NC}"

if [ -f "$BOT_DIR/config.env" ]; then
    echo -e "${C_YELLOW}[+] Bot ya configurado.${C_NC}"
    read -p "¿Deseas reconfigurar Token y Admin ID? (s/n): " reconf
    if [[ "$reconf" == "s" || "$reconf" == "S" ]]; then
        rm -f "$BOT_DIR/config.env"
    else
        echo -e "${C_GREEN}Actualizando el sistema...${C_NC}"
    fi
fi

if [ ! -f "$BOT_DIR/config.env" ]; then
    read -p "Ingresa el Token del Bot (Revendedores): " TELEGRAM_TOKEN
    read -p "Ingresa tu Admin ID: " ADMIN_ID
    echo "TOKEN=\"$(echo "$TELEGRAM_TOKEN" | tr -d ' ')\"" > "$BOT_DIR/config.env"
    echo "ADMIN=\"$(echo "$ADMIN_ID" | tr -d ' ')\"" >> "$BOT_DIR/config.env"
fi

apt update -y && apt install -y python3 python3-venv python3-pip jq uuid-runtime libpam-modules >/dev/null 2>&1
cd "$BOT_DIR" || exit 1
[ ! -d "venv" ] && python3 -m venv venv
source venv/bin/activate
pip install pyTelegramBotAPI >/dev/null 2>&1

cat << 'EOF' > "$BOT_DIR/bot.py"
import os, subprocess, telebot, time, uuid, sqlite3, secrets, string, re, shutil, html, base64
from datetime import datetime, timedelta
from telebot import types

BOT_DIR = "/etc/vps-manager/telegram_bot"
RESELLERS_FILE = os.path.join(BOT_DIR, "resellers.txt")
DB_GRUPOS = os.path.join(BOT_DIR, "bot_grupos.db")
FREE_DAYS = 3
FREE_MAX_LOGINS = 2
TOKEN, ADMIN_ID = "", ""

# La estructura existente se conserva para no perder grupos ni límites diarios.
def init_db():
    conn = sqlite3.connect(DB_GRUPOS)
    cursor = conn.cursor()
    cursor.execute('''CREATE TABLE IF NOT EXISTS grupos_activos (
                        chat_id INTEGER PRIMARY KEY
                    )''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS registro_usuarios (
                        user_id INTEGER,
                        fecha TEXT,
                        PRIMARY KEY(user_id, fecha)
                    )''')
    conn.commit()
    conn.close()

init_db()

with open(os.path.join(BOT_DIR, "config.env"), "r", encoding="utf-8") as f:
    for line in f:
        if line.startswith("TOKEN="):
            TOKEN = line.split("=", 1)[1].strip().strip('"')
        elif line.startswith("ADMIN="):
            ADMIN_ID = line.split("=", 1)[1].strip().strip('"')

bot = telebot.TeleBot(TOKEN)


# ----------------------- Utilidades del Servidor y Métodos Activos -----------------------
def cmd_ok(comando):
    """Devuelve True si el comando bash finaliza con código 0 (activo)."""
    return subprocess.run(comando, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def obtener_ip_y_dominio():
    ip = subprocess.getoutput("curl -sS --max-time 4 ifconfig.me 2>/dev/null || wget -qO- -T 4 ipv4.icanhazip.com").strip()
    if not ip:
        ip = "No disponible"
    dominio = ""
    for ruta in ("/etc/vps-manager/domain.txt", "/etc/vps-manager/dominio"):
        if os.path.exists(ruta):
            try:
                with open(ruta, "r", encoding="utf-8", errors="replace") as f:
                    d = f.read().strip()
                    if d:
                        dominio = d
                        break
            except Exception:
                pass
    return ip, dominio


def obtener_metodos_activos(ip, username):
    """Detecta todos los servicios activos igual que user.sh y los formatea en HTML para Telegram."""
    lineas = [" 🔹 <b>SSH Directo :</b> <code>22</code>"]

    # WebSocket / eProxy
    if cmd_ok("systemctl is-active --quiet edu-proxy || systemctl is-active --quiet ws-proxy || systemctl is-active --quiet ws-stunnel || systemctl is-active --quiet ws-python || systemctl is-active --quiet http-proxy || systemctl is-active --quiet ws || pgrep -f -i 'proxy.py' > /dev/null || pgrep -f -i 'ws.py' > /dev/null"):
        lineas.append(" 🔹 <b>WS / eProxy :</b> Activo (Puerto <code>80</code>)")

    # BHTTP Proxy
    if cmd_ok("systemctl is-active --quiet bhttp"):
        port_bhttp = subprocess.getoutput("grep -oP '(?<=\"port\": )[0-9]+' /etc/vps-manager/bhttp/BHTTP.py 2>/dev/null | head -1").strip()
        if not port_bhttp:
            port_bhttp = "8180"
        lineas.append(f" 🔹 <b>BHTTP Proxy :</b> <code>{html.escape(port_bhttp)}</code>")

    # HCR Plain
    if cmd_ok("systemctl is-active --quiet hcr || pgrep -x 'hcr-server' > /dev/null"):
        port_hcr = subprocess.getoutput("systemctl show hcr.service -p ExecStart 2>/dev/null | grep -oP '(?<=--listen :)[0-9]+' | head -1").strip()
        if not port_hcr:
            port_hcr = "8880"
        lineas.append(f" 🔹 <b>HCR Plain   :</b> <code>{html.escape(port_hcr)}</code>")

    # UDP Custom
    if cmd_ok("systemctl is-active --quiet udp-custom || pgrep -f 'udp-custom' > /dev/null"):
        lineas.append(" 🔹 <b>UDP Custom  :</b> Activo (Puertos <code>1-65535</code>)")

    # ZiVPN UDP
    if cmd_ok("systemctl is-active --quiet zivpn || pgrep -x 'zivpn' > /dev/null"):
        lineas.append(" 🔹 <b>ZiVPN UDP   :</b> Activo (Puerto <code>25000</code>)")

    # SSL / TLS Stunnel
    if cmd_ok("systemctl is-active --quiet stunnel4 || systemctl is-active --quiet stunnel"):
        lineas.append(" 🔹 <b>SSL / TLS   :</b> <code>443, 444</code>")

    # OpenVPN
    if cmd_ok("systemctl is-active --quiet openvpn@server-tcp || systemctl is-active --quiet openvpn@server || systemctl is-active --quiet openvpn"):
        ovpn_path = subprocess.getoutput("find /root /etc/vps-manager/openvpn_files /var/www/html /home /etc/openvpn -maxdepth 3 -name '*.ovpn' 2>/dev/null | head -n 1").strip()
        if ovpn_path:
            ovpn_name = os.path.basename(ovpn_path)
            os.makedirs("/etc/vps-manager/openvpn_files", exist_ok=True)
            try:
                if os.path.abspath(ovpn_path) != os.path.abspath(f"/etc/vps-manager/openvpn_files/{ovpn_name}"):
                    shutil.copyfile(ovpn_path, f"/etc/vps-manager/openvpn_files/{ovpn_name}")
                os.chmod(f"/etc/vps-manager/openvpn_files/{ovpn_name}", 0o644)
            except Exception:
                pass
            lineas.append(" 🔹 <b>OpenVPN     :</b> ACTIVO")
            lineas.append(f" 📥 <b>Link OVPN   :</b> http://{html.escape(ip)}:2081/{html.escape(ovpn_name)}")
        else:
            lineas.append(" 🔹 <b>OpenVPN     :</b> ACTIVO")

    # SlowDNS
    if cmd_ok("pgrep -x 'dns-server' > /dev/null || pgrep -f 'sldns-server' > /dev/null || pgrep -f 'dnstt-server' > /dev/null || systemctl is-active --quiet slowdns"):
        sl_key = "No configurada"
        ns_domain = "No configurado"
        for path in ("/etc/slowdns/server.pub", "/root/server.pub", "/root/Slowdns/server.pub", "/etc/slowdns/pub.key"):
            if os.path.exists(path):
                try:
                    with open(path, "r", encoding="utf-8", errors="replace") as f:
                        val = f.read().strip()
                        if val:
                            sl_key = val
                            break
                except Exception:
                    pass
        for path in ("/etc/slowdns/domain.ns", "/root/domain.ns", "/root/Slowdns/domain.ns"):
            if os.path.exists(path):
                try:
                    with open(path, "r", encoding="utf-8", errors="replace") as f:
                        val = f.read().strip()
                        if val:
                            ns_domain = val
                            break
                except Exception:
                    pass
        lineas.append(" 🔹 <b>SlowDNS     :</b> ACTIVO")
        lineas.append(f" 📝 <b>NS Domain   :</b> <code>{html.escape(ns_domain)}</code>")
        lineas.append(f" 🔑 <b>Pub Key     :</b> <code>{html.escape(sl_key)}</code>")

    # Hysteria 2
    if cmd_ok("systemctl is-active --quiet hysteria || systemctl is-active --quiet hysteria-server"):
        hy_conf = "/etc/vps-manager/hysteria/config.yaml"
        if os.path.exists(hy_conf):
            hy_port = subprocess.getoutput(f"grep 'listen:' {hy_conf} | grep -oP ':\\K[0-9]+'").strip() or "36712"
            hy_obfs = subprocess.getoutput(f"grep -A 2 'salamander:' {hy_conf} | grep 'password:' | awk '{{print $2}}' | tr -d '\"' | tr -d \"'\"").strip()
            _, dom_hy = obtener_ip_y_dominio()
            if not dom_hy:
                dom_hy = ip
            link_hy2 = f"hy2://{hy_obfs}@{ip}:{hy_port}?insecure=1&sni={dom_hy}&obfs=salamander&obfs-password={hy_obfs}#{username}_HY2"
            lineas.append(f" 🔹 <b>Hysteria 2  :</b> ACTIVO (Puerto <code>{html.escape(hy_port)}</code>)")
            lineas.append(f" 📥 <b>Link HY2    :</b> <code>{html.escape(link_hy2)}</code>")
        else:
            lineas.append(" 🔹 <b>Hysteria 2  :</b> ACTIVO (UDP)")

    return "\n".join(lineas)


def load_resellers():
    res = {}
    if os.path.exists(RESELLERS_FILE):
        with open(RESELLERS_FILE, "r", encoding="utf-8") as f:
            for line in f:
                if ":" in line:
                    uid, creds = line.strip().split(":", 1)
                    try:
                        res[uid] = int(creds)
                    except ValueError:
                        continue
    return res


def save_resellers(res):
    with open(RESELLERS_FILE, "w", encoding="utf-8") as f:
        for uid, creds in res.items():
            f.write(f"{uid}:{creds}\n")


def is_admin(uid):
    return str(uid) == str(ADMIN_ID)


def is_reseller(uid):
    return str(uid) in load_resellers()


def get_credits(uid):
    return load_resellers().get(str(uid), 0)


def deduct_credit(uid):
    if is_admin(uid):
        return True
    res = load_resellers()
    if str(uid) in res and res[str(uid)] > 0:
        res[str(uid)] -= 1
        save_resellers(res)
        return True
    return False


# ----------------------- Gestión de grupos -----------------------
def grupo_activo(chat_id):
    conn = sqlite3.connect(DB_GRUPOS)
    cursor = conn.cursor()
    cursor.execute("SELECT 1 FROM grupos_activos WHERE chat_id = ?", (chat_id,))
    activo = cursor.fetchone() is not None
    conn.close()
    return activo


def listar_grupos_activos():
    conn = sqlite3.connect(DB_GRUPOS)
    cursor = conn.cursor()
    cursor.execute("SELECT chat_id FROM grupos_activos ORDER BY chat_id")
    grupos = [row[0] for row in cursor.fetchall()]
    conn.close()
    return grupos


def nombre_grupo(chat_id):
    try:
        grupo = bot.get_chat(chat_id)
        return grupo.title or str(chat_id)
    except Exception:
        return str(chat_id)


def teclado_eliminar_grupos(grupos):
    markup = types.InlineKeyboardMarkup()
    for chat_id in grupos:
        etiqueta = f"🗑 {nombre_grupo(chat_id)}"
        if len(etiqueta) > 60:
            etiqueta = etiqueta[:57] + "..."
        markup.add(types.InlineKeyboardButton(
            etiqueta,
            callback_data=f"eliminar_grupo:{chat_id}"
        ))
    return markup


def bot_es_administrador(chat_id):
    try:
        bot_id = bot.get_me().id
        estado = bot.get_chat_member(chat_id, bot_id)
        return estado.status in ("administrator", "creator")
    except Exception:
        return False


def usuario_es_integrante(chat_id, user_id):
    """Comprueba la pertenencia actual; requiere que el bot sea admin del grupo."""
    miembro = bot.get_chat_member(chat_id, user_id)
    if miembro.status in ("creator", "administrator", "member"):
        return True
    if miembro.status == "restricted" and getattr(miembro, "is_member", False):
        return True
    return False


def enlace_privado_grupo(chat_id):
    username = bot.get_me().username
    if not username:
        raise RuntimeError("No se pudo obtener el nombre público del bot.")
    return f"https://t.me/{username}?start=free_{chat_id}"


def teclado_solicitar_ssh(chat_id):
    markup = types.InlineKeyboardMarkup()
    markup.add(types.InlineKeyboardButton(
        "🎁 Crear SSH Gratis (3 días)",
        url=enlace_privado_grupo(chat_id)
    ))
    return markup


def activar_grupo(message):
    chat = message.chat
    usuario = message.from_user
    if usuario is None:
        bot.reply_to(message, "❌ Debes ejecutar este comando desde tu cuenta personal, no como administrador anónimo.")
        return

    try:
        estado_dueno = bot.get_chat_member(chat.id, usuario.id)
    except Exception:
        bot.reply_to(
            message,
            "❌ No pude verificar al propietario. Asegúrate de que el bot sea administrador del grupo y vuelve a intentarlo."
        )
        return

    if estado_dueno.status != "creator":
        bot.reply_to(message, "⛔ Solo el dueño/propietario del grupo puede activar el servicio gratuito.")
        return

    if not bot_es_administrador(chat.id):
        bot.reply_to(
            message,
            "⚠️ Para validar que solo los integrantes reciban SSH, primero otórgame el cargo de administrador del grupo. No necesito permisos para borrar mensajes ni expulsar usuarios. Luego repite /activargrupo."
        )
        return

    conn = sqlite3.connect(DB_GRUPOS)
    cursor = conn.cursor()
    cursor.execute("INSERT OR IGNORE INTO grupos_activos (chat_id) VALUES (?)", (chat.id,))
    nuevo = cursor.rowcount > 0
    conn.commit()
    conn.close()

    texto = (
        "🟢 <b>Grupo activado correctamente.</b>\n\n"
        "Los integrantes podrán solicitar una cuenta SSH gratuita de 3 días. "
        "Cada integrante podrá crear una cuenta por día y cada cuenta tendrá un máximo de 2 conexiones simultáneas. "
        "La solicitud y la entrega de credenciales se realizarán únicamente por el privado del bot."
    )
    if not nuevo:
        texto = "ℹ️ Este grupo ya estaba activado. El botón de solicitud está disponible nuevamente.\n\n" + texto
    bot.send_message(chat.id, texto, parse_mode="HTML", reply_markup=teclado_solicitar_ssh(chat.id))


def desactivar_grupo(message):
    chat = message.chat
    usuario = message.from_user
    if usuario is None:
        bot.reply_to(message, "❌ Debes ejecutar este comando desde tu cuenta personal.")
        return
    try:
        estado_dueno = bot.get_chat_member(chat.id, usuario.id)
    except Exception:
        bot.reply_to(message, "❌ No pude verificar que seas el propietario del grupo.")
        return
    if estado_dueno.status != "creator":
        bot.reply_to(message, "⛔ Solo el dueño/propietario del grupo puede desactivar el servicio.")
        return

    conn = sqlite3.connect(DB_GRUPOS)
    cursor = conn.cursor()
    cursor.execute("DELETE FROM grupos_activos WHERE chat_id = ?", (chat.id,))
    eliminado = cursor.rowcount > 0
    conn.commit()
    conn.close()
    if eliminado:
        bot.reply_to(message, "🔴 <b>Servicio gratuito desactivado para este grupo.</b>", parse_mode="HTML")
    else:
        bot.reply_to(message, "ℹ️ Este grupo no estaba activado.")


@bot.callback_query_handler(func=lambda call: bool(call.data) and call.data.startswith("eliminar_grupo:"))
def callback_eliminar_grupo(call):
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "❌ Solo el administrador del bot puede eliminar grupos.", show_alert=True)
        return

    try:
        grupo_id = int(call.data.split(":", 1)[1])
    except (ValueError, IndexError):
        bot.answer_callback_query(call.id, "❌ Grupo no válido.", show_alert=True)
        return

    conn = sqlite3.connect(DB_GRUPOS)
    cursor = conn.cursor()
    cursor.execute("DELETE FROM grupos_activos WHERE chat_id = ?", (grupo_id,))
    eliminado = cursor.rowcount > 0
    conn.commit()
    conn.close()
    bot.answer_callback_query(call.id, "✅ Grupo eliminado." if eliminado else "ℹ️ El grupo ya no estaba registrado.")

    grupos = listar_grupos_activos()
    if grupos:
        texto = "👥 <b>Grupos autorizados</b>\nSelecciona el grupo que deseas eliminar:"
        markup = teclado_eliminar_grupos(grupos)
    else:
        texto = "ℹ️ No hay grupos autorizados.\nUsa «➕ Añadir Grupo» para agregar uno."
        markup = None
    try:
        bot.edit_message_text(
            texto,
            chat_id=call.message.chat.id,
            message_id=call.message.message_id,
            parse_mode="HTML",
            reply_markup=markup
        )
    except Exception:
        bot.send_message(call.message.chat.id, texto, parse_mode="HTML", reply_markup=markup)


@bot.callback_query_handler(func=lambda call: call.data == "crear_ssh_gratis")
def callback_boton_antiguo(call):
    chat_id = call.message.chat.id
    if not grupo_activo(chat_id):
        bot.answer_callback_query(call.id, "❌ Este grupo no tiene el servicio autorizado.", show_alert=True)
        return
    try:
        if not bot_es_administrador(chat_id) or not usuario_es_integrante(chat_id, call.from_user.id):
            bot.answer_callback_query(call.id, "⛔ Solo los integrantes del grupo pueden solicitar SSH.", show_alert=True)
            return
        markup = teclado_solicitar_ssh(chat_id)
        bot.answer_callback_query(call.id, "Continúa en el privado del bot.")
        bot.send_message(chat_id, "🔐 Para validar tu membresía y recibir tus credenciales, continúa en el chat privado:", reply_markup=markup)
    except Exception:
        bot.answer_callback_query(call.id, "⚠️ No pude verificar tu membresía. Contacta al dueño del grupo.", show_alert=True)


# ----------------------- Límite de dos conexiones SSH -----------------------
def asegurar_pam_limits():
    sshd_bin = shutil.which("sshd") or "/usr/sbin/sshd"
    if not os.path.exists(sshd_bin):
        raise RuntimeError("No se encontró sshd para validar el límite de conexiones.")

    prueba = subprocess.run([sshd_bin, "-T"], capture_output=True, text=True)
    if prueba.returncode != 0:
        raise RuntimeError("No se pudo validar la configuración actual de SSH: " + (prueba.stderr.strip() or "error desconocido"))
    if any(line.strip().lower() == "usepam no" for line in prueba.stdout.splitlines()):
        raise RuntimeError("SSH tiene UsePAM desactivado. Debe habilitarse UsePAM yes para aplicar el límite de dos conexiones por cuenta.")

    pam_sshd = "/etc/pam.d/sshd"
    if not os.path.exists(pam_sshd):
        raise RuntimeError("No existe /etc/pam.d/sshd; no se puede aplicar el límite PAM.")
    with open(pam_sshd, "r", encoding="utf-8") as f:
        texto_sshd = f.read()

    def tiene_pam_limits_activo(texto):
        return any(
            "pam_limits.so" in linea and not linea.lstrip().startswith("#")
            for linea in texto.splitlines()
        )

    ya_en_sshd = tiene_pam_limits_activo(texto_sshd)
    common_incluido = "common-session" in texto_sshd
    common_tiene_limits = False
    common_session = "/etc/pam.d/common-session"
    if common_incluido and os.path.exists(common_session):
        with open(common_session, "r", encoding="utf-8") as f:
            common_tiene_limits = tiene_pam_limits_activo(f.read())

    if not ya_en_sshd and not common_tiene_limits:
        with open(pam_sshd, "a", encoding="utf-8") as f:
            f.write("\n# Límite de conexiones simultáneas para cuentas SSH gratuitas\nsession required pam_limits.so\n")


def configurar_maxlogins(username, max_logins=FREE_MAX_LOGINS):
    asegurar_pam_limits()
    limits_file = "/etc/security/limits.d/99-vps-telegram-free.conf"
    os.makedirs(os.path.dirname(limits_file), exist_ok=True)
    lineas = []
    if os.path.exists(limits_file):
        with open(limits_file, "r", encoding="utf-8") as f:
            lineas = f.readlines()

    nuevas = []
    for linea in lineas:
        partes = linea.split()
        if len(partes) >= 3 and partes[0] == username and partes[1] == "hard" and partes[2] == "maxlogins":
            continue
        nuevas.append(linea)
    nuevas.append(f"{username} hard maxlogins {max_logins}\n")
    with open(limits_file, "w", encoding="utf-8") as f:
        f.writelines(nuevas)

    # Sincronizar con el directorio /root/usuarios para que user.sh muestre el límite en el panel
    os.makedirs("/root/usuarios", exist_ok=True)
    with open(f"/root/usuarios/{username}.limit", "w", encoding="utf-8") as f:
        f.write(f"{max_logins}\n")


def configurar_banner_usuario(username, exp_date, days_count=FREE_DAYS, max_logins=FREE_MAX_LOGINS):
    banner_path = f"/etc/vps-manager/banner_{username}.net"
    issue_path = "/etc/issue.net"
    base = ""
    if os.path.exists(issue_path):
        with open(issue_path, "r", encoding="utf-8", errors="replace") as f:
            base = f.read()
    contenido = (
        base
        + f"\n<br><font color='cyan'>=======================</font><br>"
        + f"<font color='yellow'>👤 Usuario:</font> <font color='white'>{username}</font><br>"
        + f"<font color='yellow'>📅 Expira:</font> <font color='white'>{exp_date} ({days_count} días)</font><br>"
        + f"<font color='yellow'>⚙️ Límite:</font> <font color='white'>{max_logins} conexión(es)</font><br>"
        + f"<font color='cyan'>=======================</font><br>\n"
    )
    with open(banner_path, "w", encoding="utf-8") as f:
        f.write(contenido)

    config_path = "/etc/ssh/sshd_config"
    if not os.path.exists(config_path):
        raise RuntimeError("No existe /etc/ssh/sshd_config.")
    with open(config_path, "r", encoding="utf-8", errors="replace") as f:
        config_original = f.read()

    patron = re.compile(r"(?m)^\s*Match\s+User\s+" + re.escape(username) + r"\s*$")
    if not patron.search(config_original):
        with open(config_path, "a", encoding="utf-8") as f:
            f.write(f"\nMatch User {username}\n    Banner {banner_path}\n")
        sshd_bin = shutil.which("sshd") or "/usr/sbin/sshd"
        prueba = subprocess.run([sshd_bin, "-t"], capture_output=True, text=True)
        if prueba.returncode != 0:
            with open(config_path, "w", encoding="utf-8") as f:
                f.write(config_original)
            raise RuntimeError("La configuración SSH no pasó la validación: " + (prueba.stderr.strip() or "error desconocido"))
        recarga = subprocess.run(["systemctl", "reload", "ssh"], capture_output=True, text=True)
        if recarga.returncode != 0:
            recarga = subprocess.run(["systemctl", "restart", "ssh"], capture_output=True, text=True)
        if recarga.returncode != 0:
            raise RuntimeError("No se pudo recargar SSH después de configurar el banner.")


def crear_usuario_ssh_gratis(user_id):
    username = f"g_{user_id}"
    password = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(12))
    exp_date = (datetime.now().date() + timedelta(days=FREE_DAYS)).isoformat()
    existe = subprocess.run(["getent", "passwd", username], capture_output=True, text=True).returncode == 0
    creado_ahora = False

    if existe:
        subprocess.run(["usermod", "-e", exp_date, "-s", "/bin/false", username], check=True, capture_output=True, text=True)
    else:
        subprocess.run(["useradd", "-e", exp_date, "-s", "/bin/false", "-M", username], check=True, capture_output=True, text=True)
        creado_ahora = True

    try:
        subprocess.run(
            ["chpasswd"],
            input=f"{username}:{password}\n",
            check=True,
            capture_output=True,
            text=True
        )
        configurar_maxlogins(username, FREE_MAX_LOGINS)
        configurar_banner_usuario(username, exp_date, FREE_DAYS, FREE_MAX_LOGINS)
    except Exception:
        if creado_ahora:
            subprocess.run(["userdel", "-f", username], capture_output=True, text=True)
        raise

    ip, dominio = obtener_ip_y_dominio()
    return username, password, exp_date, ip, dominio


def crear_ssh_gratis_en_privado(message, group_id):
    if message.chat.type != "private":
        return

    if not grupo_activo(group_id):
        bot.send_message(message.chat.id, "❌ Este grupo ya no tiene autorizado el servicio gratuito.")
        return

    try:
        if not bot_es_administrador(group_id):
            bot.send_message(message.chat.id, "⚠️ El bot ya no tiene permisos de administrador en el grupo. El dueño debe volver a otorgárselos para verificar integrantes.")
            return
        if not usuario_es_integrante(group_id, message.from_user.id):
            bot.send_message(message.chat.id, "⛔ No puedes recibir SSH gratuito porque no eres integrante del grupo autorizado.")
            return
    except Exception:
        bot.send_message(message.chat.id, "⚠️ No pude comprobar tu membresía. Avisa al dueño del grupo para revisar los permisos del bot.")
        return

    hoy = datetime.now().strftime("%Y-%m-%d")
    conn = sqlite3.connect(DB_GRUPOS, timeout=30)
    try:
        cursor = conn.cursor()
        cursor.execute("BEGIN IMMEDIATE")
        cursor.execute("SELECT 1 FROM registro_usuarios WHERE user_id = ? AND fecha = ?", (message.from_user.id, hoy))
        if cursor.fetchone():
            conn.rollback()
            bot.send_message(message.chat.id, "⏳ Ya creaste tu cuenta SSH gratuita hoy. Podrás solicitar otra mañana.")
            return

        username, password, exp_date, ip, dominio = crear_usuario_ssh_gratis(message.from_user.id)
        cursor.execute(
            "INSERT INTO registro_usuarios (user_id, fecha) VALUES (?, ?)",
            (message.from_user.id, hoy)
        )
        conn.commit()
    except sqlite3.IntegrityError:
        conn.rollback()
        bot.send_message(message.chat.id, "⏳ Ya tienes una solicitud registrada para hoy. Inténtalo mañana.")
        return
    except Exception as e:
        conn.rollback()
        bot.send_message(message.chat.id, "❌ No se pudo crear tu cuenta SSH. Contacta al administrador del servidor.\n\nDetalle: " + html.escape(str(e)[:500]))
        return
    finally:
        conn.close()

    usuario_nombre = html.escape(message.from_user.username or message.from_user.first_name or "integrante")
    metodos_html = obtener_metodos_activos(ip, username)
    linea_dominio = f"🛢️ <b>Dominio:</b> <code>{html.escape(dominio)}</code>\n" if dominio else ""

    respuesta = (
        "✅ <b>¡CUENTA SSH GRATUITA CREADA!</b>\n"
        "━━━━━━━━━━━━━━━━━━━━\n"
        f"👤 <b>Usuario:</b> <code>{html.escape(username)}</code>\n"
        f"🔑 <b>Pass:</b> <code>{html.escape(password)}</code>\n"
        f"⏳ <b>Vence:</b> {exp_date} ({FREE_DAYS} días)\n"
        f"⚙️ <b>Límite:</b> {FREE_MAX_LOGINS} conexión(es)\n"
        f"🌐 <b>IP Server:</b> <code>{html.escape(ip)}</code>\n"
        f"{linea_dominio}"
        f"👤 <b>Creada para:</b> @{usuario_nombre}\n"
        "━━━━━━━━━━━━━━━━━━━━\n"
        "🚀 <b>MÉTODOS DE CONEXIÓN ACTIVOS:</b>\n"
        f"{metodos_html}\n"
        "━━━━━━━━━━━━━━━━━━━━\n"
        "<i>Recuerda: puedes solicitar una cuenta gratuita una vez por día.</i>"
    )
    bot.send_message(message.chat.id, respuesta, parse_mode="HTML", disable_web_page_preview=True)


# ----------------------- Inicio / acceso -----------------------
@bot.message_handler(commands=["start", "help"])
def send_welcome(message):
    uid = str(message.from_user.id)
    chat = message.chat
    texto = message.text or ""
    partes = texto.split(maxsplit=1)
    payload = partes[1].strip() if len(partes) > 1 else ""

    if chat.type in ["group", "supergroup"]:
        if grupo_activo(chat.id):
            bot.reply_to(
                message,
                "🌟 <b>¡Bot activo en este grupo!</b>\nLos integrantes pueden solicitar una cuenta SSH de 3 días. La validación y entrega se realizan en privado.",
                parse_mode="HTML",
                reply_markup=teclado_solicitar_ssh(chat.id)
            )
        return

    if payload.startswith("free_"):
        try:
            group_id = int(payload[5:])
        except ValueError:
            bot.reply_to(message, "❌ Enlace de grupo no válido.")
            return
        crear_ssh_gratis_en_privado(message, group_id)
        return

    markup = types.ReplyKeyboardMarkup(row_width=2, resize_keyboard=True)
    if is_admin(uid):
        markup.add("👤 Crear SSH", "❌ Eliminar SSH")
        markup.add("🔄 Renovar SSH", "📋 Lista SSH")
        markup.add("🛡️ Crear V2Ray (Xray)", "👥 Panel Vendedores")
        markup.add("➕ Añadir Grupo", "➖ Eliminar Grupo")
        markup.add("📊 Info Servidor")
        bot.reply_to(message, "👑 <b>Panel ADMIN VPS Activo</b>", parse_mode="HTML", reply_markup=markup)
    elif is_reseller(uid):
        markup.add("👤 Crear SSH", "🔄 Renovar SSH")
        markup.add("💰 Mis Créditos")
        bot.reply_to(message, f"🤝 <b>Panel VENDEDOR Activo</b>\nCréditos Disponibles: {get_credits(uid)}", parse_mode="HTML", reply_markup=markup)
    else:
        bot.reply_to(message, f"⚠️ <b>Acceso Denegado.</b>\nTu ID: <code>{uid}</code>\n\nPara SSH gratuito, entra desde el botón publicado en tu grupo autorizado.", parse_mode="HTML")


# ----------------------- Mensajes y comandos -----------------------
@bot.message_handler(func=lambda message: True)
def handle_message(message):
    uid = str(message.from_user.id) if message.from_user else ""
    chat = message.chat
    text = message.text or ""

    if chat.type in ["group", "supergroup"]:
        comando = text.split()[0].split("@")[0].lower() if text.strip() else ""
        if comando == "/activargrupo":
            activar_grupo(message)
            return
        elif comando == "/detenergrupo":
            desactivar_grupo(message)
            return
        return

    if not (is_admin(uid) or is_reseller(uid)):
        return

    if is_admin(uid):
        if text == "📊 Info Servidor":
            ip, dom = obtener_ip_y_dominio()
            ram = subprocess.getoutput("free -m | awk 'NR==2{printf \"%s / %s MB\", $3,$2}'")
            onlines = subprocess.getoutput("ps -eo uid,user:30,comm | awk '$1 >= 1000 && $1 != 65534 && $2 != \"ubuntu\" && ($3 ~ /sshd|dropbear/) {print $2}' | sort -u | wc -l").strip()
            metodos_html = obtener_metodos_activos(ip, "Test")
            info_msg = (
                f"🌐 <b>IP:</b> <code>{html.escape(ip)}</code>\n"
                f"🛢️ <b>Dominio:</b> <code>{html.escape(dom or 'No configurado')}</code>\n"
                f"⚡ <b>RAM:</b> {html.escape(ram)}\n"
                f"📡 <b>Usuarios en Línea:</b> {html.escape(onlines)}\n"
                f"━━━━━━━━━━━━━━━━━━━━\n"
                f"🚀 <b>MÉTODOS ACTIVOS:</b>\n{metodos_html}"
            )
            bot.reply_to(message, info_msg, parse_mode="HTML", disable_web_page_preview=True)
            return
        elif text == "📋 Lista SSH":
            users = subprocess.getoutput("awk -F: '$3 >= 1000 && $1 != \"nobody\" && $1 != \"ubuntu\" {print $1}' /etc/passwd").strip()
            bot.reply_to(message, f"📋 <b>Usuarios SSH Registrados:</b>\n<code>{html.escape(users or 'Sin usuarios')}</code>", parse_mode="HTML")
            return
        elif text == "❌ Eliminar SSH":
            bot.reply_to(message, "Formato:\n<code>/deluser [usuario]</code>", parse_mode="HTML")
            return
        elif text.startswith("/deluser"):
            try:
                user = text.split()[1]
                subprocess.getoutput(f"userdel -f {user} 2>/dev/null; rm -f /root/usuarios/{user}.limit /etc/vps-manager/banner_{user}.net; sed -i '/Match User {user}/,+1d' /etc/ssh/sshd_config && systemctl reload ssh 2>/dev/null")
                bot.reply_to(message, f"✅ Usuario <b>{html.escape(user)}</b> eliminado.", parse_mode="HTML")
            except Exception:
                bot.reply_to(message, "❌ Error al eliminar el usuario.")
            return
        elif text in ("➕ Añadir Grupo", "🟢 Activar Bot Grupo"):
            bot.reply_to(
                message,
                "➕ <b>AÑADIR GRUPO</b>\n\n"
                "1. Añade este bot al grupo que deseas autorizar.\n"
                "2. Otórgale el cargo de administrador (sin necesidad de permisos para borrar mensajes o expulsar usuarios).\n"
                "3. El dueño/propietario del grupo debe escribir allí: <code>/activargrupo</code>.\n\n"
                "Solo el propietario podrá activar el grupo. Una vez activado, el bot publicará el botón para solicitar SSH gratuito.",
                parse_mode="HTML"
            )
            return
        elif text in ("➖ Eliminar Grupo", "🔴 Detener Bot Grupo"):
            grupos = listar_grupos_activos()
            if not grupos:
                bot.reply_to(message, "ℹ️ No hay grupos autorizados para eliminar. Usa «➕ Añadir Grupo» para agregar uno.", parse_mode="HTML")
            else:
                bot.reply_to(
                    message,
                    "👥 <b>GRUPOS AUTORIZADOS</b>\nSelecciona el grupo que deseas eliminar:",
                    parse_mode="HTML",
                    reply_markup=teclado_eliminar_grupos(grupos)
                )
            return
        elif text.startswith("/activargrupo"):
            bot.reply_to(message, "ℹ️ Añade el bot al grupo y el propietario debe enviar <code>/activargrupo</code> dentro de ese grupo.", parse_mode="HTML")
            return
        elif text.startswith("/detenergrupo"):
            bot.reply_to(message, "ℹ️ Para eliminar un grupo desde aquí, pulsa «➖ Eliminar Grupo» y selecciónalo de la lista.", parse_mode="HTML")
            return
        elif text == "👥 Panel Vendedores":
            msg = "👥 <b>GESTIÓN DE REVENDEDORES</b>\n\n<code>/addvend ID CREDITOS</code>\n<code>/delvend ID</code>\n\n<b>Vendedores:</b>\n"
            for r_id, cred in load_resellers().items():
                msg += f"ID: <code>{r_id}</code> - Créditos: {cred}\n"
            bot.reply_to(message, msg, parse_mode="HTML")
            return
        elif text.startswith("/addvend"):
            try:
                parts = text.split(); r_id = parts[1]; creds = int(parts[2])
                res = load_resellers(); res[r_id] = creds; save_resellers(res)
                bot.reply_to(message, f"✅ Vendedor <code>{r_id}</code> agregado ({creds} créditos).", parse_mode="HTML")
            except Exception:
                bot.reply_to(message, "❌ Formato: <code>/addvend ID CREDITOS</code>", parse_mode="HTML")
            return
        elif text.startswith("/delvend"):
            try:
                r_id = text.split()[1]; res = load_resellers()
                if r_id in res:
                    del res[r_id]; save_resellers(res)
                    bot.reply_to(message, "✅ Vendedor eliminado.", parse_mode="HTML")
            except Exception:
                pass
            return
        elif text == "🛡️ Crear V2Ray (Xray)":
            bot.reply_to(message, "Generador V2Ray:\n<code>/addvmess [usuario] [dias]</code>", parse_mode="HTML")
            return
        elif text.startswith("/addvmess"):
            try:
                parts = text.split(); v_user = parts[1]; v_days = int(parts[2]); v_uuid = str(uuid.uuid4())
                ip, dom = obtener_ip_y_dominio()
                host_v2 = dom if dom else ip
                exp_v2 = (datetime.now().date() + timedelta(days=v_days)).isoformat()

                conf_xray = "/usr/local/etc/xray/config.json"
                if os.path.exists(conf_xray):
                    subprocess.run(
                        f"jq '(.inbounds[] | select(.tag==\"vmess-ws\" or .tag==\"vmess-grpc\").settings.clients) += [{{\"id\": \"{v_uuid}\", \"email\": \"{v_user}\", \"alterId\": 0}}]' {conf_xray} > /tmp/xray_tmp.json && mv /tmp/xray_tmp.json {conf_xray} && systemctl restart xray",
                        shell=True, check=False
                    )

                json_tls = f'{{"v":"2","ps":"{v_user}-WS-TLS","add":"{host_v2}","port":"443","id":"{v_uuid}","aid":"0","scy":"auto","net":"ws","type":"none","host":"{host_v2}","path":"/vmess","tls":"tls","sni":"{host_v2}"}}'
                json_ntls = f'{{"v":"2","ps":"{v_user}-WS-NTLS","add":"{host_v2}","port":"80","id":"{v_uuid}","aid":"0","scy":"auto","net":"ws","type":"none","host":"{host_v2}","path":"/vmess","tls":"none"}}'
                json_grpc = f'{{"v":"2","ps":"{v_user}-gRPC","add":"{host_v2}","port":"443","id":"{v_uuid}","aid":"0","scy":"auto","net":"grpc","type":"none","host":"{host_v2}","path":"vmess-grpc","tls":"tls","sni":"{host_v2}"}}'

                link_tls = "vmess://" + base64.b64encode(json_tls.encode("utf-8")).decode("utf-8")
                link_ntls = "vmess://" + base64.b64encode(json_ntls.encode("utf-8")).decode("utf-8")
                link_grpc = "vmess://" + base64.b64encode(json_grpc.encode("utf-8")).decode("utf-8")

                msg_v2 = (
                    f"✅ <b>CUENTA V2RAY (VMESS) CREADA</b>\n"
                    f"━━━━━━━━━━━━━━━━━━━━\n"
                    f"👤 <b>Usuario:</b> <code>{html.escape(v_user)}</code>\n"
                    f"🌐 <b>Dominio/IP:</b> <code>{html.escape(host_v2)}</code>\n"
                    f"🔑 <b>UUID:</b> <code>{v_uuid}</code>\n"
                    f"⏳ <b>Vence:</b> {exp_v2} ({v_days} días)\n"
                    f"━━━━━━━━━━━━━━━━━━━━\n"
                    f"🟢 <b>1. WS TLS (Puerto 443):</b>\n<code>{link_tls}</code>\n\n"
                    f"🟢 <b>2. WS NTLS (Puerto 80 / SlowDNS):</b>\n<code>{link_ntls}</code>\n\n"
                    f"🟢 <b>3. gRPC (Puerto 443):</b>\n<code>{link_grpc}</code>"
                )
                bot.reply_to(message, msg_v2, parse_mode="HTML")
            except Exception as e:
                bot.reply_to(message, f"❌ Error al generar V2Ray: {html.escape(str(e))}", parse_mode="HTML")
            return

    if text == "💰 Mis Créditos":
        bot.reply_to(message, f"💰 <b>Créditos:</b> {get_credits(uid)}", parse_mode="HTML")
        return
    elif text == "👤 Crear SSH":
        bot.reply_to(message, "Comando:\n<code>/adduser [usuario] [clave] [dias] [limite_opcional]</code>", parse_mode="HTML")
        return
    elif text == "🔄 Renovar SSH":
        bot.reply_to(message, "Comando para extender días:\n<code>/renovar [usuario] [dias_a_sumar]</code>", parse_mode="HTML")
        return
    elif text.startswith("/renovar"):
        if get_credits(uid) <= 0 and not is_admin(uid):
            bot.reply_to(message, "❌ Sin créditos disponibles.", parse_mode="HTML")
            return
        try:
            parts = text.split(); user = parts[1]; add_days = int(parts[2])
            if not cmd_ok(f"id {user}"):
                bot.reply_to(message, f"❌ El usuario <code>{html.escape(user)}</code> no existe.", parse_mode="HTML")
                return

            # Renovación acumulativa igual que en user.sh
            exp_raw = subprocess.getoutput(f"chage -l {user} | grep 'Account expires' | cut -d: -f2 | sed 's/^[ \\t]*//'").strip()
            base_date = "today"
            if exp_raw and exp_raw != "never":
                exp_epoch = subprocess.getoutput(f"date -d '{exp_raw}' +%s 2>/dev/null").strip()
                now_epoch = subprocess.getoutput("date -d 'today 00:00:00' +%s").strip()
                if exp_epoch.isdigit() and now_epoch.isdigit() and int(exp_epoch) > int(now_epoch):
                    base_date = exp_raw

            nueva_fecha = subprocess.getoutput(f"date -d '{base_date} + {add_days} days' +%Y-%m-%d").strip()
            fecha_visual = subprocess.getoutput(f"date -d '{base_date} + {add_days} days' +%d/%m/%Y").strip()
            subprocess.getoutput(f"chage -E '{nueva_fecha}' {user}")

            deduct_credit(uid)
            bot.reply_to(message, f"✅ <b>CUENTA RENOVADA</b>\n👤 <b>Usuario:</b> <code>{html.escape(user)}</code>\n📅 <b>Nueva expiración:</b> {html.escape(fecha_visual)}", parse_mode="HTML")
        except Exception:
            bot.reply_to(message, "❌ Formato correcto:\n<code>/renovar usuario dias</code>", parse_mode="HTML")
        return
    elif text.startswith("/adduser"):
        if get_credits(uid) <= 0 and not is_admin(uid):
            bot.reply_to(message, "❌ Sin créditos disponibles.", parse_mode="HTML")
            return
        try:
            parts = text.split()
            user = parts[1]
            pwd = parts[2]
            days = int(parts[3])
            limite = int(parts[4]) if len(parts) > 4 and parts[4].isdigit() else 2

            if cmd_ok(f"id {user}"):
                bot.reply_to(message, f"❌ El usuario <code>{html.escape(user)}</code> ya existe.", parse_mode="HTML")
                return

            exp_iso = (datetime.now().date() + timedelta(days=days)).isoformat()
            exp_visual = (datetime.now().date() + timedelta(days=days)).strftime("%d/%m/%Y")

            subprocess.run(["useradd", "-e", exp_iso, "-s", "/bin/false", "-M", user], check=True)
            subprocess.run(["chpasswd"], input=f"{user}:{pwd}\n", check=True, text=True)

            configurar_maxlogins(user, limite)
            configurar_banner_usuario(user, exp_iso, days, limite)
            deduct_credit(uid)

            ip, dominio = obtener_ip_y_dominio()
            metodos_html = obtener_metodos_activos(ip, user)
            linea_dominio = f"🛢️ <b>Dominio:</b> <code>{html.escape(dominio)}</code>\n" if dominio else ""

            resp = (
                f"✅ <b>¡CUENTA SSH CREADA CON ÉXITO!</b>\n"
                f"━━━━━━━━━━━━━━━━━━━━\n"
                f"👤 <b>Usuario:</b> <code>{html.escape(user)}</code>\n"
                f"🔑 <b>Pass:</b> <code>{html.escape(pwd)}</code>\n"
                f"⏳ <b>Vence:</b> {exp_visual} ({days} días)\n"
                f"⚙️ <b>Límite:</b> {limite} conexión(es)\n"
                f"🌐 <b>IP Server:</b> <code>{html.escape(ip)}</code>\n"
                f"{linea_dominio}"
                f"━━━━━━━━━━━━━━━━━━━━\n"
                f"🚀 <b>MÉTODOS DE CONEXIÓN ACTIVOS:</b>\n"
                f"{metodos_html}\n"
                f"━━━━━━━━━━━━━━━━━━━━"
            )

            if not is_admin(uid):
                resp += f"\n💰 <i>Créditos restantes: {get_credits(uid)}</i>"

            bot.reply_to(message, resp, parse_mode="HTML", disable_web_page_preview=True)
        except Exception as e:
            bot.reply_to(message, f"❌ Error al crear usuario: {html.escape(str(e))}", parse_mode="HTML")


if __name__ == "__main__":
    while True:
        try:
            bot.infinity_polling(timeout=10, long_polling_timeout=5)
        except Exception:
            time.sleep(3)
EOF

cat << EOF > /etc/systemd/system/vps-bot.service
[Unit]
Description=Telegram Bot Golbert VPS Panel
After=network.target
[Service]
User=root
WorkingDirectory=$BOT_DIR
ExecStart=$BOT_DIR/venv/bin/python $BOT_DIR/bot.py
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload && systemctl enable vps-bot >/dev/null 2>&1 && systemctl restart vps-bot
echo -e "\n${C_GREEN}[✔] ¡Bot del Panel actualizado con éxito en el repositorio y VPS!${C_NC}"
read -p "Presione Enter para regresar..."
