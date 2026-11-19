class_name Powder
extends MultiMeshInstance3D
## Pooled powder puffs drawn with one MultiMesh: carve spray, landing bursts,
## the hand plant at the summit, wipeouts and the wind-blown powder.

@export var max_particles := 700
@export var gravity := 6.0
@export var drag := 1.6

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _life := PackedFloat32Array()
var _max_life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _col := PackedColorArray()
var _next := 0


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = max_particles
	multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/particle.gdshader")
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 10000.0
	top_level = true
	for arr in [_pos, _vel]:
		arr.resize(max_particles)
	for arr in [_life, _max_life, _size]:
		arr.resize(max_particles)
	_col.resize(max_particles)
	clear()


func clear() -> void:
	for i in max_particles:
		_life[i] = 0.0
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3(0, -9999, 0)))


func emit(pos: Vector3, vel: Vector3, size: float, life: float, col := Color(1, 1, 1, 0.85)) -> void:
	var i := _next
	_next = (_next + 1) % max_particles
	_pos[i] = pos
	_vel[i] = vel
	_life[i] = life
	_max_life[i] = life
	_size[i] = size
	_col[i] = col


func burst(pos: Vector3, normal: Vector3, count: int, speed: float, size: float, col := Color(1, 1, 1, 0.9)) -> void:
	for k in count:
		var dir := (normal * randf_range(0.4, 1.0) + Vector3(randf_range(-1, 1), randf_range(0, 0.6), randf_range(-1, 1))).normalized()
		emit(pos + dir * 0.2, dir * speed * randf_range(0.4, 1.0), size * randf_range(0.6, 1.3), randf_range(0.5, 1.1), col)


func _process(dt: float) -> void:
	var mm := multimesh
	var damp := exp(-drag * dt)
	for i in max_particles:
		if _life[i] <= 0.0:
			continue
		_life[i] -= dt
		if _life[i] <= 0.0:
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3(0, -9999, 0)))
			continue
		_vel[i] = _vel[i] * damp + Vector3(0, -gravity * dt, 0)
		_pos[i] += _vel[i] * dt
		var t := 1.0 - _life[i] / _max_life[i]
		var s := _size[i] * (0.6 + t * 1.2)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), _pos[i]))
		var c := _col[i]
		c.a *= (1.0 - t) * minf(1.0, t * 8.0 + 0.3)
		mm.set_instance_color(i, c)
