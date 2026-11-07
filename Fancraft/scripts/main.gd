extends Node3D
## Scene bootstrap: lighting, environment, terrain + vegetation, player, tools,
## building and UI.

const SEED := 20261107

var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var terrain: SmoothTerrain
var vegetation: Node3D
var flora: Flora
var building: BuildSystem
var tools: Tools
var inventory: Inventory
var player: Player
var hud: Hud
var menus: Menus
var _fps_hist := PackedFloat32Array()
var _scale := 1.0
var _auto_scale := false
var _auto_t := 0.0
var _auto_frames := 0
var _auto_missed := 0
var _auto_ceiling := 1.0
var _auto_ceiling_until := 0.0
var _auto_last_up := 0.0
var _loading: Label


func _ready() -> void:
	_build_environment()
	player = Player.new()
	player.controls_enabled = false
	add_child(player)
	terrain = SmoothTerrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup(SEED, player)
	terrain.set_sun(sun.global_transform.basis.z)  # direction towards the sun
	PropMeshes.refresh_textures()
	PartMeshes.refresh_textures()
	Textures.textures_changed.connect(PropMeshes.refresh_textures)
	Textures.textures_changed.connect(PartMeshes.refresh_textures)
	vegetation = Vegetation.create(terrain.terrain)
	flora = Flora.new()
	flora.name = "Flora"
	flora.setup(terrain.shape, player)
	add_child(flora)
	player.position = _find_spawn(terrain.shape)
	player.terrain = terrain
	inventory = Inventory.new()
	inventory.creative = Settings.get_value("creative")
	Textures.textures_changed.connect(ItemIcons.clear)
	building = BuildSystem.new()
	building.inventory = inventory
	building.name = "Buildings"
	building.terrain = terrain
	building.player = player
	add_child(building)
	tools = Tools.new()
	tools.player = player
	tools.terrain = terrain
	tools.building = building
	tools.flora = flora
	tools.inventory = inventory
	add_child(tools)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.setup(player, tools, building)
	hud.inventory = inventory
	tools.message.connect(hud.toast)
	inventory.gained.connect(hud.add_pickup)
	menus = Menus.new()
	menus.hud = hud
	menus.inventory = inventory
	layer.add_child(menus)
	hud.open_settings.connect(func(): _menu(true); menus.open_settings())
	hud.open_build.connect(func(): _menu(true); menus.open_build())
	hud.open_bag.connect(func(): _menu(true); menus.open_inventory())
	menus.closed.connect(func(): _menu(false))
	menus.part_chosen.connect(hud.set_part)
	_loading = Label.new()
	_loading.text = "Shaping the world…"
	_loading.add_theme_font_size_override("font_size", 34)
	_loading.set_anchors_preset(Control.PRESET_CENTER)
	layer.add_child(_loading)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	Settings.changed.connect(_apply_setting)
	for k in ["fps_target", "render_scale", "msaa", "shadows", "glow", "render_distance"]:
		_apply_setting(k)
	if "--parttest" in OS.get_cmdline_user_args():
		add_child(load("res://scripts/dev/part_test.gd").new())
	if "--inputtest" in OS.get_cmdline_user_args():
		add_child(load("res://scripts/dev/input_test.gd").new())
	if "--capture" in OS.get_cmdline_user_args():
		add_child(load("res://scripts/dev/capture.gd").new())
	get_tree().root.focus_exited.connect(func(): player.move_input = Vector2.ZERO)


## Spiral outwards for a dry, fairly flat spot.
func _find_spawn(gen: TerrainShape) -> Vector3:
	for ring in range(0, 40):
		for i in maxi(ring * 8, 1):
			var a := TAU * i / maxf(ring * 8, 1)
			var x := 8.5 + cos(a) * ring * 6.0
			var z := 8.5 + sin(a) * ring * 6.0
			var h := gen.height_at(x, z)
			if h < TerrainShape.WATER_LEVEL + 3 or h > 55:
				continue
			var slope := 0.0
			for d in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
				slope = maxf(slope, absf(gen.height_at(x + d.x, z + d.y) - h))
			if slope < 1.2:
				return Vector3(x, h + 2.0, z)
	return Vector3(8.5, gen.height_at(8.5, 8.5) + 2.0, 8.5)


func _on_spawn() -> void:
	var p := player.position
	player.position.y = terrain.height_at(p.x, p.z) + 1.5
	player.controls_enabled = true
	_loading.queue_free()
	_loading = null
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
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	# Warm sun, cool sky-lit shade: the classic stylised lighting split.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.75
	env.ambient_light_color = Color(0.58, 0.64, 0.75)
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15
	env.tonemap_white = 4.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.7, 0.82, 0.95)
	env.fog_sun_scatter = 0.35
	env.fog_depth_curve = 1.8
	env.fog_sky_affect = 0.12
	env.fog_height = 26.0
	env.fog_height_density = 0.015
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_strength = 0.9
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -32, 0)
	sun.light_color = Color(1.0, 0.9, 0.74)
	sun.light_energy = 1.45
	sun.light_angular_distance = 0.8
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
			_auto_scale = float(v) < 0.0
			_set_scale(0.8 if _auto_scale else float(v))
		"msaa":
			vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(int(v), 0, 2)]
		"shadows":
			var q := int(v)
			sun.shadow_enabled = q > 0
			sun.shadow_blur = 1.2
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 48.0 if q == 1 else 80.0
			RenderingServer.directional_shadow_atlas_set_size(2048 if q == 1 else 4096, true)
		"glow":
			env.glow_enabled = bool(v)
		"creative":
			if inventory:
				inventory.creative = bool(v)
		"render_distance":
			var far := float(v) * 16.0
			env.fog_depth_begin = far * 0.7
			env.fog_depth_end = far * 0.98
			player.camera.far = far + 48.0


func _set_scale(scale: float) -> void:
	_scale = clampf(scale, 0.5, 1.0)
	var vp := get_viewport()
	vp.scaling_3d_scale = _scale
	# FSR upscaling needs the Vulkan renderers; the OpenGL fallback uses bilinear.
	var fsr_ok := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if _scale < 0.99 and fsr_ok else Viewport.SCALING_3D_MODE_BILINEAR


## Auto resolution: lower the 3D render scale when frames run over budget, and probe
## upwards slowly when there is headroom. GPU render time is used when the driver reports
## it; otherwise missed frames are the signal. Changes are rate-limited because each
## one reallocates the render buffers.
func _auto_resolution(delta: float) -> void:
	if not _auto_scale or not player.controls_enabled:
		return
	var target: int = Settings.get_value("fps_target")
	var budget := 1.0 / float(target if target > 0 else 120)
	_auto_t += delta
	_auto_frames += 1
	if delta > budget * 1.3:
		_auto_missed += 1
	if _auto_t < 1.0:
		return
	var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	var miss_ratio := float(_auto_missed) / maxf(_auto_frames, 1)
	var now := Time.get_ticks_msec() / 1000.0
	if miss_ratio > 0.1 or (gpu_ms > 0.0 and gpu_ms > budget * 1000.0 * 0.92):
		_auto_ceiling = _scale
		_auto_ceiling_until = now + 20.0
		_set_scale(_scale - 0.05)
	elif _scale < 1.0 and miss_ratio < 0.02:
		var headroom := gpu_ms > 0.0 and gpu_ms < budget * 1000.0 * 0.7
		var ceiling_ok := now > _auto_ceiling_until or _scale + 0.05 < _auto_ceiling
		if ceiling_ok and (headroom or (gpu_ms <= 0.0 and now - _auto_last_up > 6.0)):
			_auto_last_up = now
			_set_scale(_scale + 0.05)
	_auto_t = 0.0
	_auto_frames = 0
	_auto_missed = 0


func _process(delta: float) -> void:
	if not player.controls_enabled and _loading and terrain.has_ground_below(player.position, [player.get_rid()]):
		_on_spawn()
	_auto_resolution(delta)
	if not Settings.get_value("show_stats"):
		return
	_fps_hist.append(delta * 1000.0)
	if _fps_hist.size() > 240:
		_fps_hist.remove_at(0)
	var sorted := _fps_hist.duplicate()
	sorted.sort()
	var p95 := sorted[int(sorted.size() * 0.95)] if sorted.size() > 10 else 0.0
	var vp_rid := get_viewport().get_viewport_rid()
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var cpu_ms := RenderingServer.viewport_get_measured_render_time_cpu(vp_rid) + Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
	hud.stats_text = "%d fps  p95 %.1f ms | cpu %.1f ms  gpu %.1f ms | draws %d | 3D %d%%%s | %s" % [
		Engine.get_frames_per_second(), p95, cpu_ms, gpu_ms, draws, roundi(_scale * 100),
		" auto" if _auto_scale else "", RenderingServer.get_current_rendering_method()]
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	hud.stats_text += "\ntris %dk | parts %d | %s %dpx" % [
		prims / 1000, building.parts.size(), Settings.get_value("texture_pack"), Textures.resolution]
