# Bridge 协议（Pixelorama 扩展 <-> MCP Server）

传输：TCP
消息格式：**一行一个 JSON**（UTF-8），以 `\n` 结尾。

## 请求
```
{
  "id": "req-1",
  "method": "ping",
  "params": {}
}
```

字段说明：
- `id`：请求 ID（字符串）
- `method`：方法名
- `params`：参数对象（可为空）

## 响应
成功：
```
{
  "id": "req-1",
  "ok": true,
  "result": {"message": "pong"}
}
```

失败：
```
{
  "id": "req-1",
  "ok": false,
  "error": {"code": "invalid_method", "message": "unknown method"}
}
```

## 当前实现的方法
- `ping` -> {"message":"pong"}
- `version` -> {"pixelorama":"vX.Y.Z"}
- `bridge.info` -> {"pixelorama","extension_version","protocol_version"}
- `project.create` -> 返回项目信息（name/size/frames/layers/current/save_path）
- `project.open` -> 打开 `.pxo`，返回项目信息
- `project.save` -> 保存 `.pxo`
- `project.export` -> PNG（支持 trim/scale/interpolation/split_layers/layer）
- `project.export.animated` -> GIF/APNG（支持标签/方向/trim/scale/interpolation/split_layers）
- `project.export.spritesheet` -> Spritesheet PNG（支持行列布局/trim/scale/interpolation）
- `project.import.sequence` -> 导入序列帧（新工程/追加）
- `project.import.spritesheet` -> 导入 spritesheet（新工程/新图层）
- `project.info` / `project.set_active` / `project.set_indexed_mode`
- `layer.list` / `layer.add` / `layer.remove` / `layer.rename` / `layer.move`
- `layer.get_props` / `layer.set_props` / `layer.group.create` / `layer.parent.set`
- `frame.list` / `frame.add` / `frame.remove` / `frame.duplicate` / `frame.move`
- `pixel.get` / `pixel.set` / `pixel.set_many`
- `pixel.get_region` / `pixel.set_region`（PNG/RAW base64）
- `canvas.fill` / `canvas.clear` / `canvas.resize` / `canvas.crop`
- `palette.list` / `palette.select` / `palette.create` / `palette.delete` / `palette.import` / `palette.export`
- `draw.line` / `draw.rect` / `draw.ellipse` / `draw.erase_line` / `draw.text` / `draw.gradient`
- `brush.list` / `brush.add` / `brush.remove` / `brush.clear` / `brush.stamp` / `brush.stroke`
- `pixel.replace_color`
- `selection.clear` / `selection.invert` / `selection.rect` / `selection.ellipse` / `selection.lasso` / `selection.move`
- `selection.export_mask`
- `symmetry.set`
- `animation.tags.list` / `animation.tags.add` / `animation.tags.update` / `animation.tags.remove`
- `animation.playback.set`
- `animation.fps.get` / `animation.fps.set` / `animation.frame_duration.set` / `animation.loop.set`
- `tilemap.tileset.list` / `tilemap.tileset.create` / `tilemap.tileset.add_tile` / `tilemap.tileset.remove_tile` / `tilemap.tileset.replace_tile`
- `tilemap.layer.set_tileset` / `tilemap.layer.set_params`
- `tilemap.offset.set` / `tilemap.cell.get` / `tilemap.cell.set` / `tilemap.cell.clear`
- `tilemap.fill_rect` / `tilemap.replace_index` / `tilemap.random_fill`
- `effect.layer.list` / `effect.layer.add` / `effect.layer.remove` / `effect.layer.move`
- `effect.layer.set_enabled` / `effect.layer.set_params` / `effect.layer.apply`
- `effect.shader.apply` / `effect.shader.list` / `effect.shader.inspect` / `effect.shader.schema`
- `history.undo` / `history.redo`
- `three_d.object.list` / `three_d.object.add` / `three_d.object.remove` / `three_d.object.update`
- `batch.exec`

## 说明
- `pixel.get_region` 返回 `data` 为 base64；`format=png` 或 `format=raw`。
- `pixel.set_region` 支持 `mode=replace`（覆盖当前 cel）。
- `batch.exec` 结果为 `results` 数组，每项含 `ok` 与 `result`/`error`。
- 若设置 `PIXELORAMA_BRIDGE_TOKEN`，所有请求需携带 `token` 字段。
- `brush.stamp`/`brush.stroke` 支持 `jitter`、`spray`、`spray_radius`、`spacing_curve` 与更多混合模式。
- `effect.shader.apply` / `effect.layer.add` / `effect.layer.set_params` 支持 `validate` 参数进行校验。
