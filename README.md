# Pixelorama MCP

本项目提供 **独立 MCP server（stdio）** 与 **Pixelorama 扩展桥接插件**，无需 fork Pixelorama 即可自动化。

## 运行前提
- 已安装 Pixelorama（官方 App 即可）
- Python 3.13.7（建议使用 uv 创建虚拟环境）

## 使用教程（完整流程）

### 0) 创建虚拟环境（uv）

```
cd /Users/dandan/code/tool/Pixelorama-mcp
uv venv --python 3.13.7 .venv
source .venv/bin/activate
```

### 1) 构建扩展包

```
python3 extension/build_extension_zip.py
```

产物：
```
extension/dist/PixeloramaMCP.zip
```

### 2) 安装扩展包到 Pixelorama

将 zip 放入 Pixelorama 扩展目录：
- macOS: `~/Library/Application Support/Pixelorama/extensions/`
- 也可在 Pixelorama 的 Extension Manager 中安装 zip

安装后在扩展管理器中启用 **Pixelorama MCP Bridge**。

### 3) 启动 Pixelorama

**GUI 模式（推荐）**：
```
/Applications/Pixelorama.app/Contents/MacOS/Pixelorama
```

**Headless 模式（自动化/CI）**（可选）：
```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /path/to/Pixelorama
```

扩展启用后，Pixelorama 会启动本地 TCP bridge（默认 `127.0.0.1:8123`）。

### 4) 启动 MCP Server（stdio）

```
cd server
../.venv/bin/python -m pixelorama_mcp
```

可选环境变量：
- `PIXELORAMA_BRIDGE_HOST`（默认 `127.0.0.1`）
- `PIXELORAMA_BRIDGE_PORT`（默认 `8123`）
- `PIXELORAMA_BRIDGE_PORTS`（例如 `8123,8124`，用于端口扫描）
- `PIXELORAMA_BRIDGE_PORT_RANGE`（例如 `8123-8133`）
- `PIXELORAMA_BRIDGE_TOKEN`（启用后所有请求需携带 `token`）

如果启用 token，需要用同一个 token 启动 Pixelorama 与 MCP server。

### 5) 自动化测试脚本

```
../.venv/bin/python /Users/dandan/code/tool/Pixelorama-mcp/tests/run_mcp_tests.py
```

测试覆盖：导入/导出、图层/帧/像素、绘制、选择、动画、Tilemap、效果、笔刷、调色板等。

扩展/边界测试（错误参数、协议与安全校验）：
```
../.venv/bin/python /Users/dandan/code/tool/Pixelorama-mcp/tests/run_mcp_tests_extra.py
```

## 与 Codex 集成

### 1) 启动 Pixelorama（官方 App）

> 如果启用 token，必须从终端启动 Pixelorama.app 才能注入环境变量。

```
PIXELORAMA_BRIDGE_TOKEN=YOUR_TOKEN \
/Applications/Pixelorama.app/Contents/MacOS/Pixelorama
```

### 2) 注册 MCP Server 到 Codex

```
codex mcp add pixelorama \
  --env PIXELORAMA_BRIDGE_HOST=127.0.0.1 \
  --env PIXELORAMA_BRIDGE_PORT=8123 \
  --env PIXELORAMA_BRIDGE_TOKEN=YOUR_TOKEN \
  -- /Users/dandan/code/tool/Pixelorama-mcp/.venv/bin/python -m pixelorama_mcp
```

完成后在 Codex 里输入 `/mcp`，确认已连接到 `pixelorama`。

### 3) 使用方式

在 Codex 里直接描述需求即可，例如：
- “新建 32x32 画布，画一个红色圆点并导出 PNG。”
- “把当前项目导出成 GIF，标签为 walk，方向 forward。”

## 与 Gemini CLI 集成（0.26.0）

在 `~/.gemini/settings.json` 中新增 `mcpServers.pixelorama`：

```
{
  "mcpServers": {
    "pixelorama": {
      "command": "/Users/dandan/code/tool/Pixelorama-mcp/.venv/bin/python",
      "args": ["-m", "pixelorama_mcp"],
      "cwd": "/Users/dandan/code/tool/Pixelorama-mcp/server",
      "env": {
        "PYTHONPATH": "/Users/dandan/code/tool/Pixelorama-mcp/server",
        "PIXELORAMA_BRIDGE_HOST": "127.0.0.1",
        "PIXELORAMA_BRIDGE_PORT": "8123"
      }
    }
  }
}
```

如果启用了 token，需要在 `env` 里加：
```
"PIXELORAMA_BRIDGE_TOKEN": "YOUR_TOKEN"
```

修改后重启 Gemini CLI 即可生效。

## 协议与更多文档
- Bridge 协议：`docs/bridge-protocol.md`
- 能力清单：`docs/capabilities.md`
- 路线图：`docs/mcp-roadmap.md`
- 详细步骤：`docs/setup.md`
