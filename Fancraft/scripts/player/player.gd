class_name Player
extends CharacterBody3D
## First-person controller with step-up onto slabs/quarter steps, auto-jump onto
## full blocks, swimming and a creative fly mode. Touch input arrives from the HUD.

const GRAVITY := 26.0
const JUMP_SPEED := 8.4
const WALK_SPEED := 4.3      # Minecraft-like pacing (m/s)
const SPRINT_SPEED := 5.6
const FLY_SPEED := 10.9
const STEP_HEIGHT := 0.55
const EYE_HEIGHT := 1.6

var world: VoxelWorld
var terrain: SmoothTerrain
var camera: Camera3D
var move_input := Vector2.ZERO      # x = strafe, y = forward (-1..1)
var jump_held := false
var down_held := false
var sprint := false
var flying := false
var controls_enabled := true
var _pitch := -0.15
var _cam_offset := 0.0               # smooths the camera after stepping up
var _in_water := false


func _ready() -> void:
	floor_snap_length = 0.25
	floor_max_angle = deg_to_rad(50)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.75
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.875
	add_child(col)
	camera = Camera3D.new()
	camera.position.y = EYE_HEIGHT
	camera.fov = 78.0
	camera.near = 0.05
	camera.far = 600.0
	camera.current = true
	add_child(camera)
	camera.rotation.x = _pitch


func look(delta_px: Vector2) -> void:
	if not controls_enabled:
		return
	var s: float = 0.0032 * float(Settings.get_value("look_sensitivity"))
	rotate_y(-delta_px.x * s)
	_pitch = clampf(_pitch - delta_px.y * s, -1.52, 1.52)
	camera.rotation.x = _pitch


func toggle_fly() -> void:
	flying = not flying
	velocity = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(event.relative)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F:
				toggle_fly()
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED


func _keyboard_input() -> Vector2:
	var v := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)))
	return v


func _physics_process(delta: float) -> void:
	if not controls_enabled:
		return
	var input := move_input
	var kb := _keyboard_input()
	if kb != Vector2.ZERO:
		input = kb.normalized()
	var jump := jump_held or Input.is_physical_key_pressed(KEY_SPACE)
	var down := down_held or Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_CTRL)
	var running := sprint or Input.is_physical_key_pressed(KEY_SHIFT)
	var basis_flat := Basis(Vector3.UP, rotation.y)
	var wish := basis_flat * Vector3(input.x, 0, -input.y)
	_in_water = global_position.y + 0.9 < TerrainShape.WATER_LEVEL

	if flying:
		var speed := FLY_SPEED * (1.6 if running else 1.0)
		var vert := (1.0 if jump else 0.0) - (1.0 if down else 0.0)
		var target := wish * speed + Vector3.UP * vert * speed * 0.8
		velocity = velocity.lerp(target, clampf(delta * 10.0, 0.0, 1.0))
		move_and_slide()
		_settle_camera(delta)
		return

	var speed := SPRINT_SPEED if running else WALK_SPEED
	if _in_water:
		speed *= 0.55
	var accel := 14.0 if is_on_floor() else 4.0
	var hv := Vector3(velocity.x, 0, velocity.z).lerp(wish * speed, clampf(delta * accel, 0.0, 1.0))
	velocity.x = hv.x
	velocity.z = hv.z
	if _in_water:
		velocity.y = move_toward(velocity.y, 3.2 if jump else -2.0, delta * 18.0)
	else:
		velocity.y -= GRAVITY * delta
		if jump and is_on_floor():
			velocity.y = JUMP_SPEED
	var pre_vel := velocity
	move_and_slide()
	# Blocked by a low obstacle while walking: try stepping up, else auto-jump.
	if is_on_floor() and is_on_wall() and wish.length() > 0.1:
		var horiz := Vector3(pre_vel.x, 0, pre_vel.z)
		if not _try_step(horiz * delta + horiz.normalized() * 0.05):
			if _can_rise(1.1, horiz.normalized() * 0.4):
				velocity.y = JUMP_SPEED * 0.92
	_settle_camera(delta)
	if global_position.y < -20.0 and terrain:
		global_position.y = terrain.height_at(global_position.x, global_position.z) + 3.0
		velocity = Vector3.ZERO


func _try_step(motion: Vector3) -> bool:
	if motion.length() < 0.0005:
		return false
	var up := Vector3.UP * STEP_HEIGHT
	var t := global_transform
	if test_move(t, up):
		return false
	var raised := t.translated(up)
	if test_move(raised, motion):
		return false
	var moved := raised.translated(motion)
	var col := KinematicCollision3D.new()
	if not test_move(moved, -up, col):
		return false
	if col.get_normal().y < 0.7:
		return false
	var final := moved.translated(col.get_travel())
	var rise := final.origin.y - t.origin.y
	if rise <= 0.01:
		return false
	global_transform = final
	_cam_offset -= rise
	return true


func _can_rise(height: float, ahead: Vector3) -> bool:
	var up := Vector3.UP * height
	if test_move(global_transform, up):
		return false
	return not test_move(global_transform.translated(up), ahead)


func _settle_camera(delta: float) -> void:
	_cam_offset = move_toward(_cam_offset, 0.0, delta * 4.0)
	camera.position.y = EYE_HEIGHT + _cam_offset


func eye_ray() -> Array:
	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	return [origin, dir]
