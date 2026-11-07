extends VBoxContainer
## Texture pack manager: list, select, import (.zip) and delete packs.
## Self-contained; embed with `preload("res://scripts/ui/pack_panel.gd").new()`.

const FONT_SIZE := 26
const BUTTON_HEIGHT := 64

var _list: VBoxContainer
var _current: Label
var _status: Label


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var title := _label("Texture packs", 32)
	add_child(title)
	_current = _label("", FONT_SIZE)
	add_child(_current)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	add_child(_list)
	var import_button := _button("Import .zip…")
	import_button.pressed.connect(_on_import)
	add_child(import_button)
	_status = _label("", 22)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	var lib := _lib()
	if lib:
		lib.textures_changed.connect(refresh)
		lib.import_finished.connect(_on_import_finished)
	refresh()


func _lib() -> Node:
	return get_node_or_null("/root/Textures")


func _settings() -> Node:
	return get_node_or_null("/root/Settings")


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	return b


func refresh() -> void:
	var lib := _lib()
	if lib == null or _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	var selected: String = str(_settings().get_value("texture_pack")) if _settings() else str(lib.BUILTIN_ID)
	_current.text = "Active: %s  ·  %d px" % [_pack_name(selected), lib.resolution]
	for pack in lib.list_packs():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var info := _label(pack.name + ("  ✓" if pack.id == selected else ""), FONT_SIZE)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.clip_text = true
		info.tooltip_text = pack.description
		row.add_child(info)
		var select := _button("Use")
		select.custom_minimum_size.x = 120
		select.disabled = pack.id == selected
		select.pressed.connect(_on_select.bind(pack.id))
		row.add_child(select)
		if not pack.builtin:
			var del := _button("Delete")
			del.custom_minimum_size.x = 140
			del.pressed.connect(_on_delete.bind(pack.id, pack.name))
			row.add_child(del)
		_list.add_child(row)


func _pack_name(id: String) -> String:
	for pack in _lib().list_packs():
		if pack.id == id:
			return pack.name
	return id


func _on_select(id: String) -> void:
	var s := _settings()
	if s:
		_status.text = "Building textures…"
		s.set_value("texture_pack", id)


func _on_delete(id: String, display_name: String) -> void:
	if _lib().delete_pack(id):
		_status.text = "Deleted \"%s\"." % display_name
	else:
		_status.text = "Could not delete \"%s\"." % display_name
	refresh()


func _on_import() -> void:
	_status.text = "Choose a texture pack .zip…"
	_lib().open_import_dialog()


func _on_import_finished(result: Dictionary) -> void:
	_status.text = result.get("message", "")
	refresh()
	if result.get("ok", false) and _settings():
		_settings().set_value("texture_pack", result.id)
