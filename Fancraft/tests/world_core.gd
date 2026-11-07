extends SceneTree
## Headless checks for the chunk store, mesher, generator and piece placement.

var failures := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", what)
	else:
		print("ok   ", what)


func _initialize() -> void:
	var blocks: Node = root.get_node_or_null("Blocks")
	if blocks == null:
		blocks = load("res://scripts/world/blocks.gd").new()
	var tables := Mesher.tables_from(blocks)

	# --- chunk store
	var ch := Chunk.new()
	ch.fill_micro_box(Vector3i(0, 0, 0), Vector3i(4, 2, 4), 3)
	check(ch.cells[0] == Chunk.DETAIL and ch.details.has(0), "half-filled cell becomes detailed")
	ch.fill_micro_box(Vector3i(0, 2, 0), Vector3i(4, 4, 4), 3)
	check(ch.cells[0] == 3 and ch.details.is_empty(), "uniform cell collapses to a full block")
	ch.fill_micro_box(Vector3i(0, 0, 0), Vector3i(4, 4, 4), 0)
	check(ch.cells[0] == 0 and ch.is_empty(), "removal collapses to air")
	var ser := Chunk.new()
	ser.fill_micro_box(Vector3i(2, 2, 2), Vector3i(9, 5, 7), 11)
	var raw := var_to_bytes([ser.cells, PackedInt32Array(ser.details.keys()), PackedByteArray()]).size() + ser.details.size() * 64 + 64
	var blob := ser.serialize()
	var back := Chunk.new()
	check(back.deserialize(blob, raw * 2) and back.get_micro(8, 4, 6) == 11 and back.get_micro(9, 4, 6) == 0, "serialize round trip")

	# Snapshot safety: a worker holding the old detail array must not see later edits.
	var snap := Chunk.new()
	snap.fill_micro_box(Vector3i(0, 0, 0), Vector3i(4, 2, 4), 3)
	var held: PackedByteArray = snap.details[0]
	var held_copy := held.duplicate()
	snap.set_micro(0, 3, 0, 5)
	check(held == held_copy, "editing a detailed cell does not mutate arrays held by workers")

	# --- mesher
	var single := Chunk.new()
	single.set_block(5, 5, 5, 3)
	single.recount()
	var r := _mesh(tables, single)
	check(r.passes[0].idx.size() == 36, "single block -> 6 faces (got %d idx)" % r.passes[0].idx.size())
	check(r.collision.size() == 36, "single block collision has 12 triangles")
	single.set_block(6, 5, 5, 3)
	r = _mesh(tables, single)
	check(r.passes[0].idx.size() == 60, "two touching blocks -> 10 faces (got %d)" % (r.passes[0].idx.size() / 6))
	var slab := Chunk.new()
	slab.fill_micro_box(Vector3i(20, 20, 20), Vector3i(24, 22, 24), 7)
	r = _mesh(tables, slab)
	check(r.passes[0].idx.size() == 36, "slab greedy-merges into 6 quads (got %d)" % (r.passes[0].idx.size() / 6))
	var y_top := -INF
	for v in r.passes[0].verts:
		y_top = maxf(y_top, v.y)
	check(is_equal_approx(y_top, 5.5), "slab top sits at half height (%.2f)" % y_top)
	# A half slab straddling two cells, offset by a quarter.
	var off := Chunk.new()
	off.fill_micro_box(Vector3i(21, 20, 20), Vector3i(25, 22, 24), 7)
	r = _mesh(tables, off)
	check(r.passes[0].idx.size() > 0 and off.details.size() == 2, "offset slab spans two cells")
	var water := Chunk.new()
	water.set_block(1, 1, 1, 10)
	water.set_block(2, 1, 1, 10)
	water.recount()
	r = _mesh(tables, water)
	check(r.passes[2].idx.size() == 60 and r.collision.is_empty(), "water is translucent, culls itself, has no collision")

	# --- generator + timing
	var gen := TerrainGenerator.new(42)
	var h := gen.height_at(10, 10)
	var cy := int(h) / 16
	var t0 := Time.get_ticks_usec()
	var gc := gen.generate(Vector3i(0, cy, 0))
	var gen_ms := (Time.get_ticks_usec() - t0) / 1000.0
	check(not gc.is_empty(), "surface chunk has blocks")
	check(gc.details.size() > 10, "surface uses quarter-height cells (%d)" % gc.details.size())
	var neigh := []
	for dy in range(-1, 2):
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var c := gen.generate(Vector3i(dx, cy + dy, dz))
				neigh.append([c.cells, c.details])
	t0 = Time.get_ticks_usec()
	r = Mesher.new(tables).build(neigh)
	var mesh_ms := (Time.get_ticks_usec() - t0) / 1000.0
	check(r.passes[0].idx.size() > 0, "terrain chunk produces geometry")
	print("PERF gen_ms=%.1f mesh_ms=%.1f tris=%d details=%d" % [gen_ms, mesh_ms, r.passes[0].idx.size() / 3, gc.details.size()])

	# --- column merge: chunk meshes concatenated with shifted indices
	var lower := Chunk.new()
	lower.set_block(1, 15, 1, 3)
	lower.recount()
	var upper := Chunk.new()
	upper.set_block(1, 0, 1, 3)
	upper.fill_micro_box(Vector3i(20, 4, 20), Vector3i(24, 6, 24), 7)
	upper.recount()
	var ra := Mesher.new(tables).build(_alone(lower), 0.0)
	var rb := Mesher.new(tables).build(_alone(upper), 16.0)
	var merged: Array = Mesher.merge_passes([ra.passes, rb.passes])
	var m0: Dictionary = merged[0]
	var ok: bool = m0.verts.size() == ra.passes[0].verts.size() + rb.passes[0].verts.size()
	ok = ok and m0.idx.size() == ra.passes[0].idx.size() + rb.passes[0].idx.size()
	var maxi_ := 0
	for i in m0.idx:
		maxi_ = maxi(maxi_, i)
	ok = ok and maxi_ == m0.verts.size() - 1
	var ymax := -INF
	for v in m0.verts:
		ymax = maxf(ymax, v.y)
	check(ok and is_equal_approx(ymax, 17.5), "column merge keeps all faces, valid indices and y offsets (ymax %.2f)" % ymax)
	# each merged triangle must stay within one chunk (no cross-chunk spikes)
	var spikes := 0
	for t in range(0, m0.idx.size(), 3):
		var a: Vector3 = m0.verts[m0.idx[t]]
		var b2: Vector3 = m0.verts[m0.idx[t + 1]]
		var c2: Vector3 = m0.verts[m0.idx[t + 2]]
		if a.distance_to(b2) > 1.5 or a.distance_to(c2) > 1.5:
			spikes += 1
	check(spikes == 0, "no stretched triangles after merging (%d)" % spikes)

	# --- pieces
	var box := Pieces.place_box(Vector3(0.5, 1.0, 0.5), Vector3.UP, Vector3i(4, 2, 4), 4)
	check(box.position == Vector3(0, 4, 0) and box.size == Vector3(4, 2, 4), "slab on top of block aligns to block (%s)" % box)
	box = Pieces.place_box(Vector3(0.9, 1.5, 0.5), Vector3.UP, Vector3i(4, 2, 4), 1)
	check(box.position.y == 6 and box.position.x == 2, "quarter snap lets a slab sit on a half-height surface, offset (%s)" % box)
	box = Pieces.place_box(Vector3(1.0, 0.3, 0.5), Vector3.RIGHT, Vector3i(4, 2, 4), 2)
	check(box.position.x == 4 and box.position.y == 0, "slab on a wall is flush with it (%s)" % box)
	box = Pieces.break_box(Vector3(0.5, 1.0, 0.5), Vector3.UP, Vector3i(4, 4, 4), 4)
	check(box.position == Vector3(0, 0, 0), "break box is inside the touched block (%s)" % box)
	check(Pieces.oriented(Vector3i(4, 2, 4), 2) == Vector3i(2, 4, 4), "slab can stand on its side")

	print("WORLD_CORE_RESULT failures=%d" % failures)
	quit(1 if failures else 0)


func _mesh(tables: Dictionary, c: Chunk) -> Dictionary:
	var n := []
	for i in 27:
		n.append([c.cells, c.details] if i == 13 else [PackedInt32Array(_air()), {}])
	return Mesher.new(tables).build(n)


func _alone(c: Chunk) -> Array:
	var n := []
	for i in 27:
		n.append([c.cells, c.details] if i == 13 else [_air(), {}])
	return n


func _air() -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(4096)
	return a
