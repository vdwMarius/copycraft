class_name Inventory
extends RefCounted
## Slot-based inventory with stacking. Pure data (no scene access) so it is easy to
## test and to save later.

signal changed
signal gained(id: String, amount: int)

const SLOTS := 24

var slots: Array = []        # each: {} (empty) or {"id": String, "n": int}
var creative := false        # creative mode: everything is free and unlimited


func _init() -> void:
	slots.resize(SLOTS)
	for i in SLOTS:
		slots[i] = {}


func count(id: String) -> int:
	var n := 0
	for s in slots:
		if s.get("id", "") == id:
			n += s.n
	return n


func space_for(id: String) -> int:
	var room := 0
	var cap := Items.max_stack(id)
	for s in slots:
		if s.is_empty():
			room += cap
		elif s.id == id:
			room += cap - s.n
	return room


## Add items, filling existing stacks first. Returns how many did NOT fit.
func add(id: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var left := amount
	var cap := Items.max_stack(id)
	for s in slots:
		if left == 0:
			break
		if not s.is_empty() and s.id == id and s.n < cap:
			var take := mini(cap - s.n, left)
			s.n += take
			left -= take
	for i in SLOTS:
		if left == 0:
			break
		if slots[i].is_empty():
			var take := mini(cap, left)
			slots[i] = {"id": id, "n": take}
			left -= take
	if left != amount:
		gained.emit(id, amount - left)
		changed.emit()
	return left


func has_all(cost: Dictionary) -> bool:
	if creative:
		return true
	for id in cost:
		if count(id) < cost[id]:
			return false
	return true


## Remove items (taken from the last stacks first). Returns false and changes nothing
## if there are not enough.
func remove(id: String, amount: int) -> bool:
	if creative:
		return true
	if count(id) < amount:
		return false
	var left := amount
	for i in range(SLOTS - 1, -1, -1):
		var s: Dictionary = slots[i]
		if left == 0:
			break
		if not s.is_empty() and s.id == id:
			var take := mini(s.n, left)
			s.n -= take
			left -= take
			if s.n == 0:
				slots[i] = {}
	changed.emit()
	return true


func pay(cost: Dictionary) -> bool:
	if not has_all(cost):
		return false
	for id in cost:
		remove(id, cost[id])
	return true


## Combine partial stacks and move items to the front (inventory "sort" button).
func sort() -> void:
	var totals := {}
	for s in slots:
		if not s.is_empty():
			totals[s.id] = totals.get(s.id, 0) + s.n
	for i in SLOTS:
		slots[i] = {}
	var i := 0
	for id in Items.ORDER + totals.keys().filter(func(k): return k not in Items.ORDER):
		var n: int = totals.get(id, 0)
		while n > 0 and i < SLOTS:
			var take := mini(n, Items.max_stack(id))
			slots[i] = {"id": id, "n": take}
			n -= take
			i += 1
	changed.emit()


func to_data() -> Array:
	return slots.duplicate(true)


func from_data(data: Array) -> void:
	for i in SLOTS:
		slots[i] = data[i] if i < data.size() and typeof(data[i]) == TYPE_DICTIONARY else {}
	changed.emit()
