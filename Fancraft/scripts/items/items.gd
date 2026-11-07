class_name Items
extends RefCounted
## Item registry. Icons are painted from the shared texture arrays (so texture packs
## restyle them too) with a flat colour fallback.

const STACK := 50

# id: [display name, icon texture layer name ("" = colour disc), colour, max stack]
const DEFS := {
	"wood": ["Wood", "log_side", Color(0.55, 0.32, 0.2), 50],
	"stone": ["Stone", "cobblestone", Color(0.6, 0.6, 0.62), 50],
	"dirt": ["Dirt", "dirt", Color(0.5, 0.33, 0.2), 99],
	"sand": ["Sand", "sand", Color(0.93, 0.83, 0.6), 99],
	"fiber": ["Fiber", "grass_top", Color(0.55, 0.8, 0.3), 50],
	"berries": ["Berries", "", Color(0.85, 0.15, 0.3), 30],
	"flint": ["Flint", "slate", Color(0.25, 0.27, 0.32), 30],
}

const ORDER := ["wood", "stone", "dirt", "sand", "fiber", "berries", "flint"]


static func name_of(id: String) -> String:
	return DEFS[id][0] if DEFS.has(id) else id


static func max_stack(id: String) -> int:
	return DEFS[id][3] if DEFS.has(id) else STACK


static func color_of(id: String) -> Color:
	return DEFS[id][2] if DEFS.has(id) else Color.WHITE


## Human readable cost list, e.g. "4 Wood, 2 Stone".
static func describe(cost: Dictionary) -> String:
	var parts := []
	for id in cost:
		parts.append("%d %s" % [cost[id], name_of(id)])
	return ", ".join(parts)
