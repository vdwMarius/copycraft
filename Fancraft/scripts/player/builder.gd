class_name Builder
extends Node3D
## Targets surfaces under the crosshair (or a tapped screen point) and places or
## removes building pieces at quarter-block precision.

signal changed

const REACH := 9.0
## Hotbar id of the terrain tool: tap raises ground, hold digs.
const TERRAIN_TOOL := -2
const DIG_RADIUS := 1.25
const RAISE_RADIUS := 1.15
const DIG_TIME := 0.22            # seconds per dig pulse while holding

var world: VoxelWorld
var terrain: SmoothTerrain
var player: Player
var block_id := 7
var piece := 0
var rotation_index := 0
var snap_index := 2
var breaking := false
## Screen point to aim at while a finger is held on the view (x < 0: use the crosshair).
var aim_screen := Vector2(-1, -1)

var _target := {}   # {hit, normal} or empty


var _cracks: MeshInstance3D
var _crack_mat: ShaderMaterial


func _ready() -> void:
	_crack_mat = ShaderMaterial.new()
	_crack_mat.shader = load("res://shaders/cracks.gdshader")
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_cracks = MeshInstance3D.new()
	_cracks.mesh = box
	_cracks.material_override = _crack_mat
	_cracks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cracks.visible = false
	add_child(_cracks)


## Show the cracking overlay on a piece (box in world quarter units), progress 0..1.
func show_cracks(box: AABB, progress: float) -> void:
	var size := box.size * 0.25
	_cracks.position = box.position * 0.25 + size * 0.5
	_cracks.scale = size + Vector3.ONE * 0.012
	_crack_mat.set_shader_parameter("progress", progress)
	_cracks.visible = true


func hide_cracks() -> void:
	_cracks.visible = false


func piece_size() -> Vector3i:
	return Pieces.oriented(Pieces.LIST[piece][1], rotation_index)


func snap_step() -> int:
	return Pieces.SNAPS[snap_index][1]


func _process(_delta: float) -> void:
	if player == null or world == null:
		return
	if aim_screen.x >= 0.0:
		var cam := player.camera
		_target = raycast(cam.project_ray_origin(aim_screen), cam.project_ray_normal(aim_screen))
	else:
		var ray := player.eye_ray()
		_target = raycast(ray[0], ray[1])


func raycast(origin: Vector3, dir: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * REACH)
	q.exclude = [player.get_rid()]
	var r := space.intersect_ray(q)
	if r.is_empty():
		return {}
	var n: Vector3 = r.normal
	# Snap the normal to the dominant axis (trimesh normals are exact, but be safe).
	var a := n.abs()
	var raw: Vector3 = r.normal
	if a.x >= a.y and a.x >= a.z:
		n = Vector3(signf(n.x), 0, 0)
	elif a.y >= a.z:
		n = Vector3(0, signf(n.y), 0)
	else:
		n = Vector3(0, 0, signf(n.z))
	var on_terrain := terrain != null and terrain.owns_collider(r.collider)
	return {"hit": r.position, "normal": n, "raw_normal": raw, "terrain": on_terrain}


func current_box(target: Dictionary) -> AABB:
	if breaking:
		return Pieces.break_box(target.hit, target.normal, piece_size(), snap_step())
	return Pieces.place_box(target.hit, target.normal, piece_size(), snap_step())


## Perform the current action at the crosshair (or at an explicit target).
func act(target := {}) -> bool:
	if target.is_empty():
		target = _target
	if target.is_empty():
		return false
	if breaking and target.get("terrain", false):
		terrain.dig(target.hit - target.raw_normal * 0.35, DIG_RADIUS)
		return true
	if not breaking and block_id == TERRAIN_TOOL:
		var c: Vector3 = target.hit + target.raw_normal * 0.55
		if c.distance_to(player.global_position + Vector3.UP * 0.9) < RAISE_RADIUS + 0.75:
			return false   # would bury the player
		terrain.raise(c, RAISE_RADIUS)
		return true
	var box := current_box(target)
	if breaking:
		return world.edit_box(box, 0) > 0
	# On quarter-terraced ground a piece often clips the slightly higher terrain next
	# to it; nudge it out along the surface normal (up to 3 quarters) until it fits.
	var n: Vector3 = target.normal
	for lift in 4:
		var b := box
		b.position += n * lift
		if not world.box_has_solid(b) and not _overlaps_player(b):
			return world.edit_box(b, block_id) > 0
	return false


## Place (tap) or remove (hold) at a screen position.
func place_at_screen(screen_pos: Vector2) -> bool:
	var was := breaking
	breaking = false
	var ok := act_at_screen(screen_pos)
	breaking = was
	return ok


func break_at_screen(screen_pos: Vector2) -> bool:
	var was := breaking
	breaking = true
	var ok := act_at_screen(screen_pos)
	breaking = was
	return ok


## Seconds to break a full block of each material (Minecraft-like feel: soft blocks fast,
## stone and brick slower). Smaller pieces break proportionally faster.
const HARDNESS := {
	"grass": 0.45, "dirt": 0.4, "sand": 0.35, "gravel": 0.4, "snow": 0.2, "leaves": 0.15,
	"glass": 0.25, "stone": 0.75, "cobble": 0.8, "mossy": 0.75, "bricks": 0.8, "slate": 0.8,
	"marble": 0.85, "terracotta": 0.6, "log": 0.6, "planks": 0.55, "crystal": 0.5,
}


## What a hold at `screen_pos` would break: {box, id, time} or {} if nothing.
func break_info_at_screen(screen_pos: Vector2) -> Dictionary:
	var cam := player.camera
	var t := raycast(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))
	if t.is_empty():
		return {}
	if t.get("terrain", false):
		# Smooth ground: dig in quick pulses, no cracks.
		return {"kind": "terrain", "box": AABB(t.hit.snapped(Vector3.ONE * 0.5), Vector3.ONE), "shape": AABB(), "id": 0, "time": DIG_TIME}
	var id := world.get_block_at(t.hit - t.normal * 0.05)
	if id <= 0:
		return {}
	var size := piece_size()
	var volume := float(size.x * size.y * size.z) / 64.0
	var hard: float = HARDNESS.get(Blocks.DEFS[id][0], 0.5)
	var box := Pieces.break_box(t.hit, t.normal, size, snap_step())
	return {
		"kind": "piece",
		"box": box,
		"shape": world.solid_bounds(box),   # what is really there, for the cracks overlay
		"id": id,
		"time": hard * (0.35 + 0.65 * volume),
	}


func has_target_at_screen(screen_pos: Vector2) -> bool:
	var cam := player.camera
	return not raycast(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos)).is_empty()


## Act at a screen position (tap-to-build).
func act_at_screen(screen_pos: Vector2) -> bool:
	var cam := player.camera
	var t := raycast(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))
	return act(t)


func _overlaps_player(box: AABB) -> bool:
	var p := player.global_position
	var body := AABB(Vector3(p.x - 0.3, p.y, p.z - 0.3) * 4.0, Vector3(0.6, 1.75, 0.6) * 4.0)
	return body.intersects(box)


## Eyedropper: select the material under the crosshair.
func pick() -> void:
	if _target.is_empty() or _target.get("terrain", false):
		return
	var inside: Vector3 = _target.hit - _target.normal * 0.05
	var id := world.get_block_at(inside)
	if id > 0:
		block_id = id
		changed.emit()
