extends Node

const DEFAULT_PORT: int = 7777
const MAX_CLIENTS: int = 8
const NETWORK_ARENA_PATH: String = "res://scenes/network/MultiplayerArena.tscn"


func _ready() -> void:
	var network_manager := get_node_or_null("/root/NetworkManager")
	if network_manager == null:
		push_error("Dedicated server requires the NetworkManager autoload.")
		get_tree().quit(1)
		return

	var port := _get_server_port()
	var result := int(network_manager.call("start_host", port, MAX_CLIENTS))
	if result != OK:
		push_error("Dedicated server could not start on port %d: %s" % [port, error_string(result)])
		get_tree().quit(1)
		return

	print("[server] ENet host listening on UDP port %d (max clients: %d)." % [port, MAX_CLIENTS])
	call_deferred("_load_network_arena")


func _load_network_arena() -> void:
	var network_manager := get_node_or_null("/root/NetworkManager")
	var result := get_tree().change_scene_to_file(NETWORK_ARENA_PATH)
	if result != OK:
		push_error("Dedicated server could not load network arena: %s" % error_string(result))
		network_manager.call("leave_session", false)
		get_tree().quit(1)


func _get_server_port() -> int:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--server-port="):
			var value := argument.trim_prefix("--server-port=")
			if value.is_valid_int():
				return clampi(value.to_int(), 1, 65535)
	return DEFAULT_PORT
