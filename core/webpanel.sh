#!/bin/bash
# ==========================================
# Módulo: Panel Web Ultra PRO (Multi-Rol: Admin / Revendedor)
# ==========================================
C_RED='\033[1;31m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_CYAN='\033[1;36m'; C_NC='\033[0m'
WEB_DIR="/etc/vps-manager/webpanel"

clear
echo -e "${C_CYAN}================================================${C_NC}"
echo -e "${C_GREEN}    INSTALADOR WEB PANEL PRO (MULTI-ROL)        ${C_NC}"
echo -e "${C_CYAN}================================================${C_NC}"

read -p "Crea un Usuario DUEÑO para el Web: " WEB_USER
read -p "Crea una Contraseña DUEÑO para el Web: " WEB_PASS

apt update -y >/dev/null 2>&1
apt install -y python3 python3-pip python3-venv uuid-runtime jq >/dev/null 2>&1

mkdir -p "$WEB_DIR"
cd "$WEB_DIR"
rm -rf venv
python3 -m venv venv
source venv/bin/activate
pip install Flask >/dev/null 2>&1

# ==========================================
# CÓDIGO PYTHON / FLASK Y DISEÑO HTML
# ==========================================
cat << 'EOF' > "$WEB_DIR/app.py"
from flask import Flask, render_template_string, request, session, redirect, url_for
import subprocess
import os
import uuid
import base64
import json
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = 'golbert_pro_secret_key_2026_multirol'

# --- CONFIGURACIÓN ---
USER_ADMIN = "REPLACE_USER"
PASS_ADMIN = "REPLACE_PASS"
PORT_NGINX = "81" 
XRAY_CONFIG = "/usr/local/etc/xray/config.json"
DB_FILE = "/etc/vps-manager/panel_db.json"

# --- BASE DE DATOS LOCAL MULTI-ROL ---
def load_db():
    if not os.path.exists(DB_FILE):
        os.makedirs(os.path.dirname(DB_FILE), exist_ok=True)
        with open(DB_FILE, 'w') as f:
            json.dump({"resellers": {}, "v2ray": {}, "ssh": {}}, f)
    try:
        with open(DB_FILE, 'r') as f:
            data = json.load(f)
            if "resellers" not in data: data["resellers"] = {}
            if "v2ray" not in data: data["v2ray"] = {}
            if "ssh" not in data: data["ssh"] = {}
            return data
    except:
        return {"resellers": {}, "v2ray": {}, "ssh": {}}

def save_db(data):
    with open(DB_FILE, 'w') as f:
        json.dump(data, f, indent=2)

# --- MIDDLEWARES ---
def login_required(f):
    def decorated_function(*args, **kwargs):
        if 'logged_in' not in session:
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    decorated_function.__name__ = f.__name__
    return decorated_function

def is_admin():
    return session.get('role') == 'admin'

# --- RUTAS ---
@app.route('/login', methods=['GET', 'POST'])
def login():
    error = None
    if request.method == 'POST':
        user = request.form['username'].strip()
        pwd = request.form['password'].strip()
        
        db = load_db()
        
        if user == USER_ADMIN and pwd == PASS_ADMIN:
            session['logged_in'] = True
            session['role'] = 'admin'
            session['username'] = 'Administrador'
            return redirect(url_for('index'))
        elif user in db['resellers'] and db['resellers'][user]['password'] == pwd:
            session['logged_in'] = True
            session['role'] = 'reseller'
            session['username'] = user
            return redirect(url_for('index'))
        else:
            error = 'Credenciales inválidas'
    
    html = """
    <!DOCTYPE html>
    <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Login - Panel MultiRol</title>
    <style>
        body { background-color: #0a0e17; color: #fff; font-family: sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .login-box { background: #131b2f; padding: 30px; border-radius: 15px; text-align: center; width: 300px; border: 1px solid #1f2d4a; box-shadow: 0 4px 15px rgba(0,0,0,0.5); }
        .login-box h2 { color: #60efff; margin-bottom: 20px; }
        input { width: 90%; padding: 12px; margin: 10px 0; border-radius: 8px; border: 1px solid #1f2d4a; background: #0a0e17; color: white; }
        button { width: 100%; padding: 12px; border: none; border-radius: 8px; background: #28a745; color: white; font-weight: bold; cursor: pointer; margin-top: 10px; font-size: 16px; }
    </style></head>
    <body>
        <div class="login-box">
            <h2>🛡️ Panel de Accesos<br><small style="font-size:12px;color:#8c9baf;">GOLBERT VPS</small></h2>
            {% if error %}<p style="color:#dc3545;font-size:14px;">{{ error }}</p>{% endif %}
            <form method="post">
                <input type="text" name="username" placeholder="Usuario" required>
                <input type="password" name="password" placeholder="Contraseña" required>
                <button type="submit">🚀 Ingresar</button>
            </form>
        </div>
    </body></html>
    """
    return render_template_string(html, error=error)

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

@app.route('/')
@login_required
def index():
    db = load_db()
    role = session.get('role')
    curr_user = session.get('username')
    
    # Textos dinámicos simplificados para evitar errores de sintaxis
    txt_renovar = "Se descontara 1 credito." if role == 'reseller' else "Accion gratuita."
    txt_crear = "(Gasta 1 Crédito)" if role == 'reseller' else "(Gratis)"
    
    # Obtener créditos si es revendedor
    credits = db['resellers'].get(curr_user, {}).get('credits', 0) if role == 'reseller' else "Ilimitado"
    
    # 1. Escanear Usuarios SSH
    ssh_users = []
    users_raw = subprocess.getoutput("awk -F: '$3 >= 1000 && $1 != \"nobody\" {print $1}' /etc/passwd").split('\n')
    for u in users_raw:
        if not u.strip(): continue
        
        # Filtro de aislamiento para revendedores
        owner = db['ssh'].get(u, {}).get('owner', 'admin')
        if role == 'reseller' and owner != curr_user:
            continue
            
        exp_date = subprocess.getoutput(f"chage -l {u} | grep 'Account expires' | awk -F': ' '{{print $2}}'")
        try:
            sec_exp = int(subprocess.getoutput(f"date -d '{exp_date}' +%s 2>/dev/null || echo 0"))
            dias = int((sec_exp - int(subprocess.getoutput("date +%s"))) / 86400)
        except: dias = 999
        ssh_users.append({"alias": u, "tipo": "SSH", "dias": dias, "exp": exp_date.strip(), "owner": owner})

    # 2. Escanear Usuarios V2Ray
    v2ray_users = []
    for token, data in db.get("v2ray", {}).items():
        owner = data.get('owner', 'admin')
        if role == 'reseller' and owner != curr_user:
            continue
            
        try:
            exp_date_obj = datetime.strptime(data["exp"], "%Y-%m-%d")
            dias = (exp_date_obj - datetime.now()).days
            v2ray_users.append({"alias": data["alias"], "tipo": "TOKEN", "dias": dias, "exp": data["exp"], "token": token, "owner": owner})
        except: pass

    # Consolidar listas
    all_users = ssh_users + v2ray_users
    total_users = len(all_users)
    vencidos = sum(1 for u in all_users if u['dias'] <= 0)
    por_vencer = sum(1 for u in all_users if 0 < u['dias'] <= 3)

    user_cards = ""
    for u in sorted(all_users, key=lambda x: x['dias']):
        status_color = "#dc3545" if u['dias'] <= 0 else ("#fd7e14" if u['dias'] <= 3 else "#28a745")
        badge = f"<span style='background:#1f2d4a;padding:3px 8px;border-radius:5px;font-size:11px;color:#60efff;'>{u['tipo']}</span>"
        owner_badge = f"<span style='background:#b07d00;color:#fff;padding:2px 5px;border-radius:3px;font-size:10px;margin-left:5px;'>Resp: {u['owner']}</span>" if role == 'admin' else ""
        
        user_id_url = u['alias'] if u['tipo'] == 'SSH' else u['token']
        token_html = f"<p style='margin:2px 0;font-size:11px;color:#8c9baf;'>Token: {u['token'][:8]}...</p>" if u['tipo'] == 'TOKEN' else ""
        
        user_cards += f"""
        <div style="background:#131b2f; border:1px solid #1f2d4a; border-radius:12px; padding:15px; margin-bottom:12px;">
            <div style="display:flex; justify-content:space-between; margin-bottom:10px;">
                <strong style="font-size:16px;">{u['alias']} {owner_badge}</strong>
                <div>{badge} <span style="color:{status_color};font-weight:bold;font-size:12px;margin-left:5px;">●</span></div>
            </div>
            <p style="margin:2px 0;font-size:13px;color:#8c9baf;">Días restantes: <strong style="color:#fff;">{u['dias']}</strong> (Exp: {u['exp']})</p>
            {token_html}
            <div style="margin-top:10px; display:flex; gap:10px;">
                <a href="/renew/{u['tipo']}/{user_id_url}" onclick="return confirm('¿Renovar 30 días? {txt_renovar}')" style="background:#b07d00;color:#fff;padding:6px 12px;border-radius:6px;text-decoration:none;font-size:12px;flex:1;text-align:center;">⏱ Renovar</a>
                <a href="/delete/{u['tipo']}/{user_id_url}" onclick="return confirm('¿Eliminar permanente?')" style="background:#900a22;color:#fff;padding:6px 12px;border-radius:6px;text-decoration:none;font-size:12px;flex:1;text-align:center;">🗑 Borrar</a>
            </div>
        </div>
        """

    # Bloque exclusivo de Admin para gestionar revendedores
    admin_block = ""
    if role == 'admin':
        resellers_cards = ""
        for r_user, r_data in db['resellers'].items():
            resellers_cards += f"""
            <div style="background:#1a233a; padding:10px; border-radius:8px; margin-bottom:10px; border:1px solid #4facfe;">
                <strong>{r_user}</strong> | Créditos: <strong style="color:#60efff;">{r_data['credits']}</strong> 
                | Pass: {r_data['password']}
                <a href="/del_reseller/{r_user}" style="color:#dc3545; float:right; text-decoration:none;" onclick="return confirm('¿Eliminar revendedor?')">✖ Borrar</a>
            </div>
            """
            
        admin_block = f"""
        <h3 style="border-bottom:1px solid #1f2d4a; padding-bottom:10px; margin-top:30px; color:#4facfe;">👑 Panel Dueño: Revendedores</h3>
        <div style="background:#131b2f; padding:15px; border-radius:10px; margin-bottom:20px; border:1px solid #1f2d4a;">
            <form action="/add_reseller" method="POST" style="display:flex; gap:5px; margin-bottom:15px;">
                <input type="text" name="r_user" placeholder="Usuario" style="width:30%; padding:8px; border-radius:5px; border:1px solid #1f2d4a; background:#0a0e17; color:white;" required>
                <input type="text" name="r_pass" placeholder="Clave" style="width:30%; padding:8px; border-radius:5px; border:1px solid #1f2d4a; background:#0a0e17; color:white;" required>
                <input type="number" name="r_cred" placeholder="Créditos" style="width:20%; padding:8px; border-radius:5px; border:1px solid #1f2d4a; background:#0a0e17; color:white;" required>
                <button type="submit" style="width:20%; background:#007bff; color:white; border:none; border-radius:5px; cursor:pointer;">Crear/Editar</button>
            </form>
            {resellers_cards if resellers_cards else '<p style="color:#8c9baf;font-size:12px;">No hay revendedores.</p>'}
        </div>
        """

    html = f"""
    <!DOCTYPE html>
    <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Dashboard</title>
    <style>
        body {{ background-color: #0a0e17; color: #fff; font-family: sans-serif; margin: 0; padding: 15px; }}
        .header {{ display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }}
        .stats {{ display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; margin-bottom: 20px; }}
        .stat-box {{ background: #131b2f; padding: 15px; border-radius: 10px; text-align: center; border: 1px solid #1f2d4a; }}
        .stat-box h4 {{ margin: 0; font-size: 12px; color: #8c9baf; }}
        .stat-box h2 {{ margin: 5px 0 0 0; font-size: 24px; }}
        .btn-main {{ background: #28a745; color: white; padding: 12px; text-align: center; border-radius: 8px; text-decoration: none; font-weight: bold; display: block; margin-bottom: 20px; border: none; width: 100%; cursor:pointer; font-size:16px; }}
        .modal {{ display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); justify-content: center; align-items: center; z-index: 1000; }}
        .modal-content {{ background: #131b2f; padding: 20px; border-radius: 15px; width: 90%; max-width: 400px; border: 1px solid #1f2d4a; }}
        .modal input, .modal select {{ width: 100%; padding: 10px; margin: 8px 0 15px 0; border-radius: 8px; border: 1px solid #1f2d4a; background: #0a0e17; color: white; box-sizing: border-box; }}
        .close-btn {{ float: right; cursor: pointer; font-size: 20px; color: #dc3545; }}
    </style>
    </head><body>
        <div class="header">
            <div><h3 style="margin:0;color:#60efff;">{curr_user}</h3><small>{'Administrador Supremo' if role=='admin' else 'Revendedor Autorizado'}</small></div>
            <a href="/logout" style="color:#dc3545;text-decoration:none;font-weight:bold;">Salir 🚪</a>
        </div>

        <button onclick="checkCredits()" class="btn-main">➕ Crear Usuario</button>

        <div class="stats">
            <div class="stat-box" style="border-top:3px solid #007bff;"><h4>MIS USUARIOS</h4><h2>{total_users}</h2></div>
            <div class="stat-box" style="border-top:3px solid #fd7e14;"><h4>POR VENCER</h4><h2>{por_vencer}</h2></div>
            <div class="stat-box" style="border-top:3px solid #dc3545;"><h4>VENCIDOS</h4><h2>{vencidos}</h2></div>
            <div class="stat-box" style="border-top:3px solid #60efff;"><h4>CRÉDITOS</h4><h2>{credits}</h2></div>
        </div>
        
        {admin_block}

        <h3 style="border-bottom:1px solid #1f2d4a; padding-bottom:10px;">📋 Lista de Clientes</h3>
        {user_cards if user_cards else '<p style="text-align:center;color:#8c9baf;">Sin usuarios activos</p>'}

        <div id="createModal" class="modal">
            <div class="modal-content">
                <span class="close-btn" onclick="document.getElementById('createModal').style.display='none'">✖</span>
                <h3 style="margin-top:0;">➕ Crear nueva cuenta</h3>
                <form action="/create" method="POST" id="createForm">
                    <label style="font-size:12px;color:#8c9baf;">Tipo de cuenta</label>
                    <select name="type" id="accType" onchange="toggleFields()">
                        <option value="TOKEN">TOKEN ID (V2Ray / Vmess)</option>
                        <option value="SSH">SSH Normal (Dropbear/UDP)</option>
                    </select>
                    <label style="font-size:12px;color:#8c9baf;">Alias del cliente</label>
                    <input type="text" name="alias" placeholder="Ej: Juan" required pattern="[A-Za-z0-9_-]+" title="Sin espacios ni caracteres especiales">
                    <div id="tokenField">
                        <label style="font-size:12px;color:#8c9baf;">Token (Generado auto)</label>
                        <input type="text" name="token" value="{str(uuid.uuid4())}">
                    </div>
                    <div id="sshFields" style="display:none;">
                        <label style="font-size:12px;color:#8c9baf;">Contraseña SSH</label>
                        <input type="text" name="password" placeholder="Pass123">
                    </div>
                    <label style="font-size:12px;color:#8c9baf;">Días (máximo 30)</label>
                    <input type="number" name="days" value="30" required>
                    <button type="submit" class="btn-main" style="margin-top:10px; background:#007bff;" onclick="showLoading()">Crear {txt_crear}</button>
                </form>
                <div id="loadingOverlay" style="display:none; text-align:center; padding:20px 0;">
                    <h3 style="color:#60efff;">⏳ Procesando...</h3>
                </div>
            </div>
        </div>

        <script>
            function checkCredits() {{
                var role = '{role}';
                var creds = '{credits}';
                if (role === 'reseller' && parseInt(creds) <= 0) {{
                    alert('❌ Créditos agotados.\\n\\nPor favor, contacta con tu vendedor para recargar créditos.');
                }} else {{
                    document.getElementById('createModal').style.display='flex';
                }}
            }}
            function toggleFields() {{
                let type = document.getElementById('accType').value;
                document.getElementById('tokenField').style.display = type === 'TOKEN' ? 'block' : 'none';
                document.getElementById('sshFields').style.display = type === 'SSH' ? 'block' : 'none';
            }}
            function showLoading() {{
                document.getElementById('createForm').style.display = 'none';
                document.getElementById('loadingOverlay').style.display = 'block';
            }}
        </script>
    </body></html>
    """
    return html

@app.route('/create', methods=['POST'])
@login_required
def create():
    db = load_db()
    role = session.get('role')
    curr_user = session.get('username')
    
    if role == 'reseller' and db['resellers'].get(curr_user, {}).get("credits", 0) <= 0:
        return "<script>alert('Créditos agotados.'); window.location='/';</script>"

    tipo = request.form.get('type')
    alias = "".join(e for e in request.form.get('alias') if e.isalnum() or e in ['_','-'])
    dias = int(request.form.get('days'))
    exp_date = (datetime.now() + timedelta(days=dias)).strftime('%Y-%m-%d')
    host = subprocess.getoutput("[ -f /etc/vps-manager/dominio ] && cat /etc/vps-manager/dominio || curl -s ipv4.icanhazip.com")
    
    if tipo == "TOKEN":
        token = request.form.get('token').strip()
        try:
            with open(XRAY_CONFIG, 'r') as f: data = json.load(f)
            data['inbounds'][0]['settings']['clients'].append({"id": token, "email": alias, "alterId": 0})
            with open(XRAY_CONFIG, 'w') as f: json.dump(data, f, indent=2)
            subprocess.getoutput("systemctl restart xray")
            
            db["v2ray"][token] = {"alias": alias, "exp": exp_date, "owner": curr_user}
            
            vmess_j = f'{{"v":"2","ps":"{alias}","add":"{host}","port":"{PORT_NGINX}","id":"{token}","aid":"0","scy":"auto","net":"ws","type":"none","host":"{host}","path":"/vmess","tls":"","sni":"","alpn":""}}'
            vmess_link = f"vmess://{base64.b64encode(vmess_j.encode('utf-8')).decode('utf-8')}"
            
            comprobante = f"Tipo: TOKEN\nAlias: {alias}\nToken: {token}\nHost: {host}\nExpira: {exp_date}\n\nLink:\n{vmess_link}"
        except Exception as e:
            return f"Error XRAY (Verifica que este instalado): {str(e)}"

    elif tipo == "SSH":
        password = request.form.get('password').strip()
        subprocess.getoutput(f"useradd -e {exp_date} -s /bin/false -M {alias} && echo '{alias}:{password}' | chpasswd")
        subprocess.getoutput(f"echo '1' > /etc/vps-manager/limite_{alias}")
        db["ssh"][alias] = {"owner": curr_user}
        comprobante = f"Tipo: SSH\nAlias: {alias}\nPass: {password}\nHost: {host}\nExpira: {exp_date}"

    if role == 'reseller':
        db['resellers'][curr_user]["credits"] -= 1
    save_db(db)

    html = f"""
    <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body {{ background:#0a0e17; color:#fff; font-family:sans-serif; padding:20px; }}
        .receipt {{ background:#131b2f; border:1px solid #28a745; border-radius:10px; padding:20px; }}
        textarea {{ width:100%; height:150px; background:#0a0e17; color:#60efff; border:1px solid #1f2d4a; padding:10px; margin-top:15px; box-sizing:border-box; }}
        .btn {{ display:block; text-align:center; background:#007bff; color:white; text-decoration:none; padding:12px; border-radius:8px; margin-top:20px; font-weight:bold; }}
    </style></head><body>
        <div class="receipt">
            <h2 style="color:#28a745; margin-top:0;">✅ Creado – {alias}</h2>
            <p><strong>Tipo:</strong> {tipo}</p>
            <p><strong>Expiración:</strong> {exp_date} ({dias} días)</p>
            <label style="font-size:12px;color:#8c9baf;">COMPROBANTE PARA EL CLIENTE:</label>
            <textarea id="compText" readonly>{comprobante}</textarea>
            <button onclick="navigator.clipboard.writeText(document.getElementById('compText').value); alert('Copiado');" style="background:#1f2d4a; color:white; border:none; padding:10px; border-radius:5px; margin-top:10px; cursor:pointer; width:100%;">📋 Copiar comprobante</button>
        </div>
        <a href="/" class="btn">Volver al Panel</a>
    </body></html>
    """
    return html

@app.route('/renew/<tipo>/<uid>')
@login_required
def renew_user(tipo, uid):
    db = load_db()
    role = session.get('role')
    curr_user = session.get('username')
    
    if role == 'reseller':
        if db['resellers'].get(curr_user, {}).get("credits", 0) <= 0:
            return "<script>alert('Créditos agotados.'); window.location='/';</script>"
        if tipo == 'SSH' and db['ssh'].get(uid, {}).get('owner') != curr_user:
            return redirect(url_for('index'))
        if tipo == 'TOKEN' and db['v2ray'].get(uid, {}).get('owner') != curr_user:
            return redirect(url_for('index'))

    if tipo == "SSH":
        subprocess.getoutput(f"chage -E $(date -d '+30 days' +'%Y-%m-%d') {uid}")
    elif tipo == "TOKEN":
        if uid in db.get("v2ray", {}):
            db["v2ray"][uid]["exp"] = (datetime.now() + timedelta(days=30)).strftime('%Y-%m-%d')
    
    if role == 'reseller':
        db['resellers'][curr_user]["credits"] -= 1
    save_db(db)
    return redirect(url_for('index'))

@app.route('/delete/<tipo>/<uid>')
@login_required
def delete_user(tipo, uid):
    db = load_db()
    role = session.get('role')
    curr_user = session.get('username')
    
    if role == 'reseller':
        if tipo == 'SSH' and db['ssh'].get(uid, {}).get('owner') != curr_user:
            return redirect(url_for('index'))
        if tipo == 'TOKEN' and db['v2ray'].get(uid, {}).get('owner') != curr_user:
            return redirect(url_for('index'))

    if tipo == "SSH":
        subprocess.getoutput(f"userdel -f {uid}")
        if uid in db["ssh"]: del db["ssh"][uid]
    elif tipo == "TOKEN":
        try:
            with open(XRAY_CONFIG, 'r') as f: data = json.load(f)
            data['inbounds'][0]['settings']['clients'] = [c for c in data['inbounds'][0]['settings']['clients'] if c['id'] != uid]
            with open(XRAY_CONFIG, 'w') as f: json.dump(data, f, indent=2)
            subprocess.getoutput("systemctl restart xray")
            if uid in db["v2ray"]: del db["v2ray"][uid]
        except: pass
        
    save_db(db)
    return redirect(url_for('index'))

# --- RUTAS EXCLUSIVAS DE ADMIN ---
@app.route('/add_reseller', methods=['POST'])
@login_required
def add_reseller():
    if not is_admin(): return redirect(url_for('index'))
    r_user = request.form.get('r_user').strip()
    r_pass = request.form.get('r_pass').strip()
    r_cred = int(request.form.get('r_cred'))
    
    db = load_db()
    db['resellers'][r_user] = {"password": r_pass, "credits": r_cred}
    save_db(db)
    return redirect(url_for('index'))

@app.route('/del_reseller/<r_user>')
@login_required
def del_reseller(r_user):
    if not is_admin(): return redirect(url_for('index'))
    db = load_db()
    if r_user in db['resellers']:
        del db['resellers'][r_user]
        save_db(db)
    return redirect(url_for('index'))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8181)
EOF

sed -i "s/REPLACE_USER/$WEB_USER/g" "$WEB_DIR/app.py"
sed -i "s/REPLACE_PASS/$WEB_PASS/g" "$WEB_DIR/app.py"

iptables -I INPUT -p tcp --dport 8181 -j ACCEPT
iptables-save > /etc/iptables.up.rules 2>/dev/null

cat << EOF > /etc/systemd/system/vps-webpanel.service
[Unit]
Description=Golbert VPS Web Panel PRO
After=network.target

[Service]
User=root
WorkingDirectory=$WEB_DIR
ExecStart=$WEB_DIR/venv/bin/python $WEB_DIR/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vps-webpanel >/dev/null 2>&1
systemctl restart vps-webpanel

IP_VPS=$(curl -s ipv4.icanhazip.com)
clear
echo -e "${C_GREEN}[✔] ¡Panel Web PRO Instalado!${C_NC}\nURL: ${C_YELLOW}http://$IP_VPS:8181${C_NC}"
read -p "Presione Enter para regresar..."
