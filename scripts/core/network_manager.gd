extends Node

signal status_changed(message: String)
signal session_connected
signal connection_failed(reason: String)
signal session_ended(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal peer_arena_ready(peer_id: int)

const DEFAULT_PORT: int = 7777
const DEFAULT_MAX_CLIENTS: int = 8
const CONNECTION_TIMEOUT_SECONDS: float = 12.0

var session_mode: String = "offline"
var session_port: int = DEFAULT_PORT

var _client_connected: bool = false
var _connection_generation: int = 0
var _ready_peers: Dictionary = {}


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func start_host(port: int = DEFAULT_PORT, max_clients: int = DEFAULT_MAX_CLIENTS) -> int:
	if port < 1 or port > 65535:
		return ERR_INVALID_PARAMETER
	if max_clients < 1 or max_clients > 64:
		return ERR_INVALID_PARAMETER

	leave_session(false)
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_server(port, max_clients)
	if result != OK:
		var message := "تعذر فتح منفذ الاستضافة %d: %s" % [port, error_string(result)]
		status_changed.emit(message)
		return result

	multiplayer.multiplayer_peer = peer
	session_mode = "host"
	session_port = port
	_client_connected = false
	_ready_peers.clear()
	status_changed.emit("تستضيف جلسة تجريبية على المنفذ %d." % port)
	return OK


func start_client(address: String, port: int = DEFAULT_PORT) -> int:
	var clean_address := address.strip_edges()
	if clean_address.is_empty() or port < 1 or port > 65535:
		return ERR_INVALID_PARAMETER

	leave_session(false)
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_client(clean_address, port)
	if result != OK:
		var message := "تعذر بدء الاتصال: %s" % error_string(result)
		status_changed.emit(message)
		return result

	multiplayer.multiplayer_peer = peer
	session_mode = "client"
	session_port = port
	_client_connected = false
	_ready_peers.clear()
	_connection_generation += 1
	status_changed.emit("جارٍ الاتصال بـ %s:%d ..." % [clean_address, port])
	var timer := get_tree().create_timer(CONNECTION_TIMEOUT_SECONDS)
	timer.timeout.connect(_on_connection_timeout.bind(_connection_generation))
	return OK


func leave_session(notify: bool = true) -> void:
	_connection_generation += 1
	_client_connected = false
	_ready_peers.clear()
	var old_mode := session_mode
	session_mode = "offline"
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if notify and old_mode != "offline":
		status_changed.emit("تم إنهاء الجلسة.")


func is_session_active() -> bool:
	return session_mode != "offline"


func is_connected_to_server() -> bool:
	return session_mode == "host" or (session_mode == "client" and _client_connected)


func get_ready_peer_ids() -> Array[int]:
	var result: Array[int] = []
	for key in _ready_peers.keys():
		result.append(int(key))
	return result


# Called only after the network arena and its MultiplayerSpawner are ready.
func notify_arena_ready() -> void:
	if not is_session_active():
		return
	if multiplayer.is_server():
		if not _ready_peers.has(1):
			_ready_peers[1] = true
			peer_arena_ready.emit(1)
	else:
		rpc_id(1, "_rpc_notify_arena_ready")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_notify_arena_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 1 or not multiplayer.get_peers().has(sender_id):
		return
	if _ready_peers.has(sender_id):
		return
	_ready_peers[sender_id] = true
	peer_arena_ready.emit(sender_id)


func _on_connected_to_server() -> void:
	if session_mode != "client":
		return
	_client_connected = true
	_connection_generation += 1
	status_changed.emit("تم الاتصال بالخادم.")
	session_connected.emit()


func _on_connection_failed() -> void:
	if session_mode != "client":
		return
	_connection_generation += 1
	leave_session(false)
	var reason := "فشل الاتصال بالخادم. تحقق من عنوان IP والمنفذ وإعدادات الشبكة."
	status_changed.emit(reason)
	connection_failed.emit(reason)


func _on_server_disconnected() -> void:
	if session_mode != "client":
		return
	_connection_generation += 1
	leave_session(false)
	var reason := "انقطع اتصال الخادم."
	status_changed.emit(reason)
	session_ended.emit(reason)


func _on_peer_connected(peer_id: int) -> void:
	if session_mode == "host":
		status_changed.emit("اتصل لاعب جديد: %d." % peer_id)
	peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	_ready_peers.erase(peer_id)
	status_changed.emit("غادر اللاعب %d الجلسة." % peer_id)
	peer_left.emit(peer_id)


func _on_connection_timeout(generation: int) -> void:
	if generation != _connection_generation:
		return
	if session_mode != "client" or _client_connected:
		return
	leave_session(false)
	var reason := "انتهت مهلة الاتصال بعد 12 ثانية."
	status_changed.emit(reason)
	connection_failed.emit(reason)
