class_name Encounters
extends Node3D
## Deep-trip set pieces, each with its own identity:
##  * tunnel - the slope's sides curl up into a moving rainbow tube whose
##             exit frames the real trail.
##  * garden - self-similar branching flowers grow out of the mountainside.
##  * peaks  - the horizon peaks split apart and recombine (ground stays solid).
## All are decorative: glowing, translucent, never collidable, kept to the
## sides of and above the rider's line.

@export var tunnel_length := 150.0
@export var tunnel_radius := 13.0
@export var tunnel_ring_spacing := 3.2
@export var garden_count := 14
@export var peaks_duration := 16.0

var peak_split := 0.0
var _kind := ""
var _t := 0.0
var _rider: Rider
var _nodes: Array[Node3D] = []
var _mat_tunnel: ShaderMaterial
var _mat_flower: ShaderMaterial
var _flower_meshes: Array[ArrayMesh] = []
var _path_origin := Vector3.ZERO
var _path_dir := Vector3.FORWARD


func _ready() -> void:
	var sh := preload("res://shaders/hallucination.gdshader")
	_mat_tunnel = ShaderMaterial.new()
	_mat_tunnel.shader = sh
	_mat_tunnel.set_shader_parameter("style", 0)
	_mat_tunnel.set_shader_parameter("alpha", 0.55)
	_mat_tunnel.set_shader_parameter("fade_near", 5.0)
	_mat_flower = ShaderMaterial.new()
	_mat_flower.shader = sh
	_mat_flower.set_shader_parameter("style", 1)
	_mat_flower.set_shader_parameter("alpha", 0.75)
	_mat_flower.set_shader_parameter("fade_near", 8.0)
	for i in 3:
		_flower_meshes.append(MeshFactory.fractal_flower(55 + i))


func busy() -> bool:
	return _kind != ""


func clear_all() -> void:
	for n in _nodes:
		n.queue_free()
	_nodes.clear()
	_kind = ""
	peak_split = 0.0


func start(kind: String, rider: Rider, _intensity: float) -> void:
	clear_all()
	_kind = kind
	_t = 0.0
	_rider = rider
	_path_dir = Vector3(rider.cam_heading.x, 0, rider.cam_heading.z).normalized()
	_path_origin = rider.global_position
	match kind:
		"tunnel":
			_build_tunnel()
		"garden":
			_build_garden()
	print("[trip] encounter: ", kind)


func _process(dt: float) -> void:
	if _kind == "":
		return
	_t += dt
	match _kind:
		"tunnel":
			_update_tunnel()
		"garden":
			_update_garden()
		"peaks":
			var u := _t / peaks_duration
			peak_split = sin(clampf(u, 0.0, 1.0) * PI) * (0.75 + 0.25 * sin(_t * 0.9))
			if u >= 1.0:
				clear_all()


# ---------------------------------------------------------------- tunnel

func _build_tunnel() -> void:
	var start := 45.0
	var n := int(tunnel_length / tunnel_ring_spacing)
	var side := _path_dir.cross(Vector3.UP).normalized()
	for i in n:
		var d := start + i * tunnel_ring_spacing
		var c := _path_origin + _path_dir * d
		c.y = Mountain.height(c.x, c.z)
		var ring := MeshInstance3D.new()
		ring.mesh = _arch_mesh(tunnel_radius * (1.0 - 0.25 * smoothstep(n - 8, n, i)), 0.35 if i < n - 1 else 1.2, i)
		ring.material_override = _mat_tunnel
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.transform = Transform3D(Basis(side, Vector3.UP, side.cross(Vector3.UP)), c)
		ring.set_meta("d", d)
		ring.set_meta("i", i)
		add_child(ring)
		_nodes.append(ring)


func _arch_mesh(r: float, w: float, idx: int) -> ArrayMesh:
	# Half-ring rising from both sides of the slope and meeting overhead.
	var b := MeshBuilder.new()
	var seg := 28
	for k in seg:
		var a0 := PI * k / seg
		var a1 := PI * (k + 1) / seg
		var p0 := Vector3(cos(a0) * r, sin(a0) * r * 0.8, 0)
		var p1 := Vector3(cos(a1) * r, sin(a1) * r * 0.8, 0)
		var n0 := p0.normalized()
		var n1 := p1.normalized()
		var u := float(k) / seg
		b.quad(p0 - n0 * w, p1 - n1 * w, p1 + n1 * w, p0 + n0 * w, Color.WHITE, Vector2(u * 3.0 + idx * 0.21, idx * 0.15))
	return b.commit()


func _update_tunnel() -> void:
	var rp := _rider.global_position
	var along := (rp - _path_origin).dot(_path_dir)
	var done := true
	for ring in _nodes:
		var d: float = ring.get_meta("d")
		var rel := d - along
		# Walls curl up as you approach, then unfurl behind you.
		var curl := smoothstep(110.0, 35.0, rel) * smoothstep(-25.0, 0.0, rel)
		ring.scale = Vector3(1.0, maxf(curl, 0.001), 1.0)
		ring.rotation_degrees.z = sin(TripDirector.now * 0.6 + d * 0.05) * 10.0 * curl
		if rel > -25.0:
			done = false
	if done or _t > 30.0:
		clear_all()


# ---------------------------------------------------------------- garden

func _build_garden() -> void:
	var side := _path_dir.cross(Vector3.UP).normalized()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in garden_count:
		var d := 50.0 + i * 13.0
		var s := (1.0 if i % 2 == 0 else -1.0) * rng.randf_range(15.0, 34.0)
		var p := _path_origin + _path_dir * d + side * s
		p.y = Mountain.height(p.x, p.z) - 0.3
		var f := MeshInstance3D.new()
		f.mesh = _flower_meshes[i % _flower_meshes.size()]
		f.material_override = _mat_flower
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.position = p
		f.rotation.y = rng.randf() * TAU
		f.set_meta("d", d)
		f.set_meta("s", rng.randf_range(1.0, 1.8))
		f.scale = Vector3.ONE * 0.001
		add_child(f)
		_nodes.append(f)


func _update_garden() -> void:
	var along := (_rider.global_position - _path_origin).dot(_path_dir)
	var done := true
	for f in _nodes:
		var rel: float = f.get_meta("d") - along
		var grow := smoothstep(95.0, 30.0, rel) * smoothstep(-35.0, -5.0, rel)
		f.scale = Vector3.ONE * maxf(grow * float(f.get_meta("s")), 0.001)
		f.rotation.y += 0.004 * (1.0 + grow)
		if rel > -35.0:
			done = false
	if done or _t > 32.0:
		clear_all()
