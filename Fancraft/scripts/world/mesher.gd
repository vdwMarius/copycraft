class_name Mesher
extends RefCounted
## Thread-safe chunk mesher.
##
## Input: 27 chunk snapshots ([cells, details] or null) around the target chunk.
## Output: Dictionary with three render passes (opaque, cutout, translucent),
## each {verts, norms, uvs, cols, idx}, plus `collision` triangle soup.
##
## Full blocks are meshed per face with vertex AO. Detailed cells are meshed at
## quarter-cell resolution with a small greedy merge inside each 4×4 slice.

const P := 18
const P2 := 324
const PV := 5832
const DETAIL := -1

const PASS_OPAQUE := 0
const PASS_CUTOUT := 1
const PASS_TRANSLUCENT := 2

# Face tables, order +X -X +Y -Y +Z -Z.
const NORMALS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const US := [Vector3i(0, 0, 1), Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 0, 0)]
const VS := [Vector3i(0, 1, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(0, 1, 0)]
const POSITIVE := [true, false, true, false, true, false]
const AO_CURVE := [0.34, 0.58, 0.8, 1.0]

# Lookup tables (copied in from Blocks so workers never touch the scene tree).
var face_layers: PackedInt32Array
var render_mode: PackedByteArray
var solid: PackedByteArray
var emission: PackedFloat32Array

# Working state.
var pad := PackedInt32Array()
var pdet := {}
var _cover_cache := {}
var _offs := PackedInt32Array([1, -1, P2, -P2, P, -P])
var _flip := []
var _mask := PackedInt32Array()
var out := []
var collision := PackedVector3Array()


func _init(tables: Dictionary) -> void:
	face_layers = tables.face_layers
	render_mode = tables.render_mode
	solid = tables.solid
	emission = tables.emission
	_mask.resize(384)
	for f in 6:
		var c := Vector3(US[f]).cross(Vector3(VS[f]))
		_flip.append(c.dot(Vector3(NORMALS[f])) > 0.0)


static func tables_from(blocks: Node) -> Dictionary:
	return {
		"face_layers": blocks.face_layers, "render_mode": blocks.render_mode,
		"solid": blocks.solid, "emission": blocks.emission,
	}


func build(neigh: Array) -> Dictionary:
	_fill_pad(neigh)
	out = [Buf.new(), Buf.new(), Buf.new()]
	collision = PackedVector3Array()
	_cover_cache.clear()
	for y in 16:
		for z in 16:
			var base := 1 + (z + 1) * P + (y + 1) * P2
			for x in 16:
				var p := base + x
				var c := pad[p]
				if c == 0:
					continue
				if c == DETAIL:
					_mesh_detail(x, y, z, p)
				else:
					_mesh_block(x, y, z, p, c)
	return {"passes": [out[0].to_dict(), out[1].to_dict(), out[2].to_dict()], "collision": collision}


# ---------------------------------------------------------------- padding

func _fill_pad(neigh: Array) -> void:
	pad.resize(PV)
	pdet = {}
	for ny in 3:
		for nz in 3:
			for nx in 3:
				var src = neigh[nx + nz * 3 + ny * 9]
				# Ranges in padded space covered by this neighbour.
				var x0 := 0 if nx == 0 else (1 if nx == 1 else 17)
				var x1 := 1 if nx == 0 else (17 if nx == 1 else 18)
				var y0 := 0 if ny == 0 else (1 if ny == 1 else 17)
				var y1 := 1 if ny == 0 else (17 if ny == 1 else 18)
				var z0 := 0 if nz == 0 else (1 if nz == 1 else 17)
				var z1 := 1 if nz == 0 else (17 if nz == 1 else 18)
				if src == null:
					# Below the world is treated as solid stone, everything else as air.
					var v := 3 if ny == 0 else 0
					for py in range(y0, y1):
						for pz in range(z0, z1):
							for px in range(x0, x1):
								pad[px + pz * P + py * P2] = v
					continue
				# Read-only: the main thread never mutates arrays after snapshotting (see VoxelWorld.edit_box).
				var cells: PackedInt32Array = src[0]
				var dets: Dictionary = src[1]
				for py in range(y0, y1):
					var ly := (py - 1) & 15
					for pz in range(z0, z1):
						var lz := (pz - 1) & 15
						var row := (lz << 4) + (ly << 8)
						var prow := pz * P + py * P2
						for px in range(x0, x1):
							var li := ((px - 1) & 15) + row
							var v := cells[li]
							pad[px + prow] = v
							if v == DETAIL:
								pdet[px + prow] = dets[li]


# ---------------------------------------------------------------- helpers

func _visible(me: int, other: int) -> bool:
	if other == 0:
		return true
	if render_mode[other] == 0:  # opaque neighbour hides us
		return false
	return other != me


## Is the face of padded cell `p` facing direction `f` completely covered by opaque quarter-cells?
func _covered(p: int, f: int) -> bool:
	var key := p * 8 + f
	if _cover_cache.has(key):
		return _cover_cache[key]
	var d: PackedByteArray = pdet[p]
	var result := true
	for a in 4:
		for b in 4:
			var lx: int
			var ly: int
			var lz: int
			match f:
				0: lx = 3; ly = a; lz = b
				1: lx = 0; ly = a; lz = b
				2: lx = a; ly = 3; lz = b
				3: lx = a; ly = 0; lz = b
				4: lx = a; ly = b; lz = 3
				_: lx = a; ly = b; lz = 0
			var m := d[lx + (lz << 2) + (ly << 4)]
			if m == 0 or render_mode[m] != 0:
				result = false
				break
		if not result:
			break
	_cover_cache[key] = result
	return result


func _occ_block(p: int) -> int:
	var c := pad[p]
	if c == 0:
		return 0
	if c == DETAIL:
		return 1
	return 1 if render_mode[c] == 0 else 0


## Material at padded-chunk quarter-cell coords (chunk-local micro coords -4..67).
func _micro(mx: int, my: int, mz: int) -> int:
	var p := ((mx >> 2) + 1) + ((mz >> 2) + 1) * P + ((my >> 2) + 1) * P2
	var c := pad[p]
	if c != DETAIL:
		return c
	return pdet[p][(mx & 3) + ((mz & 3) << 2) + ((my & 3) << 4)]


func _occ_micro(mx: int, my: int, mz: int) -> int:
	var m := _micro(mx, my, mz)
	return 1 if m != 0 and render_mode[m] == 0 else 0


static func _ao(s1: int, s2: int, corner: int) -> int:
	if s1 and s2:
		return 0
	return 3 - (s1 + s2 + corner)


# ---------------------------------------------------------------- full blocks

func _mesh_block(x: int, y: int, z: int, p: int, c: int) -> void:
	var mode := render_mode[c]
	var is_solid := solid[c] == 1
	for f in 6:
		var np := p + _offs[f]
		var n := pad[np]
		if n > 0 and (render_mode[n] == 0 or n == c):
			continue
		if n == DETAIL:
			if _covered(np, f ^ 1):
				continue
		elif not _visible(c, n):
			continue
		var ao := PackedInt32Array([3, 3, 3, 3])
		if mode != 2:
			var du: int = _pofs(US[f])
			var dv: int = _pofs(VS[f])
			var a0 := _occ_block(np - du)
			var a1 := _occ_block(np + du)
			var b0 := _occ_block(np - dv)
			var b1 := _occ_block(np + dv)
			ao[0] = _ao(a0, b0, _occ_block(np - du - dv))
			ao[1] = _ao(a1, b0, _occ_block(np + du - dv))
			ao[2] = _ao(a1, b1, _occ_block(np + du + dv))
			ao[3] = _ao(a0, b1, _occ_block(np - du + dv))
		var o := Vector3(x, y, z)
		if POSITIVE[f]:
			o += Vector3(NORMALS[f])
		_quad(mode, o, f, 1.0, 1.0, face_layers[c * 6 + f], emission[c], ao, is_solid)


static func _pofs(v: Vector3i) -> int:
	return v.x + v.z * P + v.y * P2


# ---------------------------------------------------------------- detailed cells

func _mesh_detail(x: int, y: int, z: int, p: int) -> void:
	var d: PackedByteArray = pdet[p]
	var bx := x * 4
	var by := y * 4
	var bz := z * 4
	# Neighbour cells: plain value, or their detail array.
	var nv := PackedInt32Array()
	nv.resize(6)
	var nd := []
	nd.resize(6)
	for f in 6:
		var q := p + _offs[f]
		nv[f] = pad[q]
		if nv[f] == DETAIL:
			nd[f] = pdet[q]
	# Visible-face masks: index f*64 + s*16 + a + b*4.
	var mask := _mask
	mask.fill(0)
	var used := 0
	for ly in 4:
		for lz in 4:
			for lx in 4:
				var si := lx + (lz << 2) + (ly << 4)
				var m := d[si]
				if m == 0:
					continue
				var nm: int
				# +X (s=lx, a=lz, b=ly)
				if lx < 3: nm = d[si + 1]
				elif nv[0] != DETAIL: nm = nv[0]
				else: nm = nd[0][si - 3]
				if nm == 0 or (nm != m and render_mode[nm] != 0):
					mask[lx * 16 + lz + ly * 4] = m
					used |= 1 << lx
				# -X
				if lx > 0: nm = d[si - 1]
				elif nv[1] != DETAIL: nm = nv[1]
				else: nm = nd[1][si + 3]
				if nm == 0 or (nm != m and render_mode[nm] != 0):
					mask[64 + lx * 16 + lz + ly * 4] = m
					used |= 1 << (4 + lx)
				# +Y (s=ly, a=lx, b=lz)
				if ly < 3: nm = d[si + 16]
				elif nv[2] != DETAIL: nm = nv[2]
				else: nm = nd[2][si - 48]
				if nm == 0 or (nm != m and render_mode[nm] != 0):
					mask[128 + ly * 16 + lx + lz * 4] = m
					used |= 1 << (8 + ly)
				# -Y
				if ly > 0: nm = d[si - 16]
				elif nv[3] != DETAIL: nm = nv[3]
				else: nm = nd[3][si + 48]
				if nm == 0 or (nm != m and render_mode[nm] != 0):
					mask[192 + ly * 16 + lx + lz * 4] = m
					used |= 1 << (12 + ly)
				# +Z (s=lz, a=lx, b=ly)
				if lz < 3: nm = d[si + 4]
				elif nv[4] != DETAIL: nm = nv[4]
				else: nm = nd[4][si - 12]
				if nm == 0 or (nm != m and render_mode[nm] != 0):
					mask[256 + lz * 16 + lx + ly * 4] = m
					used |= 1 << (16 + lz)
				# -Z
				if lz > 0: nm = d[si - 4]
				elif nv[5] != DETAIL: nm = nv[5]
				else: nm = nd[5][si + 12]
				if nm == 0 or (nm != m and render_mode[nm] != 0):
					mask[320 + lz * 16 + lx + ly * 4] = m
					used |= 1 << (20 + lz)
	if used == 0:
		return
	var cell := Vector3i(bx, by, bz)
	for f in 6:
		var nrm: Vector3i = NORMALS[f]
		var u: Vector3i = US[f]
		var v: Vector3i = VS[f]
		for s in 4:
			if (used & (1 << (f * 4 + s))) == 0:
				continue
			var base := f * 64 + s * 16
			# Greedy merge inside the 4×4 slice.
			for b in 4:
				var a := 0
				while a < 4:
					var m := mask[base + a + b * 4]
					if m == 0:
						a += 1
						continue
					var w := 1
					while a + w < 4 and mask[base + a + w + b * 4] == m:
						w += 1
					var h := 1
					var grow := true
					while b + h < 4 and grow:
						for k in w:
							if mask[base + a + k + (b + h) * 4] != m:
								grow = false
								break
						if grow:
							h += 1
					for hb in h:
						for k in w:
							mask[base + a + k + (b + hb) * 4] = 0
					var l := _local(f, s, a, b)
					var mo := cell + l
					if POSITIVE[f]:
						mo += nrm
					var mode := render_mode[m]
					var ao := PackedInt32Array([3, 3, 3, 3])
					if mode != 2:
						var front := cell + l + nrm
						var lo_a := front - u
						var hi_a := front + u * w
						var lo_b := front - v
						var hi_b := front + v * h
						ao[0] = _ao(_om(lo_a), _om(lo_b), _om(lo_a - v))
						ao[1] = _ao(_om(hi_a), _om(lo_b + u * (w - 1)), _om(hi_a - v))
						ao[2] = _ao(_om(hi_a + v * (h - 1)), _om(hi_b + u * (w - 1)), _om(hi_a + v * h))
						ao[3] = _ao(_om(lo_a + v * (h - 1)), _om(hi_b), _om(lo_a + v * h))
					_quad(mode, Vector3(mo) * 0.25, f, w * 0.25, h * 0.25, face_layers[m * 6 + f], emission[m], ao, solid[m] == 1)
					a += w


func _om(q: Vector3i) -> int:
	return _occ_micro(q.x, q.y, q.z)


## Quarter-cell coordinates inside a cell for face f, slice s (along normal), (a,b) along (U,V).
static func _local(f: int, s: int, a: int, b: int) -> Vector3i:
	match f:
		0, 1: return Vector3i(s, b, a)
		2, 3: return Vector3i(a, s, b)
		_: return Vector3i(a, b, s)


# ---------------------------------------------------------------- output

## Per-pass vertex buffers. Appends happen through the object's own methods so the
## packed arrays are modified in place (no copy-on-write churn).
class Buf:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	func add(c0: Vector3, c1: Vector3, c2: Vector3, c3: Vector3, n: Vector3, uv: Vector2, ao: PackedInt32Array, tri: PackedInt32Array) -> void:
		var base := verts.size()
		verts.append(c0)
		verts.append(c1)
		verts.append(c2)
		verts.append(c3)
		for i in 4:
			norms.append(n)
			uvs.append(uv)
			var a: float = AO_CURVE[ao[i]]
			cols.append(Color(a, a, a, 1.0))
		for t in tri:
			idx.append(base + t)

	func to_dict() -> Dictionary:
		return {"verts": verts, "norms": norms, "uvs": uvs, "cols": cols, "idx": idx}


var TRI_A := [PackedInt32Array([0, 2, 1, 0, 3, 2]), PackedInt32Array([1, 3, 2, 1, 0, 3])]
var TRI_B := [PackedInt32Array([0, 1, 2, 0, 2, 3]), PackedInt32Array([1, 2, 3, 1, 3, 0])]


func _quad(mode: int, o: Vector3, f: int, su: float, sv: float, layer: int, emis: float, ao: PackedInt32Array, is_solid: bool) -> void:
	var u := Vector3(US[f]) * su
	var v := Vector3(VS[f]) * sv
	var c0 := o
	var c1 := o + u
	var c2 := o + u + v
	var c3 := o + v
	# Flip the split diagonal so AO interpolates without creases.
	var alt := 1 if ao[0] + ao[2] < ao[1] + ao[3] else 0
	var tri: PackedInt32Array = TRI_A[alt] if _flip[f] else TRI_B[alt]
	out[mode].add(c0, c1, c2, c3, Vector3(NORMALS[f]), Vector2(layer, emis), ao, tri)
	if is_solid:
		var corners := [c0, c1, c2, c3]
		for t in tri:
			collision.append(corners[t])
