class_name SmoothTerrain
extends Node3D
## Smooth, diggable landscape built on Voxel Tools (VoxelLodTerrain + Transvoxel).
## Meshing, LOD and collision run natively on worker threads; this node only wires
## things up and exposes dig / raise for the player tools.

signal edited(kind: String, at: Vector3)

const DIG_SDF_STRENGTH := 1.0

var shape: TerrainShape
var terrain: Node3D            # VoxelLodTerrain
var tool: Object               # VoxelToolLodTerrain
var material: ShaderMaterial
var water: MeshInstance3D
var water_material: ShaderMaterial
var edit_count := 0            # for tests / stats
var _viewer: Node3D


func setup(seed_value: int, viewer_parent: Node3D) -> void:
	shape = TerrainShape.new(seed_value)
	terrain = ClassDB.instantiate("VoxelLodTerrain")
	terrain.name = "VoxelLodTerrain"
	var mesher = ClassDB.instantiate("VoxelMesherTransvoxel")
	mesher.texturing_mode = ClassDB.class_get_integer_constant("VoxelMesherTransvoxel", "TEXTURES_SINGLE_S4")
	terrain.mesher = mesher
	var fmt = ClassDB.instantiate("VoxelFormat")
	fmt.indices_depth = ClassDB.class_get_integer_constant("VoxelBuffer", "DEPTH_8_BIT")
	if "format" in terrain:
		terrain.format = fmt
	terrain.generator = shape.build_generator()
	terrain.mesh_block_size = 32          # fewer, larger meshes -> fewer draw calls
	terrain.lod_count = 6
	terrain.lod_distance = 40.0
	terrain.generate_collisions = true
	terrain.collision_lod_count = 1
	terrain.threaded_update_enabled = true
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	terrain.material = material
	add_child(terrain)
	tool = terrain.get_voxel_tool()
	_viewer = ClassDB.instantiate("VoxelViewer")
	_viewer.requires_collisions = true
	viewer_parent.add_child(_viewer)
	_build_water()
	refresh_textures()
	Textures.textures_changed.connect(refresh_textures)
	Settings.changed.connect(func(k): if k == "render_distance": _apply_distance())
	_apply_distance()


func _apply_distance() -> void:
	# Smooth LOD terrain is cheap far away: show much more than the old chunk radius.
	var d := 96 + int(Settings.get_value("render_distance")) * 32
	terrain.view_distance = d
	_viewer.view_distance = d


func refresh_textures() -> void:
	for m in [material, water_material]:
		m.set_shader_parameter("albedo_tex", Textures.albedo_array)
		m.set_shader_parameter("surface_tex", Textures.surface_array)
	for name in ["grass_top", "grass_side", "dirt", "stone", "sand", "snow", "mossy_stone", "water", "gravel"]:
		var layer := float(Blocks.TEXTURE_NAMES.find(name))
		material.set_shader_parameter("layer_" + name, layer)
		water_material.set_shader_parameter("layer_" + name, layer)
	material.set_shader_parameter("water_level", TerrainShape.WATER_LEVEL)


func _build_water() -> void:
	water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1200, 1200)
	plane.subdivide_width = 0
	plane.subdivide_depth = 0
	water.mesh = plane
	water_material = ShaderMaterial.new()
	water_material.shader = load("res://shaders/water.gdshader")
	water_material.render_priority = 1
	water.material_override = water_material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position.y = TerrainShape.WATER_LEVEL - 0.15
	add_child(water)


func _process(_delta: float) -> void:
	# Keep the water plane centred under the camera (snapped to avoid swimming UVs).
	var cam := get_viewport().get_camera_3d()
	if cam:
		var p := cam.global_position
		water.position.x = snappedf(p.x, 8.0)
		water.position.z = snappedf(p.z, 8.0)


func set_sun(dir: Vector3) -> void:
	material.set_shader_parameter("sun_dir", dir)
	water_material.set_shader_parameter("sun_dir", dir)


## Is `node` (a physics collider) part of this terrain?
func owns_collider(node: Object) -> bool:
	var n := node as Node
	while n:
		if n == terrain:
			return true
		n = n.get_parent()
	return false


## Carve a sphere out of the terrain.
func dig(center: Vector3, radius: float) -> void:
	tool.channel = ClassDB.class_get_integer_constant("VoxelBuffer", "CHANNEL_SDF")
	tool.mode = ClassDB.class_get_integer_constant("VoxelTool", "MODE_REMOVE")
	tool.sdf_strength = DIG_SDF_STRENGTH
	tool.do_sphere(center, radius)
	edit_count += 1
	edited.emit("dig", center)


## Add a sphere of dirt (painted as dirt so it does not look like natural grass).
func raise(center: Vector3, radius: float) -> void:
	tool.channel = ClassDB.class_get_integer_constant("VoxelBuffer", "CHANNEL_SDF")
	tool.mode = ClassDB.class_get_integer_constant("VoxelTool", "MODE_ADD")
	tool.sdf_strength = DIG_SDF_STRENGTH
	tool.do_sphere(center, radius)
	tool.channel = ClassDB.class_get_integer_constant("VoxelBuffer", "CHANNEL_INDICES")
	tool.mode = ClassDB.class_get_integer_constant("VoxelTool", "MODE_SET")
	tool.value = TerrainShape.DIRT
	tool.do_sphere(center, radius + 0.6)
	edit_count += 1
	edited.emit("raise", center)


## True once the terrain around `pos` has collision (safe to spawn / walk).
func has_ground_below(pos: Vector3, exclude: Array[RID] = []) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 4.0, pos + Vector3.DOWN * 80.0)
	q.exclude = exclude
	var r := space.intersect_ray(q)
	return not r.is_empty() and owns_collider(r.collider)


func height_at(x: float, z: float) -> float:
	return shape.height_at(x, z)
