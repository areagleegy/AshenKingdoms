extends SceneTree

const AVATAR_SCENE: PackedScene = preload("res://scenes/network/NetworkAvatar.tscn")

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var avatar := AVATAR_SCENE.instantiate()
	root.add_child(avatar)
	await process_frame
	avatar.call("configure_owner", 2)

	# Freeze the refill timestamp during the burst so this assertion is deterministic.
	avatar.set("_rpc_input_tokens", 60.0)
	var fixed_now := Time.get_ticks_msec()
	avatar.set("_rpc_input_last_refill_msec", fixed_now)
	var accepted := 0
	for _i in range(60):
		avatar.set("_rpc_input_last_refill_msec", fixed_now)
		if bool(avatar.call("_consume_rpc_input_token")):
			accepted += 1
	_check(accepted == 60, "token bucket accepts the configured burst of 60 inputs")

	avatar.set("_rpc_input_last_refill_msec", fixed_now)
	_check(not bool(avatar.call("_consume_rpc_input_token")), "token bucket rejects input after burst exhaustion")

	# Simulate one second of elapsed time; the bucket should refill at 30 tokens/sec.
	avatar.set("_rpc_input_tokens", 0.0)
	avatar.set("_rpc_input_last_refill_msec", Time.get_ticks_msec() - 1000)
	var accepted_after_refill := bool(avatar.call("_consume_rpc_input_token"))
	var tokens_after_refill: float = float(avatar.get("_rpc_input_tokens"))
	_check(accepted_after_refill, "token bucket accepts input after refill")
	_check(tokens_after_refill >= 28.0 and tokens_after_refill <= 30.0, "one second refills approximately 30 tokens")

	avatar.queue_free()
	await process_frame
	print("[network-rpc-rate-limit] failures: %d" % failures)
	quit(1 if failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] %s" % description)
	else:
		failures += 1
		push_error("[FAIL] %s" % description)
