class_name TerrainGenerator
extends RefCounted
## Seeded, thread-safe terrain generator.
##
## Surfaces are shaped at quarter-block precision: the top cell of each column is
## a detailed cell filled to the exact quarter height, so hills rise in gentle
## 0.25-block terraces instead of whole-block stairs.

const WATER_LEVEL := 30
const WORLD_CHUNKS_Y := 8           # 128 blocks tall
const SNOW_LINE := 62

const GRASS := 1
const DIRT := 2
const STONE := 3
const SAND := 5
const LOG := 6
const LEAVES := 8
const WATER := 10
const SNOW := 12
const GRAVEL := 13
const CRYSTAL := 14
const MOSSY := 15
const COBBLE := 4

var seed_value := 1337
## When set, the ground itself is smooth Voxel Tools terrain: this generator only
## places decorations (trees, boulders, crystals) on top of it, as editable pieces.
var smooth_shape: TerrainShape = null
var _continent := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()


func _init(s := 1337) -> void:
	seed_value = s
	_continent.seed = s
	_continent.frequency = 0.0035
	_continent.fractal_octaves = 3
	_hills.seed = s + 1
	_hills.frequency = 0.012
	_hills.fractal_octaves = 4
	_detail.seed = s + 2
	_detail.frequency = 0.06
	_ridge.seed = s + 3
	_ridge.frequency = 0.006
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 3


## Surface height in blocks (float) at world column (x, z).
func height_at(x: float, z: float) -> float:
	if smooth_shape:
		return smooth_shape.height_at(x, z)
	var c := _continent.get_noise_2d(x, z)          # -1..1
	var h := _hills.get_noise_2d(x, z)
	var r := _ridge.get_noise_2d(x, z)
	var base := 34.0 + c * 14.0
	var hills := h * (6.0 + maxf(c, 0.0) * 10.0)
	var mountains := maxf(r - 0.25, 0.0) * 42.0 * clampf(c + 0.6, 0.0, 1.0)
	return clampf(base + hills + mountains + _detail.get_noise_2d(x, z) * 0.6, 4.0, 90.0)


static func hash3(x: int, y: int, z: int, s: int) -> int:
	var h := (x * 374761393 + y * 668265263 + z * 2147483647 + s * 1442695041) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return h ^ (h >> 16)


static func rand01(x: int, y: int, z: int, s: int) -> float:
	return float(hash3(x, y, z, s) & 0xFFFF) / 65535.0


## Generate one chunk. Returns a Chunk with cells and details filled.
func generate(coord: Vector3i) -> Chunk:
	var chunk := Chunk.new(coord)
	var ox := coord.x * 16
	var oy := coord.y * 16
	var oz := coord.z * 16
	if coord.y < 0 or coord.y >= WORLD_CHUNKS_Y:
		return chunk
	var cells := chunk.cells
	var heights := PackedFloat32Array()
	heights.resize(20 * 20)
	for z in range(-2, 18):
		for x in range(-2, 18):
			heights[(x + 2) + (z + 2) * 20] = height_at(ox + x, oz + z)
	var partial := {}  # cell index -> [fill_quarters, material]
	if smooth_shape:
		_decorate(chunk, heights)
		chunk.recount()
		return chunk
	for z in 16:
		for x in 16:
			var hf := heights[(x + 2) + (z + 2) * 20]
			var hq := int(floor(hf * 4.0))     # height in quarter blocks
			var top := hq >> 2                   # first cell that is not full
			var fill := hq & 3
			# Steepness picks rock on cliffs.
			var dx := absf(heights[(x + 3) + (z + 2) * 20] - heights[(x + 1) + (z + 2) * 20])
			var dz := absf(heights[(x + 2) + (z + 3) * 20] - heights[(x + 2) + (z + 1) * 20])
			var steep := maxf(dx, dz) > 2.6
			var surface := GRASS
			var under := DIRT
			if top <= WATER_LEVEL + 1:
				surface = SAND
				under = SAND
				if top < WATER_LEVEL - 2:
					surface = GRAVEL if rand01(ox + x, 0, oz + z, seed_value) < 0.35 else SAND
			elif top >= SNOW_LINE + int(rand01(ox + x, 1, oz + z, seed_value) * 4.0):
				surface = SNOW
				under = STONE
			elif steep:
				surface = STONE if rand01(ox + x, 2, oz + z, seed_value) < 0.7 else MOSSY
				under = STONE
			for ly in 16:
				var wy := oy + ly
				var id := 0
				if wy < top:
					if wy == top - 1:
						# Directly below a partial cell the block shows its side: use soil.
						id = surface if fill == 0 else (DIRT if surface == GRASS else under)
					elif wy >= top - 4:
						id = under
					else:
						id = STONE
				elif wy == top and fill > 0:
					partial[Chunk.index(x, ly, z)] = [fill, surface]
				elif wy <= WATER_LEVEL:
					id = WATER
				cells[Chunk.index(x, ly, z)] = id
			# Water above a partial sand cell fills its remaining quarters.
	for ci in partial:
		var info: Array = partial[ci]
		var d := PackedByteArray()
		d.resize(64)
		var y: int = ci >> 8
		var wy: int = oy + y
		var above := WATER if wy <= WATER_LEVEL else 0
		for sy in 4:
			var v: int = info[1] if sy < info[0] else above
			for i in 16:
				d[(sy << 4) + i] = v
		cells[ci] = Chunk.DETAIL
		chunk.details[ci] = d
	chunk.cells = cells
	_decorate(chunk, heights)
	chunk.recount()
	return chunk


func _decorate(chunk: Chunk, heights: PackedFloat32Array) -> void:
	var ox := chunk.coord.x * 16
	var oy := chunk.coord.y * 16
	var oz := chunk.coord.z * 16
	# Tree canopies can overhang from neighbouring columns: scan a 4-block margin.
	for z in range(-4, 20):
		for x in range(-4, 20):
			var wx := ox + x
			var wz := oz + z
			var r := rand01(wx, 7, wz, seed_value)
			if r >= 0.0175:
				continue
			var inner := x >= -2 and x < 18 and z >= -2 and z < 18
			var hf := heights[(x + 2) + (z + 2) * 20] if inner else height_at(wx, wz)
			var top := int(floor(hf))
			if top <= WATER_LEVEL + 1 or top >= SNOW_LINE - 2:
				continue
			if r < 0.008:
				_tree(chunk, x, top - oy, z, wx, wz)
			elif r < 0.016 and x >= 1 and x < 15 and z >= 1 and z < 15:
				_boulder(chunk, x, int(floor(hf * 4.0)) - oy * 4, z, wx, wz)
			elif r < 0.0175 and x >= 1 and x < 15 and z >= 1 and z < 15:
				_crystal(chunk, x, int(floor(hf * 4.0)) - oy * 4, z, wx, wz)


func _set_block_if_air(chunk: Chunk, x: int, y: int, z: int, id: int, replace_leaves := false) -> void:
	if x < 0 or x > 15 or y < 0 or y > 15 or z < 0 or z > 15:
		return
	var ci := Chunk.index(x, y, z)
	var c := chunk.cells[ci]
	if c == 0 or (replace_leaves and c == LEAVES) or c == Chunk.DETAIL:
		if c == Chunk.DETAIL:
			chunk.details.erase(ci)
		chunk.cells[ci] = id


func _tree(chunk: Chunk, x: int, base_y: int, z: int, wx: int, wz: int) -> void:
	# Three silhouettes from the tree concept sheet: round broadleaf, tall conifer, bush.
	var kind := rand01(wx, 13, wz, seed_value)
	var jitter := func(k: int) -> float: return rand01(wx, 20 + k, wz, seed_value) - 0.5
	var c := Vector3(x + 0.5, base_y, z + 0.5)
	if kind < 0.18:
		_blob(chunk, c + Vector3(0, 0.6, 0), 1.6 + jitter.call(0) * 0.4, LEAVES)
		return
	if kind < 0.45:
		var h := 7 + int(rand01(wx, 9, wz, seed_value) * 4.0)
		for i in h - 3:   # trunk stays inside the top tiers
			_set_block_if_air(chunk, x, base_y + i, z, LOG, true)
		# Stacked shrinking tiers make the cone.
		var tiers := 4
		for t in tiers:
			var ty := base_y + 3.0 + t * (h - 2.5) / tiers
			_blob(chunk, Vector3(c.x, ty, c.z), 2.6 - t * 0.55, LEAVES, 0.75)
		return
	var height := 4 + int(rand01(wx, 9, wz, seed_value) * 3.0)
	for i in height:
		_set_block_if_air(chunk, x, base_y + i, z, LOG, true)
	var top := Vector3(c.x, base_y + height, c.z)
	_blob(chunk, top + Vector3(0, -0.4, 0), 2.7 + jitter.call(1) * 0.6, LEAVES)
	for k in 3:
		var a: float = TAU * (k / 3.0 + jitter.call(2 + k) * 0.2)
		var off := Vector3(cos(a) * 1.9, -0.9 + float(jitter.call(5 + k)) * 1.2, sin(a) * 1.9)
		_blob(chunk, top + off, 1.7 + jitter.call(8 + k) * 0.5, LEAVES)


## Fill an (optionally squashed) sphere with `id` into air. Interior cells are written as
## whole blocks; cells on the surface are sculpted at quarter-block resolution, which
## gives rounded, clumpy canopies without paying for detail inside.
func _blob(chunk: Chunk, centre: Vector3, radius: float, id: int, y_scale := 1.0) -> void:
	var r2 := radius * radius
	var lo := (centre - Vector3(radius, radius * y_scale, radius)).floor()
	var hi := (centre + Vector3(radius, radius * y_scale, radius)).ceil()
	for by in range(maxi(int(lo.y), 0), mini(int(hi.y), 16)):
		for bz in range(maxi(int(lo.z), 0), mini(int(hi.z), 16)):
			for bx in range(maxi(int(lo.x), 0), mini(int(hi.x), 16)):
				var inside := 0
				for corner in 8:
					var p := Vector3(bx + (corner & 1), by + ((corner >> 1) & 1), bz + ((corner >> 2) & 1)) - centre
					p.y /= y_scale
					if p.length_squared() <= r2:
						inside += 1
				if inside == 0:
					continue
				var ci := Chunk.index(bx, by, bz)
				var cur := chunk.cells[ci]
				if inside == 8:
					if cur == 0:
						chunk.cells[ci] = id
					continue
				if cur != 0 and cur != Chunk.DETAIL:
					continue
				for sy in 4:
					for sz in 4:
						for sx in 4:
							var p := Vector3(bx + (sx + 0.5) * 0.25, by + (sy + 0.5) * 0.25, bz + (sz + 0.5) * 0.25) - centre
							p.y /= y_scale
							if p.length_squared() <= r2:
								var mx := bx * 4 + sx
								var my := by * 4 + sy
								var mz := bz * 4 + sz
								if chunk.get_micro(mx, my, mz) == 0:
									chunk.set_micro(mx, my, mz, id)
				chunk.compact_cell(ci)


## A mossy boulder made of quarter cells, sitting on the exact surface height.
func _boulder(chunk: Chunk, x: int, surface_q: int, z: int, wx: int, wz: int) -> void:
	var r := 3 + int(rand01(wx, 11, wz, seed_value) * 3.0)   # radius in quarters
	var cx := x * 4 + 2
	var cz := z * 4 + 2
	for my in range(surface_q - 1, surface_q + r + 1):
		if my < 0 or my >= 64:
			continue
		for mz in range(cz - r, cz + r + 1):
			for mx in range(cx - r, cx + r + 1):
				if mx < 0 or mx >= 64 or mz < 0 or mz >= 64:
					continue
				var d := Vector3(mx - cx, (my - surface_q) * 1.3, mz - cz).length()
				if d <= r + rand01(mx, my, mz, seed_value) * 0.8 - 0.4:
					var top := my >= surface_q + r - 2
					chunk.set_micro(mx, my, mz, MOSSY if top else COBBLE)
	_compact_area(chunk, cx - r, surface_q - 1, cz - r, cx + r, surface_q + r, cz + r)


## Glow crystal spike cluster made of quarter cells.
func _crystal(chunk: Chunk, x: int, surface_q: int, z: int, wx: int, wz: int) -> void:
	var cx := x * 4 + 1
	var cz := z * 4 + 1
	var spikes := [[0, 0, 7], [2, 1, 4], [-1, 2, 3], [1, -2, 5]]
	for s in spikes:
		var sx: int = cx + s[0]
		var sz: int = cz + s[1]
		for h in s[2]:
			var my: int = surface_q + h
			if my < 0 or my >= 64 or sx < 0 or sx >= 63 or sz < 0 or sz >= 63:
				continue
			chunk.set_micro(sx, my, sz, CRYSTAL)
			if h < s[2] - 2:
				chunk.set_micro(sx + 1, my, sz, CRYSTAL)
				chunk.set_micro(sx, my, sz + 1, CRYSTAL)
				chunk.set_micro(sx + 1, my, sz + 1, CRYSTAL)
	_compact_area(chunk, cx - 2, surface_q, cz - 3, cx + 4, surface_q + 8, cz + 4)


func _compact_area(chunk: Chunk, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int) -> void:
	for cy in range(maxi(y0 >> 2, 0), mini((y1 >> 2) + 1, 16)):
		for cz in range(maxi(z0 >> 2, 0), mini((z1 >> 2) + 1, 16)):
			for cx in range(maxi(x0 >> 2, 0), mini((x1 >> 2) + 1, 16)):
				chunk.compact_cell(Chunk.index(cx, cy, cz))
