class_name Inventory
extends Node

signal inventory_changed
signal item_added(item: ItemResource, amount: int)
signal item_removed(item: ItemResource, amount: int)
signal item_used(item: ItemResource)

const DEFAULT_SLOTS: int = 24
const ITEM_PATHS: Dictionary = {
	"health_potion": "res://resources/items/health_potion.tres"
}

@export_range(1, 80, 1) var slot_count: int = DEFAULT_SLOTS
var slots: Array[Dictionary] = []
var pending_items: Array[Dictionary] = []


func _ready() -> void:
	_ensure_slot_count()


func _ensure_slot_count() -> void:
	if slots.size() == slot_count:
		return
	slots.clear()
	for _index in range(slot_count):
		slots.append({})


## Returns the amount that could not be added. Zero means the full amount was added.
func add_item(item: ItemResource, amount: int = 1) -> int:
	if item == null or amount <= 0:
		return amount
	_ensure_slot_count()

	if item.is_stackable():
		for index in range(slots.size()):
			var slot: Dictionary = slots[index]
			if slot.is_empty():
				continue
			var stored_item: ItemResource = slot.get("item") as ItemResource
			if stored_item == null or stored_item.id != item.id:
				continue
			var stored_amount := int(slot.get("amount", 0))
			if stored_amount >= item.max_stack:
				continue
			var moved := mini(item.max_stack - stored_amount, amount)
			slot["amount"] = stored_amount + moved
			amount -= moved
			item_added.emit(item, moved)
			if amount <= 0:
				inventory_changed.emit()
				return 0

	while amount > 0:
		var empty_index := _find_empty_slot()
		if empty_index < 0:
			break
		var moved := mini(item.max_stack, amount) if item.is_stackable() else 1
		slots[empty_index] = {"item": item, "amount": moved}
		amount -= moved
		item_added.emit(item, moved)

	inventory_changed.emit()
	return amount


func remove_item(item_id: StringName, amount: int = 1) -> bool:
	if amount <= 0 or count_item(item_id) < amount:
		return false
	var remaining := amount
	for index in range(slots.size()):
		if remaining <= 0:
			break
		var slot: Dictionary = slots[index]
		if slot.is_empty():
			continue
		var item: ItemResource = slot.get("item") as ItemResource
		if item == null or item.id != item_id:
			continue
		var removed := mini(int(slot.get("amount", 0)), remaining)
		remaining -= removed
		var left := int(slot.get("amount", 0)) - removed
		if left <= 0:
			slots[index] = {}
		else:
			slot["amount"] = left
		item_removed.emit(item, removed)
	inventory_changed.emit()
	return true


func use_item(slot_index: int, user: Node) -> bool:
	if slot_index < 0 or slot_index >= slots.size() or user == null:
		return false
	var slot: Dictionary = slots[slot_index]
	if slot.is_empty():
		return false
	var item: ItemResource = slot.get("item") as ItemResource
	if item == null or not item.is_consumable():
		return false

	var health := user.get_node_or_null("Health") as Health
	if item.heal_amount > 0.0:
		if health == null or health.is_dead() or health.current >= health.max_health:
			return false
		health.heal(item.heal_amount)

	item_used.emit(item)
	_decrement_slot(slot_index)
	return true


func count_item(item_id: StringName) -> int:
	var total := 0
	for slot in slots:
		if slot.is_empty():
			continue
		var item: ItemResource = slot.get("item") as ItemResource
		if item != null and item.id == item_id:
			total += int(slot.get("amount", 0))
	return total


func has_item(item_id: StringName, amount: int = 1) -> bool:
	return count_item(item_id) >= amount


func to_save_data() -> Array:
	var data: Array = []
	for slot in slots:
		if slot.is_empty():
			data.append(null)
			continue
		var item: ItemResource = slot.get("item") as ItemResource
		if item == null:
			# Preserve entries for content IDs that are not installed in this build.
			var raw: Variant = slot.get("raw", null)
			if raw is Dictionary:
				var preserved: Dictionary = (raw as Dictionary).duplicate(true)
				preserved["id"] = String(slot.get("item_id", preserved.get("id", "")))
				preserved["amount"] = int(slot.get("amount", preserved.get("amount", 1)))
				data.append(preserved)
			else:
				data.append(null)
			continue
		data.append({"id": String(item.id), "amount": int(slot.get("amount", 1))})
	if not pending_items.is_empty():
		data.append({"__inventory_pending_items": pending_items.duplicate(true)})
	return data


func restore_save_data(data: Array) -> void:
	_ensure_slot_count()
	pending_items.clear()
	for index in range(slots.size()):
		slots[index] = {}

	var overflow: Array[Dictionary] = []
	for index in range(mini(data.size(), slots.size())):
		var entry: Variant = data[index]
		if not (entry is Dictionary) or entry.has("__inventory_pending_items"):
			continue
		var item_id := String(entry.get("id", ""))
		if item_id.is_empty():
			continue
		var amount := maxi(1, int(entry.get("amount", 1)))
		var path: String = ITEM_PATHS.get(item_id, "")
		if path.is_empty() or not ResourceLoader.exists(path):
			# Keep the unknown entry in its original slot. UI/use/drop paths already
			# ignore slots whose item resource is null, while serialization preserves it.
			slots[index] = {
				"item_id": item_id,
				"amount": amount,
				"raw": entry.duplicate(true),
			}
			continue

		var item := load(path) as ItemResource
		if item == null:
			slots[index] = {
				"item_id": item_id,
				"amount": amount,
				"raw": entry.duplicate(true),
			}
			continue
		var max_stack := maxi(1, item.max_stack)
		var placed := mini(amount, max_stack)
		slots[index] = {"item": item, "amount": placed}
		if amount > placed:
			overflow.append({"id": item_id, "amount": amount - placed})

	# Read pending entries after the visible slots, preserving compatibility with
	# older saves that contain only one dictionary per slot.
	for entry in data:
		if not (entry is Dictionary) or not entry.has("__inventory_pending_items"):
			continue
		var saved_pending: Variant = entry.get("__inventory_pending_items", [])
		if saved_pending is Array:
			for pending in saved_pending:
				if pending is Dictionary:
					overflow.append((pending as Dictionary).duplicate(true))

	# Refill compatible stacks and empty slots; any remainder stays serialized as
	# pending data instead of being silently discarded when the bag is full.
	for pending in overflow:
		var pending_id := String(pending.get("id", ""))
		var pending_amount := maxi(1, int(pending.get("amount", 1)))
		var pending_path: String = ITEM_PATHS.get(pending_id, "")
		if pending_path.is_empty() or not ResourceLoader.exists(pending_path):
			pending_items.append(pending.duplicate(true))
			continue
		var pending_item := load(pending_path) as ItemResource
		if pending_item == null:
			pending_items.append(pending.duplicate(true))
			continue
		var remaining := add_item(pending_item, pending_amount)
		if remaining > 0:
			pending_items.append({"id": pending_id, "amount": remaining})
	inventory_changed.emit()


func _find_empty_slot() -> int:
	for index in range(slots.size()):
		if slots[index].is_empty():
			return index
	return -1


func _decrement_slot(index: int) -> void:
	var slot: Dictionary = slots[index]
	var remaining := int(slot.get("amount", 0)) - 1
	if remaining <= 0:
		slots[index] = {}
	else:
		slot["amount"] = remaining
	inventory_changed.emit()
