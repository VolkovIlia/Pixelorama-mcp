#!/usr/bin/env python3
import json
import os
import socket
import sys
import uuid

DEFAULT_HOST = os.environ.get("PIXELORAMA_BRIDGE_HOST", "127.0.0.1")
DEFAULT_PORT = int(os.environ.get("PIXELORAMA_BRIDGE_PORT", "8123"))
DEFAULT_TOKEN = os.environ.get("PIXELORAMA_BRIDGE_TOKEN", "")


def _parse_ports(default_port: int) -> list[int]:
    ports_env = os.environ.get("PIXELORAMA_BRIDGE_PORTS", "").strip()
    if ports_env:
        ports = []
        for part in ports_env.split(","):
            part = part.strip()
            if not part:
                continue
            ports.append(int(part))
        if ports:
            return ports
    range_env = os.environ.get("PIXELORAMA_BRIDGE_PORT_RANGE", "").strip()
    if range_env and "-" in range_env:
        start_s, end_s = range_env.split("-", 1)
        start = int(start_s.strip())
        end = int(end_s.strip())
        if end >= start:
            return list(range(start, end + 1))
    if "PIXELORAMA_BRIDGE_PORT" in os.environ:
        return [default_port]
    return list(range(default_port, default_port + 11))


class BridgeClient:
    def __init__(
        self,
        host=DEFAULT_HOST,
        port=DEFAULT_PORT,
        timeout=30.0,
        ports=None,
        token=DEFAULT_TOKEN,
        expected_protocol: str | None = None,
    ):
        self.host = host
        self.timeout = timeout
        self.ports = ports or _parse_ports(port)
        self.port = self.ports[0]
        self.token = token
        self.expected_protocol = expected_protocol
        self._protocol_checked = False
        self._sock = None

    def connect(self):
        if self._sock is not None:
            return
        last_err = None
        for port in self.ports:
            try:
                self._sock = socket.create_connection((self.host, port), timeout=self.timeout)
                self.port = port
                return
            except OSError as exc:
                last_err = exc
                self._sock = None
        if last_err:
            raise last_err

    def close(self):
        if self._sock is not None:
            try:
                self._sock.close()
            finally:
                self._sock = None

    def call(self, method, params=None):
        if params is None:
            params = {}
        for attempt in range(2):
            try:
                if (
                    self.expected_protocol
                    and not self._protocol_checked
                    and method not in ("bridge.info", "ping", "version")
                ):
                    info = self._call_raw("bridge.info", {})
                    protocol = info.get("protocol_version") if isinstance(info, dict) else None
                    if protocol != self.expected_protocol:
                        raise RuntimeError(
                            f"protocol_mismatch: expected {self.expected_protocol}, got {protocol}"
                        )
                    self._protocol_checked = True
                return self._call_raw(method, params)
            except (OSError, ConnectionError):
                self.close()
                if attempt == 0:
                    continue
                raise

    def _call_raw(self, method, params):
        self.connect()
        req = {
            "id": str(uuid.uuid4()),
            "method": method,
            "params": params,
        }
        if self.token:
            req["token"] = self.token
        data = json.dumps(req, separators=(",", ":")).encode("utf-8") + b"\n"
        self._sock.sendall(data)
        resp = self._recv_line()
        if not resp:
            raise ConnectionError("empty response from bridge")
        payload = json.loads(resp)
        if not payload.get("ok", False):
            err = payload.get("error", {})
            raise RuntimeError(f"bridge error: {err.get('code')} {err.get('message')}")
        return payload.get("result")

    def _recv_line(self):
        buf = b""
        while True:
            chunk = self._sock.recv(4096)
            if not chunk:
                break
            buf += chunk
            if b"\n" in buf:
                line, _ = buf.split(b"\n", 1)
                return line.decode("utf-8", errors="replace")
        return ""


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: bridge_client.py <method> [json_params]", file=sys.stderr)
        sys.exit(2)
    method = sys.argv[1]
    params = {}
    if len(sys.argv) >= 3:
        params = json.loads(sys.argv[2])
    client = BridgeClient()
    try:
        result = client.call(method, params)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    finally:
        client.close()
