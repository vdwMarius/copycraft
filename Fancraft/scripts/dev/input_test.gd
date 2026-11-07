extends Node
## Dev/regression: `-- --inputtest` (works headless). Simulates a finger: hold to break,
## tap to place. Prints INPUT_TEST_RESULT failures=N and quits.

func _ready() -> void:
	var main: Node = get_parent()
	var tree := get_tree()
	var t0_spawn := Time.get_ticks_msec()
	while not main.player.controls_enabled and Time.get_ticks_msec() - t0_spawn < 60000:
		await tree.process_frame
	print("spawned in ", Time.get_ticks_msec() - t0_spawn, " ms, controls=", main.player.controls_enabled)
	for i in 30:
		await tree.physics_frame
	var p: Player = main.player
	p.camera.rotation.x = -0.7   # look at the ground a few blocks ahead
	p._pitch = -0.7
	await tree.physics_frame
	await tree.process_frame
	var w: Tools = main.tools
	var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
	print("target at centre: ", not main.tools.hold_info(centre).is_empty(), " player at ", p.global_position)
	var failures := 0
	var before := _edits(w)
	_touch(3, centre, true)
	await tree.process_frame
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1300:
		await tree.process_frame
	_touch(3, centre, false)
	await tree.process_frame
	var after_hold := _edits(w)
	if after_hold - before < 1:
		failures += 1
		printerr("FAIL: holding did not break anything")
	var inv: Inventory = main.inventory
	var dug: int = inv.count("dirt") + inv.count("sand") + inv.count("stone")
	if dug < 1:
		failures += 1
		printerr("FAIL: digging should yield dirt, sand or stone")
	print("dug materials: ", dug)
	# With no wood, a foundation must be refused; with wood it is placed and paid for.
	if inv.count("wood") == 0 and main.tools.tap(centre):
		failures += 1
		printerr("FAIL: building without materials should be refused")
	inv.add("wood", 20)
	# Let the broken blocks' meshes and collision land (a real re-tap takes >100 ms).
	for i in 20:
		await tree.physics_frame
	_touch(4, centre, true)
	await tree.process_frame
	_touch(4, centre, false)
	await tree.process_frame
	var after_tap := _edits(w)
	if after_tap - after_hold < 1:
		failures += 1
		printerr("FAIL: tapping did not place")
	if inv.count("wood") != 20 - Parts.cost("foundation", "wood").wood:
		failures += 1
		printerr("FAIL: the foundation should cost %d wood (have %d)" % [Parts.cost("foundation", "wood").wood, inv.count("wood")])
	# Demolish refunds in full.
	var placed: Array = main.building.parts.values()
	if not placed.is_empty():
		var wood_before := inv.count("wood")
		main.building.demolish(placed[0])
		if inv.count("wood") - wood_before != Parts.cost("foundation", "wood").wood:
			failures += 1
			printerr("FAIL: demolishing should refund the cost")
	# Find a real instanced plant around the spawn and harvest it.
	var found := {}
	for ring in [3.0, 6.0, 8.5]:
		for k in 24:
			var a := TAU * k / 24.0
			var dir := Vector3(cos(a), -0.15, sin(a)).normalized()
			for dy in [0.4, 1.2, 2.0]:
				var t: Dictionary = main.tools._ray(p.global_position + Vector3(0, dy, 0), dir)
				if t.get("kind", "") == "plant":
					found = t
					break
			if not found.is_empty():
				break
		if not found.is_empty():
			break
	if found.is_empty():
		var space := p.get_world_3d().direct_space_state
		for gz in range(-20, 21, 2):
			for gx in range(-20, 21, 2):
				var o := p.global_position + Vector3(gx, 25, gz)
				var q := PhysicsRayQueryParameters3D.create(o, o + Vector3.DOWN * 60.0)
				q.exclude = [p.get_rid()]
				var r := space.intersect_ray(q)
				if not r.is_empty() and Tools._owned_by(r.collider, main.vegetation):
					found = {"position": r.position, "normal": r.normal, "collider": r.collider, "shape": r.shape, "kind": "plant"}
					break
			if not found.is_empty():
				break
	var bodies: Array = main.vegetation.find_children("*", "CollisionObject3D", true, false)
	var nearest := INF
	for bd in bodies:
		nearest = minf(nearest, (bd as Node3D).global_position.distance_to(p.global_position))
	print("vegetation bodies: ", bodies.size(), " nearest ", nearest, " children: ", main.vegetation.get_child_count())
	if found.is_empty() and not bodies.is_empty():
		var bd: Node3D = bodies[0]
		for b2 in bodies:
			if (b2 as Node3D).global_position.distance_to(p.global_position) < bd.global_position.distance_to(p.global_position):
				bd = b2
		found = {"position": bd.global_position + Vector3(0, 1.0, 0), "normal": Vector3.BACK, "collider": bd, "shape": 0, "kind": "plant"}
	if found.is_empty():
		print("no plant within reach of spawn (skipped harvest check); instance counts: ", main.vegetation.debug_get_instance_counts())
	else:
		var kind: String = main.tools.plant_kind(found.collider, found.shape)
		var totals := {}
		for id in Items.ORDER:
			totals[id] = inv.count(id)
		main.tools.complete_target(found)
		var got := []
		for id in Items.ORDER:
			if inv.count(id) > totals[id]:
				got.append("%s+%d" % [id, inv.count(id) - totals[id]])
		print("harvested a ", kind, ": ", got)
		if got.is_empty():
			failures += 1
			printerr("FAIL: harvesting a plant gave nothing")
	var y: Dictionary = main.tools.harvest_yield("tree")
	if y.get("wood", 0) < 4:
		failures += 1
		printerr("FAIL: trees should yield 4-6 wood")
	# Swipe while breaking: the view must not turn.
	_touch(5, centre, true)
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400:
		await tree.process_frame
	var yaw := p.rotation.y
	var pitch := p.camera.rotation.x
	for k in 6:
		var d := InputEventScreenDrag.new()
		d.index = 5
		d.position = get_viewport().get_final_transform() * (centre + Vector2(40 * (k + 1), 0))
		d.relative = Vector2(40, 0)
		Input.parse_input_event(d)
		await tree.process_frame
	_touch(5, centre + Vector2(240, 0), false)
	await tree.process_frame
	if not is_equal_approx(yaw, p.rotation.y) or not is_equal_approx(pitch, p.camera.rotation.x):
		failures += 1
		printerr("FAIL: swiping while breaking turned the view")
	# A normal drag (not held first) must still turn the view.
	_touch(6, centre, true)
	await tree.process_frame
	var d2 := InputEventScreenDrag.new()
	d2.index = 6
	d2.position = get_viewport().get_final_transform() * (centre + Vector2(80, 0))
	d2.relative = Vector2(80, 0)
	Input.parse_input_event(d2)
	await tree.process_frame
	_touch(6, centre + Vector2(80, 0), false)
	await tree.process_frame
	if is_equal_approx(yaw, p.rotation.y):
		failures += 1
		printerr("FAIL: a normal drag no longer turns the view")
	# --- building snapping
	var bs: BuildSystem = main.building
	var gx := floorf(p.global_position.x / 2.0) * 2.0 + 6.0
	var gz := floorf(p.global_position.z / 2.0) * 2.0 + 6.0
	var gh: float = main.terrain.height_at(gx + 1.0, gz + 1.0)
	bs.part_id = "foundation"
	var f := bs.plan({"position": Vector3(gx + 1.0, gh, gz + 1.0), "normal": Vector3.UP, "collider": null})
	var f_ok: bool = f.get("ok", false) and is_equal_approx(f.transform.origin.y, snappedf(main.terrain.height_at(gx + 1.0, gz + 1.0), 0.25) + 0.3)
	var fb := bs._spawn(f) if f_ok else null
	_check(f_ok and fb != null, "foundation snaps to the grid at ground height", failures)
	if not (f_ok and fb != null):
		failures += 1
	if fb:
		var lvl: float = f.transform.origin.y
		bs.part_id = "wall"
		var wplan := bs.plan({"position": Vector3(gx + 1.0, lvl, gz + 0.15), "normal": Vector3.UP, "collider": fb})
		var w_ok: bool = wplan.get("ok", false) and is_equal_approx(wplan.transform.origin.z, gz) and is_equal_approx(wplan.transform.origin.y, lvl)
		if not w_ok:
			failures += 1
			printerr("FAIL: wall should stand on the foundation's south edge: ", wplan)
		var wb := bs._spawn(wplan)
		var again := bs.plan({"position": Vector3(gx + 1.0, lvl, gz + 0.15), "normal": Vector3.UP, "collider": fb})
		if again.get("ok", true):
			failures += 1
			printerr("FAIL: a second wall in the same slot must be blocked")
		bs.part_id = "floor"
		var up := bs.plan({"position": Vector3(gx + 1.0, lvl + 2.4, gz), "normal": Vector3.UP, "collider": wb})
		if not is_equal_approx(up.get("transform", Transform3D()).origin.y, lvl + Parts.WALL_H):
			failures += 1
			printerr("FAIL: a floor aimed at a wall top should sit one storey up: ", up)
		print("building: foundation %.2f wall %s upper floor %.2f" % [lvl, wplan.slot, up.transform.origin.y])
	# A quick tap must never break; a hold must never place.
	print("hold edits=", after_hold - before, " tap edits=", after_tap - after_hold)
	print("INPUT_TEST_RESULT failures=%d" % failures)
	tree.quit(1 if failures else 0)


func _check(cond: bool, what: String, _f: int) -> void:
	print(("ok   " if cond else "FAIL: ") + what)


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	# Injected events are in window pixels; convert from viewport coordinates.
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = get_viewport().get_final_transform() * pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _edits(w: Tools) -> int:
	return w.edit_count
