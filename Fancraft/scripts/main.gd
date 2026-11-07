extends Node3D
## Scene bootstrap: lighting, environment, world, player, builder and UI.

const SEED := 20261107

var env: Environment
var sun: DirectionalLight3D
var world: VoxelWorld
var player: Player
var builder: Builder
var hud: Hud
var menus: Menus
var block_mats: BlockMaterials
var _fps_hist := PackedFloat32Array()
var _loading: Label


func _ready() -> void:
	_build_environment()
	block_mats = BlockMaterials.new()
	block_mats.set_sun(sun.global_transform.basis.z)  # direction towards the sun
	player = Player.new()
	player.controls_enabled = false
	add_child(player)
	player.position = _find_spawn(TerrainGenerator.new(SEED))
	world = VoxelWorld.new()
	world.name = "World"
	world.setup(SEED, player, block_mats.materials)
	add_child(world)
	player.world = world
	builder = Builder.new()
	builder.world = world
	builder.player = player
	add_child(builder)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.setup(player, builder, world)
	menus = Menus.new()
	menus.hud = hud
	layer.add_child(menus)
	hud.open_settings.connect(func(): _menu(true); menus.open_settings())
	hud.open_blocks.connect(func(): _menu(true); menus.open_blocks())
	menus.closed.connect(func(): _menu(false))
	menus.block_chosen.connect(hud.set_hotbar_block)
	_loading = Label.new()
	_loading.text = "Shaping the world…"
	_loading.add_theme_font_size_override("font_size", 34)
	_loading.set_anchors_preset(Control.PRESET_CENTER)
	layer.add_child(_loading)
	world.spawn_ready.connect(_on_spawn)
	Settings.changed.connect(_apply_setting)
	for k in ["fps_target", "render_scale", "msaa", "shadows", "glow", "render_distance"]:
		_apply_setting(k)
	if "--capture" in OS.get_cmdline_user_args():
		add_child(load("res://scripts/dev/capture.gd").new())
	get_tree().root.focus_exited.connect(func(): player.move_input = Vector2.ZERO)


## Spiral outwards for a dry, fairly flat grass column.
func _find_spawn(gen: TerrainGenerator) -> Vector3:
	for ring in range(0, 40):
		for i in maxi(ring * 8, 1):
			var a := TAU * i / maxf(ring * 8, 1)
			var x := 8.5 + cos(a) * ring * 6.0
			var z := 8.5 + sin(a) * ring * 6.0
			var h := gen.height_at(x, z)
			if h < TerrainGenerator.WATER_LEVEL + 3 or h > 55:
				continue
			var slope := 0.0
			for d in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
				slope = maxf(slope, absf(gen.height_at(x + d.x, z + d.y) - h))
			if slope < 1.2:
				return Vector3(x, h + 2.0, z)
	return Vector3(8.5, gen.height_at(8.5, 8.5) + 2.0, 8.5)


func _on_spawn() -> void:
	var p := player.position
	player.position.y = world.surface_height(p.x, p.z) + 1.2
	player.controls_enabled = true
	_loading.queue_free()
	if not DisplayServer.is_touchscreen_available() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _menu(open: bool) -> void:
	hud.menu_open = open
	player.controls_enabled = not open
	player.move_input = Vector2.ZERO
	if open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not DisplayServer.is_touchscreen_available() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.22, 0.45, 0.78)
	sm.sky_horizon_color = Color(0.78, 0.84, 0.92)
	sm.ground_horizon_color = Color(0.78, 0.84, 0.92)
	sm.ground_bottom_color = Color(0.25, 0.3, 0.35)
	sm.sun_angle_max = 20.0
	sm.sun_curve = 0.08
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.66, 0.64, 0.6)
	env.ambient_light_sky_contribution = 0.45
	env.ambient_light_energy = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.72, 0.8, 0.9)
	env.fog_sun_scatter = 0.25
	env.fog_depth_curve = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 1.25
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 48.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)


func _apply_setting(key: String) -> void:
	var v = Settings.get_value(key)
	var vp := get_viewport()
	match key:
		"fps_target":
			Engine.max_fps = int(v)
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		"render_scale":
			vp.scaling_3d_scale = float(v)
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if float(v) >= 0.99 else Viewport.SCALING_3D_MODE_FSR
		"msaa":
			vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(int(v), 0, 2)]
		"shadows":
			sun.shadow_enabled = int(v) > 0
			sun.directional_shadow_max_distance = 40.0 if int(v) == 1 else 80.0
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if int(v) == 1 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			RenderingServer.directional_shadow_atlas_set_size(2048 if int(v) == 1 else 4096, true)
		"glow":
			env.glow_enabled = bool(v)
		"render_distance":
			var far := float(v) * 16.0
			env.fog_depth_begin = far * 0.55
			env.fog_depth_end = far * 0.98
			player.camera.far = far + 48.0


func _process(delta: float) -> void:
	if not Settings.get_value("show_stats"):
		return
	_fps_hist.append(delta * 1000.0)
	if _fps_hist.size() > 240:
		_fps_hist.remove_at(0)
	var sorted := _fps_hist.duplicate()
	sorted.sort()
	var p95 := sorted[int(sorted.size() * 0.95)] if sorted.size() > 10 else 0.0
	var s := world.stats
	hud.stats_text = "%d fps  p95 %.1f ms | %s | chunks %d meshes %d tris %dk | gen %.1f ms mesh %.1f ms queue %d | %s %dpx" % [
		Engine.get_frames_per_second(), p95, RenderingServer.get_current_rendering_method(),
		s.chunks, s.meshes, s.triangles / 1000, s.gen_ms, s.mesh_ms, s.queue,
		Settings.get_value("texture_pack"), Textures.resolution]
