extends Control
## Resolution-independent drawn HUD; touch contacts have exclusive ownership.

const INK := Color(0.91, 0.96, 0.94)
const MUTED := Color(0.61, 0.73, 0.73)
const MINT := Color(0.57, 0.94, 0.73)
const PANEL := Color(0.035, 0.075, 0.085, 0.84)
const JOYSTICK_RADIUS := 75.0
const BLOCK_COLORS := [Color("75b975"), Color("ba9570"), Color("82989a"), Color("dabd80"), Color("8bbcc1")]

var player: CharacterBody3D
var _joystick_id := -1
var _look_id := -1
var _jump_id := -1
var _joystick_vector := Vector2.ZERO
var _scale := 1.0
var _joy_center := Vector2.ZERO
var _jump_center := Vector2.ZERO
var _samples: Array[float] = []
var _sample_cursor := 0
var _last_frame_usec := 0
var _refresh := 0.0
var _frame_ms := 0.0
var _p95_ms := 0.0
var _fps := 0
var _draw_calls := 0
var _engine_mb := 0.0
var _video_mb := 0.0
var _backend := ""
var _world_stats: Dictionary = {}
var _focused := true
var _safe_rect := Rect2()


func setup(explorer: CharacterBody3D) -> void:
	player = explorer


func set_world_stats(stats: Dictionary) -> void:
	_world_stats = stats


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backend = RenderingServer.get_current_rendering_method()
	resized.connect(_on_resized)
	_update_layout()


func _update_layout() -> void:
	_safe_rect = Rect2(Vector2.ZERO, size)
	# Android returns display-pixel insets, which need mapping into canvas units.
	if OS.get_name() == "Android":
		var window_size := Vector2(DisplayServer.window_get_size())
		var safe_pixels := Rect2(DisplayServer.get_display_safe_area())
		if window_size.x > 0 and window_size.y > 0 and safe_pixels.has_area():
			safe_pixels.position -= Vector2(DisplayServer.window_get_position())
			safe_pixels = safe_pixels.intersection(Rect2(Vector2.ZERO, window_size))
			if safe_pixels.has_area():
				_safe_rect = Rect2(safe_pixels.position * size / window_size, safe_pixels.size * size / window_size)
	_scale = maxf(0.45, minf(_safe_rect.size.x / 1280.0, _safe_rect.size.y / 720.0))
	_joy_center = Vector2(_safe_rect.position.x + 120.0 * _scale, _safe_rect.end.y - 123.0 * _scale)
	_jump_center = _safe_rect.end - Vector2(112.0, 115.0) * _scale


func _on_resized() -> void:
	_release_touches()
	_update_layout()
	queue_redraw()


func _release_touches() -> void:
	_joystick_id = -1
	_look_id = -1
	_jump_id = -1
	_joystick_vector = Vector2.ZERO
	if is_instance_valid(player):
		player.move_input = Vector2.ZERO


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_focused = false
		_release_touches()
		_last_frame_usec = 0
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		_focused = true
		_last_frame_usec = 0


func _input(event: InputEvent) -> void:
	if not _focused or not is_instance_valid(player):
		return
	if event is InputEventScreenTouch:
		if not event.pressed or event.canceled:
			var owned: bool = event.index == _joystick_id or event.index == _look_id or event.index == _jump_id
			if event.index == _joystick_id:
				_joystick_id = -1
				_joystick_vector = Vector2.ZERO
				player.move_input = Vector2.ZERO
			if event.index == _look_id:
				_look_id = -1
			if event.index == _jump_id:
				_jump_id = -1
			if owned:
				get_viewport().set_input_as_handled()
			return
		if event.position.distance_to(_jump_center) <= 65.0 * _scale and _jump_id == -1:
			_jump_id = event.index
			player.request_jump()
		elif event.position.distance_to(_joy_center) <= JOYSTICK_RADIUS * _scale and _joystick_id == -1:
			_joystick_id = event.index
			_set_joystick(event.position)
		elif event.position.x > size.x * 0.42 and _look_id == -1:
			_look_id = event.index
		else:
			return
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == _joystick_id:
			_set_joystick(event.position)
			get_viewport().set_input_as_handled()
		elif event.index == _look_id:
			player.look_delta(event.relative / _scale)
			get_viewport().set_input_as_handled()


func _set_joystick(touch_position: Vector2) -> void:
	_joystick_vector = ((touch_position - _joy_center) / (65.0 * _scale)).limit_length(1.0)
	var amount := _joystick_vector.length()
	player.move_input = Vector2.ZERO if amount < 0.12 else _joystick_vector.normalized() * ((amount - 0.12) / 0.88)


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _focused and _last_frame_usec > 0:
		var interval := float(now - _last_frame_usec) / 1000.0
		if _samples.size() < 300:
			_samples.append(interval)
		else:
			_samples[_sample_cursor] = interval
			_sample_cursor = (_sample_cursor + 1) % 300
	_last_frame_usec = now if _focused else 0
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.25
		if not _samples.is_empty():
			var ordered := _samples.duplicate()
			ordered.sort()
			_p95_ms = ordered[clampi(ceili(ordered.size() * 0.95) - 1, 0, ordered.size() - 1)]
			var total := 0.0
			for interval in _samples:
				total += interval
			_frame_ms = total / _samples.size()
		_fps = int(Performance.get_monitor(Performance.TIME_FPS))
		_draw_calls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_engine_mb = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
		_video_mb = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	queue_redraw()


func _panel(rect: Rect2, tint: Color = PANEL, border: Color = Color(0.6, 0.8, 0.78, 0.18)) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(14.0 * _scale))
	draw_style_box(style, rect)


func _text(at: Vector2, value: String, font_size: int = 16, tint: Color = INK) -> void:
	draw_string(ThemeDB.fallback_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font_size * _scale), tint)


func _draw() -> void:
	if size.x < 1.0:
		return
	var s := _scale
	var origin := _safe_rect.position
	_panel(Rect2(origin + Vector2(24, 24) * s, Vector2(286, 91) * s))
	draw_circle(origin + Vector2(45, 47) * s, 4 * s, MINT)
	_text(origin + Vector2(58, 53) * s, "COPYCRAFT", 22)
	_text(origin + Vector2(42, 80) * s, "FIRST LIGHT / ANDROID FOUNDATION", 10, MUTED)
	_text(origin + Vector2(42, 99) * s, "FIELD TEST  /  01", 11, MINT)
	var perf_x := _safe_rect.end.x - 334 * s
	var top := origin.y
	_panel(Rect2(perf_x, top + 24 * s, 310 * s, 151 * s))
	_text(Vector2(perf_x + 18 * s, top + 49 * s), "LIVE PERFORMANCE", 11, MINT)
	_text(Vector2(perf_x + 18 * s, top + 77 * s), "%d FPS" % _fps, 25)
	_text(Vector2(perf_x + 135 * s, top + 74 * s), "%.1f ms  |  p95 %.1f" % [_frame_ms, _p95_ms], 12)
	var render_size := get_viewport().get_texture().get_size()
	_text(Vector2(perf_x + 18 * s, top + 98 * s), "%s  •  %d × %d  •  3D %d%%" % [_backend, int(render_size.x), int(render_size.y), roundi(get_viewport().scaling_3d_scale * 100)], 11, MUTED)
	_text(Vector2(perf_x + 18 * s, top + 118 * s), "%d draws  •  engine %.0f MB  •  video %.0f MB" % [_draw_calls, _engine_mb, _video_mb], 11, MUTED)
	_text(Vector2(perf_x + 18 * s, top + 138 * s), "Frame interval · rolling 300 · GPU timing unavailable", 10, MUTED)
	var status := str(_world_stats.get("status", "FINITE SCENE / 96 × 96 BLOCKS"))
	_text(Vector2(perf_x + 18 * s, top + 157 * s), status, 10, MINT)
	var center := size * 0.5
	for axis in [Vector2.RIGHT, Vector2.DOWN]:
		draw_line(center - axis * 8 * s, center - axis * 3 * s, Color(0, 0, 0, 0.45), 4 * s, true)
		draw_line(center + axis * 3 * s, center + axis * 8 * s, Color(0, 0, 0, 0.45), 4 * s, true)
		draw_line(center - axis * 8 * s, center - axis * 3 * s, INK, 1.5 * s, true)
		draw_line(center + axis * 3 * s, center + axis * 8 * s, INK, 1.5 * s, true)
	var bar_origin := Vector2(_safe_rect.get_center().x - 162 * s, _safe_rect.end.y - 88 * s)
	_panel(Rect2(bar_origin, Vector2(324, 64) * s))
	for i in range(5):
		var slot := bar_origin + Vector2(9 + i * 62, 7) * s
		_panel(Rect2(slot, Vector2(58, 50) * s), Color(0.14, 0.24, 0.24, 0.8), MINT if i == 0 else Color(0.5, 0.6, 0.6, 0.1))
		draw_rect(Rect2(slot + Vector2(17, 10) * s, Vector2(25, 25) * s), BLOCK_COLORS[i])
		draw_rect(Rect2(slot + Vector2(17, 10) * s, Vector2(25, 7) * s), BLOCK_COLORS[i].lightened(0.23))
		_text(slot + Vector2(5, 43) * s, str(i + 1), 10, MUTED)
	_text(Vector2(_safe_rect.get_center().x - 92 * s, _safe_rect.end.y - 101 * s), "TERRAIN PALETTE · PREVIEW", 10, MUTED)
	draw_circle(_joy_center, JOYSTICK_RADIUS * s, Color(0.035, 0.075, 0.085, 0.3))
	draw_arc(_joy_center, 74 * s, 0, TAU, 64, Color(0.84, 0.96, 0.9, 0.3), 1.5 * s, true)
	draw_circle(_joy_center + _joystick_vector * 47 * s, 29 * s, Color(0.74, 0.91, 0.84, 0.28))
	draw_arc(_joy_center + _joystick_vector * 47 * s, 29 * s, 0, TAU, 40, Color(0.84, 0.96, 0.9, 0.45), s, true)
	_text(_joy_center + Vector2(-18, 103) * s, "MOVE", 11, MUTED)
	draw_circle(_jump_center, 49 * s, Color(0.035, 0.075, 0.085, 0.65) if _jump_id == -1 else Color(0.25, 0.5, 0.4, 0.7))
	draw_arc(_jump_center, 49 * s, 0, TAU, 48, Color(0.84, 0.96, 0.9, 0.45), 1.5 * s, true)
	draw_line(_jump_center + Vector2(-10, 3) * s, _jump_center + Vector2(0, -8) * s, INK, 2.5 * s, true)
	draw_line(_jump_center + Vector2(0, -8) * s, _jump_center + Vector2(10, 3) * s, INK, 2.5 * s, true)
	_text(_jump_center + Vector2(-17, 77) * s, "JUMP", 11, MUTED)
	if not DisplayServer.is_touchscreen_available():
		_text(Vector2(_safe_rect.get_center().x - 210 * s, top + 33 * s), "WASD  MOVE     MOUSE  LOOK     SPACE  JUMP     ESC  CURSOR", 10, Color(0.9, 0.97, 0.94, 0.8))
