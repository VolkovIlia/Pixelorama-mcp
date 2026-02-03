# Pixelorama MCP 桥接路线图

目标：在不 fork Pixelorama 的前提下，通过 MCP 实现完整的像素制作自动化。
方案：独立 MCP 服务（stdio）+ Pixelorama 扩展插件（IPC 桥）。

## 范围与原则
- 不修改 Pixelorama 源码。
- MCP 作为独立进程运行，使用 stdio 通信。
- Pixelorama 通过扩展插件提供本地 IPC API。
- Headless 运行是第一优先级。
- 分阶段交付，每一阶段可独立发布。

## 架构概览
- MCP server（stdio）：实现 MCP tools/resources/prompts；负责协议与路由。
- Pixelorama 桥接扩展：加载到 `user://extensions`，提供本地 IPC 服务（TCP/WS），
  将命令分发到 Pixelorama API。

## Phase 0 — 调研与协议
- 盘点 Pixelorama Extension API 与核心类能力。
- 定义桥接协议（JSON 请求/响应、版本、错误码）。
- 决定 IPC 传输（TCP vs WebSocket）与消息封包格式。
- 设定本地安全策略（端口绑定、token 等）。
- 输出最小规范：路由、会话模型、错误语义。

## Phase 1 — 桥接扩展 MVP
- 设计扩展包结构（`extension.json` + 入口节点）。
- 启动 IPC 服务并输出端口/就绪状态。
- 实现健康检查与版本查询接口。
- 加入安全关闭与崩溃恢复。
- Headless 环境下可稳定初始化。

## Phase 2 — MCP Server MVP
- 实现 MCP server 骨架（stdio framing）。
- 提供基础 tools：`ping`、`version`、`open_project`、`create_project`、`save_project`、`export`。
- MCP 调用 -> 桥接协议 -> Pixelorama 扩展。
- 提供一个简单 CLI 方便本地手动测试。

## Phase 3 — 核心像素能力（V1）
- 项目 IO：open/save/save_as/export（PNG/APNG/GIF/spritesheet）。
- 画布操作：get/set pixel、fill、clear、resize、crop。
- 图层：list/add/remove/reorder/rename，切换 active layer。
- 帧：list/add/remove/duplicate，切换 active frame。
- 调色板：list/add/remove/select，设置颜色，indexed mode 切换。

## Phase 4 — 绘制与选择（V2）
- 绘制：line/rect/ellipse、笔刷 stamp、擦除、颜色替换。
- 选择：矩形/椭圆/套索，移动/清除/反选，导出 mask。
- 对称设置：X/Y/XY/对角线轴。

## Phase 5 — 高级功能（V3）
已落地：
- 滤镜/效果管线（layer effect + shader apply）。
- Tilemap 图层操作（tileset/cell/offset/params）。
- 动画标签与播放范围（tags + play_only_tags）。
- 导入序列帧 / spritesheet。
- 3D 图层基础操作（对象增删改查）。

## Phase 6 — 可靠性与性能
已落地：
- 批量像素传输（PNG/RAW base64）。
- 批处理（batch.exec）与 Undo/Redo 接口。
- 回归测试脚本覆盖高级能力。
- BridgeClient 自动重连（一次重试）。

## Phase 7 — 扩展能力补齐（已落地）
- 导出能力：GIF / APNG / Spritesheet（含标签分段、布局）。
- 导出高级选项：trim/scale/interpolation/split_layers。
- 笔刷系统：项目笔刷管理、印章/笔划、基础混合模式。
- 笔刷高级能力：抖动/喷枪/间距曲线与更多混合模式。
- 文本与渐变绘制。
- 图层能力：分组层、父子关系、可见性/锁定/混合/不透明度。
- 动画控制：FPS、批量帧时长、循环模式。
- 效果辅助：内置 shader 列表与参数检视。
- 效果参数标准化：schema 与校验。
- Tilemap 深度能力：区域填充、随机权重、批量替换。
- 资源/文件管理：调色板导入/导出。
- 稳定性/安全：token/鉴权、端口冲突处理、版本协商与兼容性检查。

## 下一阶段任务（不含 3D）
- （非 3D 能力已补齐）

## 交付物
- Pixelorama 扩展包（zip/pck）。
- 独立 MCP server 项目（stdio）。
- 文档：安装扩展、headless 运行、MCP 接入方式。
- 示例流程与最小回归测试。

## 验收标准
- Headless 模式下可通过 MCP 完成创建并导出一个 sprite。
- 不需要修改 Pixelorama 源码，仅安装扩展即可使用。
- MCP tools 具备版本化与清晰文档。

## 待确认问题
- 选择 TCP 还是 WebSocket 作为 IPC？
- 本地安全模型（token/端口限制）怎么定？
- “完整像素制作能力”的最小必要功能清单？
