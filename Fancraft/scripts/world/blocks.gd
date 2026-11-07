extends Node
## Block registry (autoload "Blocks").
##
## Every material is addressed by a small integer id (1..255; 0 = air) so the
## micro-voxel store can use one byte per quarter-cell.  Texture layers are named;
## the TextureLibrary resolves names to Texture2DArray layer indices.

enum Render { OPAQUE, CUTOUT, TRANSLUCENT }

const AIR := 0

# id: [key, display name, top tex, side tex, bottom tex, render, solid, emission]
const DEFS := {
	1: ["grass", "Grass", "grass_top", "grass_side", "dirt", Render.OPAQUE, true, 0.0],
	2: ["dirt", "Dirt", "dirt", "dirt", "dirt", Render.OPAQUE, true, 0.0],
	3: ["stone", "Stone", "stone", "stone", "stone", Render.OPAQUE, true, 0.0],
	4: ["cobble", "Cobblestone", "cobblestone", "cobblestone", "cobblestone", Render.OPAQUE, true, 0.0],
	5: ["sand", "Sand", "sand", "sand", "sand", Render.OPAQUE, true, 0.0],
	6: ["log", "Oak Log", "log_top", "log_side", "log_top", Render.OPAQUE, true, 0.0],
	7: ["planks", "Oak Planks", "planks", "planks", "planks", Render.OPAQUE, true, 0.0],
	8: ["leaves", "Leaves", "leaves", "leaves", "leaves", Render.CUTOUT, true, 0.0],
	9: ["glass", "Glass", "glass", "glass", "glass", Render.TRANSLUCENT, true, 0.0],
	10: ["water", "Water", "water", "water", "water", Render.TRANSLUCENT, false, 0.0],
	11: ["bricks", "Bricks", "bricks", "bricks", "bricks", Render.OPAQUE, true, 0.0],
	12: ["snow", "Snow", "snow", "snow", "snow", Render.OPAQUE, true, 0.0],
	13: ["gravel", "Gravel", "gravel", "gravel", "gravel", Render.OPAQUE, true, 0.0],
	14: ["crystal", "Glow Crystal", "crystal", "crystal", "crystal", Render.TRANSLUCENT, true, 1.4],
	15: ["mossy", "Mossy Stone", "mossy_stone", "mossy_stone", "mossy_stone", Render.OPAQUE, true, 0.0],
	16: ["marble", "Marble", "marble", "marble", "marble", Render.OPAQUE, true, 0.0],
	17: ["terracotta", "Terracotta", "terracotta", "terracotta", "terracotta", Render.OPAQUE, true, 0.0],
	18: ["slate", "Slate Tiles", "slate", "slate", "slate", Render.OPAQUE, true, 0.0],
}

## Every texture name a pack may provide, in stable layer order.
const TEXTURE_NAMES: PackedStringArray = [
	"grass_top", "grass_side", "dirt", "stone", "cobblestone", "sand", "log_top",
	"log_side", "planks", "leaves", "glass", "water", "bricks", "snow", "gravel",
	"crystal", "mossy_stone", "marble", "terracotta", "slate",
]

## Order shown in the build palette.
const PALETTE: PackedInt32Array = [1, 2, 3, 4, 7, 6, 11, 16, 18, 17, 15, 5, 13, 12, 8, 9, 14, 10]

# Flat lookup tables, filled in _init so worker threads can read them lock-free.
var face_layers := PackedInt32Array()   # id*6 + face -> layer
var render_mode := PackedByteArray()    # id -> Render
var solid := PackedByteArray()          # id -> 1 if it has collision
var emission := PackedFloat32Array()    # id -> emissive strength
var names := PackedStringArray()

# Face order shared by mesher: +X, -X, +Y, -Y, +Z, -Z
const FACE_POS_X := 0
const FACE_NEG_X := 1
const FACE_POS_Y := 2
const FACE_NEG_Y := 3
const FACE_POS_Z := 4
const FACE_NEG_Z := 5


func _init() -> void:
	face_layers.resize(256 * 6)
	render_mode.resize(256)
	solid.resize(256)
	emission.resize(256)
	names.resize(256)
	for id in DEFS:
		var d: Array = DEFS[id]
		var top := TEXTURE_NAMES.find(d[2])
		var side := TEXTURE_NAMES.find(d[3])
		var bottom := TEXTURE_NAMES.find(d[4])
		assert(top >= 0 and side >= 0 and bottom >= 0, "Unknown texture for block %s" % d[0])
		for f in 6:
			var layer := side
			if f == FACE_POS_Y:
				layer = top
			elif f == FACE_NEG_Y:
				layer = bottom
			face_layers[id * 6 + f] = layer
		render_mode[id] = d[5]
		solid[id] = 1 if d[6] else 0
		emission[id] = d[7]
		names[id] = d[1]


func is_opaque(id: int) -> bool:
	return id != AIR and render_mode[id] == Render.OPAQUE


func id_of(key: String) -> int:
	for id in DEFS:
		if DEFS[id][0] == key:
			return id
	return AIR
