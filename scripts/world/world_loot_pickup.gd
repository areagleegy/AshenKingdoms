class_name WorldLootPickup
extends Node3D

signal picked_up(item_id: StringName, amount: int)
signal pickup_changed(remaining_amount: int)

const MAX_PICKUP_AMOUNT: int = 10000
const PICKUP_RADIUS: float = 1.15

@export var item: ItemResource
@export_range(1, MAX_PICKUP_AMOUNT, 1) var amount: int = 1
@export var display_label: String = ""

var _prompt: Label3D
var _pickup_area: Area3D
var _pickup_in_progress: bool = false


func _ready() -> void:
	if item == null or amount <= 0 or amount > MAX_PICKUP_AMOUNT:
		push_warning("WorldLootPickup has invalid item or amount; removing invalid pickup.")
		queue_free()
		return

	_build_visuals()
	_build_pickup_area()
	_build_prompt()
	set_prompt_visible(false)


func interact() -> void:
	if _pickup_in_progress or not is_inside_tree() or item == null or amount <= 0:
		return

	var player := get_tree().get_first_node_in_group("player") as Node
	if player == null or not is_instance_valid(player):
		return
	if player is Node3D:
		var distance := (player as Node3D).global_position.distance_to(global_position)
		if distance > PICKUP_RADIUS + 3.2:
			return

	var inventory := player.get_node_or_null("Inventory") as Inventory
	if inventory == null:
		push_warning("Cannot pick up loot: player Inventory node is missing.")
		return

	_pickup_in_progress = true
	var requested := amount
	var leftovers := inventory.add_item(item, requested)
	var accepted := requested - leftovers
	if accepted > 0:
		amount = leftovers
		picked_up.emit(item.id, accepted)
		pickup_changed.emit(amount)
	if amount <= 0:
		queue_free()
	else:
		_update_prompt_text()
	_pickup_in_progress = false


func set_prompt_visible(value: bool) -> void:
	if is_instance_valid(_prompt):
		_prompt.visible = value and amount > 0


func _build_pickup_area() -> void:
	_pickup_area = Area3D.new()
	_pickup_area.name = "PickupArea"
	_pickup_area.collision_layer = 4
	_pickup_area.collision_mask = 0
	_pickup_area.monitoring = true
	_pickup_area.monitorable = true

	var collision_node := CollisionShape3D.new()
	collision_node.name = "CollisionShape3D"
	var sphere := SphereShape3D.new()
	sphere.radius = 0.45
	collision_node.shape = sphere
	_pickup_area.add_child(collision_node)
	add_child(_pickup_area)


func _build_visuals() -> void:
	var visual := MeshInstance3D.new()
	visual.name = "LootVisual"
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.38
	visual.mesh = mesh
	visual.position.y = 0.28

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.75, 0.18, 0.12, 1.0)
	material.roughness = 0.35
	material.metallic = 0.15
	visual.material_override = material
	add_child(visual)


func _build_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.name = "PickupPrompt"
	_prompt.position = Vector3(0.0, 0.85, 0.0)
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.font_size = 28
	_prompt.outline_size = 6
	_prompt.modulate = Color(1.0, 0.92, 0.65, 1.0)
	add_child(_prompt)
	_update_prompt_text()


func _update_prompt_text() -> void:
	if not is_instance_valid(_prompt):
		return
	var item_name := display_label
	if item_name.is_empty() and item != null:
		item_name = item.display_name
	_prompt.text = "E — التقاط %s ×%d" % [item_name, amount]
