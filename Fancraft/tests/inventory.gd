extends SceneTree
## Headless inventory checks. Prints INVENTORY_RESULT failures=N.

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL: ") + what)
	if not cond:
		failures += 1


func _initialize() -> void:
	var inv := Inventory.new()
	check(inv.add("wood", 30) == 0 and inv.count("wood") == 30, "add wood")
	check(inv.add("wood", 30) == 0 and inv.count("wood") == 60 and not inv.slots[1].is_empty(), "stacks split at 50")
	check(inv.slots[0].n == 50 and inv.slots[1].n == 10, "first stack filled before a new one")
	check(inv.has_all({"wood": 60}) and not inv.has_all({"wood": 61}), "has_all")
	check(inv.pay({"wood": 15}) and inv.count("wood") == 45, "pay removes the cost")
	check(not inv.pay({"wood": 5, "stone": 1}) and inv.count("wood") == 45, "failed payment changes nothing")
	var big := Inventory.new()
	var left := big.add("dirt", 99 * 30)
	check(left == 99 * 6 and big.count("dirt") == 99 * 24, "overflow reports what did not fit")
	check(big.space_for("stone") == 0 and big.add("stone", 3) == 3, "full inventory refuses new items")
	var messy := Inventory.new()
	messy.add("stone", 10)
	messy.add("wood", 5)
	messy.slots[5] = {"id": "stone", "n": 7}
	messy.sort()
	check(messy.slots[0].id == "wood" and messy.slots[1].id == "stone" and messy.slots[1].n == 17 and messy.slots[2].is_empty(), "sort merges and orders stacks")
	var c := Inventory.new()
	c.creative = true
	check(c.pay({"wood": 999}) and c.has_all({"stone": 5}), "creative mode is free")
	var copy := Inventory.new()
	copy.from_data(inv.to_data())
	check(copy.count("wood") == 45, "save/load round trip")
	print("INVENTORY_RESULT failures=%d" % failures)
	quit(1 if failures else 0)
