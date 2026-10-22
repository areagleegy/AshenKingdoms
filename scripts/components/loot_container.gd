class_name LootContainer
extends Node

signal contents_changed
signal loot_transferred(item_id: StringName, amount: int)

const MAX_LOOT_AMOUNT: int = 10000

@export var container_id: StringName = &""
@export var single_use: bool = false

var contents: Array[Dictionary] = []
var opened: bool = false


func add_loot(item: ItemResource, amount: int = 1) -> bool:
	if item == null or amount <= 0 or amount > MAX_LOOT_AMOUNT:
		return false
	if item.max_stack < 1 or (single_use and opened):
		return false

	var remaining := amount
	if item.is_stackable():
		for index in range(contents.size()):
			var existing: ItemResource = contents[index].get("item") as ItemResource
			if existing == null or existing.id != item.id:
				continue
			var current := int(contents[index].get("amount", 0))
			if current < 1 or current >= item.max_stack:
				continue
			var moved := mini(item.max_stack - current, remaining)
			contents[index]["amount"] = current + moved
			remaining -= moved
			if remaining == 0:
				contents_changed.emit()
				return true

	while remaining > 0:
		var stack_amount := mini(item.max_stack, remaining) if item.is_stackable() else 1
		contents.append({"item": item, "amount": stack_amount})
		remaining -= stack_amount

	contents_changed.emit()
	return true


## Transfers only what the inventory accepted; unaccepted loot stays in the container.
func take_loot(slot_index: int, requested_amount: int, inventory: Inventory) -> int:
	if inventory == null or slot_index < 0 or slot_index >= contents.size():
		return 0
	if requested_amount <= 0:
		return 0

	var slot: Dictionary = contents[slot_index]
	var item: ItemResource = slot.get("item") as ItemResource
	var available := int(slot.get("amount", 0))
	if item == null or available <= 0:
		return 0

	var transfer_amount := mini(requested_amount, available)
	var remaining := inventory.add_item(item, transfer_amount)
	var accepted := transfer_amount - remaining
	if accepted <= 0:
		return 0

	var left := available - accepted
	if left <= 0:
		contents.remove_at(slot_index)
	else:
		slot["amount"] = left

	opened = true
	loot_transferred.emit(item.id, accepted)
	contents_changed.emit()
	return accepted
