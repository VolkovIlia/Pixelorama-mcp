extends Node

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 8123

var _server := TCPServer.new()
var _peers := {}  # id -> StreamPeerTCP
var _buffers := {}  # id -> PackedByteArray
var _api: Node = null


func _ready() -> void:
	_api = get_node_or_null("/root/ExtensionsApi")
	process_mode = Node.PROCESS_MODE_ALWAYS
	var host := DEFAULT_HOST
	var port := DEFAULT_PORT
	if OS.has_environment("PIXELORAMA_BRIDGE_HOST"):
		host = OS.get_environment("PIXELORAMA_BRIDGE_HOST")
	if OS.has_environment("PIXELORAMA_BRIDGE_PORT"):
		var port_str := OS.get_environment("PIXELORAMA_BRIDGE_PORT")
		if port_str.is_valid_int():
			port = int(port_str)
	var err := _server.listen(port, host)
	if err != OK:
		push_error("Pixelorama MCP bridge listen failed: %s" % error_string(err))
		return
	set_process(true)
	print("Pixelorama MCP bridge listening on %s:%d" % [host, port])


func _process(_delta: float) -> void:
	while _server.is_connection_available():
		var peer := _server.take_connection()
		var peer_id := str(peer.get_instance_id())
		_peers[peer_id] = peer
		_buffers[peer_id] = PackedByteArray()

	var to_remove := []
	for peer_id in _peers.keys():
		var peer: StreamPeerTCP = _peers[peer_id]
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			to_remove.append(peer_id)
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var data = peer.get_data(available)
			if data[0] != OK:
				continue
			var buf: PackedByteArray = _buffers[peer_id]
			buf.append_array(data[1])
			_buffers[peer_id] = buf
			_drain_buffer(peer_id)

	for peer_id in to_remove:
		_peers.erase(peer_id)
		_buffers.erase(peer_id)


func _drain_buffer(peer_id: String) -> void:
	var buf: PackedByteArray = _buffers[peer_id]
	while true:
		var idx := buf.find(10)  # '\n'
		if idx == -1:
			break
		var line_bytes := buf.slice(0, idx)
		buf = buf.slice(idx + 1, buf.size())
		var line := line_bytes.get_string_from_utf8().strip_edges()
		if line.is_empty():
			continue
		_handle_request(peer_id, line)
	_buffers[peer_id] = buf


func _handle_request(peer_id: String, line: String) -> void:
	var json := JSON.new()
	var err := json.parse(line)
	if err != OK:
		_send_error(peer_id, "", "parse_error", "invalid json")
		return
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		_send_error(peer_id, "", "invalid_request", "expected object")
		return

	var req_id = data.get("id", "")
	var method = data.get("method", "")
	var params = data.get("params", {})
	if typeof(params) != TYPE_DICTIONARY:
		params = {}
	var result := _dispatch_method(str(method), params, true)
	_send_result(peer_id, req_id, result)
	return


func _send_ok(peer_id: String, req_id, result: Dictionary) -> void:
	_send(peer_id, {"id": req_id, "ok": true, "result": result})


func _send_error(peer_id: String, req_id, code: String, message: String) -> void:
	_send(peer_id, {"id": req_id, "ok": false, "error": {"code": code, "message": message}})


func _send_result(peer_id: String, req_id, result: Dictionary) -> void:
	if result.has("_error"):
		var err: Dictionary = result["_error"]
		_send_error(peer_id, req_id, str(err.get("code", "error")), str(err.get("message", "")))
	else:
		_send_ok(peer_id, req_id, result)


func _send(peer_id: String, payload: Dictionary) -> void:
	if not _peers.has(peer_id):
		return
	var peer: StreamPeerTCP = _peers[peer_id]
	var line := JSON.stringify(payload)
	var data := line.to_utf8_buffer()
	data.append(10)
	peer.put_data(data)


func _dispatch_method(method: String, params: Dictionary, allow_batch: bool) -> Dictionary:
	if method == "ping":
		return {"message": "pong"}
	if method == "version":
		var version := ""
		if _api and _api.general:
			version = _api.general.get_pixelorama_version()
		return {"pixelorama": version}
	if method == "batch.exec":
		if not allow_batch:
			return _err("invalid_method", "nested batch not allowed")
		return _handle_batch_exec(params)
	if method == "project.create":
		return _handle_project_create(params)
	if method == "project.open":
		return _handle_project_open(params)
	if method == "project.save":
		return _handle_project_save(params)
	if method == "project.export":
		return _handle_project_export(params)
	if method == "project.info":
		return _handle_project_info()
	if method == "project.set_active":
		return _handle_project_set_active(params)
	if method == "project.set_indexed_mode":
		return _handle_project_set_indexed_mode(params)
	if method == "project.import.sequence":
		return _handle_project_import_sequence(params)
	if method == "project.import.spritesheet":
		return _handle_project_import_spritesheet(params)
	if method == "project.export.animated":
		return _handle_project_export_animated(params)
	if method == "project.export.spritesheet":
		return _handle_project_export_spritesheet(params)
	if method == "layer.list":
		return _handle_layer_list()
	if method == "layer.add":
		return _handle_layer_add(params)
	if method == "layer.remove":
		return _handle_layer_remove(params)
	if method == "layer.rename":
		return _handle_layer_rename(params)
	if method == "layer.move":
		return _handle_layer_move(params)
	if method == "layer.get_props":
		return _handle_layer_get_props(params)
	if method == "layer.set_props":
		return _handle_layer_set_props(params)
	if method == "layer.group.create":
		return _handle_layer_group_create(params)
	if method == "layer.parent.set":
		return _handle_layer_parent_set(params)
	if method == "frame.list":
		return _handle_frame_list()
	if method == "frame.add":
		return _handle_frame_add(params)
	if method == "frame.remove":
		return _handle_frame_remove(params)
	if method == "frame.duplicate":
		return _handle_frame_duplicate(params)
	if method == "frame.move":
		return _handle_frame_move(params)
	if method == "pixel.get":
		return _handle_pixel_get(params)
	if method == "pixel.set":
		return _handle_pixel_set(params)
	if method == "pixel.set_many":
		return _handle_pixel_set_many(params)
	if method == "pixel.get_region":
		return _handle_pixel_get_region(params)
	if method == "pixel.set_region":
		return _handle_pixel_set_region(params)
	if method == "pixel.replace_color":
		return _handle_pixel_replace_color(params)
	if method == "canvas.fill":
		return _handle_canvas_fill(params)
	if method == "canvas.clear":
		return _handle_canvas_clear(params)
	if method == "canvas.resize":
		return _handle_canvas_resize(params)
	if method == "canvas.crop":
		return _handle_canvas_crop(params)
	if method == "palette.list":
		return _handle_palette_list()
	if method == "palette.select":
		return _handle_palette_select(params)
	if method == "palette.create":
		return _handle_palette_create(params)
	if method == "palette.delete":
		return _handle_palette_delete(params)
	if method == "draw.line":
		return _handle_draw_line(params)
	if method == "draw.rect":
		return _handle_draw_rect(params)
	if method == "draw.ellipse":
		return _handle_draw_ellipse(params)
	if method == "draw.erase_line":
		return _handle_draw_erase_line(params)
	if method == "draw.text":
		return _handle_draw_text(params)
	if method == "draw.gradient":
		return _handle_draw_gradient(params)
	if method == "selection.clear":
		return _handle_selection_clear()
	if method == "selection.invert":
		return _handle_selection_invert()
	if method == "selection.rect":
		return _handle_selection_rect(params)
	if method == "selection.ellipse":
		return _handle_selection_ellipse(params)
	if method == "selection.lasso":
		return _handle_selection_lasso(params)
	if method == "selection.move":
		return _handle_selection_move(params)
	if method == "selection.export_mask":
		return _handle_selection_export_mask(params)
	if method == "symmetry.set":
		return _handle_symmetry_set(params)
	if method == "animation.tags.list":
		return _handle_animation_tags_list()
	if method == "animation.tags.add":
		return _handle_animation_tags_add(params)
	if method == "animation.tags.update":
		return _handle_animation_tags_update(params)
	if method == "animation.tags.remove":
		return _handle_animation_tags_remove(params)
	if method == "animation.playback.set":
		return _handle_animation_playback_set(params)
	if method == "animation.fps.get":
		return _handle_animation_fps_get()
	if method == "animation.fps.set":
		return _handle_animation_fps_set(params)
	if method == "animation.frame_duration.set":
		return _handle_animation_frame_duration_set(params)
	if method == "animation.loop.set":
		return _handle_animation_loop_set(params)
	if method == "tilemap.tileset.list":
		return _handle_tilemap_tileset_list()
	if method == "tilemap.tileset.create":
		return _handle_tilemap_tileset_create(params)
	if method == "tilemap.tileset.add_tile":
		return _handle_tilemap_tileset_add_tile(params)
	if method == "tilemap.tileset.remove_tile":
		return _handle_tilemap_tileset_remove_tile(params)
	if method == "tilemap.tileset.replace_tile":
		return _handle_tilemap_tileset_replace_tile(params)
	if method == "tilemap.layer.set_tileset":
		return _handle_tilemap_layer_set_tileset(params)
	if method == "tilemap.layer.set_params":
		return _handle_tilemap_layer_set_params(params)
	if method == "tilemap.offset.set":
		return _handle_tilemap_offset_set(params)
	if method == "tilemap.cell.get":
		return _handle_tilemap_cell_get(params)
	if method == "tilemap.cell.set":
		return _handle_tilemap_cell_set(params)
	if method == "tilemap.cell.clear":
		return _handle_tilemap_cell_clear(params)
	if method == "tilemap.fill_rect":
		return _handle_tilemap_fill_rect(params)
	if method == "tilemap.replace_index":
		return _handle_tilemap_replace_index(params)
	if method == "tilemap.random_fill":
		return _handle_tilemap_random_fill(params)
	if method == "effect.layer.list":
		return _handle_effect_layer_list(params)
	if method == "effect.layer.add":
		return _handle_effect_layer_add(params)
	if method == "effect.layer.remove":
		return _handle_effect_layer_remove(params)
	if method == "effect.layer.move":
		return _handle_effect_layer_move(params)
	if method == "effect.layer.set_enabled":
		return _handle_effect_layer_set_enabled(params)
	if method == "effect.layer.set_params":
		return _handle_effect_layer_set_params(params)
	if method == "effect.layer.apply":
		return _handle_effect_layer_apply(params)
	if method == "effect.shader.apply":
		return _handle_effect_shader_apply(params)
	if method == "effect.shader.list":
		return _handle_effect_shader_list()
	if method == "effect.shader.inspect":
		return _handle_effect_shader_inspect(params)
	if method == "history.undo":
		return _handle_history_undo()
	if method == "history.redo":
		return _handle_history_redo()
	if method == "brush.list":
		return _handle_brush_list()
	if method == "brush.add":
		return _handle_brush_add(params)
	if method == "brush.remove":
		return _handle_brush_remove(params)
	if method == "brush.clear":
		return _handle_brush_clear()
	if method == "brush.stamp":
		return _handle_brush_stamp(params)
	if method == "brush.stroke":
		return _handle_brush_stroke(params)
	if method == "palette.import":
		return _handle_palette_import(params)
	if method == "palette.export":
		return _handle_palette_export(params)
	if method == "three_d.object.list":
		return _handle_three_d_object_list(params)
	if method == "three_d.object.add":
		return _handle_three_d_object_add(params)
	if method == "three_d.object.remove":
		return _handle_three_d_object_remove(params)
	if method == "three_d.object.update":
		return _handle_three_d_object_update(params)
	return _err("invalid_method", "unknown method")


func _handle_project_create(params: Dictionary) -> Dictionary:
	var name := str(params.get("name", "untitled"))
	var width := int(params.get("width", 64))
	var height := int(params.get("height", 64))
	var fill := _parse_color(params.get("fill_color", null))
	if not _api or not _api.project:
		return {"_error": {"code": "extensions_api_unavailable", "message": "ExtensionsApi missing"}}
	var frames: Array[Frame] = []
	var project: Project = _api.project.new_project(frames, name, Vector2(width, height), fill, false)
	if _api.project:
		_api.project.current_project = project
	return _project_info(project)


func _handle_project_open(params: Dictionary) -> Dictionary:
	var path := str(params.get("path", ""))
	if path.is_empty():
		return {"_error": {"code": "path_required", "message": "path is required"}}
	if not FileAccess.file_exists(path):
		return {"_error": {"code": "file_not_found", "message": "file not found"}}
	var replace_empty := true
	if params.has("replace_empty"):
		replace_empty = bool(params.get("replace_empty"))
	OpenSave.open_pxo_file(path, false, replace_empty)
	return _project_info(Global.current_project)


func _handle_project_save(params: Dictionary) -> Dictionary:
	var path := str(params.get("path", ""))
	if path.is_empty():
		return {"_error": {"code": "path_required", "message": "path is required"}}
	var include_blended := false
	if params.has("include_blended"):
		include_blended = bool(params.get("include_blended"))
	var ok := OpenSave.save_pxo_file(path, false, include_blended, Global.current_project)
	if not ok:
		return {"_error": {"code": "save_failed", "message": "save failed"}}
	return {"path": path}


func _handle_project_export(params: Dictionary) -> Dictionary:
	var path := str(params.get("path", ""))
	if path.is_empty():
		return {"_error": {"code": "path_required", "message": "path is required"}}
	var project := Global.current_project
	var frame := project.current_frame
	if params.has("frame"):
		frame = int(params.get("frame"))
		frame = clampi(frame, 0, project.frames.size() - 1)
	var image := project.new_empty_image()
	DrawingAlgos.blend_layers(image, project.frames[frame], Vector2i.ZERO, project)
	var err := image.save_png(path)
	if err != OK:
		return {"_error": {"code": "export_failed", "message": error_string(err)}}
	return {"path": path, "frame": frame}


func _handle_project_export_animated(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var path := str(params.get("path", ""))
	if path.is_empty():
		return _err("path_required", "path is required")
	var format := str(params.get("format", "gif")).to_lower()
	var project: Project = Global.current_project
	Export.current_tab = Export.ExportTab.IMAGE
	Export.split_layers = false
	Export.erase_unselected_area = false
	Export.trim_images = false
	Export.direction = Export.AnimationDirection.FORWARD
	if params.has("direction"):
		Export.direction = _parse_animation_direction(params.get("direction", "forward"))
	Export.frame_current_tag = Export.ExportFrames.ALL_FRAMES
	if params.has("tag"):
		var tag_name := str(params.get("tag", ""))
		if not tag_name.is_empty():
			for i in project.animation_tags.size():
				if project.animation_tags[i].name == tag_name:
					Export.frame_current_tag = Export.ExportFrames.size() + i
					break
	if params.has("tag_index"):
		var tag_index := int(params.get("tag_index", -1))
		if tag_index >= 0 and tag_index < project.animation_tags.size():
			Export.frame_current_tag = Export.ExportFrames.size() + tag_index
	Export.cache_blended_frames(project)
	Export.process_animation(project)
	var frames: Array = []
	for item in Export.processed_images:
		var p: Export.ProcessedImage = item
		var img := p.image
		img.convert(Image.FORMAT_RGBA8)
		var frame := AImgIOFrame.new()
		frame.content = img
		frame.duration = p.duration
		frames.append(frame)
	if frames.is_empty():
		return _err("export_failed", "no frames to export")
	if format == "gif":
		var data := _export_gif_frames(frames)
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return _err("export_failed", "unable to open file")
		file.store_buffer(data)
		return {"path": path, "format": "gif", "frames": frames.size()}
	if format == "apng":
		var data := _export_apng_frames(frames, project.fps)
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return _err("export_failed", "unable to open file")
		file.store_buffer(data)
		return {"path": path, "format": "apng", "frames": frames.size()}
	return _err("invalid_format", "format must be gif or apng")


func _handle_project_export_spritesheet(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var path := str(params.get("path", ""))
	if path.is_empty():
		return _err("path_required", "path is required")
	var project: Project = Global.current_project
	Export.current_tab = Export.ExportTab.SPRITESHEET
	Export.split_layers = false
	Export.erase_unselected_area = false
	Export.trim_images = false
	Export.orientation = _parse_spritesheet_orientation(params.get("orientation", "rows"))
	Export.lines_count = int(params.get("lines", 1))
	Export.frame_current_tag = Export.ExportFrames.ALL_FRAMES
	if params.has("tag"):
		var tag_name := str(params.get("tag", ""))
		if not tag_name.is_empty():
			for i in project.animation_tags.size():
				if project.animation_tags[i].name == tag_name:
					Export.frame_current_tag = Export.ExportFrames.size() + i
					break
	Export.cache_blended_frames(project)
	Export.process_spritesheet(project)
	if Export.processed_images.is_empty():
		return _err("export_failed", "no image to export")
	var sheet := Export.processed_images[0].image
	var err := sheet.save_png(path)
	if err != OK:
		return _err("export_failed", error_string(err))
	return {"path": path, "width": sheet.get_width(), "height": sheet.get_height()}


func _project_info(project: Project) -> Dictionary:
	return {
		"name": project.name,
		"size": [project.size.x, project.size.y],
		"frames": project.frames.size(),
		"layers": project.layers.size(),
		"current_frame": project.current_frame,
		"current_layer": project.current_layer,
		"save_path": project.save_path
	}


func _handle_project_info() -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	return _project_info(Global.current_project)


func _handle_project_set_active(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project := Global.current_project
	var frame := project.current_frame
	var layer := project.current_layer
	if params.has("frame"):
		frame = int(params.get("frame"))
	if params.has("layer"):
		layer = int(params.get("layer"))
	frame = clampi(frame, 0, project.frames.size() - 1)
	layer = clampi(layer, 0, project.layers.size() - 1)
	project.change_cel(frame, layer)
	return _project_info(project)


func _handle_project_set_indexed_mode(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var enabled := bool(params.get("enabled", false))
	if enabled:
		Global.current_project.color_mode = Project.INDEXED_MODE
	else:
		Global.current_project.color_mode = Image.FORMAT_RGBA8
	return {"indexed": enabled}


func _handle_layer_list() -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project := Global.current_project
	var items := []
	for i in project.layers.size():
		var layer := project.layers[i]
		items.append({
			"index": i,
			"name": layer.name,
			"type": layer.get_class()
		})
	return {"layers": items, "current_layer": project.current_layer}


func _handle_layer_add(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project := Global.current_project
	if project.layers.size() == 0:
		return _err("invalid_operation", "project has no layers")
	var above := int(params.get("above", project.layers.size() - 1))
	above = clampi(above, 0, project.layers.size() - 1)
	var name := str(params.get("name", ""))
	var type_val = params.get("type", "pixel")
	var layer_type := _parse_layer_type(type_val)
	if layer_type < 0:
		return _err("invalid_type", "unknown layer type")
	if layer_type == Global.LayerTypes.TILEMAP:
		var tileset_index := int(params.get("tileset_index", -1))
		var tile_size := Vector2i(16, 16)
		if params.has("tile_size"):
			var size_raw: Variant = params.get("tile_size", [])
			if typeof(size_raw) == TYPE_ARRAY:
				var size_arr: Array = size_raw
				if size_arr.size() >= 2:
					tile_size = Vector2i(int(size_arr[0]), int(size_arr[1]))
		var tileset: TileSetCustom
		if tileset_index >= 0 and tileset_index < project.tilesets.size():
			tileset = project.tilesets[tileset_index]
		else:
			var tileset_name := str(params.get("tileset_name", ""))
			tileset = TileSetCustom.new(tile_size, tileset_name, TileSet.TILE_SHAPE_SQUARE, true)
			project.add_tileset(tileset)
		var layer_tilemap := LayerTileMap.new(project, tileset, name)
		var cels: Array = []
		for f in project.frames.size():
			cels.append(layer_tilemap.new_empty_cel())
		var insert_index := clampi(above + 1, 0, project.layers.size())
		project.add_layers([layer_tilemap], PackedInt32Array([insert_index]), [cels])
	else:
		ExtensionsApi.project.add_new_layer(above, "", layer_type)
		if not name.is_empty():
			var new_index := above + 1
			if new_index >= 0 and new_index < project.layers.size():
				project.layers[new_index].name = name
	return _handle_layer_list()


func _handle_layer_remove(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project := Global.current_project
	if project.layers.size() <= 1:
		return _err("invalid_operation", "cannot remove last layer")
	var index := int(params.get("index", -1))
	if index < 0 or index >= project.layers.size():
		return _err("invalid_index", "layer index out of range")
	project.remove_layers(PackedInt32Array([index]))
	project.change_cel(project.current_frame, clampi(project.current_layer, 0, project.layers.size() - 1))
	return _handle_layer_list()


func _handle_layer_rename(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project := Global.current_project
	var index := int(params.get("index", -1))
	var name := str(params.get("name", ""))
	if index < 0 or index >= project.layers.size():
		return _err("invalid_index", "layer index out of range")
	if name.is_empty():
		return _err("invalid_name", "name required")
	project.layers[index].name = name
	return _handle_layer_list()


func _handle_layer_move(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project := Global.current_project
	var from_idx := int(params.get("from", -1))
	var to_idx := int(params.get("to", -1))
	if from_idx < 0 or from_idx >= project.layers.size():
		return _err("invalid_index", "from out of range")
	if to_idx < 0 or to_idx >= project.layers.size():
		return _err("invalid_index", "to out of range")
	var layer := project.layers[from_idx]
	project.move_layers(PackedInt32Array([from_idx]), PackedInt32Array([to_idx]), [layer.parent])
	return _handle_layer_list()


func _handle_layer_get_props(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var index := int(params.get("index", project.current_layer))
	if index < 0 or index >= project.layers.size():
		return _err("invalid_index", "layer index out of range")
	var layer := project.layers[index]
	var parent_index := -1
	if is_instance_valid(layer.parent):
		parent_index = project.layers.find(layer.parent)
	return {
		"index": index,
		"name": layer.name,
		"type": layer.get_class(),
		"visible": layer.visible,
		"locked": layer.locked,
		"opacity": layer.opacity,
		"blend_mode": layer.blend_mode,
		"clipping_mask": layer.clipping_mask,
		"parent": parent_index
	}


func _handle_layer_set_props(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var index := int(params.get("index", project.current_layer))
	if index < 0 or index >= project.layers.size():
		return _err("invalid_index", "layer index out of range")
	var layer := project.layers[index]
	if params.has("name"):
		layer.name = str(params.get("name", layer.name))
	if params.has("visible"):
		layer.visible = bool(params.get("visible", layer.visible))
	if params.has("locked"):
		layer.locked = bool(params.get("locked", layer.locked))
	if params.has("opacity"):
		layer.opacity = clampf(float(params.get("opacity", layer.opacity)), 0.0, 1.0)
	if params.has("blend_mode"):
		var mode := _parse_blend_mode(params.get("blend_mode"))
		if mode >= -2:
			layer.blend_mode = mode
	if params.has("clipping_mask"):
		layer.clipping_mask = bool(params.get("clipping_mask", layer.clipping_mask))
	return _handle_layer_get_props({"index": index})


func _handle_layer_group_create(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var above := int(params.get("above", project.layers.size() - 1))
	above = clampi(above, 0, project.layers.size() - 1)
	var name := str(params.get("name", ""))
	var group := GroupLayer.new(project, name)
	var cels: Array = []
	for f in project.frames.size():
		cels.append(group.new_empty_cel())
	var insert_index := clampi(above + 1, 0, project.layers.size())
	project.add_layers([group], PackedInt32Array([insert_index]), [cels])
	return _handle_layer_list()


func _handle_layer_parent_set(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var index := int(params.get("index", project.current_layer))
	var parent_index := int(params.get("parent", -1))
	if index < 0 or index >= project.layers.size():
		return _err("invalid_index", "layer index out of range")
	if parent_index >= project.layers.size():
		return _err("invalid_index", "parent index out of range")
	var layer := project.layers[index]
	if parent_index < 0:
		layer.parent = null
	else:
		var parent := project.layers[parent_index]
		if parent is GroupLayer:
			layer.parent = parent
		else:
			return _err("invalid_parent", "parent must be a GroupLayer")
	return _handle_layer_get_props({"index": index})


func _handle_frame_list() -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project := Global.current_project
	var items := []
	for i in project.frames.size():
		var frame := project.frames[i]
		items.append({"index": i, "duration": frame.duration})
	return {"frames": items, "current_frame": project.current_frame}


func _handle_frame_add(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project := Global.current_project
	var after := int(params.get("after", project.frames.size() - 1))
	after = clampi(after, 0, project.frames.size() - 1)
	var frame := project.new_empty_frame()
	project.add_frames([frame], PackedInt32Array([after + 1]))
	return _handle_frame_list()


func _handle_frame_remove(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project := Global.current_project
	if project.frames.size() <= 1:
		return _err("invalid_operation", "cannot remove last frame")
	var index := int(params.get("index", -1))
	if index < 0 or index >= project.frames.size():
		return _err("invalid_index", "frame index out of range")
	project.remove_frames(PackedInt32Array([index]))
	project.change_cel(clampi(project.current_frame, 0, project.frames.size() - 1), project.current_layer)
	return _handle_frame_list()


func _handle_frame_duplicate(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project := Global.current_project
	var index := int(params.get("index", project.current_frame))
	if index < 0 or index >= project.frames.size():
		return _err("invalid_index", "frame index out of range")
	var src := project.frames[index]
	var new_cels: Array[BaseCel] = []
	for cel in src.cels:
		var dup := cel.duplicate_cel()
		var content = cel.copy_content()
		dup.set_content(content)
		new_cels.append(dup)
	var frame := Frame.new(new_cels, src.duration)
	project.add_frames([frame], PackedInt32Array([index + 1]))
	return _handle_frame_list()


func _handle_frame_move(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project := Global.current_project
	var from_idx := int(params.get("from", -1))
	var to_idx := int(params.get("to", -1))
	if from_idx < 0 or from_idx >= project.frames.size():
		return _err("invalid_index", "from out of range")
	if to_idx < 0 or to_idx >= project.frames.size():
		return _err("invalid_index", "to out of range")
	project.move_frames(PackedInt32Array([from_idx]), PackedInt32Array([to_idx]))
	return _handle_frame_list()


func _handle_pixel_get(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project := Global.current_project
	var x := int(params.get("x", -1))
	var y := int(params.get("y", -1))
	var frame := int(params.get("frame", project.current_frame))
	var layer := int(params.get("layer", project.current_layer))
	if x < 0 or y < 0 or x >= project.size.x or y >= project.size.y:
		return _err("out_of_bounds", "pixel out of bounds")
	var cel := _get_pixel_cel(frame, layer)
	if cel == null:
		return _err("invalid_cel", "not a PixelCel")
	var color := cel.image.get_pixel(x, y)
	return {"color": _color_to_array(color)}


func _handle_pixel_set(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project := Global.current_project
	var x := int(params.get("x", -1))
	var y := int(params.get("y", -1))
	var frame := int(params.get("frame", project.current_frame))
	var layer := int(params.get("layer", project.current_layer))
	if x < 0 or y < 0 or x >= project.size.x or y >= project.size.y:
		return _err("out_of_bounds", "pixel out of bounds")
	var cel := _get_pixel_cel(frame, layer)
	if cel == null:
		return _err("invalid_cel", "not a PixelCel")
	var color := _parse_color(params.get("color", null))
	cel.image.set_pixel(x, y, color)
	cel.update_texture()
	return {"ok": true}


func _handle_canvas_fill(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project := Global.current_project
	var frame := int(params.get("frame", project.current_frame))
	var layer := int(params.get("layer", project.current_layer))
	var cel := _get_pixel_cel(frame, layer)
	if cel == null:
		return _err("invalid_cel", "not a PixelCel")
	var color := _parse_color(params.get("color", null))
	cel.image.fill(color)
	cel.update_texture()
	return {"ok": true}


func _handle_canvas_clear(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project := Global.current_project
	var frame := int(params.get("frame", project.current_frame))
	var layer := int(params.get("layer", project.current_layer))
	var cel := _get_pixel_cel(frame, layer)
	if cel == null:
		return _err("invalid_cel", "not a PixelCel")
	cel.image.fill(Color.TRANSPARENT)
	cel.update_texture()
	return {"ok": true}


func _handle_canvas_resize(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var width := int(params.get("width", 0))
	var height := int(params.get("height", 0))
	if width <= 0 or height <= 0:
		return _err("invalid_size", "width/height must be > 0")
	var offset_x := int(params.get("offset_x", 0))
	var offset_y := int(params.get("offset_y", 0))
	DrawingAlgos.resize_canvas(width, height, offset_x, offset_y)
	return _project_info(Global.current_project)


func _handle_canvas_crop(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var x := int(params.get("x", 0))
	var y := int(params.get("y", 0))
	var width := int(params.get("width", 0))
	var height := int(params.get("height", 0))
	if width <= 0 or height <= 0:
		return _err("invalid_size", "width/height must be > 0")
	DrawingAlgos.resize_canvas(width, height, -x, -y)
	return _project_info(Global.current_project)


func _handle_palette_list() -> Dictionary:
	var items := []
	for name in Palettes.palettes.keys():
		items.append({"name": name, "scope": "global"})
	if Global.current_project:
		for name in Global.current_project.palettes.keys():
			items.append({"name": name, "scope": "project"})
	var current := ""
	if Palettes.current_palette:
		current = Palettes.current_palette.name
	return {"palettes": items, "current": current}


func _handle_palette_select(params: Dictionary) -> Dictionary:
	var name := str(params.get("name", ""))
	if name.is_empty():
		return _err("invalid_name", "name required")
	Palettes.select_palette(name)
	return {"current": Palettes.current_palette.name if Palettes.current_palette else ""}


func _handle_palette_create(params: Dictionary) -> Dictionary:
	var name := str(params.get("name", ""))
	if name.is_empty():
		return _err("invalid_name", "name required")
	var width := int(params.get("width", Palette.DEFAULT_WIDTH))
	var height := int(params.get("height", Palette.DEFAULT_HEIGHT))
	var is_global := bool(params.get("global", true))
	if Palettes.does_palette_exist(name):
		return _err("already_exists", "palette exists")
	var palette := Palette.new(name, width, height)
	if is_global:
		Palettes.palettes[palette.name] = palette
		Palettes.save_palette(palette)
	else:
		palette.is_project_palette = true
		if Global.current_project:
			Global.current_project.palettes[palette.name] = palette
	Palettes.select_palette(palette.name)
	return {"name": palette.name}


func _handle_palette_delete(params: Dictionary) -> Dictionary:
	var name := str(params.get("name", ""))
	if name.is_empty():
		return _err("invalid_name", "name required")
	var palette: Palette = null
	if Palettes.palettes.has(name):
		palette = Palettes.palettes[name]
	elif Global.current_project and Global.current_project.palettes.has(name):
		palette = Global.current_project.palettes[name]
	if palette == null:
		return _err("not_found", "palette not found")
	if palette.is_project_palette:
		Palettes.unparent_palette(palette)
	else:
		Palettes.palette_delete_and_reselect(true, palette)
	return {"deleted": name}


func _handle_draw_line(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var x1 := int(params.get("x1", 0))
	var y1 := int(params.get("y1", 0))
	var x2 := int(params.get("x2", 0))
	var y2 := int(params.get("y2", 0))
	var thickness := int(params.get("thickness", 1))
	var frame := int(params.get("frame", project.current_frame))
	var layer := int(params.get("layer", project.current_layer))
	var cel := _get_pixel_cel(frame, layer)
	if cel == null:
		return _err("invalid_cel", "not a PixelCel")
	var color := _parse_color(params.get("color", null))
	var points := Geometry2D.bresenham_line(Vector2i(x1, y1), Vector2i(x2, y2))
	_draw_points(cel.image, points, color, thickness)
	cel.update_texture()
	return {"ok": true}


func _handle_draw_erase_line(params: Dictionary) -> Dictionary:
	var p := params.duplicate()
	p["color"] = Color.TRANSPARENT
	return _handle_draw_line(p)


func _handle_draw_text(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var text := str(params.get("text", ""))
	if text.is_empty():
		return _err("invalid_text", "text is required")
	var x := int(params.get("x", 0))
	var y := int(params.get("y", 0))
	var frame := int(params.get("frame", project.current_frame))
	var layer := int(params.get("layer", project.current_layer))
	var cel := _get_pixel_cel(frame, layer)
	if cel == null:
		return _err("invalid_cel", "not a PixelCel")
	var font_name := str(params.get("font_name", "Roboto"))
	var size := int(params.get("size", 16))
	var align := str(params.get("align", "left")).to_lower()
	var antialias := bool(params.get("antialias", false))
	var color := _parse_color(params.get("color", null))
	var font := FontVariation.new()
	font.base_font = Global.find_font_from_name(font_name)
	if not is_instance_valid(font.base_font):
		font.base_font = Global.find_font_from_name("Roboto")
	font.base_font.antialiasing = (
		TextServer.FONT_ANTIALIASING_GRAY if antialias else TextServer.FONT_ANTIALIASING_NONE
	)
	var halign := HORIZONTAL_ALIGNMENT_LEFT
	if align == "center":
		halign = HORIZONTAL_ALIGNMENT_CENTER
	elif align == "right":
		halign = HORIZONTAL_ALIGNMENT_RIGHT
	var vp := RenderingServer.viewport_create()
	var canvas := RenderingServer.canvas_create()
	RenderingServer.viewport_attach_canvas(vp, canvas)
	RenderingServer.viewport_set_size(vp, project.size.x, project.size.y)
	RenderingServer.viewport_set_disable_3d(vp, true)
	RenderingServer.viewport_set_active(vp, true)
	RenderingServer.viewport_set_transparent_background(vp, true)
	RenderingServer.viewport_set_default_canvas_item_texture_filter(
		vp, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	)
	var ci_rid := RenderingServer.canvas_item_create()
	RenderingServer.viewport_set_canvas_transform(vp, canvas, Transform2D())
	RenderingServer.canvas_item_set_parent(ci_rid, canvas)
	var texture := RenderingServer.texture_2d_create(cel.image)
	RenderingServer.canvas_item_add_texture_rect(ci_rid, Rect2(Vector2.ZERO, project.size), texture)
	var font_ascent := font.get_ascent(size)
	var pos := Vector2(x, y + font_ascent)
	var width := int(params.get("width", project.size.x))
	font.draw_multiline_string(ci_rid, pos, text, halign, width, size, -1, color)
	RenderingServer.viewport_set_update_mode(vp, RenderingServer.VIEWPORT_UPDATE_ONCE)
	RenderingServer.force_draw(false)
	var viewport_texture := RenderingServer.texture_2d_get(RenderingServer.viewport_get_texture(vp))
	RenderingServer.free_rid(vp)
	RenderingServer.free_rid(canvas)
	RenderingServer.free_rid(ci_rid)
	RenderingServer.free_rid(texture)
	if not viewport_texture.is_empty():
		viewport_texture.convert(cel.image.get_format())
		cel.image.copy_from(viewport_texture)
		if cel.image is ImageExtended:
			cel.image.convert_rgb_to_indexed()
	cel.update_texture()
	return {"ok": true}


func _handle_draw_gradient(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var x := int(params.get("x", 0))
	var y := int(params.get("y", 0))
	var width := int(params.get("width", project.size.x))
	var height := int(params.get("height", project.size.y))
	if width <= 0 or height <= 0:
		return _err("invalid_size", "width/height must be > 0")
	var frame := int(params.get("frame", project.current_frame))
	var layer := int(params.get("layer", project.current_layer))
	var cel := _get_pixel_cel(frame, layer)
	if cel == null:
		return _err("invalid_cel", "not a PixelCel")
	var from_color := _parse_color(params.get("from", null))
	var to_color := _parse_color(params.get("to", null))
	var direction := str(params.get("direction", "horizontal")).to_lower()
	for yy in range(y, y + height):
		for xx in range(x, x + width):
			if xx < 0 or yy < 0 or xx >= project.size.x or yy >= project.size.y:
				continue
			var t := 0.0
			if direction == "vertical":
				t = float(yy - y) / float(max(1, height - 1))
			elif direction == "diagonal":
				var tx := float(xx - x) / float(max(1, width - 1))
				var ty := float(yy - y) / float(max(1, height - 1))
				t = (tx + ty) * 0.5
			else:
				t = float(xx - x) / float(max(1, width - 1))
			var c := from_color.lerp(to_color, t)
			cel.image.set_pixel(xx, yy, c)
	cel.update_texture()
	return {"ok": true}


func _handle_draw_rect(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var x := int(params.get("x", 0))
	var y := int(params.get("y", 0))
	var width := int(params.get("width", 0))
	var height := int(params.get("height", 0))
	var fill := bool(params.get("fill", false))
	var thickness := int(params.get("thickness", 1))
	var frame := int(params.get("frame", project.current_frame))
	var layer := int(params.get("layer", project.current_layer))
	var cel := _get_pixel_cel(frame, layer)
	if cel == null:
		return _err("invalid_cel", "not a PixelCel")
	var color := _parse_color(params.get("color", null))
	if width <= 0 or height <= 0:
		return _err("invalid_size", "width/height must be > 0")
	var rect := Rect2i(x, y, width, height)
	if fill:
		cel.image.fill_rect(rect, color)
	else:
		for i in range(thickness):
			_draw_line_on_image(cel.image, Vector2i(rect.position.x, rect.position.y + i), Vector2i(rect.position.x + rect.size.x - 1, rect.position.y + i), color, 1)
			_draw_line_on_image(cel.image, Vector2i(rect.position.x, rect.position.y + rect.size.y - 1 - i), Vector2i(rect.position.x + rect.size.x - 1, rect.position.y + rect.size.y - 1 - i), color, 1)
			_draw_line_on_image(cel.image, Vector2i(rect.position.x + i, rect.position.y), Vector2i(rect.position.x + i, rect.position.y + rect.size.y - 1), color, 1)
			_draw_line_on_image(cel.image, Vector2i(rect.position.x + rect.size.x - 1 - i, rect.position.y), Vector2i(rect.position.x + rect.size.x - 1 - i, rect.position.y + rect.size.y - 1), color, 1)
	cel.update_texture()
	return {"ok": true}


func _handle_draw_ellipse(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var x := int(params.get("x", 0))
	var y := int(params.get("y", 0))
	var width := int(params.get("width", 0))
	var height := int(params.get("height", 0))
	var fill := bool(params.get("fill", false))
	var thickness := int(params.get("thickness", 1))
	var frame := int(params.get("frame", project.current_frame))
	var layer := int(params.get("layer", project.current_layer))
	var cel := _get_pixel_cel(frame, layer)
	if cel == null:
		return _err("invalid_cel", "not a PixelCel")
	if width <= 0 or height <= 0:
		return _err("invalid_size", "width/height must be > 0")
	var color := _parse_color(params.get("color", null))
	var pos := Vector2i(x, y)
	var size := Vector2i(width, height)
	var points: Array[Vector2i] = []
	if fill:
		points = DrawingAlgos.get_ellipse_points_filled(pos, size, max(1, thickness))
	else:
		points = DrawingAlgos.get_ellipse_points(pos, size)
	_draw_points(cel.image, points, color, 1)
	cel.update_texture()
	return {"ok": true}


func _handle_pixel_replace_color(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var frame := int(params.get("frame", project.current_frame))
	var layer := int(params.get("layer", project.current_layer))
	var cel := _get_pixel_cel(frame, layer)
	if cel == null:
		return _err("invalid_cel", "not a PixelCel")
	var from_color := _parse_color(params.get("from", null))
	var to_color := _parse_color(params.get("to", null))
	var tolerance := float(params.get("tolerance", 0.0))
	var img := cel.image
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if _color_close(c, from_color, tolerance):
				img.set_pixel(x, y, to_color)
	cel.update_texture()
	return {"ok": true}


func _handle_selection_clear() -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	project.selection_map.clear()
	project.selection_offset = Vector2i.ZERO
	project.selection_map_changed()
	return {"ok": true}


func _handle_selection_invert() -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	project.selection_map.invert()
	project.selection_map_changed()
	return {"ok": true}


func _handle_selection_rect(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var x := int(params.get("x", 0))
	var y := int(params.get("y", 0))
	var width := int(params.get("width", 0))
	var height := int(params.get("height", 0))
	if width <= 0 or height <= 0:
		return _err("invalid_size", "width/height must be > 0")
	var mode := str(params.get("mode", "replace"))
	if mode == "replace":
		project.selection_map.clear()
	var rect := Rect2i(x, y, width, height)
	project.selection_map.select_rect(rect, mode != "subtract")
	project.selection_map_changed()
	return {"ok": true}


func _handle_selection_ellipse(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var x := int(params.get("x", 0))
	var y := int(params.get("y", 0))
	var width := int(params.get("width", 0))
	var height := int(params.get("height", 0))
	if width <= 0 or height <= 0:
		return _err("invalid_size", "width/height must be > 0")
	var mode := str(params.get("mode", "replace"))
	if mode == "replace":
		project.selection_map.clear()
	var points := DrawingAlgos.get_ellipse_points_filled(Vector2i(x, y), Vector2i(width, height), 1)
	for p in points:
		project.selection_map.select_pixel(p, mode != "subtract")
	project.selection_map_changed()
	return {"ok": true}


func _handle_selection_lasso(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var points_in: Array = params.get("points", [])
	if points_in.size() < 3:
		return _err("invalid_points", "need at least 3 points")
	var poly := PackedVector2Array()
	var min_x := 999999
	var min_y := 999999
	var max_x := -999999
	var max_y := -999999
	for p in points_in:
		if typeof(p) == TYPE_ARRAY and p.size() >= 2:
			var vx := int(p[0])
			var vy := int(p[1])
			poly.append(Vector2(vx, vy))
			min_x = mini(min_x, vx)
			min_y = mini(min_y, vy)
			max_x = maxi(max_x, vx)
			max_y = maxi(max_y, vy)
	var mode := str(params.get("mode", "replace"))
	if mode == "replace":
		project.selection_map.clear()
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly):
				project.selection_map.select_pixel(Vector2i(x, y), mode != "subtract")
	project.selection_map_changed()
	return {"ok": true}


func _handle_selection_move(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var dx := int(params.get("dx", 0))
	var dy := int(params.get("dy", 0))
	var sel := project.selection_map
	var rect := sel.get_used_rect()
	if rect.size == Vector2i.ZERO:
		return _err("no_selection", "selection is empty")
	var new_map := SelectionMap.new()
	new_map.copy_from(sel)
	new_map.clear()
	new_map.blit_rect(sel, rect, rect.position + Vector2i(dx, dy))
	project.selection_map.blit_rect_custom(new_map, Rect2i(Vector2i.ZERO, new_map.get_size()), Vector2i.ZERO)
	project.selection_offset = Vector2i.ZERO
	project.selection_map_changed()
	return {"ok": true}


func _handle_selection_export_mask(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var path := str(params.get("path", ""))
	if path.is_empty():
		return _err("path_required", "path is required")
	var err := Global.current_project.selection_map.save_png(path)
	if err != OK:
		return _err("export_failed", error_string(err))
	return {"path": path}


func _handle_symmetry_set(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	if params.has("show_x"):
		Global.show_x_symmetry_axis = bool(params.get("show_x"))
	if params.has("show_y"):
		Global.show_y_symmetry_axis = bool(params.get("show_y"))
	if params.has("show_xy"):
		Global.show_xy_symmetry_axis = bool(params.get("show_xy"))
	if params.has("show_x_minus_y"):
		Global.show_x_minus_y_symmetry_axis = bool(params.get("show_x_minus_y"))
	if params.has("x"):
		project.x_symmetry_point = float(params.get("x"))
		for point in project.y_symmetry_axis.points.size():
			project.y_symmetry_axis.points[point].x = floorf(project.x_symmetry_point / 2 + 1)
	if params.has("y"):
		project.y_symmetry_point = float(params.get("y"))
		for point in project.x_symmetry_axis.points.size():
			project.x_symmetry_axis.points[point].y = floorf(project.y_symmetry_point / 2 + 1)
	if params.has("xy"):
		var xy = params.get("xy")
		if typeof(xy) == TYPE_ARRAY and xy.size() >= 2:
			project.xy_symmetry_point = Vector2(float(xy[0]), float(xy[1]))
			project.x_minus_y_symmetry_point = project.xy_symmetry_point
			project.diagonal_xy_symmetry_axis.points[1] = (
				Vector2(-19999, 19999) + project.xy_symmetry_point * 2.0
			)
			project.diagonal_x_minus_y_symmetry_axis.points[1] = (
				Vector2(19999, 19999) + project.x_minus_y_symmetry_point * 2.0
			)
	return {"ok": true}


func _handle_batch_exec(params: Dictionary) -> Dictionary:
	var calls_raw: Variant = params.get("calls", [])
	if typeof(calls_raw) != TYPE_ARRAY:
		return _err("invalid_params", "calls must be array")
	var calls: Array = calls_raw
	var results: Array = []
	for item in calls:
		if typeof(item) != TYPE_DICTIONARY:
			results.append({"ok": false, "error": {"code": "invalid_item", "message": "call must be object"}})
			continue
		var item_dict: Dictionary = item
		var method := str(item_dict.get("method", ""))
		var sub_params: Dictionary = {}
		var raw_params = item_dict.get("params", {})
		if typeof(raw_params) == TYPE_DICTIONARY:
			sub_params = raw_params
		var res := _dispatch_method(method, sub_params, false)
		if res.has("_error"):
			results.append({"ok": false, "error": res["_error"]})
		else:
			results.append({"ok": true, "result": res})
	return {"results": results}


func _handle_project_import_sequence(params: Dictionary) -> Dictionary:
	var paths_raw: Variant = params.get("paths", [])
	if typeof(paths_raw) != TYPE_ARRAY:
		return _err("invalid_params", "paths must be array")
	var paths: Array = paths_raw
	if paths.is_empty():
		return _err("invalid_params", "paths required")
	var mode := str(params.get("mode", "new_project")).to_lower()
	var layer_index := int(params.get("layer", 0))
	var fps := float(params.get("fps", 0.0))
	var durations_ms_raw: Variant = params.get("durations_ms", [])
	var durations_ms: Array = []
	if typeof(durations_ms_raw) == TYPE_ARRAY:
		durations_ms = durations_ms_raw

	var first_path := str(paths[0])
	var first_image := Image.new()
	var err := first_image.load(first_path)
	if err != OK:
		return _err("load_failed", error_string(err))

	if mode == "append_frames":
		if not _require_project():
			return _err("no_project", "no current project")
		var project: Project = Global.current_project
		layer_index = clampi(layer_index, 0, project.layers.size() - 1)
		for p in paths:
			var path := str(p)
			var image := Image.new()
			var load_err := image.load(path)
			if load_err != OK:
				return _err("load_failed", error_string(load_err))
			OpenSave.open_image_as_new_frame(image, layer_index, project, false)
		if fps > 0.0:
			project.fps = fps
		if durations_ms.size() > 0:
			for i in range(mini(durations_ms.size(), project.frames.size())):
				var ms := float(durations_ms[i])
				project.frames[i].set_duration_in_seconds(ms / 1000.0, project.fps)
		return _project_info(project)

	if mode == "new_project":
		OpenSave.open_image_as_new_tab(first_path, first_image)
		if not _require_project():
			return _err("no_project", "import failed")
		var new_project: Project = Global.current_project
		for i in range(1, paths.size()):
			var path := str(paths[i])
			var image := Image.new()
			var load_err := image.load(path)
			if load_err != OK:
				return _err("load_failed", error_string(load_err))
			OpenSave.open_image_as_new_frame(image, 0, new_project, false)
		if fps > 0.0:
			new_project.fps = fps
		if durations_ms.size() > 0:
			for i in range(mini(durations_ms.size(), new_project.frames.size())):
				var ms := float(durations_ms[i])
				new_project.frames[i].set_duration_in_seconds(ms / 1000.0, new_project.fps)
		return _project_info(new_project)

	return _err("invalid_mode", "mode must be new_project or append_frames")


func _handle_project_import_spritesheet(params: Dictionary) -> Dictionary:
	var path := str(params.get("path", ""))
	if path.is_empty():
		return _err("path_required", "path is required")
	var image := Image.new()
	var err := image.load(path)
	if err != OK:
		return _err("load_failed", error_string(err))
	var horiz := int(params.get("horizontal", 1))
	var vert := int(params.get("vertical", 1))
	if horiz <= 0 or vert <= 0:
		return _err("invalid_size", "horizontal/vertical must be > 0")
	var detect_empty := bool(params.get("detect_empty", true))
	var mode := str(params.get("mode", "new_project")).to_lower()
	if mode == "new_project":
		OpenSave.open_image_as_spritesheet_tab(path, image, horiz, vert, detect_empty)
		return _project_info(Global.current_project)
	if mode == "new_layer":
		if not _require_project():
			return _err("no_project", "no current project")
		var file_name := str(params.get("name", path.get_file()))
		var start_frame := int(params.get("start_frame", 0))
		OpenSave.open_image_as_spritesheet_layer(
			path, image, file_name, start_frame, horiz, vert, detect_empty
		)
		return _project_info(Global.current_project)
	return _err("invalid_mode", "mode must be new_project or new_layer")


func _handle_pixel_set_many(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var points_raw: Variant = params.get("points", [])
	if typeof(points_raw) != TYPE_ARRAY:
		return _err("invalid_params", "points must be array")
	var frame := int(params.get("frame", project.current_frame))
	var layer := int(params.get("layer", project.current_layer))
	var cel := _get_pixel_cel(frame, layer)
	if cel == null:
		return _err("invalid_cel", "not a PixelCel")
	var default_color := _parse_color(params.get("color", null))
	var points: Array = points_raw
	var count := 0
	for item in points:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = item
		var x := int(p.get("x", -1))
		var y := int(p.get("y", -1))
		if x < 0 or y < 0 or x >= project.size.x or y >= project.size.y:
			continue
		var color := default_color
		if p.has("color"):
			color = _parse_color(p.get("color", null))
		cel.image.set_pixel(x, y, color)
		count += 1
	cel.update_texture()
	return {"count": count}


func _handle_pixel_get_region(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var x := int(params.get("x", 0))
	var y := int(params.get("y", 0))
	var width := int(params.get("width", project.size.x))
	var height := int(params.get("height", project.size.y))
	var frame := int(params.get("frame", project.current_frame))
	var layer := int(params.get("layer", project.current_layer))
	if width <= 0 or height <= 0:
		return _err("invalid_size", "width/height must be > 0")
	if x < 0 or y < 0 or x + width > project.size.x or y + height > project.size.y:
		return _err("out_of_bounds", "region out of bounds")
	var cel := _get_pixel_cel(frame, layer)
	if cel == null:
		return _err("invalid_cel", "not a PixelCel")
	var rect := Rect2i(x, y, width, height)
	var region := cel.image.get_region(rect)
	var fmt := str(params.get("format", "png")).to_lower()
	if fmt == "raw":
		region.convert(Image.FORMAT_RGBA8)
		var raw: PackedByteArray = region.get_data()
		var b64 := Marshalls.raw_to_base64(raw)
		return {
			"format": "raw",
			"width": region.get_width(),
			"height": region.get_height(),
			"image_format": Image.FORMAT_RGBA8,
			"data": b64
		}
	var png: PackedByteArray = region.save_png_to_buffer()
	var b64png := Marshalls.raw_to_base64(png)
	return {
		"format": "png",
		"width": region.get_width(),
		"height": region.get_height(),
		"data": b64png
	}


func _handle_pixel_set_region(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var x := int(params.get("x", 0))
	var y := int(params.get("y", 0))
	var frame := int(params.get("frame", project.current_frame))
	var layer := int(params.get("layer", project.current_layer))
	var cel := _get_pixel_cel(frame, layer)
	if cel == null:
		return _err("invalid_cel", "not a PixelCel")
	var data_str := str(params.get("data", ""))
	if data_str.is_empty():
		return _err("invalid_params", "data required")
	var fmt := str(params.get("format", "png")).to_lower()
	var raw := Marshalls.base64_to_raw(data_str)
	var image := Image.new()
	if fmt == "raw":
		var width := int(params.get("width", 0))
		var height := int(params.get("height", 0))
		if width <= 0 or height <= 0:
			return _err("invalid_size", "width/height required for raw")
		image = Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, raw)
	else:
		var err := image.load_png_from_buffer(raw)
		if err != OK:
			return _err("decode_failed", error_string(err))
	var mode := str(params.get("mode", "blit")).to_lower()
	if mode == "replace":
		cel.image.fill(Color.TRANSPARENT)
		x = 0
		y = 0
	cel.image.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(x, y))
	if cel is CelTileMap:
		(cel as CelTileMap).update_tilemap()
	cel.update_texture()
	return {"ok": true, "width": image.get_width(), "height": image.get_height()}


func _handle_animation_tags_list() -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var items := []
	for i in project.animation_tags.size():
		var tag := project.animation_tags[i]
		items.append(
			{
				"index": i,
				"name": tag.name,
				"color": _color_to_array(tag.color),
				"from": tag.from,
				"to": tag.to,
				"user_data": tag.user_data
			}
		)
	return {"tags": items}


func _handle_animation_tags_add(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var name := str(params.get("name", ""))
	if name.is_empty():
		return _err("invalid_name", "name required")
	var from_frame := int(params.get("from", 1))
	var to_frame := int(params.get("to", from_frame))
	from_frame = clampi(from_frame, 1, project.frames.size())
	to_frame = clampi(to_frame, 1, project.frames.size())
	if to_frame < from_frame:
		var tmp := to_frame
		to_frame = from_frame
		from_frame = tmp
	var color := _parse_color(params.get("color", null))
	var user_data := str(params.get("user_data", ""))
	var new_tags: Array[AnimationTag] = []
	for t in project.animation_tags:
		new_tags.append(t.duplicate())
	new_tags.append(AnimationTag.new(name, color, from_frame, to_frame))
	new_tags[-1].user_data = user_data
	project.animation_tags = new_tags
	return _handle_animation_tags_list()


func _handle_animation_tags_update(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var index := int(params.get("index", -1))
	var name := str(params.get("name", ""))
	var target_idx := index
	if target_idx < 0 and not name.is_empty():
		for i in project.animation_tags.size():
			if project.animation_tags[i].name == name:
				target_idx = i
				break
	if target_idx < 0 or target_idx >= project.animation_tags.size():
		return _err("invalid_index", "tag not found")
	var new_tags: Array[AnimationTag] = []
	for t in project.animation_tags:
		new_tags.append(t.duplicate())
	var tag := new_tags[target_idx]
	if params.has("new_name"):
		tag.name = str(params.get("new_name", tag.name))
	if params.has("color"):
		tag.color = _parse_color(params.get("color", null))
	if params.has("from"):
		tag.from = clampi(int(params.get("from", tag.from)), 1, project.frames.size())
	if params.has("to"):
		tag.to = clampi(int(params.get("to", tag.to)), 1, project.frames.size())
	if tag.to < tag.from:
		var tmp := tag.to
		tag.to = tag.from
		tag.from = tmp
	if params.has("user_data"):
		tag.user_data = str(params.get("user_data", tag.user_data))
	project.animation_tags = new_tags
	return _handle_animation_tags_list()


func _handle_animation_tags_remove(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var index := int(params.get("index", -1))
	var name := str(params.get("name", ""))
	var target_idx := index
	if target_idx < 0 and not name.is_empty():
		for i in project.animation_tags.size():
			if project.animation_tags[i].name == name:
				target_idx = i
				break
	if target_idx < 0 or target_idx >= project.animation_tags.size():
		return _err("invalid_index", "tag not found")
	var new_tags: Array[AnimationTag] = []
	for t in project.animation_tags:
		new_tags.append(t.duplicate())
	new_tags.remove_at(target_idx)
	project.animation_tags = new_tags
	return _handle_animation_tags_list()


func _handle_animation_playback_set(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var enabled := bool(params.get("play_only_tags", true))
	Global.play_only_tags = enabled
	if params.has("tag"):
		var tag_name := str(params.get("tag", ""))
		if not tag_name.is_empty():
			for tag in Global.current_project.animation_tags:
				if tag.name == tag_name:
					Global.current_project.change_cel(tag.from - 1, Global.current_project.current_layer)
					break
	return {"play_only_tags": Global.play_only_tags}


func _handle_animation_fps_get() -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	return {"fps": Global.current_project.fps}


func _handle_animation_fps_set(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var fps := float(params.get("fps", 0.0))
	if fps <= 0.0:
		return _err("invalid_fps", "fps must be > 0")
	Global.current_project.fps = fps
	return {"fps": Global.current_project.fps}


func _handle_animation_frame_duration_set(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	if params.has("durations_ms") and typeof(params.get("durations_ms")) == TYPE_ARRAY:
		var durations: Array = params.get("durations_ms")
		for i in range(mini(durations.size(), project.frames.size())):
			var ms := float(durations[i])
			project.frames[i].set_duration_in_seconds(ms / 1000.0, project.fps)
		return {"ok": true}
	var frame := int(params.get("frame", project.current_frame))
	if frame < 0 or frame >= project.frames.size():
		return _err("invalid_index", "frame index out of range")
	var duration_ms := float(params.get("duration_ms", 0.0))
	if duration_ms <= 0.0:
		return _err("invalid_duration", "duration_ms must be > 0")
	project.frames[frame].set_duration_in_seconds(duration_ms / 1000.0, project.fps)
	return {"ok": true}


func _handle_animation_loop_set(params: Dictionary) -> Dictionary:
	var mode := str(params.get("mode", "cycle")).to_lower()
	if Global.animation_timeline:
		if mode == "pingpong":
			Global.animation_timeline.animation_loop = Global.animation_timeline.LoopType.PINGPONG
		elif mode == "none":
			Global.animation_timeline.animation_loop = Global.animation_timeline.LoopType.NO
		else:
			Global.animation_timeline.animation_loop = Global.animation_timeline.LoopType.CYCLE
	return {"mode": mode}


func _handle_tilemap_tileset_list() -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var items := []
	for i in project.tilesets.size():
		var tileset := project.tilesets[i]
		items.append(
			{
				"index": i,
				"name": tileset.name,
				"tile_size": [tileset.tile_size.x, tileset.tile_size.y],
				"tile_shape": tileset.tile_shape,
				"tile_count": tileset.tiles.size()
			}
		)
	return {"tilesets": items}


func _handle_tilemap_tileset_create(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var size_raw: Variant = params.get("tile_size", [])
	if typeof(size_raw) != TYPE_ARRAY:
		return _err("invalid_params", "tile_size must be array")
	var size_arr: Array = size_raw
	if size_arr.size() < 2:
		return _err("invalid_params", "tile_size must have 2 values")
	var tile_size := Vector2i(int(size_arr[0]), int(size_arr[1]))
	if tile_size.x <= 0 or tile_size.y <= 0:
		return _err("invalid_size", "tile_size must be > 0")
	var name := str(params.get("name", ""))
	var tile_shape := _parse_tile_shape(params.get("tile_shape", null))
	if tile_shape < 0:
		tile_shape = TileSet.TILE_SHAPE_SQUARE
	var add_empty := bool(params.get("add_empty_tile", true))
	var tileset := TileSetCustom.new(tile_size, name, tile_shape, add_empty)
	Global.current_project.add_tileset(tileset)
	return _handle_tilemap_tileset_list()


func _handle_tilemap_tileset_add_tile(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var idx := int(params.get("tileset_index", -1))
	if idx < 0 or idx >= project.tilesets.size():
		return _err("invalid_index", "tileset index out of range")
	var path := str(params.get("path", ""))
	if path.is_empty():
		return _err("path_required", "path is required")
	var image := Image.new()
	var err := image.load(path)
	if err != OK:
		return _err("load_failed", error_string(err))
	var tileset := project.tilesets[idx]
	if image.get_size() != tileset.tile_size:
		var resized := DrawingAlgos.resize_image(
			image, tileset.tile_size.x, tileset.tile_size.y, Image.INTERPOLATE_NEAREST
		)
		image = resized
	var cel: CelTileMap = null
	if params.has("layer"):
		var layer_idx := int(params.get("layer", project.current_layer))
		var frame_idx := int(params.get("frame", project.current_frame))
		cel = _get_tilemap_cel(frame_idx, layer_idx)
	tileset.add_tile(image, cel, int(params.get("times_used", 1)))
	return {"tile_index": tileset.tiles.size() - 1}


func _handle_tilemap_tileset_remove_tile(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var tileset_index := int(params.get("tileset_index", -1))
	if tileset_index < 0 or tileset_index >= project.tilesets.size():
		return _err("invalid_index", "tileset index out of range")
	var tile_index := int(params.get("tile_index", -1))
	if tile_index <= 0 or tile_index >= project.tilesets[tileset_index].tiles.size():
		return _err("invalid_index", "tile index out of range")
	var cel: CelTileMap = null
	if params.has("layer"):
		var layer_idx := int(params.get("layer", project.current_layer))
		var frame_idx := int(params.get("frame", project.current_frame))
		cel = _get_tilemap_cel(frame_idx, layer_idx)
	project.tilesets[tileset_index].remove_tile_at_index(tile_index, cel)
	return _handle_tilemap_tileset_list()


func _handle_tilemap_tileset_replace_tile(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var tileset_index := int(params.get("tileset_index", -1))
	if tileset_index < 0 or tileset_index >= project.tilesets.size():
		return _err("invalid_index", "tileset index out of range")
	var tile_index := int(params.get("tile_index", -1))
	if tile_index < 0 or tile_index >= project.tilesets[tileset_index].tiles.size():
		return _err("invalid_index", "tile index out of range")
	var path := str(params.get("path", ""))
	if path.is_empty():
		return _err("path_required", "path is required")
	var image := Image.new()
	var err := image.load(path)
	if err != OK:
		return _err("load_failed", error_string(err))
	var tileset := project.tilesets[tileset_index]
	if image.get_size() != tileset.tile_size:
		var resized := DrawingAlgos.resize_image(
			image, tileset.tile_size.x, tileset.tile_size.y, Image.INTERPOLATE_NEAREST
		)
		image = resized
	var cel: CelTileMap = null
	if params.has("layer"):
		var layer_idx := int(params.get("layer", project.current_layer))
		var frame_idx := int(params.get("frame", project.current_frame))
		cel = _get_tilemap_cel(frame_idx, layer_idx)
	tileset.replace_tile_at(image, tile_index, cel)
	return {"tile_index": tile_index}


func _handle_tilemap_layer_set_tileset(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var layer_idx := int(params.get("layer", project.current_layer))
	var tileset_index := int(params.get("tileset_index", -1))
	if layer_idx < 0 or layer_idx >= project.layers.size():
		return _err("invalid_index", "layer index out of range")
	if tileset_index < 0 or tileset_index >= project.tilesets.size():
		return _err("invalid_index", "tileset index out of range")
	var layer := project.layers[layer_idx]
	if layer is not LayerTileMap:
		return _err("invalid_layer", "layer is not tilemap")
	var tileset := project.tilesets[tileset_index]
	(layer as LayerTileMap).set_tileset(tileset)
	for f in project.frames.size():
		var cel := project.frames[f].cels[layer_idx]
		if cel is CelTileMap:
			(cel as CelTileMap).set_tileset(tileset, true)
	return {"ok": true}


func _handle_tilemap_layer_set_params(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var layer_idx := int(params.get("layer", project.current_layer))
	if layer_idx < 0 or layer_idx >= project.layers.size():
		return _err("invalid_index", "layer index out of range")
	var layer := project.layers[layer_idx]
	if layer is not LayerTileMap:
		return _err("invalid_layer", "layer is not tilemap")
	var tilemap := layer as LayerTileMap
	if params.has("place_only_mode"):
		tilemap.place_only_mode = bool(params.get("place_only_mode", tilemap.place_only_mode))
	if params.has("tile_size"):
		var size_raw: Variant = params.get("tile_size", [])
		if typeof(size_raw) == TYPE_ARRAY:
			var size_arr: Array = size_raw
			if size_arr.size() >= 2:
				tilemap.tile_size = Vector2i(int(size_arr[0]), int(size_arr[1]))
	if params.has("tile_shape"):
		var shape := _parse_tile_shape(params.get("tile_shape", null))
		if shape >= 0:
			tilemap.tile_shape = shape
	if params.has("tile_layout"):
		var layout := _parse_tile_layout(params.get("tile_layout", null))
		if layout >= 0:
			tilemap.tile_layout = layout
	if params.has("tile_offset_axis"):
		var axis := _parse_tile_offset_axis(params.get("tile_offset_axis", null))
		if axis >= 0:
			tilemap.tile_offset_axis = axis
	for f in project.frames.size():
		var cel := project.frames[f].cels[layer_idx]
		if cel is CelTileMap:
			tilemap.pass_variables_to_cel(cel)
	return {"ok": true}


func _handle_tilemap_offset_set(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var layer_idx := int(params.get("layer", project.current_layer))
	var frame_idx := int(params.get("frame", project.current_frame))
	var x := int(params.get("x", 0))
	var y := int(params.get("y", 0))
	var cel := _get_tilemap_cel(frame_idx, layer_idx)
	if cel == null:
		return _err("invalid_cel", "not a CelTileMap")
	cel.change_offset(Vector2i(x, y))
	return {"ok": true}


func _handle_tilemap_cell_get(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var layer_idx := int(params.get("layer", project.current_layer))
	var frame_idx := int(params.get("frame", project.current_frame))
	var cell_x := int(params.get("cell_x", 0))
	var cell_y := int(params.get("cell_y", 0))
	var cel := _get_tilemap_cel(frame_idx, layer_idx)
	if cel == null:
		return _err("invalid_cel", "not a CelTileMap")
	var cell := cel.get_cell_at(Vector2i(cell_x, cell_y))
	return {"index": cell.index, "flip_h": cell.flip_h, "flip_v": cell.flip_v, "transpose": cell.transpose}


func _handle_tilemap_cell_set(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var layer_idx := int(params.get("layer", project.current_layer))
	var frame_idx := int(params.get("frame", project.current_frame))
	var cell_x := int(params.get("cell_x", 0))
	var cell_y := int(params.get("cell_y", 0))
	var index := int(params.get("index", 0))
	var flip_h := bool(params.get("flip_h", false))
	var flip_v := bool(params.get("flip_v", false))
	var transpose := bool(params.get("transpose", false))
	var cel := _get_tilemap_cel(frame_idx, layer_idx)
	if cel == null:
		return _err("invalid_cel", "not a CelTileMap")
	var cell := cel.get_cell_at(Vector2i(cell_x, cell_y))
	cel.set_index(cell, index, flip_h, flip_v, transpose)
	return {"ok": true}


func _handle_tilemap_cell_clear(params: Dictionary) -> Dictionary:
	params["index"] = 0
	params["flip_h"] = false
	params["flip_v"] = false
	params["transpose"] = false
	return _handle_tilemap_cell_set(params)


func _handle_tilemap_fill_rect(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var layer_idx := int(params.get("layer", project.current_layer))
	var frame_idx := int(params.get("frame", project.current_frame))
	var cell_x := int(params.get("cell_x", 0))
	var cell_y := int(params.get("cell_y", 0))
	var width := int(params.get("width", 1))
	var height := int(params.get("height", 1))
	var index := int(params.get("index", 0))
	var flip_h := bool(params.get("flip_h", false))
	var flip_v := bool(params.get("flip_v", false))
	var transpose := bool(params.get("transpose", false))
	if width <= 0 or height <= 0:
		return _err("invalid_size", "width/height must be > 0")
	var cel := _get_tilemap_cel(frame_idx, layer_idx)
	if cel == null:
		return _err("invalid_cel", "not a CelTileMap")
	for yy in range(cell_y, cell_y + height):
		for xx in range(cell_x, cell_x + width):
			var cell := cel.get_cell_at(Vector2i(xx, yy))
			cel.set_index(cell, index, flip_h, flip_v, transpose)
	return {"ok": true}


func _handle_tilemap_replace_index(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var layer_idx := int(params.get("layer", project.current_layer))
	var frame_idx := int(params.get("frame", project.current_frame))
	var from_idx := int(params.get("from", 0))
	var to_idx := int(params.get("to", 0))
	var cel := _get_tilemap_cel(frame_idx, layer_idx)
	if cel == null:
		return _err("invalid_cel", "not a CelTileMap")
	var count := 0
	for key in cel.cells.keys():
		var cell := cel.cells[key]
		if cell.index == from_idx:
			cel.set_index(cell, to_idx, cell.flip_h, cell.flip_v, cell.transpose)
			count += 1
	return {"count": count}


func _handle_tilemap_random_fill(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var layer_idx := int(params.get("layer", project.current_layer))
	var frame_idx := int(params.get("frame", project.current_frame))
	var cell_x := int(params.get("cell_x", 0))
	var cell_y := int(params.get("cell_y", 0))
	var width := int(params.get("width", 1))
	var height := int(params.get("height", 1))
	var indices_raw: Variant = params.get("indices", [])
	if typeof(indices_raw) != TYPE_ARRAY:
		return _err("invalid_params", "indices must be array")
	var indices: Array = indices_raw
	if indices.is_empty():
		return _err("invalid_params", "indices required")
	var weights: Array = []
	if params.has("weights") and typeof(params.get("weights")) == TYPE_ARRAY:
		weights = params.get("weights")
	if width <= 0 or height <= 0:
		return _err("invalid_size", "width/height must be > 0")
	var cel := _get_tilemap_cel(frame_idx, layer_idx)
	if cel == null:
		return _err("invalid_cel", "not a CelTileMap")
	for yy in range(cell_y, cell_y + height):
		for xx in range(cell_x, cell_x + width):
			var idx := _pick_weighted_index(indices, weights)
			var cell := cel.get_cell_at(Vector2i(xx, yy))
			cel.set_index(cell, idx, false, false, false)
	return {"ok": true}


func _handle_effect_layer_list(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var layer_idx := int(params.get("layer", project.current_layer))
	if layer_idx < 0 or layer_idx >= project.layers.size():
		return _err("invalid_index", "layer index out of range")
	var layer := project.layers[layer_idx]
	var items := []
	for i in layer.effects.size():
		var effect := layer.effects[i]
		var shader_path := ""
		if is_instance_valid(effect.shader):
			shader_path = effect.shader.resource_path
		items.append(
			{
				"index": i,
				"name": effect.name,
				"shader_path": shader_path,
				"enabled": effect.enabled,
				"params": _serialize_effect_params(effect.params)
			}
		)
	return {"layer": layer_idx, "effects": items, "effects_enabled": layer.effects_enabled}


func _handle_effect_layer_add(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var layer_idx := int(params.get("layer", project.current_layer))
	if layer_idx < 0 or layer_idx >= project.layers.size():
		return _err("invalid_index", "layer index out of range")
	var shader_path := str(params.get("shader_path", ""))
	if shader_path.is_empty():
		return _err("invalid_params", "shader_path required")
	var shader_res := load(shader_path)
	if not is_instance_valid(shader_res) or shader_res is not Shader:
		return _err("invalid_shader", "shader not found")
	var name := str(params.get("name", shader_path.get_file().get_basename()))
	var category := str(params.get("category", ""))
	var effect := LayerEffect.new(name, shader_res, category, {})
	if params.has("params") and typeof(params.get("params")) == TYPE_DICTIONARY:
		effect.params = params.get("params")
	effect.enabled = bool(params.get("enabled", true))
	project.layers[layer_idx].effects.append(effect)
	project.layers[layer_idx].emit_effects_added_removed()
	return _handle_effect_layer_list({"layer": layer_idx})


func _handle_effect_layer_remove(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var layer_idx := int(params.get("layer", project.current_layer))
	var index := int(params.get("index", -1))
	if layer_idx < 0 or layer_idx >= project.layers.size():
		return _err("invalid_index", "layer index out of range")
	if index < 0 or index >= project.layers[layer_idx].effects.size():
		return _err("invalid_index", "effect index out of range")
	project.layers[layer_idx].effects.remove_at(index)
	project.layers[layer_idx].emit_effects_added_removed()
	return _handle_effect_layer_list({"layer": layer_idx})


func _handle_effect_layer_move(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var layer_idx := int(params.get("layer", project.current_layer))
	var from_idx := int(params.get("from", -1))
	var to_idx := int(params.get("to", -1))
	if layer_idx < 0 or layer_idx >= project.layers.size():
		return _err("invalid_index", "layer index out of range")
	var effects: Array[LayerEffect] = project.layers[layer_idx].effects
	if from_idx < 0 or from_idx >= effects.size():
		return _err("invalid_index", "from out of range")
	if to_idx < 0 or to_idx >= effects.size():
		return _err("invalid_index", "to out of range")
	var eff: LayerEffect = effects.pop_at(from_idx)
	effects.insert(to_idx, eff)
	project.layers[layer_idx].emit_effects_added_removed()
	return _handle_effect_layer_list({"layer": layer_idx})


func _handle_effect_layer_set_enabled(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var layer_idx := int(params.get("layer", project.current_layer))
	var index := int(params.get("index", -1))
	var enabled := bool(params.get("enabled", true))
	if layer_idx < 0 or layer_idx >= project.layers.size():
		return _err("invalid_index", "layer index out of range")
	if index < 0 or index >= project.layers[layer_idx].effects.size():
		return _err("invalid_index", "effect index out of range")
	project.layers[layer_idx].effects[index].enabled = enabled
	project.layers[layer_idx].emit_effects_added_removed()
	return _handle_effect_layer_list({"layer": layer_idx})


func _handle_effect_layer_set_params(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var layer_idx := int(params.get("layer", project.current_layer))
	var index := int(params.get("index", -1))
	if layer_idx < 0 or layer_idx >= project.layers.size():
		return _err("invalid_index", "layer index out of range")
	if index < 0 or index >= project.layers[layer_idx].effects.size():
		return _err("invalid_index", "effect index out of range")
	var effect := project.layers[layer_idx].effects[index]
	if params.has("params") and typeof(params.get("params")) == TYPE_DICTIONARY:
		var new_params: Dictionary = effect.params.duplicate()
		for key in params.get("params"):
			new_params[key] = params.get("params")[key]
		effect.params = new_params
	project.layers[layer_idx].emit_effects_added_removed()
	return _handle_effect_layer_list({"layer": layer_idx})


func _handle_effect_layer_apply(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var layer_idx := int(params.get("layer", project.current_layer))
	var frame_idx := int(params.get("frame", project.current_frame))
	var index := int(params.get("index", -1))
	if layer_idx < 0 or layer_idx >= project.layers.size():
		return _err("invalid_index", "layer index out of range")
	if index < 0 or index >= project.layers[layer_idx].effects.size():
		return _err("invalid_index", "effect index out of range")
	var layer := project.layers[layer_idx]
	var effect := layer.effects[index]
	var cel := project.frames[frame_idx].cels[layer_idx]
	if cel is not PixelCel:
		return _err("invalid_cel", "not a PixelCel")
	if not is_instance_valid(effect.shader):
		return _err("invalid_shader", "shader not valid")
	var gen := ShaderImageEffect.new()
	gen.generate_image((cel as PixelCel).get_image(), effect.shader, effect.params, project.size)
	if cel is CelTileMap:
		(cel as CelTileMap).update_tilemap()
	cel.update_texture()
	if bool(params.get("remove_after", true)):
		layer.effects.remove_at(index)
		layer.emit_effects_added_removed()
	return {"ok": true}


func _handle_effect_shader_apply(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var layer_idx := int(params.get("layer", project.current_layer))
	var frame_idx := int(params.get("frame", project.current_frame))
	var shader_path := str(params.get("shader_path", ""))
	if shader_path.is_empty():
		return _err("invalid_params", "shader_path required")
	var shader_res := load(shader_path)
	if not is_instance_valid(shader_res) or shader_res is not Shader:
		return _err("invalid_shader", "shader not found")
	var cel := project.frames[frame_idx].cels[layer_idx]
	if cel is not PixelCel:
		return _err("invalid_cel", "not a PixelCel")
	var params_dict := {}
	if params.has("params") and typeof(params.get("params")) == TYPE_DICTIONARY:
		params_dict = params.get("params")
	var gen := ShaderImageEffect.new()
	gen.generate_image((cel as PixelCel).get_image(), shader_res, params_dict, project.size)
	if cel is CelTileMap:
		(cel as CelTileMap).update_tilemap()
	cel.update_texture()
	return {"ok": true}


func _handle_effect_shader_list() -> Dictionary:
	var dir := DirAccess.open("res://src/Shaders/Effects")
	if dir == null:
		return _err("not_found", "effects directory not found")
	var items := []
	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir():
			continue
		if file_name.to_lower().ends_with(".gdshader"):
			items.append("res://src/Shaders/Effects/" + file_name)
	dir.list_dir_end()
	return {"shaders": items}


func _handle_effect_shader_inspect(params: Dictionary) -> Dictionary:
	var path := str(params.get("shader_path", ""))
	if path.is_empty():
		return _err("invalid_params", "shader_path required")
	var shader := load(path)
	if not is_instance_valid(shader) or shader is not Shader:
		return _err("invalid_shader", "shader not found")
	var uniforms: Array = shader.get_uniform_list()
	return {"shader_path": path, "uniforms": uniforms}


func _handle_history_undo() -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	Global.undo_or_redo(true)
	return {"ok": true}


func _handle_history_redo() -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	Global.undo_or_redo(false)
	return {"ok": true}


func _handle_brush_list() -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var items := []
	for i in project.brushes.size():
		var brush: Image = project.brushes[i]
		items.append({"index": i, "size": [brush.get_width(), brush.get_height()]})
	return {"brushes": items}


func _handle_brush_add(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var path := str(params.get("path", ""))
	var data_str := str(params.get("data", ""))
	var image := Image.new()
	if not path.is_empty():
		var err := image.load(path)
		if err != OK:
			return _err("load_failed", error_string(err))
	elif not data_str.is_empty():
		var raw := Marshalls.base64_to_raw(data_str)
		var err2 := image.load_png_from_buffer(raw)
		if err2 != OK:
			return _err("decode_failed", error_string(err2))
	else:
		return _err("invalid_params", "path or data required")
	image.convert(Image.FORMAT_RGBA8)
	project.brushes.append(image)
	Brushes.add_project_brush(image)
	return _handle_brush_list()


func _handle_brush_remove(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var index := int(params.get("index", -1))
	if index < 0 or index >= project.brushes.size():
		return _err("invalid_index", "brush index out of range")
	project.brushes.remove_at(index)
	Brushes.clear_project_brush()
	for b in project.brushes:
		Brushes.add_project_brush(b)
	return _handle_brush_list()


func _handle_brush_clear() -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	project.brushes.clear()
	Brushes.clear_project_brush()
	return {"ok": true}


func _handle_brush_stamp(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var x := int(params.get("x", 0))
	var y := int(params.get("y", 0))
	var frame := int(params.get("frame", project.current_frame))
	var layer := int(params.get("layer", project.current_layer))
	var cel := _get_pixel_cel(frame, layer)
	if cel == null:
		return _err("invalid_cel", "not a PixelCel")
	var brush := _build_brush_image(params)
	if brush == null:
		return _err("invalid_brush", "brush not found")
	var color := _parse_color(params.get("color", null))
	var opacity := float(params.get("opacity", 1.0))
	_apply_brush(cel.image, brush, Vector2i(x, y), color, opacity, str(params.get("mode", "paint")))
	cel.update_texture()
	return {"ok": true}


func _handle_brush_stroke(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var points_raw: Variant = params.get("points", [])
	if typeof(points_raw) != TYPE_ARRAY:
		return _err("invalid_params", "points must be array")
	var points: Array = points_raw
	if points.size() < 2:
		return _err("invalid_params", "points must have >= 2")
	var frame := int(params.get("frame", project.current_frame))
	var layer := int(params.get("layer", project.current_layer))
	var cel := _get_pixel_cel(frame, layer)
	if cel == null:
		return _err("invalid_cel", "not a PixelCel")
	var brush := _build_brush_image(params)
	if brush == null:
		return _err("invalid_brush", "brush not found")
	var color := _parse_color(params.get("color", null))
	var opacity := float(params.get("opacity", 1.0))
	var spacing := float(params.get("spacing", 1.0))
	var mode := str(params.get("mode", "paint"))
	for i in range(points.size() - 1):
		var a: Variant = points[i]
		var b: Variant = points[i + 1]
		if typeof(a) != TYPE_ARRAY or typeof(b) != TYPE_ARRAY:
			continue
		if a.size() < 2 or b.size() < 2:
			continue
		var x1 := float(a[0])
		var y1 := float(a[1])
		var x2 := float(b[0])
		var y2 := float(b[1])
		var dx := x2 - x1
		var dy := y2 - y1
		var dist := sqrt(dx * dx + dy * dy)
		var steps := int(dist / max(1.0, spacing))
		for s in range(steps + 1):
			var t := 0.0 if steps == 0 else float(s) / float(steps)
			var px := int(round(x1 + dx * t))
			var py := int(round(y1 + dy * t))
			_apply_brush(cel.image, brush, Vector2i(px, py), color, opacity, mode)
	cel.update_texture()
	return {"ok": true}


func _handle_palette_import(params: Dictionary) -> Dictionary:
	var path := str(params.get("path", ""))
	if path.is_empty():
		return _err("path_required", "path is required")
	Palettes.import_palette_from_path(path, true, false)
	return {"ok": true}


func _handle_palette_export(params: Dictionary) -> Dictionary:
	var name := str(params.get("name", ""))
	var path := str(params.get("path", ""))
	var palette: Palette = null
	if not name.is_empty():
		if Palettes.palettes.has(name):
			palette = Palettes.palettes[name]
		elif _require_project() and Global.current_project.palettes.has(name):
			palette = Global.current_project.palettes[name]
	else:
		palette = Palettes.current_palette
	if not is_instance_valid(palette):
		return _err("not_found", "palette not found")
	if path.is_empty():
		return _err("path_required", "path is required")
	var ext := path.get_extension().to_lower()
	var err := OK
	if ext == "gpl":
		err = _palette_export_gpl(palette, path)
	elif ext == "pal":
		err = _palette_export_pal(palette, path)
	else:
		palette.path = path
		err = palette.save_to_file()
	if err != OK:
		return _err("export_failed", error_string(err))
	return {"path": path, "format": ext if not ext.is_empty() else "json"}


func _palette_export_gpl(palette: Palette, path: String) -> int:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not is_instance_valid(file):
		return FileAccess.get_open_error()
	file.store_line("GIMP Palette")
	file.store_line("Name: %s" % palette.name)
	file.store_line("Columns: %d" % maxi(1, palette.width))
	file.store_line("#")
	var keys: Array = palette.colors.keys()
	keys.sort()
	for key in keys:
		var pc: Palette.PaletteColor = palette.colors[key]
		if pc == null:
			continue
		var c := pc.color
		var r := clampi(int(round(c.r * 255.0)), 0, 255)
		var g := clampi(int(round(c.g * 255.0)), 0, 255)
		var b := clampi(int(round(c.b * 255.0)), 0, 255)
		file.store_line("%d %d %d\tColor%d" % [r, g, b, int(key)])
	file.close()
	return OK


func _palette_export_pal(palette: Palette, path: String) -> int:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not is_instance_valid(file):
		return FileAccess.get_open_error()
	file.store_line("JASC-PAL")
	file.store_line("0100")
	var keys: Array = palette.colors.keys()
	keys.sort()
	file.store_line(str(keys.size()))
	for key in keys:
		var pc: Palette.PaletteColor = palette.colors[key]
		if pc == null:
			continue
		var c := pc.color
		var r := clampi(int(round(c.r * 255.0)), 0, 255)
		var g := clampi(int(round(c.g * 255.0)), 0, 255)
		var b := clampi(int(round(c.b * 255.0)), 0, 255)
		file.store_line("%d %d %d" % [r, g, b])
	file.close()
	return OK


func _handle_three_d_object_list(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var layer_idx := int(params.get("layer", project.current_layer))
	var frame_idx := int(params.get("frame", project.current_frame))
	var cel := _get_3d_cel(frame_idx, layer_idx)
	if cel == null:
		return _err("invalid_cel", "not a Cel3D")
	var items := []
	for id in cel.object_properties.keys():
		var obj := cel.get_object_from_id(int(id))
		if not obj:
			continue
		var t := obj.transform
		items.append(
			{
				"id": obj.id,
				"type": obj.type,
				"visible": obj.visible,
				"file_path": obj.file_path,
				"position": [t.origin.x, t.origin.y, t.origin.z],
				"rotation": [
					obj.rotation.x,
					obj.rotation.y,
					obj.rotation.z
				],
				"scale": [obj.scale.x, obj.scale.y, obj.scale.z]
			}
		)
	return {"objects": items}


func _handle_three_d_object_add(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var layer_idx := int(params.get("layer", project.current_layer))
	var frame_idx := int(params.get("frame", project.current_frame))
	var cel := _get_3d_cel(frame_idx, layer_idx)
	if cel == null:
		return _err("invalid_cel", "not a Cel3D")
	var obj_type := _parse_three_d_type(params.get("type", null))
	if obj_type < 0:
		return _err("invalid_type", "unknown 3d type")
	var current_transform := Transform3D()
	var transform := _build_transform(params, current_transform)
	var obj_id := cel.current_object_id
	cel.current_object_id += 1
	var obj_dict := {
		"id": obj_id,
		"type": obj_type,
		"transform": transform,
		"visible": bool(params.get("visible", true)),
		"file_path": str(params.get("file_path", ""))
	}
	cel.object_properties[obj_id] = obj_dict
	cel._add_object_node(obj_id)
	return {"id": obj_id}


func _handle_three_d_object_remove(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var layer_idx := int(params.get("layer", project.current_layer))
	var frame_idx := int(params.get("frame", project.current_frame))
	var obj_id := int(params.get("id", -1))
	var cel := _get_3d_cel(frame_idx, layer_idx)
	if cel == null:
		return _err("invalid_cel", "not a Cel3D")
	if not cel.object_properties.has(obj_id):
		return _err("invalid_id", "object not found")
	cel.object_properties.erase(obj_id)
	cel._remove_object_node(obj_id)
	return {"ok": true}


func _handle_three_d_object_update(params: Dictionary) -> Dictionary:
	if not _require_project():
		return _err("no_project", "no current project")
	var project: Project = Global.current_project
	var layer_idx := int(params.get("layer", project.current_layer))
	var frame_idx := int(params.get("frame", project.current_frame))
	var obj_id := int(params.get("id", -1))
	var cel := _get_3d_cel(frame_idx, layer_idx)
	if cel == null:
		return _err("invalid_cel", "not a Cel3D")
	var obj := cel.get_object_from_id(obj_id)
	if not obj:
		return _err("invalid_id", "object not found")
	var data := obj.serialize()
	if params.has("type"):
		var obj_type := _parse_three_d_type(params.get("type", null))
		if obj_type >= 0:
			data["type"] = obj_type
	if params.has("file_path"):
		data["file_path"] = str(params.get("file_path", data.get("file_path", "")))
	if params.has("visible"):
		data["visible"] = bool(params.get("visible", data.get("visible", true)))
	if params.has("position") or params.has("rotation") or params.has("rotation_degrees") or params.has("scale"):
		var new_transform := _build_transform(params, obj.transform)
		data["transform"] = new_transform
	obj.deserialize(data)
	cel.object_properties[obj_id] = obj.serialize()
	return {"ok": true}


func _parse_color(value) -> Color:
	if typeof(value) == TYPE_STRING:
		return Color.from_string(value, Color.TRANSPARENT)
	if typeof(value) == TYPE_DICTIONARY:
		var r = float(value.get("r", 0.0))
		var g = float(value.get("g", 0.0))
		var b = float(value.get("b", 0.0))
		var a = float(value.get("a", 1.0))
		if r > 1.0 or g > 1.0 or b > 1.0 or a > 1.0:
			return Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0)
		return Color(r, g, b, a)
	if typeof(value) == TYPE_ARRAY:
		var arr: Array = value
		var r := 0.0
		var g := 0.0
		var b := 0.0
		var a := 1.0
		if arr.size() > 0:
			r = float(arr[0])
		if arr.size() > 1:
			g = float(arr[1])
		if arr.size() > 2:
			b = float(arr[2])
		if arr.size() > 3:
			a = float(arr[3])
		if r > 1.0 or g > 1.0 or b > 1.0 or a > 1.0:
			return Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0)
		return Color(r, g, b, a)
	return Color.TRANSPARENT


func _err(code: String, message: String) -> Dictionary:
	return {"_error": {"code": code, "message": message}}


func _require_project() -> bool:
	return Global.current_project != null


func _get_pixel_cel(frame: int, layer: int) -> PixelCel:
	var project := Global.current_project
	if frame < 0 or frame >= project.frames.size():
		return null
	if layer < 0 or layer >= project.layers.size():
		return null
	var cel := project.frames[frame].cels[layer]
	if cel is PixelCel:
		return cel
	return null


func _get_tilemap_cel(frame: int, layer: int) -> CelTileMap:
	var project := Global.current_project
	if frame < 0 or frame >= project.frames.size():
		return null
	if layer < 0 or layer >= project.layers.size():
		return null
	var cel := project.frames[frame].cels[layer]
	if cel is CelTileMap:
		return cel
	return null


func _get_3d_cel(frame: int, layer: int) -> Cel3D:
	var project := Global.current_project
	if frame < 0 or frame >= project.frames.size():
		return null
	if layer < 0 or layer >= project.layers.size():
		return null
	var cel := project.frames[frame].cels[layer]
	if cel is Cel3D:
		return cel
	return null


func _serialize_effect_params(params: Dictionary) -> Dictionary:
	var out := {}
	for key in params.keys():
		var value = params[key]
		var t := typeof(value)
		if t in [TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_BOOL]:
			out[key] = value
		elif t == TYPE_COLOR:
			out[key] = _color_to_array(value)
		elif t == TYPE_VECTOR2 or t == TYPE_VECTOR2I:
			out[key] = [value.x, value.y]
		elif t == TYPE_VECTOR3 or t == TYPE_VECTOR3I:
			out[key] = [value.x, value.y, value.z]
		else:
			out[key] = var_to_str(value)
	return out


func _parse_vector3(value: Variant, default_value: Vector3) -> Vector3:
	if typeof(value) == TYPE_ARRAY:
		var arr: Array = value
		if arr.size() >= 3:
			return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	if typeof(value) == TYPE_DICTIONARY:
		var dict: Dictionary = value
		return Vector3(
			float(dict.get("x", default_value.x)),
			float(dict.get("y", default_value.y)),
			float(dict.get("z", default_value.z))
		)
	return default_value


func _build_transform(params: Dictionary, current: Transform3D) -> Transform3D:
	var pos := _parse_vector3(params.get("position", null), current.origin)
	var scale := _parse_vector3(params.get("scale", null), current.basis.get_scale())
	var rot := current.basis.get_euler()
	if params.has("rotation"):
		rot = _parse_vector3(params.get("rotation", null), rot)
	elif params.has("rotation_degrees"):
		var rot_deg := _parse_vector3(params.get("rotation_degrees", null), rot * 180.0 / PI)
		rot = Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))
	var basis := Basis.from_euler(rot)
	basis = basis.scaled(scale)
	return Transform3D(basis, pos)


func _parse_tile_shape(value) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_STRING:
		var v := String(value).to_lower()
		if v == "square":
			return TileSet.TILE_SHAPE_SQUARE
		if v == "isometric":
			return TileSet.TILE_SHAPE_ISOMETRIC
		if v == "half_offset":
			return TileSet.TILE_SHAPE_HALF_OFFSET_SQUARE
		if v == "hexagon":
			return TileSet.TILE_SHAPE_HEXAGON
	return -1


func _parse_tile_layout(value) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_STRING:
		var v := String(value).to_lower()
		if v == "stacked":
			return TileSet.TILE_LAYOUT_STACKED
		if v == "stacked_offset":
			return TileSet.TILE_LAYOUT_STACKED_OFFSET
		if v == "stairs_right":
			return TileSet.TILE_LAYOUT_STAIRS_RIGHT
		if v == "stairs_down":
			return TileSet.TILE_LAYOUT_STAIRS_DOWN
		if v == "diamond_down":
			return TileSet.TILE_LAYOUT_DIAMOND_DOWN
		if v == "diamond_right":
			return TileSet.TILE_LAYOUT_DIAMOND_RIGHT
	return -1


func _parse_tile_offset_axis(value) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_STRING:
		var v := String(value).to_lower()
		if v == "horizontal":
			return TileSet.TILE_OFFSET_AXIS_HORIZONTAL
		if v == "vertical":
			return TileSet.TILE_OFFSET_AXIS_VERTICAL
	return -1


func _parse_three_d_type(value) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_STRING:
		var v := String(value).to_lower()
		if v == "box":
			return Cel3DObject.Type.BOX
		if v == "sphere":
			return Cel3DObject.Type.SPHERE
		if v == "capsule":
			return Cel3DObject.Type.CAPSULE
		if v == "cylinder":
			return Cel3DObject.Type.CYLINDER
		if v == "prism":
			return Cel3DObject.Type.PRISM
		if v == "torus":
			return Cel3DObject.Type.TORUS
		if v == "plane":
			return Cel3DObject.Type.PLANE
		if v == "text":
			return Cel3DObject.Type.TEXT
		if v == "dir_light" or v == "directional_light":
			return Cel3DObject.Type.DIR_LIGHT
		if v == "spot_light":
			return Cel3DObject.Type.SPOT_LIGHT
		if v == "omni_light":
			return Cel3DObject.Type.OMNI_LIGHT
		if v == "imported":
			return Cel3DObject.Type.IMPORTED
	return -1


func _parse_blend_mode(value) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_STRING:
		var v := String(value).to_lower()
		if v == "pass_through":
			return BaseLayer.BlendModes.PASS_THROUGH
		if v == "normal":
			return BaseLayer.BlendModes.NORMAL
		if v == "erase":
			return BaseLayer.BlendModes.ERASE
		if v == "darken":
			return BaseLayer.BlendModes.DARKEN
		if v == "multiply":
			return BaseLayer.BlendModes.MULTIPLY
		if v == "color_burn":
			return BaseLayer.BlendModes.COLOR_BURN
		if v == "linear_burn":
			return BaseLayer.BlendModes.LINEAR_BURN
		if v == "lighten":
			return BaseLayer.BlendModes.LIGHTEN
		if v == "screen":
			return BaseLayer.BlendModes.SCREEN
		if v == "color_dodge":
			return BaseLayer.BlendModes.COLOR_DODGE
		if v == "add":
			return BaseLayer.BlendModes.ADD
		if v == "overlay":
			return BaseLayer.BlendModes.OVERLAY
		if v == "soft_light":
			return BaseLayer.BlendModes.SOFT_LIGHT
		if v == "hard_light":
			return BaseLayer.BlendModes.HARD_LIGHT
		if v == "difference":
			return BaseLayer.BlendModes.DIFFERENCE
		if v == "exclusion":
			return BaseLayer.BlendModes.EXCLUSION
		if v == "subtract":
			return BaseLayer.BlendModes.SUBTRACT
		if v == "divide":
			return BaseLayer.BlendModes.DIVIDE
		if v == "hue":
			return BaseLayer.BlendModes.HUE
		if v == "saturation":
			return BaseLayer.BlendModes.SATURATION
		if v == "color":
			return BaseLayer.BlendModes.COLOR
		if v == "luminosity":
			return BaseLayer.BlendModes.LUMINOSITY
	return -1


func _parse_animation_direction(value) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_STRING:
		var v := String(value).to_lower()
		if v == "backwards":
			return Export.AnimationDirection.BACKWARDS
		if v == "ping_pong" or v == "pingpong":
			return Export.AnimationDirection.PING_PONG
	return Export.AnimationDirection.FORWARD


func _parse_spritesheet_orientation(value) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_STRING:
		var v := String(value).to_lower()
		if v == "columns":
			return Export.Orientation.COLUMNS
		if v == "tags_by_row":
			return Export.Orientation.TAGS_BY_ROW
		if v == "tags_by_column":
			return Export.Orientation.TAGS_BY_COLUMN
	return Export.Orientation.ROWS


func _export_gif_frames(frames: Array) -> PackedByteArray:
	var GIFExporter := preload("res://addons/gdgifexporter/exporter.gd")
	var MedianCutQuantization := preload("res://addons/gdgifexporter/quantization/median_cut.gd")
	var first_frame: AImgIOFrame = frames[0]
	var exporter := GIFExporter.new(first_frame.content.get_width(), first_frame.content.get_height())
	for v in frames:
		var frame: AImgIOFrame = v
		exporter.add_frame(frame.content, frame.duration, MedianCutQuantization)
	return exporter.export_file_data()


func _export_apng_frames(frames: Array, fps_hint: float) -> PackedByteArray:
	var result := AImgIOAPNGStream.new()
	result.write_magic()
	var image: Image = frames[0].content
	var chunk := result.start_chunk()
	chunk.put_32(image.get_width())
	chunk.put_32(image.get_height())
	chunk.put_32(0x08060000)
	chunk.put_8(0)
	result.write_chunk("IHDR", chunk.data_array)
	chunk = result.start_chunk()
	chunk.put_32(frames.size())
	chunk.put_32(0)
	result.write_chunk("acTL", chunk.data_array)
	var sequence := 0
	for i in range(frames.size()):
		image = frames[i].content
		chunk = result.start_chunk()
		chunk.put_32(sequence)
		sequence += 1
		chunk.put_32(image.get_width())
		chunk.put_32(image.get_height())
		chunk.put_32(0)
		chunk.put_32(0)
		_apng_write_delay(chunk, frames[i].duration, fps_hint)
		chunk.put_8(0)
		chunk.put_8(0)
		result.write_chunk("fcTL", chunk.data_array)
		chunk = result.start_chunk()
		if i != 0:
			chunk.put_32(sequence)
			sequence += 1
		var ichk := result.start_chunk()
		_apng_write_padded_lines(ichk, image)
		chunk.put_data(ichk.data_array.compress(FileAccess.COMPRESSION_DEFLATE))
		if i == 0:
			result.write_chunk("IDAT", chunk.data_array)
		else:
			result.write_chunk("fdAT", chunk.data_array)
	result.write_chunk("IEND", PackedByteArray())
	return result.finish()


func _apng_write_delay(sp: StreamPeer, duration: float, fps_hint: float) -> void:
	duration = max(duration, 0)
	fps_hint = min(32767, max(fps_hint, 1))
	var den: float = min(32767.0, max(fps_hint, 1.0))
	var num: float = max(duration, 0) * den
	var fallback := 10000
	while num > 32767:
		num = max(duration, 0) * den
		den = fallback
		if fallback == 1:
			break
		fallback /= 10
	if num > 32767:
		sp.put_16(1)
		sp.put_16(1)
		return
	while num < 16384 and den < 16384:
		num *= 2
		den *= 2
	sp.put_16(int(round(num)))
	sp.put_16(int(round(den)))


func _apng_write_padded_lines(sp: StreamPeer, img: Image) -> void:
	if img.get_format() != Image.FORMAT_RGBA8:
		return
	var data := img.get_data()
	var y := 0
	var w := img.get_width()
	var h := img.get_height()
	var base := 0
	while y < h:
		var nl := base + (w * 4)
		var line := data.slice(base, nl)
		sp.put_8(0)
		sp.put_data(line)
		y += 1
		base = nl


func _pick_weighted_index(indices: Array, weights: Array) -> int:
	if weights.size() != indices.size() or weights.is_empty():
		return int(indices[randi() % indices.size()])
	var total := 0.0
	for w in weights:
		total += float(w)
	var r := randf() * total
	var acc := 0.0
	for i in range(indices.size()):
		acc += float(weights[i])
		if acc >= r:
			return int(indices[i])
	return int(indices[0])


func _build_brush_image(params: Dictionary) -> Image:
	if params.has("brush_index"):
		if not _require_project():
			return null
		var project: Project = Global.current_project
		var idx := int(params.get("brush_index", -1))
		if idx >= 0 and idx < project.brushes.size():
			return project.brushes[idx]
	var path := str(params.get("brush_path", ""))
	var data_str := str(params.get("brush_data", ""))
	var image := Image.new()
	if not path.is_empty():
		if image.load(path) != OK:
			return null
	elif not data_str.is_empty():
		var raw := Marshalls.base64_to_raw(data_str)
		if image.load_png_from_buffer(raw) != OK:
			return null
	else:
		var brush_type := str(params.get("brush_type", "pixel")).to_lower()
		var size := int(params.get("size", 1))
		size = maxi(1, size)
		image = Image.create(size, size, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		if brush_type == "circle":
			var points := DrawingAlgos.get_ellipse_points(Vector2i.ZERO, Vector2i(size - 1, size - 1))
			for p in points:
				if typeof(p) == TYPE_VECTOR2I:
					image.set_pixelv(p, Color.WHITE)
		elif brush_type == "filled_circle":
			var points_filled := DrawingAlgos.get_ellipse_points_filled(
				Vector2i.ZERO, Vector2i(size - 1, size - 1), 1
			)
			for p2 in points_filled:
				if typeof(p2) == TYPE_VECTOR2I:
					image.set_pixelv(p2, Color.WHITE)
		else:
			image.fill(Color.WHITE)
	image.convert(Image.FORMAT_RGBA8)
	var scale := int(params.get("scale", 1))
	if scale > 1:
		image.resize(image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST)
	return image


func _apply_brush(
	target: Image,
	brush: Image,
	pos: Vector2i,
	color: Color,
	opacity: float,
	mode: String
) -> void:
	var brush_img := Image.new()
	brush_img.copy_from(brush)
	var size := brush_img.get_size()
	var dst := pos - size / 2
	if mode == "erase":
		var blank := Image.create(size.x, size.y, false, target.get_format())
		blank.fill(Color(0, 0, 0, 0))
		target.blit_rect_mask(blank, brush_img, Rect2i(Vector2i.ZERO, size), dst)
		return
	for y in size.y:
		for x in size.x:
			var pix := brush_img.get_pixel(x, y)
			if pix.a <= 0.0:
				continue
			var c := color
			c.a = pix.a * opacity
			brush_img.set_pixel(x, y, c)
	target.blend_rect(brush_img, Rect2i(Vector2i.ZERO, size), dst)


func _color_to_array(color: Color) -> Array:
	return [color.r, color.g, color.b, color.a]


func _color_close(a: Color, b: Color, tolerance: float) -> bool:
	return (
		abs(a.r - b.r) <= tolerance
		and abs(a.g - b.g) <= tolerance
		and abs(a.b - b.b) <= tolerance
		and abs(a.a - b.a) <= tolerance
	)


func _draw_points(image: Image, points: Array, color: Color, thickness := 1) -> void:
	var radius := maxi(0, int(thickness / 2))
	for p in points:
		if typeof(p) == TYPE_VECTOR2I:
			_draw_point(image, p, color, radius)


func _draw_line_on_image(
	image: Image, start: Vector2i, end: Vector2i, color: Color, thickness := 1
) -> void:
	var points := Geometry2D.bresenham_line(start, end)
	_draw_points(image, points, color, thickness)


func _draw_point(image: Image, p: Vector2i, color: Color, radius := 0) -> void:
	var w := image.get_width()
	var h := image.get_height()
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x := p.x + dx
			var y := p.y + dy
			if x >= 0 and y >= 0 and x < w and y < h:
				image.set_pixel(x, y, color)


func _parse_layer_type(value) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_STRING:
		var v := String(value).to_lower()
		if v == "pixel":
			return Global.LayerTypes.PIXEL
		if v == "group":
			return Global.LayerTypes.GROUP
		if v == "three_d" or v == "3d":
			return Global.LayerTypes.THREE_D
		if v == "tilemap":
			return Global.LayerTypes.TILEMAP
		if v == "audio":
			return Global.LayerTypes.AUDIO
	return -1
