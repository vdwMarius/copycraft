extends Node3D

const Pack = preload("res://scripts/material_pack.gd")
const Settings = preload("res://scripts/material_settings.gd")

var material_settings = Settings.new()
var surface_pack: RefCounted
var surface_material: ShaderMaterial
var relief_layer: Node3D
var _pack_cache: Dictionary = {}
var terrain: Node3D
var player: CharacterBody3D
var hud: Control

func _ready() -> void:
	material_settings.load_from()
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
	hud.setup_material_settings(material_settings.grid, material_settings.resolution, material_settings.relief)
	hud.material_settings_changed.connect(_apply_material_settings)
	relief_layer = preload("res://scripts/surface_relief.gd").new()
	add_child(relief_layer)
	_apply_material_settings(material_settings.grid, material_settings.resolution, material_settings.relief, false)


func _apply_material_settings(grid: int, resolution: int, relief: bool, persist: bool = true) -> void:
	if grid not in Pack.GRIDS or resolution not in Pack.RESOLUTIONS:
		return
	material_settings.grid = grid
	material_settings.resolution = resolution
	material_settings.relief = relief
	if not _pack_cache.has(resolution):
		var pack := Pack.new()
		pack.generate(resolution)
		_pack_cache[resolution] = pack
	surface_pack = _pack_cache[resolution]
	surface_material = surface_pack.make_material(grid, relief)
	terrain.apply_material(surface_material)
	relief_layer.configure(surface_pack, grid, relief, surface_material, terrain, player)
	hud.set_world_stats({"status": "%d×%d GRID · %d×%d TEX · RELIEF %s" % [grid,grid,resolution,resolution,"ON" if relief else "OFF"]})
	if persist and material_settings.save_to() != OK:
		push_warning("Material settings could not be saved; selection remains active for this session.")
