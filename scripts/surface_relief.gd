extends Node3D
## Stable cosmetic face residency, batched rendering and continuous height transitions.
const MAX_PATCHES := 256
const MAX_RESIDENT := 384
const RADIUS := 10.0
const FULL_DISTANCE := 6.0
const QUERY_RADIUS := 11.5
const TRANSITION_SECONDS := 0.45
const Pack = preload("res://scripts/material_pack.gd")

var stats: Dictionary = {"patches": 0, "residents": 0, "pool": MAX_RESIDENT, "meshes": 0, "triangles": 0, "mesh_builds": 0, "placement_updates": 0, "batches": 0}
var _batches: Dictionary = {}
var _meshes: Dictionary = {}
var _residents: Dictionary = {}
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
	if rebuild:
		_meshes.clear()
		_meshes[_key(Pack.GRASS, 1, 1)] = _build_tile(Pack.GRASS, 1, 1)
		for id in [Pack.SOIL, Pack.BARK]:
			for axis in [0, 2]:
				for sign_value in [-1, 1]:
					_meshes[_key(id, axis, sign_value)] = _build_tile(id, axis, sign_value)
	var relief_material := material.duplicate() as ShaderMaterial
	relief_material.set_shader_parameter("is_relief_geometry", true)
	for key: String in _meshes:
		var mesh: ArrayMesh = _meshes[key]
		mesh.surface_set_material(0, relief_material)
		if not _batches.has(key):
			var batch := MultiMeshInstance3D.new()
			batch.name = "ReliefBatch" + key.replace(":", "_")
			batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.use_custom_data = true
			multimesh.instance_count = MAX_RESIDENT
			multimesh.visible_instance_count = 0
			batch.multimesh = multimesh
			add_child(batch)
			_batches[key] = batch
		_batches[key].multimesh.mesh = mesh
	stats.meshes = _meshes.size()
	stats.batches = _batches.size()
	# Explicit settings changes may swap mesh detail. Movement preserves all strengths.
	if not enabled:
		_residents.clear()
	_last_block = Vector3i(2147483647, 0, 0)
	_refresh_placement()
	_render_residents()

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
	var uv_depths := PackedVector2Array()
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
					uv_depths.append(Vector2(corners[corner].z, float(axis * 2 + (1 if sign_value > 0 else 2))))
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
	arrays[Mesh.ARRAY_TEX_UV] = uv_depths
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	stats.mesh_builds += 1
	return mesh


func _eye_local() -> Vector3:
	return _terrain.to_local(_player.camera.global_position)

func _process(delta: float) -> void:
	if not _enabled or not is_instance_valid(_player):
		return
	var block := Vector3i(_player.global_position.floor())
	if block != _last_block:
		_refresh_placement()
	_advance_transitions(delta)

func _face_id(origin: Vector3, key: String) -> String:
	return "%d,%d,%d/%s" % [roundi(origin.x), roundi(origin.y), roundi(origin.z), key]

func _candidate(candidates: Array[Dictionary], origin: Vector3, id: int, axis: int, sign_value: int, eye: Vector3) -> void:
	var center := origin + _map(Vector3(0.5, 0.5, 0), axis, sign_value)
	var distance_squared := center.distance_squared_to(eye)
	if distance_squared <= QUERY_RADIUS * QUERY_RADIUS:
		var key := _key(id, axis, sign_value)
		var face_id := _face_id(origin, key)
		# A small residency bias avoids churning equal-distance faces at the budget edge.
		var bias := 0.75 if _residents.has(face_id) and _residents[face_id].strength > 0.0 else 0.0
		candidates.append({"id": face_id, "position": origin, "key": key, "center": center, "rank": distance_squared - bias})

func _refresh_placement() -> void:
	for resident: Dictionary in _residents.values():
		resident.desired = false
	stats.patches = 0
	if not _enabled or not is_instance_valid(_player) or not is_instance_valid(_terrain):
		return
	_last_block = Vector3i(_player.global_position.floor())
	stats.placement_updates += 1
	var foot := _terrain.to_local(_player.global_position)
	var eye := _eye_local()
	var candidates: Array[Dictionary] = []
	for z in range(floori(foot.z) - 12, floori(foot.z) + 13):
		for x in range(floori(foot.x) - 12, floori(foot.x) + 13):
			if x < -48 or x >= 48 or z < -48 or z >= 48:
				continue
			var h: int = _terrain.elevation(x, z)
			if h >= 4:
				_candidate(candidates, Vector3(x, h + 1, z), Pack.GRASS, 1, 1, eye)
			for offset: Vector2i in [Vector2i(-1,0), Vector2i(1,0), Vector2i(0,-1), Vector2i(0,1)]:
				var neighbor: int = _terrain.elevation(x + offset.x, z + offset.y)
				for y in range(maxi(0, neighbor + 1), h + 1):
					var axis := 0 if offset.x != 0 else 2
					var sign_value := offset.x if axis == 0 else offset.y
					_candidate(candidates, Vector3(x + (1 if offset.x > 0 else 0), y, z + (1 if offset.y > 0 else 0)), Pack.SOIL, axis, sign_value, eye)
	for point: Vector2i in _terrain.details.TREE_POINTS:
		var base: int = _terrain.elevation(point.x, point.y) + 1
		for y in range(base, base + 5):
			_candidate(candidates, Vector3(point.x,y,point.y), Pack.BARK, 0, -1, eye)
			_candidate(candidates, Vector3(point.x+1,y,point.y), Pack.BARK, 0, 1, eye)
			_candidate(candidates, Vector3(point.x,y,point.y), Pack.BARK, 2, -1, eye)
			_candidate(candidates, Vector3(point.x,y,point.y+1), Pack.BARK, 2, 1, eye)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.rank < b.rank)
	var admitted := 0
	for i in range(mini(MAX_PATCHES, candidates.size())):
		var candidate: Dictionary = candidates[i]
		if _residents.has(candidate.id):
			_residents[candidate.id].desired = true
			admitted += 1
		elif _residents.size() < MAX_RESIDENT:
			candidate.strength = 0.0
			candidate.desired = true
			_residents[candidate.id] = candidate
			admitted += 1
		# When saturated, defer a newcomer; never steal a still-visible retiring face.
	stats.patches = admitted

func _distance_strength(center: Vector3) -> float:
	return 1.0 - smoothstep(FULL_DISTANCE, RADIUS, center.distance_to(_eye_local()))

func _advance_transitions(delta: float) -> void:
	var removed := false
	var eye := _eye_local()
	for face_id: String in _residents.keys():
		var resident: Dictionary = _residents[face_id]
		var target := (1.0 - smoothstep(FULL_DISTANCE, RADIUS, resident.center.distance_to(eye))) if resident.desired else 0.0
		resident.strength = move_toward(float(resident.strength), target, maxf(delta, 0.0) / TRANSITION_SECONDS)
		if not resident.desired and resident.strength <= 0.0:
			_residents.erase(face_id)
			removed = true
	# Fill deferred newcomers only after old faces have actually reached zero.
	if removed:
		_refresh_placement()
	_render_residents()

func _render_residents() -> void:
	var counts: Dictionary = {}
	var layer_from_terrain := global_transform.affine_inverse() * _terrain.global_transform
	for key: String in _batches:
		counts[key] = 0
	for resident: Dictionary in _residents.values():
		if resident.strength <= 0.0:
			continue
		var key: String = resident.key
		var batch: MultiMeshInstance3D = _batches[key]
		var index: int = counts[key]
		var transform := Transform3D(Basis.IDENTITY, resident.position)
		# Face origins are in terrain-local coordinates; each batch is in this layer's space.
		transform = layer_from_terrain * transform
		batch.multimesh.set_instance_transform(index, transform)
		batch.multimesh.set_instance_custom_data(index, Color(resident.strength, 0, 0, 1))
		counts[key] = index + 1
	var rendered := 0
	for key: String in _batches:
		_batches[key].multimesh.visible_instance_count = counts[key]
		rendered += counts[key]
	stats.residents = _residents.size()
	stats.triangles = rendered * _grid * _grid * 12
