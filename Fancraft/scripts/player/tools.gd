class_name Tools
extends Node3D
## The player's hand tools. Each tool defines what a TAP and a HOLD do:
##   Shovel: tap raises ground, hold digs.
##   Axe:    hold chops trees / bushes / rocks.
##   Hammer: tap places the previewed building part, hold demolishes a part.
## Any tool can hold-harvest anything, just slower than the right tool.

signal message(text: String)

const SHOVEL := 0
const AXE := 1
const HAMMER := 2
const NAMES := ["Shovel", "Axe", "Hammer"]

const REACH := 9.0
const DIG_RADIUS := 1.25
const RAISE_RADIUS := 1.15

var current := HAMMER
var player: Player
var terrain: SmoothTerrain
var building: BuildSystem
var vegetation: Node3D           # VoxelInstancer
var inventory: Inventory
var _rng := RandomNumberGenerator.new()
var edit_count := 0              # successful actions (tests / stats)

## Screen point to aim at while a finger rests on the view (x < 0: crosshair).
var aim_screen := Vector2(-1, -1)


func _process(_delta: float) -> void:
	if player == null:
		return
	# The hammer always previews at the crosshair; other tools show nothing.
	var show := current == HAMMER and player.controls_enabled
	building.update_preview(_ray_crosshair() if show else {}, show)


# ------------------------------------------------------------------ targeting

func _ray(origin: Vector3, dir: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * REACH)
	q.exclude = [player.get_rid()]
	var r := space.intersect_ray(q)
	if r.is_empty():
		return {}
	var kind := "other"
	if BuildSystem.is_part(r.collider):
		kind = "part"
	elif terrain.owns_collider(r.collider):
		kind = "terrain"
	elif _owned_by(r.collider, vegetation):
		kind = "plant"
	return {"position": r.position, "normal": r.normal, "collider": r.collider, "shape": r.shape, "kind": kind}


func _ray_screen(screen_pos: Vector2) -> Dictionary:
	var cam := player.camera
	return _ray(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))


func _ray_crosshair() -> Dictionary:
	var e := player.eye_ray()
	return _ray(e[0], e[1])


static func _owned_by(node: Object, owner: Node) -> bool:
	var n := node as Node
	while n and owner:
		if n == owner:
			return true
		n = n.get_parent()
	return false


# ------------------------------------------------------------------ actions

## What holding at `screen_pos` would do: {kind, time, key} or {} if nothing.
func hold_info(screen_pos: Vector2) -> Dictionary:
	var t := _ray_screen(screen_pos)
	if t.is_empty():
		return {}
	match t.kind:
		"terrain":
			return {"kind": "dig", "time": 0.22 if current == SHOVEL else 0.6, "key": "terrain"}
		"part":
			return {"kind": "demolish", "time": 0.8 if current == HAMMER else 2.0, "key": t.collider.get_instance_id()}
		"plant":
			return {"kind": "chop", "time": 1.1 if current == AXE else 2.8, "key": t.collider.get_instance_id()}
	return {}


## Finish a hold at `screen_pos` (dig one pulse, chop the plant, demolish the part).
func complete_hold(screen_pos: Vector2) -> bool:
	return complete_target(_ray_screen(screen_pos))


## Finish a hold on an already-traced target (see _ray).
func complete_target(t: Dictionary) -> bool:
	if t.is_empty():
		return false
	match t.kind:
		"terrain":
			var at: Vector3 = t.position - t.normal * 0.35
			var mat := dug_material(at)
			terrain.dig(at, DIG_RADIUS)
			_give(mat, 2 if mat != "stone" else 1)
		"part":
			building.demolish(t.collider)
		"plant":
			var kind := plant_kind(t.collider, t.get("shape", 0))
			var p: Vector3 = t.position
			var ground := terrain.height_at(p.x, p.z)
			vegetation.remove_instances_in_sphere(Vector3(p.x, minf(ground, p.y), p.z), 1.6 if kind != "bush" else 1.0)
			var got := harvest_yield(kind)
			for id in got:
				_give(id, got[id])
		_:
			return false
	edit_count += 1
	return true


## A quick tap at `screen_pos`.
func tap(screen_pos: Vector2) -> bool:
	match current:
		SHOVEL:
			var t := _ray_screen(screen_pos)
			if t.is_empty() or t.kind == "plant":
				return false
			var c: Vector3 = t.position + t.normal * 0.55
			if c.distance_to(player.global_position + Vector3.UP * 0.9) < RAISE_RADIUS + 0.75:
				return false   # would bury the player
			if inventory and not inventory.pay({"dirt": 2}):
				if not inventory.pay({"sand": 2}):
					message.emit("Need 2 Dirt to raise ground: dig some first")
					return false
			terrain.raise(c, RAISE_RADIUS)
		HAMMER:
			# Building aims with the crosshair preview, so a tap anywhere places it.
			var why := building.place()
			if why != "":
				message.emit(why)
				return false
		_:
			return false
	edit_count += 1
	return true


# ------------------------------------------------------------------ resources

## What a dig at `at` yields: the voxel's material (topsoil near water is sand).
func dug_material(at: Vector3) -> String:
	var t = terrain.tool
	t.channel = ClassDB.class_get_integer_constant("VoxelBuffer", "CHANNEL_INDICES")
	var idx: int = t.get_voxel(Vector3i(at.round()))
	if idx == TerrainShape.STONE:
		return "stone"
	if at.y < TerrainShape.WATER_LEVEL + 2.0:
		return "sand"
	return "dirt"


## Which kind of plant a collider belongs to, from its collision shape:
## capsule / cylinder = tree trunk, convex hull = rock, sphere = bush.
func plant_kind(collider: Object, shape_index: int) -> String:
	var body := collider as CollisionObject3D
	if body == null:
		return "tree"
	var owner_id := body.shape_find_owner(shape_index)
	var shape := body.shape_owner_get_shape(owner_id, 0) if owner_id >= 0 else null
	if shape is ConvexPolygonShape3D or shape is BoxShape3D:
		return "rock"
	if shape is SphereShape3D:
		return "bush"
	return "tree"


func harvest_yield(kind: String) -> Dictionary:
	match kind:
		"rock":
			var y := {"stone": _rng.randi_range(3, 5)}
			if _rng.randf() < 0.4:
				y["flint"] = 1
			return y
		"bush":
			return {"fiber": _rng.randi_range(2, 3), "berries": _rng.randi_range(1, 2)}
	return {"wood": _rng.randi_range(4, 6)}


func _give(id: String, n: int) -> void:
	if inventory == null:
		return
	if inventory.add(id, n) > 0:
		message.emit("Bag full: some %s was lost" % Items.name_of(id))
