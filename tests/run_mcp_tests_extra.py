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


def _require_error(resp, label):
    if resp is None:
        raise AssertionError(f"{label} timed out")
    if "error" not in resp:
        raise AssertionError(f"{label} expected error")
    return resp["error"]


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
        print("[1/8] initialize")
        client.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
        _require_result(client.recv(), "initialize")

        print("[2/8] bridge info + protocol")
        info = _require_result(_call_tool(client, "bridge.info", {}, msg_id=2), "bridge.info")
        if not info.get("protocol_version"):
            raise AssertionError("bridge.info missing protocol_version")

        print("[3/8] create project")
        _require_result(
            _call_tool(client, "project.create", {"name": "test", "width": 8, "height": 8}, msg_id=3),
            "project.create",
        )

        print("[4/8] invalid params")
        _require_error(_call_tool(client, "project.export", {"path": ""}, msg_id=4), "project.export empty path")
        _require_error(_call_tool(client, "layer.set_props", {"index": 9999}, msg_id=5), "layer.set_props invalid")
        _require_error(
            _call_tool(client, "palette.import", {"path": "/tmp/__missing__.gpl"}, msg_id=6),
            "palette.import invalid",
        )

        print("[5/8] shader validation errors")
        _require_error(
            _call_tool(
                client,
                "effect.shader.apply",
                {"shader_path": "res://src/Shaders/Effects/Invert.gdshader", "params": {"__bad": 1}, "validate": True},
                msg_id=7,
            ),
            "effect.shader.apply validate",
        )

        print("[6/8] batch.exec invalid")
        resp = _call_tool(
            client,
            "batch.exec",
            {"calls": [{"method": "no.such.method", "params": {}}]},
            msg_id=8,
        )
        result = _require_result(resp, "batch.exec")
        if not result.get("results"):
            raise AssertionError("batch.exec missing results")
        first = result["results"][0]
        if first.get("ok") is not False:
            raise AssertionError("batch.exec invalid call should fail")

        print("[7/8] optional token check")
        token = os.environ.get("PIXELORAMA_BRIDGE_TOKEN", "")
        if token:
            from pixelorama_mcp.bridge_client import BridgeClient

            bad = BridgeClient(token="__bad__")
            try:
                bad.call("ping", {})
                raise AssertionError("bridge token should reject")
            except Exception:
                pass
            finally:
                bad.close()

        print("[8/8] done")
        print("MCP extra tests passed")
    except Exception as exc:
        try:
            err = proc.stderr.read().decode("utf-8", errors="replace")
            if err.strip():
                print(err)
        except Exception:
            pass
        print(f"MCP extra tests failed: {exc}")
        sys.exit(1)
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2)
        except Exception:
            proc.kill()


if __name__ == "__main__":
    main()
