extends SceneTree
const Pack = preload("res://scripts/material_pack.gd")
var failures := 0


func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var terrain = load("res://scripts/terrain.gd").new()
	root.add_child(terrain)
	var player = load("res://scripts/player.gd").new()
	root.add_child(player)
	player.set_physics_process(false)
	player.position = Vector3(-11, terrain.elevation(-11, -12) + 1, -12)
	var relief = load("res://scripts/surface_relief.gd").new()
	root.add_child(relief)
	var pack := Pack.new()
	pack.generate(64)
	var material := pack.make_material(8, true)
	relief.configure(pack, 8, true, material, terrain, player)
	check(relief.stats.patches > 0 and relief.stats.patches <= 32, "Nearby relief uses bounded pool")
	check(relief.stats.meshes == 9 and relief.stats.mesh_builds == 9, "Nine cached material/orientation variants")
	check(relief.stats.triangles <= 30000, "Eight-grid relief stays under triangle budget")
	var pool_ids: Array[int] = []
	var mesh_ids: Array[int] = []
	var actual_triangles := 0
	var found_bark := false
	for child in relief.get_children():
		check(child is MeshInstance3D, "Relief contains meshes only, with no collision nodes")
		pool_ids.append(child.get_instance_id())
		if child.visible:
			actual_triangles += child.mesh.get_faces().size() / 3
			var colors: PackedColorArray = child.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			found_bark = found_bark or roundi(colors[0].r * 255.0) == Pack.BARK
	check(found_bark, "Nearby tree receives actual bark geometry")
	check(actual_triangles == relief.stats.triangles, "Statistics match actual active triangle count")
	for mesh: ArrayMesh in relief._meshes.values():
		mesh_ids.append(mesh.get_instance_id())
	var bark: ArrayMesh = relief._meshes[relief._key(Pack.BARK, 0, 1)]
	var arrays := bark.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var depths: Dictionary = {}
	for i in range(vertices.size()):
		if normals[i].dot(Vector3.RIGHT) > 0.99:
			depths[snappedf(vertices[i].x, 0.000001)] = true
	check(depths.size() > 1, "Bark relief has varied real vertex depths")
	check(bark.get_aabb().size.x > 0.02 and bark.get_aabb().size.x <= Pack.RELIEF_DEPTH[Pack.BARK], "Bark relief depth stays within authored range")
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		var cross := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		check(cross.dot(normals[a]) < 0, "Clockwise winding agrees with outward normal")
	var updates: int = relief.stats.placement_updates
	player.position.x += 0.1
	relief._process(0.016)
	check(relief.stats.placement_updates == updates, "Movement within block does not refresh placement")
	player.position.x += 1.1
	relief._process(0.016)
	check(relief.stats.placement_updates == updates + 1 and relief.stats.mesh_builds == 9, "New block reuses mesh cache")
	relief.configure(pack, 8, false, material, terrain, player)
	check(relief.stats.patches == 0 and relief.stats.triangles == 0, "Off removes all active geometry")
	for child in relief.get_children():
		check(not child.visible, "Off hides every pooled instance")
	relief.configure(pack, 8, true, material, terrain, player)
	check(relief.stats.mesh_builds == 9, "Toggling relief reuses cache")
	var reused_mesh_ids: Array[int] = []
	for mesh: ArrayMesh in relief._meshes.values():
		reused_mesh_ids.append(mesh.get_instance_id())
	check(reused_mesh_ids == mesh_ids, "Reconfiguration retains shared mesh resources")
	relief.configure(pack, 4, true, pack.make_material(4, true), terrain, player)
	check(relief.stats.mesh_builds == 18 and relief.stats.meshes == 9, "Grid change replaces bounded cache once")
	var reused_pool_ids: Array[int] = []
	for child in relief.get_children():
		reused_pool_ids.append(child.get_instance_id())
	check(pool_ids == reused_pool_ids and reused_pool_ids.size() == 32, "Movement and settings reuse the same instance pool")
	print("SURFACE_RELIEF_RESULT failures=", failures, " stats=", relief.stats)
	quit(1 if failures else 0)
