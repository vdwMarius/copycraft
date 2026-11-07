extends Node
## Dev capture: run the game with `-- --capture` (needs a display, e.g. xvfb-run).
## Saves screenshots to build/: landscape, a small built house, and the menu test.

func _ready() -> void:
	var main: Node = get_parent()
	var root := get_tree().root
	var process_frame := get_tree().process_frame
	var t := 0
	while not main.player.controls_enabled and t < 100000:
		await process_frame
		t += 1
	print("spawned after frames: ", t)
	var p: Player = main.player
	Settings.set_value("render_distance", 6, false)
	Settings.set_value("texture_resolution", 256, false)
	await Textures.textures_changed
	p.toggle_fly()
	p.global_position += Vector3(0, 6, 0)
	p.rotation.y = 2.2
	p.look(Vector2(0, -40))
	for i in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shot_horizon.png")
	# A small house: 2x2 foundations, walls with a doorway and window, roof.
	var bs: BuildSystem = main.building
	var gx := floorf(p.global_position.x / 2.0) * 2.0 + 8.0
	var gz := floorf(p.global_position.z / 2.0) * 2.0
	var lvl: float = snappedf(main.terrain.height_at(gx + 2.0, gz + 2.0), 0.25) + 0.3
	for cx in 2:
		for cz in 2:
			_part(bs, "foundation", "stone", Vector3(gx + cx * 2 + 1, lvl, gz + cz * 2 + 1), 0.0, "f%d%d" % [cx, cz])
	var walls := [["wall", Vector3(gx + 1, lvl, gz), 0.0], ["doorway", Vector3(gx + 3, lvl, gz), 0.0],
		["wall", Vector3(gx + 1, lvl, gz + 4), 0.0], ["window", Vector3(gx + 3, lvl, gz + 4), 0.0],
		["wall", Vector3(gx, lvl, gz + 1), PI / 2], ["window", Vector3(gx, lvl, gz + 3), PI / 2],
		["wall", Vector3(gx + 4, lvl, gz + 1), PI / 2], ["wall", Vector3(gx + 4, lvl, gz + 3), PI / 2]]
	for i in walls.size():
		_part(bs, walls[i][0], "wood", walls[i][1], walls[i][2], "w%d" % i)
	for cx in 2:
		_part(bs, "roof", "wood", Vector3(gx + cx * 2 + 1, lvl + 2.4, gz + 1), PI, "r0%d" % cx)
		_part(bs, "roof", "wood", Vector3(gx + cx * 2 + 1, lvl + 2.4, gz + 3), 0.0, "r1%d" % cx)
	_part(bs, "stairs", "stone", Vector3(gx + 1, lvl - 2.4, gz - 3), 0.0, "s")
	p.global_position = Vector3(gx - 4.5, lvl + 2.5, gz - 5.5)
	p.look_at_from_position(p.global_position, Vector3(gx + 2, p.global_position.y, gz + 2))
	p.camera.rotation.x = -0.25
	for i in 60:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shot_build.png")
	# Pickup feed + bag screen.
	for pair in [["wood", 14], ["stone", 9], ["fiber", 3], ["berries", 2], ["dirt", 22], ["flint", 1]]:
		main.inventory.add(pair[0], pair[1])
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shot_feed.png")
	main.hud.open_bag.emit()
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shot_bag.png")
	main.menus.close_menu()
	# Menu: tap the "60" fps button with a simulated finger.
	main.hud.open_settings.emit()
	await process_frame
	await process_frame
	var target: Button = null
	for row in main.menus._rows["fps_target"].get_children():
		if row.text == "60":
			target = row
	var before = Settings.get_value("fps_target")
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = target.get_global_rect().get_center()
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var ev2 := ev.duplicate()
	ev2.pressed = false
	Input.parse_input_event(ev2)
	await process_frame
	print("MENU_TAP fps_target before=", before, " after=", Settings.get_value("fps_target"))
	Settings.set_value("fps_target", before)
	print("CAPTURE fps=", Engine.get_frames_per_second(), " parts=", bs.parts.size())
	get_tree().quit()


func _part(bs: BuildSystem, id: String, mat: String, pos: Vector3, yaw: float, slot: String) -> void:
	bs._spawn({"id": id, "mat": mat, "transform": Transform3D(Basis(Vector3.UP, yaw), pos), "slot": slot})
