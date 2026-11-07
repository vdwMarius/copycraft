extends SceneTree

var failures := 0
var changes: Array[Array] = []


func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1


func touch(hud: Control, index: int, position: Vector2, pressed: bool = true) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	hud._input(event)


func mouse(hud: Control, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	hud._input(event)


func key(hud: Control, code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	hud._input(event)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var hud = scene.hud
	var player = scene.player
	# Keep UI tests separate from main's persistent material application.
	if hud.material_settings_changed.is_connected(scene._apply_material_settings):
		hud.material_settings_changed.disconnect(scene._apply_material_settings)
	hud.material_settings_changed.connect(func(grid: int, resolution: int, relief: bool) -> void: changes.append([grid, resolution, relief]))
	hud.setup_material_settings(4, 64, true)
	check(changes.is_empty(), "Setup must initialize without emitting changes")
	check(hud.GRID_LABELS == ["1 × 1", "4 × 4 (16)", "8 × 8 (64)"], "Face labels distinguish width from cells per face")
	check(hud.RESOLUTION_LABELS == ["16 × 16", "64 × 64", "128 × 128"], "Texture labels use dimensions")
	for canvas_size in [Vector2(1280, 720), Vector2(1920, 1080)]:
		hud.size = canvas_size
		hud._update_layout()
		hud.setup_material_settings(4, 64, true)
		var opening := hud._materials_button_rect().get_center() as Vector2
		touch(hud, 2, hud._joy_center + Vector2(50, 0) * hud._scale)
		player.request_jump()
		touch(hud, 3, opening)
		check(hud._materials_open, "Materials touch opens panel")
		check(not player.controls_enabled, "Modal disables desktop and touch player controls")
		player.request_jump()
		check(player.move_input == Vector2.ZERO and player._jump_buffer == 0, "Opening clears movement and buffered jump")
		check(hud._joystick_id == -1 and hud._look_id == -1 and hud._jump_id == -1, "Opening clears all contact ownership")
		check(hud._safe_rect.encloses(hud._materials_panel_rect()), "Scaled panel remains inside safe area")
		touch(hud, 4, hud._joy_center)
		touch(hud, 5, hud._jump_center)
		touch(hud, 6, Vector2(canvas_size.x * 0.9, canvas_size.y * 0.5))
		check(hud._joystick_id == -1 and hud._look_id == -1 and hud._jump_id == -1, "Modal contacts never acquire world controls")
		var before: float = player.rotation.y
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(100, 50)
		check(hud._handle_materials_input(motion), "Modal consumes mouse motion")
		var drag := InputEventScreenDrag.new()
		drag.index = 6
		drag.relative = Vector2(100, 50)
		hud._input(drag)
		check(player.rotation.y == before, "Modal drag does not turn camera")
		key(hud, KEY_SPACE)
		check(player._jump_buffer == 0, "Modal Space selects an option without jumping")
		var previous := changes.size()
		touch(hud, 7, hud._material_option_rect(2).get_center())
		check(changes.size() == previous + 1 and changes[-1] == [8, 64, true], "Touch grid choice emits exact state immediately")
		touch(hud, 7, hud._material_option_rect(2).get_center(), false)
		touch(hud, 8, hud._material_option_rect(2).get_center())
		check(changes.size() == previous + 1, "Reselecting active option does not emit duplicate change")
		mouse(hud, hud._material_option_rect(5).get_center())
		check(changes[-1] == [8, 128, true], "Mouse texture choice emits exact state")
		mouse(hud, hud._material_option_rect(6).get_center())
		check(changes[-1] == [8, 128, false], "Raised detail Off emits exact state")
		key(hud, KEY_RIGHT)
		key(hud, KEY_ENTER)
		check(changes[-1] == [8, 128, true], "Keyboard navigation changes raised detail")
		key(hud, KEY_ESCAPE)
		check(not hud._materials_open and hud._look_id == -1 and player.move_input == Vector2.ZERO, "Escape closes and clears input")
		check(player.controls_enabled, "Closing re-enables player controls")
		drag.position = hud._joy_center
		hud._input(drag)
		check(player.move_input == Vector2.ZERO and hud._look_id == -1, "Old contact drag after closing cannot acquire controls")
		key(hud, KEY_M)
		check(hud._materials_open, "M opens modal")
		mouse(hud, hud._material_option_rect(8).get_center())
		check(not hud._materials_open, "Mouse Close dismisses modal")
		mouse(hud, opening)
		check(hud._materials_open, "Mouse Materials opens modal")
		touch(hud, 9, hud._material_option_rect(8).get_center())
		check(not hud._materials_open, "Touch Close dismisses modal")
		touch(hud, 9, hud._material_option_rect(8).get_center(), false)
		touch(hud, 10, hud._joy_center + Vector2(50, 0) * hud._scale)
		check(player.move_input.x > 0.5 and hud._joystick_id == 10, "Joystick works again after modal closes")
		touch(hud, 10, hud._joy_center, false)
	await process_frame
	print("MATERIAL_UI_RESULT failures=", failures)
	quit(1 if failures else 0)
