extends Node3D
## Cosmetic quarter-block geometry, shared across a bounded finite grove.
const VOXEL_SCALE := 0.25
const VISIBILITY_DISTANCE := 44.0
const TREE_POINTS := [Vector2i(-13, -12), Vector2i(13, -18), Vector2i(20, 2), Vector2i(-20, 10), Vector2i(-6, -27)]
const PATCH_OFFSETS := [Vector2i(-4, -3), Vector2i(3, -4), Vector2i(-4, 3), Vector2i(3, 3), Vector2i(-2, -5), Vector2i(1, 5)]
const MAX_INSTANCES := 35

var meshes: Array[Mesh] = []
var instances: Array[MeshInstance3D] = []
var trunk_colliders: Array[StaticBody3D] = []
var stats: Dictionary = {}


func populate(elevation: Callable) -> Dictionary:
	# Repeated calls replace this layer rather than stacking props or collisions.
	for child in get_children():
		remove_child(child)
		child.queue_free()
	meshes.clear()
	instances.clear()
	trunk_colliders.clear()
	for variant in range(2):
		meshes.append(_tree_mesh(variant))
	for variant in range(2):
		meshes.append(_ground_mesh(variant))
	for i in range(TREE_POINTS.size()):
		var point: Vector2i = TREE_POINTS[i]
		var base := float(elevation.call(point.x, point.y)) + 1.0
		# Trunk spans local [12,16), centered at 14 micro voxels.
		_place(meshes[i % 2], Vector3(point.x - 3.0, base, point.y - 3.0), "Tree")
		_trunk_collision(Vector3(point.x + 0.5, base + 2.5, point.y + 0.5))
		for j in range(PATCH_OFFSETS.size()):
			var patch: Vector2i = point + PATCH_OFFSETS[j]
			# Include the complete two-block patch footprint in the spawn exclusion.
			if patch.x < 8 and patch.x + 2 > -8 and patch.y < 16 and patch.y + 2 > -16:
				continue
			var ground := int(elevation.call(patch.x, patch.y))
			if int(elevation.call(patch.x + 1, patch.y)) != ground or int(elevation.call(patch.x, patch.y + 1)) != ground or int(elevation.call(patch.x + 1, patch.y + 1)) != ground:
				continue
			_place(meshes[2 + (i + j) % 2], Vector3(patch.x, ground + 1.0, patch.y), "GroundPatch")
	var unique_triangles := 0
	for mesh in meshes:
		unique_triangles += _triangle_count(mesh)
	var rendered_triangles := 0
	for instance in instances:
		rendered_triangles += _triangle_count(instance.mesh)
	stats = {"meshes": meshes.size(), "instances": instances.size(), "triangles": rendered_triangles, "unique_triangles": unique_triangles, "collisions": trunk_colliders.size()}
	return stats.duplicate()


func _buffer(dimensions: Vector3i) -> VoxelBuffer:
	var buffer := VoxelBuffer.new()
	buffer.create(dimensions.x + 2, dimensions.y + 2, dimensions.z + 2)
	buffer.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_32_BIT)
	return buffer


func _voxel(buffer: VoxelBuffer, x: int, y: int, z: int, color: Color) -> void:
	buffer.set_voxel(color.to_rgba32(), x + 1, y + 1, z + 1, VoxelBuffer.CHANNEL_COLOR)


func _build_mesh(buffer: VoxelBuffer) -> Mesh:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	var mesher := VoxelMesherCubes.new()
	mesher.greedy_meshing_enabled = true
	var mesh := mesher.build_mesh(buffer, [material])
	assert(mesh != null and mesh.get_surface_count() > 0, "Micro-detail native mesher returned empty geometry")
	return mesh


func _tree_mesh(variant: int) -> Mesh:
	var buffer := _buffer(Vector3i(28, 36, 28))
	var bark := Color("79583e") if variant == 0 else Color("70543f")
	for y in range(20):
		for z in range(12, 16):
			for x in range(12, 16):
				_voxel(buffer, x, y, z, bark.darkened(0.12) if x == 12 else bark)
	var greens := [Color("365c48"), Color("477760"), Color("56846d")] if variant == 0 else [Color("315b53"), Color("40796b"), Color("528879")]
	# Overlapping stepped boughs form a complete crown with quarter-unit tips.
	for tier in range(6):
		var base_y := 12 + tier * 3
		var radius := 11 - tier * 2
		for layer in range(4):
			var reach := maxf(1.0, float(radius) - layer * 0.75)
			for z in range(28):
				for x in range(28):
					var dx := absf(x + 0.5 - 14.0)
					var dz := absf(z + 0.5 - 14.0)
					if maxf(dx, dz) <= reach and dx + dz <= reach * 1.5:
						var shade := 0 if layer == 0 else (2 if layer == 3 else 1)
						_voxel(buffer, x, base_y + layer, z, greens[shade])
	return _build_mesh(buffer)


func _ground_mesh(variant: int) -> Mesh:
	var buffer := _buffer(Vector3i(8, 1, 8))
	if variant == 0:
		for z in range(1, 7):
			for x in range(1, 7):
				if abs(x - 3) + abs(z - 4) <= 4 and not (x > 4 and z < 3):
					_voxel(buffer, x, 0, z, Color("6a8052") if z < 4 else Color("5c734c"))
	else:
		for point in [Vector2i(1, 2), Vector2i(4, 4), Vector2i(5, 1)]:
			_voxel(buffer, point.x, 0, point.y, Color("999286"))
			_voxel(buffer, point.x + 1, 0, point.y, Color("8d897e"))
	return _build_mesh(buffer)


func _place(mesh: Mesh, at: Vector3, label: String) -> void:
	assert(instances.size() < MAX_INSTANCES, "Micro-detail instance budget exceeded")
	var instance := MeshInstance3D.new()
	instance.name = "%s%02d" % [label, instances.size()]
	instance.mesh = mesh
	instance.scale = Vector3.ONE * VOXEL_SCALE
	instance.position = at
	instance.visibility_range_end = VISIBILITY_DISTANCE
	instance.visibility_range_end_margin = 3.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	add_child(instance)
	instances.append(instance)


func _trunk_collision(at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "TrunkCollision"
	body.position = at
	var shape := BoxShape3D.new()
	shape.size = Vector3(1, 5, 1)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	trunk_colliders.append(body)


func _triangle_count(mesh: Mesh) -> int:
	var triangles := 0
	for surface in range(mesh.get_surface_count()):
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
	return triangles
