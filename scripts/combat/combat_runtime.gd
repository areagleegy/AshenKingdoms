extends Node
## Deterministic combat timing core. Damage application and hit detection remain caller-owned.

signal phase_changed(phase: StringName)
signal hit_window_opened(weapon_id: StringName)
signal attack_finished(weapon_id: StringName)
signal attack_rejected(reason: StringName)

const WeaponDefinitionScript: Script = preload("res://scripts/combat/weapon_definition.gd")
const PHASE_READY: StringName = &"ready"
const PHASE_WINDUP: StringName = &"windup"
const PHASE_ACTIVE: StringName = &"active"
const PHASE_RECOVERY: StringName = &"recovery"
const PHASE_COOLDOWN: StringName = &"cooldown"

var weapon: Resource
var phase: StringName = PHASE_READY
var stamina: float = 100.0
var stamina_max: float = 100.0
var ammunition: int = 0
var charges: int = 0
var _phase_elapsed: float = 0.0
var _cooldown_remaining: float = 0.0
var _hit_emitted: bool = false


func configure(definition: Resource, initial_stamina: float = 100.0) -> bool:
	if definition == null or not definition is WeaponDefinitionScript:
		attack_rejected.emit(&"invalid_definition")
		return false
	if not bool(definition.call("is_valid_definition")):
		attack_rejected.emit(&"invalid_definition")
		return false
	weapon = definition
	stamina_max = maxf(0.0, initial_stamina)
	stamina = stamina_max
	ammunition = int(weapon.get("ammo_capacity"))
	charges = int(weapon.get("charges"))
	_cooldown_remaining = 0.0
	_phase_elapsed = 0.0
	_set_phase(PHASE_READY)
	return true


func restore_stamina(amount: float) -> void:
	if not is_finite(amount) or amount <= 0.0:
		return
	stamina = minf(stamina_max, stamina + amount)


func can_start_attack() -> bool:
	if weapon == null or not is_instance_valid(weapon):
		return false
	if phase != PHASE_READY or _cooldown_remaining > 0.0:
		return false
	if stamina < float(weapon.get("stamina_cost")):
		return false
	var category: StringName = weapon.get("category")
	if category == &"limited" and ammunition <= 0 and charges <= 0:
		return false
	if category == &"charged" and charges <= 0:
		return false
	return true


func start_attack() -> bool:
	if not can_start_attack():
		attack_rejected.emit(&"not_ready_or_insufficient_resources")
		return false
	stamina = maxf(0.0, stamina - float(weapon.get("stamina_cost")))
	if StringName(weapon.get("category")) == &"limited":
		if ammunition > 0:
			ammunition -= 1
		elif charges > 0:
			charges -= 1
	if StringName(weapon.get("category")) == &"charged":
		charges -= 1
	_phase_elapsed = 0.0
	_hit_emitted = false
	_set_phase(PHASE_WINDUP)
	return true


func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or weapon == null:
		return
	if phase == PHASE_READY:
		_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
		return
	var remaining := delta
	var guard := 0
	while remaining > 0.0 and phase != PHASE_READY and guard < 8:
		guard += 1
		var duration := _duration_for_phase(phase)
		var phase_left := maxf(0.0, duration - _phase_elapsed)
		var consumed := minf(remaining, phase_left)
		_phase_elapsed += consumed
		remaining -= consumed
		if _phase_elapsed + 0.000001 < duration:
			break
		_transition_phase()


func _duration_for_phase(current: StringName) -> float:
	match current:
		PHASE_WINDUP:
			var windup := maxf(0.0, float(weapon.get("windup_seconds")))
			if StringName(weapon.get("category")) == &"charged":
				windup = maxf(windup, float(weapon.get("charge_seconds")))
			return windup
		PHASE_ACTIVE:
			return maxf(0.001, float(weapon.get("active_seconds")))
		PHASE_RECOVERY:
			return maxf(0.0, float(weapon.get("recovery_seconds")))
		PHASE_COOLDOWN:
			return maxf(0.0, _cooldown_remaining)
		_:
			return 0.0


func _transition_phase() -> void:
	_phase_elapsed = 0.0
	match phase:
		PHASE_WINDUP:
			_set_phase(PHASE_ACTIVE)
			if not _hit_emitted:
				_hit_emitted = true
				hit_window_opened.emit(StringName(weapon.get("weapon_id")))
		PHASE_ACTIVE:
			_set_phase(PHASE_RECOVERY)
		PHASE_RECOVERY:
			_cooldown_remaining = maxf(0.0, float(weapon.get("cooldown_seconds")))
			if _cooldown_remaining > 0.0:
				_set_phase(PHASE_COOLDOWN)
			else:
				_finish_attack()
		PHASE_COOLDOWN:
			_cooldown_remaining = 0.0
			_finish_attack()


func _finish_attack() -> void:
	var finished_id: StringName = StringName(weapon.get("weapon_id"))
	_set_phase(PHASE_READY)
	attack_finished.emit(finished_id)


func _set_phase(next_phase: StringName) -> void:
	if phase == next_phase:
		return
	phase = next_phase
	phase_changed.emit(phase)
