extends RefCounted
class_name BattleRoyaleRules

## Deterministic match rules shared by gameplay and headless tests.
## The 100-player figure is a long-term capacity target, not a tested limit.

enum Phase {
	WAITING,
	ACTIVE,
	FINAL_CIRCLE,
	FINISHED,
}

const LONG_TERM_TARGET_PLAYERS: int = 100
const MINIMUM_PLAYERS_TO_START: int = 2

var initial_safe_radius: float = 32.0
var final_safe_radius: float = 5.0
var shrink_duration_seconds: float = 180.0
var storm_damage_per_second: float = 8.0

var phase: Phase = Phase.WAITING
var elapsed_seconds: float = 0.0
var winner_peer_id: int = 0


func try_start(alive_player_count: int) -> bool:
	if phase != Phase.WAITING or alive_player_count < MINIMUM_PLAYERS_TO_START:
		return false
	phase = Phase.ACTIVE
	elapsed_seconds = 0.0
	winner_peer_id = 0
	return true


func advance(delta: float, alive_player_count: int, sole_survivor_peer_id: int = 0) -> void:
	if phase == Phase.WAITING or phase == Phase.FINISHED or delta <= 0.0:
		return
	elapsed_seconds += delta
	if alive_player_count <= 1:
		phase = Phase.FINISHED
		winner_peer_id = sole_survivor_peer_id if alive_player_count == 1 else 0
		return
	if get_safe_radius() <= final_safe_radius + 0.001:
		phase = Phase.FINAL_CIRCLE
	else:
		phase = Phase.ACTIVE


func get_safe_radius() -> float:
	if phase == Phase.WAITING:
		return initial_safe_radius
	var duration := maxf(shrink_duration_seconds, 0.001)
	var progress := clampf(elapsed_seconds / duration, 0.0, 1.0)
	return lerpf(initial_safe_radius, final_safe_radius, progress)


func is_inside_safe_zone(world_position: Vector3, center: Vector3 = Vector3.ZERO) -> bool:
	var offset := Vector2(world_position.x - center.x, world_position.z - center.z)
	return offset.length() <= get_safe_radius()


func get_phase_label() -> String:
	match phase:
		Phase.WAITING:
			return "بانتظار لاعبين"
		Phase.ACTIVE:
			return "المعركة بدأت — المنطقة الآمنة تنكمش"
		Phase.FINAL_CIRCLE:
			return "الدائرة الأخيرة"
		Phase.FINISHED:
			return "انتهت المباراة"
	return "حالة غير معروفة"
