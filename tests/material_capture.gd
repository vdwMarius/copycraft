extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func capture(name: String) -> void:
	for i in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("res://build/" + name + ".png")
	if error != OK:
		quit(1)
func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.player.set_controls_enabled(false)
	for mode in [[1,16,false],[4,64,true],[8,128,true]]:
		scene._apply_material_settings(mode[0],mode[1],mode[2],false)
		scene.hud.setup_material_settings(mode[0],mode[1],mode[2])
		await create_timer(1.0).timeout
		await capture("materials-%s-%s" % [mode[0],mode[1]])
	scene.hud._set_materials_open(true)
	await capture("materials-menu")
	scene.hud._set_materials_open(false)
	scene.player.set_controls_enabled(false)
	var point := Vector2i(-13,-12)
	var base: int = scene.terrain.elevation(point.x,point.y) + 1
	scene.player.position = Vector3(-12.5,base+0.01,-8.8)
	scene.player.camera.look_at(Vector3(-12.5,base+1.9,-11.8))
	scene.relief_layer._refresh_placement()
	await capture("materials-bark")
	quit(0)
