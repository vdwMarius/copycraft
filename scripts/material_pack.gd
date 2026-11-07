extends RefCounted
## Original pack: semantic material IDs, paired color/height layers, no game-state voxels.
const GRASS := 0
const SOIL := 1
const BARK := 2
const STONE := 3
const SAND := 4
const LEAVES := 5
const MATERIAL_COUNT := 6
const RESOLUTIONS := [16, 64, 128]
const GRIDS := [1, 4, 8]
const COLORS := [Color("547e42"), Color("73513b"), Color("775039"), Color("858480"), Color("c7b27e"), Color("40745a")]
const RELIEF_DEPTH := [0.025, 0.055, 0.075, 0.04, 0.015, 0.025]
var resolution := 64
var albedo_images: Array[Image] = []
var height_images: Array[Image] = []
var albedo: Texture2DArray
var heights: Texture2DArray

static func marker(id: int) -> Color:
	return Color(float(id) / 255.0, 0, 0, 1)

static func noise_at(x: int, y: int, salt: int) -> float:
	var n := posmod(x * 73856093 ^ y * 19349663 ^ salt * 83492791, 65521)
	return float(n) / 65520.0

static func pattern(id: int, uv: Vector2) -> float:
	var x := posmod(int(floor(uv.x * 16.0)), 16)
	var y := posmod(int(floor(uv.y * 16.0)), 16)
	var grain := noise_at(x, y, id + 1)
	if id == BARK:
		# Long ridges and broken furrows, periodic across each block face.
		return clampf(0.18 + 0.7 * noise_at(x, 0, 11) + 0.08 * grain, 0.0, 1.0)
	if id == SOIL:
		return 0.15 + 0.65 * noise_at(x / 3, y / 3, 7) + 0.18 * grain
	if id == STONE:
		return 0.2 + 0.65 * noise_at(x / 4, y / 4, 23) + 0.1 * grain
	return 0.3 + 0.55 * grain

func generate(size: int) -> void:
	assert(size in RESOLUTIONS)
	resolution = size
	albedo_images.clear()
	height_images.clear()
	for id in range(MATERIAL_COUNT):
		var color_map := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var height_map := Image.create(size, size, false, Image.FORMAT_RF)
		for y in range(size):
			for x in range(size):
				var uv := Vector2(x + 0.5, y + 0.5) / float(size)
				var h := pattern(id, uv)
				var fine := noise_at(x, y, id + 31)
				var c: Color = COLORS[id] * (0.78 + h * 0.32 + fine * 0.08)
				c.a = 1.0
				color_map.set_pixel(x, y, c)
				height_map.set_pixel(x, y, Color(h, 0, 0, 1))
		color_map.generate_mipmaps()
		height_map.generate_mipmaps()
		albedo_images.append(color_map)
		height_images.append(height_map)
	albedo = Texture2DArray.new()
	heights = Texture2DArray.new()
	assert(albedo.create_from_images(albedo_images) == OK)
	assert(heights.create_from_images(height_images) == OK)

func sample_height(id: int, uv: Vector2) -> float:
	var x := posmod(int(floor(uv.x * resolution)), resolution)
	var y := posmod(int(floor(uv.y * resolution)), resolution)
	return height_images[id].get_pixel(x, y).r

func make_material(grid: int, relief: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/voxel_surface.gdshader")
	material.set_shader_parameter("color_layers", albedo)
	material.set_shader_parameter("height_layers", heights)
	material.set_shader_parameter("grid_size", float(grid))
	material.set_shader_parameter("texture_size", float(resolution))
	material.set_shader_parameter("relief_enabled", relief)
	return material
