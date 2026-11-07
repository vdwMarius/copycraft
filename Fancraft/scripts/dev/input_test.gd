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
	# Walk up to the nearest tree, aim at its CANOPY through the screen like a player,
	# and hold: it must chop the tree for wood (not dig the ground behind it).
	var fl: Flora = main.flora
	var t_wait := Time.get_ticks_msec()
	while fl.regions.size() < 9 and Time.get_ticks_msec() - t_wait < 20000:
		await tree.process_frame
	var near_tree := {}
	for rc in fl.regions:
		for pl in fl.regions[rc].plants:
			if pl.kind == "tree" and (near_tree.is_empty() or (pl.xform.origin as Vector3).distance_to(p.global_position) < (near_tree.xform.origin as Vector3).distance_to(p.global_position)):
				near_tree = pl
	if near_tree.is_empty():
		failures += 1
		printerr("FAIL: no trees generated around the spawn")
	else:
		var tb: Vector3 = near_tree.xform.origin
		p.controls_enabled = false   # freeze physics while aiming (terrain collision may still be loading there)
		p.velocity = Vector3.ZERO
		p.global_position = tb + Vector3(4.0, 0.0, 0.0)
		p.global_position.y = main.terrain.height_at(p.global_position.x, p.global_position.z) + 0.2
		for i in 3:
			await tree.process_frame
		var eye: Vector3 = p.camera.global_position
		var canopy := tb + Vector3(0, 4.5 * near_tree.scale, 0)
		p.look_at_from_position(p.global_position, Vector3(canopy.x, p.global_position.y, canopy.z))
		p.camera.rotation.x = atan2(canopy.y - eye.y, Vector2(canopy.x - eye.x, canopy.z - eye.z).length())
		# Teleports confuse physics interpolation (the camera would lerp from the old spot).
		p.reset_physics_interpolation()
		for i in 2:
			await tree.physics_frame
		await tree.process_frame
		var info: Dictionary = main.tools.hold_info(centre)
		var wood0 := inv.count("wood")
		var dirt0 := inv.count("dirt")
		main.tools.complete_hold(centre)
		p.controls_enabled = true
		print("aiming at a canopy %.1f m away: hold=%s wood +%d dirt +%d, tree gone=%s" % [tb.distance_to(eye), info.get("kind", "none"), inv.count("wood") - wood0, inv.count("dirt") - dirt0, near_tree.get("gone", false)])
		# (Another tree's canopy may be in front of the target; chopping that one is right too.)
		if info.get("kind", "") != "chop" or inv.count("wood") <= wood0 or inv.count("dirt") != dirt0:
			failures += 1
			printerr("FAIL: aiming at a tree canopy must chop that tree for wood")
		# A bush and a rock too, if any are close.
		for kind in ["bush", "rock"]:
			var target := {}
			for rc in fl.regions:
				for pl in fl.regions[rc].plants:
					if pl.kind == kind and not pl.get("gone", false) and (target.is_empty() or (pl.xform.origin as Vector3).distance_to(p.global_position) < (target.xform.origin as Vector3).distance_to(p.global_position)):
						target = pl
			if target.is_empty():
				continue
			var base: Vector3 = target.xform.origin
			var o := base + Vector3(3.0, 1.6, 0.0)
			var hit: Dictionary = main.tools._ray(o, (base + Vector3(0, 0.5 * target.scale, 0) - o).normalized())
			var before_items := 0
			for id in Items.ORDER:
				before_items += inv.count(id)
			var ok: bool = hit.get("kind", "") == "plant" and main.tools.complete_target(hit)
			var after_items := 0
			for id in Items.ORDER:
				after_items += inv.count(id)
			print("%s: %s, items +%d" % [kind, "harvested" if ok else "MISSED", after_items - before_items])
			if not ok or after_items <= before_items:
				failures += 1
				printerr("FAIL: could not harvest a " + kind)
	var y: Dictionary = main.tools.harvest_yield("tree")
	if y.get("wood", 0) < 4:
		failures += 1
		printerr("FAIL: trees should yield 4-6 wood")
	# A rested finger that swipes away before anything was dug is a LOOK: the view turns
	# fully and nothing is dug.
	var yaw := p.rotation.y
	var pitch := p.camera.rotation.x
	var edits_before := _edits(w)
	_touch(5, centre, true)
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 380:
		await tree.process_frame
	for k in 6:
		var d := InputEventScreenDrag.new()
		d.index = 5
		d.position = get_viewport().get_final_transform() * (centre + Vector2(40 * (k + 1), 0))
		d.relative = Vector2(40, 0)
		Input.parse_input_event(d)
		await tree.process_frame
	_touch(5, centre + Vector2(240, 0), false)
	await tree.process_frame
	var turned := absf(angle_difference(yaw, p.rotation.y))
	if turned < 0.3 or _edits(w) != edits_before:
		failures += 1
		printerr("FAIL: rest-then-swipe should look around (turned %.2f rad, edits %d)" % [turned, _edits(w) - edits_before])
	# During a real hold (after an action completed) a swipe only nudges the camera.
	p.rotation.y = yaw
	p.look(Vector2.ZERO)
	_touch(7, centre, true)
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1400:
		await tree.process_frame
	var yaw2 := p.rotation.y
	var d3 := InputEventScreenDrag.new()
	d3.index = 7
	d3.position = get_viewport().get_final_transform() * (centre + Vector2(120, 0))
	d3.relative = Vector2(120, 0)
	Input.parse_input_event(d3)
	await tree.process_frame
	_touch(7, centre + Vector2(120, 0), false)
	await tree.process_frame
	var nudge := absf(angle_difference(yaw2, p.rotation.y))
	if nudge <= 0.0 or nudge > 0.2:
		failures += 1
		printerr("FAIL: a swipe during a hold should nudge the camera slightly (%.3f rad)" % nudge)
	print("look: rest-then-swipe turned %.2f rad, hold nudge %.3f rad" % [turned, nudge])
	yaw = p.rotation.y
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
