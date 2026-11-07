class_name Menus
extends Control
## Settings and block-picker overlays (regular Controls, touch via mouse emulation).

signal closed
signal part_chosen(id: String)

var hud: Hud
var inventory: Inventory
var _panel: PanelContainer
var _body: VBoxContainer
var _rows := {}   # setting key -> HBoxContainer of toggle buttons
var _scroll: ScrollContainer
# Touch handling: menus get raw touches (mouse emulation is off so the HUD can
# use many fingers). A short tap activates the button under the finger, a drag scrolls.
var _touch_index := -1
var _touch_start := Vector2.ZERO
var _scroll_start := 0
var _dragging := false


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 24
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.06, 0.08, 0.12, 0.94)
	panel.set_corner_radius_all(18)
	panel.set_content_margin_all(22)
	t.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(12)
		sb.set_content_margin_all(12)
		match state:
			"pressed", "hover_pressed":
				sb.bg_color = Color(0.25, 0.6, 0.95, 0.95)
			"hover":
				sb.bg_color = Color(0.2, 0.25, 0.33, 0.95)
			"focus":
				sb.bg_color = Color(0, 0, 0, 0)
				sb.draw_center = false
			_:
				sb.bg_color = Color(0.14, 0.17, 0.23, 0.95)
		t.set_stylebox(state, "Button", sb)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 8)
	return t


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = make_theme()
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 60
	_panel.offset_right = -60
	_panel.offset_top = 30
	_panel.offset_bottom = -30
	add_child(_panel)


func _clear() -> VBoxContainer:
	for c in _panel.get_children():
		c.queue_free()
	var outer := VBoxContainer.new()
	_panel.add_child(outer)
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	var close := Button.new()
	close.text = "Resume"
	close.custom_minimum_size.y = 64
	close.pressed.connect(close_menu)
	outer.add_child(close)
	return _body


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index < 0:
			_touch_index = event.index
			_touch_start = event.position
			_scroll_start = _scroll.scroll_vertical if _scroll else 0
			_dragging = false
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			if not _dragging:
				tap(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		if event.position.distance_to(_touch_start) > 14.0:
			_dragging = true
		if _dragging and _scroll:
			_scroll.scroll_vertical = _scroll_start - int(event.position.y - _touch_start.y)
		get_viewport().set_input_as_handled()


## Activate whatever button is under `pos` (also used by tests).
func tap(pos: Vector2) -> bool:
	var btn := _button_at(self, pos)
	if btn == null or btn.disabled:
		return false
	if btn.toggle_mode:
		if btn.button_group == null:
			btn.button_pressed = not btn.button_pressed
		else:
			btn.set_pressed_no_signal(true)
	btn.pressed.emit()
	_sync_rows()
	return true


func _button_at(node: Node, pos: Vector2) -> Button:
	# Search children last-to-first so the topmost control wins.
	for i in range(node.get_child_count() - 1, -1, -1):
		var c := node.get_child(i)
		if c is Control and not c.is_visible_in_tree():
			continue
		if c is ScrollContainer and not (c as Control).get_global_rect().has_point(pos):
			continue
		var found := _button_at(c, pos)
		if found:
			return found
		if c is Button and (c as Control).get_global_rect().has_point(pos):
			return c
	return null


func close_menu() -> void:
	visible = false
	closed.emit()


# ------------------------------------------------------------------ settings

func open_settings() -> void:
	_rows.clear()
	var b := _clear()
	_heading(b, "Fancraft settings")
	var presets := HBoxContainer.new()
	for p in Settings.PRESETS:
		var btn := _button(p)
		btn.pressed.connect(func(): Settings.apply_preset(p); _sync_rows())
		presets.add_child(btn)
	_row(b, "Quality preset", presets)
	_choice(b, "Game mode", "creative", [["Survival", false], ["Creative", true]])
	_choice(b, "Frame rate cap", "fps_target", [["30", 30], ["60", 60], ["90", 90], ["120", 120], ["Max", 0]])
	_choice(b, "View distance", "render_distance", [["3", 3], ["4", 4], ["6", 6], ["8", 8], ["10", 10], ["12", 12]])
	_choice(b, "3D resolution", "render_scale", [["Auto", -1.0], ["50%", 0.5], ["67%", 0.67], ["75%", 0.75], ["90%", 0.9], ["100%", 1.0]])
	_choice(b, "Texture resolution", "texture_resolution", [["16", 16], ["32", 32], ["64", 64], ["128", 128], ["256", 256], ["512", 512], ["Pack", 0]])
	_choice(b, "Shadows", "shadows", [["Off", 0], ["Low", 1], ["High", 2]])
	_choice(b, "Anti-aliasing", "msaa", [["Off", 0], ["2×", 1]])
	_choice(b, "Glow", "glow", [["Off", false], ["On", true]])
	_choice(b, "Look sensitivity", "look_sensitivity", [["0.5", 0.5], ["0.75", 0.75], ["1", 1.0], ["1.5", 1.5], ["2", 2.0]])
	_choice(b, "Performance stats", "show_stats", [["Hide", false], ["Show", true]])
	_heading(b, "Texture packs")
	var pack_path := "res://scripts/ui/pack_panel.gd"
	if ResourceLoader.exists(pack_path):
		b.add_child(load(pack_path).new())
	_heading(b, "Controls")
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = "Left side: move (push to the edge to sprint). Right side: drag to look. Tools (bottom): SHOVEL - tap raises ground, hold digs. AXE - hold chops trees, bushes and rocks. HAMMER - aim the hologram with the crosshair, tap to build, hold a part to demolish; PART picks what to build, MAT wood/stone, ROT rotates. Desktop: WASD, mouse, LMB hold-action, RMB tap-action, 1-3 tools, Tab build menu, G material, R rotate, F fly, M menu."
	b.add_child(help)
	visible = true


func _heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	parent.add_child(l)


func _button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(84, 58)
	return btn


func _row(parent: Control, label: String, content: Control) -> void:
	var row := VBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	row.add_child(l)
	row.add_child(content)
	parent.add_child(row)


func _choice(parent: Control, label: String, key: String, options: Array) -> void:
	var box := HBoxContainer.new()
	var group := ButtonGroup.new()
	for o in options:
		var btn := _button(o[0])
		btn.toggle_mode = true
		btn.button_group = group
		btn.set_meta("value", o[1])
		btn.pressed.connect(func(): Settings.set_value(key, o[1]))
		box.add_child(btn)
	_rows[key] = box
	_row(parent, label, box)
	_sync_rows()


func _sync_rows() -> void:
	for key in _rows:
		var current = Settings.get_value(key)
		for btn: Button in _rows[key].get_children():
			var v = btn.get_meta("value")
			var same: bool = (typeof(v) == typeof(current) and v == current) or (typeof(v) in [TYPE_INT, TYPE_FLOAT] and typeof(current) in [TYPE_INT, TYPE_FLOAT] and is_equal_approx(float(v), float(current)))
			btn.set_pressed_no_signal(same)


# ------------------------------------------------------------------ build menu

func open_build() -> void:
	var b := _clear()
	_heading(b, "Build")
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for id in Parts.ORDER:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(190, 110)
		var mat: String = hud.building.material_id if hud else "wood"
		var cost := Parts.cost(id, mat)
		btn.text = "%s\n%s" % [Parts.CATALOG[id].name, Items.describe(cost)]
		if inventory and not inventory.has_all(cost):
			btn.modulate = Color(1, 0.75, 0.75, 0.75)   # can't afford yet (still selectable)
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(func(): part_chosen.emit(id); close_menu())
		grid.add_child(btn)
	b.add_child(grid)
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Aim with the crosshair: the hologram shows where the part snaps (green = OK, red = blocked). Tap anywhere to place. Walls snap to the nearest edge of a foundation or floor; aim at the top of walls for upper floors and roofs. MAT switches wood / stone, ROT turns roofs and stairs. Hold on a part to demolish it."
	b.add_child(note)
	visible = true


# ------------------------------------------------------------------ inventory

func open_inventory() -> void:
	var b := _clear()
	_heading(b, "Bag" + ("  (creative: building is free)" if inventory.creative else ""))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for i in Inventory.SLOTS:
		var slot: Dictionary = inventory.slots[i]
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(118, 118)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.15, 0.2, 0.95)
		sb.set_corner_radius_all(12)
		sb.set_border_width_all(2)
		sb.border_color = Color(1, 1, 1, 0.12)
		panel.add_theme_stylebox_override("panel", sb)
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		panel.add_child(box)
		if not slot.is_empty():
			var icon := TextureRect.new()
			icon.texture = ItemIcons.get_icon(slot.id)
			icon.custom_minimum_size = Vector2(56, 56)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			box.add_child(icon)
			var l := Label.new()
			l.text = "%s ×%d" % [Items.name_of(slot.id), slot.n]
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.add_theme_font_size_override("font_size", 17)
			box.add_child(l)
		grid.add_child(panel)
	b.add_child(grid)
	var sort := _button("Sort")
	sort.custom_minimum_size = Vector2(160, 58)
	sort.pressed.connect(func(): inventory.sort(); open_inventory())
	b.add_child(sort)
	var tip := Label.new()
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.text = "Chop trees (axe) for wood, break rocks for stone and flint, pick bushes for fiber and berries, dig for dirt, sand and stone. Building parts cost materials; demolishing refunds them."
	b.add_child(tip)
	visible = true
