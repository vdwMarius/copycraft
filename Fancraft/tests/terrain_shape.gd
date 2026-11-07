extends SceneTree
## The native generator graph must match TerrainShape.height_at (spawn, plants, tests rely
## on it). Prints TERRAIN_SHAPE_RESULT failures=N.

func _initialize() -> void:
	var failures := 0
	var shape := TerrainShape.new(20261107)
	var gen = shape.build_generator()
	var SDF = ClassDB.class_get_integer_constant("VoxelBuffer", "CHANNEL_SDF")
	var worst := 0.0
	var lo := INF
	var hi := -INF
	for k in 12:
		var x := float(k * 97 - 500)
		var z := float(k * 61 - 300)
		var h := shape.height_at(x, z)
		lo = minf(lo, h)
		hi = maxf(hi, h)
		var buf = ClassDB.instantiate("VoxelBuffer")
		buf.create(1, 16, 1)
		var oy := int(floor(h)) - 8
		gen.generate_block(buf, Vector3i(int(x), oy, int(z)), 0)
		for ly in 16:
			var expect := oy + ly - h
			worst = maxf(worst, absf(buf.get_voxel_f(0, ly, 0, SDF) - expect))
	print("max |graph - gdscript| = %.3f, sampled heights %.1f..%.1f" % [worst, lo, hi])
	if worst > 0.1:
		failures += 1
		printerr("FAIL: generator graph and GDScript height disagree")
	# Smoothness: neighbouring metres should not jump much on most of the map.
	var steep := 0
	for k in 400:
		var x := float((k * 37) % 800 - 400)
		var z := float((k * 53) % 800 - 400)
		if absf(shape.height_at(x + 1, z) - shape.height_at(x, z)) > 1.2:
			steep += 1
	print("steep samples: %d / 400" % steep)
	if steep > 40:
		failures += 1
		printerr("FAIL: terrain is too jagged")
	print("TERRAIN_SHAPE_RESULT failures=%d" % failures)
	quit(1 if failures else 0)
