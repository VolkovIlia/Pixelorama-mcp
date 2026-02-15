#!/usr/bin/env python3
import json
import os
from typing import Any, Dict, Optional

from .bridge_client import BridgeClient
from .image_utils import handle_animated_export, handle_to_pixelart
from .tools import TOOLS
from .transport import StdioTransport

PROTOCOL_VERSION = "2024-11-05"  # conservative MCP-style version string

# Bridge method name mapping for tools that differ from their MCP name
_BRIDGE_NAME_MAP = {
    "bridge.ping": "ping",
    "bridge.version": "version",
}

# Tools that skip protocol check (work without verified bridge protocol)
_SKIP_PROTOCOL_CHECK = {"bridge.ping", "bridge.version", "bridge.info"}

# Tools handled server-side (not passed through to bridge)
_SERVER_SIDE_TOOLS = {"image.to_pixelart", "project.export.animated"}

# Tools that return image data ({"data": b64, "format": "png"})
# These get MCP image content blocks in the response
_IMAGE_TOOLS = {"pixel.get_region", "canvas.snapshot"}

# Tools that modify pixel data and need a canvas refresh after execution
_NEEDS_REFRESH = {
    "pixel.set", "pixel.set_many", "pixel.set_region", "pixel.replace_color",
    "canvas.fill", "canvas.clear", "canvas.resize", "canvas.crop",
    "draw.line", "draw.rect", "draw.ellipse", "draw.erase_line",
    "draw.text", "draw.gradient",
    "effect.shader.apply", "effect.layer.apply",
    "brush.stamp", "brush.stroke",
    "project.create", "batch.exec",
}


def _deserialize_args(args: Dict[str, Any]) -> Dict[str, Any]:
    """MCP clients may serialize arrays/objects AND strings as JSON strings.

    Claude Code MCP client JSON-encodes all non-primitive argument values:
      - arrays:  [255,0,0,255]  -> '"[255,0,0,255]"'  (starts with '[')
      - objects: {"r":1}        -> '"{\"r\":1}"'       (starts with '{')
      - strings: "#ff0000"      -> '"\"#ff0000\""'     (starts with '"')

    We detect these and parse them back to their original types.
    """
    out = {}
    for key, val in args.items():
        if isinstance(val, str) and val and val[0] in ("[", "{", '"'):
            try:
                out[key] = json.loads(val)
                continue
            except (json.JSONDecodeError, ValueError):
                pass
        out[key] = val
    return out


class MCPServer:
    def __init__(self):
        self._transport = StdioTransport()
        host = os.environ.get("PIXELORAMA_BRIDGE_HOST", "127.0.0.1")
        port = int(os.environ.get("PIXELORAMA_BRIDGE_PORT", "8123"))
        self._bridge = BridgeClient(host=host, port=port)
        self._bridge_protocol_checked = False
        self._tool_names = {t["name"] for t in TOOLS}

    def run(self) -> None:
        while True:
            msg = self._transport.read_message()
            if msg is None:
                break
            response = self._handle_message(msg)
            if response is not None:
                self._transport.send_message(response)

    def _handle_message(self, msg: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        msg_id = msg.get("id")
        method = msg.get("method")
        params = msg.get("params", {})

        try:
            if method == "initialize":
                result = {
                    "protocolVersion": PROTOCOL_VERSION,
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "pixelorama-mcp", "version": "0.1.0"},
                }
                return self._ok(msg_id, result) if msg_id is not None else None
            if method == "tools/list":
                return self._ok(msg_id, {"tools": TOOLS}) if msg_id is not None else None
            if method == "tools/call":
                if msg_id is None:
                    return None
                tool_name = params.get("name", "")
                tool_result = self._call_tool(params)
                wrapped = self._wrap_tool_result(tool_name, tool_result)
                return self._ok(msg_id, wrapped)
            if method in ("shutdown", "exit"):
                return self._ok(msg_id, {"ok": True}) if msg_id is not None else None
            if msg_id is None:
                return None
            return self._err(msg_id, "method_not_found", f"unknown method: {method}")
        except Exception as exc:  # guardrail to avoid crashing the server
            if msg_id is None:
                return None
            return self._err(msg_id, "internal_error", str(exc))

    def _wrap_tool_result(self, tool_name: str, result: Dict[str, Any]) -> Dict[str, Any]:
        """Wrap tool result as MCP content. Image tools get image content blocks."""
        if tool_name in _IMAGE_TOOLS and isinstance(result, dict) and "data" in result:
            fmt = result.get("format", "png")
            if fmt == "png":
                image_data = result["data"]
                meta = {k: v for k, v in result.items() if k != "data"}
                return {
                    "content": [
                        {"type": "text", "text": json.dumps(meta, ensure_ascii=False)},
                        {"type": "image", "data": image_data, "mimeType": "image/png"},
                    ]
                }
        return {
            "content": [
                {"type": "text", "text": json.dumps(result, ensure_ascii=False)}
            ]
        }

    def _call_tool(self, params: Dict[str, Any]) -> Dict[str, Any]:
        name = params.get("name")
        args = _deserialize_args(params.get("arguments", {}))

        # Server-side tools (not passed through to bridge)
        if name == "image.to_pixelart":
            return handle_to_pixelart(args, self._bridge.call)
        if name == "project.export.animated":
            return handle_animated_export(args, self._bridge.call)

        # Validate tool exists in registry
        if name not in self._tool_names:
            raise RuntimeError(f"unknown tool: {name}")

        # Protocol check for bridge tools (skip for basic bridge queries)
        if name not in _SKIP_PROTOCOL_CHECK:
            self._ensure_bridge_protocol()

        # Map to bridge method name and call
        bridge_method = _BRIDGE_NAME_MAP.get(name, name)
        result = self._bridge.call(bridge_method, args)

        # Force canvas refresh for drawing/modification tools
        if name in _NEEDS_REFRESH:
            try:
                self._bridge.call("project.set_active", {})
            except Exception:
                pass

        return result

    def _ensure_bridge_protocol(self) -> None:
        if self._bridge_protocol_checked:
            return
        info = self._bridge.call("bridge.info", {})
        protocol = info.get("protocol_version") if isinstance(info, dict) else None
        if protocol != PROTOCOL_VERSION:
            raise RuntimeError(
                f"protocol_mismatch: expected {PROTOCOL_VERSION}, got {protocol}"
            )
        self._bridge_protocol_checked = True

    def _ok(self, msg_id: Any, result: Any) -> Dict[str, Any]:
        return {"jsonrpc": "2.0", "id": msg_id, "result": result}

    def _err(self, msg_id: Any, code: str, message: str) -> Dict[str, Any]:
        return {
            "jsonrpc": "2.0",
            "id": msg_id,
            "error": {"code": code, "message": message},
        }


def main():
    MCPServer().run()


if __name__ == "__main__":
    main()
