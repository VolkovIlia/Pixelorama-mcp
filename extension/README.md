# Pixelorama MCP 扩展

此扩展在 Pixelorama 内启动一个本地 TCP IPC 服务，供 MCP server 调用。

默认：
- Host: `127.0.0.1`
- Port: `8123`

可通过环境变量覆盖：
- `PIXELORAMA_BRIDGE_HOST`
- `PIXELORAMA_BRIDGE_PORT`

构建：
```
python3 /Users/dandan/code/tool/Pixelorama-mcp/extension/build_extension_zip.py
```
