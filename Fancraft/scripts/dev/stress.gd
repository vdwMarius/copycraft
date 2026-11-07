extends Node
## Dev: `-- --stress` streams the world for a while (works headless) and quits.
func _ready() -> void:
	var main: Node = get_parent()
	for i in 900:
		await get_tree().process_frame
		if i % 60 == 0:
			main.player.global_position += Vector3(16, 0, 7)
	print("STRESS done stats=", main.world.stats)
	get_tree().quit()
