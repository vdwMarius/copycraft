extends SceneTree
## Deterministic movement/transition checks without relying on rendering speed.
const Pack = preload("res://scripts/material_pack.gd")
var failures := 0

class EmptyGrove extends RefCounted:
	const TREE_POINTS: Array[Vector2i] = []

class FlatTerrain extends Node3D:
	var details := EmptyGrove.new()
	func elevation(_x: int, _z: int) -> int:
		return 5


func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1


func _initialize() -> void:
	call_deferred("run")


func snapshot(relief: Node3D) -> Dictionary:
	return relief._residents.duplicate(true)


func advance(relief: Node3D, seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.00001:
		var dt := minf(0.025, remaining)
		relief._advance_transitions(dt)
		relief._render_residents()
		remaining -= dt


func check_budget(relief: Node3D) -> void:
	check(relief._residents.size() <= 384 and relief.stats.residents <= 384, "Resident descriptor count stays bounded")
	check(relief.stats.patches <= 256, "Desired face count stays bounded")
	check(relief._batches.size() == 9 and relief.get_child_count() == 9, "Only nine draw batches and no collision children")
	var visible := 0
	var triangles := 0
	var custom_data_valid := true
	for batch: MultiMeshInstance3D in relief._batches.values():
		var count := batch.multimesh.visible_instance_count
		check(count >= 0 and count <= 384, "Batch has valid bounded visible instance count")
		visible += count
		triangles += batch.multimesh.mesh.get_faces().size() / 3 * count
		if DisplayServer.get_name() != "headless":
			for i in range(count):
				var strength := batch.multimesh.get_instance_custom_data(i).r
				custom_data_valid = custom_data_valid and strength > 0 and strength <= 1.0001
	# Godot's dummy headless renderer does not retain MultiMesh custom-data readback.
	check(custom_data_valid, "Rendered instances carry bounded positive strength")
	for descriptor: Dictionary in relief._residents.values():
		check(descriptor.strength >= 0 and descriptor.strength <= 1.0001, "Resident strengths remain bounded")
	check(visible <= 384 and triangles <= 294912, "Actual batched geometry obeys transient budget")
	check(triangles == relief.stats.triangles, "Triangle telemetry equals actual submitted instance geometry")


func run() -> void:
	var terrain := FlatTerrain.new()
	root.add_child(terrain)
	var player = load("res://scripts/player.gd").new()
	root.add_child(player)
	player.set_physics_process(false)
	player.position = Vector3(0, 6, 0)
	var relief = load("res://scripts/surface_relief.gd").new()
	root.add_child(relief)
	relief.set_process(false)
	var pack := Pack.new()
	pack.generate(64)
	relief.configure(pack, 8, true, pack.make_material(8, true), terrain, player)
	var eye: Vector3 = player.camera.global_position
	check(is_equal_approx(relief._distance_strength(eye + Vector3.RIGHT * 6), 1.0), "Six-metre distance remains at full target strength")
	var middle: float = relief._distance_strength(eye + Vector3.RIGHT * 8)
	check(middle > 0 and middle < 1 and is_zero_approx(relief._distance_strength(eye + Vector3.RIGHT * 10)), "Distance strength falls continuously toward zero at ten metres")
	check(not relief._residents.is_empty(), "Configuration admits nearby face descriptors")
	for descriptor: Dictionary in relief._residents.values():
		check(is_zero_approx(descriptor.strength), "New faces begin flattened")
	advance(relief, 0.1)
	var warming := snapshot(relief)
	var fading_in := false
	for descriptor: Dictionary in warming.values():
		fading_in = fading_in or (descriptor.strength > 0 and descriptor.strength < 0.95)
	check(fading_in, "New geometry eases in over several frames")
	advance(relief, 0.6)
	var settled := snapshot(relief)
	var farther_than_old_cutoff := false
	for descriptor: Dictionary in settled.values():
		var horizontal := Vector2(descriptor.center.x, descriptor.center.z).length()
		farther_than_old_cutoff = farther_than_old_cutoff or (horizontal > 5 and descriptor.strength > 0.5)
	check(farther_than_old_cutoff, "Open-ground detail extends beyond the old three-block budget boundary")
	check_budget(relief)
	var builds: int = relief.stats.mesh_builds
	player.position.x = 1.0
	relief._refresh_placement()
	var shared := 0
	var retiring_ids: Array = []
	for id: Variant in settled:
		if relief._residents.has(id):
			var descriptor: Dictionary = relief._residents[id]
			check(descriptor.position == settled[id].position and descriptor.key == settled[id].key, "Stable face ID retains position and material/orientation")
			check(is_equal_approx(descriptor.strength, settled[id].strength), "Ranking refresh never resets current strength")
			shared += 1
			if not descriptor.desired and descriptor.strength > 0.05:
				retiring_ids.append(id)
	check(shared > 150 and not retiring_ids.is_empty(), "Movement retains residents and marks outgoing faces for retirement")
	advance(relief, 0.025)
	var mid_retirement := snapshot(relief)
	var retired_smoothly := false
	for id: Variant in retiring_ids:
		if mid_retirement.has(id):
			retired_smoothly = retired_smoothly or (mid_retirement[id].strength > 0 and mid_retirement[id].strength < settled[id].strength)
	check(retired_smoothly, "Outgoing faces flatten gradually before removal")
	player.position.x = 0.0
	relief._refresh_placement()
	var reversed := false
	for id: Variant in retiring_ids:
		if mid_retirement.has(id) and relief._residents.has(id) and relief._residents[id].desired:
			check(is_equal_approx(relief._residents[id].strength, mid_retirement[id].strength), "Reverse movement preserves intermediate strength")
			reversed = true
	check(reversed, "Returning movement cancels an in-progress retirement")
	advance(relief, 0.6)
	var before_teleport := snapshot(relief)
	player.position.x = 30.0
	relief._refresh_placement()
	for id: Variant in before_teleport:
		if before_teleport[id].strength > 0.01:
			check(relief._residents.has(id), "Saturation never steals a still-raised outgoing resident")
	check_budget(relief)
	advance(relief, 0.025)
	check_budget(relief)
	check(relief.stats.triangles > 196608, "Teleport exercises overlapping incoming and retiring geometry")
	advance(relief, 0.775)
	# Retry pending admissions at the same block: no extra player movement required.
	relief._process(0.025)
	advance(relief, 0.6)
	check_budget(relief)
	var new_region_faces := 0
	for descriptor: Dictionary in relief._residents.values():
		if descriptor.desired and descriptor.center.x > 20:
			new_region_faces += 1
	check(new_region_faces >= 200, "Deferred admissions fill the new region after retirees flatten")
	check(relief.stats.mesh_builds == builds, "Movement, retirement and teleport never rebuild shared geometry")
	for child in relief.get_children():
		check(child is MultiMeshInstance3D, "No transition creates collision bodies or per-face nodes")
	print("RELIEF_TRANSITIONS_RESULT failures=", failures, " stats=", relief.stats)
	quit(1 if failures else 0)
