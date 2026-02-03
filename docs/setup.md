# 安装与运行（MVP）

本阶段提供：
- Pixelorama 扩展桥接插件（TCP）
- MCP server（stdio）
- 支持 `ping` / `version` 基础连通性

## 1) 构建并安装 Pixelorama 扩展

构建 zip：
```
python3 /Users/dandan/code/tool/Pixelorama-mcp/extension/build_extension_zip.py
```

构建产物：
```
/Users/dandan/code/tool/Pixelorama-mcp/extension/dist/PixeloramaMCP.zip
```

安装（把 zip 复制到 Pixelorama 扩展目录）：
- macOS 通常是：`~/Library/Application Support/Pixelorama/extensions/`
- 也可以在 Pixelorama 中通过扩展管理器安装 zip

## 2) 启动 Pixelorama（Headless）

示例（路径仅供参考）：
```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /path/to/Pixelorama
```

确保扩展已启用（Extension Manager 里可见）。

## 3) 启动 MCP Server（stdio）

```
cd /Users/dandan/code/tool/Pixelorama-mcp/server
../.venv/bin/python -m pixelorama_mcp
```

环境变量（可选）：
- `PIXELORAMA_BRIDGE_HOST`（默认 `127.0.0.1`）
- `PIXELORAMA_BRIDGE_PORT`（默认 `8123`）
- `PIXELORAMA_BRIDGE_PORTS`（例如 `8123,8124`，用于端口扫描）
- `PIXELORAMA_BRIDGE_PORT_RANGE`（例如 `8123-8133`）
- `PIXELORAMA_BRIDGE_TOKEN`（启用后所有请求需携带 `token`）

## 4) 自动化测试脚本（推荐）

```
../.venv/bin/python /Users/dandan/code/tool/Pixelorama-mcp/tests/run_mcp_tests.py
```

覆盖：导入/导出、图层/帧/像素、绘制、选择、动画、Tilemap、效果、笔刷、调色板等。

扩展/边界测试（错误参数、协议/安全）：
```
../.venv/bin/python /Users/dandan/code/tool/Pixelorama-mcp/tests/run_mcp_tests_extra.py
```

## 5) 说明

- MCP server 通过 stdio 接收/输出消息，适配 Codex/MCP 客户端。
- Pixelorama 扩展通过 TCP 接收 JSON line 请求。
