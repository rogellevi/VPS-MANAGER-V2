#!/bin/bash
# ==========================================================
# SSH WebSocket Interno (Puerto 10015 para HAProxy TCP)
# ==========================================================
SERVICE_NAME="ssh-ws"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
PROXY_FILE="/etc/vps-manager/core/proxy.py"

c_red='\033[1;31m'; c_green='\033[1;32m'; c_yellow='\033[1;33m'; c_nc='\033[0m'

install_proxy() {
    echo -e "${c_yellow}[*] Configurando dependencias y algoritmos SSH...${c_nc}"
    apt-get install -y python3 >/dev/null 2>&1
    
    mkdir -p /etc/ssh/sshd_config.d
    cat << 'SSHCONF' > /etc/ssh/sshd_config.d/httpcustom.conf
KexAlgorithms +diffie-hellman-group14-sha1,diffie-hellman-group-exchange-sha1
Ciphers +aes128-ctr,aes256-ctr
MACs +hmac-sha1,hmac-sha1-96
HostKeyAlgorithms +ssh-rsa,ssh-ed25519
PubkeyAcceptedAlgorithms +ssh-rsa
SSHCONF
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null

    systemctl stop ssh-ws ws-python >/dev/null 2>&1
    pkill -9 -f "proxy.py" >/dev/null 2>&1
    fuser -k 10015/tcp >/dev/null 2>&1

    cat > "${PROXY_FILE}" <<'PYEOF'
#!/usr/bin/env python3
import base64, hashlib, os, select, socket, subprocess, threading

LISTEN_PORT = 10015
SSH_HOST = '127.0.0.1'
SSH_PORT = 22
BUFFER_SIZE = 65536
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

def get_user_data(username):
    data = {"exp": "Ilimitado", "dias": "Ilimitado", "limite": "Desconocido"}
    try:
        chage_out = subprocess.check_output(["chage", "-l", username], stderr=subprocess.STDOUT, timeout=2).decode("utf-8", errors="ignore")
        for line in chage_out.split("\n"):
            if "Account expires" in line or "La cuenta caduca" in line:
                d_str = line.split(":", 1)[1].strip()
                if d_str != "never":
                    data["exp"] = d_str
                    break
    except: pass
    try:
        limit_path = f"/root/usuarios/{username}.limit"
        if os.path.exists(limit_path):
            with open(limit_path, "r") as f: data["limite"] = f.read().strip()
    except: pass
    return data

def _extract_headers(raw):
    text = raw.decode("iso-8859-1", errors="replace")
    ws_key, ssh_user = None, None
    for line in text.replace("\r\n", "\n").split("\n"):
        line = line.strip()
        if ":" not in line: continue
        k, v = line.split(":", 1)
        k_low, v_clean = k.strip().lower(), v.strip()
        if k_low == "sec-websocket-key" and v_clean: ws_key = v_clean
        elif k_low in ("x-user", "ssh-user") and v_clean: ssh_user = v_clean
    return ws_key, ssh_user

def _build_response(ws_key, ssh_user, raw_req):
    req_str = raw_req.decode("iso-8859-1", errors="ignore").lower()
    if "upgrade: websocket" in req_str:
        headers = ["HTTP/1.1 101 Switching Protocols", "Upgrade: websocket", "Connection: Upgrade"]
        if ws_key:
            digest = hashlib.sha1((ws_key + WS_GUID).encode("ascii")).digest()
            headers.append(f"Sec-WebSocket-Accept: {base64.b64encode(digest).decode('ascii')}")
    elif "expect: 100-continue" in req_str:
        headers = ["HTTP/1.1 100 Continue"]
    elif req_str.startswith("connect"):
        headers = ["HTTP/1.1 200 Connection Established"]
    else:
        headers = ["HTTP/1.1 200 OK"]
    
    resp = "\r\n".join(headers) + "\r\n\r\n"
    if ssh_user and os.path.exists("/etc/issue.net"):
        try:
            with open("/etc/issue.net", "r") as f: banner = f.read()
            u_data = get_user_data(ssh_user)
            banner = banner.replace("%USER%", ssh_user).replace("%EXP%", u_data["exp"]).replace("%DIAS%", u_data["dias"]).replace("%LIMITE%", u_data["limite"])
            resp += banner + "\r\n"
        except: pass
    return resp.encode("utf-8", errors="ignore")

def relay(client, target, initial, already_sent):
    ssh_started = False
    if initial:
        ssh_pos = initial.find(b"SSH-")
        if ssh_pos != -1:
            ssh_started = True
            target.sendall(initial[ssh_pos:])

    sockets = [client, target]
    while True:
        r, _, e = select.select(sockets, [], sockets, 300)
        if e or not r: break
        for s in r:
            data = s.recv(BUFFER_SIZE)
            if not data: return
            if s is client:
                if not ssh_started:
                    ssh_pos = data.find(b"SSH-")
                    if ssh_pos != -1:
                        ssh_started = True
                        if ssh_pos > 0 and not already_sent:
                            w, u = _extract_headers(data[:ssh_pos])
                            client.sendall(_build_response(w, u, data[:ssh_pos]))
                            already_sent = True
                        target.sendall(data[ssh_pos:])
                    else:
                        if b"upgrade: websocket" in data.lower() or not already_sent:
                            w, u = _extract_headers(data)
                            client.sendall(_build_response(w, u, data))
                            already_sent = True
                    continue
                target.sendall(data)
            else:
                client.sendall(data)

def handle(c):
    t = None
    try:
        c.settimeout(10.0)
        try: first = c.recv(BUFFER_SIZE)
        except socket.timeout: first = b""
        c.settimeout(None)
        
        t = socket.create_connection((SSH_HOST, SSH_PORT), timeout=8)
        t.settimeout(None)
        
        if not first:
            relay(c, t, b"", True)
            return
        if first.startswith(b"SSH-"):
            relay(c, t, first, True)
            return
            
        data = bytearray(first)
        if b"upgrade: websocket" not in data.lower() and b"SSH-" not in data:
            r, _, _ = select.select([c], [], [], 0.15)
            if r:
                try:
                    more = c.recv(BUFFER_SIZE)
                    if more: data.extend(more)
                except: pass
                
        raw = bytes(data)
        w, u = _extract_headers(raw)
        c.sendall(_build_response(w, u, raw))
        relay(c, t, raw, True)
    except: pass
    finally:
        c.close()
        if t: 
            try: t.close() 
            except: pass

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('0.0.0.0', LISTEN_PORT))
server.listen(1024)
while True:
    try:
        c, _ = server.accept()
        threading.Thread(target=handle, args=(c,), daemon=True).start()
    except: pass
PYEOF
    chmod +x "${PROXY_FILE}"
    cp -f "${PROXY_FILE}" /etc/vps-manager/core/sshws_proxy.py

    cat > "${SERVICE_FILE}" <<SERVICEEOF
[Unit]
Description=Golbert SSH WebSocket Engine (10015)
After=network.target ssh.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 -u ${PROXY_FILE}
Restart=always
RestartSec=2
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
Alias=ws-python.service
SERVICEEOF

    ln -sf "${SERVICE_FILE}" /etc/systemd/system/ws-python.service
    systemctl daemon-reload
    systemctl enable --now ssh-ws >/dev/null 2>&1
    systemctl restart ssh-ws
    echo -e "${c_green}[✔] SSH WebSocket Dinámico activo en el puerto 10015.${c_nc}"
}

case "${1:-menu}" in
    install) install_proxy ;;
    stop|disable) systemctl disable --now ssh-ws ws-python 2>/dev/null ;;
    status) systemctl --no-pager status ssh-ws ;;
    *) install_proxy ;;
esac
