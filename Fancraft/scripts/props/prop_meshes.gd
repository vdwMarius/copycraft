class_name PropMeshes
extends RefCounted
## Procedural stylised props (trees, bushes, rocks, grass, flowers), generated in code
## so the APK carries no mesh or texture assets.
##
## Look: chunky, cel-shaded, painterly (docs/art-reference 03/04). Foliage gets its
## colour from vertex colours (sRGB authored) plus the shared cel light; vertex colour
## alpha carries the wind-sway weight. Bark and rock sample the shared texture arrays
## (layer index in UV2.x) so texture packs restyle them too.
##
## Detail levels: 0 = near (full), 1 = medium, 2 = far (a few dozen triangles).

const LAYER_NAMES := [
	"grass_top", "grass_side", "dirt", "stone", "cobblestone", "sand", "log_top",
	"log_side", "planks", "leaves", "glass", "water", "bricks", "snow", "gravel",
	"crystal", "mossy_stone", "marble", "terracotta", "slate",
]

const PAINT_LIGHT := Vector3(-0.45, 0.8, 0.4)   # painted top-left light for vertex colours

static var _materials := {}
static var _ico := {}
static var _noise: FastNoiseLite


# --------------------------------------------------------------------------- utilities

static func texture_library() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Textures")
	return null


static func layer(texture_name: String) -> int:
	var lib := texture_library()
	if lib and lib.has_method("layer_of"):
		var l: int = lib.layer_of(texture_name)
		if l >= 0:
			return l
	return LAYER_NAMES.find(texture_name)


static func _nz() -> FastNoiseLite:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_noise.frequency = 1.0
	return _noise


static func _noise3(p: Vector3, seed_offset: float) -> float:
	return _nz().get_noise_3d(p.x + seed_offset * 17.13, p.y - seed_offset * 5.71, p.z + seed_offset * 3.37)


static func _rand(seed_value: int, k: int) -> float:
	var h := (seed_value * 374761393 + k * 668265263) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	return float(h & 0xFFFF) / 65535.0


## Icosphere (unit radius): [PackedVector3Array verts, Array of Vector3i faces].
static func _ico_sphere(subdiv: int) -> Array:
	if _ico.has(subdiv):
		return _ico[subdiv]
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)])
	for i in verts.size():
		verts[i] = verts[i].normalized()
	var faces := [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10), Vector3i(0, 10, 11),
		Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8),
		Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
		Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1)]
	for s in subdiv:
		var mid := {}
		var nf := []
		for f: Vector3i in faces:
			var m := []
			for e in [[f.x, f.y], [f.y, f.z], [f.z, f.x]]:
				var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
				if not mid.has(key):
					verts.append(((verts[e[0]] + verts[e[1]]) * 0.5).normalized())
					mid[key] = verts.size() - 1
				m.append(mid[key])
			nf.append(Vector3i(f.x, m[0], m[2]))
			nf.append(Vector3i(f.y, m[1], m[0]))
			nf.append(Vector3i(f.z, m[2], m[1]))
			nf.append(Vector3i(m[0], m[1], m[2]))
		faces = nf
	_ico[subdiv] = [verts, faces]
	return _ico[subdiv]


## Emit a triangle so it faces `outward` (Godot front faces are clockwise).
static func _tri(st: SurfaceTool, p: Array, n: Array, c: Array, uv: Array, outward: Vector3, uv2 := Vector2.ZERO) -> void:
	var order := [0, 1, 2]
	var cr: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
	if cr.dot(outward) > 0.0:
		order = [0, 2, 1]
	for i in order:
		st.set_color(c[i])
		st.set_normal(n[i])
		st.set_uv(uv[i])
		st.set_uv2(uv2)
		st.add_vertex(p[i])


static func _commit(surfaces: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for st: SurfaceTool in surfaces:
		st.commit(mesh)
	return mesh


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


# --------------------------------------------------------------------------- shapes

## A lumpy foliage clump. Normals blend the clump's own sphere with the whole
## canopy's sphere, so the cel shading reads as one big painted shape.
static func _clump(st: SurfaceTool, center: Vector3, radius: float, squash: float, subdiv: int,
		seed_value: float, canopy_center: Vector3, canopy_radius: float, dark: Color, light: Color, sway_base: float) -> void:
	var ico := _ico_sphere(subdiv)
	var verts: PackedVector3Array = ico[0]
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	pos.resize(verts.size())
	nrm.resize(verts.size())
	col.resize(verts.size())
	for i in verts.size():
		var v := verts[i]
		var bump := 1.0 + _noise3(v * 1.6, seed_value) * 0.28
		var d := v * radius * bump
		d.y *= squash
		var p := center + d
		pos[i] = p
		var n_canopy := (p - canopy_center).normalized()
		var n := (v * 0.45 + n_canopy * 0.55).normalized()
		nrm[i] = n
		var up := clampf(n.y * 0.6 + (p.y - canopy_center.y) / maxf(canopy_radius, 0.1) * 0.5 + 0.35, 0.0, 1.0)
		var c := dark.lerp(light, smoothstep(0.0, 1.0, up))
		c.a = clampf((p.y - sway_base) / 4.0, 0.0, 1.0)
		col[i] = c
	for f: Vector3i in ico[1]:
		var ids := [f.x, f.y, f.z]
		var p := [pos[ids[0]], pos[ids[1]], pos[ids[2]]]
		var n := [nrm[ids[0]], nrm[ids[1]], nrm[ids[2]]]
		var c := [col[ids[0]], col[ids[1]], col[ids[2]]]
		var outward: Vector3 = (p[0] + p[1] + p[2]) / 3.0 - center
		_tri(st, p, n, c, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], outward)


## A tube along `points` with per-point radii (trunks, branches). UV wraps around.
static func _tube(st: SurfaceTool, points: Array, radii: Array, sides: int, seed_value: float, bark_layer: int, tint: Color, flare := 0.0) -> void:
	var rings := []
	var count := points.size()
	for i in count:
		var p: Vector3 = points[i]
		var dir: Vector3
		if i == 0:
			dir = (points[1] - p).normalized()
		elif i == count - 1:
			dir = (p - points[i - 1]).normalized()
		else:
			dir = (points[i + 1] - points[i - 1]).normalized()
		var side := Vector3.RIGHT if absf(dir.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
		var a := dir.cross(side).normalized()
		var b := dir.cross(a).normalized()
		var ring := []
		var t := float(i) / float(count - 1)
		for s in sides + 1:
			var ang := TAU * s / sides
			var r: float = radii[i]
			if flare > 0.0:
				r *= 1.0 + flare * pow(1.0 - t, 5.0) * (0.6 + 0.4 * maxf(sin(ang * 3.0 + seed_value), 0.0))
			var off := (a * cos(ang) + b * sin(ang))
			ring.append([p + off * r, off, Vector2(float(s) / sides * 2.0, -t * 3.0)])
		rings.append(ring)
	for i in count - 1:
		var ao0 := 0.7 + 0.3 * float(i) / (count - 1)
		var ao1 := 0.7 + 0.3 * float(i + 1) / (count - 1)
		for s in sides:
			var q0: Array = rings[i][s]
			var q1: Array = rings[i][s + 1]
			var q2: Array = rings[i + 1][s + 1]
			var q3: Array = rings[i + 1][s]
			var c0 := tint * ao0
			var c1 := tint * ao1
			c0.a = 0.95   # saturation (prop shader)
			c1.a = 0.95
			var outward: Vector3 = (q0[1] + q2[1]) * 0.5
			_tri(st, [q0[0], q1[0], q2[0]], [q0[1], q1[1], q2[1]], [c0, c0, c1], [q0[2], q1[2], q2[2]], outward, Vector2(bark_layer, 0))
			_tri(st, [q0[0], q2[0], q3[0]], [q0[1], q2[1], q3[1]], [c0, c1, c1], [q0[2], q2[2], q3[2]], outward, Vector2(bark_layer, 0))


static func _bent_path(base: Vector3, height: float, bend: Vector3, segments: int) -> Array:
	var pts := []
	for i in segments + 1:
		var t := float(i) / segments
		pts.append(base + Vector3(0, height * t, 0) + bend * sin(t * PI * 0.5))
	return pts


# --------------------------------------------------------------------------- trees

static func tree_broadleaf(variant: int, detail: int) -> ArrayMesh:
	var bark := _begin()
	var leaves := _begin()
	var sv := float(variant) * 3.1 + 0.5
	var height := 3.2 + _rand(variant, 1) * 1.6                  # trunk height
	var lean := Vector3(_rand(variant, 2) - 0.5, 0, _rand(variant, 3) - 0.5) * 0.9
	var top := Vector3(0, height, 0) + lean
	var bark_layer := layer("log_side")
	var bark_tint := Color(1.0, 0.92, 0.88)
	var sides: int = [8, 6, 4][detail]
	var segs: int = [5, 3, 1][detail]
	var path := _bent_path(Vector3.ZERO, height + 0.6, lean, segs)
	var radii := []
	for i in path.size():
		radii.append(lerpf(0.34, 0.16, float(i) / (path.size() - 1)))
	_tube(bark, path, radii, sides, sv, bark_layer, bark_tint, 0.9 if detail == 0 else 0.4)
	# Canopy: clumps around a centre above the trunk.
	var crown := 2.4 + _rand(variant, 4) * 0.8
	var canopy_c := top + Vector3(0, crown * 0.75, 0)
	var dark := Color(0.16, 0.33, 0.17).lerp(Color(0.19, 0.36, 0.15), _rand(variant, 5))
	var light := Color(0.42, 0.62, 0.28).lerp(Color(0.5, 0.66, 0.3), _rand(variant, 6))
	var clumps: int = [8, 4, 2][detail]
	var subdiv: int = 1 if detail < 2 else 0
	if detail == 0:
		# A few branches reaching into the lower clumps.
		for k in 3:
			var ang := TAU * (k / 3.0 + _rand(variant, 30 + k) * 0.2)
			var start := path[int(path.size() * 0.6)] as Vector3
			var end := start + Vector3(cos(ang) * 1.3, 0.9 + _rand(variant, 40 + k) * 0.5, sin(ang) * 1.3)
			_tube(bark, [start, (start + end) * 0.5 + Vector3(0, 0.2, 0), end], [0.12, 0.08, 0.05], 5, sv, bark_layer, bark_tint)
	_clump(leaves, canopy_c, crown * (0.95 if detail < 2 else 1.1), 0.82, subdiv, sv, canopy_c, crown, dark, light, 0.0)
	for k in clumps - 1:
		var ang := TAU * (float(k) / maxf(clumps - 1, 1) + _rand(variant, 10 + k) * 0.15)
		var ring := crown * (0.75 + _rand(variant, 20 + k) * 0.25)
		var c := canopy_c + Vector3(cos(ang) * ring, (_rand(variant, 50 + k) - 0.45) * crown * 0.9, sin(ang) * ring)
		_clump(leaves, c, crown * (0.5 + _rand(variant, 60 + k) * 0.25), 0.8, subdiv, sv + k, canopy_c, crown * 1.4, dark, light, 0.0)
	return _commit([bark, leaves])


static func tree_pine(variant: int, detail: int) -> ArrayMesh:
	var bark := _begin()
	var needles := _begin()
	var sv := float(variant) * 2.3 + 1.7
	var height := 8.0 + _rand(variant, 1) * 3.5
	var bark_layer := layer("log_side")
	var sides: int = [7, 5, 4][detail]
	var path := _bent_path(Vector3.ZERO, height * 0.8, Vector3(_rand(variant, 2) - 0.5, 0, _rand(variant, 3) - 0.5) * 0.3, [4, 2, 1][detail])
	var radii := []
	for i in path.size():
		radii.append(lerpf(0.3, 0.1, float(i) / (path.size() - 1)))
	_tube(bark, path, radii, sides, sv, bark_layer, Color(1.0, 0.9, 0.86), 0.7 if detail == 0 else 0.3)
	var tiers: int = [5, 3, 2][detail]
	var cone_sides: int = [10, 8, 6][detail]
	var dark := Color(0.11, 0.27, 0.19)
	var light := Color(0.26, 0.48, 0.3).lerp(Color(0.32, 0.5, 0.28), _rand(variant, 4))
	var base_y := height * 0.22
	for t in tiers:
		var f := float(t) / tiers
		var y0 := base_y + (height - base_y) * f * 0.82
		var r := lerpf(2.4, 0.9, f) * (0.9 + _rand(variant, 10 + t) * 0.2)
		var h := (height - y0) * (0.55 if t < tiers - 1 else 1.0)
		_cone(needles, Vector3(0, y0, 0), r, h, cone_sides, sv + t, dark, light, detail == 0)
	return _commit([bark, needles])


## One conifer tier: a jagged drooping skirt rising to a point, closed underneath.
static func _cone(st: SurfaceTool, base: Vector3, radius: float, height: float, sides: int, seed_value: float, dark: Color, light: Color, jag: bool) -> void:
	var apex := base + Vector3(0, height, 0)
	var under := base + Vector3(0, height * 0.18, 0)
	var ring := []
	for s in sides:
		var ang := TAU * s / sides + seed_value
		var r := radius * (1.0 if (s % 2 == 0 or not jag) else 0.8) * (0.9 + 0.2 * _rand(int(seed_value * 10.0), s))
		var droop := -0.25 * radius * (0.6 + 0.4 * _rand(int(seed_value * 7.0), s)) if (s % 2 == 0 or not jag) else 0.0
		ring.append(base + Vector3(cos(ang) * r, droop, sin(ang) * r))
	for s in sides:
		var a: Vector3 = ring[s]
		var b: Vector3 = ring[(s + 1) % sides]
		var na := ((a - base).normalized() * 0.7 + Vector3.UP * 0.6).normalized()
		var nb := ((b - base).normalized() * 0.7 + Vector3.UP * 0.6).normalized()
		var ca := dark.lerp(light, 0.45)
		var ct := light
		ca.a = clampf(a.y / 6.0, 0.0, 1.0)
		ct.a = clampf(apex.y / 6.0, 0.0, 1.0)
		var outward := ((a + b) * 0.5 - base).normalized() + Vector3.UP * 0.3
		_tri(st, [a, b, apex], [na, nb, Vector3.UP], [ca, ca, ct], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], outward)
		var cu := dark
		cu.a = ca.a
		_tri(st, [a, b, under], [Vector3.DOWN, Vector3.DOWN, Vector3.DOWN], [cu, cu, cu], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Vector3.DOWN)


# --------------------------------------------------------------------------- bushes & rocks

static func bush(variant: int, detail: int) -> ArrayMesh:
	var st := _begin()
	var sv := float(variant) * 4.7 + 0.3
	var size := 1.0 + _rand(variant, 1) * 0.6
	var center := Vector3(0, size * 0.45, 0)
	var dark := Color(0.15, 0.31, 0.15)
	var light := Color(0.4, 0.6, 0.26).lerp(Color(0.46, 0.64, 0.3), _rand(variant, 2))
	var clumps: int = [4, 2, 1][detail]
	var subdiv: int = 1 if detail < 2 else 0
	_clump(st, center, size * 0.6, 0.75, subdiv, sv, center, size, dark, light, 0.0)
	for k in clumps - 1:
		var ang := TAU * (float(k) / maxf(clumps - 1, 1) + _rand(variant, 10 + k) * 0.2)
		var c := center + Vector3(cos(ang) * size * 0.4, (_rand(variant, 20 + k) - 0.5) * size * 0.3, sin(ang) * size * 0.4)
		_clump(st, c, size * (0.38 + _rand(variant, 30 + k) * 0.12), 0.8, subdiv, sv + k, center, size, dark, light, 0.0)
	if variant % 3 != 2 and detail < 2:
		# Berries / blossoms: small bright clumps on the surface.
		var berry: Color = [Color(0.85, 0.2, 0.25), Color(1.0, 0.85, 0.3), Color(0.95, 0.95, 0.9)][variant % 3]
		for k in [7, 3, 0][detail]:
			var d := Vector3(_rand(variant, 40 + k) - 0.5, _rand(variant, 50 + k) * 0.8, _rand(variant, 60 + k) - 0.5).normalized()
			var p := center + Vector3(d.x * size * 0.62, d.y * size * 0.45, d.z * size * 0.62)
			_clump(st, p, 0.07, 1.0, 0, sv + 9 + k, p, 0.1, berry * 0.8, berry, 0.0)
	return _commit([st])


static func rock(variant: int, detail: int) -> ArrayMesh:
	var st := _begin()
	var sv := float(variant) * 5.9 + 2.1
	var size := 0.9 + _rand(variant, 1) * 1.1
	var stretch := Vector3(1.0 + _rand(variant, 2) * 0.4, 0.8 + _rand(variant, 3) * 0.45, 0.9 + _rand(variant, 4) * 0.35)
	var ico := _ico_sphere(1 if detail == 0 else 0)
	var verts: PackedVector3Array = ico[0]
	var pos := PackedVector3Array()
	pos.resize(verts.size())
	for i in verts.size():
		var v := verts[i]
		var bump := 1.0 + _noise3(v * 1.3, sv) * 0.35
		var p := v * bump * stretch * size * 0.5
		p.y = maxf(p.y, -size * 0.12)          # flat-ish bottom, origin slightly sunk
		pos[i] = p + Vector3(0, size * 0.12, 0) - Vector3(0, size * 0.1, 0)
	var stone_layer := layer("stone")
	var moss := variant % 3 == 1
	var L := PAINT_LIGHT.normalized()
	for f: Vector3i in ico[1]:
		var p := [pos[f.x], pos[f.y], pos[f.z]]
		var n: Vector3 = (p[1] - p[0]).cross(p[2] - p[0]).normalized()
		var centroid: Vector3 = (p[0] + p[1] + p[2]) / 3.0
		if n.dot(centroid - Vector3(0, size * 0.1, 0)) < 0.0:
			n = -n
		# Painted light: three flat tone bands like the reference sheets.
		var k := n.dot(L)
		var tone := 0.62 if k < -0.1 else (0.86 if k < 0.45 else 1.08)
		var c := Color(0.78, 0.77, 0.74) * tone
		c.a = 0.75
		if moss and n.y > 0.55:
			c = Color(0.55, 0.78, 0.3) * (0.9 + 0.15 * n.y)
			c.a = 1.0
		var uv := []
		var a := n.abs()
		for q: Vector3 in p:
			if a.y >= a.x and a.y >= a.z:
				uv.append(Vector2(q.x, q.z) * 0.6)
			elif a.x >= a.z:
				uv.append(Vector2(q.z, -q.y) * 0.6)
			else:
				uv.append(Vector2(q.x, -q.y) * 0.6)
		_tri(st, p, [n, n, n], [c, c, c], uv, n, Vector2(stone_layer, 0))
	return _commit([st])


# --------------------------------------------------------------------------- grass & flowers

static func grass_tuft(variant: int) -> ArrayMesh:
	var st := _begin()
	_blades(st, variant, 12, 0.32, 0.6)
	return _commit([st])


static func flower_tuft(variant: int) -> ArrayMesh:
	var st := _begin()
	_blades(st, variant + 50, 6, 0.25, 0.45)
	var colours := [Color(1.0, 0.55, 0.15), Color(1.0, 0.86, 0.25), Color(0.98, 0.97, 0.92), Color(0.62, 0.45, 0.95)]
	var heads := 3
	for k in heads:
		var ang := TAU * (k / float(heads) + _rand(variant, 70 + k) * 0.3)
		var r := 0.08 + _rand(variant, 80 + k) * 0.1
		var h := 0.32 + _rand(variant, 90 + k) * 0.18
		var base := Vector3(cos(ang) * r * 0.3, 0, sin(ang) * r * 0.3)
		var tip := Vector3(cos(ang) * r, h, sin(ang) * r)
		var stem := Color(0.3, 0.55, 0.2)
		stem.a = 0.0
		var stem_tip := Color(0.4, 0.65, 0.25)
		stem_tip.a = 1.0
		var side := Vector3(-sin(ang), 0, cos(ang)) * 0.012
		_tri(st, [base - side, base + side, tip], [Vector3.UP, Vector3.UP, Vector3.UP], [stem, stem, stem_tip], [Vector2(0, 0), Vector2(0, 0), Vector2(1, 0)], side.cross(Vector3.UP))
		var petal: Color = colours[(variant + k) % colours.size()]
		petal.a = 1.0
		_flower_head(st, tip, 0.085 + _rand(variant, 100 + k) * 0.035, petal)
	return _commit([st])


## Crossed-quad blades rising from the origin. UV.x = sway weight (0 at the root).
static func _blades(st: SurfaceTool, variant: int, count: int, min_h: float, max_h: float) -> void:
	var root := Color(0.17, 0.36, 0.14)
	var tip := Color(0.52, 0.72, 0.3)
	for i in count:
		var ang := TAU * _rand(variant, i)
		var dist := _rand(variant, 100 + i) * 0.18
		var h := lerpf(min_h, max_h, _rand(variant, 200 + i))
		var w := 0.035 + _rand(variant, 300 + i) * 0.03
		var face := ang + PI * 0.5 + (_rand(variant, 400 + i) - 0.5)
		var out := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(cos(face), 0, sin(face)) * w
		var base := out * dist
		var mid := base + out * 0.05 + Vector3(0, h * 0.55, 0)
		var top := base + out * (0.12 + _rand(variant, 500 + i) * 0.1) + Vector3(0, h, 0)
		var cr := root
		var cm := root.lerp(tip, 0.55)
		var ct := tip
		cr.a = 0.0
		cm.a = 0.5
		ct.a = 1.0
		var n := Vector3.UP
		var outward := side.cross(Vector3.UP)
		_tri(st, [base - side, base + side, mid + side * 0.7], [n, n, n], [cr, cr, cm], [Vector2(0, 0), Vector2(0, 0), Vector2(0.3, 0)], outward)
		_tri(st, [base - side, mid + side * 0.7, mid - side * 0.7], [n, n, n], [cr, cm, cm], [Vector2(0, 0), Vector2(0.3, 0), Vector2(0.3, 0)], outward)
		_tri(st, [mid - side * 0.7, mid + side * 0.7, top], [n, n, n], [cm, cm, ct], [Vector2(0.3, 0), Vector2(0.3, 0), Vector2(1, 0)], outward)


static func _flower_head(st: SurfaceTool, center: Vector3, r: float, col: Color) -> void:
	# A tiny star: 5 petal triangles around a darker centre, facing up.
	var heart := Color(0.95, 0.75, 0.2)
	heart.a = 1.0
	for k in 5:
		var a0 := TAU * k / 5.0
		var a1 := a0 + TAU / 10.0
		var p0 := center + Vector3(cos(a0) * r, 0.01, sin(a0) * r)
		var p1 := center + Vector3(cos(a1) * r * 0.45, 0.0, sin(a1) * r * 0.45)
		var pm := center + Vector3(cos(a0 - TAU / 10.0) * r * 0.45, 0.0, sin(a0 - TAU / 10.0) * r * 0.45)
		_tri(st, [center, pm, p0], [Vector3.UP, Vector3.UP, Vector3.UP], [heart, col, col], [Vector2(1, 0), Vector2(1, 0), Vector2(1, 0)], Vector3.UP)
		_tri(st, [center, p0, p1], [Vector3.UP, Vector3.UP, Vector3.UP], [heart, col, col], [Vector2(1, 0), Vector2(1, 0), Vector2(1, 0)], Vector3.UP)


# --------------------------------------------------------------------------- collision

## Trunk collision: {shape, transform} entries in the mesh's local space.
static func tree_collision(kind: String) -> Array:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32 if kind != "pine" else 0.28
	cap.height = 4.0 if kind != "pine" else 6.0
	return [{"shape": cap, "transform": Transform3D(Basis(), Vector3(0, cap.height * 0.5, 0))}]


static func rock_collision(variant: int) -> Array:
	var mesh := rock(variant, 1)
	var pts := PackedVector3Array()
	var arr := mesh.surface_get_arrays(0)
	pts = arr[Mesh.ARRAY_VERTEX]
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	return [{"shape": shape, "transform": Transform3D()}]


# --------------------------------------------------------------------------- materials

static func _shader_material(key: String, path: String) -> ShaderMaterial:
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = load(path)
	_materials[key] = m
	_apply_textures(m)
	return m


static func bark_material() -> ShaderMaterial:
	return _shader_material("bark", "res://shaders/prop.gdshader")


static func rock_material() -> ShaderMaterial:
	return _shader_material("rock", "res://shaders/prop.gdshader")


static func foliage_material() -> ShaderMaterial:
	return _shader_material("foliage", "res://shaders/foliage.gdshader")


static func grass_material() -> ShaderMaterial:
	return _shader_material("grass", "res://shaders/grass.gdshader")


## Re-bind the texture arrays (call after Textures.textures_changed).
static func refresh_textures() -> void:
	for m in _materials.values():
		_apply_textures(m)


static func _apply_textures(m: ShaderMaterial) -> void:
	var lib := texture_library()
	var ok := lib != null and lib.get("albedo_array") != null
	m.set_shader_parameter("use_texture", ok)
	if ok:
		m.set_shader_parameter("albedo_tex", lib.albedo_array)
		m.set_shader_parameter("surface_tex", lib.surface_array)
