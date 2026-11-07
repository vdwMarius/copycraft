extends Node3D
## Pooled cosmetic face tiles. Whole-block terrain remains the collision authority.
const MAX_PATCHES := 32
const RADIUS := 7.0
const Pack = preload("res://scripts/material_pack.gd")

var stats: Dictionary = {"patches": 0, "pool": 0, "meshes": 0, "triangles": 0, "mesh_builds": 0, "placement_updates": 0}
var _pool: Array[MeshInstance3D] = []
var _meshes: Dictionary = {}
var _pack: RefCounted
var _grid := 4
var _enabled := false
var _terrain: Node3D
var _player: CharacterBody3D
var _last_block := Vector3i(2147483647, 0, 0)


func configure(pack: RefCounted, grid: int, enabled: bool, material: ShaderMaterial, terrain: Node3D, player: CharacterBody3D) -> void:
	assert(grid in [1, 4, 8])
	var rebuild := _pack != pack or _grid != grid or _meshes.is_empty()
	_pack = pack
	_grid = grid
	_enabled = enabled
	_terrain = terrain
	_player = player
	if _pool.is_empty():
		for i in range(MAX_PATCHES):
			var instance := MeshInstance3D.new()
			instance.name = "Relief%02d" % i
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.visibility_range_end = 8.0
			instance.visible = false
			add_child(instance)
			_pool.append(instance)
	if rebuild:
		_meshes.clear()
		_meshes[_key(Pack.GRASS, 1, 1)] = _build_tile(Pack.GRASS, 1, 1)
		for id in [Pack.SOIL, Pack.BARK]:
			for axis in [0, 2]:
				for sign_value in [-1, 1]:
					_meshes[_key(id, axis, sign_value)] = _build_tile(id, axis, sign_value)
	for mesh: ArrayMesh in _meshes.values():
		mesh.surface_set_material(0, material)
	stats.meshes = _meshes.size()
	stats.pool = _pool.size()
	_last_block = Vector3i(2147483647, 0, 0)
	_refresh_placement()


func _key(id: int, axis: int, sign_value: int) -> String:
	return "%d:%d:%d" % [id, axis, sign_value]


func _map(point: Vector3, axis: int, sign_value: int) -> Vector3:
	if axis == 0:
		return Vector3(point.z * sign_value, point.y, point.x)
	if axis == 1:
		return Vector3(point.x, point.z * sign_value, point.y)
	return Vector3(point.x, point.y, point.z * sign_value)


func _build_tile(id: int, axis: int, sign_value: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var step := 1.0 / _grid
	for y in range(_grid):
		for x in range(_grid):
			var uv := Vector2(x + 0.5, y + 0.5) * step
			var height: float = (0.12 + 0.88 * _pack.sample_height(id, uv)) * Pack.RELIEF_DEPTH[id]
			var lo := Vector3(x * step, y * step, 0.001)
			var hi := Vector3((x + 1) * step, (y + 1) * step, height)
			var corners := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
			# Cube quads include closed backs, with winding corrected after axis mapping.
			var faces := [[4, 5, 6, 7], [1, 0, 3, 2], [0, 4, 7, 3], [5, 1, 2, 6], [3, 7, 6, 2], [0, 1, 5, 4]]
			var outward := [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0)]
			for face in range(6):
				var offset := vertices.size()
				var normal := _map(outward[face], axis, sign_value)
				for corner: int in faces[face]:
					vertices.append(_map(corners[corner], axis, sign_value))
					normals.append(normal)
					colors.append(Pack.marker(id))
				var cross := (vertices[offset + 1] - vertices[offset]).cross(vertices[offset + 2] - vertices[offset])
				# Godot's front faces use clockwise winding.
				if cross.dot(normal) < 0:
					indices.append_array(PackedInt32Array([offset, offset + 1, offset + 2, offset, offset + 2, offset + 3]))
				else:
					indices.append_array(PackedInt32Array([offset, offset + 2, offset + 1, offset, offset + 3, offset + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	stats.mesh_builds += 1
	return mesh


func _process(_delta: float) -> void:
	if _enabled and is_instance_valid(_player):
		var block := Vector3i(_player.global_position.floor())
		if block != _last_block:
			_refresh_placement()


func _candidate(candidates: Array[Dictionary], origin: Vector3, id: int, axis: int, sign_value: int, eye: Vector3) -> void:
	var center := origin + _map(Vector3(0.5, 0.5, 0), axis, sign_value)
	var distance_squared := center.distance_squared_to(eye)
	if distance_squared <= RADIUS * RADIUS:
		candidates.append({"position": origin, "key": _key(id, axis, sign_value), "distance": distance_squared})


func _refresh_placement() -> void:
	for instance in _pool:
		instance.visible = false
	stats.patches = 0
	stats.triangles = 0
	if not _enabled or not is_instance_valid(_player) or not is_instance_valid(_terrain):
		return
	_last_block = Vector3i(_player.global_position.floor())
	stats.placement_updates += 1
	var foot := _terrain.to_local(_player.global_position)
	var eye := foot + Vector3.UP * 1.4
	var candidates: Array[Dictionary] = []
	for z in range(floori(foot.z) - 7, floori(foot.z) + 8):
		for x in range(floori(foot.x) - 7, floori(foot.x) + 8):
			if x < -48 or x >= 48 or z < -48 or z >= 48:
				continue
			var h: int = _terrain.elevation(x, z)
			# Low terrain uses sand in the base mesh; retain its shader-only detail.
			if h >= 4:
				_candidate(candidates, Vector3(x, h + 1, z), Pack.GRASS, 1, 1, eye)
			for offset: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var neighbor: int = _terrain.elevation(x + offset.x, z + offset.y)
				for y in range(maxi(0, neighbor + 1), h + 1):
					var axis := 0 if offset.x != 0 else 2
					var sign_value := offset.x if axis == 0 else offset.y
					_candidate(candidates, Vector3(x + (1 if offset.x > 0 else 0), y, z + (1 if offset.y > 0 else 0)), Pack.SOIL, axis, sign_value, eye)
	for point: Vector2i in _terrain.details.TREE_POINTS:
		var base: int = _terrain.elevation(point.x, point.y) + 1
		for y in range(base, base + 5):
			_candidate(candidates, Vector3(point.x, y, point.y), Pack.BARK, 0, -1, eye)
			_candidate(candidates, Vector3(point.x + 1, y, point.y), Pack.BARK, 0, 1, eye)
			_candidate(candidates, Vector3(point.x, y, point.y), Pack.BARK, 2, -1, eye)
			_candidate(candidates, Vector3(point.x, y, point.y + 1), Pack.BARK, 2, 1, eye)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
	var count := mini(MAX_PATCHES, candidates.size())
	for i in range(count):
		var instance := _pool[i]
		instance.mesh = _meshes[candidates[i].key]
		instance.global_position = _terrain.to_global(candidates[i].position)
		instance.visible = true
	stats.patches = count
	stats.triangles = count * _grid * _grid * 12
