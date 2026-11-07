extends Node
## Dev/regression: `-- --inputtest` (works headless). Simulates a finger: hold to break,
## tap to place. Prints INPUT_TEST_RESULT failures=N and quits.

func _ready() -> void:
	var main: Node = get_parent()
	var tree := get_tree()
	var t := 0
	while not main.player.controls_enabled and t < 3000:
		await tree.process_frame
		t += 1
	for i in 30:
		await tree.physics_frame
	var p: Player = main.player
	p.camera.rotation.x = -0.7   # look at the ground a few blocks ahead
	p._pitch = -0.7
	await tree.physics_frame
	await tree.process_frame
	var w: VoxelWorld = main.world
	var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var b: Builder = main.builder
	print("target at centre: ", b.has_target_at_screen(centre), " player at ", p.global_position)
	var failures := 0
	var before := _edits(w)
	_touch(3, centre, true)
	await tree.process_frame
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1300:
		await tree.process_frame
	_touch(3, centre, false)
	await tree.process_frame
	var after_hold := _edits(w)
	if after_hold - before < 1:
		failures += 1
		printerr("FAIL: holding did not break anything")
	# Let the broken blocks' meshes and collision land (a real re-tap takes >100 ms).
	for i in 20:
		await tree.physics_frame
	var cam := p.camera
	var tg := b.raycast(cam.project_ray_origin(centre), cam.project_ray_normal(centre))
	print("tap target ", tg, " box ", b.current_box(tg) if not tg.is_empty() else null, " player ", p.global_position, " block ", b.block_id)
	_touch(4, centre, true)
	await tree.process_frame
	_touch(4, centre, false)
	await tree.process_frame
	var after_tap := _edits(w)
	if after_tap - after_hold < 1:
		failures += 1
		printerr("FAIL: tapping did not place")
	# A quick tap must never break; a hold must never place.
	print("hold edits=", after_hold - before, " tap edits=", after_tap - after_hold)
	print("INPUT_TEST_RESULT failures=%d" % failures)
	tree.quit(1 if failures else 0)


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	# Injected events are in window pixels; convert from viewport coordinates.
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = get_viewport().get_final_transform() * pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _edits(w: VoxelWorld) -> int:
	var n := 0
	for k in w.versions:
		n += w.versions[k]
	return n
