class_name VoxelWorld
extends Node3D
## Streams chunk columns around a focus point, generating and meshing them on
## worker threads and uploading a bounded amount of geometry per frame.

signal spawn_ready

const CS := 16
const COLLISION_RADIUS := 2          # chunk columns around the player with physics
const UPLOAD_BUDGET_USEC := 2500     # main-thread time per frame for mesh uploads

var generator: TerrainGenerator
var focus: Node3D
var render_distance := 6

var chunks := {}            # Vector3i -> Chunk
var columns := {}           # Vector2i -> 0 queued, 1 generating, 2 generated, 3 meshed
var nodes := {}             # Vector3i -> MeshInstance3D
var bodies := {}            # Vector3i -> StaticBody3D
var collision_faces := {}   # Vector3i -> PackedVector3Array
var versions := {}          # Vector3i -> int, bumped on every edit
var applied := {}           # Vector3i -> version of the mesh currently shown
var edited_store := {}      # Vector3i -> Chunk, kept when columns unload

var materials: Array[ShaderMaterial] = []
var stats := {"chunks": 0, "meshes": 0, "triangles": 0, "gen_ms": 0.0, "mesh_ms": 0.0, "queue": 0}

var _tables: Dictionary
var _center := Vector2i(1 << 30, 0)
var _gen_queue: Array[Vector2i] = []
var _mesh_queue: Array[Vector2i] = []
var _edit_done: Array = []
var _tasks := []
var _mutex := Mutex.new()
var _gen_done: Array = []
var _mesh_done: Array = []
var _max_tasks := 2
var _spawned := false
var _quitting := false


func setup(seed_value: int, focus_node: Node3D, mats: Array[ShaderMaterial]) -> void:
	generator = TerrainGenerator.new(seed_value)
	focus = focus_node
	materials = mats
	_tables = Mesher.tables_from(Blocks)
	_max_tasks = clampi(int(OS.get_processor_count() * 0.6), 1, 6)
	render_distance = Settings.get_value("render_distance")
	Settings.changed.connect(_on_setting)


func _on_setting(key: String) -> void:
	if key == "render_distance":
		render_distance = Settings.get_value("render_distance")
		_center = Vector2i(1 << 30, 0)


func _exit_tree() -> void:
	_quitting = true
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()


static func column_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / CS), floori(pos.z / CS))


func _process(_delta: float) -> void:
	if focus == null:
		return
	var c := column_of(focus.global_position)
	if c != _center:
		_center = c
		_replan()
	_reap_tasks()
	_collect_generated()
	_dispatch()
	_upload()
	stats.queue = _gen_queue.size() + _mesh_queue.size()


# ------------------------------------------------------------------ planning

func _in_range(col: Vector2i, extra := 0) -> bool:
	var d := col - _center
	var r := render_distance + extra
	return d.x * d.x + d.y * d.y <= r * r + r


func _replan() -> void:
	# Unload far columns.
	for col in columns.keys():
		if not _in_range(col, 2) and columns[col] != 1:
			_unload_column(col)
	# Queue missing columns by distance.
	_gen_queue.clear()
	var r := render_distance + 1
	for z in range(-r, r + 1):
		for x in range(-r, r + 1):
			var col := _center + Vector2i(x, z)
			if not columns.has(col) and _in_range(col, 1):
				_gen_queue.append(col)
	_gen_queue.sort_custom(func(a, b): return (a - _center).length_squared() > (b - _center).length_squared())
	# Re-sort pending mesh work too (nearest last so pop_back takes it).
	_mesh_queue.sort_custom(func(a, b): return (a - _center).length_squared() > (b - _center).length_squared())
	_update_collision()


func _unload_column(col: Vector2i) -> void:
	for y in TerrainGenerator.WORLD_CHUNKS_Y:
		var c := Vector3i(col.x, y, col.y)
		if chunks.has(c):
			var ch: Chunk = chunks[c]
			if ch.edited:
				edited_store[c] = ch
			chunks.erase(c)
		if nodes.has(c):
			stats.triangles -= nodes[c].get_meta("tris", 0)
			nodes[c].queue_free()
			nodes.erase(c)
		if bodies.has(c):
			bodies[c].queue_free()
			bodies.erase(c)
		collision_faces.erase(c)
		applied.erase(c)
	columns.erase(col)
	_mesh_queue.erase(col)


# ------------------------------------------------------------------ worker jobs

func _reap_tasks() -> void:
	var i := 0
	while i < _tasks.size():
		if WorkerThreadPool.is_task_completed(_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks.remove_at(i)
		else:
			i += 1


func _dispatch() -> void:
	while _tasks.size() < _max_tasks and not _mesh_queue.is_empty():
		var col: Vector2i = _mesh_queue.pop_back()
		if not columns.has(col) or columns[col] != 2:
			continue
		columns[col] = 3
		for y in TerrainGenerator.WORLD_CHUNKS_Y:
			var c := Vector3i(col.x, y, col.y)
			var ch: Chunk = chunks.get(c)
			if ch == null or ch.is_empty():
				continue
			var job := [[c, _snapshot(c), versions.get(c, 0)]]
			_tasks.append(WorkerThreadPool.add_task(_mesh_job.bind(job, false), false, "fancraft mesh"))
	while _tasks.size() < _max_tasks and not _gen_queue.is_empty():
		var col: Vector2i = _gen_queue.pop_back()
		if columns.has(col):
			continue
		columns[col] = 1
		_tasks.append(WorkerThreadPool.add_task(_gen_job.bind(col), false, "fancraft generate"))


func _gen_job(col: Vector2i) -> void:
	var t := Time.get_ticks_usec()
	var out := []
	for y in TerrainGenerator.WORLD_CHUNKS_Y:
		out.append(generator.generate(Vector3i(col.x, y, col.y)))
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	_mutex.lock()
	_gen_done.append([col, out, ms])
	_mutex.unlock()


func _mesh_job(job: Array, is_edit: bool) -> void:
	var mesher := Mesher.new(_tables)
	var results := []
	for entry in job:
		if _quitting:
			return
		var t := Time.get_ticks_usec()
		var r := mesher.build(entry[1])
		r.coord = entry[0]
		r.version = entry[2]
		r.ms = (Time.get_ticks_usec() - t) / 1000.0
		results.append(r)
	_mutex.lock()
	if is_edit:
		_edit_done.append_array(results)
	else:
		_mesh_done.append_array(results)
	_mutex.unlock()


func _snapshot(c: Vector3i) -> Array:
	var n := []
	n.resize(27)
	for dy in range(-1, 2):
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var ch: Chunk = chunks.get(c + Vector3i(dx, dy, dz))
				n[(dx + 1) + (dz + 1) * 3 + (dy + 1) * 9] = null if ch == null else [ch.cells, ch.details]
				if ch and OS.has_environment("FANCRAFT_VALIDATE"):
					if ch.cells.size() != 4096:
						printerr("BAD cells size ", ch.coord, " ", ch.cells.size())
					for i in 4096:
						if ch.cells[i] == -1 and not ch.details.has(i):
							printerr("BAD detail missing ", ch.coord, " ", i)
							break
	return n


func _collect_generated() -> void:
	_mutex.lock()
	var done := _gen_done
	_gen_done = []
	_mutex.unlock()
	for item in done:
		var col: Vector2i = item[0]
		stats.gen_ms = lerpf(stats.gen_ms, item[2], 0.1)
		if not columns.has(col):
			continue  # unloaded while generating
		for ch: Chunk in item[1]:
			if edited_store.has(ch.coord):
				ch = edited_store[ch.coord]
				edited_store.erase(ch.coord)
			chunks[ch.coord] = ch
		columns[col] = 2
		# This column and its neighbours may now have everything they need.
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var n := col + Vector2i(dx, dz)
				if columns.get(n, -1) == 2 and _neighbours_ready(n) and _in_range(n) and not _mesh_queue.has(n):
					_mesh_queue.append(n)
	if not done.is_empty():
		_mesh_queue.sort_custom(func(a, b): return (a - _center).length_squared() > (b - _center).length_squared())
	stats.chunks = chunks.size()


func _neighbours_ready(col: Vector2i) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if columns.get(col + Vector2i(dx, dz), -1) < 2:
				return false
	return true


# ------------------------------------------------------------------ uploads

func _upload() -> void:
	# Player edits first, without a time budget, so building feels instant.
	_mutex.lock()
	var edits := _edit_done
	_edit_done = []
	_mutex.unlock()
	for r in edits:
		_apply_mesh(r)
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < UPLOAD_BUDGET_USEC:
		_mutex.lock()
		var r = _mesh_done.pop_front() if not _mesh_done.is_empty() else null
		_mutex.unlock()
		if r == null:
			break
		_apply_mesh(r)
	if not _spawned and focus:
		var c := column_of(focus.global_position)
		var p := focus.global_position
		var sy := floori(surface_height(p.x, p.z) / CS)
		for y in [sy, sy - 1]:
			if bodies.has(Vector3i(c.x, y, c.y)):
				_spawned = true
				spawn_ready.emit()
				break


func _apply_mesh(r: Dictionary) -> void:
	var c: Vector3i = r.coord
	# Results can arrive out of order; never replace a newer mesh with an older one.
	if not chunks.has(c) or r.version <= applied.get(c, -1):
		return
	applied[c] = r.version
	stats.mesh_ms = lerpf(stats.mesh_ms, r.ms, 0.1)
	var mesh := ArrayMesh.new()
	var tris := 0
	for pass_i in 3:
		var p: Dictionary = r.passes[pass_i]
		if p.verts.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = p.verts
		arrays[Mesh.ARRAY_NORMAL] = p.norms
		arrays[Mesh.ARRAY_TEX_UV] = p.uvs
		arrays[Mesh.ARRAY_COLOR] = p.cols
		arrays[Mesh.ARRAY_INDEX] = p.idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[pass_i])
		tris += p.idx.size() / 3
	var mi: MeshInstance3D = nodes.get(c)
	if mesh.get_surface_count() == 0:
		if mi:
			stats.triangles -= mi.get_meta("tris", 0)
			mi.queue_free()
			nodes.erase(c)
	else:
		if mi == null:
			mi = MeshInstance3D.new()
			mi.position = Vector3(c) * CS
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			add_child(mi)
			nodes[c] = mi
		mi.mesh = mesh
		stats.triangles += tris - mi.get_meta("tris", 0)
		mi.set_meta("tris", tris)
	collision_faces[c] = r.collision
	if _wants_collision(c):
		_build_body(c)
	stats.meshes = nodes.size()


# ------------------------------------------------------------------ collision

func _wants_collision(c: Vector3i) -> bool:
	return absi(c.x - _center.x) <= COLLISION_RADIUS and absi(c.z - _center.y) <= COLLISION_RADIUS


func _build_body(c: Vector3i) -> void:
	var faces: PackedVector3Array = collision_faces.get(c, PackedVector3Array())
	var body: StaticBody3D = bodies.get(c)
	if faces.is_empty():
		if body:
			body.queue_free()
			bodies.erase(c)
		return
	if body == null:
		body = StaticBody3D.new()
		body.position = Vector3(c) * CS
		var cs := CollisionShape3D.new()
		body.add_child(cs)
		add_child(body)
		bodies[c] = body
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	(body.get_child(0) as CollisionShape3D).shape = shape


func _update_collision() -> void:
	for c in bodies.keys():
		if not _wants_collision(c):
			bodies[c].queue_free()
			bodies.erase(c)
	for c in collision_faces:
		if _wants_collision(c) and not bodies.has(c):
			_build_body(c)


# ------------------------------------------------------------------ queries & edits

## Material at a world quarter-cell coordinate.
func get_micro(q: Vector3i) -> int:
	var c := Vector3i(floori(q.x / 64.0), floori(q.y / 64.0), floori(q.z / 64.0))
	var ch: Chunk = chunks.get(c)
	if ch == null:
		return 0
	return ch.get_micro(q.x - c.x * 64, q.y - c.y * 64, q.z - c.z * 64)


func get_block_at(pos: Vector3) -> int:
	return get_micro(Vector3i((pos * 4.0).floor()))


## True if every chunk the box touches is loaded.
func box_loaded(box: AABB) -> bool:
	var from := Vector3i(box.position)
	var to := Vector3i(box.end) - Vector3i.ONE
	for cy in range(floori(from.y / 64.0), floori(to.y / 64.0) + 1):
		if cy < 0 or cy >= TerrainGenerator.WORLD_CHUNKS_Y:
			return false
		for cz in range(floori(from.z / 64.0), floori(to.z / 64.0) + 1):
			for cx in range(floori(from.x / 64.0), floori(to.x / 64.0) + 1):
				if not chunks.has(Vector3i(cx, cy, cz)):
					return false
	return true


## Is any quarter-cell inside `box` (world quarter coordinates) solid?
func box_has_solid(box: AABB) -> bool:
	var from := Vector3i(box.position)
	var to := Vector3i(box.end)
	for y in range(from.y, to.y):
		for z in range(from.z, to.z):
			for x in range(from.x, to.x):
				var m := get_micro(Vector3i(x, y, z))
				if m != 0 and Blocks.solid[m] == 1:
					return true
	return false


## Fill a box of world quarter-cells with `id` (0 removes). Returns cells changed.
func edit_box(box: AABB, id: int) -> int:
	if not box_loaded(box):
		return 0
	var from := Vector3i(box.position)
	var to := Vector3i(box.end)
	var changed := 0
	var dirty := {}
	for cy in range(floori(from.y / 64.0), floori((to.y - 1) / 64.0) + 1):
		for cz in range(floori(from.z / 64.0), floori((to.z - 1) / 64.0) + 1):
			for cx in range(floori(from.x / 64.0), floori((to.x - 1) / 64.0) + 1):
				var c := Vector3i(cx, cy, cz)
				var ch: Chunk = chunks[c]
				var base := c * 64
				var lf := (from - base).clamp(Vector3i.ZERO, Vector3i(64, 64, 64))
				var lt := (to - base).clamp(Vector3i.ZERO, Vector3i(64, 64, 64))
				# Packed arrays and dictionaries are shared by reference in Godot 4, and
				# worker snapshots may still be reading them: edit fresh copies instead.
				ch.cells = ch.cells.duplicate()
				ch.details = ch.details.duplicate()
				var before := ch.cells.duplicate()
				var before_details := ch.details.duplicate()
				ch.fill_micro_box(lf, lt, id)
				if ch.cells != before or not _same_details(before_details, ch.details):
					changed += 1
					ch.edited = true
					dirty[c] = true
					# Neighbours whose faces/AO may change.
					for dy in range(-1, 2):
						for dz in range(-1, 2):
							for dx in range(-1, 2):
								var n := c + Vector3i(dx, dy, dz)
								if chunks.has(n):
									var touches := _box_near_chunk(from, to, n)
									if touches:
										dirty[n] = true
	if dirty.is_empty():
		return changed
	# Remesh right away on a high-priority worker job (edited chunk first), bypassing
	# the streaming queue so the change shows up within a frame or two.
	var order: Array = dirty.keys()
	var centre := Vector3((from + to) / 2) / 64.0
	order.sort_custom(func(a, b): return Vector3(a).distance_squared_to(centre) < Vector3(b).distance_squared_to(centre))
	var job := []
	for c in order:
		versions[c] = versions.get(c, 0) + 1
		job.append([c, _snapshot(c), versions[c]])
	_tasks.append(WorkerThreadPool.add_task(_mesh_job.bind(job, true), true, "fancraft edit"))
	return changed


static func _same_details(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k) or a[k] != b[k]:
			return false
	return true


## Does the edited box come within one quarter of chunk `n` (so its border faces/AO change)?
static func _box_near_chunk(from: Vector3i, to: Vector3i, n: Vector3i) -> bool:
	var lo := n * 64 - Vector3i(4, 4, 4)
	var hi := n * 64 + Vector3i(68, 68, 68)
	return from.x < hi.x and to.x > lo.x and from.y < hi.y and to.y > lo.y and from.z < hi.z and to.z > lo.z


func surface_height(x: float, z: float) -> float:
	return generator.height_at(x, z)
