import os
import subprocess
import telebot
import time
import uuid
import requests
import datetime
import threading
from flask import Flask, request, jsonify
from telebot import types

# Cargar Configuración
config = {}
with open("/root/master_bot/config.env", "r") as f:
    for line in f:
        if "=" in line:
            k, v = line.strip().split("=", 1)
            config[k] = v.strip('"')

TOKEN = config.get("TOKEN", "")
ADMIN_ID = config.get("ADMIN", "")
CF_EMAIL = config.get("CF_EMAIL", "")
CF_KEY = config.get("CF_KEY", "")
CF_ZONE = config.get("CF_ZONE", "")
DOMAIN = config.get("DOMAIN", "")

AUTH_FILE = "/root/master_bot/auth_users.txt"
CREDITS_FILE = "/root/master_bot/credits.txt"
KEYS_FILE = "/root/master_bot/keys_db.txt"
bot = telebot.TeleBot(TOKEN)

# COORDENADAS UNICODE
BTN_KEY_D = "\U0001F511 Key Due\u00f1o"
BTN_BROADCAST = "\U0001F4E2 Mensaje"
BTN_KEY_CLIENT = "\U0001F511 Generar Key"
BTN_ESTADO = "\U0001F4CA Estado"
BTN_DOM_MIS = "\U0001F4C1 Mis Dominios"
BTN_DOM_A = "\U0001F310 Dominio A"
BTN_DOM_NS = "\U0001F9E9 Dominio NS"
BTN_HIST = "\U0001F4DC Mi Historial"
BTN_USO = "\U0001F4C8 Mi Uso"
BTN_ID = "\U0001F194 Mi ID"
BTN_ADD_USR = "\u2795 Add User"
BTN_RENEW = "\U0001F504 Renovar Acceso"
BTN_DEL = "\u274C Eliminar Acceso"
BTN_FIND = "\U0001F50D Buscar ID"
BTN_LOGS = "\U0001F4DC Logs Keys"
BTN_RANK = "\U0001F3C6 Ranking"
BTN_CLIENTS = "\U0001F465 Mis Clientes"
BTN_IPS = "\U0001F310 Lista de IPs"
BTN_PRECIOS = "\U0001F4B3 Precios" # NUEVO BOTON

def load_auth():
    users = {}
    if os.path.exists(AUTH_FILE):
        with open(AUTH_FILE, "r") as f:
            for line in f:
                if ":" in line:
                    u, d = line.strip().split(":")
                    users[u] = d
    return users

def save_auth(users):
    with open(AUTH_FILE, "w") as f:
        for u, d in users.items():
            f.write(f"{u}:{d}\n")

def load_credits():
    creds = {}
    if os.path.exists(CREDITS_FILE):
        with open(CREDITS_FILE, "r") as f:
            for line in f:
                if ":" in line:
                    u, c = line.strip().split(":")
                    creds[u] = int(c)
    return creds

def save_credits(creds):
    with open(CREDITS_FILE, "w") as f:
        for u, c in creds.items():
            f.write(f"{u}:{c}\n")

def save_key_owner(key, owner_id):
    with open(KEYS_FILE, "a") as f:
        f.write(f"{key}:{owner_id}\n")

def check_and_burn_key(key):
    if not os.path.exists(KEYS_FILE):
        return None
    lines = []
    owner_id = None
    with open(KEYS_FILE, "r") as f:
        for line in f:
            parts = line.strip().split(":")
            if len(parts) == 2:
                k, o = parts
                if k == key:
                    owner_id = o
                else:
                    lines.append(line)
    if owner_id:
        with open(KEYS_FILE, "w") as f:
            f.writelines(lines)
    return owner_id

# SE MODIFICÓ PARA RETORNAR TRUE SI LA KEY ERA VÁLIDA
def notify_key_usage(key_used, vps_ip="Desconocida"):
    owner_id = check_and_burn_key(key_used)
    if owner_id:
        try:
            bot.send_message(
                owner_id,
                "\U0001F514 <b>\u00a1AVISO DE KEY USADA!</b>\n"
                "━━━━━━━━━━━━━━━━━━━━\n"
                f"\U0001F511 La Key: <code>{key_used}</code>\n"
                f"\U0001F310 Ha sido instalada en la IP: <code>{vps_ip}</code>\n"
                "━━━━━━━━━━━━━━━━━━━━",
                parse_mode="HTML"
            )
        except Exception as e:
            pass
        return True
    return False

def is_auth(uid):
    if uid == ADMIN_ID: return True
    users = load_auth()
    if uid in users:
        if datetime.datetime.now().strftime("%Y-%m-%d") <= users[uid]:
            return True
    return False

def get_keyboard():
    markup = types.ReplyKeyboardMarkup(row_width=2, resize_keyboard=True)
    markup.add(BTN_KEY_D, BTN_PRECIOS)
    markup.add(BTN_ADD_USR, BTN_RENEW, BTN_DEL)
    markup.add(BTN_FIND, BTN_CLIENTS)
    markup.add(BTN_ESTADO, BTN_IPS)
    markup.add(BTN_BROADCAST, BTN_DOM_MIS)
    markup.add(BTN_DOM_A, BTN_DOM_NS)
    markup.add(BTN_HIST, BTN_USO, BTN_LOGS, BTN_RANK)
    markup.add(BTN_ID)
    return markup

def get_client_keyboard():
    markup = types.ReplyKeyboardMarkup(row_width=2, resize_keyboard=True)
    markup.add(BTN_KEY_CLIENT, BTN_PRECIOS)
    markup.add(BTN_ADD_USR, BTN_RENEW, BTN_DEL)
    markup.add(BTN_FIND, BTN_DOM_A, BTN_DOM_NS)
    markup.add(BTN_ID)
    return markup

def is_menu_button(text):
    return text in [BTN_KEY_D, BTN_BROADCAST, BTN_KEY_CLIENT, BTN_ESTADO, BTN_DOM_MIS, BTN_DOM_A, BTN_DOM_NS, BTN_HIST, BTN_USO, BTN_ID, BTN_ADD_USR, BTN_RENEW, BTN_DEL, BTN_FIND, BTN_LOGS, BTN_RANK, BTN_CLIENTS, BTN_IPS, BTN_PRECIOS]

def cf_api_call(method, endpoint, data=None):
    url = f"https://api.cloudflare.com/client/v4/zones/{CF_ZONE}/{endpoint}"
    headers = {"X-Auth-Email": CF_EMAIL, "X-Auth-Key": CF_KEY, "Content-Type": "application/json"}
    if method == "POST": return requests.post(url, headers=headers, json=data)
    elif method == "GET": return requests.get(url, headers=headers)
    return None

def get_denied_msg(uid):
    return (
        "\u26A0\uFE0F <b>ACCESO DENEGADO</b> \u26A0\uFE0F\n"
        "━━━━━━━━━━━━━━━━━━━━\n"
        "No tienes permisos para utilizar este bot.\n\n"
        "Para adquirir acceso o servicios, contacta a:\n"
        "\U0001F468\u200D\U0001F4BB <b>Telegram:</b> @golbert_service\n"
        "\U0001F4DE <b>WhatsApp:</b> +51960084993\n"
        "━━━━━━━━━━━━━━━━━━━━\n"
        f"\U0001F194 <b>Tu ID es:</b> <code>{uid}</code>"
    )

@bot.message_handler(commands=['start'])
def send_welcome(message):
    uid = str(message.from_user.id)
    if uid == ADMIN_ID:
        bot.reply_to(message, "\U0001F451 <b>Bot Maestro Activo y Vinculado.</b>", parse_mode="HTML", reply_markup=get_keyboard())
    elif is_auth(uid):
        bot.reply_to(message, "\u2705 <b>Bienvenido Revendedor.</b>\nPuedes administrar clientes y generar keys.", parse_mode="HTML", reply_markup=get_client_keyboard())
    else:
        bot.reply_to(message, get_denied_msg(uid), parse_mode="HTML")

@bot.message_handler(func=lambda message: True)
def handle_message(message):
    uid = str(message.from_user.id)
    if not is_auth(uid):
        bot.reply_to(message, get_denied_msg(uid), parse_mode="HTML")
        return
        
    text = message.text
    username = message.from_user.username or "Usuario"

    # === NUEVA FUNCIÓN: PRECIOS ===
    if text == BTN_PRECIOS:
        msg_precio = (
            "SCRIPT GOLBERT ILIMITADO\n\n"
            "💳 PLANES Y PRECIOS\n"
            "━━━━━━━━━━━━━━━━━━\n"
            "🟢 1 MES\n"
            "💵 USD: $1.50 |\n\n"
            "🟢 3 MESES\n"
            "💵 USD: $2.50 |\n\n"
            "🟢 6 MESES\n"
            "💵 USD: $4.00 |\n\n"
            "🔥 12 MESES — MEJOR PRECIO 🔥\n"
            "💵 USD: $6.00 |\n"
            "━━━━━━━━━━━━━━━━━━\n"
            "ℹ️ INFORMACIÓN IMPORTANTE\n"
            "BOT PREMIUM CON ACCESO Ilimitado\n"
            "(Soporte, Actualizaciones y MAS!!)\n"
            "• El cobro se realiza en USD.\n"
            "• Paypal 🌎\n"
            "• Binance 🌎\n"
            "• Yape solo Perú 🇵🇪\n"
            "━━━━━━━━━━━━━━━━━━\n"
            "📩 Para contratar: https://t.me/golbert_service\n\n"
            "VISITA NUESTRO GRUPOS,\n"
            "Telegram\n"
            "https://t.me/golbert_service\n"
            "Grupo telegram\n"
            "https://t.me/vpsgratis2026\n"
            "WhatsApp\n"
            "https://wa.me/51960084993\n"
            "YouTube\n"
            "https://www.youtube.com/@golbertvps\n"
            "Facebook\n"
            "https://www.facebook.com/share/1BsxYW18P4/\n"
            "Puedes escribir directamente a @golbert_service solicitando tu /ID y LISTO!!\n"
            "=============================================\n"
            " ⚜ by @golbert_service ⚜\n"
            "============================================="
        )
        bot.reply_to(message, msg_precio, disable_web_page_preview=True)
        return

    # === FUNCIONES COMPARTIDAS (ADMIN Y CLIENTE) ===
    elif text == BTN_DOM_A:
        msg = bot.reply_to(message, f"\U0001F310 <b>Crear Dominio A</b> ({DOMAIN})\nIngresa el subdominio y la IP separados por espacio:\nEj: <code>vps1 192.168.1.1</code>", parse_mode="HTML")
        bot.register_next_step_handler(msg, process_domain_a)
        return
        
    elif text == BTN_DOM_NS:
        msg = bot.reply_to(message, f"\U0001F9E9 <b>Crear Dominio NS</b> ({DOMAIN})\nIngresa el subdominio y destino separados por espacio:\nEj: <code>ns1 vps1.dominio.com</code>", parse_mode="HTML")
        bot.register_next_step_handler(msg, process_domain_ns)
        return
        
    elif text == BTN_ID:
        if uid == ADMIN_ID:
            bot.reply_to(message, f"\U0001F194 <b>Tu ID:</b> <code>{uid}</code>\n\U0001F451 <b>Rol:</b> Due\u00f1o", parse_mode="HTML")
        else:
            exp_date = load_auth().get(uid, "Desconocido")
            creds = load_credits().get(uid, 0)
            bot.reply_to(message, f"\U0001F194 <b>Tu ID:</b> <code>{uid}</code>\n\u23F3 <b>Vence:</b> {exp_date}\n\U0001F4B0 <b>Créditos:</b> {creds}", parse_mode="HTML")
        return

    elif text == BTN_ADD_USR:
        if uid == ADMIN_ID:
            msg = bot.reply_to(message, "\u2795 <b>Autorizar Revendedor</b>\nIngresa el ID y los CRÉDITOS separados por espacio:\nEj: <code>123456789 30</code>", parse_mode="HTML")
            bot.register_next_step_handler(msg, process_add_revendedor)
        else:
            msg = bot.reply_to(message, "\u2795 <b>Autorizar Cliente</b>\nIngresa el ID y los DÍAS separados por espacio:\nEj: <code>123456789 30</code>", parse_mode="HTML")
            bot.register_next_step_handler(msg, process_add_cliente)
        return

    elif text == BTN_RENEW:
        if uid == ADMIN_ID:
            msg = bot.reply_to(message, "\U0001F504 <b>Renovar Revendedor</b>\nIngresa el ID y los CRÉDITOS a sumar:\nEj: <code>123456789 15</code>", parse_mode="HTML")
            bot.register_next_step_handler(msg, process_renew_revendedor)
        else:
            msg = bot.reply_to(message, "\U0001F504 <b>Renovar Cliente</b>\nIngresa el ID y los DÍAS a sumar (Cuesta 1 crédito):\nEj: <code>123456789 30</code>", parse_mode="HTML")
            bot.register_next_step_handler(msg, process_renew_cliente)
        return

    elif text == BTN_DEL:
        msg = bot.reply_to(message, "\u274C <b>Eliminar Acceso</b>\nIngresa el ID del usuario a eliminar:", parse_mode="HTML")
        bot.register_next_step_handler(msg, process_del_user)
        return

    elif text == BTN_FIND:
        msg = bot.reply_to(message, "\U0001F50D <b>Buscar ID</b>\nIngresa el ID de Telegram a consultar:", parse_mode="HTML")
        bot.register_next_step_handler(msg, process_find_user)
        return

    # === FUNCIONES EXCLUSIVAS DEL CLIENTE ===
    if uid != ADMIN_ID:
        if text == BTN_KEY_CLIENT:
            new_key = "VPS-" + str(uuid.uuid4()).upper().replace("-", "")[:12]
            new_key = f"{new_key[:4]}-{new_key[4:8]}-{new_key[8:12]}"
            save_key_owner(new_key, uid)
            exp_date = load_auth().get(uid, "Desconocido")
            msg = (
                "\u2705 <b>KEY GENERADA</b>\n"
                "━━━━━━━━━━━━━━━━━━━━\n"
                f"\U0001F464 <b>Vendedor:</b> @{username} (ID: <code>{uid}</code>)\n"
                f"\U0001F511 <b>Key:</b> <code>{new_key}</code>\n"
                f"\u23F3 <b>Vence:</b> {exp_date}\n"
                "━━━━━━━━━━━━━━━━━━━━\n"
                "\u26A0\uFE0F Compatible con Ubuntu (22.04, 24.04).\n"
                "\U0001F468\u200D\U0001F4BB <b>Dueño:</b> @golbertperuvps\n"
                "━━━━━━━━━━━━━━━━━━━━\n"
                "\U0001F4BB <b>Instalación:</b>\n"
                "<code>apt update -y && apt install -y wget curl && wget -O install.sh https://script.golbertvps.org.pe/install.sh && chmod +x install.sh && ./install.sh</code>"
            )
            bot.reply_to(message, msg, parse_mode="HTML")
        else:
            bot.reply_to(message, "\u26A0\uFE0F Utiliza los botones del men\u00fa.", reply_markup=get_client_keyboard())
        return

    # === FUNCIONES EXCLUSIVAS DEL ADMIN ===
    if text == BTN_KEY_D:
        new_key = "VPS-" + str(uuid.uuid4()).upper().replace("-", "")[:12]
        new_key = f"{new_key[:4]}-{new_key[4:8]}-{new_key[8:12]}"
        save_key_owner(new_key, uid)
        msg = (
            "\u2705 <b>KEY GENERADA (DUEÑO)</b>\n"
            "━━━━━━━━━━━━━━━━━━━━\n"
            f"\U0001F464 <b>Cliente:</b> @{username} (ID: <code>{uid}</code>)\n"
            f"\U0001F511 <b>Key:</b> <code>{new_key}</code>\n"
            "\u23F3 <b>Vence:</b> Permanente\n"
            "━━━━━━━━━━━━━━━━━━━━\n"
            "\u26A0\uFE0F Compatible con Ubuntu (22.04, 24.04).\n"
            "\U0001F468\u200D\U0001F4BB <b>Dueño:</b> @golbertperuvps\n"
            "━━━━━━━━━━━━━━━━━━━━\n"
            "\U0001F4BB <b>Instalación:</b>\n"
            "<code>apt update -y && apt install -y wget curl && wget -O install.sh https://script.golbertvps.org.pe/install.sh && chmod +x install.sh && ./install.sh</code>"
        )
        bot.reply_to(message, msg, parse_mode="HTML")

    elif text == BTN_BROADCAST:
        msg = bot.reply_to(message, "\U0001F4E2 <b>Enviar Anuncio / Mensaje Masivo</b>\nIngresa el texto que deseas enviar a todos los usuarios registrados:", parse_mode="HTML")
        bot.register_next_step_handler(msg, process_broadcast)
        return

    elif text == BTN_DOM_MIS:
        resp = cf_api_call("GET", "dns_records")
        if resp and resp.status_code == 200:
            records = resp.json().get("result", [])
            if not records:
                bot.reply_to(message, f"\U0001F4C1 No hay registros DNS en Cloudflare para <b>{DOMAIN}</b>.", parse_mode="HTML")
            else:
                res = f"\U0001F4C1 <b>REGISTROS DNS ({DOMAIN})</b>\n━━━━━━━━━━━━━━━━━━━━\n"
                for r in records[:20]:
                    res += f"\U0001F310 <b>{r.get('type')}</b>: <code>{r.get('name')}</code>\n\u2514 IP/Destino: <code>{r.get('content')}</code>\n\n"
                bot.reply_to(message, res, parse_mode="HTML")
        else:
            bot.reply_to(message, "\u274C Error al consultar los dominios en Cloudflare.", parse_mode="HTML")

    elif text == BTN_CLIENTS:
        users = load_auth()
        creds = load_credits()
        if not users:
            bot.reply_to(message, "\u26A0\uFE0F No hay usuarios autorizados.", parse_mode="HTML")
        else:
            res = "\U0001F465 <b>USUARIOS AUTORIZADOS</b>\n━━━━━━━━━━━━━━━━━━━━\n"
            for u, d in users.items():
                c = creds.get(u, 0)
                res += f"\U0001F194 ID: <code>{u}</code> \u279C Vence: {d} | Créditos: {c}\n"
            bot.reply_to(message, res, parse_mode="HTML")
            
    elif text == BTN_ESTADO:
        ip = subprocess.getoutput("curl -s ipv4.icanhazip.com")
        ram = subprocess.getoutput("free -m | awk 'NR==2{printf \"%s / %s MB\", $3,$2}'")
        bot.reply_to(message, f"\U0001F4CA <b>ESTADO DEL VPS</b>\n\U0001F310 <b>IP:</b> {ip}\n\u26A1 <b>RAM:</b> {ram}", parse_mode="HTML")
        
    elif text == BTN_IPS:
        ips = subprocess.getoutput("netstat -tn 2>/dev/null | grep :22 | awk '{print $5}' | cut -d: -f1 | sort | uniq")
        if not ips: ips = "Ninguna conexi\u00f3n activa."
        bot.reply_to(message, f"\U0001F310 <b>IPs Conectadas al VPS:</b>\n<code>{ips}</code>", parse_mode="HTML")

    elif text in [BTN_HIST, BTN_USO, BTN_LOGS, BTN_RANK]:
        bot.reply_to(message, "\u2139\uFE0F Esta funci\u00f3n se encuentra en desarrollo o almacenamiento local.", parse_mode="HTML")


# ==========================================
# PROCESADORES INTERNOS
# ==========================================

def process_add_revendedor(message):
    if is_menu_button(message.text): return handle_message(message)
    try:
        target_id, creditos = message.text.split()
        creditos = int(creditos)
        exp_date = (datetime.datetime.now() + datetime.timedelta(days=365)).strftime("%Y-%m-%d")
        
        users = load_auth()
        creds = load_credits()
        users[target_id] = exp_date
        creds[target_id] = creds.get(target_id, 0) + creditos
        save_auth(users)
        save_credits(creds)
        
        bot.reply_to(message, f"\u2705 <b>REVENDEDOR AÑADIDO</b>\n\U0001F194 <b>ID:</b> <code>{target_id}</code>\n\U0001F4B0 <b>Créditos:</b> {creditos}\n\nEl revendedor ya puede autorizar clientes.", parse_mode="HTML")
    except: 
        bot.reply_to(message, "\u274C Formato incorrecto. Usa: ID CRÉDITOS", parse_mode="HTML")

def process_add_cliente(message):
    uid = str(message.from_user.id)
    if is_menu_button(message.text): return handle_message(message)
    try:
        target_id, days = message.text.split()
        days = int(days)
        
        creds = load_credits()
        if creds.get(uid, 0) < 1:
            bot.reply_to(message, "\u274C <b>Fondos insuficientes.</b> No tienes créditos para autorizar clientes.", parse_mode="HTML")
            return
            
        creds[uid] -= 1
        save_credits(creds)
        
        exp_date = (datetime.datetime.now() + datetime.timedelta(days=days)).strftime("%Y-%m-%d")
        users = load_auth()
        users[target_id] = exp_date
        save_auth(users)
        
        bot.reply_to(message, f"\u2705 <b>CLIENTE AUTORIZADO</b>\n\U0001F194 <b>ID:</b> <code>{target_id}</code>\n\u23F3 <b>Vence:</b> {exp_date} ({days} d\u00edas)\n\U0001F4B0 <b>Tus créditos:</b> {creds[uid]}", parse_mode="HTML")
    except: 
        bot.reply_to(message, "\u274C Formato incorrecto. Usa: ID DIAS", parse_mode="HTML")

def process_renew_revendedor(message):
    if is_menu_button(message.text): return handle_message(message)
    try:
        target_id, creditos = message.text.split()
        creditos = int(creditos)
        
        users = load_auth()
        if target_id not in users:
            bot.reply_to(message, "\u274C El ID no está registrado.", parse_mode="HTML")
            return
            
        creds = load_credits()
        creds[target_id] = creds.get(target_id, 0) + creditos
        save_credits(creds)
        
        bot.reply_to(message, f"\U0001F504 <b>RENOVACIÓN EXITOSA</b>\n\U0001F194 <b>ID:</b> <code>{target_id}</code>\n\U0001F4B0 <b>Nuevos Créditos Totales:</b> {creds[target_id]}", parse_mode="HTML")
    except: 
        bot.reply_to(message, "\u274C Formato incorrecto. Usa: ID CRÉDITOS", parse_mode="HTML")

def process_renew_cliente(message):
    uid = str(message.from_user.id)
    if is_menu_button(message.text): return handle_message(message)
    try:
        target_id, days = message.text.split()
        days = int(days)
        
        users = load_auth()
        if target_id not in users:
            bot.reply_to(message, "\u274C El ID de cliente no está registrado.", parse_mode="HTML")
            return
            
        creds = load_credits()
        if creds.get(uid, 0) < 1:
            bot.reply_to(message, "\u274C <b>Fondos insuficientes.</b> Necesitas 1 crédito para renovar clientes.", parse_mode="HTML")
            return
            
        creds[uid] -= 1
        save_credits(creds)
        
        current_exp = datetime.datetime.strptime(users[target_id], "%Y-%m-%d")
        if current_exp < datetime.datetime.now():
            current_exp = datetime.datetime.now()
            
        new_exp_date = (current_exp + datetime.timedelta(days=days)).strftime("%Y-%m-%d")
        users[target_id] = new_exp_date
        save_auth(users)
        
        bot.reply_to(message, f"\U0001F504 <b>CLIENTE RENOVADO</b>\n\U0001F194 <b>ID:</b> <code>{target_id}</code>\n\u23F3 <b>Nuevo Vencimiento:</b> {new_exp_date}\n\U0001F4B0 <b>Tus créditos:</b> {creds[uid]}", parse_mode="HTML")
    except: 
        bot.reply_to(message, "\u274C Formato incorrecto. Usa: ID DIAS", parse_mode="HTML")

def process_del_user(message):
    if is_menu_button(message.text): return handle_message(message)
    target_id = message.text.strip()
    users = load_auth()
    
    if target_id in users:
        del users[target_id]
        save_auth(users)
        
        creds = load_credits()
        if target_id in creds:
            del creds[target_id]
            save_credits(creds)
            
        bot.reply_to(message, f"\u274C <b>USUARIO ELIMINADO</b>\nEl ID <code>{target_id}</code> ha perdido el acceso al bot.", parse_mode="HTML")
    else:
        bot.reply_to(message, f"\u26A0\uFE0F El ID <code>{target_id}</code> no se encontró en la base de datos.", parse_mode="HTML")

def process_find_user(message):
    if is_menu_button(message.text): return handle_message(message)
    target_id = message.text.strip()
    users = load_auth()
    creds = load_credits()
    if target_id in users:
        bot.reply_to(message, f"\U0001F50D <b>Usuario Encontrado</b>\n\U0001F194 ID: <code>{target_id}</code>\n\u23F3 Vence: <b>{users[target_id]}</b>\n\U0001F4B0 Créditos: <b>{creds.get(target_id, 0)}</b>", parse_mode="HTML")
    else:
        bot.reply_to(message, f"\u274C El ID <code>{target_id}</code> no está registrado.", parse_mode="HTML")

def process_broadcast(message):
    if is_menu_button(message.text): return handle_message(message)
    announcement = message.text
    users = load_auth()
    count = 0
    
    for target_id in users.keys():
        try:
            bot.send_message(target_id, f"\U0001F4E2 <b>AVISO IMPORTANTE</b>\n━━━━━━━━━━━━━━━━━━━━\n{announcement}", parse_mode="HTML")
            count += 1
        except:
            pass
            
    bot.reply_to(message, f"\u2705 Mensaje enviado exitosamente a <b>{count}</b> usuarios.", parse_mode="HTML")

def process_domain_a(message):
    if is_menu_button(message.text): return handle_message(message)
    try:
        sub, ip = message.text.split()
        full_domain = f"{sub}.{DOMAIN}"
        data = {"type": "A", "name": full_domain, "content": ip, "ttl": 1, "proxied": False}
        
        resp = cf_api_call("POST", "dns_records", data=data)
        if resp and resp.status_code == 200:
            bot.reply_to(message, f"\u2705 <b>Dominio A Creado Exitosamente:</b>\n<code>{full_domain}</code> ➔ <code>{ip}</code>", parse_mode="HTML")
        else:
            bot.reply_to(message, "\u274C <b>Error al crear el registro A en Cloudflare.</b>", parse_mode="HTML")
    except ValueError:
        bot.reply_to(message, "\u274C Formato incorrecto. Debes usar: subdominio IP", parse_mode="HTML")

def process_domain_ns(message):
    if is_menu_button(message.text): return handle_message(message)
    try:
        sub, target = message.text.split()
        full_domain = f"{sub}.{DOMAIN}"
        data = {"type": "NS", "name": full_domain, "content": target, "ttl": 1, "proxied": False}
        
        resp = cf_api_call("POST", "dns_records", data=data)
        if resp and resp.status_code == 200:
            bot.reply_to(message, f"\u2705 <b>Dominio NS Creado Exitosamente:</b>\n<code>{full_domain}</code> ➔ <code>{target}</code>", parse_mode="HTML")
        else:
            bot.reply_to(message, "\u274C <b>Error al crear el registro NS en Cloudflare.</b>", parse_mode="HTML")
    except ValueError:
        bot.reply_to(message, "\u274C Formato incorrecto. Debes usar: subdominio destino", parse_mode="HTML")

# ==========================================
# API FLASK (PARA VALIDAR LA KEY DESDE EL BASH INSTALLER)
# ==========================================
app = Flask(__name__)

@app.route('/verify', methods=['GET'])
def verify_key():
    key = request.args.get('key')
    ip = request.args.get('ip', 'Desconocida')
    
    if not key:
        return jsonify({"status": "error", "msg": "No enviaste una Key."}), 400
    
    # notify_key_usage quema la key, manda el mensaje de telegram al dueño y retorna True
    is_valid = notify_key_usage(key, ip)
    
    if is_valid:
        return jsonify({"status": "valid", "msg": "Key autorizada. Procediendo."}), 200
    else:
        return jsonify({"status": "invalid", "msg": "Key invalida o ya usada."}), 403

def run_api():
    # Iniciamos API en puerto 8888
    app.run(host='0.0.0.0', port=8888, debug=False, use_reloader=False)

if __name__ == "__main__":
    # Corremos Flask en un hilo separado
    api_thread = threading.Thread(target=run_api, daemon=True)
    api_thread.start()
    print("✅ API Flask iniciada en puerto 8888 para validar keys...")
    
    while True:
        try:
            bot.polling(none_stop=True)
        except Exception as e:
            time.sleep(5)
