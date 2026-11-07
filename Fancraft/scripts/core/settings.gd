extends Node
## Persistent player settings (autoload "Settings").  Emits `changed(key)`.

signal changed(key: String)

const PATH := "user://settings.cfg"
const VERSION := 3   # bump to migrate saved settings

const DEFAULTS := {
	"fps_target": 120,           # 30 / 60 / 90 / 120 / 0 (unlimited)
	"render_distance": 6,        # chunk radius
	"render_scale": -1.0,        # 3D resolution scale (0.5..1.0), -1 = auto
	"texture_resolution": 128,   # 16 / 32 / 64 / 128 / 256 / 512
	"texture_pack": "fancraft_default",
	"parallax": 2,               # 0 off, 1 low, 2 medium, 3 high
	"shadows": 1,                # 0 off, 1 low, 2 high
	"glow": true,
	"msaa": 1,                   # 0 off, 1 2x
	"look_sensitivity": 1.0,
	"show_stats": true,
}

const PRESETS := {
	"Performance": {"fps_target": 60, "render_distance": 4, "render_scale": -1.0, "texture_resolution": 32, "parallax": 0, "shadows": 0, "glow": false, "msaa": 0},
	"Balanced": {"fps_target": 60, "render_distance": 6, "render_scale": -1.0, "texture_resolution": 128, "parallax": 1, "shadows": 1, "glow": true, "msaa": 0},
	"Ultra 120": {"fps_target": 120, "render_distance": 8, "render_scale": -1.0, "texture_resolution": 256, "parallax": 2, "shadows": 1, "glow": true, "msaa": 1},
	"Max Fidelity": {"fps_target": 120, "render_distance": 10, "render_scale": -1.0, "texture_resolution": 512, "parallax": 3, "shadows": 2, "glow": true, "msaa": 1},
}

var values := {}


func _init() -> void:
	values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key in DEFAULTS:
			if cfg.has_section_key("settings", key):
				var v = cfg.get_value("settings", key)
				if typeof(v) == typeof(DEFAULTS[key]) or (typeof(v) in [TYPE_INT, TYPE_FLOAT] and typeof(DEFAULTS[key]) in [TYPE_INT, TYPE_FLOAT]):
					values[key] = v
		if int(cfg.get_value("meta", "version", 1)) < 2:
			# 0.4.0: switch to auto resolution and cap MSAA at 2x (full-res 4x MSAA could not hold 120 fps).
			values["render_scale"] = -1.0
			values["msaa"] = mini(int(values["msaa"]), 1)
		if int(cfg.get_value("meta", "version", 1)) < 3:
			# 0.6.0: 4x MSAA removed (20-30 fps on the S26 Ultra).
			values["msaa"] = mini(int(values["msaa"]), 1)
			save()
	else:
		values.merge(_first_run_preset(), true)


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant, persist := true) -> void:
	if values.get(key) == value:
		return
	values[key] = value
	if persist:
		save()
	changed.emit(key)


func apply_preset(preset: String) -> void:
	for key in PRESETS[preset]:
		set_value(key, PRESETS[preset][key], false)
	save()


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", VERSION)
	for key in values:
		cfg.set_value("settings", key, values[key])
	cfg.save(PATH)


## Pick a sensible starting preset from the hardware we are running on.
func _first_run_preset() -> Dictionary:
	if OS.get_name() != "Android":
		return PRESETS["Ultra 120"]
	var cores := OS.get_processor_count()
	var mem: int = OS.get_memory_info().get("physical", 0)
	# Note: the display may report 60 Hz at launch even on 120 Hz panels, so it is not used here.
	if mem >= 11 * 1024 * 1024 * 1024 and cores >= 8:
		return PRESETS["Ultra 120"]
	if mem >= 6 * 1024 * 1024 * 1024:
		return PRESETS["Balanced"]
	return PRESETS["Performance"]
