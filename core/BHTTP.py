#!/usr/bin/env python3
"""BHTTP - concurrent HTTP-upgrade relay for an SSH service.

The server accepts direct BHTTP frames or an HTTP 101 upgrade, multiplexes
upload and download requests by a 16-byte session ID, reorders concurrent
chunks, and relays the resulting byte stream to a configured TCP target. It
also supports capability probes, batched downloads, replay-safe acknowledgments,
optional TLS listeners, and automatic cleanup of inactive sessions.

Frame layout: [1-byte mode][16-byte session ID][8-byte sequence][4-byte length].
Payloads use the protocol's SHA-256-derived XOR stream transformation.
Reversed and re-made by @forjad0 and @dragonnx9 and originally written by @DuTra01 (Dtunnel)
"""

import socket
import struct
import hashlib
import threading
import json
import time
import logging
import ipaddress
import select
import os
import ssl
import traceback
import sys
from dataclasses import dataclass, field
from typing import Optional, Dict, Tuple

# ─── Configuration ────────────────────────────────────────────────────────────

CONFIG = {
    "server": {
        "virtual_subnet_cidr": "10.10.0.0/16",
    },
    "proxy": {
        "listen": [
            {"host": "0.0.0.0", "port": 80, "ssl": False},
        ],
        "target": {"host": "127.0.0.1", "port": 22},
    },
    "tls": {
        "certificate": "/etc/ssl/certs/bhttp.crt",
        "private_key": "/etc/ssl/private/bhttp.key",
    },
}

# ─── Logging ──────────────────────────────────────────────────────────────────

logging.basicConfig(
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    level=logging.DEBUG,
)
log = logging.getLogger("BHTTP")

# ─── BHTTP Constants ──────────────────────────────────────────────────────────

MODE_PROBE    = 0
MODE_UPLOAD   = 1
MODE_DOWNLOAD = 2
MODE_BATCH    = 3
MODE_ACK      = 4

STATUS_OK      = 0
STATUS_DATA    = 2

HEADER_SIZE = 29  # 1+16+8+4
SESSIONS_LOCK = threading.Lock()

# ─── Legacy Packet Types ─────────────────────────────────────────────────────

PKT_AUTH       = 1
PKT_DATA       = 2
PKT_KEEPALIVE  = 3
PKT_DISCONNECT = 4
PKT_IP         = 5

# ─── BHTTP Stream Cipher ──────────────────────────────────────────────────────

def bhttp_crypt(data: bytes, sid: bytes, mode: int, seq: int, isr: bool) -> bytes:
    """
    SHA256-based stream cipher.
    isr=False -> sender (client upload / server download encoder)
    isr=True  -> receiver (server upload decoder / client download decoder)
    Note: The cipher is symmetric; isr just labels perspective, key is the same.
    """
    if not data:
        return b""
    out = bytearray(len(data))
    sb = bytearray(26)
    sb[0:16] = sid[:16]
    sb[16] = mode & 0xFF
    struct.pack_into(">Q", sb, 17, seq)
    sb[25] = 1 if isr else 0
    o = i = 0
    while o < len(data):
        k = hashlib.sha256(bytes(sb) + struct.pack(">I", i)).digest()
        n = min(32, len(data) - o)
        for j in range(n):
            out[o + j] = data[o + j] ^ k[j]
        o += n
        i += 1
    return bytes(out)

# ─── Legacy Packet Encoding/Decoding ────────────────────────────────────────
#
# Legacy packet layout (from marshalPacket / readPacketHeader):
#   [1B type][4B stream_id][4B payload_len][payload]
#

def encode_packet(pkt_type: int, stream_id: int, payload: bytes) -> bytes:
    return struct.pack(">BII", pkt_type, stream_id, len(payload)) + payload

def decode_packet(data: bytes) -> Tuple[int, int, bytes]:
    if len(data) < 9:
        raise ValueError(f"Packet too short: {len(data)} bytes")
    pkt_type, stream_id, plen = struct.unpack_from(">BII", data, 0)
    payload = data[9:9 + plen]
    return pkt_type, stream_id, payload

# ─── IP Pool ──────────────────────────────────────────────────────────────────

class IPPool:
    """Manages virtual IP assignment from a subnet."""

    def __init__(self, cidr: str):
        self.network = ipaddress.ip_network(cidr, strict=False)
        self.hosts = iter(self.network.hosts())
        next(self.hosts)  # skip .0.1 (gateway)
        self.assigned: Dict[str, str] = {}  # sid_hex -> ip
        self.lock = threading.Lock()

    def assign(self, sid_hex: str) -> Optional[str]:
        with self.lock:
            if sid_hex in self.assigned:
                return self.assigned[sid_hex]
            try:
                ip = str(next(self.hosts))
                self.assigned[sid_hex] = ip
                return ip
            except StopIteration:
                return None

    def release(self, sid_hex: str):
        with self.lock:
            self.assigned.pop(sid_hex, None)

    @property
    def subnet_mask(self) -> str:
        return str(self.network.netmask)

    @property
    def gateway(self) -> str:
        return str(next(self.network.hosts()))

# ─── Session ──────────────────────────────────────────────────────────────────

@dataclass
class Session:
    sid: bytes
    target: Optional[socket.socket] = None
    target_started: bool = False
    target_eof: bool = False
    target_error: str = ""
    banner_delivered: bool = False
    download_buffer: bytearray = field(default_factory=bytearray)
    upload_pending: Dict[int, bytes] = field(default_factory=dict)
    upload_next_seq: int = 0
    first_upload_logged: bool = False
    lock: threading.RLock = field(default_factory=threading.RLock)
    download_next_seq: int = 0
    download_acked_seq: int = -1
    download_closed: bool = False
    download_frames: Dict[int, bytes] = field(default_factory=dict)
    download_order_lock: threading.Lock = field(default_factory=threading.Lock)
    download_order: threading.Condition = field(init=False)
    ready: threading.Condition = field(init=False)
    last_seen: float = field(default_factory=time.time)

    def __post_init__(self):
        self.ready = threading.Condition(self.lock)
        self.download_order = threading.Condition(self.download_order_lock)

    def acknowledge_download(self, seq: int):
        with self.download_order:
            if seq <= self.download_acked_seq:
                return
            self.download_acked_seq = seq
            stale = [number for number in self.download_frames if number <= seq]
            for number in stale:
                self.download_frames.pop(number, None)

    def open_target(self, host: str, port: int) -> bool:
        with self.lock:
            if self.target is not None:
                return True
            if self.target_started:
                return not self.target_error
            self.target_started = True

        try:
            target = socket.create_connection((host, port), timeout=10)
            target.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            target.settimeout(None)
        except OSError as exc:
            with self.ready:
                self.target_error = str(exc)
                self.target_eof = True
                self.ready.notify_all()
            return False

        with self.ready:
            self.target = target
            self.ready.notify_all()
        threading.Thread(target=self._read_target, daemon=True).start()
        return True

    def _read_target(self):
        tag = self.sid.hex()[:8]
        try:
            while True:
                data = self.target.recv(65536) if self.target else b""
                if not data:
                    break
                with self.ready:
                    self.download_buffer.extend(data)
                    self.last_seen = time.time()
                    self.ready.notify_all()
                log.debug(f"[{tag}] SSH download buffered: {len(data)}B")
        except OSError as exc:
            with self.lock:
                if not self.target_error:
                    self.target_error = str(exc)
        finally:
            with self.ready:
                self.target_eof = True
                self.ready.notify_all()
            with self.download_order:
                self.download_closed = True
                self.download_order.notify_all()
            log.info(
                "[%s] SSH target EOF%s",
                tag,
                f" ({self.target_error})" if self.target_error else "",
            )

    def write_upload(self, seq: int, payload: bytes):
        with self.lock:
            tag = self.sid.hex()[:8]
            log.debug(
                "[%s] BHTTP upload received seq=%d len=%d next=%d",
                tag,
                seq,
                len(payload),
                self.upload_next_seq,
            )
            if seq < self.upload_next_seq:
                return
            self.upload_pending.setdefault(seq, payload)
            while self.upload_next_seq in self.upload_pending:
                chunk = self.upload_pending.pop(self.upload_next_seq)
                if not self.first_upload_logged and chunk:
                    self.first_upload_logged = True
                    tag = self.sid.hex()[:8]
                    if chunk.startswith(b"SSH-"):
                        line = chunk.split(b"\n", 1)[0] + b"\n"
                        log.info(
                            "[%s] Client SSH identification seq=%d: %r",
                            tag,
                            self.upload_next_seq,
                            line,
                        )
                    else:
                        log.warning(
                            "[%s] First SSH upload is not an identification "
                            "line (seq=%d, len=%d, prefix=%s)",
                            tag,
                            self.upload_next_seq,
                            len(chunk),
                            chunk[:32].hex(),
                        )
                if chunk and self.target is not None:
                    self.target.sendall(chunk)
                    log.debug(
                        "[%s] SSH upload forwarded seq=%d len=%d",
                        tag,
                        self.upload_next_seq,
                        len(chunk),
                    )
                self.upload_next_seq += 1
                self.last_seen = time.time()

    def take_download(self, seq: int, size: int, banner_timeout: float = 5.0) -> bytes:
        size = min(max(size, 1), 524284)
        deadline = time.monotonic() + banner_timeout
        with self.ready:
            if not self.banner_delivered and seq != 0:
                return b""

            while not self.download_buffer and not self.target_eof:
                if self.banner_delivered:
                    return b""
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    return b""
                self.ready.wait(remaining)

            if not self.download_buffer:
                return b""
            chunk = bytes(self.download_buffer[:size])
            del self.download_buffer[:len(chunk)]
            if not self.banner_delivered:
                self.banner_delivered = True
            self.last_seen = time.time()
            log.debug(
                "[%s] BHTTP download served seq=%d len=%d remaining=%d",
                self.sid.hex()[:8],
                seq,
                len(chunk),
                len(self.download_buffer),
            )
            return chunk

    def close(self):
        with self.ready:
            target = self.target
            self.target = None
            self.target_eof = True
            self.ready.notify_all()
        with self.download_order:
            self.download_closed = True
            self.download_order.notify_all()
        if target:
            try:
                target.close()
            except OSError:
                pass

# ─── Authentication ───────────────────────────────────────────────────────────

def auth_system(username: str, password: str) -> bool:
    try:
        import pam
        p = pam.pam()
        return p.authenticate(username, password)
    except ImportError:
        log.warning("PAM module not available, falling back to dict auth")
        return auth_dict(username, password)

def auth_dict(username: str, password: str) -> bool:
    users = CONFIG.get("users", {})
    return users.get(username) == password

def authenticate(username: str, password: str) -> bool:
    if CONFIG["server"]["auth"]["system"]:
        return auth_system(username, password)
    return auth_dict(username, password)

# ─── BHTTP Frame I/O ──────────────────────────────────────────────────────────

def read_bhttp_frame_buf(sock: socket.socket, buf: bytes) -> Tuple[int, bytes, int, bytes, bytes]:
    while len(buf) < HEADER_SIZE:
        chunk = sock.recv(4096)
        if not chunk:
            raise ConnectionError("Connection closed")
        buf += chunk
    header = buf[:HEADER_SIZE]
    buf = buf[HEADER_SIZE:]
    mode = header[0]
    sid = header[1:17]
    seq = struct.unpack(">Q", header[17:25])[0]
    length = struct.unpack(">I", header[25:29])[0]
    if mode in (MODE_DOWNLOAD, MODE_ACK):
        return mode, sid, seq, b"", buf
    while len(buf) < length:
        chunk = sock.recv(max(4096, length - len(buf)))
        if not chunk:
            raise ConnectionError("Connection closed")
        buf += chunk
    payload = buf[:length]
    buf = buf[length:]
    return mode, sid, seq, payload, buf

def send_bhttp_status(sock: socket.socket, status: int, data: bytes = b""):
    sock.sendall(struct.pack(">BI", status, len(data)) + data)

def send_bhttp_download(
    sock: socket.socket,
    sid: bytes,
    data: bytes,
    mode: int = MODE_DOWNLOAD,
    seq: int = 0,
):
    enc = bhttp_crypt(data, sid, mode, seq, True)
    payload = struct.pack(">I", len(data)) + enc
    sock.sendall(struct.pack(">BI", STATUS_DATA, len(payload)) + payload)


def handle_bhttp_probe(conn: socket.socket):
    mode, sid, seq, encrypted, _ = read_bhttp_frame_buf(conn, b"")
    if mode != MODE_PROBE:
        raise ValueError(f"Expected BHTTP probe mode, got {mode}")

    clear = bhttp_crypt(encrypted, sid, MODE_PROBE, seq, False)
    if len(clear) < 10 or clear[:4] != b"BHP1" or clear[4] != 1:
        send_bhttp_status(conn, 1, b"invalid BHTTP v1 probe")
        return

    submode = clear[5]
    parameter = struct.unpack_from(">I", clear, 6)[0]
    if submode not in (MODE_PROBE, MODE_UPLOAD, MODE_DOWNLOAD, MODE_BATCH, MODE_ACK):
        send_bhttp_status(conn, 1, b"unsupported BHTTP probe mode")
        return

    expected_request_size = parameter if submode == MODE_UPLOAD and parameter >= 10 else 10
    if len(clear) != expected_request_size:
        send_bhttp_status(conn, 1, b"invalid BHTTP v1 probe length")
        return
    if any(clear[index] != (index * 31) & 0xFF for index in range(10, len(clear))):
        send_bhttp_status(conn, 1, b"invalid BHTTP v1 probe pattern")
        return

    response_size = max(parameter, 10) if submode == MODE_DOWNLOAD else 10
    if response_size > 524288:
        send_bhttp_status(conn, 1, b"BHTTP v1 probe too large")
        return

    response = bytearray(response_size)
    response[:4] = b"BHP1"
    response[4] = 1
    response[5] = submode
    struct.pack_into(">I", response, 6, parameter)
    for index in range(10, response_size):
        response[index] = (index * 31) & 0xFF

    encrypted_response = bhttp_crypt(bytes(response), sid, MODE_PROBE, seq, True)
    response_count = min(max(parameter, 1), 256) if submode == MODE_ACK else 1
    for _ in range(response_count):
        send_bhttp_status(conn, STATUS_OK, encrypted_response)

# ─── Legacy Handler ─────────────────────────────────────────────────────────

class SessionHandler:
    def __init__(self, conn: socket.socket, addr, sessions: dict, ip_pool: IPPool, extra_bytes: bytes = b""):
        self.conn = conn
        self.addr = addr
        self.sessions = sessions
        self.ip_pool = ip_pool
        self._pending_flush = b""
        self.extra_bytes = extra_bytes

    def get_session(self, sid: bytes) -> Session:
        sid_hex = sid.hex()
        with SESSIONS_LOCK:
            session = self.sessions.get(sid_hex)
            if session is None:
                session = Session(sid=sid)
                self.sessions[sid_hex] = session
            return session

    def handle(self):
        log.info(f"Connection from {self.addr}")
        try:
            while True:
                mode, sid, seq, enc_payload, self.extra_bytes = read_bhttp_frame_buf(self.conn, self.extra_bytes)
                session = self.get_session(sid)
                session.last_seen = time.time()

                payload = b""
                if enc_payload and mode == MODE_UPLOAD:
                    payload = bhttp_crypt(enc_payload, sid, mode, seq, False)

                if mode == MODE_UPLOAD:
                    with session.lock:
                        self._handle_upload(session, seq, payload)
                elif mode == MODE_DOWNLOAD:
                    with session.download_order:
                        while (
                            seq > session.download_next_seq
                            and not session.download_closed
                        ):
                            session.download_order.wait()
                        is_new = seq == session.download_next_seq
                        if is_new:
                            chunk = session.take_download(seq, 65536)
                            if chunk:
                                session.download_frames[seq] = chunk
                            session.download_next_seq += 1
                            session.download_order.notify_all()
                        else:
                            chunk = session.download_frames.get(seq, b"")
                        send_bhttp_download(
                            self.conn, session.sid, chunk, mode, seq
                        )
                elif mode == MODE_BATCH:
                    try:
                        clear = bhttp_crypt(enc_payload, sid, mode, seq, False)
                        chunk_size, count = struct.unpack(">IH", clear)
                        chunk_size = min(max(chunk_size, 1), 524284)
                        count = min(max(count, 1), 256)
                    except struct.error:
                        send_bhttp_status(self.conn, 1, b"invalid BHTTP batch request")
                        continue
                    log.debug(
                        "[%s] BHTTP batch requested seq=%d count=%d chunk=%d",
                        session.sid.hex()[:8],
                        seq,
                        count,
                        chunk_size,
                    )
                    nonempty = []
                    with session.download_order:
                        while (
                            seq > session.download_next_seq
                            and not session.download_closed
                        ):
                            session.download_order.wait()
                        is_new = seq == session.download_next_seq
                        chunks = []
                        for offset in range(count):
                            current_seq = seq + offset
                            if is_new:
                                chunk = session.take_download(
                                    current_seq, chunk_size
                                )
                                if chunk:
                                    session.download_frames[current_seq] = chunk
                            else:
                                chunk = session.download_frames.get(
                                    current_seq, b""
                                )
                            chunks.append(chunk)
                            if chunk:
                                nonempty.append((current_seq, len(chunk)))
                        if is_new:
                            session.download_next_seq += count
                            session.download_order.notify_all()
                        for offset, chunk in enumerate(chunks):
                            current_seq = seq + offset
                            send_bhttp_download(
                                self.conn, session.sid, chunk, mode, current_seq
                            )
                    if nonempty:
                        log.debug(
                            "[%s] BHTTP batch completed seq=%d data=%s",
                            session.sid.hex()[:8],
                            seq,
                            nonempty,
                        )
                elif mode == MODE_ACK:
                    log.debug(
                        "[%s] BHTTP ACK seq=%d",
                        session.sid.hex()[:8],
                        seq,
                    )
                    session.acknowledge_download(seq)
                    send_bhttp_status(self.conn, STATUS_OK)

        except (ConnectionError, OSError) as e:
            log.debug(f"Connection closed ({self.addr}): {e}")
        except Exception as e:
            log.error(f"Session error ({self.addr}): {e}")
            log.debug(traceback.format_exc())
        finally:
            self.conn.close()

    def _handle_upload(self, session: Session, seq: int, payload: bytes):
        sid = session.sid
        tag = sid.hex()[:8]

        if seq == 0 and not payload:
            target = CONFIG["proxy"]["target"]
            if session.open_target(target["host"], target["port"]):
                log.info(
                    f"[{tag}] Session init -> SSH {target['host']}:{target['port']}"
                )
                send_bhttp_status(self.conn, STATUS_OK)
            else:
                log.warning(f"[{tag}] SSH open failed: {session.target_error}")
                send_bhttp_status(self.conn, 1, b"SSH target unavailable")
            return

        if session.target is None:
            target = CONFIG["proxy"]["target"]
            if not session.open_target(target["host"], target["port"]):
                send_bhttp_status(self.conn, 1, b"SSH target unavailable")
                return
        try:
            session.write_upload(seq, payload)
            send_bhttp_status(self.conn, STATUS_OK)
        except OSError as exc:
            log.warning(f"[{tag}] SSH upload failed: {exc}")
            send_bhttp_status(self.conn, 1, b"SSH upload failed")

    def _handle_handshake(self, session: Session, payload: bytes):
        tag = session.sid.hex()[:8]

        if not payload.startswith(b"BHTTP/1.1 CLIENT_HELLO"):
            prefix = payload[:26].hex()
            log.warning(
                f"[{tag}] Invalid handshake magic (len={len(payload)}, prefix={prefix})"
            )
            return

        try:
            body = payload[len(b"BHTTP/1.1 CLIENT_HELLO"):].lstrip(b"\n\r ")
            creds = json.loads(body)
            username = creds.get("user", "")
            password = creds.get("pass", "")
        except (json.JSONDecodeError, KeyError) as e:
            log.warning(f"[{tag}] Malformed handshake JSON: {e}")
            return

        if not authenticate(username, password):
            log.warning(f"[{tag}] Authentication failed for user '{username}'")
            err_resp = json.dumps({"status": False, "message": "authentication failed"}).encode()
            resp = b"BHTTP/1.1 SERVER_HELLO\n" + struct.pack(">I", len(err_resp)) + err_resp
            session.download_queue += resp
            return

        assigned_ip = self.ip_pool.assign(session.sid.hex())
        session.authenticated = True
        session.username = username
        session.assigned_ip = assigned_ip or ""

        log.info(f"[{tag}] Authentication succeeded for '{username}', IP={assigned_ip}")

        hello_data = json.dumps({
            "status": True,
            "message": "authentication succeeded",
            "ip": assigned_ip,
            "subnet": str(self.ip_pool.network.with_prefixlen),
            "gateway": self.ip_pool.gateway,
        }).encode()
        resp = b"BHTTP/1.1 SERVER_HELLO\n" + struct.pack(">I", len(hello_data)) + hello_data
        session.download_queue += resp

    def _handle_legacy_packet(self, session: Session, payload: bytes):
        tag = session.sid.hex()[:8]
        try:
            pkt_type, stream_id, pkt_payload = decode_packet(payload)
        except ValueError as e:
            log.warning(f"[{tag}] Invalid legacy packet: {e}")
            send_bhttp_status(self.conn, STATUS_OK)
            return

        send_bhttp_status(self.conn, STATUS_OK)

        if pkt_type == PKT_AUTH:
            self._on_pkt_auth(session, stream_id, pkt_payload)
        elif pkt_type == PKT_DATA:
            self._on_pkt_data(session, stream_id, pkt_payload)
        elif pkt_type == PKT_KEEPALIVE:
            self._on_pkt_keepalive(session, stream_id)
        elif pkt_type == PKT_DISCONNECT:
            self._on_pkt_disconnect(session, stream_id)
        elif pkt_type == PKT_IP:
            self._on_pkt_ip(session, stream_id, pkt_payload)
        else:
            log.debug(f"[{tag}] Unknown packet type {pkt_type}")

    def _on_pkt_auth(self, session: Session, stream_id: int, payload: bytes):
        tag = session.sid.hex()[:8]
        try:
            null_idx = payload.index(b"\x00")
            host = payload[:null_idx].decode()
            port = struct.unpack(">H", payload[null_idx + 1:null_idx + 3])[0]
        except (ValueError, struct.error) as e:
            log.warning(f"[{tag}] Malformed AUTH packet: {e}")
            return

        log.info(f"[{tag}] NewStream: {host}:{port} (stream_id={stream_id})")
        threading.Thread(
            target=self._proxy_stream,
            args=(session, stream_id, host, port),
            daemon=True,
        ).start()

    def _on_pkt_data(self, session: Session, stream_id: int, payload: bytes):
        tag = session.sid.hex()[:8]
        sock = session.streams.get(stream_id)
        if sock is None:
            log.debug(f"[{tag}] DATA for unknown stream {stream_id}")
            return
        try:
            sock.sendall(payload)
        except OSError:
            session.streams.pop(stream_id, None)

    def _on_pkt_keepalive(self, session: Session, stream_id: int):
        tag = session.sid.hex()[:8]
        log.debug(f"[{tag}] KeepAlive (stream={stream_id})")
        resp_pkt = encode_packet(PKT_KEEPALIVE, stream_id, b"")
        session.download_queue += resp_pkt

    def _on_pkt_disconnect(self, session: Session, stream_id: int):
        tag = session.sid.hex()[:8]
        log.info(f"[{tag}] Disconnect stream {stream_id}")
        sock = session.streams.pop(stream_id, None)
        if sock:
            try:
                sock.close()
            except OSError:
                pass

    def _on_pkt_ip(self, session: Session, stream_id: int, payload: bytes):
        tag = session.sid.hex()[:8]
        if CONFIG["server"]["tun"].get("enabled"):
            self._write_tun(payload)
        else:
            log.debug(f"[{tag}] IP packet received (TUN disabled), {len(payload)}B")

    def _proxy_stream(self, session: Session, stream_id: int, host: str, port: int):
        tag = session.sid.hex()[:8]
        try:
            remote = socket.create_connection((host, port), timeout=10)
            remote.setblocking(False)
        except OSError as e:
            log.warning(f"[{tag}] Stream {stream_id}: connect {host}:{port} failed: {e}")
            disc = encode_packet(PKT_DISCONNECT, stream_id, b"")
            with session.lock:
                session.download_queue += disc
            return

        with session.lock:
            session.streams[stream_id] = remote

        log.info(f"[{tag}] Stream {stream_id}: connected to {host}:{port}")

        try:
            while True:
                rlist, _, _ = select.select([remote], [], [], 30)
                if not rlist:
                    ka = encode_packet(PKT_KEEPALIVE, stream_id, b"")
                    with session.lock:
                        session.download_queue += ka
                    continue

                data = remote.recv(65536)
                if not data:
                    break

                pkt = encode_packet(PKT_DATA, stream_id, data)
                with session.lock:
                    session.download_queue += pkt

        except OSError:
            pass
        finally:
            try:
                remote.close()
            except OSError:
                pass
            with session.lock:
                session.streams.pop(stream_id, None)
                disc = encode_packet(PKT_DISCONNECT, stream_id, b"")
                session.download_queue += disc
            log.info(f"[{tag}] Stream {stream_id}: closed")

    def _handle_download(self, session: Session, seq: int, _enc_payload: bytes):
        if session.download_queue:
            chunk = session.download_queue[:65536]
            session.download_queue = session.download_queue[len(chunk):]
            send_bhttp_download(self.conn, session.sid, chunk)
        else:
            send_bhttp_status(self.conn, STATUS_OK)

    def _handle_batch(self, session: Session, seq: int):
        if session.download_queue:
            chunk = session.download_queue[:65536]
            session.download_queue = session.download_queue[len(chunk):]
            send_bhttp_download(self.conn, session.sid, chunk)
        else:
            send_bhttp_status(self.conn, STATUS_OK)

    def _handle_ack(self, session: Session):
        tag = session.sid.hex()[:8]
        log.info(f"[{tag}] Session ACK/destroy for user '{session.username}'")
        self.ip_pool.release(session.sid.hex())
        send_bhttp_status(self.conn, STATUS_OK)

    def _write_tun(self, data: bytes):
        tun_name = CONFIG["server"]["tun"]["name"]
        try:
            fd = os.open(f"/dev/net/tun", os.O_RDWR)
            os.write(fd, data)
            os.close(fd)
        except OSError as e:
            log.debug(f"TUN write error: {e}")

# ─── HTTP/WebSocket Upgrade Proxy ────────────────────────────────────────────

def handle_http_upgrade(conn: socket.socket) -> Tuple[bool, bytes]:
    try:
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = conn.recv(1024)
            if not chunk:
                return False, b""
            buf += chunk
    except OSError:
        return False, b""

    idx = buf.find(b"\r\n\r\n") + 4
    extra = buf[idx:]

    conn.sendall(
        b"HTTP/1.1 101 BHTTP\r\n"
        b"Upgrade: websocket\r\n"
        b"Connection: Upgrade\r\n"
        b"\r\n"
        b"HTTP/1.1 200 BHTTP\r\n"
        b"\r\n"
    )
    return True, extra

# ─── Client Thread ────────────────────────────────────────────────────────────

def handle_client(conn: socket.socket, addr, sessions: dict, ip_pool: IPPool):
    try:
        first = conn.recv(1, socket.MSG_PEEK)
        if not first:
            conn.close()
            return

        if first[0] == 0:
            handle_bhttp_probe(conn)
            conn.close()
            return

        extra_bytes = b""
        if first[0] not in (MODE_UPLOAD, MODE_DOWNLOAD, MODE_BATCH, MODE_ACK):
            success, extra_bytes = handle_http_upgrade(conn)
            if not success:
                conn.close()
                return

        handler = SessionHandler(conn, addr, sessions, ip_pool, extra_bytes)
        handler.handle()
    except Exception as e:
        log.debug(f"Client error ({addr}): {e}")
        conn.close()

# ─── Listener ─────────────────────────────────────────────────────────────────

def start_listener(host: str, port: int, use_ssl: bool, sessions: dict, ip_pool: IPPool):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((host, port))
    srv.listen(128)

    if use_ssl:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        try:
            ctx.load_cert_chain(
                CONFIG["tls"]["certificate"],
                CONFIG["tls"]["private_key"],
            )
        except FileNotFoundError:
            log.warning(f"SSL cert not found, disabling SSL on port {port}")
            use_ssl = False

    proto = "HTTPS" if use_ssl else "HTTP"
    log.info(f"[Server] Listening on {host}:{port} ({proto})")

    while True:
        try:
            conn, addr = srv.accept()
            if use_ssl:
                try:
                    conn = ctx.wrap_socket(conn, server_side=True)
                except ssl.SSLError as e:
                    log.debug(f"SSL error from {addr}: {e}")
                    conn.close()
                    continue
            t = threading.Thread(
                target=handle_client,
                args=(conn, addr, sessions, ip_pool),
                daemon=True,
            )
            t.start()
        except Exception as e:
            log.error(f"Accept error: {e}")

# ─── Session Cleanup ─────────────────────────────────────────────────────────

def cleanup_sessions(sessions: dict, ip_pool: IPPool, timeout: int = 120):
    while True:
        time.sleep(30)
        now = time.time()
        with SESSIONS_LOCK:
            dead = [k for k, s in sessions.items() if now - s.last_seen > timeout]
        for k in dead:
            with SESSIONS_LOCK:
                session = sessions.pop(k, None)
            if session:
                session.close()
                ip_pool.release(k)
                log.info(f"[Cleanup] Removed stale SSH session {k[:8]}")

# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    # --- MODIFICACIÓN DE PUERTO DINÁMICO ---
    if len(sys.argv) > 1 and sys.argv[1].isdigit():
        CONFIG["proxy"]["listen"][0]["port"] = int(sys.argv[1])
    # ---------------------------------------

    log.info("BHTTP starting...")

    ip_pool = IPPool(CONFIG["server"]["virtual_subnet_cidr"])
    sessions: Dict[str, Session] = {}

    threading.Thread(
        target=cleanup_sessions,
        args=(sessions, ip_pool),
        daemon=True,
    ).start()

    listeners = CONFIG["proxy"]["listen"]
    threads = []
    for lst in listeners:
        t = threading.Thread(
            target=start_listener,
            args=(lst["host"], lst["port"], lst.get("ssl", False), sessions, ip_pool),
            daemon=True,
        )
        t.start()
        threads.append(t)

    log.info("BHTTP listening on %d port(s). Press Ctrl+C to stop.", len(listeners))
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        log.info("Shutting down.")
    except Exception as e:
        log.error(f"Main loop crashed: {e}")


if __name__ == "__main__":
    main()
