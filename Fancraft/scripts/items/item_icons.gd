class_name ItemIcons
extends RefCounted
## 64 px item icons: a rounded tile cut from the item's texture-array layer (so texture
## packs restyle them too) with a soft rim; plain painted discs for the rest.

static var _cache := {}


static func clear() -> void:
	_cache.clear()


static func get_icon(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var src: Image = null
	var layer_name: String = Items.DEFS.get(id, ["", "", Color.WHITE])[1]
	var tex = Engine.get_main_loop().root.get_node_or_null("Textures")
	if layer_name != "" and tex and tex.albedo_array:
		var layer := Blocks.TEXTURE_NAMES.find(layer_name)
		if layer >= 0:
			src = tex.albedo_array.get_layer_data(layer)
			if src:
				src = src.duplicate()
				if src.is_compressed():
					src.decompress()
				src.clear_mipmaps()
				src.convert(Image.FORMAT_RGBA8)
				src.resize(size, size, Image.INTERPOLATE_BILINEAR)
	var base := Items.color_of(id)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / (size * 0.5)
			if d > 0.96:
				continue
			var col: Color = src.get_pixel(x, y) if src else base.lightened(0.25 * (1.0 - d) - 0.1 * float(y) / size)
			col.a = 1.0
			if d > 0.84:
				col = col.darkened(0.45)       # rim
			elif y < size * 0.35 and d < 0.7:
				col = col.lightened(0.08)      # painted top highlight
			img.set_pixel(x, y, col)
	var t := ImageTexture.create_from_image(img)
	_cache[id] = t
	return t
