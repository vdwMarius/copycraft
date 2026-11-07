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
var continent := FastNoiseLite.new()
var hills := FastNoiseLite.new()
var ridges := FastNoiseLite.new()

# Note: the graph expression parser reads `name * (` as a function call, so parenthesised
# terms come first.
const HEIGHT_EXPR := "34 + cont * 14 + (6 + max(cont, 0) * 10) * hill + max(ridge - 0.25, 0) * 42 * clamp(cont + 0.6, 0, 1)"


func _init(s := 1337) -> void:
	seed_value = s
	continent.seed = s
	continent.frequency = 0.0035
	continent.fractal_octaves = 3
	hills.seed = s + 1
	hills.frequency = 0.012
	hills.fractal_octaves = 4
	ridges.seed = s + 3
	ridges.frequency = 0.006
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridges.fractal_octaves = 3


func height_at(x: float, z: float) -> float:
	var c := continent.get_noise_2d(x, z)
	var h := hills.get_noise_2d(x, z)
	var r := ridges.get_noise_2d(x, z)
	return 34.0 + c * 14.0 + h * (6.0 + maxf(c, 0.0) * 10.0) + maxf(r - 0.25, 0.0) * 42.0 * clampf(c + 0.6, 0.0, 1.0)


## Native generator graph mirroring height_at(): SDF = y - height, plus a texture index.
func build_generator() -> Resource:
	var gen = ClassDB.instantiate("VoxelGeneratorGraph")
	var g = gen.get_main_function()
	var T := func(name: String) -> int: return ClassDB.class_get_integer_constant("VoxelGraphFunction", name)
	var nx: int = g.create_node(T.call("NODE_INPUT_X"), Vector2(0, 0))
	var ny: int = g.create_node(T.call("NODE_INPUT_Y"), Vector2(0, 100))
	var nz: int = g.create_node(T.call("NODE_INPUT_Z"), Vector2(0, 200))
	var noises := []
	for n in [continent, hills, ridges]:
		var id: int = g.create_node(T.call("NODE_NOISE_2D"), Vector2(200, 0))
		g.set_node_param(id, 0, n)
		g.add_connection(nx, 0, id, 0)
		g.add_connection(nz, 0, id, 1)
		noises.append(id)
	var height: int = g.create_node(T.call("NODE_EXPRESSION"), Vector2(400, 0))
	g.set_node_param(height, 0, HEIGHT_EXPR)
	g.set_expression_node_inputs(height, PackedStringArray(["cont", "hill", "ridge"]))
	for i in 3:
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
