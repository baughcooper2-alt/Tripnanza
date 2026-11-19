class_name Backdrop
extends Node3D
## A ring of huge faceted peaks on the horizon. It follows the rider so the
## skyline always reads as distant, and each peak has a ghost twin used by the
## "peaks split" encounter.

@export var peak_count := 16
@export var ring_radius := Vector2(3000.0, 4200.0)
@export var peak_height := Vector2(560.0, 1000.0)
@export var sink_below_rider := 640.0
@export var shader: Shader = preload("res://shaders/backdrop.gdshader")

var _solid: ShaderMaterial
var _ghost: ShaderMaterial


func _ready() -> void:
	_solid = ShaderMaterial.new()
	_solid.shader = shader
	_ghost = ShaderMaterial.new()
	_ghost.shader = shader
	_ghost.set_shader_parameter("ghost", 1.0)
	_ghost.render_priority = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in peak_count:
		var a := TAU * i / peak_count + rng.randf_range(-0.12, 0.12)
		var rad := rng.randf_range(ring_radius.x, ring_radius.y)
		var h := rng.randf_range(peak_height.x, peak_height.y)
		# Taller peaks downhill, where the camera looks.
		h *= 0.7 + 0.5 * maxf(0.0, sin(a))
		var mesh := MeshFactory.peak(1000 + i)
		var xf := Transform3D(Basis().scaled(Vector3(h * 0.9, h, h * 0.8)).rotated(Vector3.UP, rng.randf() * TAU),
			Vector3(cos(a) * rad, 0, sin(a) * rad))
		for ghost in [false, true]:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = _ghost if ghost else _solid
			mi.transform = xf
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.extra_cull_margin = 2000.0
			add_child(mi)


func follow(pos: Vector3) -> void:
	global_position = Vector3(pos.x, pos.y - sink_below_rider, pos.z)
