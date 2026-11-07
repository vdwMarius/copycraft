extends RefCounted
const Pack = preload("res://scripts/material_pack.gd")
var grid := 4
var resolution := 64
var relief := true
const DEFAULT_PATH := "user://materials.cfg"

func load_from(path: String = DEFAULT_PATH) -> void:
	# Reset first so corrupt/missing values cannot leak from a previous read.
	grid = 4
	resolution = 64
	relief = true
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	var candidate: Variant = config.get_value("materials", "grid", 4)
	if typeof(candidate) == TYPE_INT and candidate in Pack.GRIDS:
		grid = candidate
	candidate = config.get_value("materials", "resolution", 64)
	if typeof(candidate) == TYPE_INT and candidate in Pack.RESOLUTIONS:
		resolution = candidate
	candidate = config.get_value("materials", "relief", true)
	if typeof(candidate) == TYPE_BOOL:
		relief = candidate

func save_to(path: String = DEFAULT_PATH) -> Error:
	var config := ConfigFile.new()
	config.set_value("materials", "grid", grid)
	config.set_value("materials", "resolution", resolution)
	config.set_value("materials", "relief", relief)
	return config.save(path)
