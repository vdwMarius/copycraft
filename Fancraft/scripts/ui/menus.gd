class_name Menus
extends Control
## Settings and block-picker overlays (regular Controls, touch via mouse emulation).

signal closed
signal block_chosen(id: int)

var hud: Hud
var _panel: PanelContainer
var _body: VBoxContainer
var _rows := {}   # setting key -> HBoxContainer of toggle buttons


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
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = make_theme()
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	_choice(b, "Frame rate cap", "fps_target", [["30", 30], ["60", 60], ["90", 90], ["120", 120], ["Max", 0]])
	_choice(b, "View distance", "render_distance", [["3", 3], ["4", 4], ["6", 6], ["8", 8], ["10", 10], ["12", 12]])
	_choice(b, "Render scale", "render_scale", [["50%", 0.5], ["67%", 0.67], ["75%", 0.75], ["90%", 0.9], ["100%", 1.0]])
	_choice(b, "Texture resolution", "texture_resolution", [["16", 16], ["32", 32], ["64", 64], ["128", 128], ["256", 256], ["512", 512], ["Pack", 0]])
	_choice(b, "3D surface depth", "parallax", [["Off", 0], ["Low", 1], ["Medium", 2], ["High", 3]])
	_choice(b, "Shadows", "shadows", [["Off", 0], ["Low", 1], ["High", 2]])
	_choice(b, "Anti-aliasing", "msaa", [["Off", 0], ["2×", 1], ["4×", 2]])
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
	help.text = "Left side: move (push to the edge to sprint). Right side: drag to look, tap to build/break at that spot. BUILD button acts at the crosshair. MODE switches build/break. PIECE cycles shapes, ROT turns them, SNAP sets how pieces align (quarter / half / block). PICK copies the material you are looking at. Desktop: WASD, mouse, LMB break, RMB place, R rotate, T piece, G snap, F fly, Tab blocks, M menu."
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


# ------------------------------------------------------------------ block picker

func open_blocks() -> void:
	var b := _clear()
	_heading(b, "Choose a material")
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for id in Blocks.PALETTE:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 120)
		btn.text = Blocks.names[id]
		btn.icon = hud.block_icon(id) if hud else null
		btn.expand_icon = false
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_font_size_override("font_size", 18)
		btn.pressed.connect(func(): block_chosen.emit(id); close_menu())
		grid.add_child(btn)
	b.add_child(grid)
	visible = true
