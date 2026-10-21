extends Node3D

const EFFECT_DURATION: float = 0.24
const SPARK_COUNT: int = 6


func _ready() -> void:
	var glow := MeshInstance3D.new()
	glow.name = "ImpactGlow"
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	sphere.radial_segments = 8
	sphere.rings = 4
	glow.mesh = sphere
	glow.material_override = _make_material(Color(1.0, 0.35, 0.08, 0.86), Color(1.0, 0.16, 0.025))
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)

	var sparks: Array[MeshInstance3D] = []
	for index in range(SPARK_COUNT):
		var spark := MeshInstance3D.new()
		spark.name = "ImpactSpark%d" % index
		var shard := BoxMesh.new()
		shard.size = Vector3(0.045, 0.045, 0.24)
		spark.mesh = shard
		var color := Color(1.0, 0.78, 0.29, 0.98) if index % 2 == 0 else Color(0.95, 0.24, 0.075, 0.94)
		spark.material_override = _make_material(color, color)
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var angle := TAU * float(index) / float(SPARK_COUNT)
		var direction := Vector3(cos(angle), 0.22 + 0.18 * sin(angle * 2.0), sin(angle)).normalized()
		spark.position = direction * 0.08
		spark.look_at(global_position + direction, Vector3.UP)
		add_child(spark)
		sparks.append(spark)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(glow, "scale", Vector3.ONE * 2.7, EFFECT_DURATION)
	tween.tween_property(glow, "transparency", 1.0, EFFECT_DURATION)

	for index in range(sparks.size()):
		var spark := sparks[index]
		var angle := TAU * float(index) / float(SPARK_COUNT)
		var direction := Vector3(cos(angle), 0.25 + 0.2 * sin(angle * 2.0), sin(angle)).normalized()
		var target_position := spark.position + direction * 0.30 + Vector3.UP * 0.08
		tween.tween_property(spark, "position", target_position, EFFECT_DURATION)
		tween.tween_property(spark, "scale", Vector3(0.28, 0.28, 0.60), EFFECT_DURATION)
		tween.tween_property(spark, "transparency", 1.0, EFFECT_DURATION)

	tween.finished.connect(queue_free)


func _make_material(color: Color, emission_color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = emission_color
	material.emission_energy_multiplier = 1.8
	material.roughness = 0.8
	return material
