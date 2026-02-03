#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import time
import select
import fcntl

SERVER_CWD = os.environ.get(
    "PIXELORAMA_MCP_SERVER_DIR",
    "/Users/dandan/code/tool/Pixelorama-mcp/server",
)
TIMEOUT = float(os.environ.get("PIXELORAMA_MCP_TIMEOUT", "12"))

TMP_PXO = "/tmp/pixelorama_mcp_test.pxo"
TMP_PNG = "/tmp/pixelorama_mcp_test.png"
TMP_MASK = "/tmp/pixelorama_mcp_mask.png"
TMP_GIF = "/tmp/pixelorama_mcp_test.gif"
TMP_APNG = "/tmp/pixelorama_mcp_test.apng"
TMP_SPRITESHEET = "/tmp/pixelorama_mcp_spritesheet.png"
TMP_PALETTE = "/tmp/pixelorama_mcp_palette.gpl"


class StdioClient:
    def __init__(self, proc):
        self.proc = proc
        self.buf = b""
        self.stdout_fd = proc.stdout.fileno()
        flags = fcntl.fcntl(self.stdout_fd, fcntl.F_GETFL)
        fcntl.fcntl(self.stdout_fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

    def send(self, msg):
        body = json.dumps(msg, ensure_ascii=False).encode("utf-8")
        header = f"Content-Length: {len(body)}\r\n\r\n".encode("utf-8")
        self.proc.stdin.write(header + body)
        self.proc.stdin.flush()

    def recv(self, timeout=TIMEOUT):
        end_time = time.time() + timeout
        while time.time() < end_time:
            msg = self._try_parse()
            if msg is not None:
                return msg

            rlist, _, _ = select.select([self.stdout_fd], [], [], 0.2)
            if not rlist:
                continue
            try:
                chunk = os.read(self.stdout_fd, 4096)
            except BlockingIOError:
                continue
            if not chunk:
                return None
            self.buf += chunk
        return None

    def _try_parse(self):
        header_end = self.buf.find(b"\r\n\r\n")
        if header_end == -1:
            return None
        header_blob = self.buf[:header_end].decode("utf-8", errors="replace")
        headers = {}
        for line in header_blob.split("\r\n"):
            if not line:
                continue
            key, _, value = line.partition(":")
            headers[key.strip().lower()] = value.strip()
        length = int(headers.get("content-length", "0"))
        body_start = header_end + 4
        if len(self.buf) < body_start + length:
            return None
        body = self.buf[body_start : body_start + length]
        self.buf = self.buf[body_start + length :]
        return json.loads(body.decode("utf-8"))


def _call_tool(client, tool_name, arguments=None, msg_id=1):
    if arguments is None:
        arguments = {}
    client.send(
        {
            "jsonrpc": "2.0",
            "id": msg_id,
            "method": "tools/call",
            "params": {"name": tool_name, "arguments": arguments},
        }
    )
    return client.recv()


def _require_result(resp, label):
    if resp is None:
        raise AssertionError(f"{label} timed out")
    if "error" in resp:
        err = resp.get("error", {})
        raise AssertionError(f"{label} error: {err.get('code')} {err.get('message')}")
    if "result" not in resp:
        raise AssertionError(f"{label} missing result")
    result = resp["result"]
    if isinstance(result, dict) and "content" in result:
        return _extract_content_json(result["content"])
    return result


def _extract_content_json(content):
    if not isinstance(content, list):
        return content
    for item in content:
        if not isinstance(item, dict):
            continue
        if item.get("type") == "json":
            return item.get("json")
        if item.get("type") == "text":
            try:
                return json.loads(item.get("text", ""))
            except json.JSONDecodeError:
                return item.get("text")
    return None


def main():
    proc = subprocess.Popen(
        ["/Users/dandan/code/tool/Pixelorama-mcp/.venv/bin/python", "-m", "pixelorama_mcp"],
        cwd=SERVER_CWD,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=False,
    )

    client = StdioClient(proc)

    try:
        print("[1/16] initialize")
        client.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
        _require_result(client.recv(), "initialize")

        print("[2/16] tools/list")
        client.send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        _require_result(client.recv(), "tools/list")

        print("[3/16] bridge")
        _require_result(_call_tool(client, "bridge.ping", {}, msg_id=3), "bridge.ping")
        _require_result(_call_tool(client, "bridge.version", {}, msg_id=4), "bridge.version")

        print("[4/16] project + draw basics")
        _require_result(
            _call_tool(client, "project.create", {"name": "test", "width": 16, "height": 16}, msg_id=5),
            "project.create",
        )
        _require_result(
            _call_tool(
                client,
                "draw.line",
                {"x1": 0, "y1": 0, "x2": 3, "y2": 0, "color": [255, 0, 0, 255]},
                msg_id=6,
            ),
            "draw.line",
        )
        _require_result(
            _call_tool(
                client,
                "draw.rect",
                {"x": 5, "y": 5, "width": 4, "height": 4, "color": [0, 255, 0, 255], "fill": True},
                msg_id=7,
            ),
            "draw.rect",
        )
        _require_result(
            _call_tool(
                client,
                "draw.ellipse",
                {"x": 8, "y": 1, "width": 4, "height": 4, "color": [0, 0, 255, 255], "fill": False},
                msg_id=8,
            ),
            "draw.ellipse",
        )

        print("[5/16] text + gradient")
        _require_result(
            _call_tool(
                client,
                "draw.text",
                {"text": "Hi", "x": 1, "y": 8, "size": 8, "color": [255, 255, 255, 255]},
                msg_id=9,
            ),
            "draw.text",
        )
        _require_result(
            _call_tool(
                client,
                "draw.gradient",
                {"x": 0, "y": 12, "width": 6, "height": 2, "from": [0, 0, 0, 255], "to": [255, 255, 255, 255], "direction": "horizontal"},
                msg_id=10,
            ),
            "draw.gradient",
        )

        print("[6/16] layer props + group")
        props = _require_result(_call_tool(client, "layer.get_props", {}, msg_id=11), "layer.get_props")
        _require_result(
            _call_tool(
                client,
                "layer.set_props",
                {"index": props.get("index", 0), "name": "Base", "opacity": 0.9, "visible": True},
                msg_id=12,
            ),
            "layer.set_props",
        )
        layers = _require_result(
            _call_tool(client, "layer.group.create", {"above": 0, "name": "Group"}, msg_id=13),
            "layer.group.create",
        )
        group_index = None
        for item in layers.get("layers", []):
            if item.get("name") == "Group":
                group_index = item.get("index")
                break
        if group_index is None:
            raise AssertionError("group layer not found")
        parent_props = _require_result(
            _call_tool(client, "layer.parent.set", {"index": 0, "parent": group_index}, msg_id=14),
            "layer.parent.set",
        )
        if int(parent_props.get("parent", -1)) < 0:
            raise AssertionError("layer parent set failed")

        print("[7/16] pixel + replace")
        result = _require_result(_call_tool(client, "pixel.get", {"x": 3, "y": 0}, msg_id=15), "pixel.get")
        color = result.get("color")
        if not isinstance(color, list) or len(color) != 4:
            raise AssertionError("pixel.get invalid color")
        if abs(color[0] - 1.0) >= 0.01:
            raise AssertionError("draw.line red channel mismatch")
        _require_result(
            _call_tool(
                client,
                "pixel.replace_color",
                {"from": [255, 0, 0, 255], "to": [0, 0, 0, 255]},
                msg_id=16,
            ),
            "pixel.replace_color",
        )

        print("[8/16] pixel batch + region + batch.exec")
        _require_result(
            _call_tool(
                client,
                "pixel.set_many",
                {
                    "points": [{"x": 1, "y": 1}, {"x": 2, "y": 1}],
                    "color": [0, 0, 255, 255],
                },
                msg_id=17,
            ),
            "pixel.set_many",
        )
        _require_result(
            _call_tool(
                client,
                "batch.exec",
                {
                    "calls": [
                        {"method": "pixel.set", "params": {"x": 0, "y": 1, "color": [255, 255, 0, 255]}},
                        {"method": "pixel.get", "params": {"x": 0, "y": 1}},
                    ]
                },
                msg_id=18,
            ),
            "batch.exec",
        )
        region = _require_result(
            _call_tool(
                client,
                "pixel.get_region",
                {"x": 0, "y": 0, "width": 2, "height": 2, "format": "png"},
                msg_id=19,
            ),
            "pixel.get_region",
        )
        _require_result(
            _call_tool(
                client,
                "pixel.set_region",
                {"x": 10, "y": 10, "data": region.get("data", ""), "format": "png"},
                msg_id=20,
            ),
            "pixel.set_region",
        )

        print("[9/16] selection")
        _require_result(
            _call_tool(
                client,
                "selection.rect",
                {"x": 0, "y": 0, "width": 4, "height": 4, "mode": "replace"},
                msg_id=21,
            ),
            "selection.rect",
        )
        _require_result(_call_tool(client, "selection.invert", {}, msg_id=22), "selection.invert")
        _require_result(
            _call_tool(client, "selection.export_mask", {"path": TMP_MASK}, msg_id=23),
            "selection.export_mask",
        )
        if not os.path.exists(TMP_MASK) or os.path.getsize(TMP_MASK) == 0:
            raise AssertionError("selection.export_mask file missing")

        print("[10/16] animation control")
        _require_result(_call_tool(client, "animation.fps.get", {}, msg_id=24), "animation.fps.get")
        _require_result(_call_tool(client, "animation.fps.set", {"fps": 12}, msg_id=25), "animation.fps.set")
        _require_result(_call_tool(client, "frame.add", {"after": 0}, msg_id=26), "frame.add")
        _require_result(_call_tool(client, "project.set_active", {"frame": 1}, msg_id=27), "project.set_active")
        _require_result(
            _call_tool(client, "pixel.set", {"x": 0, "y": 0, "color": [0, 255, 0, 255]}, msg_id=28),
            "pixel.set",
        )
        _require_result(_call_tool(client, "project.set_active", {"frame": 0}, msg_id=29), "project.set_active")
        _require_result(
            _call_tool(
                client,
                "animation.frame_duration.set",
                {"durations_ms": [100, 200]},
                msg_id=30,
            ),
            "animation.frame_duration.set",
        )
        _require_result(_call_tool(client, "animation.loop.set", {"mode": "pingpong"}, msg_id=31), "animation.loop.set")

        print("[11/16] animation tags + effects + shader")
        _require_result(
            _call_tool(
                client,
                "animation.tags.add",
                {"name": "tag1", "from": 1, "to": 2, "color": [255, 0, 255, 255]},
                msg_id=32,
            ),
            "animation.tags.add",
        )
        _require_result(
            _call_tool(
                client,
                "animation.tags.update",
                {"name": "tag1", "new_name": "tag_renamed", "from": 1, "to": 2},
                msg_id=33,
            ),
            "animation.tags.update",
        )
        _require_result(
            _call_tool(client, "animation.tags.remove", {"name": "tag_renamed"}, msg_id=34),
            "animation.tags.remove",
        )
        _require_result(
            _call_tool(
                client,
                "effect.layer.add",
                {
                    "shader_path": "res://src/Shaders/Effects/Invert.gdshader",
                    "name": "Invert",
                },
                msg_id=35,
            ),
            "effect.layer.add",
        )
        _require_result(
            _call_tool(client, "effect.layer.apply", {"index": 0, "remove_after": True}, msg_id=36),
            "effect.layer.apply",
        )
        shader_list = _require_result(_call_tool(client, "effect.shader.list", {}, msg_id=37), "effect.shader.list")
        shader_path = None
        shaders = shader_list.get("shaders", [])
        if shaders:
            shader_path = shaders[0]
        if not shader_path:
            raise AssertionError("effect.shader.list empty")
        _require_result(
            _call_tool(client, "effect.shader.inspect", {"shader_path": shader_path}, msg_id=38),
            "effect.shader.inspect",
        )
        _require_result(
            _call_tool(client, "effect.shader.schema", {"shader_path": shader_path}, msg_id=39),
            "effect.shader.schema",
        )

        print("[12/16] brush + palette")
        palettes = _require_result(_call_tool(client, "palette.list", {}, msg_id=40), "palette.list")
        palette_name = None
        for item in palettes.get("palettes", []):
            if item.get("name"):
                palette_name = item.get("name")
                break
        if not palette_name:
            raise AssertionError("palette.list empty")
        _require_result(
            _call_tool(client, "palette.export", {"name": palette_name, "path": TMP_PALETTE}, msg_id=41),
            "palette.export",
        )
        if not os.path.exists(TMP_PALETTE) or os.path.getsize(TMP_PALETTE) == 0:
            raise AssertionError("palette.export file missing")
        _require_result(_call_tool(client, "palette.import", {"path": TMP_PALETTE}, msg_id=42), "palette.import")
        _require_result(_call_tool(client, "brush.list", {}, msg_id=43), "brush.list")
        _require_result(
            _call_tool(client, "brush.add", {"data": region.get("data", "")}, msg_id=44),
            "brush.add",
        )
        brush_list = _require_result(_call_tool(client, "brush.list", {}, msg_id=45), "brush.list")
        brush_index = None
        if brush_list.get("brushes"):
            brush_index = brush_list["brushes"][-1]["index"]
        if brush_index is None:
            raise AssertionError("brush.add failed")
        _require_result(
            _call_tool(
                client,
                "brush.stamp",
                {"x": 4, "y": 4, "brush_index": brush_index, "mode": "multiply", "jitter": 1, "spray": 3, "spray_radius": 1},
                msg_id=46,
            ),
            "brush.stamp",
        )
        _require_result(
            _call_tool(
                client,
                "brush.stroke",
                {
                    "points": [[1, 1], [6, 1]],
                    "brush_index": brush_index,
                    "spacing": 1,
                    "spacing_curve": "ease_in_out",
                    "mode": "screen",
                    "jitter": 0.5,
                },
                msg_id=47,
            ),
            "brush.stroke",
        )
        _require_result(_call_tool(client, "brush.remove", {"index": brush_index}, msg_id=48), "brush.remove")
        _require_result(_call_tool(client, "brush.clear", {}, msg_id=49), "brush.clear")

        print("[13/16] save + export")
        _require_result(_call_tool(client, "project.save", {"path": TMP_PXO}, msg_id=50), "project.save")
        _require_result(
            _call_tool(
                client,
                "project.export",
                {"path": TMP_PNG, "trim": True, "scale": 200, "interpolation": "nearest"},
                msg_id=51,
            ),
            "project.export",
        )
        _require_result(
            _call_tool(
                client,
                "project.export.animated",
                {"path": TMP_GIF, "format": "gif", "trim": True, "scale": 100},
                msg_id=52,
            ),
            "project.export.animated",
        )
        _require_result(
            _call_tool(
                client,
                "project.export.animated",
                {"path": TMP_APNG, "format": "apng"},
                msg_id=53,
            ),
            "project.export.animated",
        )
        _require_result(
            _call_tool(
                client,
                "project.export.spritesheet",
                {"path": TMP_SPRITESHEET, "orientation": "rows", "lines": 1, "scale": 100},
                msg_id=54,
            ),
            "project.export.spritesheet",
        )
        split = _require_result(
            _call_tool(
                client,
                "project.export",
                {"path": "/tmp/pixelorama_mcp_layers.png", "split_layers": True},
                msg_id=55,
            ),
            "project.export",
        )
        for p in split.get("paths", []):
            if not os.path.exists(p) or os.path.getsize(p) == 0:
                raise AssertionError(f"split export file missing: {p}")
        for path in (TMP_PNG, TMP_GIF, TMP_APNG, TMP_SPRITESHEET):
            if not os.path.exists(path) or os.path.getsize(path) == 0:
                raise AssertionError(f"export file missing: {path}")

        print("[14/16] tilemap")
        layers = _require_result(
            _call_tool(client, "layer.add", {"above": 0, "name": "Tilemap", "type": "tilemap"}, msg_id=56),
            "layer.add",
        )
        tilemap_layer = None
        for item in layers.get("layers", []):
            if item.get("name") == "Tilemap":
                tilemap_layer = item.get("index")
                break
        if tilemap_layer is None:
            raise AssertionError("tilemap layer not found")
        tilesets = _require_result(
            _call_tool(client, "tilemap.tileset.create", {"tile_size": [16, 16], "name": "ts"}, msg_id=57),
            "tilemap.tileset.create",
        )
        if not tilesets.get("tilesets"):
            raise AssertionError("tileset create failed")
        _require_result(
            _call_tool(
                client,
                "tilemap.tileset.add_tile",
                {"tileset_index": 0, "path": TMP_PNG, "layer": tilemap_layer},
                msg_id=58,
            ),
            "tilemap.tileset.add_tile",
        )
        _require_result(
            _call_tool(
                client,
                "tilemap.tileset.add_tile",
                {"tileset_index": 0, "path": TMP_PNG, "layer": tilemap_layer},
                msg_id=59,
            ),
            "tilemap.tileset.add_tile",
        )
        _require_result(
            _call_tool(
                client,
                "tilemap.layer.set_tileset",
                {"layer": tilemap_layer, "tileset_index": 0},
                msg_id=60,
            ),
            "tilemap.layer.set_tileset",
        )
        _require_result(
            _call_tool(
                client,
                "tilemap.cell.set",
                {"layer": tilemap_layer, "cell_x": 0, "cell_y": 0, "index": 1},
                msg_id=61,
            ),
            "tilemap.cell.set",
        )
        _require_result(
            _call_tool(
                client,
                "tilemap.cell.get",
                {"layer": tilemap_layer, "cell_x": 0, "cell_y": 0},
                msg_id=62,
            ),
            "tilemap.cell.get",
        )
        _require_result(
            _call_tool(
                client,
                "tilemap.fill_rect",
                {"layer": tilemap_layer, "cell_x": 0, "cell_y": 0, "width": 2, "height": 2, "index": 1},
                msg_id=63,
            ),
            "tilemap.fill_rect",
        )
        _require_result(
            _call_tool(
                client,
                "tilemap.replace_index",
                {"layer": tilemap_layer, "from": 1, "to": 2},
                msg_id=64,
            ),
            "tilemap.replace_index",
        )
        _require_result(
            _call_tool(
                client,
                "tilemap.random_fill",
                {"layer": tilemap_layer, "cell_x": 0, "cell_y": 0, "width": 2, "height": 2, "indices": [1, 2], "weights": [1, 2]},
                msg_id=65,
            ),
            "tilemap.random_fill",
        )

        print("[15/16] symmetry")
        _require_result(
            _call_tool(client, "symmetry.set", {"show_x": True, "show_y": True}, msg_id=66),
            "symmetry.set",
        )

        print("[16/16] import spritesheet + sequence")
        _require_result(
            _call_tool(
                client,
                "project.import.spritesheet",
                {"path": TMP_PNG, "horizontal": 1, "vertical": 1, "mode": "new_project"},
                msg_id=67,
            ),
            "project.import.spritesheet",
        )
        seq_path = "/tmp/pixelorama_mcp_test_seq.png"
        with open(TMP_PNG, "rb") as src, open(seq_path, "wb") as dst:
            dst.write(src.read())
        _require_result(
            _call_tool(
                client,
                "project.import.sequence",
                {"paths": [TMP_PNG, seq_path], "mode": "new_project"},
                msg_id=68,
            ),
            "project.import.sequence",
        )

        print("MCP tests passed")
    except Exception as exc:
        try:
            err = proc.stderr.read().decode("utf-8", errors="replace")
            if err.strip():
                print(err)
        except Exception:
            pass
        print(f"MCP tests failed: {exc}")
        sys.exit(1)
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2)
        except Exception:
            proc.kill()


if __name__ == "__main__":
    main()
