extends SceneTree
## Headless checks for the texture library: fallback arrays, pack import,
## unsafe zip rejection, pack loading, list/delete.

var failures := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FAIL ", what)


func _initialize() -> void:
	_run.call_deferred()


func _png(color: Color, size := 16) -> PackedByteArray:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return img.save_png_to_buffer()


func _make_zip(path: String, entries: Dictionary) -> void:
	var z := ZIPPacker.new()
	z.open(path)
	for name in entries:
		z.start_file(name)
		z.write_file(entries[name])
		z.close_file()
	z.close()


func _wait_for(cond: Callable, frames := 600) -> bool:
	for i in frames:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _run() -> void:
	var lib: Node = root.get_node("Textures")
	var settings: Node = root.get_node("Settings")
	var n: int = lib.layer_count()
	print("TEXTURE_LIBRARY")
	check(n == 20, "20 texture layers")
	check(lib.albedo_array != null and lib.albedo_array.get_layers() == n, "albedo fallback array has all layers")
	check(lib.surface_array != null and lib.surface_array.get_layers() == n, "surface fallback array has all layers")
	check(lib.albedo_array.get_format() == Image.FORMAT_RGBA8, "albedo RGBA8")

	# clean slate
	for p in lib.list_packs():
		if not p.builtin:
			lib.delete_pack(p.id)
	settings.set_value("texture_pack", lib.BUILTIN_ID)
	settings.set_value("texture_resolution", 32)
	await _wait_for(func(): return not lib._building)
	await lib._build(lib.BUILTIN_ID, 32)
	check(lib.resolution == 32 and lib.albedo_array.get_width() == 32, "built-in rebuilt at 32 px")
	check(lib.albedo_array.has_mipmaps(), "arrays have mipmaps")
	check(lib.use_nearest, "nearest filtering at low resolution")

	# valid pack inside a top-level folder
	var good := "user://test_good.zip"
	var meta := JSON.stringify({"name": "Test Pack!", "description": "d", "pixel_art": true})
	_make_zip(good, {
		"mypack/pack.json": meta.to_utf8_buffer(),
		"mypack/textures/stone.png": _png(Color(1, 0, 0)),
		"mypack/textures/stone_h.png": _png(Color(0.2, 0.2, 0.2)),
		"mypack/textures/unknown.png": _png(Color(0, 1, 0)),
		"mypack/readme.txt": "hi".to_utf8_buffer(),
	})
	var r: Dictionary = lib.import_pack_zip(good)
	check(r.ok and r.id == "test_pack", "valid zip imports as test_pack (%s)" % r.message)
	check(FileAccess.file_exists("user://packs/test_pack/textures/stone.png"), "stone.png extracted")
	check(not FileAccess.file_exists("user://packs/test_pack/textures/unknown.png"), "unknown texture ignored")
	check(not FileAccess.file_exists("user://packs/test_pack/readme.txt"), "non-texture file ignored")
	var r2: Dictionary = lib.import_pack_zip(good)
	check(r2.ok and r2.id == "test_pack_2", "second import gets unique id")

	# unsafe / invalid zips
	var evil := "user://test_evil.zip"
	_make_zip(evil, {"pack.json": meta.to_utf8_buffer(), "../escape.png": _png(Color.WHITE)})
	var r3: Dictionary = lib.import_pack_zip(evil)
	check(not r3.ok and r3.message.contains("unsafe"), "path traversal rejected")
	check(not FileAccess.file_exists("user://escape.png") and not FileAccess.file_exists("user://packs/escape.png"), "nothing escaped")
	var nojson := "user://test_nojson.zip"
	_make_zip(nojson, {"textures/stone.png": _png(Color.WHITE)})
	check(not lib.import_pack_zip(nojson).ok, "zip without pack.json rejected")
	var big := "user://test_big.zip"
	_make_zip(big, {"pack.json": meta.to_utf8_buffer(), "textures/stone.png": Image.create(2100, 8, false, Image.FORMAT_RGBA8).save_png_to_buffer()})
	check(not lib.import_pack_zip(big).ok, "oversized image rejected")
	check(not lib.import_pack_zip("user://does_not_exist.zip").ok, "missing file rejected")

	# list
	var ids := []
	for p in lib.list_packs():
		ids.append(p.id)
	check(ids[0] == lib.BUILTIN_ID and ids.has("test_pack") and ids.has("test_pack_2"), "list_packs shows built-in + imports")

	# activate the pack through Settings and verify textures
	var changed := [false]
	lib.textures_changed.connect(func(): changed[0] = true)
	settings.set_value("texture_pack", "test_pack")
	await _wait_for(func(): return changed[0] and not lib._building and lib.active_pack == "test_pack")
	check(lib.active_pack == "test_pack", "pack activated via Settings")
	var stone: int = lib.layer_of("stone")
	var img: Image = lib._images.albedo[stone]
	var c := img.get_pixel(3, 3)
	check(c.r > 0.9 and c.g < 0.1, "stone albedo comes from pack")
	var surf: Image = lib._images.surface[stone]
	check(absf(surf.get_pixel(3, 3).a - 0.2) < 0.03, "stone height comes from _h.png")
	var dirt: Image = lib._images.albedo[lib.layer_of("dirt")]
	check(dirt.get_pixel(2, 2).r < 0.9, "missing layers fall back to built-in")
	check(lib.albedo_array.get_width() == 32, "pack resampled to selected resolution")

	# delete
	check(not lib.delete_pack(lib.BUILTIN_ID), "built-in cannot be deleted")
	check(not lib.delete_pack("../packs"), "unsafe delete refused")
	check(lib.delete_pack("test_pack"), "delete active pack")
	check(str(settings.get_value("texture_pack")) == lib.BUILTIN_ID, "deleting active pack reverts to built-in")
	check(lib.delete_pack("test_pack_2"), "delete second pack")
	check(lib.list_packs().size() == 1, "only built-in remains")
	await _wait_for(func(): return not lib._building)

	for f in [good, evil, nojson, big]:
		DirAccess.remove_absolute(f)
	print("TEXTURE_LIBRARY_RESULT failures=%d" % failures)
	quit(1 if failures else 0)
