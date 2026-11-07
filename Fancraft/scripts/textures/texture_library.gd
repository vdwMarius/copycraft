extends Node
## Texture library (autoload "Textures").
##
## Owns two Texture2DArrays shared by every block material:
##   albedo_array  RGB colour, A opacity
##   surface_array RG tangent normal (OpenGL, +Y = image up), B roughness, A height
## Layer i corresponds to Blocks.TEXTURE_NAMES[i].
##
## The built-in pack is synthesised on the GPU (shaders/texgen.gdshader) at the
## chosen resolution, so the APK ships no texture files.  User packs live in
## user://packs/<id>/ (pack.json + textures/*.png) and fall back to built-in
## layers for anything they do not provide.

signal textures_changed
signal import_finished(result: Dictionary)

const BlocksScript = preload("res://scripts/world/blocks.gd")
const TEXGEN_SHADER = preload("res://shaders/texgen.gdshader")

const BUILTIN_ID := "fancraft_default"
const PACKS_DIR := "user://packs"
const MAX_UNPACKED_BYTES := 64 * 1024 * 1024
const MAX_IMAGE_SIZE := 2048
const RESOLUTIONS := [16, 32, 64, 128, 256, 512]
const ATLAS_COLS := 5

## Flat colours used for the instant fallback set and the headless CPU generator.
const BASE_COLORS := {
	"grass_top": Color(0.33, 0.58, 0.16), "grass_side": Color(0.42, 0.33, 0.2),
	"dirt": Color(0.42, 0.29, 0.17), "stone": Color(0.5, 0.5, 0.52),
	"cobblestone": Color(0.46, 0.45, 0.45), "sand": Color(0.88, 0.8, 0.58),
	"log_top": Color(0.72, 0.55, 0.33), "log_side": Color(0.3, 0.2, 0.11),
	"planks": Color(0.66, 0.47, 0.27), "leaves": Color(0.2, 0.46, 0.12),
	"glass": Color(0.8, 0.93, 0.97, 0.18), "water": Color(0.14, 0.4, 0.7, 0.62),
	"bricks": Color(0.62, 0.3, 0.2), "snow": Color(0.93, 0.95, 1.0),
	"gravel": Color(0.47, 0.45, 0.43), "crystal": Color(0.5, 0.7, 1.0, 0.75),
	"mossy_stone": Color(0.38, 0.45, 0.3), "marble": Color(0.92, 0.91, 0.88),
	"terracotta": Color(0.74, 0.4, 0.23), "slate": Color(0.24, 0.27, 0.31),
}
const BASE_ROUGHNESS := {"glass": 0.04, "water": 0.04, "crystal": 0.06, "marble": 0.12, "snow": 0.6}

var albedo_array: Texture2DArray
var surface_array: Texture2DArray
var resolution := 4
var use_nearest := true
var active_pack := BUILTIN_ID
var last_error := ""

var _building := false
var _rebuild_queued := false
var _builtin_cache := {}  # resolution -> {"albedo": Array[Image], "surface": Array[Image]}
var _dialog: FileDialog
var _images := {"albedo": [], "surface": []}  # CPU copies of the live layers (mip 0)


func _ready() -> void:
	_make_flat_fallback()
	var settings := _settings()
	if settings and settings.has_signal("changed"):
		settings.changed.connect(_on_setting_changed)
	rebuild.call_deferred()


func _settings() -> Node:
	return get_node_or_null("/root/Settings")


func _setting(key: String, default_value: Variant) -> Variant:
	var s := _settings()
	if s == null:
		return default_value
	var v = s.get_value(key)
	return default_value if v == null else v


func _on_setting_changed(key: String) -> void:
	if key == "texture_pack" or key == "texture_resolution":
		rebuild()


func layer_count() -> int:
	return BlocksScript.TEXTURE_NAMES.size()


func layer_of(texture_name: String) -> int:
	return BlocksScript.TEXTURE_NAMES.find(texture_name)


# ------------------------------------------------------------------ building

## Rebuild the arrays from the selected pack/resolution.  Safe to call any time;
## overlapping calls coalesce.  Emits textures_changed when the new set is live.
func rebuild() -> void:
	if _building:
		_rebuild_queued = true
		return
	_building = true
	while true:
		_rebuild_queued = false
		var pack_id: String = str(_setting("texture_pack", BUILTIN_ID))
		var res_setting := int(_setting("texture_resolution", 64))
		await _build(pack_id, res_setting)
		if not _rebuild_queued:
			break
	_building = false


func _build(pack_id: String, res_setting: int) -> void:
	last_error = ""
	var meta := {}
	if pack_id != BUILTIN_ID:
		meta = _read_pack_meta(_pack_path(pack_id))
		if meta.is_empty():
			last_error = "Pack '%s' not found; using built-in textures." % pack_id
			push_warning(last_error)
			pack_id = BUILTIN_ID
	var res := _clamp_resolution(res_setting)
	if pack_id != BUILTIN_ID and res_setting <= 0:
		res = _clamp_resolution(int(meta.get("resolution", _detect_native_resolution(pack_id))))
	elif res_setting <= 0:
		res = 64
	if not _gpu_available():
		res = mini(res, 32)  # CPU fallback stays cheap
	var builtin := await _builtin_images(res)
	var albedo: Array = builtin.albedo
	var surface: Array = builtin.surface
	var pixel_art := res <= 32
	if pack_id != BUILTIN_ID:
		var loaded := await _load_user_pack(pack_id, res, builtin)
		albedo = loaded.albedo
		surface = loaded.surface
		if meta.has("pixel_art"):
			pixel_art = bool(meta.pixel_art) or res <= 32
	_publish(albedo, surface, res, pixel_art, pack_id)


func _publish(albedo: Array, surface: Array, res: int, nearest: bool, pack_id: String) -> void:
	var a := Texture2DArray.new()
	var s := Texture2DArray.new()
	var images_a: Array[Image] = []
	var images_s: Array[Image] = []
	for i in albedo.size():
		var ia: Image = albedo[i].duplicate()
		var is_: Image = surface[i].duplicate()
		if not ia.has_mipmaps():
			ia.generate_mipmaps()
		if not is_.has_mipmaps():
			is_.generate_mipmaps()
		images_a.append(ia)
		images_s.append(is_)
	if a.create_from_images(images_a) != OK or s.create_from_images(images_s) != OK:
		last_error = "Could not create texture arrays."
		push_error(last_error)
		return
	albedo_array = a
	surface_array = s
	_images = {"albedo": albedo, "surface": surface}
	resolution = res
	use_nearest = nearest
	active_pack = pack_id
	textures_changed.emit()


func _clamp_resolution(r: int) -> int:
	var best := 16
	for c in RESOLUTIONS:
		if c <= max(r, 16):
			best = c
	return best


func _gpu_available() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return RenderingServer.get_video_adapter_name() != ""


func _builtin_images(res: int) -> Dictionary:
	if _builtin_cache.has(res):
		return _builtin_cache[res]
	var result: Dictionary
	if _gpu_available():
		result = await _synth_gpu(res)
	else:
		result = _synth_cpu(res)
	_builtin_cache.clear()  # keep memory bounded: only the latest resolution
	_builtin_cache[res] = result
	return result


func _atlas_size(res: int) -> Vector2i:
	var n := layer_count()
	return Vector2i(ATLAS_COLS * res, int(ceil(float(n) / ATLAS_COLS)) * res)


## Render the texgen shader into an offscreen atlas and read it back.
func _render_atlas(material: ShaderMaterial, size: Vector2i) -> Image:
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	vp.transparent_bg = true  # alpha carries opacity / height
	vp.use_hdr_2d = false
	vp.msaa_2d = Viewport.MSAA_DISABLED
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(size)
	rect.material = material
	vp.add_child(rect)
	add_child(vp)
	await RenderingServer.frame_post_draw
	if vp.get_texture().get_image() == null:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img:
		img.convert(Image.FORMAT_RGBA8)
	return img


func _texgen_material(mode: int, res: int, size: Vector2i) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TEXGEN_SHADER
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("res", float(res))
	m.set_shader_parameter("cols", ATLAS_COLS)
	m.set_shader_parameter("tiles", layer_count())
	m.set_shader_parameter("atlas_px", Vector2(size))
	return m


func _slice(atlas: Image, res: int) -> Array:
	var out: Array = []
	for i in layer_count():
		var x := (i % ATLAS_COLS) * res
		var y := (i / ATLAS_COLS) * res
		out.append(atlas.get_region(Rect2i(x, y, res, res)))
	return out


func _synth_gpu(res: int) -> Dictionary:
	var size := _atlas_size(res)
	var a_img := await _render_atlas(_texgen_material(0, res, size), size)
	var s_img := await _render_atlas(_texgen_material(1, res, size), size)
	if a_img == null or s_img == null or a_img.get_size() != size:
		push_warning("GPU texture synthesis unavailable; using CPU fallback.")
		var cpu := _synth_cpu(mini(res, 32))
		for key in ["albedo", "surface"]:
			for img in cpu[key]:
				img.resize(res, res, Image.INTERPOLATE_NEAREST)
		cpu.res = res
		return cpu
	return {"albedo": _slice(a_img, res), "surface": _slice(s_img, res), "res": res}


## Cheap deterministic CPU textures (headless tests / emergency fallback).
func _synth_cpu(res: int) -> Dictionary:
	var albedo: Array = []
	var surface: Array = []
	for i in layer_count():
		var tex_name: String = BlocksScript.TEXTURE_NAMES[i]
		var base: Color = BASE_COLORS.get(tex_name, Color.MAGENTA)
		var rough: float = BASE_ROUGHNESS.get(tex_name, 0.85)
		var a_data := PackedByteArray()
		var s_data := PackedByteArray()
		a_data.resize(res * res * 4)
		s_data.resize(res * res * 4)
		var heights := PackedFloat32Array()
		heights.resize(res * res)
		for p in res * res:
			heights[p] = _hash01(i * 7919 + p) * 0.5 + 0.25
		for y in res:
			for x in res:
				var p := y * res + x
				var h := heights[p]
				var c := base * (0.85 + 0.3 * h)
				a_data[p * 4] = clampi(int(c.r * 255.0), 0, 255)
				a_data[p * 4 + 1] = clampi(int(c.g * 255.0), 0, 255)
				a_data[p * 4 + 2] = clampi(int(c.b * 255.0), 0, 255)
				a_data[p * 4 + 3] = clampi(int(base.a * 255.0), 0, 255)
				var dx := heights[y * res + (x + 1) % res] - heights[y * res + (x - 1 + res) % res]
				var dy := heights[((y + 1) % res) * res + x] - heights[((y - 1 + res) % res) * res + x]
				var n := Vector3(-dx, dy, 1.0).normalized()
				s_data[p * 4] = int((n.x * 0.5 + 0.5) * 255.0)
				s_data[p * 4 + 1] = int((n.y * 0.5 + 0.5) * 255.0)
				s_data[p * 4 + 2] = int(rough * 255.0)
				s_data[p * 4 + 3] = int(h * 255.0)
		albedo.append(Image.create_from_data(res, res, false, Image.FORMAT_RGBA8, a_data))
		surface.append(Image.create_from_data(res, res, false, Image.FORMAT_RGBA8, s_data))
	return {"albedo": albedo, "surface": surface, "res": res}


func _hash01(n: int) -> float:
	n = (n << 13) ^ n
	n = (n * (n * n * 15731 + 789221) + 1376312589) & 0x7fffffff
	return float(n) / 2147483647.0


## Instant 4×4 flat arrays so materials are valid before the first rebuild.
func _make_flat_fallback() -> void:
	var albedo: Array = []
	var surface: Array = []
	for tex_name in BlocksScript.TEXTURE_NAMES:
		var a := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		a.fill(BASE_COLORS.get(tex_name, Color.MAGENTA))
		var s := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		s.fill(Color(0.5, 0.5, BASE_ROUGHNESS.get(tex_name, 0.85), 0.5))
		albedo.append(a)
		surface.append(s)
	_publish(albedo, surface, 4, true, BUILTIN_ID)


# ------------------------------------------------------------------ user packs

func _pack_path(id: String) -> String:
	return PACKS_DIR.path_join(id)


func _read_pack_meta(dir: String) -> Dictionary:
	var path := dir.path_join("pack.json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("name")) != TYPE_STRING:
		return {}
	return parsed


func list_packs() -> Array:
	var out: Array = [{
		"id": BUILTIN_ID, "name": "Fancraft Default", "builtin": true, "resolution": 0,
		"description": "Procedural textures generated on your GPU at any resolution.",
	}]
	var dir := DirAccess.open(PACKS_DIR)
	if dir == null:
		return out
	var ids := dir.get_directories()
	ids.sort()
	for id in ids:
		var meta := _read_pack_meta(_pack_path(id))
		if meta.is_empty():
			continue
		out.append({
			"id": id, "name": str(meta.name), "builtin": false,
			"description": str(meta.get("description", "")),
			"author": str(meta.get("author", "")),
			"resolution": int(meta.get("resolution", 0)),
		})
	return out


func _detect_native_resolution(id: String) -> int:
	var dir := _pack_path(id).path_join("textures")
	for tex_name in BlocksScript.TEXTURE_NAMES:
		var p := dir.path_join(tex_name + ".png")
		if FileAccess.file_exists(p):
			var img := Image.load_from_file(p)
			if img:
				return img.get_width()
	return 64


func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		push_warning("Invalid PNG: " + path)
		return null
	if img.get_width() > MAX_IMAGE_SIZE or img.get_height() > MAX_IMAGE_SIZE:
		push_warning("Image too large (max %d px): %s" % [MAX_IMAGE_SIZE, path])
		return null
	if img.is_compressed():
		img.decompress()
	if img.has_mipmaps():
		img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _fit(img: Image, res: int, pixel_art: bool) -> Image:
	if img.get_width() != img.get_height():
		var side: int = min(img.get_width(), img.get_height())
		img = img.get_region(Rect2i(0, 0, side, side))
	if img.get_width() != res:
		var up := res > img.get_width()
		var interp := Image.INTERPOLATE_NEAREST if (pixel_art and up) else Image.INTERPOLATE_LANCZOS
		img.resize(res, res, interp)
	return img


func _load_user_pack(id: String, res: int, builtin: Dictionary) -> Dictionary:
	var dir := _pack_path(id).path_join("textures")
	var meta := _read_pack_meta(_pack_path(id))
	var pixel_art := bool(meta.get("pixel_art", false))
	var n := layer_count()
	var albedo: Array = []
	var heights: Array = []
	var normals: Array = []
	var roughs: Array = []
	var flags := PackedInt32Array()
	flags.resize(32)
	for i in n:
		var tex_name: String = BlocksScript.TEXTURE_NAMES[i]
		var a := _load_png(dir.path_join(tex_name + ".png"))
		var h := _load_png(dir.path_join(tex_name + "_h.png"))
		var nm := _load_png(dir.path_join(tex_name + "_n.png"))
		var r := _load_png(dir.path_join(tex_name + "_r.png"))
		var f := 0
		if a == null:
			albedo.append(builtin.albedo[i])
			f = 8
		else:
			albedo.append(_fit(a, res, pixel_art))
		if a != null and h:
			h = _fit(h, res, false)
			f |= 1
		if a != null and nm:
			nm = _fit(nm, res, false)
			f |= 2
		if a != null and r:
			r = _fit(r, res, false)
			f |= 4
		heights.append(h if (f & 1) else null)
		normals.append(nm if (f & 2) else null)
		roughs.append(r if (f & 4) else null)
		flags[i] = f
	var surface: Array
	if _gpu_available():
		surface = await _pack_surface_gpu(res, albedo, heights, normals, roughs, flags, builtin)
	if surface.is_empty():
		surface = _pack_surface_cpu(res, albedo, heights, normals, roughs, flags, builtin)
	return {"albedo": albedo, "surface": surface}


func _atlas_from(images: Array, res: int, fallback: Color) -> ImageTexture:
	var size := _atlas_size(res)
	var atlas := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	atlas.fill(fallback)
	for i in images.size():
		var img: Image = images[i]
		if img == null:
			continue
		if img.has_mipmaps():
			img = img.duplicate()
			img.clear_mipmaps()
		atlas.blit_rect(img, Rect2i(0, 0, res, res), Vector2i((i % ATLAS_COLS) * res, (i / ATLAS_COLS) * res))
	return ImageTexture.create_from_image(atlas)


func _pack_surface_gpu(res: int, albedo: Array, heights: Array, normals: Array, roughs: Array, flags: PackedInt32Array, builtin: Dictionary) -> Array:
	var size := _atlas_size(res)
	var m := _texgen_material(2, res, size)
	m.set_shader_parameter("albedo_atlas", _atlas_from(albedo, res, Color.GRAY))
	m.set_shader_parameter("height_atlas", _atlas_from(heights, res, Color.GRAY))
	m.set_shader_parameter("normal_atlas", _atlas_from(normals, res, Color(0.5, 0.5, 1.0)))
	m.set_shader_parameter("rough_atlas", _atlas_from(roughs, res, Color(0.8, 0.8, 0.8)))
	m.set_shader_parameter("builtin_surface", _atlas_from(builtin.surface, res, Color(0.5, 0.5, 0.8, 0.5)))
	m.set_shader_parameter("flags", flags)
	var img := await _render_atlas(m, size)
	if img == null or img.get_size() != size:
		return []
	return _slice(img, res)


## CPU equivalent of texgen mode 2 (used headless; small packs only in practice).
func _pack_surface_cpu(res: int, albedo: Array, heights: Array, normals: Array, roughs: Array, flags: PackedInt32Array, builtin: Dictionary) -> Array:
	var out: Array = []
	for i in albedo.size():
		var f := flags[i]
		if f & 8:
			out.append(builtin.surface[i])
			continue
		var src: Image = heights[i] if (f & 1) else albedo[i]
		var data := src.get_data()
		var h := PackedFloat32Array()
		h.resize(res * res)
		for p in res * res:
			if f & 1:
				h[p] = data[p * 4] / 255.0
			else:
				var lum := (0.299 * data[p * 4] + 0.587 * data[p * 4 + 1] + 0.114 * data[p * 4 + 2]) / 255.0
				h[p] = lerpf(0.5, lum, 0.65)
		var bsurf: Image = builtin.surface[i]
		var bdata := bsurf.get_data() if bsurf.get_width() == res and not bsurf.has_mipmaps() else PackedByteArray()
		var ndata: PackedByteArray = normals[i].get_data() if (f & 2) else PackedByteArray()
		var rdata: PackedByteArray = roughs[i].get_data() if (f & 4) else PackedByteArray()
		var o := PackedByteArray()
		o.resize(res * res * 4)
		var s := res * 0.1 / 8.0
		for y in res:
			for x in res:
				var p := y * res + x
				var nx: int
				var ny: int
				if f & 2:
					nx = ndata[p * 4]
					ny = ndata[p * 4 + 1]
				else:
					var xm := (x - 1 + res) % res
					var xp := (x + 1) % res
					var ym := ((y - 1 + res) % res) * res
					var yp := ((y + 1) % res) * res
					var yr := y * res
					var gx := (h[ym + xp] + 2.0 * h[yr + xp] + h[yp + xp]) - (h[ym + xm] + 2.0 * h[yr + xm] + h[yp + xm])
					var gy := (h[yp + xm] + 2.0 * h[yp + x] + h[yp + xp]) - (h[ym + xm] + 2.0 * h[ym + x] + h[ym + xp])
					var n := Vector3(-gx * s, gy * s, 1.0).normalized()
					nx = int((n.x * 0.5 + 0.5) * 255.0)
					ny = int((n.y * 0.5 + 0.5) * 255.0)
				o[p * 4] = nx
				o[p * 4 + 1] = ny
				o[p * 4 + 2] = rdata[p * 4] if (f & 4) else (bdata[p * 4 + 2] if bdata.size() > 0 else 204)
				o[p * 4 + 3] = int(h[p] * 255.0)
		out.append(Image.create_from_data(res, res, false, Image.FORMAT_RGBA8, o))
	return out


# ------------------------------------------------------------------ import / delete

func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message, "id": ""}


func _is_safe_entry(path: String) -> bool:
	if path.is_empty() or path.begins_with("/") or path.contains("\\") or path.contains(":"):
		return false
	for part in path.split("/", false):
		if part == ".." or part == ".":
			return false
	return true


func _sanitize_id(text: String) -> String:
	var out := ""
	for ch in text.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-":
			out += ch
		elif ch == " ":
			out += "_"
	out = out.substr(0, 40)
	return out if out != "" else "pack"


## Import a texture pack zip into user://packs/<id>/.  Does not activate it.
func import_pack_zip(path: String) -> Dictionary:
	var zip := ZIPReader.new()
	var err := zip.open(path)
	var temp_copy := ""
	if err != OK:
		# Android content:// URIs: copy through FileAccess first.
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.is_empty():
			return _fail("Could not open zip file.")
		temp_copy = "user://import_tmp.zip"
		var fa := FileAccess.open(temp_copy, FileAccess.WRITE)
		if fa == null:
			return _fail("Could not stage zip file.")
		fa.store_buffer(bytes)
		fa.close()
		err = zip.open(temp_copy)
		if err != OK:
			DirAccess.remove_absolute(temp_copy)
			return _fail("Not a valid zip file.")
	var result := _import_from_zip(zip)
	zip.close()
	if temp_copy != "":
		DirAccess.remove_absolute(temp_copy)
	return result


func _import_from_zip(zip: ZIPReader) -> Dictionary:
	var files := zip.get_files()
	for f in files:
		if not _is_safe_entry(f):
			return _fail("Rejected unsafe path in zip: %s" % f)
	# pack.json at root or inside one top-level folder
	var prefix := ""
	if not files.has("pack.json"):
		for f in files:
			if f.count("/") == 1 and f.get_file() == "pack.json":
				prefix = f.get_base_dir() + "/"
				break
		if prefix == "":
			return _fail("pack.json not found in zip.")
	var meta = JSON.parse_string(zip.read_file(prefix + "pack.json").get_string_from_utf8())
	if typeof(meta) != TYPE_DICTIONARY or typeof(meta.get("name")) != TYPE_STRING or str(meta.name).strip_edges() == "":
		return _fail("pack.json must be a JSON object with a \"name\".")
	var valid_names := {}
	for tex_name in BlocksScript.TEXTURE_NAMES:
		for suffix in ["", "_h", "_n", "_r"]:
			valid_names[tex_name + suffix + ".png"] = true
	var staged := {}
	var total := 0
	for f in files:
		if not f.begins_with(prefix) or f.ends_with("/"):
			continue
		var rel := f.substr(prefix.length())
		if not rel.begins_with("textures/") or rel.count("/") != 1:
			continue
		if not valid_names.has(rel.get_file()):
			continue
		var bytes := zip.read_file(f)
		total += bytes.size()
		if total > MAX_UNPACKED_BYTES:
			return _fail("Pack is larger than %d MB." % (MAX_UNPACKED_BYTES / 1048576))
		var img := Image.new()
		if img.load_png_from_buffer(bytes) != OK:
			return _fail("Invalid PNG: %s" % rel)
		if img.get_width() > MAX_IMAGE_SIZE or img.get_height() > MAX_IMAGE_SIZE:
			return _fail("%s is larger than %d px." % [rel, MAX_IMAGE_SIZE])
		staged[rel] = bytes
	if staged.is_empty():
		return _fail("No recognised textures in textures/ (see TEXTURE_PACKS.md).")
	var base_id := _sanitize_id(str(meta.name))
	if base_id == BUILTIN_ID:
		base_id += "_custom"
	var id := base_id
	var n := 2
	while DirAccess.dir_exists_absolute(_pack_path(id)):
		id = "%s_%d" % [base_id, n]
		n += 1
	var dest := _pack_path(id)
	if DirAccess.make_dir_recursive_absolute(dest.path_join("textures")) != OK:
		return _fail("Could not create pack folder.")
	var clean := {"name": str(meta.name)}
	for key in ["description", "author"]:
		if meta.has(key):
			clean[key] = str(meta[key])
	if meta.has("resolution"):
		clean["resolution"] = int(meta.resolution)
	if meta.has("pixel_art"):
		clean["pixel_art"] = bool(meta.pixel_art)
	var ok := _write_file(dest.path_join("pack.json"), JSON.stringify(clean, "  ").to_utf8_buffer())
	for rel in staged:
		ok = ok and _write_file(dest.path_join(rel), staged[rel])
	if not ok:
		_remove_dir(dest)
		return _fail("Could not write pack files.")
	return {"ok": true, "message": "Imported \"%s\" (%d textures)." % [clean.name, staged.size()], "id": id}


func _write_file(path: String, bytes: PackedByteArray) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	return true


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for d in dir.get_directories():
		_remove_dir(path.path_join(d))
	DirAccess.remove_absolute(path)


func delete_pack(id: String) -> bool:
	if id == BUILTIN_ID or not _is_safe_entry(id) or id.contains("/"):
		return false
	var path := _pack_path(id)
	if not DirAccess.dir_exists_absolute(path):
		return false
	_remove_dir(path)
	var s := _settings()
	if s and str(s.get_value("texture_pack")) == id:
		s.set_value("texture_pack", BUILTIN_ID)
	return not DirAccess.dir_exists_absolute(path)


## Show a file picker for a .zip; the outcome arrives via import_finished.
func open_import_dialog() -> void:
	var filters := PackedStringArray(["*.zip;Texture pack;application/zip"])
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var err := DisplayServer.file_dialog_show("Import texture pack", "", "", false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters, _on_native_dialog)
		if err == OK:
			return
	if _dialog == null:
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.filters = PackedStringArray(["*.zip ; Texture pack"])
		_dialog.title = "Import texture pack"
		_dialog.use_native_dialog = false
		_dialog.file_selected.connect(_finish_import)
		_dialog.canceled.connect(func(): import_finished.emit(_fail("Import cancelled.")))
		add_child(_dialog)
	_dialog.popup_centered_ratio(0.8)


func _on_native_dialog(status: bool, selected_paths: PackedStringArray, _filter_index: int) -> void:
	if not status or selected_paths.is_empty():
		import_finished.emit.call_deferred(_fail("Import cancelled."))
		return
	_finish_import.call_deferred(selected_paths[0])


func _finish_import(path: String) -> void:
	import_finished.emit(import_pack_zip(path))
