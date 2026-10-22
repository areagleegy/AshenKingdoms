class_name WorldItemDrop
extends Area3D

const ITEM_PATHS: Dictionary = {
	"health_potion": "res://resources/items/health_potion.tres"
}
const PICKUP_LOCK_MSEC: int = 750

@export var item_id: StringName = &""
@export_range(1, 999, 1) var amount: int = 1

var _available_after_msec: int = 0
var _item: ItemResource


func configure(item_identifier: StringName, quantity: int = 1) -> bool:
	if String(item_identifier).is_empty() or quantity <= 0:
		return false
	item_id = item_identifier
	amount = mini(quantity, 999)
	var path: String = ITEM_PATHS.get(String(item_id), "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return false
	_item = load(path) as ItemResource
	return _item != null


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	_available_after_msec = Time.get_ticks_msec() + PICKUP_LOCK_MSEC
	body_entered.connect(_on_body_entered)

	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.8
	collision.shape = sphere
	add_child(collision)

	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.44
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.72, 0.52, 0.19, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.16, 0.09, 0.015, 1.0)
	visual.material_override = material
	add_child(visual)


func _on_body_entered(body: Node3D) -> void:
	if Time.get_ticks_msec() < _available_after_msec or amount <= 0 or _item == null:
		return
	if not body.is_in_group("player"):
		return
	var inventory := body.get_node_or_null("Inventory") as Inventory
	if inventory == null:
		return

	var remaining := inventory.add_item(_item, amount)
	remaining = clampi(remaining, 0, amount)
	var accepted := amount - remaining
	if accepted <= 0:
		return
	amount = remaining
	if amount <= 0:
		queue_free()
