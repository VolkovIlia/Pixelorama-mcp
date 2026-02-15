class_name Parsers


static func parse_hint_range(hint: String) -> Dictionary:
	if not hint.contains("hint_range"):
		return {}
	var start := hint.find("hint_range(")
	if start == -1:
		return {}
	var end := hint.find(")", start)
	if end == -1:
		return {}
	var inside := hint.substr(start + "hint_range(".length(), end - (start + "hint_range(".length()))
	var parts := inside.split(",", false)
	if parts.size() < 2:
		return {}
	if not parts[0].strip_edges().is_valid_float():
		return {}
	if not parts[1].strip_edges().is_valid_float():
		return {}
	var result := {"min": float(parts[0]), "max": float(parts[1])}
	if parts.size() >= 3 and parts[2].strip_edges().is_valid_float():
		result["step"] = float(parts[2])
	return result


static func parse_interpolation(value) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	var v := str(value).to_lower()
	if v == "linear" or v == "bilinear":
		return Image.INTERPOLATE_BILINEAR
	if v == "cubic":
		return Image.INTERPOLATE_CUBIC
	return Image.INTERPOLATE_NEAREST


static func parse_color(value) -> Color:
	if typeof(value) == TYPE_COLOR:
		return value
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
		if arr.size() == 1 and typeof(arr[0]) == TYPE_STRING:
			return Color.from_string(str(arr[0]), Color.TRANSPARENT)
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


static func parse_vector3(value: Variant, default_value: Vector3) -> Vector3:
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


static func parse_tile_shape(value) -> int:
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


static func parse_tile_layout(value) -> int:
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


static func parse_tile_offset_axis(value) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_STRING:
		var v := String(value).to_lower()
		if v == "horizontal":
			return TileSet.TILE_OFFSET_AXIS_HORIZONTAL
		if v == "vertical":
			return TileSet.TILE_OFFSET_AXIS_VERTICAL
	return -1


static func parse_three_d_type(value) -> int:
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


static func parse_blend_mode(value) -> int:
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


static func parse_animation_direction(value) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_STRING:
		var v := String(value).to_lower()
		if v == "backwards":
			return Export.AnimationDirection.BACKWARDS
		if v == "ping_pong" or v == "pingpong":
			return Export.AnimationDirection.PING_PONG
	return Export.AnimationDirection.FORWARD


static func parse_spritesheet_orientation(value) -> int:
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


static func parse_spacing_curve(value) -> Dictionary:
	var curve: Dictionary = {"type": "none"}
	if typeof(value) == TYPE_STRING:
		curve["type"] = "preset"
		curve["name"] = str(value).to_lower()
		return curve
	if typeof(value) == TYPE_ARRAY:
		var arr: Array = value
		if arr.is_empty():
			return curve
		var points: Array = []
		if typeof(arr[0]) == TYPE_DICTIONARY:
			for item in arr:
				if typeof(item) != TYPE_DICTIONARY:
					continue
				var t := float(item.get("t", 0.0))
				var v := float(item.get("value", 1.0))
				points.append(Vector2(t, v))
		else:
			for i in range(arr.size()):
				var v2 := float(arr[i])
				var t2 := 0.0
				if arr.size() > 1:
					t2 = float(i) / float(arr.size() - 1)
				points.append(Vector2(t2, v2))
		if not points.is_empty():
			points.sort_custom(func(a, b): return a.x < b.x)
			curve["type"] = "points"
			curve["points"] = points
	return curve


static func parse_layer_type(value) -> int:
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
