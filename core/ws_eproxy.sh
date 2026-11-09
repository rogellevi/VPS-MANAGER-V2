#!/bin/bash
# ==========================================
# Gestor Python Proxy (Módulos Separados y Optimizados)
# 1. Modo WebSocket (101)  |  2. Modo HTTP Payload (200)
# ==========================================
C_CYAN='\033[1;36m'; C_ORANGE='\033[38;5;214m'; C_GREEN='\033[1;32m'; C_RED='\033[1;31m'; C_NC='\033[0m'
PROXY_DIR="/etc/vps-manager/proxy"
mkdir -p $PROXY_DIR

clear
echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
echo -e "       ${C_CYAN}GESTOR PYTHON PROXY (ALTO RENDIMIENTO)${C_NC}"
echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
echo -e " ${C_CYAN}1.${C_NC} Instalar Proxy WEBSOCKET (Responde 101)"
echo -e " ${C_CYAN}2.${C_NC} Instalar Proxy HTTP PAYLOAD (Responde 200)"
echo -e " ${C_RED}3.${C_NC} Desinstalar AMBOS Proxys y liberar puertos"
echo -e " ${C_CYAN}0.${C_NC} Volver al Menú Principal"
echo -e "${C_ORANGE}------------------------------------------------------${C_NC}"
read -p " Opción: " opc

case $opc in
    1)
        read -p "$(echo -e "\n${C_ORANGE}Puerto para el Proxy WebSocket (Ej: 80): ${C_NC}")" PORT_WS
        if ! [[ "$PORT_WS" =~ ^[0-9]+$ ]]; then echo -e " ${C_RED}Puerto inválido.${C_NC}"; sleep 2; exit; fi

        cat << 'PYEOF' > $PROXY_DIR/proxy_ws.py
import socket, threading, sys, select

def handle(client_socket):
    target = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    target.settimeout(5)
    try:
        target.connect(('127.0.0.1', 22))
        target.settimeout(None)
        
        client_socket.settimeout(5)
        first_data = client_socket.recv(8192)
        client_socket.settimeout(None)
        if not first_data:
            client_socket.close()
            return
            
        client_socket.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")

        def forward(s, d):
            try:
                while True:
                    r, _, _ = select.select([s], [], [], 300) 
                    if not r: break 
                    data = s.recv(8192)
                    if not data: break
                    d.sendall(data)
            except: pass
            finally:
                try: s.shutdown(socket.SHUT_RDWR)
                except: pass
                s.close()
                try: d.shutdown(socket.SHUT_RDWR)
                except: pass
                d.close()

        t1 = threading.Thread(target=forward, args=(client_socket, target))
        t2 = threading.Thread(target=forward, args=(target, client_socket))
        t1.daemon = True; t2.daemon = True
        t1.start(); t2.start()
    except:
        try: client_socket.close()
        except: pass

def main():
    port = int(sys.argv[1])
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 65536)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 65536)
    server.bind(('0.0.0.0', port))
    server.listen(1024)
    while True:
        try:
            client, _ = server.accept()
            t = threading.Thread(target=handle, args=(client,))
            t.daemon = True
            t.start()
        except: pass

if __name__ == '__main__':
    main()
PYEOF

        cat << SRVEOF > /etc/systemd/system/ws-proxy.service
[Unit]
Description=Python Proxy WebSocket (101)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PROXY_DIR
ExecStart=/usr/bin/python3 $PROXY_DIR/proxy_ws.py $PORT_WS
LimitNOFILE=65535
LimitNPROC=65535
TasksMax=infinity
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SRVEOF

        systemctl daemon-reload
        systemctl enable ws-proxy >/dev/null 2>&1
        systemctl restart ws-proxy
        echo -e "\n${C_GREEN}✅ Proxy WEBSOCKET operando fluido en el puerto $PORT_WS${C_NC}"
        read -p " Presiona Enter para volver..."
        ;;
        
    2)
        read -p "$(echo -e "\n${C_ORANGE}Puerto para el Proxy HTTP Payload (Ej: 8080): ${C_NC}")" PORT_HTTP
        if ! [[ "$PORT_HTTP" =~ ^[0-9]+$ ]]; then echo -e " ${C_RED}Puerto inválido.${C_NC}"; sleep 2; exit; fi

        cat << 'PYEOF' > $PROXY_DIR/proxy_http.py
import socket, threading, sys, select

def handle(client_socket):
    target = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    target.settimeout(5)
    try:
        target.connect(('127.0.0.1', 22))
        target.settimeout(None)
        
        client_socket.settimeout(5)
        first_data = client_socket.recv(8192)
        client_socket.settimeout(None)
        if not first_data:
            client_socket.close()
            return
            
        client_socket.sendall(b"HTTP/1.1 200 Connection established\r\n\r\n")

        def forward(s, d):
            try:
                while True:
                    r, _, _ = select.select([s], [], [], 300) 
                    if not r: break 
                    data = s.recv(8192)
                    if not data: break
                    d.sendall(data)
            except: pass
            finally:
                try: s.shutdown(socket.SHUT_RDWR)
                except: pass
                s.close()
                try: d.shutdown(socket.SHUT_RDWR)
                except: pass
                d.close()

        t1 = threading.Thread(target=forward, args=(client_socket, target))
        t2 = threading.Thread(target=forward, args=(target, client_socket))
        t1.daemon = True; t2.daemon = True
        t1.start(); t2.start()
    except:
        try: client_socket.close()
        except: pass

def main():
    port = int(sys.argv[1])
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 65536)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 65536)
    server.bind(('0.0.0.0', port))
    server.listen(1024)
    while True:
        try:
            client, _ = server.accept()
            t = threading.Thread(target=handle, args=(client,))
            t.daemon = True
            t.start()
        except: pass

if __name__ == '__main__':
    main()
PYEOF

        cat << SRVEOF > /etc/systemd/system/http-proxy.service
[Unit]
Description=Python Proxy HTTP Payload (200)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PROXY_DIR
ExecStart=/usr/bin/python3 $PROXY_DIR/proxy_http.py $PORT_HTTP
LimitNOFILE=65535
LimitNPROC=65535
TasksMax=infinity
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SRVEOF

        systemctl daemon-reload
        systemctl enable http-proxy >/dev/null 2>&1
        systemctl restart http-proxy
        echo -e "\n${C_GREEN}✅ Proxy HTTP PAYLOAD operando fluido en el puerto $PORT_HTTP${C_NC}"
        read -p " Presiona Enter para volver..."
        ;;
        
    3)
        systemctl stop ws-proxy http-proxy >/dev/null 2>&1
        systemctl disable ws-proxy http-proxy >/dev/null 2>&1
        rm -f /etc/systemd/system/ws-proxy.service /etc/systemd/system/http-proxy.service
        rm -rf $PROXY_DIR
        systemctl daemon-reload
        echo -e "\n${C_GREEN}✅ Ambos Proxys Python desinstalados.${C_NC}"
        read -p " Presiona Enter para volver..."
        ;;
    0) exit 0 ;;
esac
