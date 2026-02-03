#!/usr/bin/env python3
import json
import os
import socket
import sys
import uuid

DEFAULT_HOST = os.environ.get("PIXELORAMA_BRIDGE_HOST", "127.0.0.1")
DEFAULT_PORT = int(os.environ.get("PIXELORAMA_BRIDGE_PORT", "8123"))


class BridgeClient:
    def __init__(self, host=DEFAULT_HOST, port=DEFAULT_PORT, timeout=3.0):
        self.host = host
        self.port = port
        self.timeout = timeout
        self._sock = None

    def connect(self):
        if self._sock is not None:
            return
        self._sock = socket.create_connection((self.host, self.port), timeout=self.timeout)

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
                self.connect()
                req = {
                    "id": str(uuid.uuid4()),
                    "method": method,
                    "params": params,
                }
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
            except (OSError, ConnectionError):
                self.close()
                if attempt == 0:
                    continue
                raise

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
