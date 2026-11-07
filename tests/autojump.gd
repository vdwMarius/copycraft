extends SceneTree
var failures := 0
var scenarios_completed := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1
func box(parent: Node3D, at: Vector3, dimensions: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.position = at
	body.add_child(collider)
	parent.add_child(body)
func _initialize() -> void:
	call_deferred("run")
func scenario(height: float, ceiling: bool, expected_jump: bool) -> void:
	var world := Node3D.new()
	root.add_child(world)
	box(world, Vector3(0,-0.5,0), Vector3(20,1,20))
	box(world, Vector3(1.5,height / 2.0,0), Vector3(1,height,3))
	if ceiling:
		box(world, Vector3(0,2.6,0), Vector3(10,0.2,10))
	var player = load("res://scripts/player.gd").new()
	world.add_child(player)
	player.position = Vector3(0,0.01,0)
	for i in range(20):
		await physics_frame
	check(not player._can_auto_jump(Vector3.ZERO), "Idle must not auto jump")
	player.move_input = Vector2(1,0)
	var jumped := false
	var maximum_x := 0.0
	for i in range(75):
		await physics_frame
		jumped = jumped or player.velocity.y > 1.0
		maximum_x = maxf(maximum_x, player.position.x)
	check(jumped == expected_jump, "Auto jump height=%s ceiling=%s expected=%s actual=%s" % [height,ceiling,expected_jump,jumped])
	if expected_jump:
		check(maximum_x > 2.4, "Player must clear one-block obstacle")
	else:
		check(maximum_x < 1.0, "Player must stay blocked")
	scenarios_completed += 1
	world.queue_free()
	await physics_frame
func run() -> void:
	await scenario(1.0, false, true)
	await scenario(2.0, false, false)
	await scenario(1.0, true, false)
	check(scenarios_completed == 3, "All auto-jump scenarios must complete")
	print("AUTOJUMP_RESULT failures=", failures)
	quit(1 if failures else 0)
