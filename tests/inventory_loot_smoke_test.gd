extends SceneTree

const INVENTORY_SCRIPT = preload("res://scripts/components/inventory.gd")
const ITEM_PATH = "res://resources/items/health_potion.tres"
const LOOT_SCRIPT = preload("res://scripts/components/loot_container.gd")

var _failed: bool = false


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var item := load(ITEM_PATH) as ItemResource
	if item == null:
		_fail("Could not load health potion resource.")
		quit(1)
		return

	var inventory: Inventory = INVENTORY_SCRIPT.new()
	root.add_child(inventory)
	await process_frame

	var leftovers: int = inventory.add_item(item, 25)
	_expect(leftovers == 0, "25 potions should fit in the 24-slot inventory.")
	_expect(inventory.count_item(item.id) == 25, "Inventory should contain all 25 potions.")
	_expect(int(inventory.slots[0].get("amount", 0)) == item.max_stack, "First stack should respect max_stack.")

	var count_before_zero_add := inventory.count_item(item.id)
	_expect(inventory.add_item(item, 0) == 0, "Zero-amount input should normalize to zero leftovers.")
	_expect(inventory.add_item(item, -5) == 0, "Negative amounts must normalize to zero leftovers.")
	_expect(inventory.count_item(item.id) == count_before_zero_add, "Non-positive input must not change inventory.")
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
	_expect(loot.take_loot(-1, 1, inventory) == 0, "Negative slot indices must be rejected.")
	_expect(loot.take_loot(0, -1, inventory) == 0, "Non-positive transfer amounts must be rejected.")
	_expect(not loot.add_loot(item, 0), "Zero-amount loot must be rejected.")
	_expect(not loot.add_loot(item, LootContainer.MAX_LOOT_AMOUNT + 1), "Excessive loot amounts must be rejected.")

	var multi_stack_loot: LootContainer = LOOT_SCRIPT.new()
	root.add_child(multi_stack_loot)
	_expect(multi_stack_loot.add_loot(item, item.max_stack * 2 + 5), "Large valid loot should be split into bounded stacks.")
	_expect(multi_stack_loot.contents.size() == 3, "45 potions should occupy three loot stacks.")
	_expect(int(multi_stack_loot.contents[0].get("amount", 0)) == item.max_stack, "Loot stacks must not exceed max_stack.")
	_expect(int(multi_stack_loot.contents[2].get("amount", 0)) == 5, "Final partial loot stack should preserve the remainder.")

	var full_inventory: Inventory = INVENTORY_SCRIPT.new()
	root.add_child(full_inventory)
	await process_frame
	var full_leftovers := full_inventory.add_item(item, item.max_stack * full_inventory.slot_count)
	_expect(full_leftovers == 0, "Inventory should be fillable to capacity.")
	var overflow_loot: LootContainer = LOOT_SCRIPT.new()
	root.add_child(overflow_loot)
	_expect(overflow_loot.add_loot(item, 7), "Overflow loot should be stored in the container.")
	_expect(overflow_loot.take_loot(0, 7, full_inventory) == 0, "Full inventory must not accept additional loot.")
	_expect(int(overflow_loot.contents[0].get("amount", 0)) == 7, "Unaccepted loot must remain in the container.")

	inventory.queue_free()
	loot.queue_free()
	multi_stack_loot.queue_free()
	full_inventory.queue_free()
	overflow_loot.queue_free()
	if _failed:
		quit(1)
	else:
		print("Inventory/Loot smoke tests completed.")
		quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	push_error("Inventory/Loot test failed: " + message)
