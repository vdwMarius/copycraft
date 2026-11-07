extends Node
## Dev: `-- --stress` streams the world for a while (works headless) and quits.
func _ready() -> void:
	var main: Node = get_parent()
	for i in 900:
		await get_tree().process_frame
		if i % 60 == 0:
			main.player.global_position += Vector3(16, 0, 7)
	print("STRESS done stats=", main.world.stats)
	# Merged column meshes must equal the sum of their chunk meshes, with valid indices.
	var w: VoxelWorld = main.world
	var bad := 0
	for col in w.nodes:
		var mesh: ArrayMesh = w.nodes[col].mesh
		var expect := 0
		for y in TerrainGenerator.WORLD_CHUNKS_Y:
			var c := Vector3i(col.x, y, col.y)
			if w.chunk_passes.has(c):
				for pass_i in 3:
					expect += w.chunk_passes[c][pass_i].idx.size()
		var got := 0
		for si in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(si)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var nv: int = arr[Mesh.ARRAY_VERTEX].size()
			got += idx.size()
			for i in idx:
				if i < 0 or i >= nv:
					bad += 1
					break
		if got != expect and w.column_applied.get(col, -1) == w.column_versions.get(col, 0):
			bad += 1
			print("column ", col, " idx ", got, " expected ", expect)
	print("STRESS_MERGE bad=", bad)
	get_tree().quit()
