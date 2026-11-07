extends Node
## Dev capture: run the game with `-- --capture` (needs a display, e.g. xvfb-run); saves screenshots to build/.
## Also exercises building: places a few pieces in front of the player.

func _ready() -> void:
	var main: Node = get_parent()
	var root := get_tree().root
	var process_frame := get_tree().process_frame
	var t := 0
	while not main.player.controls_enabled and t < 3000:
		await process_frame
		t += 1
		if t % 100 == 0: print("frame ", t, " ", main.world.stats, " bodies ", main.world.bodies.size())
	print("spawned after frames: ", t, " stats ", main.world.stats)
	for i in 120:
		await process_frame
	var p: Player = main.player
	p.toggle_fly()
	p.global_position += Vector3(0, 9, 0)
	p.rotation.y = 0.6
	p.look(Vector2(0, 120))
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shot_world.png")
	# Build a little structure out of mixed pieces right in front of the player.
	var b: Builder = main.builder
	var fwd := -p.global_transform.basis.z
	var base := (p.global_position + Vector3(fwd.x, 0, fwd.z).normalized() * 9.0).floor()
	var gy := floorf(main.world.surface_height(base.x, base.z) * 4.0)
	var q := Vector3(base.x * 4.0, gy, base.z * 4.0)
	var ids := [16, 7, 11, 9, 14]
	main.world.edit_box(AABB(q, Vector3(8, 2, 8)), 16)          # marble slab floor (half height)
	main.world.edit_box(AABB(q + Vector3(0, 2, 0), Vector3(2, 8, 2)), 7)    # pillar
	main.world.edit_box(AABB(q + Vector3(6, 2, 6), Vector3(2, 8, 2)), 7)
	main.world.edit_box(AABB(q + Vector3(1, 10, 1), Vector3(7, 2, 7)), 11)  # offset brick roof slab
	main.world.edit_box(AABB(q + Vector3(3, 2, 3), Vector3(2, 2, 2)), 14)   # half-cube crystal
	main.world.edit_box(AABB(q + Vector3(2, 2, 6), Vector3(4, 4, 1)), 9)    # glass panel
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shot_build.png")
	print("CAPTURE fps=", Engine.get_frames_per_second(), " stats=", main.world.stats, " ghost target=", not b._target.is_empty())
	get_tree().quit()
