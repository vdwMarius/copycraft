class_name BuildSystem
extends Node3D
## Snap-together building parts (Valheim / Rust style) on a 2 m world grid.
##
## Every placed part occupies a *slot*: a grid cell (foundations, floors, stairs, roofs),
## a cell edge (walls, beams) or a cell corner (pillars), at a storey level (y). The
## slot key prevents double placement. Snapping:
## - aiming at terrain: the part goes in the cell under the aim point, at ground height
##   (foundations rise 0.3 m out of the ground);
## - aiming at the TOP of a part: the next part stands on it (walls on floors, an upper
##   floor or roof on wall tops);
## - aiming at the SIDE of a part: the new part continues the same storey next to it.

signal changed

var part_id := "foundation"
var material_id := "wood"
var rotation_steps := 0          # extra quarter turns for roofs / stairs
var terrain: SmoothTerrain
var player: Node3D

var parts := {}                  # slot key -> StaticBody3D
var _ghost: MeshInstance3D
var _plan := {}                  # last computed placement


func _ready() -> void:
	_ghost = MeshInstance3D.new()
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)


static func is_part(node: Object) -> bool:
	return node is Node and (node as Node).has_meta("part_slot")


# ------------------------------------------------------------------ planning

## Work out where the selected part would go for a ray hit.
## `hit` = {position, normal, collider}. Returns {} if nothing sensible.
func plan(hit: Dictionary) -> Dictionary:
	if hit.is_empty():
		return {}
	var def: Dictionary = Parts.CATALOG[part_id]
	var p: Vector3 = hit.position
	var n: Vector3 = hit.normal
	var level: float
	var on_part := is_part(hit.collider)
	if on_part:
		var other: Node3D = hit.collider
		var o: Dictionary = other.get_meta("part_info")
		var odef: Dictionary = Parts.CATALOG[o.id]
		if n.y > 0.7:
			level = o.level + odef.base + odef.size.y          # stand on its top
			if odef.kind == "cell" and o.id in ["foundation", "floor"]:
				level = o.level
		else:
			level = o.level                                     # continue the storey
	else:
		level = p.y
	# Point just in front of the surface decides the cell / edge / corner.
	var q := p + n * 0.3
	var cx := floori(q.x / Parts.GRID)
	var cz := floori(q.z / Parts.GRID)
	var u := q.x / Parts.GRID - cx      # 0..1 inside the cell
	var v := q.z / Parts.GRID - cz
	var out := {"id": part_id, "mat": material_id}
	match def.kind:
		"cell":
			var centre := Vector3((cx + 0.5) * Parts.GRID, 0.0, (cz + 0.5) * Parts.GRID)
			if not on_part and terrain:
				var g := terrain.height_at(centre.x, centre.z)
				if part_id == "foundation":
					level = snappedf(g, 0.25) + 0.3
				elif part_id == "floor":
					level = maxf(level, g + 0.05)
			centre.y = level
			var yaw := _facing_yaw() + rotation_steps * PI * 0.5
			if part_id in ["foundation", "floor"]:
				yaw = 0.0
			out.transform = Transform3D(Basis(Vector3.UP, yaw), centre)
			var cat := "floor" if part_id in ["foundation", "floor"] else part_id
			out.slot = "c:%s:%d:%d:%d" % [cat, cx, cz, roundi(level * 10.0)]
		"edge":
			# Nearest of the four cell edges.
			var d := [v, 1.0 - v, u, 1.0 - u]     # south(z-), north(z+), west(x-), east(x+)
			var best := 0
			for i in 4:
				if d[i] < d[best]:
					best = i
			var pos: Vector3
			var yaw := 0.0
			var key: String
			match best:
				0:
					pos = Vector3((cx + 0.5) * Parts.GRID, level, cz * Parts.GRID)
					key = "ez:%d:%d" % [cx, cz]
				1:
					pos = Vector3((cx + 0.5) * Parts.GRID, level, (cz + 1) * Parts.GRID)
					key = "ez:%d:%d" % [cx, cz + 1]
				2:
					pos = Vector3(cx * Parts.GRID, level, (cz + 0.5) * Parts.GRID)
					yaw = PI * 0.5
					key = "ex:%d:%d" % [cx, cz]
				_:
					pos = Vector3((cx + 1) * Parts.GRID, level, (cz + 0.5) * Parts.GRID)
					yaw = PI * 0.5
					key = "ex:%d:%d" % [cx + 1, cz]
			out.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
			out.slot = "%s:%s:%d" % [key, "beam" if part_id == "beam" else "wall", roundi(level * 10.0)]
		"post":
			var px := roundi(q.x / Parts.GRID)
			var pz := roundi(q.z / Parts.GRID)
			out.transform = Transform3D(Basis.IDENTITY, Vector3(px * Parts.GRID, level, pz * Parts.GRID))
			out.slot = "p:%d:%d:%d" % [px, pz, roundi(level * 10.0)]
	out.ok = not parts.has(out.slot) and not _hits_player(out)
	return out


func _facing_yaw() -> float:
	if player == null:
		return 0.0
	var f := -player.global_transform.basis.z
	return snappedf(atan2(-f.x, -f.z), PI * 0.5)


func _hits_player(p: Dictionary) -> bool:
	if player == null:
		return false
	var def: Dictionary = Parts.CATALOG[p.id]
	var half := Vector3(def.size.x, 0, def.size.z) * 0.5
	var lo := Vector3(-half.x, def.base, -half.z)
	var box: AABB = p.transform * AABB(lo, def.size)
	var me := AABB(player.global_position + Vector3(-0.3, 0.05, -0.3), Vector3(0.6, 1.7, 0.6))
	return box.grow(-0.05).intersects(me)


# ------------------------------------------------------------------ preview

func update_preview(hit: Dictionary, show: bool) -> void:
	if not show:
		_ghost.visible = false
		_plan = {}
		return
	_plan = plan(hit)
	if _plan.is_empty():
		_ghost.visible = false
		return
	_ghost.mesh = PartMeshes.mesh(_plan.id, _plan.mat)
	_ghost.material_override = PartMeshes.ghost_material(_plan.ok)
	_ghost.global_transform = _plan.transform
	_ghost.visible = true


# ------------------------------------------------------------------ placing / removing

## Place the part currently previewed (or planned from `hit`).
func place(hit := {}) -> bool:
	var p := _plan if hit.is_empty() else plan(hit)
	if p.is_empty() or not p.ok:
		return false
	_spawn(p)
	changed.emit()
	return true


func _spawn(p: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_meta("part_slot", p.slot)
	body.set_meta("part_info", {"id": p.id, "mat": p.mat, "level": p.transform.origin.y})
	var mi := MeshInstance3D.new()
	mi.mesh = PartMeshes.mesh(p.id, p.mat)
	if mi.mesh.get_surface_count() > 0 and mi.mesh.surface_get_material(0) == null:
		mi.material_override = PartMeshes.material(p.mat)
	body.add_child(mi)
	for c in PartMeshes.collision(p.id):
		var cs := CollisionShape3D.new()
		cs.shape = c.shape
		cs.transform = c.transform
		body.add_child(cs)
	add_child(body)
	body.global_transform = p.transform
	parts[p.slot] = body
	return body


func demolish(node: Object) -> bool:
	if not is_part(node):
		return false
	var slot: String = (node as Node).get_meta("part_slot")
	parts.erase(slot)
	(node as Node).queue_free()
	changed.emit()
	return true


## Serializable list of placed parts (for saves, M7).
func snapshot() -> Array:
	var out := []
	for slot in parts:
		var b: Node3D = parts[slot]
		var info: Dictionary = b.get_meta("part_info")
		out.append({"slot": slot, "id": info.id, "mat": info.mat, "xform": b.global_transform})
	return out
