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
var flora: Flora                 # trees, bushes, rocks
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

func _ray(origin: Vector3, dir: Vector3, plants := true) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * REACH)
	q.exclude = [player.get_rid()]
	var r := space.intersect_ray(q)
	# Plants only collide at the trunk / core, but players aim at canopies and bushes:
	# if the aim passes through a plant's visual volume before the hit, target the plant.
	if plants and flora:
		var pick := flora.pick(origin, dir, REACH if r.is_empty() else origin.distance_to(r.position) + 0.3)
		if not pick.is_empty():
			pick.kind = "plant"
			pick.normal = -dir
			return pick
	if r.is_empty():
		return {}
	var kind := "other"
	if BuildSystem.is_part(r.collider):
		kind = "part"
	elif terrain.owns_collider(r.collider):
		kind = "terrain"
	elif flora and (r.collider as Node).has_meta("flora_region"):
		var hit := flora.from_collider(r.collider, r.shape)
		if not hit.is_empty():
			hit.kind = "plant"
			hit.position = r.position
			hit.normal = r.normal
			return hit
	return {"position": r.position, "normal": r.normal, "collider": r.collider, "shape": r.shape, "kind": kind}


func _ray_screen(screen_pos: Vector2) -> Dictionary:
	var cam := player.camera
	return _ray(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))


func _ray_crosshair() -> Dictionary:
	var e := player.eye_ray()
	return _ray(e[0], e[1], false)   # building aims at real surfaces only


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
			return {"kind": "chop", "time": 1.1 if current == AXE else 2.8, "key": t.plant.id}
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
			if flora:
				flora.remove_in_sphere(at, DIG_RADIUS + 0.6)   # no floating trees
			_give(mat, 2 if mat != "stone" else 1)
		"part":
			building.demolish(t.collider)
		"plant":
			var kind := flora.remove(t.region, t.index)
			if kind == "":
				return false
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


func harvest_yield(kind: String) -> Dictionary:
	match kind:
		"rock":
			var y := {"stone": _rng.randi_range(3, 5)}
			if _rng.randf() < 0.4:
				y["flint"] = 1
			return y
		"bush":
			return {"fiber": _rng.randi_range(2, 3), "berries": _rng.randi_range(1, 2)}
	return {"wood": _rng.randi_range(4, 6)}   # broadleaf and pine trees


func _give(id: String, n: int) -> void:
	if inventory == null:
		return
	if inventory.add(id, n) > 0:
		message.emit("Bag full: some %s was lost" % Items.name_of(id))
