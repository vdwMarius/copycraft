extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.player.position = Vector3(0,6.01,8)
	var collision: Node = scene.terrain.terrain_instance.get_child(0)
	var original_shape: Shape3D = collision.get_child(0).shape
	for resolution in [16,64,128]:
		for grid in [1,4,8]:
			for raised in [false,true]:
				scene._apply_material_settings(grid,resolution,raised,false)
				check(scene.surface_material.get_shader_parameter("grid_size") == float(grid), "Grid applies to world material")
				check(scene.surface_pack.resolution == resolution, "Texture resolution applies to active pack")
				check(scene.surface_material.get_shader_parameter("relief_enabled") == raised, "Relief shader flag follows toggle")
				check(scene.terrain.terrain_instance.material_override == scene.surface_material, "Terrain uses active material")
				for instance in scene.terrain.details.instances:
					check(instance.material_override == scene.surface_material, "Trees and details use same active pack")
				var stats: Dictionary = scene.relief_layer.stats
				check(stats.patches > 0 if raised else stats.patches == 0, "Relief geometry follows toggle")
				check(stats.triangles <= 294912 and stats.pool == 384 and stats.patches <= 256, "Batched transition residency remains bounded across switches")
				check(scene.relief_layer._batches.size() == 9, "Material choices retain nine relief batches")
				check(collision.get_child(0).shape == original_shape, "Changing appearance preserves terrain collider")
	check(scene._pack_cache.size() == 3, "Only three resolution packs retained")
	var cached: RefCounted = scene._pack_cache[64]
	scene._apply_material_settings(4,64,true,false)
	check(scene.surface_pack == cached, "Returning to resolution reuses texture pack")
	print("MATERIAL_INTEGRATION_RESULT failures=",failures, " relief=",scene.relief_layer.stats)
	quit(1 if failures else 0)
