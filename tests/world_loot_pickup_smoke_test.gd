extends SceneTree

const INVENTORY_SCRIPT = preload("res://scripts/components/inventory.gd")
const PICKUP_SCRIPT = preload("res://scripts/world/world_loot_pickup.gd")
const ITEM_PATH = "res://resources/items/health_potion.tres"

var _failed: bool = false


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var item := load(ITEM_PATH) as ItemResource
	if item == null:
		_fail("Health potion resource could not be loaded.")
		quit(1)
		return

	var player := Node3D.new()
	player.name = "TestPlayer"
	player.add_to_group("player")
	var inventory: Inventory = INVENTORY_SCRIPT.new()
	inventory.name = "Inventory"
	player.add_child(inventory)
	root.add_child(player)
	await process_frame

	var pickup := PICKUP_SCRIPT.new() as WorldLootPickup
	if pickup == null:
		_fail("World loot pickup script could not be instantiated.")
		quit(1)
		return
	pickup.item = item
	pickup.amount = 5
	pickup.display_label = "Test Potion"
	root.add_child(pickup)
	await process_frame

	# Leave room for exactly three potions so the pickup must preserve overflow.
	var target_total := item.max_stack * inventory.slot_count - 3
	var leftovers := inventory.add_item(item, target_total)
	_expect(leftovers == 0, "Test inventory should fill to exactly three free units.")
	pickup.interact()
	_expect(inventory.count_item(item.id) == target_total + 3, "Pickup should transfer only the accepted quantity.")
	_expect(pickup.amount == 2, "Unaccepted pickup quantity should remain in the world.")
	_expect(is_instance_valid(pickup), "Partially collected pickup must remain available.")

	# Repeating interaction with the remaining two should finish collection.
	for index in range(inventory.slots.size()):
		if inventory.slots[index].is_empty():
			break
	# Free three units by removing items, then collect the remainder.
	_expect(inventory.remove_item(item.id, 3), "Inventory should permit making room for the remaining pickup.")
	pickup.interact()
	_expect(inventory.count_item(item.id) == target_total + 2, "Second interaction should transfer the remaining quantity.")
	_expect(pickup.amount == 0 or not is_instance_valid(pickup), "Fully collected pickup should be removed.")

	if _failed:
		quit(1)
	else:
		print("World loot pickup smoke tests completed.")
		quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	push_error("World loot pickup test failed: " + message)
