extends SceneTree
## Display-only art review: renders every prop variant (detail 0/1/2) and every
## building part in both materials to build/props.png and build/parts.png.
## xvfb-run -a -s "-screen 0 1280x720x24" tools/godot.sh --rendering-driver opengl3 --script res://tests/props_capture.gd

func _initialize() -> void:
	_run.call_deferred()


func _env(sky_top := Color(0.35, 0.6, 0.9)) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.8, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.68, 0.8)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -32, 0)
	sun.light_color = Color(1.0, 0.9, 0.74)
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.5, 0.72, 0.3)
	ground.material_override = gm
	root.add_child(ground)


func _add(mesh: Mesh, pos: Vector3, mats: Array, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	for i in mats.size():
		mi.set_surface_override_material(i, mats[i])
	parent.add_child(mi)
	return mi


func _tris(mesh: ArrayMesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		n += mesh.surface_get_array_len(s) / 3
	return n


func _shot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _run() -> void:
	var lib: Node = root.get_node_or_null("Textures")
	if lib and lib.has_method("_build"):
		await lib._build("fancraft_default", 128)
	PropMeshes.refresh_textures()
	PartMeshes.refresh_textures()
	_env()
	var scene := Node3D.new()
	root.add_child(scene)
	var bark := PropMeshes.bark_material()
	var fol := PropMeshes.foliage_material()
	var rock_m := PropMeshes.rock_material()
	var grass_m := PropMeshes.grass_material()
	var report := []
	# Row of trees at the three detail levels.
	for d in 3:
		for v in 3:
			var m := PropMeshes.tree_broadleaf(v, d)
			_add(m, Vector3(v * 7.0 - 20.0, 0, -d * 9.0), [bark, fol], scene)
			if v == 0: report.append("broadleaf d%d: %d tris" % [d, _tris(m)])
		for v in 2:
			var m := PropMeshes.tree_pine(v, d)
			_add(m, Vector3(4.0 + v * 6.0, 0, -d * 9.0), [bark, fol], scene)
			if v == 0: report.append("pine d%d: %d tris" % [d, _tris(m)])
		for v in 3:
			var m := PropMeshes.bush(v, d)
			_add(m, Vector3(-20.0 + v * 2.6, 0, 5.0 - d * 9.0), [fol], scene)
			if v == 0: report.append("bush d%d: %d tris" % [d, _tris(m)])
		for v in 3:
			var m := PropMeshes.rock(v, d)
			_add(m, Vector3(-10.0 + v * 2.6, 0, 5.0 - d * 9.0), [rock_m], scene)
			if v == 0: report.append("rock d%d: %d tris" % [d, _tris(m)])
	# A grass and flower patch.
	for i in 140:
		var g: Mesh = PropMeshes.grass_tuft(i % 4) if i % 7 != 0 else PropMeshes.flower_tuft(i % 4)
		var p := Vector3(randf_range(0.0, 9.0), 0, randf_range(1.5, 7.5))
		var mi := _add(g, p, [grass_m], scene)
		mi.rotation.y = randf() * TAU
	report.append("grass: %d tris, flowers: %d tris" % [_tris(PropMeshes.grass_tuft(0)), _tris(PropMeshes.flower_tuft(0))])
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.fov = 60
	cam.look_at_from_position(Vector3(-3, 9, 19), Vector3(-3, 2.5, -6))
	await _shot("res://build/props.png")
	# Close-up of near-detail props.
	cam.look_at_from_position(Vector3(-6, 4.5, 13), Vector3(-6, 3.0, 0))
	await _shot("res://build/props_close.png")
	scene.queue_free()
	# Parts: both materials, a little hut per material plus a lineup.
	var parts := Node3D.new()
	root.add_child(parts)
	var x := -14.0
	for mat in ["wood", "stone"]:
		var pm := PartMeshes.material(mat)
		for id in Parts.ORDER:
			var m := PartMeshes.mesh(id, mat)
			_add(m, Vector3(x, 0.8, 0 if mat == "wood" else 4.0), [pm], parts)
			if mat == "wood":
				report.append("part %s: %d tris" % [id, _tris(m)])
			x += 2.8
		x = -14.0
	for mat in ["wood", "stone"]:
		var pm := PartMeshes.material(mat)
		var o := Vector3(-6.0 if mat == "wood" else 2.0, 0.8, -8.0)
		_add(PartMeshes.mesh("foundation", mat), o, [pm], parts)
		_add(PartMeshes.mesh("foundation", mat), o + Vector3(2, 0, 0), [pm], parts)
		_add(PartMeshes.mesh("wall", mat), o + Vector3(1, 0, -1) + Vector3(-1, 0, 0), [pm], parts)
		_add(PartMeshes.mesh("window", mat), o + Vector3(2, 0, -1), [pm], parts)
		var door := _add(PartMeshes.mesh("doorway", mat), o + Vector3(0, 0, 1), [pm], parts)
		door.rotation.y = 0
		_add(PartMeshes.mesh("wall", mat), o + Vector3(2, 0, 1), [pm], parts)
		var side := _add(PartMeshes.mesh("wall", mat), o + Vector3(-1, 0, 0), [pm], parts)
		side.rotation.y = PI * 0.5
		var side2 := _add(PartMeshes.mesh("half_wall", mat), o + Vector3(3, 0, 0), [pm], parts)
		side2.rotation.y = PI * 0.5
		_add(PartMeshes.mesh("roof", mat), o + Vector3(0, 2.4, 0), [pm], parts)
		_add(PartMeshes.mesh("roof", mat), o + Vector3(2, 2.4, 0), [pm], parts)
		var st := _add(PartMeshes.mesh("stairs", mat), o + Vector3(1, 0, 3.0), [pm], parts)
		st.rotation.y = PI
	var cam2 := cam
	cam2.look_at_from_position(Vector3(-1, 6, 13), Vector3(-1, 1.2, -2))
	await _shot("res://build/parts.png")
	cam2.look_at_from_position(Vector3(-2, 3.5, 2.5), Vector3(-2, 1.5, -8))
	await _shot("res://build/parts_huts.png")
	for line in report:
		print(line)
	quit()
