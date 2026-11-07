extends Node3D
## Finite native-meshed test island. Streaming is deliberately reserved for Job 02.
const SIZE := 96
const HEIGHT := 40
var voxel_mesh: Mesh
var generation_ms := 0.0

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
				var color := Color("547e54") if y == h else Color("635c51")
				if y == h and h < 4:
					color = Color("cfb88a")
				buffer.set_voxel(color.to_rgba32(), x + 1, y + 1, z + 1, VoxelBuffer.CHANNEL_COLOR)
	# Small grove with warm trunks and cool fantasy foliage, all part of the native mesh.
	for point in [Vector2i(-13,-12), Vector2i(13,-18), Vector2i(20,2), Vector2i(-20,10), Vector2i(-6,-27)]:
		var base := elevation(point.x, point.y) + 1
		for y in range(5):
			buffer.set_voxel(Color("795238").to_rgba32(), point.x + 49, base + y + 1, point.y + 49, VoxelBuffer.CHANNEL_COLOR)
		for dz in range(-3,4):
			for dx in range(-3,4):
				for dy in range(3):
					if abs(dx) + abs(dz) < 5 - dy:
						buffer.set_voxel(Color("488c83").to_rgba32(), point.x + dx + 49, base + dy + 5, point.y + dz + 49, VoxelBuffer.CHANNEL_COLOR)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.9
	var mesher := VoxelMesherCubes.new()
	mesher.greedy_meshing_enabled = true
	voxel_mesh = mesher.build_mesh(buffer, [material])
	assert(voxel_mesh != null and voxel_mesh.get_surface_count() > 0, "Native mesher produced no terrain")
	var instance := MeshInstance3D.new()
	instance.mesh = voxel_mesh
	instance.position = Vector3(-48, 0, -48)
	add_child(instance)
	instance.create_trimesh_collision()
	generation_ms = (Time.get_ticks_usec() - start) / 1000.0
	print("TERRAIN_READY native=VoxelMesherCubes size=96x40x96 generation_ms=", generation_ms)
