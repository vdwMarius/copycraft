class_name PartMeshes
extends RefCounted
## Procedural meshes, collision and materials for building parts (see Parts.CATALOG).
## Wood: plank panels in a darker timber frame with corner posts. Stone: chunky cut
## stone with plinths and caps. Edges are chamfered a little for the stylised pop.
## Every vertex stores its texture-array layer in UV2.x; colours carry tint and AO.

const CHAMFER := 0.04

static var _meshes := {}
static var _materials := {}
static var _ghosts := {}


# --------------------------------------------------------------------------- public API

static func mesh(part_id: String, material_id: String) -> ArrayMesh:
	var key := part_id + "/" + material_id
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var def: Dictionary = Parts.CATALOG[part_id]
	var y0: float = def.base
	var size: Vector3 = def.size
	var wood := material_id == "wood"
	match part_id:
		"foundation":
			_foundation(st, size, y0, wood)
		"floor":
			_floor(st, size, y0, wood)
		"wall", "half_wall":
			_wall(st, size, y0, wood, Rect2())
		"doorway", "window":
			_wall(st, size, y0, wood, def.opening)
		"roof":
			_roof(st, wood)
		"stairs":
			_stairs(st, size, wood)
		"pillar":
			_pillar(st, size, y0, wood)
		"beam":
			_cbox(st, Transform3D(Basis(), Vector3(0, y0 + size.y * 0.5, 0)), size, CHAMFER, _L("planks" if wood else "stone"), _tint(wood, 0.72 if wood else 0.92), 1.0)
	var m := ArrayMesh.new()
	st.commit(m)
	_meshes[key] = m
	return m


static func material(material_id: String) -> ShaderMaterial:
	if _materials.has(material_id):
		return _materials[material_id]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/prop.gdshader")
	_materials[material_id] = m
	_apply_textures(m)
	return m


static func refresh_textures() -> void:
	for m in _materials.values():
		_apply_textures(m)


static func _apply_textures(m: ShaderMaterial) -> void:
	var lib := PropMeshes.texture_library()
	var ok := lib != null and lib.get("albedo_array") != null
	m.set_shader_parameter("use_texture", ok)
	if ok:
		m.set_shader_parameter("albedo_tex", lib.albedo_array)
		m.set_shader_parameter("surface_tex", lib.surface_array)


## Translucent hologram for placement previews (green = ok, red = blocked).
static func ghost_material(ok: bool) -> Material:
	if _ghosts.has(ok):
		return _ghosts[ok]
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode blend_mix, unshaded, cull_back, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.4, 1.0, 0.6, 0.3);
void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float scan = 0.85 + 0.15 * sin(TIME * 4.0 + FRAGCOORD.y * 0.15);
	ALBEDO = tint.rgb * (1.0 + fres * 0.8);
	ALPHA = clamp((tint.a + fres * 0.55) * scan, 0.0, 0.9);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tint", Color(0.4, 1.0, 0.6, 0.28) if ok else Color(1.0, 0.3, 0.25, 0.32))
	m.render_priority = 2
	_ghosts[ok] = m
	return m


## Collision as {shape, transform} entries, matching the catalogue extents exactly.
static func collision(part_id: String) -> Array:
	var def: Dictionary = Parts.CATALOG[part_id]
	var size: Vector3 = def.size
	var y0: float = def.base
	match part_id:
		"doorway", "window":
			var out := []
			for r in _wall_pieces(size, def.opening):
				var rect: Rect2 = r
				out.append(_box_shape(Vector3(rect.position.x + rect.size.x * 0.5, y0 + rect.position.y + rect.size.y * 0.5, 0), Vector3(rect.size.x, rect.size.y, size.z)))
			return out
		"roof":
			var t := 0.15
			var pts := PackedVector3Array()
			for x in [-1.0, 1.0]:
				pts.append(Vector3(x, 0, 1))
				pts.append(Vector3(x, 2, -1))
				pts.append(Vector3(x, t * 1.41, 1))
				pts.append(Vector3(x, 2 + t * 1.41, -1))
			var s := ConvexPolygonShape3D.new()
			s.points = pts
			return [{"shape": s, "transform": Transform3D()}]
		"stairs":
			var pts := PackedVector3Array()
			for x in [-0.9, 0.9]:
				pts.append(Vector3(x, 0, 1))
				pts.append(Vector3(x, 0, -1))
				pts.append(Vector3(x, size.y, -1))
			var s := ConvexPolygonShape3D.new()
			s.points = pts
			return [{"shape": s, "transform": Transform3D()}]
	return [_box_shape(Vector3(0, y0 + size.y * 0.5, 0), size)]


static func _box_shape(center: Vector3, size: Vector3) -> Dictionary:
	var b := BoxShape3D.new()
	b.size = size
	return {"shape": b, "transform": Transform3D(Basis(), center)}


# --------------------------------------------------------------------------- part builders

static func _L(name: String) -> int:
	return PropMeshes.layer(name)


static func _tint(wood: bool, k: float) -> Color:
	var c := Color(0.86, 0.76, 0.66) if wood else Color(0.86, 0.83, 0.78)
	c = c * k
	c.a = 0.55 if wood else 0.85   # saturation: weathered wood, natural stone
	return c


static func _foundation(st: SurfaceTool, size: Vector3, y0: float, wood: bool) -> void:
	var top := y0 + size.y
	if wood:
		# Log-cabin style: corner posts, perimeter beams and a plank deck.
		var deck_t := 0.16
		_cbox(st, _at(0, top - deck_t * 0.5, 0), Vector3(size.x, deck_t, size.z), CHAMFER, _L("planks"), _tint(true, 1.0), 1.0)
		var beam_h := size.y - deck_t
		for s in [-1.0, 1.0]:
			_cbox(st, _at(0, y0 + beam_h * 0.5, s * (size.z * 0.5 - 0.12)), Vector3(size.x - 0.3, beam_h * 0.7, 0.2), CHAMFER, _L("log_side"), _tint(true, 0.85), 1.0)
			_cbox(st, _at(s * (size.x * 0.5 - 0.12), y0 + beam_h * 0.5, 0), Vector3(0.2, beam_h * 0.7, size.z - 0.3), CHAMFER, _L("log_side"), _tint(true, 0.85), 1.0)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_cbox(st, _at(sx * (size.x * 0.5 - 0.14), y0 + beam_h * 0.5, sz * (size.z * 0.5 - 0.14)), Vector3(0.28, beam_h, 0.28), 0.06, _L("log_side"), _tint(true, 0.7), 1.0)
	else:
		# Chunky cut-stone plinth with a cap slab.
		_cbox(st, _at(0, y0 + (size.y - 0.16) * 0.5, 0), Vector3(size.x - 0.04, size.y - 0.16, size.z - 0.04), 0.06, _L("cobblestone"), _tint(false, 0.95), 0.9)
		_cbox(st, _at(0, top - 0.08, 0), Vector3(size.x, 0.16, size.z), CHAMFER, _L("stone"), _tint(false, 1.05), 0.8)


static func _floor(st: SurfaceTool, size: Vector3, y0: float, wood: bool) -> void:
	_cbox(st, _at(0, y0 + size.y * 0.5, 0), size, CHAMFER * 0.6, _L("planks" if wood else "stone"), _tint(wood, 1.0), 1.0 if wood else 0.75)
	if wood:
		# Two joists underneath so the edge reads as a built floor.
		for s in [-1.0, 1.0]:
			_cbox(st, _at(s * 0.6, y0 - 0.08, 0), Vector3(0.16, 0.16, size.z - 0.1), CHAMFER, _L("planks"), _tint(true, 0.68), 1.0)


## Rectangles (x, y relative to the wall's bottom centre) of solid wall around an opening.
static func _wall_pieces(size: Vector3, opening: Rect2) -> Array:
	var hx := size.x * 0.5
	if opening.size == Vector2.ZERO:
		return [Rect2(-hx, 0, size.x, size.y)]
	var o := opening
	var out := []
	out.append(Rect2(-hx, 0, o.position.x + hx, size.y))                                  # left
	out.append(Rect2(o.end.x, 0, hx - o.end.x, size.y))                                    # right
	if o.position.y > 0.001:
		out.append(Rect2(o.position.x, 0, o.size.x, o.position.y))                         # below
	if o.end.y < size.y - 0.001:
		out.append(Rect2(o.position.x, o.end.y, o.size.x, size.y - o.end.y))               # above
	return out


static func _wall(st: SurfaceTool, size: Vector3, y0: float, wood: bool, opening: Rect2) -> void:
	var hx := size.x * 0.5
	if wood:
		var frame := 0.16
		var panel_t := size.z * 0.6
		# Plank infill (no chamfer: the frame carries the bevels).
		for r in _wall_pieces(Vector3(size.x - frame * 2.0, size.y, size.z), opening):
			var rect: Rect2 = r
			var bottom := maxf(rect.position.y, frame)
			var top := minf(rect.end.y, size.y - frame)
			if top - bottom < 0.02 or rect.size.x < 0.02:
				continue
			_cbox(st, _at(rect.get_center().x, y0 + (bottom + top) * 0.5, 0), Vector3(rect.size.x, top - bottom, panel_t), 0.0, _L("planks"), _tint(true, 1.0), 0.55, true, true)
		# Frame: sill and top plate beams, darker corner posts.
		_cbox(st, _at(0, y0 + frame * 0.5, 0), Vector3(size.x - frame * 2.0, frame, size.z), CHAMFER, _L("planks"), _tint(true, 0.7), 1.0)
		_cbox(st, _at(0, y0 + size.y - frame * 0.5, 0), Vector3(size.x - frame * 2.0, frame, size.z), CHAMFER, _L("planks"), _tint(true, 0.7), 1.0)
		for s in [-1.0, 1.0]:
			_cbox(st, _at(s * (hx - frame * 0.5), y0 + size.y * 0.5, 0), Vector3(frame, size.y, size.z + 0.04), 0.05, _L("log_side"), _tint(true, 0.62), 1.0)
		if opening.size != Vector2.ZERO:
			_opening_trim(st, opening, y0, size.z + 0.04, true)
		elif size.y > 2.0:
			# Mid rail on full walls.
			_cbox(st, _at(0, y0 + size.y * 0.5, 0), Vector3(size.x - frame * 2.0, 0.12, size.z * 0.85), CHAMFER, _L("planks"), _tint(true, 0.72), 1.0)
	else:
		var plinth := 0.22
		var cap := 0.14
		for r in _wall_pieces(size, opening):
			var rect: Rect2 = r
			var bottom := maxf(rect.position.y, plinth)
			var top := minf(rect.end.y, size.y - cap)
			if top - bottom < 0.02 or rect.size.x < 0.02:
				continue
			_cbox(st, _at(rect.get_center().x, y0 + (bottom + top) * 0.5, 0), Vector3(rect.size.x, top - bottom, size.z), 0.03, _L("stone"), _tint(false, 1.0), 0.8, true)
		# Chunky plinth (split around a door) and a cap course.
		for r in _wall_pieces(Vector3(size.x, plinth, size.z), Rect2(opening.position.x, 0, opening.size.x, plinth) if opening.size != Vector2.ZERO and opening.position.y < 0.01 else Rect2()):
			var rect: Rect2 = r
			_cbox(st, _at(rect.get_center().x, y0 + plinth * 0.5, 0), Vector3(rect.size.x, plinth, size.z + 0.06), 0.05, _L("cobblestone"), _tint(false, 0.88), 0.9)
		_cbox(st, _at(0, y0 + size.y - cap * 0.5, 0), Vector3(size.x, cap, size.z + 0.06), 0.04, _L("stone"), _tint(false, 1.08), 0.8)
		if opening.size != Vector2.ZERO:
			_opening_trim(st, opening, y0, size.z + 0.08, false)


## Frame around a door / window opening: jambs, lintel and (windows) a sill and mullion.
static func _opening_trim(st: SurfaceTool, o: Rect2, y0: float, depth: float, wood: bool) -> void:
	var t := 0.1
	var layer := _L("planks" if wood else "stone")
	var c := _tint(wood, 0.65 if wood else 1.1)
	for x in [o.position.x - t * 0.5, o.end.x + t * 0.5]:
		_cbox(st, _at(x, y0 + o.get_center().y, 0), Vector3(t, o.size.y + (t if o.position.y > 0.01 else 0.0), depth), 0.0, layer, c, 1.0)
	_cbox(st, _at(o.get_center().x, y0 + o.end.y + t * 0.5, 0), Vector3(o.size.x + t * 2.0, t, depth), 0.0, layer, c, 1.0)
	if o.position.y > 0.01:
		_cbox(st, _at(o.get_center().x, y0 + o.position.y - t * 0.5, 0), Vector3(o.size.x + t * 2.6, t, depth + 0.08), 0.0, layer, c, 1.0)
		# Cross mullion.
		_cbox(st, _at(o.get_center().x, y0 + o.get_center().y, 0), Vector3(0.05, o.size.y, 0.06), 0.0, layer, c, 1.0)
		_cbox(st, _at(o.get_center().x, y0 + o.get_center().y, 0), Vector3(o.size.x, 0.05, 0.06), 0.0, layer, c, 1.0)


## 45° roof: a sheathing slab rising from y=0 at z=+1 to y=2 at z=-1, with shingle
## (wood) or slate (stone) courses on top.
static func _roof(st: SurfaceTool, wood: bool) -> void:
	var down := Vector3(0, -1, 1).normalized()       # along the slope, towards the eave
	var up_n := Vector3(0, 1, 1).normalized()        # slope normal
	var b := Basis(Vector3.RIGHT, up_n, down)
	var length := 2.0 * sqrt(2.0)
	var t := 0.1
	var mid := Vector3(0, 1, 0)
	_cbox(st, Transform3D(b, mid + up_n * (t * 0.5)), Vector3(2.0, t, length), 0.0, _L("planks"), _tint(true, 0.6), 1.0)
	var courses := 5
	var course_len := length / courses + 0.12
	for i in courses:
		var along := -length * 0.5 + (i + 0.5) * (length / courses)
		var tilt := Basis(Vector3.RIGHT, deg_to_rad(-4.0))  # each course kicks out a little
		var c := Transform3D(b * tilt, mid + down * along + up_n * (t + 0.035 + 0.02 * (i % 2)))
		var tint := Color(0.62, 0.48, 0.34) * (0.9 + 0.08 * (i % 2)) if wood else Color(0.86, 0.86, 0.86) * (0.92 + 0.06 * (i % 2))
		tint.a = 0.55 if wood else 0.6
		_cbox(st, c, Vector3(2.08, 0.07, course_len), 0.02, _L("planks" if wood else "slate"), tint, 0.7, false, wood)


static func _stairs(st: SurfaceTool, size: Vector3, wood: bool) -> void:
	var steps := 8
	var rise := size.y / steps
	var run := size.z / steps
	for i in steps:
		var z_front := size.z * 0.5 - i * run          # steps climb towards -Z
		if wood:
			_cbox(st, _at(0, (i + 1) * rise - 0.05, z_front - run * 0.5), Vector3(1.7, 0.1, run + 0.04), 0.0, _L("planks"), _tint(true, 1.0 - 0.02 * (i % 2)), 1.0)
		else:
			var h := (i + 1) * rise
			_cbox(st, _at(0, h * 0.5, z_front - run * 0.5), Vector3(1.8, h, run), 0.03, _L("stone"), _tint(false, 1.0 - 0.04 * (i % 2)), 0.8)
	if wood:
		# Slanted stringers on both sides.
		var dir := Vector3(0, size.y, -size.z).normalized()
		var length := Vector3(0, size.y, size.z).length()
		var n := Vector3(0, size.z, size.y).normalized()
		var b := Basis(Vector3.RIGHT, n, -dir)
		for s in [-1.0, 1.0]:
			_cbox(st, Transform3D(b, Vector3(s * 0.9, size.y * 0.5 - 0.1, 0)), Vector3(0.12, 0.3, length), CHAMFER, _L("planks"), _tint(true, 0.66), 1.0)


static func _pillar(st: SurfaceTool, size: Vector3, y0: float, wood: bool) -> void:
	if wood:
		_cbox(st, _at(0, y0 + size.y * 0.5, 0), size, 0.06, _L("log_side"), _tint(true, 0.78), 1.0)
	else:
		_cbox(st, _at(0, y0 + 0.12, 0), Vector3(size.x + 0.14, 0.24, size.z + 0.14), 0.04, _L("cobblestone"), _tint(false, 0.9), 0.9)
		_cbox(st, _at(0, y0 + size.y * 0.5, 0), Vector3(size.x, size.y - 0.4, size.z), 0.05, _L("stone"), _tint(false, 1.0), 0.8)
		_cbox(st, _at(0, y0 + size.y - 0.08, 0), Vector3(size.x + 0.12, 0.16, size.z + 0.12), 0.04, _L("stone"), _tint(false, 1.08), 0.8)


static func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


# --------------------------------------------------------------------------- chamfered box

## Box with chamfered edges/corners (44 tris; 12 when chamfer == 0). UVs are projected
## per face in the part's local space at `uv_scale` tiles per metre (image top = up).
## Vertex colour = tint * ground AO (darker near y = 0 of the part).
static func _cbox(st: SurfaceTool, xf: Transform3D, size: Vector3, chamfer: float, layer: int, tint: Color, uv_scale: float, skip_ao := false, rotate_uv := false) -> void:
	var h := size * 0.5
	var c := minf(chamfer, minf(h.x, minf(h.y, h.z)) * 0.45)
	var hc := h - Vector3.ONE * c
	var faces := []   # [points(4 or 3), normal]
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for s in [-1.0, 1.0]:
			var pts := []
			for ab in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
				var p := Vector3.ZERO
				p[axis] = s * h[axis]
				p[u] = ab[0] * hc[u]
				p[v] = ab[1] * hc[v]
				pts.append(p)
			var n := Vector3.ZERO
			n[axis] = s
			faces.append([pts, n])
	if c > 0.0:
		for i in 3:
			for j in range(i + 1, 3):
				var k := 3 - i - j
				for si in [-1.0, 1.0]:
					for sj in [-1.0, 1.0]:
						var pts := []
						for sk in [-1.0, 1.0]:
							var p1 := Vector3.ZERO
							p1[i] = si * h[i]
							p1[j] = sj * hc[j]
							p1[k] = sk * hc[k]
							pts.append(p1)
						for sk in [1.0, -1.0]:
							var p2 := Vector3.ZERO
							p2[i] = si * hc[i]
							p2[j] = sj * h[j]
							p2[k] = sk * hc[k]
							pts.append(p2)
						var n := Vector3.ZERO
						n[i] = si
						n[j] = sj
						faces.append([pts, n.normalized()])
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var pts := [
						Vector3(sx * h.x, sy * hc.y, sz * hc.z),
						Vector3(sx * hc.x, sy * h.y, sz * hc.z),
						Vector3(sx * hc.x, sy * hc.y, sz * h.z)]
					faces.append([pts, Vector3(sx, sy, sz).normalized()])
	var uv2 := Vector2(layer, 0)
	for f in faces:
		var pts: Array = f[0]
		var n_local: Vector3 = f[1]
		var n: Vector3 = (xf.basis * n_local).normalized()
		var wp := []
		var uv := []
		var col := []
		var a := n_local.abs()
		for p: Vector3 in pts:
			var q := xf * p
			wp.append(q)
			# Project in the box's own frame so textures follow rotated parts (roofs).
			var o := xf.basis.inverse() * xf.origin + p
			if a.y >= a.x and a.y >= a.z:
				uv.append(Vector2(o.x, o.z) * uv_scale)
			elif a.x >= a.z:
				uv.append(Vector2(o.z, -o.y) * uv_scale)
			else:
				uv.append(Vector2(o.x, -o.y) * uv_scale)
			if rotate_uv:
				var last: Vector2 = uv[uv.size() - 1]
				uv[uv.size() - 1] = Vector2(last.y, -last.x)
			var ao := 1.0 if skip_ao else lerpf(0.72, 1.0, clampf((q.y + 0.9) / 1.2, 0.0, 1.0))
			if n.y < -0.5:
				ao *= 0.7
			var cc := tint * ao
			cc.a = tint.a
			col.append(cc)
		PropMeshes._tri(st, [wp[0], wp[1], wp[2]], [n, n, n], [col[0], col[1], col[2]], [uv[0], uv[1], uv[2]], n, uv2)
		if pts.size() == 4:
			PropMeshes._tri(st, [wp[0], wp[2], wp[3]], [n, n, n], [col[0], col[2], col[3]], [uv[0], uv[2], uv[3]], n, uv2)
