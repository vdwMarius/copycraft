extends CharacterBody3D
## First-person controller. HUD owns touch IDs and supplies movement/look requests.

const AUTO_JUMP_HEIGHT := 1.05
const JUMP_SPEED := 8.2
const GRAVITY := 24.0

var camera: Camera3D
var move_input := Vector2.ZERO
var walk_speed := 6.0
var look_sensitivity := 0.0025
var _pitch := -0.08
var _jump_buffer := 0.0
var _floor_grace := 0.0
var _focused := true


func _ready() -> void:
	name = "Explorer"
	position = Vector3(0, 12, 8)
	floor_snap_length = 0.3
	floor_stop_on_slope = true
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.8
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.9
	add_child(collider)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.position.y = 1.62
	camera.rotation.x = _pitch
	camera.fov = 76.0
	camera.near = 0.08
	camera.far = 512.0
	camera.current = true
	add_child(camera)
	if not DisplayServer.is_touchscreen_available() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func look_delta(pixel_delta: Vector2) -> void:
	if not _focused or not is_instance_valid(camera):
		return
	rotate_y(-pixel_delta.x * look_sensitivity)
	_pitch = clampf(_pitch - pixel_delta.y * look_sensitivity, -1.48, 1.48)
	camera.rotation.x = _pitch


func request_jump() -> void:
	if _focused:
		_jump_buffer = 0.14


func clear_input() -> void:
	move_input = Vector2.ZERO
	_jump_buffer = 0.0
	velocity.x = 0.0
	velocity.z = 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_focused = false
		clear_input()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		_focused = true


func _unhandled_input(event: InputEvent) -> void:
	if not _focused:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_SPACE:
			request_jump()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			look_delta(event.relative)


func _physics_process(delta: float) -> void:
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	_floor_grace = 0.12 if is_on_floor() else maxf(0.0, _floor_grace - delta)
	var direction := move_input
	if _focused:
		direction += Vector2(
			float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	else:
		direction = Vector2.ZERO
	direction = direction.limit_length(1.0)
	var world_direction := transform.basis * Vector3(direction.x, 0.0, direction.y)
	var speed := walk_speed
	if _focused and Input.is_physical_key_pressed(KEY_SHIFT):
		speed *= 1.5
	velocity.x = move_toward(velocity.x, world_direction.x * speed, 32.0 * delta)
	velocity.z = move_toward(velocity.z, world_direction.z * speed, 32.0 * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var auto_jump := is_on_floor() and _can_auto_jump(world_direction)
	if (_jump_buffer > 0.0 and _floor_grace > 0.0) or auto_jump:
		velocity.y = JUMP_SPEED
		_jump_buffer = 0.0
		_floor_grace = 0.0
	move_and_slide()
	if position.y < -70.0:
		position = Vector3(0, 12, 8)
		velocity = Vector3.ZERO


func _can_auto_jump(direction: Vector3) -> bool:
	# Sweep the player's capsule, rather than a ray that could miss shoulders.
	if not _focused or direction.length_squared() < 0.04:
		return false
	var forward := direction.normalized() * 0.6
	var obstacle := KinematicCollision3D.new()
	if not test_move(global_transform, forward, obstacle):
		return false
	if obstacle.get_normal().dot(direction.normalized()) > -0.5:
		return false
	# Refuse tall walls and low ceilings, including the full jump's headroom.
	var clearance := Vector3.UP * (JUMP_SPEED * JUMP_SPEED / (2.0 * GRAVITY) + 0.03)
	if test_move(global_transform, clearance):
		return false
	var apex := global_transform
	apex.origin += clearance
	if test_move(apex, forward):
		return false
	var raised := global_transform
	raised.origin.y += AUTO_JUMP_HEIGHT
	if test_move(raised, forward):
		return false
	raised.origin += forward
	var landing := KinematicCollision3D.new()
	if not test_move(raised, Vector3.DOWN * (AUTO_JUMP_HEIGHT + 0.05), landing):
		return false
	var rise := AUTO_JUMP_HEIGHT + landing.get_travel().y
	return rise > 0.15 and rise <= AUTO_JUMP_HEIGHT and landing.get_normal().y > 0.7
