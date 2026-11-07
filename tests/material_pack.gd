extends SceneTree
const Pack = preload("res://scripts/material_pack.gd")
const Settings = preload("res://scripts/material_settings.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	for resolution in Pack.RESOLUTIONS:
		var pack := Pack.new()
		pack.generate(resolution)
		check(pack.albedo_images.size() == 6 and pack.height_images.size() == 6, "Six paired material layers")
		for id in range(6):
			var color: Image = pack.albedo_images[id]
			var height: Image = pack.height_images[id]
			check(color.get_width() == resolution and height.get_height() == resolution, "Requested texture dimensions")
			check(color.has_mipmaps() and height.has_mipmaps(), "Color and linear height maps retain mipmaps")
			var minimum := 1.0
			var maximum := 0.0
			for y in range(resolution):
				for x in range(resolution):
					var h: float = height.get_pixel(x,y).r
					minimum = minf(minimum,h)
					maximum = maxf(maximum,h)
			check(maximum > minimum + 0.1 and minimum >= 0 and maximum <= 1.0, "Nontrivial bounded height data")
			check(is_equal_approx(pack.sample_height(id,Vector2(0.25,0.25)),pack.sample_height(id,Vector2(1.25,-0.75))), "Height samples wrap per block")
		var second := Pack.new()
		second.generate(resolution)
		check(pack.albedo_images[Pack.BARK].get_data() == second.albedo_images[Pack.BARK].get_data(), "Pack generation deterministic")
		var material := pack.make_material(8,true)
		check(material.get_shader_parameter("grid_size") == 8.0 and material.get_shader_parameter("texture_size") == float(resolution), "Grid and texture size remain separate")
	var path := "user://materials-test.cfg"
	var settings := Settings.new()
	settings.grid = 8
	settings.resolution = 128
	settings.relief = false
	check(settings.save_to(path) == OK, "Settings save")
	var restored := Settings.new()
	restored.load_from(path)
	check(restored.grid == 8 and restored.resolution == 128 and not restored.relief, "Settings roundtrip")
	var invalid := ConfigFile.new()
	invalid.set_value("materials","grid",128)
	invalid.set_value("materials","resolution","64")
	invalid.set_value("materials","relief",12)
	invalid.save(path)
	restored.load_from(path)
	check(restored.grid == 4 and restored.resolution == 64 and restored.relief, "Invalid settings fall back to validated defaults")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("MATERIAL_PACK_RESULT failures=",failures)
	quit(1 if failures else 0)
