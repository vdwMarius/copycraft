extends SceneTree
## Display-only visual check: renders the cracking overlay at several stages to build/cracks.png.

func _initialize() -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(2.2, 2.4, 3.6)
	cam.look_at(Vector3(2.0, 0.5, 0.5))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	root.add_child(light)
	var shader := load("res://shaders/cracks.gdshader")
	for i in 4:
		var block := MeshInstance3D.new()
		var bm := BoxMesh.new()
		block.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.75, 0.62, 0.45)
		block.material_override = mat
		block.position = Vector3(i * 1.3 + 0.5, 0.5, 0.5)
		root.add_child(block)
		var cracks := MeshInstance3D.new()
		cracks.mesh = bm
		var cm := ShaderMaterial.new()
		cm.shader = shader
		cm.set_shader_parameter("progress", [0.15, 0.4, 0.7, 0.95][i])
		cracks.material_override = cm
		cracks.position = block.position
		cracks.scale = Vector3.ONE * 1.012
		root.add_child(cracks)
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/cracks.png")
	quit()
