extends SceneTree
## Needs a display (e.g. xvfb-run). Renders the built-in pack at several
## resolutions and saves contact sheets (albedo over checker / normals / height) to build/.

func _initialize() -> void:
	_run.call_deferred()


func _sheet(lib: Node, res: int) -> Image:
	var n: int = lib.layer_count()
	var cell := 128
	var sheet := Image.create(cell * n, cell * 3, false, Image.FORMAT_RGBA8)
	for i in n:
		var a: Image = lib.albedo_array.get_layer_data(i)
		var s: Image = lib.surface_array.get_layer_data(i)
		a = a.duplicate(); s = s.duplicate()
		a.clear_mipmaps(); s.clear_mipmaps()
		a.resize(cell, cell, Image.INTERPOLATE_NEAREST)
		s.resize(cell, cell, Image.INTERPOLATE_NEAREST)
		for y in cell:
			for x in cell:
				var c := a.get_pixel(x, y)
				var chk := 0.35 if ((x / 16 + y / 16) % 2) == 0 else 0.6
				sheet.set_pixel(i * cell + x, y, Color(chk, chk, chk).lerp(Color(c.r, c.g, c.b), c.a))
				var sp := s.get_pixel(x, y)
				sheet.set_pixel(i * cell + x, cell + y, Color(sp.r, sp.g, 1.0))
				sheet.set_pixel(i * cell + x, cell * 2 + y, Color(sp.a, sp.a, sp.a * 0.8 + sp.b * 0.2))
	return sheet


## Full-resolution albedo tiles (2 rows x 10) over a checker, for close art review.
func _detail_sheet(lib: Node) -> Image:
	var n: int = lib.layer_count()
	var cell := 256
	var sheet := Image.create(cell * 10, cell * 2, false, Image.FORMAT_RGBA8)
	for i in n:
		var a: Image = lib.albedo_array.get_layer_data(i).duplicate()
		a.clear_mipmaps()
		a.resize(cell, cell, Image.INTERPOLATE_NEAREST)
		var ox := (i % 10) * cell
		var oy := (i / 10) * cell
		for y in cell:
			for x in cell:
				var c := a.get_pixel(x, y)
				var chk := 0.35 if ((x / 16 + y / 16) % 2) == 0 else 0.6
				sheet.set_pixel(ox + x, oy + y, Color(chk, chk, chk).lerp(Color(c.r, c.g, c.b), c.a))
	return sheet


func _run() -> void:
	var lib: Node = root.get_node("Textures")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	for res in [16, 64, 256]:
		var t0 := Time.get_ticks_msec()
		await lib._build("fancraft_default", res)
		print("built res=%d in %d ms (adapter=%s)" % [res, Time.get_ticks_msec() - t0, RenderingServer.get_video_adapter_name()])
		_sheet(lib, res).save_png("res://build/texgen_%d.png" % res)
		if res == 256:
			_detail_sheet(lib).save_png("res://build/texgen_256_albedo.png")
	var r: Dictionary = lib.import_pack_zip("res://build/example_pack.zip")
	print("import: ", r)
	if r.ok:
		await lib._build(r.id, 64)
		_sheet(lib, 64).save_png("res://build/texgen_pack.png")
		lib.delete_pack(r.id)
	quit()
