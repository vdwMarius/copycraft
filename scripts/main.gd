extends Node3D

var terrain: Node3D
var player: CharacterBody3D
var hud: Control

func _ready() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var atmosphere := ProceduralSkyMaterial.new()
	atmosphere.sky_top_color = Color("326b92")
	atmosphere.sky_horizon_color = Color("e9d5ad")
	atmosphere.ground_horizon_color = Color("e9d5ad")
	atmosphere.ground_bottom_color = Color("526d69")
	sky.sky_material = atmosphere
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("aacbd4")
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32,-38,0)
	sun.light_color = Color("ffe2af")
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 64.0
	add_child(sun)
	terrain = preload("res://scripts/terrain.gd").new()
	add_child(terrain)
	player = preload("res://scripts/player.gd").new()
	add_child(player)
	hud = preload("res://scripts/hud.gd").new()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	canvas.add_child(hud)
	hud.setup(player)
