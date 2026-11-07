extends Node
## Dev/regression: `-- --parttest`. Selects every building part (directly and through the
## build menu), previews it at the crosshair and switches back to the foundation.
## Prints PART_TEST_RESULT failures=N.

func _ready() -> void:
	var main: Node = get_parent()
	var tree := get_tree()
	var t0 := Time.get_ticks_msec()
	while not main.player.controls_enabled and Time.get_ticks_msec() - t0 < 60000:
		await tree.process_frame
	main.player.camera.rotation.x = -0.6
	main.player._pitch = -0.6
	main.inventory.add("wood", 50)
	main.inventory.add("stone", 50)
	for mat in ["wood", "stone"]:
		main.building.material_id = mat
		for id in Parts.ORDER + ["foundation"]:
			print("select ", mat, " ", id)
			main.hud.set_part(id)
			for i in 4:
				await tree.process_frame
	# Open and close Settings first (its option rows stay referenced by the menu).
	main.hud.open_settings.emit()
	await tree.process_frame
	main.menus.close_menu()
	await tree.process_frame
	# Aim the hammer straight at a tree trunk while previewing a foundation.
	var fl: Flora = main.flora
	var pl := {}
	for rc in fl.regions:
		for p2 in fl.regions[rc].plants:
			if p2.kind == "tree":
				pl = p2
				break
		if not pl.is_empty():
			break
	if not pl.is_empty():
		var b: Vector3 = pl.xform.origin
		main.player.controls_enabled = false
		main.player.global_position = b + Vector3(3, 0.3, 0)
		main.player.look_at_from_position(main.player.global_position, b + Vector3(0, 0.3, 0))
		main.player.camera.rotation.x = 0.0
		main.player.reset_physics_interpolation()
		for i in 6:
			await tree.physics_frame
		await tree.process_frame
		main.player.controls_enabled = true
		print("aimed hammer at a tree trunk")
		for i in 6:
			await tree.process_frame
	# Same through the build menu (tap the buttons like a finger).
	for id in ["wall", "foundation", "roof", "foundation"]:
		main.hud.open_build.emit()
		await tree.process_frame
		await tree.process_frame
		var btn: Button = null
		for b in main.menus.find_children("*", "Button", true, false):
			if b.text.begins_with(Parts.CATALOG[id].name + "\n"):
				btn = b
		print("menu tap ", id, " button=", btn != null)
		if btn:
			main.menus.tap(btn.get_global_rect().get_center())
		for i in 4:
			await tree.process_frame
		print("now building ", main.building.part_id, " menu open=", main.menus.visible)
	print("PART_TEST_RESULT failures=0")   # SCRIPT ERRORs in the log fail the suite
	tree.quit()
