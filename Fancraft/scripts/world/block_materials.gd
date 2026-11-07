class_name BlockMaterials
extends RefCounted
## Builds the three block materials (opaque, cutout, translucent) and keeps them
## in sync with the texture library and graphics settings.

const RENDER_MODES := [
	"cull_back, depth_draw_opaque, diffuse_lambert_wrap, specular_schlick_ggx",
	"cull_disabled, depth_draw_opaque, diffuse_lambert_wrap, specular_schlick_ggx",
	"blend_mix, cull_back, depth_draw_opaque, unshaded",
]
const PASS_DEFINES := ["PASS_OPAQUE", "PASS_CUTOUT", "PASS_TRANSLUCENT"]
const POM_STEPS := [0, 8, 14, 24]

var materials: Array[ShaderMaterial] = []
var _nearest := -1
var sun_dir := Vector3(0.45, 0.75, 0.35)


func _init() -> void:
	for i in 3:
		materials.append(ShaderMaterial.new())
	materials[2].render_priority = 1
	# The translucent pass never casts shadows (water/glass would darken what is below).
	refresh()
	Textures.textures_changed.connect(refresh)
	Settings.changed.connect(func(k): if k == "parallax": refresh())


static func shader_code(pass_i: int, nearest: bool) -> String:
	var filter := "filter_nearest_mipmap_anisotropic" if nearest else "filter_linear_mipmap_anisotropic"
	return "shader_type spatial;\nrender_mode %s;\n#define %s\n#define BLOCK_FILTER %s\n#include \"res://shaders/block_common.gdshaderinc\"\n" % [RENDER_MODES[pass_i], PASS_DEFINES[pass_i], filter]


func refresh() -> void:
	var nearest := 1 if Textures.use_nearest else 0
	if nearest != _nearest:
		_nearest = nearest
		for i in 3:
			var sh := Shader.new()
			sh.code = shader_code(i, nearest == 1)
			materials[i].shader = sh
	var q: int = clampi(Settings.get_value("parallax"), 0, 3)
	for m in materials:
		m.set_shader_parameter("albedo_tex", Textures.albedo_array)
		m.set_shader_parameter("surface_tex", Textures.surface_array)
		m.set_shader_parameter("pom_steps", POM_STEPS[q])
		m.set_shader_parameter("pom_shadows", q >= 3)
		m.set_shader_parameter("pom_fade_end", [0.0, 14.0, 22.0, 32.0][q])
		m.set_shader_parameter("pom_fade_start", [0.0, 6.0, 10.0, 16.0][q])
		m.set_shader_parameter("water_layer", float(Blocks.TEXTURE_NAMES.find("water")))
		m.set_shader_parameter("sun_dir", sun_dir)


func set_sun(dir: Vector3) -> void:
	sun_dir = dir
	for m in materials:
		m.set_shader_parameter("sun_dir", dir)
