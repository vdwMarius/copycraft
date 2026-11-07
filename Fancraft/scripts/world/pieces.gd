class_name Pieces
extends RefCounted
## Building pieces, measured in quarter-blocks (1 = 0.25 block).

# name, size (x, y, z) in quarters, icon glyph
const LIST := [
	["Block", Vector3i(4, 4, 4)],
	["Slab", Vector3i(4, 2, 4)],
	["Thin slab", Vector3i(4, 1, 4)],
	["Half cube", Vector3i(2, 2, 2)],
	["Quarter", Vector3i(1, 1, 1)],
	["Pillar", Vector3i(2, 4, 2)],
	["Beam", Vector3i(4, 2, 2)],
	["Panel", Vector3i(4, 4, 1)],
	["Post", Vector3i(1, 4, 1)],
]

## Snap step along the surface, in quarters.
const SNAPS := [["Quarter", 1], ["Half", 2], ["Block", 4]]


## Size after `rot` quarter-turn orientations: 0 = as listed, 1 = turned around Y,
## 2 = laid on its side (X), 3 = laid on its side (Z).
static func oriented(size: Vector3i, rot: int) -> Vector3i:
	match rot % 4:
		1: return Vector3i(size.z, size.y, size.x)
		2: return Vector3i(size.y, size.x, size.z)
		3: return Vector3i(size.x, size.z, size.y)
	return size


## Placement box (in world quarter coordinates) for a piece placed against a surface.
## `hit` is the world-space hit point, `normal` the surface normal (axis aligned).
static func place_box(hit: Vector3, normal: Vector3, size: Vector3i, snap: int) -> AABB:
	var q := hit * 4.0
	var n := Vector3i(roundi(normal.x), roundi(normal.y), roundi(normal.z))
	var start := Vector3i.ZERO
	for axis in 3:
		var s: int = size[axis]
		if n[axis] != 0:
			# Flush against the surface along the normal.
			var plane := roundi(q[axis])
			start[axis] = plane if n[axis] > 0 else plane - s
		else:
			# Centre the piece on the touch point, then snap on the surface.
			var c := q[axis] - s * 0.5
			start[axis] = floori(c / snap + 0.5) * snap if snap > 1 else roundi(c)
	return AABB(Vector3(start), Vector3(size))


## Removal box: the same piece footprint, but on the inside of the touched surface.
static func break_box(hit: Vector3, normal: Vector3, size: Vector3i, snap: int) -> AABB:
	var box := place_box(hit, normal, size, snap)
	var n := Vector3i(roundi(normal.x), roundi(normal.y), roundi(normal.z))
	var shift := Vector3.ZERO
	for axis in 3:
		if n[axis] != 0:
			shift[axis] = -n[axis] * size[axis]
	box.position += shift
	return box
