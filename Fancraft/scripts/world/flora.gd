class_name Flora
extends Node3D
## Trees, bushes and rocks: deterministic placement from the terrain shape, rendered with
## one MultiMesh per (region, model) whose detail level follows distance, with real
## collision near the player. Every plant has a stable id, so harvesting removes exactly
## that plant (and later saves can remember it).

const REGION := 64.0
var VIEW_REGIONS := 3            # regions drawn around the player (follows view distance)
const COLLIDE_DIST := 48.0       # plants closer than this get collision
const LOD1_DIST := 45.0
const LOD2_DIST := 110.0

# kind, variants, cell size (m), base chance, height range, max slope (rise per metre),
# scale range, uses forest noise
const SPECS := [
	["tree", 3, 7.0, 0.55, Vector2(2.5, 30.0), 0.5, Vector2(0.8, 1.25), true],
	["pine", 2, 8.0, 0.6, Vector2(16.0, 52.0), 0.7, Vector2(0.85, 1.3), false],
	["bush", 2, 6.0, 0.25, Vector2(2.0, 34.0), 0.6, Vector2(0.7, 1.3), true],
	["rock", 3, 13.0, 0.35, Vector2(-3.0, 120.0), 1.2, Vector2(0.6, 1.6), false],
]

var shape: TerrainShape
var focus: Node3D
var removed := {}                # plant id -> true (harvested)
var regions := {}                # Vector2i -> region dict
var _meshes := {}                # "kind:variant:detail" -> ArrayMesh
var _forest := FastNoiseLite.new()
var _queue: Array[Vector2i] = []
var _timer := 0.0


func setup(terrain_shape: TerrainShape, focus_node: Node3D) -> void:
	shape = terrain_shape
	focus = focus_node
	_forest.seed = 4242
	_forest.frequency = 0.008
	_apply_distance()
	Settings.changed.connect(func(k): if k == "render_distance": _apply_distance())


## View distance setting 3..12 -> 2..4 regions of flora (128..256 m).
func _apply_distance() -> void:
	VIEW_REGIONS = clampi(int(Settings.get_value("render_distance")) / 3 + 1, 2, 4)


# ------------------------------------------------------------------ placement

static func _hash(x: int, z: int, s: int) -> float:
	var h := (x * 374761393 + z * 668265263 + s * 1442695041) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	return float((h ^ (h >> 16)) & 0xFFFF) / 65535.0


## Deterministic plant list for one region.
func plants_in(rc: Vector2i) -> Array:
	var out := []
	var water := TerrainShape.WATER_LEVEL
	for si in SPECS.size():
		var spec: Array = SPECS[si]
		var cell: float = spec[2]
		var n := int(REGION / cell)
		for j in n:
			for i in n:
				var gx := rc.x * n + i
				var gz := rc.y * n + j
				var r := _hash(gx, gz, si * 7 + 1)
				var x := (gx + 0.15 + 0.7 * _hash(gx, gz, si * 7 + 2)) * cell
				var z := (gz + 0.15 + 0.7 * _hash(gx, gz, si * 7 + 3)) * cell
				var chance: float = spec[3]
				if spec[7]:
					chance *= clampf(_forest.get_noise_2d(x, z) * 2.0 + 0.6, 0.0, 1.4)
				if r > chance:
					continue
				var h := shape.height_at(x, z)
				var rel := h - water
				if rel < spec[4].x or rel > spec[4].y:
					continue
				var slope := maxf(absf(shape.height_at(x + 1.0, z) - h), absf(shape.height_at(x, z + 1.0) - h))
				if slope > spec[5]:
					continue
				var sc: float = lerpf(spec[6].x, spec[6].y, _hash(gx, gz, si * 7 + 4))
				var yaw := _hash(gx, gz, si * 7 + 5) * TAU
				var variant: int = int(_hash(gx, gz, si * 7 + 6) * spec[1]) % spec[1]
				var id := "%s:%d:%d" % [spec[0], gx, gz]
				if removed.has(id):
					continue
				var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc)
				out.append({"id": id, "kind": spec[0], "variant": variant, "scale": sc,
					"xform": Transform3D(basis, Vector3(x, h - 0.12 * sc, z))})
	return out


# ------------------------------------------------------------------ streaming

func _process(delta: float) -> void:
	if focus == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.3
		_refresh()
	# Build at most one new region per frame to keep frame times flat.
	if not _queue.is_empty():
		var rc: Vector2i = _queue.pop_front()
		if not regions.has(rc) and _region_dist(rc) <= (VIEW_REGIONS + 0.5) * REGION:
			_build_region(rc)


func _region_dist(rc: Vector2i) -> float:
	var c := Vector2((rc.x + 0.5) * REGION, (rc.y + 0.5) * REGION)
	return c.distance_to(Vector2(focus.global_position.x, focus.global_position.z))


func _refresh() -> void:
	var p := focus.global_position
	var centre := Vector2i(floori(p.x / REGION), floori(p.z / REGION))
	var want := {}
	for dz in range(-VIEW_REGIONS, VIEW_REGIONS + 1):
		for dx in range(-VIEW_REGIONS, VIEW_REGIONS + 1):
			var rc := centre + Vector2i(dx, dz)
			if _region_dist(rc) <= (VIEW_REGIONS + 0.5) * REGION:
				want[rc] = true
	for rc in regions.keys():
		if not want.has(rc):
			regions[rc].root.queue_free()
			regions.erase(rc)
	var missing := []
	for rc in want:
		if not regions.has(rc) and not _queue.has(rc):
			missing.append(rc)
	missing.sort_custom(func(a, b): return _region_dist(a) < _region_dist(b))
	_queue.append_array(missing)
	for rc in regions:
		_update_region(regions[rc])


func _mesh(kind: String, variant: int, detail: int) -> ArrayMesh:
	var key := "%s:%d:%d" % [kind, variant, detail]
	if _meshes.has(key):
		return _meshes[key]
	var m: ArrayMesh
	match kind:
		"tree": m = PropMeshes.tree_broadleaf(variant, detail)
		"pine": m = PropMeshes.tree_pine(variant, detail)
		"bush": m = PropMeshes.bush(variant, detail)
		_: m = PropMeshes.rock(variant, detail)
	var mats: Array = [PropMeshes.rock_material()] if kind == "rock" else ([PropMeshes.foliage_material()] if kind == "bush" else [PropMeshes.bark_material(), PropMeshes.foliage_material()])
	for si in m.get_surface_count():
		if m.surface_get_material(si) == null and si < mats.size():
			m.surface_set_material(si, mats[si])
	_meshes[key] = m
	return m


func _build_region(rc: Vector2i) -> void:
	var root := Node3D.new()
	add_child(root)
	var plants := plants_in(rc)
	var groups := {}
	for i in plants.size():
		var k := "%s:%d" % [plants[i].kind, plants[i].variant]
		if not groups.has(k):
			groups[k] = []
		groups[k].append(i)
	var mmis := {}
	for k in groups:
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var parts: PackedStringArray = k.split(":")
		mm.mesh = _mesh(parts[0], int(parts[1]), 2)
		mm.instance_count = groups[k].size()
		for n in groups[k].size():
			mm.set_instance_transform(n, plants[groups[k][n]].xform)
		mmi.multimesh = mm
		mmi.set_meta("detail", 2)
		root.add_child(mmi)
		mmis[k] = mmi
		for n in groups[k].size():
			plants[groups[k][n]].slot = [k, n]
	var reg := {"rc": rc, "root": root, "plants": plants, "mmis": mmis, "body": null}
	regions[rc] = reg
	_update_region(reg)


## Detail level by distance, and collision when close.
func _update_region(reg: Dictionary) -> void:
	var d := _region_dist(reg.rc) - REGION * 0.5
	var detail := 0 if d < LOD1_DIST else (1 if d < LOD2_DIST else 2)
	for k in reg.mmis:
		var mmi: MultiMeshInstance3D = reg.mmis[k]
		if mmi.get_meta("detail") != detail:
			var parts: PackedStringArray = k.split(":")
			mmi.multimesh.mesh = _mesh(parts[0], int(parts[1]), detail)
			mmi.set_meta("detail", detail)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if detail < 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var want_body := d < COLLIDE_DIST
	if want_body and reg.body == null:
		var body := StaticBody3D.new()
		body.set_meta("flora_region", reg.rc)
		for i in reg.plants.size():
			var pl: Dictionary = reg.plants[i]
			for c in _collision(pl):
				var cs := CollisionShape3D.new()
				cs.shape = c.shape
				cs.transform = pl.xform * c.transform
				cs.set_meta("plant", i)
				body.add_child(cs)
				pl.shape_node = cs
		reg.root.add_child(body)
		reg.body = body
	elif not want_body and reg.body != null:
		reg.body.queue_free()
		reg.body = null


var _shape_cache := {}


func _collision(pl: Dictionary) -> Array:
	var k := "%s:%d" % [pl.kind, pl.variant]
	if not _shape_cache.has(k):
		match pl.kind:
			"tree", "pine":
				_shape_cache[k] = PropMeshes.tree_collision("pine" if pl.kind == "pine" else "broadleaf")
			"bush":
				var s := SphereShape3D.new()
				s.radius = 0.55
				_shape_cache[k] = [{"shape": s, "transform": Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 0))}]
			_:
				_shape_cache[k] = PropMeshes.rock_collision(pl.variant)
	return _shape_cache[k]


# ------------------------------------------------------------------ queries & edits

## Visual volumes (radius, height) per kind, for aiming at canopies / bushes / rocks.
const VOLUMES := {"tree": [2.4, 8.5], "pine": [1.9, 10.0], "bush": [1.0, 1.5], "rock": [1.3, 1.8]}


## First plant whose visual volume the ray passes through, within max_t.
## Returns {plant, region, index, position, base} or {}.
func pick(origin: Vector3, dir: Vector3, max_t: float) -> Dictionary:
	var best := {}
	var best_t := max_t
	for rc in regions:
		var reg: Dictionary = regions[rc]
		if _region_dist(rc) > REGION:
			continue
		for i in reg.plants.size():
			var pl: Dictionary = reg.plants[i]
			if pl.get("gone", false):
				continue
			var base: Vector3 = pl.xform.origin
			if base.distance_to(origin) > max_t + 10.0:
				continue
			var vol: Array = VOLUMES[pl.kind]
			var top: float = vol[1] * pl.scale
			var t := _ray_axis_t(origin, dir, base)
			if t < 0.0 or t > best_t:
				continue
			var p := origin + dir * t
			var ay := clampf(p.y - base.y, 0.0, top)
			var trunk: bool = (pl.kind == "tree" or pl.kind == "pine") and ay < top * 0.35
			var rad: float = (0.6 if trunk else vol[0]) * pl.scale
			if p.distance_to(base + Vector3(0, ay, 0)) <= rad:
				best_t = t
				best = {"plant": pl, "region": rc, "index": i, "position": p, "base": base}
	return best


static func _ray_axis_t(o: Vector3, d: Vector3, base: Vector3) -> float:
	var w := o - base
	var b := d.y
	var denom := 1.0 - b * b
	if denom < 0.0001:
		return w.length()
	return (b * w.y - d.dot(w)) / denom


## Remove a plant for good (harvested or dug out). Returns its kind.
func remove(region: Vector2i, index: int) -> String:
	var reg: Dictionary = regions.get(region, {})
	if reg.is_empty():
		return ""
	var pl: Dictionary = reg.plants[index]
	if pl.get("gone", false):
		return ""
	pl.gone = true
	removed[pl.id] = true
	var slot: Array = pl.slot
	var mmi: MultiMeshInstance3D = reg.mmis[slot[0]]
	mmi.multimesh.set_instance_transform(slot[1], Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), pl.xform.origin))
	if pl.has("shape_node") and is_instance_valid(pl.shape_node):
		pl.shape_node.queue_free()
	return pl.kind


## Region + index for a collision hit (ray hit the plant's own collision shape).
func from_collider(collider: Object, shape_idx: int) -> Dictionary:
	var body := collider as StaticBody3D
	if body == null or not body.has_meta("flora_region"):
		return {}
	var owner_id := body.shape_find_owner(shape_idx)
	var node := body.shape_owner_get_owner(owner_id) as Node
	if node == null or not node.has_meta("plant"):
		return {}
	var rc: Vector2i = body.get_meta("flora_region")
	var i: int = node.get_meta("plant")
	var pl: Dictionary = regions[rc].plants[i]
	return {"plant": pl, "region": rc, "index": i, "base": pl.xform.origin}


## Plants whose base lies inside a dug sphere are removed (no floating trees).
func remove_in_sphere(center: Vector3, radius: float) -> void:
	for rc in regions:
		if _region_dist(rc) > REGION * 1.5:
			continue
		var reg: Dictionary = regions[rc]
		for i in reg.plants.size():
			var pl: Dictionary = reg.plants[i]
			if not pl.get("gone", false) and (pl.xform.origin as Vector3).distance_to(center) < radius:
				remove(rc, i)
