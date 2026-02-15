import json
import sys
from typing import Any, Dict, Optional


class StdioTransport:
    def __init__(self):
        self._stdin = sys.stdin.buffer
        self._stdout = sys.stdout.buffer
        self._mode = None  # "lsp" or "line"

    def read_message(self) -> Optional[Dict[str, Any]]:
        if self._mode == "line":
            line = self._stdin.readline()
            if not line:
                return None
            line = line.strip()
            if not line:
                return None
            return json.loads(line.decode("utf-8"))

        if self._mode == "lsp":
            return self._read_lsp_message()

        # Auto-detect framing based on the first line.
        line = self._stdin.readline()
        if not line:
            return None
        if line in (b"\r\n", b"\n"):
            return None
        stripped = line.lstrip()
        if stripped.startswith(b"{"):
            self._mode = "line"
            return json.loads(stripped.decode("utf-8"))

        self._mode = "lsp"
        return self._read_lsp_message(first_line=line)

    def _read_lsp_message(self, first_line: Optional[bytes] = None) -> Optional[Dict[str, Any]]:
        headers = {}
        if first_line is not None:
            key, _, value = first_line.decode("utf-8", errors="replace").partition(":")
            headers[key.strip().lower()] = value.strip()
        while True:
            line = self._stdin.readline()
            if not line:
                return None
            if line in (b"\r\n", b"\n"):
                break
            key, _, value = line.decode("utf-8", errors="replace").partition(":")
            headers[key.strip().lower()] = value.strip()
        length = int(headers.get("content-length", "0"))
        if length <= 0:
            return None
        body = self._stdin.read(length)
        if not body:
            return None
        return json.loads(body.decode("utf-8"))

    def send_message(self, payload: Dict[str, Any]) -> None:
        if self._mode == "line":
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8") + b"\n"
            self._stdout.write(body)
            self._stdout.flush()
            return
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        header = f"Content-Length: {len(body)}\r\n\r\n".encode("utf-8")
        self._stdout.write(header + body)
        self._stdout.flush()
