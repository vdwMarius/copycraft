class_name Vegetation
extends RefCounted
## Grass and flower ground cover, scattered natively by Voxel Tools' VoxelInstancer
## (multimesh per terrain block, only near the player, removed when the ground is dug).

const KIND_TREE := "tree"
const KIND_ROCK := "rock"
const KIND_BUSH := "bush"

## item id -> kind, filled when the library is built (for harvesting yields later).
static var item_kinds := {}


static func create(voxel_terrain: Node3D) -> Node3D:
	var instancer = ClassDB.instantiate("VoxelInstancer")
	instancer.name = "Vegetation"
	var lib = ClassDB.instantiate("VoxelInstanceLibrary")
	var forest := FastNoiseLite.new()
	forest.seed = 4242
	forest.frequency = 0.008
	var meadow := FastNoiseLite.new()
	meadow.seed = 777
	meadow.frequency = 0.03
	# Trees, bushes and rocks are placed by Flora (exact positions for harvesting and
	# collision); the instancer only scatters ground cover.
	var id := 0
	# Ground cover: only close by (LOD0), dense, no collision, no shadows.
	for v in 2:
		_add_cover(lib, id, PropMeshes.grass_tuft(v), 0.32, meadow, -1.0)
		id += 1
	_add_cover(lib, id, PropMeshes.flower_tuft(0), 0.04, meadow, 0.25)
	id += 1
	instancer.library = lib
	voxel_terrain.add_child(instancer)
	return instancer


static func _gen(params: Dictionary) -> Resource:
	var g = ClassDB.instantiate("VoxelInstanceGenerator")
	g.emit_mode = ClassDB.class_get_integer_constant("VoxelInstanceGenerator", "EMIT_FROM_FACES")
	g.density = params.density
	g.max_slope_degrees = params.get("max_slope", 40.0)
	g.max_slope_falloff_degrees = 6.0
	g.min_height = params.get("min_h", -1000.0)
	g.max_height = params.get("max_h", 1000.0)
	g.min_height_falloff = 1.5
	g.max_height_falloff = 4.0
	var sc: Vector2 = params.get("scale", Vector2.ONE)
	g.min_scale = sc.x
	g.max_scale = sc.y
	g.random_rotation = true
	g.vertical_alignment = params.get("align", 1.0)
	g.offset_along_normal = params.get("offset", 0.0)
	if params.has("noise"):
		g.noise = params.noise
		g.noise_threshold = params.get("noise_threshold", 0.0)
		g.noise_falloff = 0.15
	if params.get("topsoil", false):
		g.voxel_texture_filter_enabled = true
		g.voxel_texture_filter_array = PackedInt32Array([TerrainShape.TOPSOIL])
	return g


static func _add(lib: Object, id: int, kind: String, make: Callable, params: Dictionary, mats: Array) -> void:
	var item = ClassDB.instantiate("VoxelInstanceLibraryMultiMeshItem")
	item.name = "%s_%d" % [kind, id]
	item.lod_index = params.lod_index
	item.generator = _gen(params)
	var meshes: Array = [make.call(0), make.call(1), make.call(2)]
	for m: ArrayMesh in meshes:
		for si in m.get_surface_count():
			if m.surface_get_material(si) == null and si < mats.size():
				m.surface_set_material(si, mats[si])
	item.mesh = meshes[0]
	item.mesh_lod1 = meshes[1]
	item.mesh_lod2 = meshes[2]
	item.mesh_lod0_distance_ratio = 0.25
	item.mesh_lod1_distance_ratio = 0.55
	item.mesh_lod2_distance_ratio = 1.0
	if params.has("collision"):
		var shapes := []
		for c in params.collision:
			shapes.append(c.shape)
			shapes.append(c.transform)
		item.collision_shapes = shapes
		item.collision_distance = 40.0
	lib.add_item(id, item)
	item_kinds[id] = kind


static func _add_cover(lib: Object, id: int, mesh: ArrayMesh, density: float, noise: Noise, threshold: float) -> void:
	var item = ClassDB.instantiate("VoxelInstanceLibraryMultiMeshItem")
	item.name = "cover_%d" % id
	item.lod_index = 0
	var params := {"density": density, "max_slope": 36.0, "min_h": TerrainShape.WATER_LEVEL + 1.8, "max_h": 66.0,
		"scale": Vector2(0.8, 1.3), "topsoil": true, "align": 0.6, "offset": -0.02}
	if threshold > -1.0:
		params.noise = noise
		params.noise_threshold = threshold
	item.generator = _gen(params)
	for si in mesh.get_surface_count():
		if mesh.surface_get_material(si) == null:
			mesh.surface_set_material(si, PropMeshes.grass_material())
	item.mesh = mesh
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	item.hide_beyond_max_lod = true
	lib.add_item(id, item)
	item_kinds[id] = "cover"


## Bushes get a small sphere so they can be targeted and harvested (sphere = "bush").
static func _bush_shape() -> Dictionary:
	var sphere := SphereShape3D.new()
	sphere.radius = 0.55
	return {"shape": sphere, "transform": Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 0))}
