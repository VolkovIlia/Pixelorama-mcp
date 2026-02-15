class_name Shaders

const Parsers = preload("parsers.gd")


static func _err(code: String, message: String) -> Dictionary:
	return {"_error": {"code": code, "message": message}}


static func shader_uniform_schema(shader: Shader) -> Array:
	return parse_shader_uniforms(shader)


static func parse_shader_uniforms(shader: Shader) -> Array:
	var code_lines: Array = shader.code.split("\n")
	var uniforms: Array = []
	var uniform_data: Array = []
	var current_group := ""
	for line in code_lines:
		var stripped := String(line).strip_edges()
		if stripped.begins_with("// uniform_data"):
			uniform_data.append(stripped)
		if stripped.begins_with("group_uniforms"):
			var parts := stripped.split(" ")
			if parts.size() >= 2:
				current_group = parts[1]
			continue
		if not stripped.begins_with("uniform"):
			continue
		var uniform_split := stripped.split("=")
		var u_value := ""
		if uniform_split.size() > 1:
			u_value = uniform_split[1].replace(";", "").strip_edges()
		else:
			uniform_split[0] = uniform_split[0].replace(";", "").strip_edges()
		var u_left_side := uniform_split[0].split(":")
		var u_hint := ""
		if u_left_side.size() > 1:
			u_hint = u_left_side[1].strip_edges().replace(";", "")
		var left := u_left_side[0].replace(";", "").strip_edges()
		var raw_tokens := left.split(" ")
		var tokens: Array = []
		for t in raw_tokens:
			var s := String(t)
			if not s.is_empty():
				tokens.append(s)
		if tokens.size() < 3:
			continue
		var u_name := String(tokens[tokens.size() - 1])
		if u_name in ["PXO_time", "PXO_frame_index", "PXO_layer_index"]:
			continue
		var u_type := String(tokens[1])
		var custom_data: Array = []
		var type_override := ""
		for data in uniform_data:
			if u_name in data:
				custom_data.append(data)
				var line_to_examine := String(data).split(" ")
				if line_to_examine.size() >= 4 and line_to_examine[3] == "type::":
					var temp_splitter := String(data).split("::")
					if temp_splitter.size() > 1:
						type_override = temp_splitter[1].strip_edges()
		uniforms.append(
			{
				"name": u_name,
				"type": u_type,
				"hint": u_hint,
				"default": u_value,
				"group": current_group,
				"custom": type_override,
				"data": custom_data
			}
		)
	return uniforms


static func normalize_shader_params(shader: Shader, params: Dictionary, strict: bool) -> Dictionary:
	var schema: Array = shader_uniform_schema(shader)
	var lookup: Dictionary = {}
	for item in schema:
		lookup[item["name"]] = item
	var normalized: Dictionary = {}
	for key in params.keys():
		var name := str(key)
		if not lookup.has(name):
			if strict:
				return _err("invalid_param", "unknown uniform: " + name)
			normalized[name] = params[key]
			continue
		var info: Dictionary = lookup[name]
		var converted := coerce_shader_param(name, info, params[key], strict)
		if converted.has("_error"):
			return converted
		normalized[name] = converted.get("value", params[key])
	return {"params": normalized, "schema": schema}


static func coerce_shader_param(name: String, info: Dictionary, value: Variant, strict: bool) -> Dictionary:
	var hint := str(info.get("hint", ""))
	var type_val: Variant = info.get("type", TYPE_NIL)
	if typeof(type_val) == TYPE_INT:
		var t := int(type_val)
		if t == TYPE_FLOAT:
			if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
				var v := float(value)
				return validate_number_range(name, v, hint, strict)
			return _err("invalid_param", "expected float for " + name)
		if t == TYPE_INT:
			if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
				var v2 := int(round(float(value)))
				return validate_number_range(name, float(v2), hint, strict)
			return _err("invalid_param", "expected int for " + name)
		if t == TYPE_BOOL:
			return {"value": bool(value)}
		if t == TYPE_VECTOR2:
			if typeof(value) == TYPE_VECTOR2:
				return {"value": value}
			if typeof(value) == TYPE_ARRAY and value.size() >= 2:
				return {"value": Vector2(float(value[0]), float(value[1]))}
			return _err("invalid_param", "expected vec2 for " + name)
		if t == TYPE_VECTOR3:
			if typeof(value) == TYPE_VECTOR3:
				return {"value": value}
			if typeof(value) == TYPE_ARRAY and value.size() >= 3:
				return {"value": Vector3(float(value[0]), float(value[1]), float(value[2]))}
			return _err("invalid_param", "expected vec3 for " + name)
		if t == TYPE_VECTOR4:
			if typeof(value) == TYPE_VECTOR4:
				return {"value": value}
			if typeof(value) == TYPE_ARRAY and value.size() >= 4:
				return {"value": Vector4(float(value[0]), float(value[1]), float(value[2]), float(value[3]))}
			return _err("invalid_param", "expected vec4 for " + name)
		if t == TYPE_COLOR:
			if typeof(value) == TYPE_COLOR:
				return {"value": value}
			return {"value": Parsers.parse_color(value)}
		return {"value": value}

	var type_name := str(type_val).to_lower()
	if type_name == "float":
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			var v3 := float(value)
			return validate_number_range(name, v3, hint, strict)
		return _err("invalid_param", "expected float for " + name)
	if type_name == "int":
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			var v4 := int(round(float(value)))
			return validate_number_range(name, float(v4), hint, strict)
		return _err("invalid_param", "expected int for " + name)
	if type_name == "bool":
		return {"value": bool(value)}
	if type_name in ["vec2", "ivec2", "uvec2"]:
		if typeof(value) == TYPE_VECTOR2:
			return {"value": value}
		if typeof(value) == TYPE_ARRAY and value.size() >= 2:
			return {"value": Vector2(float(value[0]), float(value[1]))}
		return _err("invalid_param", "expected vec2 for " + name)
	if type_name in ["vec3", "ivec3", "uvec3"]:
		if typeof(value) == TYPE_VECTOR3:
			return {"value": value}
		if typeof(value) == TYPE_ARRAY and value.size() >= 3:
			return {"value": Vector3(float(value[0]), float(value[1]), float(value[2]))}
		return _err("invalid_param", "expected vec3 for " + name)
	if type_name in ["vec4", "ivec4", "uvec4"]:
		if typeof(value) == TYPE_VECTOR4:
			return {"value": value}
		if typeof(value) == TYPE_ARRAY and value.size() >= 4:
			return {"value": Vector4(float(value[0]), float(value[1]), float(value[2]), float(value[3]))}
		return {"value": Parsers.parse_color(value)}
	return {"value": value}


static func validate_number_range(name: String, value: float, hint: String, strict: bool) -> Dictionary:
	var range := Parsers.parse_hint_range(hint)
	if range.is_empty():
		return {"value": value}
	var min_v := float(range.get("min", value))
	var max_v := float(range.get("max", value))
	if value < min_v or value > max_v:
		if strict:
			return _err("invalid_param", "value out of range for " + name)
	return {"value": clampf(value, min_v, max_v)}
