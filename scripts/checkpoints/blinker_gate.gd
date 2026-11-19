class_name BlinkerGate
extends Node3D
## One BLINKER gate. Styles evolve with each gate:
##   0 Arch       - thin luminous arch; crossing releases round rings.
##   1 Lotus      - pointed arch; crossing releases spinning hexagon rings.
##   2 Halo       - full circle; crossing releases triangles + rings in rainbow.
##   3 Prism      - squared frame; crossing releases a dense rainbow ring tunnel.
## Segments light up from the snow toward the crown as the rider approaches.

var style := 0
var index := 1
var width := 12.0
var _mat: ShaderMaterial
var _frame: MeshInstance3D
var _rings: Array = []
var _crossed := false
var _t := 0.0
var _speed := 20.0
var _dir := Vector3.FORWARD
var _obstacles: Array = []

const RING_SIDES := [40, 6, 3, 4]


func build() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/gate.gdshader")
	_mat.set_shader_parameter("segments", 9.0 + style * 2.0)
	_mat.set_shader_parameter("rainbow", clampf(style * 0.35, 0.0, 1.0))
	_mat.set_shader_parameter("base_color", Vector3(0.35, 0.95, 1.0))
	_frame = MeshInstance3D.new()
	_frame.mesh = _frame_mesh()
	_frame.material_override = _mat
	_frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_frame)
	# Two flanking trees (solid, collidable) and small marker lights.
	var tm := MeshFactory.tree(index % 3)
	var tmat := ShaderMaterial.new()
	tmat.shader = preload("res://shaders/prop.gdshader")
	tmat.set_shader_parameter("rim_base", 0.3)
	for s in [-1.0, 1.0]:
		var p := global_position + Vector3(s * (width * 0.5 + 1.2), 0, 0)
		p.y = Mountain.terrain(p.x, p.z).w
		var t := MeshInstance3D.new()
		t.mesh = tm
		t.material_override = tmat
		add_child(t)
		t.global_position = p - Vector3(0, 0.15, 0)
		t.scale = Vector3.ONE * 1.05
		_obstacles.append(Mountain.add_external_obstacle(p, 0.75, 9.0))


func _frame_mesh() -> ArrayMesh:
	var b := MeshBuilder.new()
	var pts: Array[Vector3] = []
	var half := width * 0.5
	var n := 40
	for k in n + 1:
		var u := float(k) / n
		var p := Vector3.ZERO
		match style:
			0:  # round arch
				var a := PI * u
				p = Vector3(-cos(a) * half, sin(a) * half * 1.05, 0)
			1:  # pointed lotus arch
				var a := PI * 0.5 * (u * 2.0 if u < 0.5 else (2.0 - u * 2.0))
				var x := (1.0 - sin(a)) * half * (-1.0 if u < 0.5 else 1.0)
				p = Vector3(x, (1.0 - cos(a)) * half * 1.35 + (0.0 if u < 0.5 else 0.0), 0)
				p.y = sin(a) * half * 1.3 + pow(sin(a), 6.0) * 2.0
			2:  # full halo standing on the snow
				var a := -PI * 0.5 + TAU * u
				p = Vector3(cos(a) * half * 0.85, half * 0.85 + sin(a) * half * 0.85, 0)
			3:  # prism frame
				var per := u * 3.0
				if per < 1.0:
					p = Vector3(-half, per * half * 1.4, 0)
				elif per < 2.0:
					p = Vector3(-half + (per - 1.0) * width, half * 1.4, 0)
				else:
					p = Vector3(half, (3.0 - per) * half * 1.4, 0)
		pts.append(p)
	var thick := 0.18
	for k in n:
		var a := pts[k]
		var c := pts[k + 1]
		var t := (c - a).normalized()
		var side := t.cross(Vector3.BACK).normalized() * thick
		var depth := Vector3(0, 0, thick)
		# "Base to crown" coordinate: 0 at both feet, 1 at the top.
		var u0 := 1.0 - absf(float(k) / n * 2.0 - 1.0)
		var u1 := 1.0 - absf(float(k + 1) / n * 2.0 - 1.0)
		var uv := Vector2(minf(u0, u1) + 0.001, 0)
		b.quad(a - side, c - side, c + side, a + side, Color.WHITE, uv)
		b.quad(a - depth, c - depth, c + depth, a + depth, Color.WHITE, uv)
	return b.commit()


## Called each frame before crossing: light segments from the snow upward.
func approach(rider_pos: Vector3) -> void:
	var d := global_position.z - rider_pos.z
	var lit := clampf(1.0 - (d - 12.0) / 95.0, 0.0, 1.0)
	_mat.set_shader_parameter("lit", lit)
	_mat.set_shader_parameter("pulse", 0.25 * smoothstep(25.0, 5.0, d))


func cross(rider: Rider) -> void:
	_crossed = true
	_t = 0.0
	_speed = rider.speed
	_dir = Vector3(rider.cam_heading.x, 0, rider.cam_heading.z).normalized()
	_mat.set_shader_parameter("lit", 1.0)
	var rmat := ShaderMaterial.new()
	rmat.shader = preload("res://shaders/hallucination.gdshader")
	rmat.set_shader_parameter("style", 2)
	rmat.set_shader_parameter("alpha", 0.9)
	rmat.set_shader_parameter("fade_near", 2.0)
	var count := 5 + style * 2
	var basis := Basis(_dir.cross(Vector3.UP).normalized(), Vector3.UP, -_dir).orthonormalized()
	for i in count:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.92
		tm.outer_radius = 1.0
		tm.rings = RING_SIDES[style]
		tm.ring_segments = 4
		var m := MeshInstance3D.new()
		m.mesh = tm
		var mat := rmat.duplicate()
		mat.set_shader_parameter("hue_offset", float(i) / count)
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		m.global_transform = Transform3D(basis * Basis(Vector3.RIGHT, PI * 0.5), rider.global_position + Vector3(0, 2.5, 0))
		_rings.append({node = m, delay = i * 0.12, mat = mat})


func _process(dt: float) -> void:
	if not _crossed:
		return
	_t += dt
	_mat.set_shader_parameter("fade", clampf(1.0 - _t / 1.2, 0.0, 1.0))
	_frame.scale = Vector3.ONE * (1.0 + _t * 1.5)
	for r in _rings:
		var t: float = _t - r.delay
		var node: MeshInstance3D = r.node
		if t < 0.0:
			node.visible = false
			continue
		node.visible = true
		# Rings race downhill ahead of the rider while expanding.
		var travel := (_speed + 26.0) * t
		var p := global_position + _dir * (travel + 10.0)
		p.y = Mountain.height(p.x, p.z) + 3.0 + t * 1.0
		node.global_position = p
		var s := 3.0 + t * 3.5
		node.scale = Vector3(s, s, s)
		node.rotate_object_local(Vector3.UP, dt * (1.0 + style) * 0.6)
		r.mat.set_shader_parameter("alpha", 0.9 * clampf(1.0 - t / 2.4, 0.0, 1.0))
	if _t > 4.0:
		_crossed = false
		_frame.visible = false
		for r in _rings:
			r.node.queue_free()
		_rings.clear()


func _exit_tree() -> void:
	for o in _obstacles:
		o.alive = false
