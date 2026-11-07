class_name Chunk
extends RefCounted
## 16³ block cells. A cell is air (0), a full block (1..255) or DETAIL (-1).
## Detailed cells hold 4×4×4 quarter-cells of material ids in `details`.
##
## Mutation rule: packed arrays and dictionaries are shared BY REFERENCE in Godot 4.
## Worker threads mesh from references to `cells`, `details` and the detail arrays,
## so published chunks are only changed after copying (see VoxelWorld.edit_box and
## set_micro, which duplicates a detail array before writing to it).

const SIZE := 16
const VOLUME := 4096
const SUB := 4
const SUB_VOLUME := 64
const DETAIL := -1

var coord := Vector3i.ZERO
var cells := PackedInt32Array()
var details := {}            # cell index -> PackedByteArray(64)
var edited := false          # true once a player changed it (needs saving)
var solid_count := 0         # non-air cells, used to skip empty chunks


func _init(c := Vector3i.ZERO) -> void:
	coord = c
	cells.resize(VOLUME)


static func index(x: int, y: int, z: int) -> int:
	return x + (z << 4) + (y << 8)


static func sub_index(x: int, y: int, z: int) -> int:
	return x + (z << 2) + (y << 4)


## Material at chunk-local quarter-cell coordinates (0..63).
func get_micro(mx: int, my: int, mz: int) -> int:
	var ci := index(mx >> 2, my >> 2, mz >> 2)
	var c := cells[ci]
	if c != DETAIL:
		return c
	return details[ci][sub_index(mx & 3, my & 3, mz & 3)]


func get_block(x: int, y: int, z: int) -> int:
	return cells[index(x, y, z)]


func set_block(x: int, y: int, z: int, id: int) -> void:
	var ci := index(x, y, z)
	if cells[ci] == DETAIL:
		details.erase(ci)
	cells[ci] = id


## Write one quarter-cell. Call `compact_cell` afterwards (or use `fill_micro_box`).
func set_micro(mx: int, my: int, mz: int, id: int) -> void:
	var ci := index(mx >> 2, my >> 2, mz >> 2)
	var c := cells[ci]
	var si := sub_index(mx & 3, my & 3, mz & 3)
	var d: PackedByteArray
	if c == DETAIL:
		d = details[ci]
		if d[si] == id:
			return
		d = d.duplicate()
	else:
		if c == id:
			return
		d = PackedByteArray()
		d.resize(SUB_VOLUME)
		d.fill(c)
		cells[ci] = DETAIL
	d[si] = id
	details[ci] = d


## Fill a box of quarter-cells [from, to) (chunk-local, clamped by caller).
func fill_micro_box(from: Vector3i, to: Vector3i, id: int) -> void:
	var touched := {}
	for my in range(from.y, to.y):
		for mz in range(from.z, to.z):
			for mx in range(from.x, to.x):
				set_micro(mx, my, mz, id)
				touched[index(mx >> 2, my >> 2, mz >> 2)] = true
	for ci in touched:
		compact_cell(ci)
	recount()


## Collapse a uniform detailed cell back into a plain cell value.
func compact_cell(ci: int) -> void:
	if cells[ci] != DETAIL:
		return
	var d: PackedByteArray = details[ci]
	var first := d[0]
	for i in range(1, SUB_VOLUME):
		if d[i] != first:
			return
	details.erase(ci)
	cells[ci] = first


func recount() -> void:
	solid_count = VOLUME - cells.count(0)


func is_empty() -> bool:
	return solid_count == 0


## Compact binary form for saves: cells + detail table.
func serialize() -> PackedByteArray:
	var keys := PackedInt32Array(details.keys())
	var blob := PackedByteArray()
	for k in keys:
		blob.append_array(details[k])
	return var_to_bytes([cells, keys, blob]).compress(FileAccess.COMPRESSION_ZSTD)


func deserialize(data: PackedByteArray, raw_size: int) -> bool:
	var parts = bytes_to_var(data.decompress(raw_size, FileAccess.COMPRESSION_ZSTD))
	if typeof(parts) != TYPE_ARRAY or parts.size() != 3:
		return false
	cells = parts[0]
	details.clear()
	var keys: PackedInt32Array = parts[1]
	var blob: PackedByteArray = parts[2]
	for i in keys.size():
		details[keys[i]] = blob.slice(i * SUB_VOLUME, (i + 1) * SUB_VOLUME)
	recount()
	return cells.size() == VOLUME
