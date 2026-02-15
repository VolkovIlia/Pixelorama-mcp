class_name ExportUtils


static func export_layer_path(base_path: String, layer_name: String, index: int) -> String:
	var ext := base_path.get_extension()
	var base := base_path
	if not ext.is_empty():
		base = base_path.substr(0, base_path.length() - ext.length() - 1)
	var safe := layer_name.strip_edges()
	safe = safe.replace(" ", "_").replace("/", "_").replace("\\", "_")
	if safe.is_empty():
		safe = "layer" + str(index)
	if ext.is_empty():
		return base + "_" + safe
	return base + "_" + safe + "." + ext


static func palette_export_gpl(palette: Palette, path: String) -> int:
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


static func palette_export_pal(palette: Palette, path: String) -> int:
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


static func export_gif_frames(frames: Array) -> PackedByteArray:
	var GIFExporter := preload("res://addons/gdgifexporter/exporter.gd")
	var MedianCutQuantization := preload("res://addons/gdgifexporter/quantization/median_cut.gd")
	var first_frame: AImgIOFrame = frames[0]
	var exporter := GIFExporter.new(first_frame.content.get_width(), first_frame.content.get_height())
	for v in frames:
		var frame: AImgIOFrame = v
		exporter.add_frame(frame.content, frame.duration, MedianCutQuantization)
	return exporter.export_file_data()


static func export_apng_frames(frames: Array, fps_hint: float) -> PackedByteArray:
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
		apng_write_delay(chunk, frames[i].duration, fps_hint)
		chunk.put_8(0)
		chunk.put_8(0)
		result.write_chunk("fcTL", chunk.data_array)
		chunk = result.start_chunk()
		if i != 0:
			chunk.put_32(sequence)
			sequence += 1
		var ichk := result.start_chunk()
		apng_write_padded_lines(ichk, image)
		chunk.put_data(ichk.data_array.compress(FileAccess.COMPRESSION_DEFLATE))
		if i == 0:
			result.write_chunk("IDAT", chunk.data_array)
		else:
			result.write_chunk("fdAT", chunk.data_array)
	result.write_chunk("IEND", PackedByteArray())
	return result.finish()


static func apng_write_delay(sp: StreamPeer, duration: float, fps_hint: float) -> void:
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


static func apng_write_padded_lines(sp: StreamPeer, img: Image) -> void:
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
