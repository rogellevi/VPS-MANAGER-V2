#!/usr/bin/env python3
"""
Gateway SSH-WebSocket Multiconexiones de Alto Rendimiento para HAProxy.
- Soporta payloads simples, múltiples bloques [split] y métodos personalizados (PUT, X, PROPATCH, etc.).
- Respuesta dinámica: HTTP 101, 100 o 200 según el método solicitado por el cliente.
- Filtra el 100% de cabeceras HTTP residuales antes de entregar el flujo SSH-2.0 a OpenSSH (puerto 22).
- Optimizado con TCP_NODELAY y SO_KEEPALIVE para multiconexiones simultáneas sin latencia.
"""
from __future__ import annotations

import base64
import hashlib
import logging
import os
import select
import socket
import subprocess
import threading
from typing import Dict, Optional, Tuple

LISTEN_HOST = os.getenv("SSHWS_LISTEN_HOST", "0.0.0.0")
LISTEN_PORTS_ENV = os.getenv("SSHWS_LISTEN_PORTS", "10080,8080")
SSH_HOST = os.getenv("SSHWS_SSH_HOST", "127.0.0.1")
SSH_PORT = int(os.getenv("SSHWS_SSH_PORT", "22"))

BUFFER_SIZE = 65536
HANDSHAKE_TIMEOUT = 10.0
SPLIT_WAIT_TIMEOUT = 0.15
SELECT_TIMEOUT = 300.0
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

logging.basicConfig(
    level=os.getenv("SSHWS_LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(message)s",
)
LOG = logging.getLogger("ssh-ws")


def configure_socket(sock: socket.socket) -> None:
    """Activa TCP_NODELAY y SO_KEEPALIVE para estabilidad en multiconexiones."""
    try:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    except OSError:
        pass
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
    except OSError:
        pass


def get_user_data(username: str) -> Dict[str, str]:
    data = {"exp": "Ilimitado", "dias": "Ilimitado", "limite": "Desconocido"}
    try:
        chage_out = subprocess.check_output(
            ["chage", "-l", username], stderr=subprocess.STDOUT, timeout=2
        ).decode("utf-8", errors="ignore")
        for line in chage_out.split("\n"):
            if "Account expires" in line or "La cuenta caduca" in line:
                date_str = line.split(":", 1)[1].strip()
                if date_str != "never":
                    data["exp"] = date_str
                    break
    except Exception:
        pass
    try:
        limit_path = f"/root/usuarios/{username}.limit"
        if os.path.exists(limit_path):
            with open(limit_path, "r", encoding="utf-8", errors="ignore") as f:
                data["limite"] = f.read().strip()
    except Exception:
        pass
    return data


def _websocket_accept(key: str) -> str:
    digest = hashlib.sha1((key.strip() + WS_GUID).encode("ascii")).digest()
    return base64.b64encode(digest).decode("ascii")


def _extract_headers_info(raw: bytes) -> Tuple[Optional[str], Optional[str], bool]:
    """Extrae Sec-WebSocket-Key, X-User/SSH-User y detecta si hay petición de Upgrade."""
    text = raw.decode("iso-8859-1", errors="replace")
    ws_key: Optional[str] = None
    ssh_user: Optional[str] = None
    has_upgrade = False

    for line in text.replace("\r\n", "\n").split("\n"):
        line = line.strip()
        if not line or ":" not in line:
            continue
        k, v = line.split(":", 1)
        k_low = k.strip().lower()
        v_clean = v.strip()
        if k_low == "sec-websocket-key" and v_clean:
            ws_key = v_clean
        elif k_low in ("x-user", "ssh-user") and v_clean:
            ssh_user = v_clean
        elif k_low == "upgrade" and "websocket" in v_clean.lower():
            has_upgrade = True

    return ws_key, ssh_user, has_upgrade


def _build_dynamic_response(ws_key: Optional[str], ssh_user: Optional[str], raw_req: bytes) -> bytes:
    """Genera la respuesta HTTP adecuada (101, 100 o 200) evaluando el payload."""
    req_str = raw_req.decode("iso-8859-1", errors="ignore").lower()
    
    if "upgrade: websocket" in req_str:
        headers = [
            "HTTP/1.1 101 Switching Protocols",
            "Upgrade: websocket",
            "Connection: Upgrade"
        ]
        if ws_key:
            try:
                headers.append(f"Sec-WebSocket-Accept: {_websocket_accept(ws_key)}")
            except Exception:
                pass
    elif "expect: 100-continue" in req_str:
        headers = ["HTTP/1.1 100 Continue"]
    elif req_str.startswith("connect"):
        headers = ["HTTP/1.1 200 Connection Established"]
    else:
        headers = ["HTTP/1.1 200 OK"]

    response_str = "\r\n".join(headers) + "\r\n\r\n"

    # Insertar el banner solo si tenemos el usuario y el archivo existe
    if ssh_user and os.path.exists("/etc/issue.net"):
        try:
            with open("/etc/issue.net", "r", encoding="utf-8", errors="ignore") as f:
                banner_text = f.read()
            u_data = get_user_data(ssh_user)
            banner_text = (
                banner_text.replace("%USER%", ssh_user)
                .replace("%EXP%", u_data["exp"])
                .replace("%DIAS%", u_data["dias"])
                .replace("%LIMITE%", u_data["limite"])
            )
            response_str += banner_text + "\r\n"
        except Exception:
            pass

    return response_str.encode("utf-8", errors="ignore")


def _relay_multiconn(
    client: socket.socket,
    target: socket.socket,
    initial_to_ssh: bytes = b"",
    already_sent_response: bool = True,
) -> None:
    ssh_started = False
    if initial_to_ssh:
        ssh_pos = initial_to_ssh.find(b"SSH-")
        if ssh_pos != -1:
            ssh_started = True
            target.sendall(initial_to_ssh[ssh_pos:])

    sockets = (client, target)
    while True:
        readable, _, exceptional = select.select(sockets, [], sockets, SELECT_TIMEOUT)
        if exceptional:
            return
        if not readable:
            continue
        for source in readable:
            data = source.recv(BUFFER_SIZE)
            if not data:
                return
            if source is client:
                if not ssh_started:
                    ssh_pos = data.find(b"SSH-")
                    if ssh_pos != -1:
                        ssh_started = True
                        if ssh_pos > 0 and not already_sent_response:
                            ws_key, ssh_user, _ = _extract_headers_info(data[:ssh_pos])
                            client.sendall(_build_dynamic_response(ws_key, ssh_user, data[:ssh_pos]))
                            already_sent_response = True
                        target.sendall(data[ssh_pos:])
                    else:
                        if b"upgrade: websocket" in data.lower() or not already_sent_response:
                            ws_key, ssh_user, _ = _extract_headers_info(data)
                            client.sendall(_build_dynamic_response(ws_key, ssh_user, data))
                            already_sent_response = True
                    continue
                target.sendall(data)
            else:
                client.sendall(data)


def handle_client(client: socket.socket, address) -> None:
    target: Optional[socket.socket] = None
    try:
        configure_socket(client)
        client.settimeout(HANDSHAKE_TIMEOUT)

        try:
            first = client.recv(BUFFER_SIZE)
        except socket.timeout:
            first = b""

        target = socket.create_connection((SSH_HOST, SSH_PORT), timeout=8.0)
        configure_socket(target)
        target.settimeout(None)
        client.settimeout(None)

        if not first:
            _relay_multiconn(client, target, b"", already_sent_response=True)
            return

        if first.startswith(b"SSH-"):
            _relay_multiconn(client, target, first, already_sent_response=True)
            return

        data = bytearray(first)

        if b"upgrade: websocket" not in data.lower() and b"SSH-" not in data:
            r, _, _ = select.select([client], [], [], SPLIT_WAIT_TIMEOUT)
            if r:
                try:
                    more = client.recv(BUFFER_SIZE)
                    if more:
                        data.extend(more)
                except OSError:
                    pass

        raw_bytes = bytes(data)
        ws_key, ssh_user, _ = _extract_headers_info(raw_bytes)

        # Enviar respuesta dinámica basada en los encabezados reales recibidos
        client.sendall(_build_dynamic_response(ws_key, ssh_user, raw_bytes))

        _relay_multiconn(client, target, raw_bytes, already_sent_response=True)

    except (ConnectionError, OSError):
        pass
    except Exception:
        LOG.exception("Unexpected proxy error from %s", address)
    finally:
        for sock in (client, target):
            if sock is not None:
                try:
                    sock.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                try:
                    sock.close()
                except OSError:
                    pass


def serve_port(host: str, port: int) -> None:
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    except (AttributeError, OSError):
        pass
    server.bind((host, port))
    server.listen(4096)
    LOG.info("SSH-WS Dinámico escuchando en %s:%s -> %s:%s", host, port, SSH_HOST, SSH_PORT)
    try:
        while True:
            client, address = server.accept()
            threading.Thread(target=handle_client, args=(client, address), daemon=True).start()
    finally:
        server.close()


def main() -> None:
    ports = []
    for p in LISTEN_PORTS_ENV.split(","):
        p = p.strip()
        if p.isdigit():
            ports.append(int(p))
    if not ports:
        ports = [10080, 8080]

    threads = []
    for port in ports:
        t = threading.Thread(target=serve_port, args=(LISTEN_HOST, port), daemon=True)
        t.start()
        threads.append(t)

    for t in threads:
        t.join()


if __name__ == "__main__":
    main()
            
