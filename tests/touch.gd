extends SceneTree
## Run with tools/godot.sh --headless --script res://tests/touch.gd.
var failures := 0


func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1


func touch(hud: Control, id: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = id
	event.position = point
	event.pressed = pressed
	hud._input(event)


func drag(hud: Control, id: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = id
	event.position = point
	hud._input(event)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var hud = scene.hud
	var player = scene.player
	# Headless windows can be 64 px; explicitly exercise two landscape canvas sizes.
	for canvas_size in [Vector2(1280, 720), Vector2(1920, 1080)]:
		hud.size = canvas_size
		hud._update_layout()
		var center: Vector2 = hud._joy_center
		var radius: float = hud.JOYSTICK_RADIUS * hud._scale
		var outside := center + Vector2(radius + 1.0, 0)
		touch(hud, 2, outside, true)
		check(hud._joystick_id == -1 and hud._look_id == -1 and player.move_input == Vector2.ZERO, "Touch beyond visible joystick must leave left world area available")
		drag(hud, 2, center)
		check(hud._joystick_id == -1 and player.move_input == Vector2.ZERO, "Outside contact must not acquire joystick by dragging inside")
		touch(hud, 2, center, false)
		var old_activation_area := Vector2(canvas_size.x * 0.3, canvas_size.y * 0.5)
		touch(hud, 3, old_activation_area, true)
		check(hud._joystick_id == -1 and hud._look_id == -1, "Former broad left activation area must not capture movement or look")
		touch(hud, 3, old_activation_area, false)
		touch(hud, 4, center + Vector2(radius, 0), true)
		check(hud._joystick_id == 4 and player.move_input.x > 0.9, "Visible disc edge must activate joystick")
		var beyond := center + Vector2(0, -radius * 4)
		drag(hud, 4, beyond)
		check(hud._joystick_id == 4 and player.move_input.y < -0.9 and player.move_input.length() <= 1.001, "Captured contact must retain bounded movement beyond disc")
		touch(hud, 5, center, true)
		check(hud._joystick_id == 4, "Second contact must not steal active joystick")
		touch(hud, 5, center, false)
		check(hud._joystick_id == 4, "Unowned contact release must preserve active joystick")
		touch(hud, 4, beyond, false)
		check(hud._joystick_id == -1 and player.move_input == Vector2.ZERO, "Release outside disc must clear movement")
		touch(hud, 6, center, true)
		check(hud._joystick_id == 6 and player.move_input == Vector2.ZERO, "Disc center must activate with neutral movement")
		touch(hud, 6, center, false)
	print("TOUCH_RESULT failures=", failures)
	quit(1 if failures else 0)
