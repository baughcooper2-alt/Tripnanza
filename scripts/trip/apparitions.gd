class_name Apparitions
extends Node3D
## "See random things": decorative hallucinations that appear well off to the
## side of your line, swell into view, then dissolve before you reach them.
## They never collide and never sit on the line you're riding.
##   mushrooms - a grove of giant glowing mushrooms
##   eye       - a floating eye that turns to watch you
##   ghost     - a huge rainbow ghost of the rider, posed on a ridge
##   flower    - a self-similar fractal flower
##   halo      - a stack of slowly turning rainbow rings

@export var start_intensity := 0.22
@export var interval := Vector2(5.0, 11.0)      ## seconds between apparitions (shrinks at peak)
@export var max_alive := 4
@export var spawn_distance := Vector2(75.0, 120.0)
@export var side_offset := Vector2(18.0, 45.0)
@export var dissolve_distance := 32.0

var rider: Rider
var trip: TripDirector
var _timer := 3.0
var _items: Array = []
var _shader: Shader = preload("res://shaders/hallucination.gdshader")
var _mushroom_mesh: ArrayMesh
var _flower_mesh: ArrayMesh
const KINDS := ["mushrooms", "eye", "ghost", "flower", "halo"]
var _kind_index := 0


func _ready() -> void:
	_mushroom_mesh = MeshFactory.mushroom()
	_flower_mesh = MeshFactory.fractal_flower(91)


func clear_all() -> void:
	for it in _items:
		if is_instance_valid(it.node):
			it.node.queue_free()
	_items.clear()
	_timer = 3.0
	_kind_index = randi() % KINDS.size()


func _mat(style: int, alpha: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("style", style)
	m.set_shader_parameter("alpha", alpha)
	m.set_shader_parameter("fade_near", 10.0)
	m.set_shader_parameter("grow", 0.0)
	m.set_shader_parameter("hue_offset", randf())
	return m


func _process(dt: float) -> void:
	if rider == null or trip == null:
		return
	var I := trip.intensity * Settings.trip_strength
	_update_items(dt)
	if not trip.active or not rider.is_controllable() or I < start_intensity:
		return
	_timer -= dt
	if _timer > 0.0 or _items.size() >= max_alive:
		return
	_timer = randf_range(interval.x, interval.y) * lerpf(1.0, 0.55, smoothstep(0.5, 1.0, I))
	_spawn(KINDS[_kind_index % KINDS.size()])
	_kind_index += 1 + (randi() % 2)


func _spawn(kind: String) -> void:
	var h := Vector3(rider.cam_heading.x, 0, rider.cam_heading.z).normalized()
	var side := h.cross(Vector3.UP).normalized() * (1.0 if randf() < 0.5 else -1.0)
	var p := rider.global_position + h * randf_range(spawn_distance.x, spawn_distance.y) \
		+ side * randf_range(side_offset.x, side_offset.y)
	p.y = Mountain.height(p.x, p.z)
	var root := Node3D.new()
	add_child(root)
	root.global_position = p
	var mats: Array = []
	match kind:
		"mushrooms":
			var m := _mat(3, 0.8)
			mats.append(m)
			for i in randi_range(3, 6):
				var mi := MeshInstance3D.new()
				mi.mesh = _mushroom_mesh
				mi.material_override = m
				var s := randf_range(60.0, 150.0)
				mi.scale = Vector3(s, s * randf_range(0.9, 1.4), s)
				mi.position = Vector3(randf_range(-7, 7), -0.3, randf_range(-7, 7))
				mi.rotation.y = randf() * TAU
				_no_shadow(mi)
				root.add_child(mi)
		"eye":
			var m := _mat(4, 0.92)
			mats.append(m)
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = randf_range(3.5, 6.5)
			sm.height = sm.radius * 2.0
			sm.radial_segments = 24
			sm.rings = 12
			mi.mesh = sm
			mi.material_override = m
			mi.position.y = sm.radius + randf_range(4.0, 10.0)
			_no_shadow(mi)
			root.add_child(mi)
		"ghost":
			var m := _mat(3, 0.6)
			mats.append(m)
			var g := RiderModel.new()
			root.add_child(g)
			g.scale = Vector3.ONE * randf_range(3.5, 6.0)
			var poses := ["sit", "pop", "air", "plant", "tuck"]
			var pose: String = poses[randi() % poses.size()]
			for k in g.weights:
				g.weights[k] = 1.0 if k == pose else 0.0
			g.snap()
			for c in g.get_children():
				if c is MeshInstance3D:
					c.material_override = m
					_no_shadow(c)
			# Face the rider.
			var to_r := rider.global_position - p
			g.rotation.y = atan2(to_r.x, to_r.z) - PI * 0.5
		"flower":
			var m := _mat(1, 0.75)
			mats.append(m)
			var mi := MeshInstance3D.new()
			mi.mesh = _flower_mesh
			mi.material_override = m
			mi.scale = Vector3.ONE * randf_range(1.2, 2.2)
			_no_shadow(mi)
			root.add_child(mi)
		"halo":
			var m := _mat(2, 0.8)
			mats.append(m)
			for i in 5:
				var t := TorusMesh.new()
				t.inner_radius = 0.9
				t.outer_radius = 1.0
				t.rings = 48
				t.ring_segments = 6
				var mi := MeshInstance3D.new()
				mi.mesh = t
				mi.material_override = m
				var s := 4.0 + i * 2.2
				mi.scale = Vector3(s, s, s)
				mi.position.y = 9.0
				mi.rotation = Vector3(PI * 0.5, 0, i * 0.4)
				_no_shadow(mi)
				root.add_child(mi)
	_items.append({node = root, mats = mats, kind = kind, age = 0.0})


func _no_shadow(gi: GeometryInstance3D) -> void:
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _update_items(dt: float) -> void:
	var rp := rider.global_position
	var h := Vector3(rider.cam_heading.x, 0, rider.cam_heading.z).normalized()
	for it in _items.duplicate():
		var n: Node3D = it.node
		if not is_instance_valid(n):
			_items.erase(it)
			continue
		it.age += dt
		var rel := n.global_position - rp
		var d := Vector2(rel.x, rel.z).length()
		var ahead := rel.dot(h)
		# Swell in from the distance, dissolve as you get close.
		var grow := smoothstep(0.0, 2.5, it.age) * smoothstep(dissolve_distance, dissolve_distance + 25.0, d)
		for m in it.mats:
			m.set_shader_parameter("grow", grow)
		match it.kind:
			"eye":
				var c: Node3D = n.get_child(0)
				c.position.y += sin(TripDirector.now * 0.8) * dt * 0.6
			"halo":
				for i in n.get_child_count():
					n.get_child(i).rotate_object_local(Vector3.UP, dt * (0.3 + i * 0.12))
			"flower", "mushrooms":
				n.scale = Vector3.ONE * (0.6 + 0.4 * grow)
		if ahead < -15.0 or it.age > 30.0 or (d < dissolve_distance and grow < 0.01):
			n.queue_free()
			_items.erase(it)
