class_name Hud
extends Control
## In-game touch HUD. All gameplay controls are drawn and hit-tested here so any
## number of fingers can be used at once (joystick + look + buttons). Menus use
## regular Controls.

signal open_settings
signal open_build

const LOOK_TAP_TIME := 0.3      # a touch released sooner than this (without dragging) is a tap
const LOOK_TAP_SLOP := 16.0     # moving further than this turns the touch into camera look
const HOLD_START := 0.2         # a still finger held this long starts harvesting / demolishing
const BREAK_COOLDOWN := 0.25    # pause after each finished hold action (not for digging)
const TOOL_COLORS := [Color(0.55, 0.38, 0.22), Color(0.72, 0.3, 0.22), Color(0.3, 0.5, 0.75)]

var player: Player
var tools: Tools
var building: BuildSystem
var selected_slot := Tools.HAMMER
var stats_text := ""
var menu_open := false

var _buttons := {}           # name -> {pos, r, label}
var _held := {}              # touch index -> button name
var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _look_index := -1
var _look_last := Vector2.ZERO
var _look_start := Vector2.ZERO
var _look_time := 0.0
var _look_moved := 0.0
var _font: Font
var _safe := Rect2()
var _hotbar_rects: Array[Rect2] = []
var _break_progress := 0.0     # 0..1 ring around the held finger
var _broke_this_touch := false
var _breaking := false          # this touch has turned into a hold action (view no longer turns)
var _break_key: Variant = null  # target being worked on; progress resets if it changes
var _cooldown := 0.0
var _toast := ""
var _toast_time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	resized.connect(_layout)
	_layout()


func setup(p: Player, t: Tools, b: BuildSystem) -> void:
	player = p
	tools = t
	building = b
	tools.current = selected_slot


func toast(text: String) -> void:
	_toast = text
	_toast_time = 2.0


func set_part(id: String) -> void:
	building.part_id = id
	_select_slot(Tools.HAMMER)
	toast(Parts.CATALOG[id].name)


func _layout() -> void:
	var size_v := get_viewport_rect().size
	_safe = Rect2(Vector2.ZERO, size_v)
	var win := DisplayServer.window_get_size()
	if win.x > 0 and OS.has_feature("mobile"):
		var sa := DisplayServer.get_display_safe_area()
		var k := size_v / Vector2(win)
		_safe = Rect2(Vector2(sa.position) * k, Vector2(sa.size) * k).intersection(Rect2(Vector2.ZERO, size_v))
	var r := _safe
	var m := 18.0
	var br := r.end - Vector2(m, m)
	_buttons = {
		"jump": {"pos": br + Vector2(-95, -105), "r": 72.0, "label": "JUMP"},
		"fly": {"pos": br + Vector2(-95, -275), "r": 44.0, "label": "FLY"},
		"down": {"pos": br + Vector2(-210, -330), "r": 44.0, "label": "DOWN"},
		"settings": {"pos": Vector2(r.end.x - m - 40, r.position.y + m + 40), "r": 38.0, "label": "MENU"},
		"part": {"pos": Vector2(r.end.x - m - 158, r.position.y + m + 40), "r": 54.0, "label": "PART", "hammer": true},
		"mat": {"pos": Vector2(r.end.x - m - 278, r.position.y + m + 40), "r": 42.0, "label": "MAT", "hammer": true},
		"rotate": {"pos": Vector2(r.end.x - m - 380, r.position.y + m + 40), "r": 38.0, "label": "ROT", "hammer": true},
	}
	# Hotbar centred at the bottom.
	_hotbar_rects.clear()
	var slot := 64.0
	var gap := 8.0
	slot = 84.0
	var count := Tools.NAMES.size()
	var total := count * slot + (count - 1) * gap
	var x0 := r.position.x + (r.size.x - total) * 0.5
	var y0 := r.end.y - slot - 14.0
	for i in count:
		_hotbar_rects.append(Rect2(x0 + i * (slot + gap), y0, slot, slot))
	queue_redraw()


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		queue_redraw()
	if player == null:
		return
	if _joy_index >= 0:
		var v := (_joy_pos - _joy_origin) / 110.0
		if v.length() > 1.0:
			v = v.normalized()
		player.move_input = Vector2(v.x, -v.y)
		player.sprint = v.length() > 0.97
	else:
		player.move_input = Vector2.ZERO
		player.sprint = false
	_update_hold(delta)
	player.jump_held = _is_held("jump")
	player.down_held = _is_held("down")
	if Settings.get_value("show_stats"):
		queue_redraw()


## Hold actions: a still finger held for HOLD_START starts working on whatever is under
## it (dig ground, chop a plant, demolish a part). The time depends on the target and
## on using the right tool. Swiping during a hold moves it to the new target.
func _update_hold(delta: float) -> void:
	if _look_index < 0:
		if tools.aim_screen.x >= 0.0:
			_end_hold()
		return
	if not _breaking:
		var held := Time.get_ticks_msec() / 1000.0 - _look_time
		if _look_moved >= LOOK_TAP_SLOP or held < HOLD_START:
			return   # still a tap, or it became a camera drag
		_breaking = true
		_break_progress = 0.0
	tools.aim_screen = _look_last
	if _cooldown > 0.0:
		_cooldown -= delta
		queue_redraw()
		return
	var info := tools.hold_info(_look_last)
	if info.is_empty():
		_break_progress = 0.0
		queue_redraw()
		return
	if info.key != _break_key:
		_break_key = info.key   # moved onto a different target: start over
		_break_progress = 0.0
	_break_progress += delta / info.time
	if _break_progress >= 1.0:
		_break_progress = 0.0
		_break_key = null
		if tools.complete_hold(_look_last):
			_broke_this_touch = true
			_cooldown = 0.0 if info.kind == "dig" else BREAK_COOLDOWN
			Input.vibrate_handheld(18)
	queue_redraw()


func _end_hold() -> void:
	_break_progress = 0.0
	_breaking = false
	_break_key = null
	tools.aim_screen = Vector2(-1, -1)
	queue_redraw()


func _is_held(name: String) -> bool:
	for i in _held:
		if _held[i] == name:
			return true
	return false


func _hit_button(p: Vector2) -> String:
	for name in _buttons:
		if not _button_visible(name):
			continue
		var b: Dictionary = _buttons[name]
		if p.distance_to(b.pos) <= b.r + 10.0:
			return name
	return ""


func _button_visible(name: String) -> bool:
	if name == "down":
		return player != null and player.flying
	if _buttons[name].get("hammer", false):
		return tools != null and tools.current == Tools.HAMMER
	return true


func _hit_hotbar(p: Vector2) -> int:
	for i in _hotbar_rects.size():
		if _hotbar_rects[i].grow(4).has_point(p):
			return i
	return -1


func _input(event: InputEvent) -> void:
	if menu_open or player == null:
		return
	if event is InputEventScreenTouch:
		_touch(event)
	elif event is InputEventScreenDrag:
		_drag(event)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and event.pressed:
		_desktop_click(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		_desktop_key(event)


func _touch(e: InputEventScreenTouch) -> void:
	var p := e.position
	if e.pressed:
		var b := _hit_button(p)
		if b != "":
			_held[e.index] = b
			_press(b)
			get_viewport().set_input_as_handled()
			return
		var slot := _hit_hotbar(p)
		if slot >= 0:
			_select_slot(slot)
			get_viewport().set_input_as_handled()
			return
		if p.x < _safe.position.x + _safe.size.x * 0.42 and _joy_index < 0:
			_joy_index = e.index
			_joy_origin = p
			_joy_pos = p
		elif _look_index < 0:
			_look_index = e.index
			_look_last = p
			_look_start = p
			_look_time = Time.get_ticks_msec() / 1000.0
			_look_moved = 0.0
			_break_progress = 0.0
			_broke_this_touch = false
			_breaking = false
			_cooldown = 0.0
		get_viewport().set_input_as_handled()
	else:
		if _held.has(e.index):
			_held.erase(e.index)
		if e.index == _joy_index:
			_joy_index = -1
		if e.index == _look_index:
			_look_index = -1
			var dt := Time.get_ticks_msec() / 1000.0 - _look_time
			# Tap = place. A hold that already broke something never places on release.
			if dt < LOOK_TAP_TIME and _look_moved < LOOK_TAP_SLOP and not _breaking and not _broke_this_touch:
				tools.tap(p)
			_end_hold()
		queue_redraw()


func _drag(e: InputEventScreenDrag) -> void:
	if e.index == _joy_index:
		_joy_pos = e.position
		queue_redraw()
	elif e.index == _look_index:
		var d := e.position - _look_last
		_look_last = e.position
		_look_moved += d.length()
		# Once a touch is breaking, swiping moves the break to the block under the
		# finger (progress restarts) instead of turning the camera.
		if not _breaking:
			player.look(d * 1.2)


func _press(b: String) -> void:
	match b:
		"fly":
			player.toggle_fly()
			toast("Flying" if player.flying else "Walking")
		"settings":
			open_settings.emit()
		"part":
			open_build.emit()
		"mat":
			building.material_id = "stone" if building.material_id == "wood" else "wood"
			toast(Parts.MATERIALS[building.material_id].name)
		"rotate":
			building.rotation_steps = (building.rotation_steps + 1) % 4
			toast("Rotated")
	queue_redraw()


func _select_slot(i: int) -> void:
	selected_slot = i
	tools.current = i
	toast(Tools.NAMES[i])
	queue_redraw()


func _desktop_click(e: InputEventMouseButton) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Clicking the HUD with a mouse behaves like a touch.
		var b := _hit_button(e.position)
		if b != "" and e.button_index == MOUSE_BUTTON_LEFT:
			_press(b)
			return
		var slot := _hit_hotbar(e.position)
		if slot >= 0:
			_select_slot(slot)
			return
		if e.button_index == MOUSE_BUTTON_LEFT and not DisplayServer.is_touchscreen_available():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	var centre := get_viewport_rect().size * 0.5
	match e.button_index:
		MOUSE_BUTTON_LEFT:
			tools.complete_hold(centre)
		MOUSE_BUTTON_RIGHT:
			tools.tap(centre)
		MOUSE_BUTTON_WHEEL_UP:
			_select_slot((selected_slot + Tools.NAMES.size() - 1) % Tools.NAMES.size())
		MOUSE_BUTTON_WHEEL_DOWN:
			_select_slot((selected_slot + 1) % Tools.NAMES.size())


func _desktop_key(e: InputEventKey) -> void:
	match e.keycode:
		KEY_R: _press("rotate")
		KEY_G: _press("mat")
		KEY_TAB: open_build.emit()
		KEY_M: open_settings.emit()
		_:
			if e.keycode >= KEY_1 and e.keycode <= KEY_3:
				_select_slot(e.keycode - KEY_1)


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if player == null:
		return
	var center := get_viewport_rect().size * 0.5
	# Crosshair
	draw_line(center - Vector2(11, 0), center + Vector2(11, 0), Color(1, 1, 1, 0.85), 2.0)
	draw_line(center - Vector2(0, 11), center + Vector2(0, 11), Color(1, 1, 1, 0.85), 2.0)
	# Joystick
	if _joy_index >= 0:
		draw_circle(_joy_origin, 110.0, Color(0, 0, 0, 0.22))
		draw_arc(_joy_origin, 110.0, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
		var knob := _joy_origin + (_joy_pos - _joy_origin).limit_length(110.0)
		draw_circle(knob, 46.0, Color(1, 1, 1, 0.45))
	else:
		var hint := Vector2(_safe.position.x + 190, _safe.end.y - 200)
		draw_arc(hint, 100.0, 0, TAU, 48, Color(1, 1, 1, 0.16), 3.0)
	# Buttons
	for name in _buttons:
		if not _button_visible(name):
			continue
		var b: Dictionary = _buttons[name]
		var active: bool = _is_held(name) or (name == "fly" and player.flying)
		draw_circle(b.pos, b.r, Color(0.08, 0.1, 0.14, 0.55) if not active else Color(0.35, 0.75, 1.0, 0.6))
		draw_arc(b.pos, b.r, 0, TAU, 40, Color(1, 1, 1, 0.5), 2.5)
		var label: String = b.label
		match name:
			"part": label = Parts.CATALOG[building.part_id].name
			"mat": label = Parts.MATERIALS[building.material_id].name
		_text_centered(label, b.pos, 18 if label.length() > 5 else 22)
	# Break progress ring around the held finger.
	if _breaking and _look_index >= 0:
		# Thumb-sized ring: sits around the fingertip rather than under it.
		draw_arc(_look_last, 96.0, 0, TAU, 64, Color(0, 0, 0, 0.35), 14.0)
		draw_arc(_look_last, 96.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(_break_progress, 0.0, 1.0), 64, Color(1, 0.6, 0.35, 0.95), 12.0)
	# Tool bar
	for i in _hotbar_rects.size():
		var rc := _hotbar_rects[i]
		var sel := i == selected_slot
		draw_rect(rc, Color(0.05, 0.07, 0.1, 0.62))
		draw_circle(rc.get_center() + Vector2(0, -8), 22.0, TOOL_COLORS[i])
		_text_centered(Tools.NAMES[i].to_upper(), rc.get_center() + Vector2(0, 26), 15)
		draw_rect(rc, Color(1, 0.9, 0.5, 1) if sel else Color(1, 1, 1, 0.35), false, 4.0 if sel else 2.0)
	var hints := ["Tap: raise ground   ·   Hold: dig", "Hold: chop trees, bushes and rocks", "Tap: place %s (%s)   ·   Hold: demolish" % [Parts.CATALOG[building.part_id].name, Parts.MATERIALS[building.material_id].name]]
	_text_centered(hints[selected_slot], Vector2(center.x, _hotbar_rects[0].position.y - 22), 20)
	if Settings.get_value("show_stats"):
		draw_multiline_string_outline(_font, _safe.position + Vector2(16, 30), stats_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, -1, 4, Color(0, 0, 0, 0.6))
		draw_multiline_string(_font, _safe.position + Vector2(16, 30), stats_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, -1, Color(1, 1, 1, 0.92))
	if _toast_time > 0.0:
		_text_centered(_toast, Vector2(center.x, center.y - 120), 30, Color(1, 1, 1, clampf(_toast_time, 0, 1)))


func _text_centered(t: String, pos: Vector2, fs: int, col := Color(1, 1, 1, 0.95)) -> void:
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, pos + Vector2(-w * 0.5 + 1, fs * 0.35 + 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, col.a * 0.6))
	draw_string(_font, pos + Vector2(-w * 0.5, fs * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
