class_name TerrainShape
extends RefCounted
## The smooth world's shape, defined once and used twice:
## - `build_generator()` compiles it into a native VoxelGeneratorGraph (fast, threaded);
## - `height_at()` evaluates the same formula in GDScript (spawn points, trees, tests).
##
## Texture indices written per voxel (what digging reveals):
##   0 = topsoil (shader turns it into grass / sand / snow / rock by height and slope)
##   1 = dirt, 2 = stone

const WATER_LEVEL := 30.0
const TOPSOIL := 0
const DIRT := 1
const STONE := 2

var seed_value := 1337
var continent := FastNoiseLite.new()   # lowlands vs highlands, very broad
var hills := FastNoiseLite.new()       # rolling hills, domain-warped for natural shapes
var ridges := FastNoiseLite.new()      # mountain ridges
var ranges := FastNoiseLite.new()      # where mountain ranges are allowed

# Note: the graph expression parser reads `name * (` as a function call, so
# parenthesised terms come first.
#   base:      broad lowlands near the sea, gentle highlands inland
#   hills:     amplitude grows inland (flat beaches, rolling interior)
#   mountains: ridged noise squared for sharp crests and wide smooth foothills,
#              only inside "range" regions so most land stays walkable
const HEIGHT_EXPR := "36 + cont * 16 + (2.5 + clamp(cont * 2.2 + 0.9, 0, 1) * 9) * hill + max(ridge, 0) * max(ridge, 0) * 75 * clamp(rng * 2.5 + 0.05, 0, 1)"


func _init(s := 1337) -> void:
	seed_value = s
	continent.seed = s
	continent.frequency = 0.0016
	continent.fractal_octaves = 4
	continent.fractal_gain = 0.45
	hills.seed = s + 1
	hills.frequency = 0.0065
	hills.fractal_octaves = 3
	hills.fractal_gain = 0.42           # fewer small bumps: smoother slopes
	hills.domain_warp_enabled = true
	hills.domain_warp_amplitude = 28.0
	hills.domain_warp_frequency = 0.004
	ridges.seed = s + 3
	ridges.frequency = 0.0032
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridges.fractal_octaves = 4
	ridges.fractal_gain = 0.45
	ranges.seed = s + 5
	ranges.frequency = 0.0011
	ranges.fractal_octaves = 2


func height_at(x: float, z: float) -> float:
	var c := continent.get_noise_2d(x, z)
	var h := hills.get_noise_2d(x, z)
	var r := ridges.get_noise_2d(x, z)
	var m := ranges.get_noise_2d(x, z)
	var crest := maxf(r, 0.0)
	return 36.0 + c * 16.0 + (2.5 + clampf(c * 2.2 + 0.9, 0.0, 1.0) * 9.0) * h + crest * crest * 75.0 * clampf(m * 2.5 + 0.05, 0.0, 1.0)


## Native generator graph mirroring height_at(): SDF = y - height, plus a texture index.
func build_generator() -> Resource:
	var gen = ClassDB.instantiate("VoxelGeneratorGraph")
	var g = gen.get_main_function()
	var T := func(name: String) -> int: return ClassDB.class_get_integer_constant("VoxelGraphFunction", name)
	var nx: int = g.create_node(T.call("NODE_INPUT_X"), Vector2(0, 0))
	var ny: int = g.create_node(T.call("NODE_INPUT_Y"), Vector2(0, 100))
	var nz: int = g.create_node(T.call("NODE_INPUT_Z"), Vector2(0, 200))
	var noises := []
	for n in [continent, hills, ridges, ranges]:
		var id: int = g.create_node(T.call("NODE_NOISE_2D"), Vector2(200, 0))
		g.set_node_param(id, 0, n)
		g.add_connection(nx, 0, id, 0)
		g.add_connection(nz, 0, id, 1)
		noises.append(id)
	var height: int = g.create_node(T.call("NODE_EXPRESSION"), Vector2(400, 0))
	g.set_node_param(height, 0, HEIGHT_EXPR)
	g.set_expression_node_inputs(height, PackedStringArray(["cont", "hill", "ridge", "rng"]))
	for i in 4:
		g.add_connection(noises[i], 0, height, i)
	var sdf: int = g.create_node(T.call("NODE_EXPRESSION"), Vector2(600, 0))
	g.set_node_param(sdf, 0, "posy - height")
	g.set_expression_node_inputs(sdf, PackedStringArray(["posy", "height"]))
	g.add_connection(ny, 0, sdf, 0)
	g.add_connection(height, 0, sdf, 1)
	var out_sdf: int = g.create_node(T.call("NODE_OUTPUT_SDF"), Vector2(800, 0))
	g.add_connection(sdf, 0, out_sdf, 0)
	# Topsoil in the top 1.5 voxels, then dirt, then stone below ~4.
	var tex: int = g.create_node(T.call("NODE_EXPRESSION"), Vector2(600, 200))
	g.set_node_param(tex, 0, "clamp(floor((height - posy - 1.5) / 2.5) + 1, 0, 2)")
	g.set_expression_node_inputs(tex, PackedStringArray(["posy", "height"]))
	g.add_connection(ny, 0, tex, 0)
	g.add_connection(height, 0, tex, 1)
	var out_tex: int = g.create_node(T.call("NODE_OUTPUT_SINGLE_TEXTURE"), Vector2(800, 200))
	g.add_connection(tex, 0, out_tex, 0)
	gen.texture_mode = ClassDB.class_get_integer_constant("VoxelGeneratorGraph", "TEXTURE_MODE_SINGLE")
	gen.use_xz_caching = true
	var result = gen.compile()
	if typeof(result) == TYPE_DICTIONARY and not result.get("success", true):
		push_error("Terrain graph failed to compile: %s" % result)
	return gen
