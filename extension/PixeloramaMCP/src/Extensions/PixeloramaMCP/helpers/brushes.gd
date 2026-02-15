class_name BrushHelpers

const Drawing = preload("drawing.gd")


static func build_brush_image(params: Dictionary) -> Image:
	if params.has("brush_index"):
		if Global.current_project == null:
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


static func apply_brush(
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
	var mode_l := mode.to_lower()
	if mode_l == "erase":
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
	if mode_l == "paint" or mode_l == "normal":
		target.blend_rect(brush_img, Rect2i(Vector2i.ZERO, size), dst)
		return
	for y2 in size.y:
		for x2 in size.x:
			var src := brush_img.get_pixel(x2, y2)
			if src.a <= 0.0:
				continue
			var tx := dst.x + x2
			var ty := dst.y + y2
			if tx < 0 or ty < 0 or tx >= target.get_width() or ty >= target.get_height():
				continue
			var dst_c := target.get_pixel(tx, ty)
			var blended := Drawing.blend_mode_color(src, dst_c, mode_l)
			var out_r := dst_c.r * (1.0 - src.a) + blended.r * src.a
			var out_g := dst_c.g * (1.0 - src.a) + blended.g * src.a
			var out_b := dst_c.b * (1.0 - src.a) + blended.b * src.a
			var out_a := dst_c.a + src.a * (1.0 - dst_c.a)
			target.set_pixel(tx, ty, Color(out_r, out_g, out_b, out_a))


static func apply_brush_with_variation(
	target: Image,
	brush: Image,
	pos: Vector2i,
	color: Color,
	opacity: float,
	mode: String,
	jitter: float,
	spray: int,
	spray_radius: float
) -> void:
	if spray > 0:
		for i in range(spray):
			var offset := random_offset(spray_radius)
			var jitter_offset := random_offset(jitter)
			apply_brush(target, brush, pos + offset + jitter_offset, color, opacity, mode)
		return
	var jitter_offset2 := random_offset(jitter)
	apply_brush(target, brush, pos + jitter_offset2, color, opacity, mode)


static func random_offset(radius: float) -> Vector2i:
	if radius <= 0.0:
		return Vector2i.ZERO
	var angle := randf() * TAU
	var r := sqrt(randf()) * radius
	return Vector2i(int(round(cos(angle) * r)), int(round(sin(angle) * r)))
