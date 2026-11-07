class_name Parts
extends RefCounted
## Building-part catalogue shared by the building system (snapping, placement) and
## PartMeshes (visuals + collision). Units are metres; +Y up; walls run along X and
## face ±Z. Each part's local origin is the centre of its footprint at FLOOR LEVEL
## (the height you stand on). Its geometry spans y from `base` to `base + size.y`,
## so foundations and floors sit below their origin (their top is the floor) and
## walls / stairs / roofs rise above it. One storey = WALL_H; an upper floor panel's
## top is flush with the wall tops below it.

const GRID := 2.0          # building grid cell (metres)
const WALL_H := 2.4        # storey height

# kind: "cell" occupies a grid cell (foundations, floors, stairs, roofs),
#       "edge" sits on a cell edge (walls), "post" sits on a cell corner.
const CATALOG := {
	"foundation": {"name": "Foundation", "kind": "cell", "size": Vector3(2.0, 0.8, 2.0), "base": -0.8},
	"floor": {"name": "Floor", "kind": "cell", "size": Vector3(2.0, 0.2, 2.0), "base": -0.2},
	"wall": {"name": "Wall", "kind": "edge", "size": Vector3(2.0, 2.4, 0.2), "base": 0.0},
	"doorway": {"name": "Doorway", "kind": "edge", "size": Vector3(2.0, 2.4, 0.2), "base": 0.0, "opening": Rect2(-0.5, 0.0, 1.0, 2.0)},
	"window": {"name": "Window wall", "kind": "edge", "size": Vector3(2.0, 2.4, 0.2), "base": 0.0, "opening": Rect2(-0.5, 1.0, 1.0, 0.8)},
	"half_wall": {"name": "Half wall", "kind": "edge", "size": Vector3(2.0, 1.2, 0.2), "base": 0.0},
	"roof": {"name": "Roof (45°)", "kind": "cell", "size": Vector3(2.0, 2.0, 2.0), "base": 0.0},
	"stairs": {"name": "Stairs", "kind": "cell", "size": Vector3(2.0, 2.4, 2.0), "base": 0.0},
	"pillar": {"name": "Pillar", "kind": "post", "size": Vector3(0.3, 2.4, 0.3), "base": 0.0},
	"beam": {"name": "Beam", "kind": "edge", "size": Vector3(2.0, 0.3, 0.3), "base": 2.1},
}

## Order in the build menu.
const ORDER := ["foundation", "floor", "wall", "doorway", "window", "half_wall", "roof", "stairs", "pillar", "beam"]

const MATERIALS := {
	"wood": {"name": "Wood"},
	"stone": {"name": "Stone"},
}

# Shape notes for PartMeshes (must match collision):
# - roof: a 45° slab rising from y=0 at z=+1 to y=2 at z=-1 (thickness ~0.15), spanning
#   x in [-1, 1], with a small overhang allowed visually only.
# - stairs: 8 steps rising from y=0 at z=+1 to y=2.4 at z=-1, x in [-0.9, 0.9],
#   with side stringers.
# - doorway / window: a wall with a rectangular opening (Rect2 in x / y), framed.


## Material cost of one part (wood parts cost wood; stone parts cost mostly stone,
## with a little wood for roofs / stairs framing). Demolishing refunds it in full.
const COST_UNITS := {
	"foundation": 6, "floor": 3, "wall": 4, "doorway": 3, "window": 3, "half_wall": 2,
	"roof": 4, "stairs": 4, "pillar": 2, "beam": 2,
}


static func cost(part_id: String, material_id: String) -> Dictionary:
	var n: int = COST_UNITS.get(part_id, 2)
	if material_id == "stone":
		var c := {"stone": n}
		if part_id in ["roof", "stairs"]:
			c["wood"] = 1
		return c
	return {"wood": n}
