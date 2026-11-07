extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	await create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("res://build/first-light.png")
	quit(0 if error == OK else 1)
