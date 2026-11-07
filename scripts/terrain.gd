extends Node3D
## Finite native-meshed test island. Streaming is deliberately reserved for Job 02.
const Pack = preload("res://scripts/material_pack.gd")
const SIZE := 96
const HEIGHT := 40
var voxel_mesh: Mesh
var generation_ms := 0.0
var detail_stats: Dictionary = {}
var terrain_instance: MeshInstance3D
var details: Node3D

func elevation(x: int, z: int) -> int:
	if abs(x) < 8 and abs(z) < 16:
		return 5
	return 5 + int(3.0 * sin(x * 0.10) * cos(z * 0.075) + 2.0 * sin((x + z) * 0.045))

func _ready() -> void:
	var start := Time.get_ticks_usec()
	var buffer := VoxelBuffer.new()
	buffer.create(SIZE + 2, HEIGHT + 2, SIZE + 2)
	buffer.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_32_BIT)
	for z in range(SIZE):
		for x in range(SIZE):
			var h := elevation(x - SIZE / 2, z - SIZE / 2)
			for y in range(h + 1):
				var color := Pack.marker(Pack.GRASS if y == h else Pack.SOIL)
				if y == h and h < 4:
					color = Pack.marker(Pack.SAND)
				buffer.set_voxel(color.to_rgba32(), x + 1, y + 1, z + 1, VoxelBuffer.CHANNEL_COLOR)
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/voxel_surface.gdshader")
	var mesher := VoxelMesherCubes.new()
	mesher.greedy_meshing_enabled = true
	voxel_mesh = mesher.build_mesh(buffer, [material])
	assert(voxel_mesh != null and voxel_mesh.get_surface_count() > 0, "Native mesher produced no terrain")
	var instance := MeshInstance3D.new()
	instance.mesh = voxel_mesh
	terrain_instance = instance
	instance.position = Vector3(-48, 0, -48)
	add_child(instance)
	instance.create_trimesh_collision()
	details = preload("res://scripts/micro_details.gd").new()
	add_child(details)
	detail_stats = details.populate(elevation)
	print("DETAIL_READY ", detail_stats)
	generation_ms = (Time.get_ticks_usec() - start) / 1000.0
	print("TERRAIN_READY native=VoxelMesherCubes size=96x40x96 generation_ms=", generation_ms)


func apply_material(material: ShaderMaterial) -> void:
	terrain_instance.material_override = material
	for instance in details.instances:
		instance.material_override = material
