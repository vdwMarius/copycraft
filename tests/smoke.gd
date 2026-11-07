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
	for i in range(150):
		await physics_frame
	var player = scene.player
	check(player.is_on_floor(), "Player must land on native terrain collider")
	check(player.position.y > 3.0, "Terrain collision must prevent falling through")
	var initial_y: float = player.position.y
	player.request_jump()
	for i in range(12):
		await physics_frame
	check(player.position.y > initial_y + 0.5, "Jump must lift player off terrain")
	for i in range(100):
		await physics_frame
	var initial: Vector3 = player.position
	player.move_input = Vector2(1,0)
	for i in range(30):
		await physics_frame
	check(player.position.x > initial.x + 1.0, "Movement input must translate player")
	player.clear_input()
	check(player.move_input == Vector2.ZERO, "Clear input must release movement")
	var rotation_before: float = player.rotation.y
	player.look_delta(Vector2(40,20))
	check(player.rotation.y != rotation_before, "Look input must rotate camera")
	check(scene.terrain.voxel_mesh.get_surface_count() > 0, "Native mesher must emit geometry")
	var hud = scene.hud
	hud.size = Vector2(1280,720)
	hud._update_layout()
	var touch := InputEventScreenTouch.new()
	touch.index = 4
	touch.pressed = true
	touch.position = hud._joy_center + Vector2(50,0)
	hud._input(touch)
	check(player.move_input.x > 0.5, "Touch joystick must move player")
	var look := InputEventScreenTouch.new()
	look.index = 8
	look.pressed = true
	look.position = Vector2(900,300)
	hud._input(look)
	check(hud._look_id == 8 and hud._joystick_id == 4, "Touch contacts must be independent")
	touch.pressed = false
	hud._input(touch)
	check(player.move_input == Vector2.ZERO and hud._look_id == 8, "Joystick release must preserve look contact")
	hud._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(hud._look_id == -1, "Focus loss must release contacts")
	print("SMOKE_RESULT failures=", failures, " player=", player.position)
	quit(1 if failures else 0)
