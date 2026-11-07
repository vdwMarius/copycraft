class_name Builder
extends Node3D
## Targets surfaces under the crosshair (or a tapped screen point) and places or
## removes building pieces at quarter-block precision. Shows a ghost preview.

signal changed

const REACH := 9.0

var world: VoxelWorld
var player: Player
var block_id := 7
var piece := 0
var rotation_index := 0
var snap_index := 1
var breaking := false

var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _edge: MeshInstance3D
var _target := {}   # {hit, normal} or empty


func _ready() -> void:
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.no_depth_test = false
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_ghost = MeshInstance3D.new()
	_ghost.mesh = box
	_ghost.material_override = _ghost_mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)
	_edge = MeshInstance3D.new()
	_edge.mesh = _edge_mesh()
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = Color(1, 1, 1, 0.95)
	em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_edge.material_override = em
	_edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_edge)
	_ghost.visible = false
	_edge.visible = false


static func _edge_mesh() -> ArrayMesh:
	var v := PackedVector3Array()
	var c := [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)]
	for i in 4:
		v.append(c[i]); v.append(c[(i + 1) % 4])
		v.append(c[i] + Vector3.UP); v.append(c[(i + 1) % 4] + Vector3.UP)
		v.append(c[i]); v.append(c[i] + Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return m


func piece_size() -> Vector3i:
	return Pieces.oriented(Pieces.LIST[piece][1], rotation_index)


func snap_step() -> int:
	return Pieces.SNAPS[snap_index][1]


func _process(_delta: float) -> void:
	if player == null or world == null:
		return
	var ray := player.eye_ray()
	_target = raycast(ray[0], ray[1])
	_update_ghost()


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
	if a.x >= a.y and a.x >= a.z:
		n = Vector3(signf(n.x), 0, 0)
	elif a.y >= a.z:
		n = Vector3(0, signf(n.y), 0)
	else:
		n = Vector3(0, 0, signf(n.z))
	return {"hit": r.position, "normal": n}


func current_box(target: Dictionary) -> AABB:
	if breaking:
		return Pieces.break_box(target.hit, target.normal, piece_size(), snap_step())
	return Pieces.place_box(target.hit, target.normal, piece_size(), snap_step())


func _update_ghost() -> void:
	if _target.is_empty():
		_ghost.visible = false
		_edge.visible = false
		return
	var box := current_box(_target)
	var pos := box.position * 0.25
	var size := box.size * 0.25
	var grow := 0.006
	_ghost.visible = true
	_edge.visible = true
	_ghost.position = pos + size * 0.5
	_ghost.scale = size + Vector3.ONE * grow * 2.0
	_edge.position = pos - Vector3.ONE * grow
	_edge.scale = size + Vector3.ONE * grow * 2.0
	_ghost_mat.albedo_color = Color(1.0, 0.35, 0.3, 0.28) if breaking else Color(0.55, 1.0, 0.7, 0.22)


## Perform the current action at the crosshair (or at an explicit target).
func act(target := {}) -> bool:
	if target.is_empty():
		target = _target
	if target.is_empty():
		return false
	var box := current_box(target)
	if breaking:
		return world.edit_box(box, 0) > 0
	if world.box_has_solid(box) or _overlaps_player(box):
		return false
	return world.edit_box(box, block_id) > 0


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
	if _target.is_empty():
		return
	var inside: Vector3 = _target.hit - _target.normal * 0.05
	var id := world.get_block_at(inside)
	if id > 0:
		block_id = id
		changed.emit()
