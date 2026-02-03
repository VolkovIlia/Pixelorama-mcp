# Pixelorama MCP

本项目提供 **独立 MCP server（stdio）** 与 **Pixelorama 扩展桥接插件**，实现无需 fork Pixelorama 的自动化能力。

目录结构：
- `server/` MCP 服务（stdio）
- `extension/` Pixelorama 扩展插件（IPC 桥接）
- `docs/` 设计与协议文档

## 运行前提
- 已安装 Pixelorama（官方仓库即可，不需要 fork）
- 使用 Godot 运行 Pixelorama 时可启用扩展（GUI 或 headless 均可）
- Python 3.13.7（建议使用 uv 创建虚拟环境）

## 安装与使用（完整流程）

### 0) 创建虚拟环境（uv, Python 3.13.7）

```
cd /Users/dandan/code/tool/Pixelorama-mcp
uv venv --python 3.13.7 .venv
source .venv/bin/activate
```

### 1) 构建扩展包

```
python3 /Users/dandan/code/tool/Pixelorama-mcp/extension/build_extension_zip.py
```

产物：
```
/Users/dandan/code/tool/Pixelorama-mcp/extension/dist/PixeloramaMCP.zip
```

### 2) 安装扩展包到 Pixelorama

将 zip 放入 Pixelorama 扩展目录：
- macOS: `~/Library/Application Support/Pixelorama/extensions/`
- 也可在 Pixelorama 的 Extension Manager 中安装 zip

安装后在扩展管理器中启用 **Pixelorama MCP Bridge**。

### 3) 启动 Pixelorama

**GUI 模式（推荐调试）**：直接启动 Pixelorama 应用即可。

**Headless 模式（自动化/CI）**：
```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /path/to/Pixelorama
```

扩展启用后，Pixelorama 会启动本地 TCP bridge（默认 `127.0.0.1:8123`）。

### 4) 启动 MCP Server（stdio）

```
cd /Users/dandan/code/tool/Pixelorama-mcp/server
../.venv/bin/python -m pixelorama_mcp
```

可选环境变量：
- `PIXELORAMA_BRIDGE_HOST`（默认 `127.0.0.1`）
- `PIXELORAMA_BRIDGE_PORT`（默认 `8123`）

### 5) 自动化测试脚本（推荐）

```
../.venv/bin/python /Users/dandan/code/tool/Pixelorama-mcp/tests/run_mcp_tests.py
```

测试覆盖：导入/导出、图层/帧/像素、绘制、选择、动画、Tilemap、效果、笔刷、调色板等。

## 当前已实现能力
- project: create/open/save/export/info/set_active/set_indexed_mode
- project: import.sequence/import.spritesheet/export.animated/export.spritesheet
- layer: list/add/remove/rename/move
- layer: get_props/set_props/group.create/parent.set
- frame: list/add/remove/duplicate/move
- pixel: get/set/set_many/get_region/set_region
- draw: line/rect/ellipse/erase_line/text/gradient
- brush: list/add/remove/clear/stamp/stroke
- pixel: replace_color
- canvas: fill/clear/resize/crop
- palette: list/select/create/delete/import/export
- selection: clear/invert/rect/ellipse/lasso/move/export_mask
- symmetry: set
- animation: tags.list/tags.add/tags.update/tags.remove/playback.set
- animation: fps.get/fps.set/frame_duration.set/loop.set
- tilemap: tileset.list/create/add_tile/remove_tile/replace_tile
- tilemap: layer.set_tileset/layer.set_params/offset.set/cell.get/cell.set/cell.clear
- tilemap: fill_rect/replace_index/random_fill
- effect: layer.list/layer.add/layer.remove/layer.move/layer.set_enabled/layer.set_params/layer.apply
- effect: shader.apply/shader.list/shader.inspect
- history: undo/redo
- three_d: object.list/object.add/object.remove/object.update
- batch: exec

## 协议与更多文档
- Bridge 协议：`docs/bridge-protocol.md`
- 路线图：`docs/mcp-roadmap.md`
- 详细步骤：`docs/setup.md`

## 注意事项
- MCP server 通过 stdio 运行，供 Codex/MCP 客户端调用。
- Bridge 使用 TCP JSON-line 协议。
- GUI/Headless 均可使用，只要 Pixelorama 进程在运行且扩展已启用。
