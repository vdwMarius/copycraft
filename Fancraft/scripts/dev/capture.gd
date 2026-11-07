extends Node
## Dev capture: run the game with `-- --capture` (needs a display, e.g. xvfb-run); saves screenshots to build/.
## Also exercises building: places a few pieces in front of the player.

func _ready() -> void:
	var main: Node = get_parent()
	var root := get_tree().root
	var process_frame := get_tree().process_frame
	var t := 0
	while not main.player.controls_enabled and t < 3000:
		await process_frame
		t += 1
		if t % 100 == 0: print("frame ", t, " ", main.world.stats, " bodies ", main.world.bodies.size())
	print("spawned after frames: ", t, " stats ", main.world.stats)
	for i in 120:
		await process_frame
	var p: Player = main.player
	Settings.set_value("render_distance", 4, false)
	Settings.set_value("texture_resolution", 256, false)
	Settings.set_value("parallax", 2, false)
	await Textures.textures_changed
	# Eye-level landscape towards the horizon.
	p.toggle_fly()
	p.global_position += Vector3(0, 3, 0)
	p.global_position += Vector3(0, 5, 0)
	p.rotation.y = 2.2
	p.look(Vector2(0, -60))
	for i in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shot_horizon.png")
	p.global_position += Vector3(0, 6, 0)
	p.rotation.y = 0.6
	p.look(Vector2(0, 120))
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shot_world.png")
	# Build a little structure out of mixed pieces right in front of the player.
	var b: Builder = main.builder
	var fwd := -p.global_transform.basis.z
	var base := (p.global_position + Vector3(fwd.x, 0, fwd.z).normalized() * 9.0).floor()
	var gy := floorf(main.world.surface_height(base.x, base.z) * 4.0)
	var q := Vector3(base.x * 4.0, gy, base.z * 4.0)
	var ids := [16, 7, 11, 9, 14]
	main.world.edit_box(AABB(q, Vector3(8, 2, 8)), 16)          # marble slab floor (half height)
	main.world.edit_box(AABB(q + Vector3(0, 2, 0), Vector3(2, 8, 2)), 7)    # pillar
	main.world.edit_box(AABB(q + Vector3(6, 2, 6), Vector3(2, 8, 2)), 7)
	main.world.edit_box(AABB(q + Vector3(1, 10, 1), Vector3(7, 2, 7)), 11)  # offset brick roof slab
	main.world.edit_box(AABB(q + Vector3(3, 2, 3), Vector3(2, 2, 2)), 14)   # half-cube crystal
	main.world.edit_box(AABB(q + Vector3(2, 2, 6), Vector3(4, 4, 1)), 9)    # glass panel
	for i in 30:
		await process_frame
	var look_at_pos := q / 4.0 + Vector3(1, 1, 1)
	p.global_position = look_at_pos + Vector3(3.5, 1.8, 3.5)
	var ground: float = main.world.surface_height(p.global_position.x, p.global_position.z)
	p.global_position.y = maxf(p.global_position.y, ground + 2.5)   # never film from inside a hill
	p.look_at_from_position(p.global_position, Vector3(look_at_pos.x, p.global_position.y, look_at_pos.z))
	p.camera.rotation.x = -0.35
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shot_build.png")
	# --- edit latency: frames until the edited chunk's new mesh is on screen
	var w: VoxelWorld = main.world
	var lat := []
	for k in 5:
		var spot := q + Vector3(12 + k * 2, 2, 0)
		var c := Vector3i((spot / 64.0).floor())
		w.edit_box(AABB(spot, Vector3(2, 2, 2)), 11)
		var want: int = w.versions.get(c, 0)
		var f := 0
		while w.applied.get(c, -1) < want and f < 600:
			await process_frame
			f += 1
		lat.append(f)
	print("EDIT_LATENCY_FRAMES ", lat)
	# --- menu: tap the "60" fps button with a simulated finger
	main.hud.open_settings.emit()
	await process_frame
	await process_frame
	var target: Button = null
	for row in main.menus._rows["fps_target"].get_children():
		if row.text == "60":
			target = row
	var before = Settings.get_value("fps_target")
	var pos := target.get_global_rect().get_center()
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = pos
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var ev2 := ev.duplicate()
	ev2.pressed = false
	Input.parse_input_event(ev2)
	await process_frame
	await process_frame
	print("MENU_TAP fps_target before=", before, " after=", Settings.get_value("fps_target"), " pressed=", target.button_pressed)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shot_menu.png")
	Settings.set_value("fps_target", before)
	print("CAPTURE fps=", Engine.get_frames_per_second(), " stats=", main.world.stats, " ghost target=", not b._target.is_empty())
	get_tree().quit()
