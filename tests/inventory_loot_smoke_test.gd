extends SceneTree

const INVENTORY_SCRIPT = preload("res://scripts/components/inventory.gd")
const ITEM_PATH = "res://resources/items/health_potion.tres"
const LOOT_SCRIPT = preload("res://scripts/components/loot_container.gd")

func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var inventory: Inventory = INVENTORY_SCRIPT.new()
	root.add_child(inventory)
	await process_frame

	var item := load(ITEM_PATH) as ItemResource
	if item == null:
		_fail("Could not load health potion resource.")
		return

	var leftovers: int = inventory.add_item(item, 25)
	_expect(leftovers == 0, "25 potions should fit in the 24-slot inventory.")
	_expect(inventory.count_item(item.id) == 25, "Inventory should contain all 25 potions.")
	_expect(int(inventory.slots[0].get("amount", 0)) == item.max_stack, "First stack should respect max_stack.")

	var removed := inventory.remove_item(item.id, 5)
	_expect(removed, "Removing an available quantity should succeed.")
	_expect(inventory.count_item(item.id) == 20, "Removal should subtract the exact quantity.")
	_expect(not inventory.remove_item(item.id, 1000), "Removing more than owned must fail.")

	var loot: LootContainer = LOOT_SCRIPT.new()
	root.add_child(loot)
	_expect(loot.add_loot(item, 10), "Container should accept valid loot.")
	var accepted := loot.take_loot(0, 10, inventory)
	_expect(accepted == 10, "Container should transfer requested loot when space exists.")
	_expect(inventory.count_item(item.id) == 30, "Transferred loot should be reflected in inventory.")
	_expect(loot.contents.is_empty(), "Fully transferred loot should be removed from the container.")

	inventory.queue_free()
	loot.queue_free()
	print("Inventory/Loot smoke tests completed.")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	push_error("Inventory/Loot test failed: " + message)
	quit(1)
