class_name Drawing


static func blend_mode_color(src: Color, dst: Color, mode: String) -> Color:
	match mode:
		"multiply":
			return Color(dst.r * src.r, dst.g * src.g, dst.b * src.b, 1.0)
		"screen":
			return Color(
				1.0 - (1.0 - dst.r) * (1.0 - src.r),
				1.0 - (1.0 - dst.g) * (1.0 - src.g),
				1.0 - (1.0 - dst.b) * (1.0 - src.b),
				1.0
			)
		"overlay":
			return Color(
				blend_overlay(dst.r, src.r),
				blend_overlay(dst.g, src.g),
				blend_overlay(dst.b, src.b),
				1.0
			)
		"add":
			return Color(
				min(dst.r + src.r, 1.0),
				min(dst.g + src.g, 1.0),
				min(dst.b + src.b, 1.0),
				1.0
			)
		"subtract":
			return Color(
				max(dst.r - src.r, 0.0),
				max(dst.g - src.g, 0.0),
				max(dst.b - src.b, 0.0),
				1.0
			)
		"replace":
			return Color(src.r, src.g, src.b, 1.0)
		_:
			return Color(src.r, src.g, src.b, 1.0)


static func blend_overlay(dst: float, src: float) -> float:
	if dst < 0.5:
		return 2.0 * dst * src
	return 1.0 - 2.0 * (1.0 - dst) * (1.0 - src)


static func spacing_curve_value(curve: Dictionary, t: float) -> float:
	if curve.is_empty():
		return 1.0
	var curve_type := str(curve.get("type", "none"))
	if curve_type == "preset":
		var name := str(curve.get("name", "linear"))
		if name == "ease_in":
			return 0.5 + 0.5 * t
		if name == "ease_out":
			return 1.5 - 0.5 * t
		if name == "ease_in_out":
			return 0.75 + 0.5 * (1.0 - abs(2.0 * t - 1.0))
		return 1.0
	if curve_type == "points":
		var points: Array = curve.get("points", [])
		if points.is_empty():
			return 1.0
		if t <= points[0].x:
			return max(0.1, points[0].y)
		if t >= points[points.size() - 1].x:
			return max(0.1, points[points.size() - 1].y)
		for i in range(points.size() - 1):
			var a: Vector2 = points[i]
			var b: Vector2 = points[i + 1]
			if t >= a.x and t <= b.x:
				var local_t := 0.0
				if b.x > a.x:
					local_t = (t - a.x) / (b.x - a.x)
				return max(0.1, lerp(a.y, b.y, local_t))
	return 1.0


static func polyline_length(points: Array) -> float:
	var total := 0.0
	for i in range(points.size() - 1):
		var a: Variant = points[i]
		var b: Variant = points[i + 1]
		if typeof(a) != TYPE_ARRAY or typeof(b) != TYPE_ARRAY:
			continue
		if a.size() < 2 or b.size() < 2:
			continue
		var v1 := Vector2(float(a[0]), float(a[1]))
		var v2 := Vector2(float(b[0]), float(b[1]))
		total += (v2 - v1).length()
	return total


static func color_to_array(color: Color) -> Array:
	return [color.r, color.g, color.b, color.a]


static func color_close(a: Color, b: Color, tolerance: float) -> bool:
	return (
		abs(a.r - b.r) <= tolerance
		and abs(a.g - b.g) <= tolerance
		and abs(a.b - b.b) <= tolerance
		and abs(a.a - b.a) <= tolerance
	)


static func draw_points(image: Image, points: Array, color: Color, thickness := 1) -> void:
	var radius := maxi(0, int(thickness / 2))
	for p in points:
		if typeof(p) == TYPE_VECTOR2I:
			draw_point(image, p, color, radius)


static func draw_line_on_image(
	image: Image, start: Vector2i, end: Vector2i, color: Color, thickness := 1
) -> void:
	var points := Geometry2D.bresenham_line(start, end)
	draw_points(image, points, color, thickness)


static func draw_point(image: Image, p: Vector2i, color: Color, radius := 0) -> void:
	var w := image.get_width()
	var h := image.get_height()
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x := p.x + dx
			var y := p.y + dy
			if x >= 0 and y >= 0 and x < w and y < h:
				image.set_pixel(x, y, color)


static func pick_weighted_index(indices: Array, weights: Array) -> int:
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
