extends SceneTree

var failures := 0


func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1


func _initialize() -> void:
	call_deferred("run")


func elevation(_x: int, _z: int) -> int:
	return 5


func run() -> void:
	var details = load("res://scripts/micro_details.gd").new()
	root.add_child(details)
	var stats: Dictionary = details.populate(elevation)
	check(stats.meshes == 4, "Exactly four reusable native mesh variants")
	check(stats.instances > 5 and stats.instances <= details.MAX_INSTANCES, "Trees and bounded ground patches populated")
	check(stats.triangles > 0 and stats.unique_triangles > 0, "Native meshes contain actual triangles")
	var actual_triangles := 0
	var used_meshes: Dictionary = {}
	for instance in details.instances:
		check(instance.mesh.get_surface_count() > 0, "Every prop has native geometry")
		check(instance.scale.is_equal_approx(Vector3.ONE * 0.25), "Quarter-unit geometry scale")
		check(instance.visibility_range_end >= 36 and instance.visibility_range_end <= 48, "Detail visibility remains bounded")
		used_meshes[instance.mesh.get_instance_id()] = true
		actual_triangles += instance.mesh.get_faces().size() / 3
		var bounds: AABB = instance.mesh.get_aabb()
		var world_bounds := AABB(bounds.position * instance.scale + instance.position, bounds.size * instance.scale)
		if instance.name.begins_with("Tree"):
			check(world_bounds.size.y > 7.0 and world_bounds.size.y < 9.0, "Full tree scaled height is plausible")
			check(world_bounds.size.x > 4.0 and world_bounds.size.x < 7.0, "Quarter-voxel crown scaled width")
		else:
			check(is_equal_approx(world_bounds.size.y, 0.25), "Ground detail remains one quarter-unit high")
			check(world_bounds.size.x <= 2.0 and world_bounds.size.z <= 2.0, "Ground patches retain bounded footprints")
			var intersects_spawn := world_bounds.position.x < 8 and world_bounds.end.x > -8 and world_bounds.position.z < 16 and world_bounds.end.z > -16
			check(not intersects_spawn, "Ground details exclude the flat spawn area")
	check(used_meshes.size() == 4 and details.instances.size() > used_meshes.size(), "Instances reuse mesh resources")
	check(actual_triangles == stats.triangles, "Reported triangles agree with instantiated mesh faces")
	check(details.trunk_colliders.size() == 5, "Only five coarse trunk colliders")
	for i in range(details.trunk_colliders.size()):
		var body: StaticBody3D = details.trunk_colliders[i]
		var point: Vector2i = details.TREE_POINTS[i]
		check(body.position.is_equal_approx(Vector3(point.x + 0.5, 8.5, point.y + 0.5)), "Trunk collider anchored at original block base")
		check(body.get_child(0).shape.size == Vector3(1, 5, 1), "Trunk collision stays coarse")
	check(details.get_child_count() == stats.instances + stats.collisions, "No per-voxel nodes or cosmetic collision bodies")
	var repeated: Dictionary = details.populate(elevation)
	check(repeated == stats and details.get_child_count() == stats.instances + stats.collisions, "Repopulation replaces rather than accumulating props")
	await process_frame
	print("MICRO_DETAILS_RESULT failures=", failures, " stats=", stats)
	quit(1 if failures else 0)
