class_name RiderModel
extends Node3D
## Procedural low-poly snowboarder. Local frame: +X = board nose, +Y = up,
## +Z = the way the rider faces (toe edge). Poses are dictionaries of joint
## values blended by weight every frame; legs use two-bone IK so the boots stay
## strapped to the board whatever the body does.

@export var jacket_color := Color(1.0, 0.36, 0.08)
@export var pants_color := Color(0.13, 0.17, 0.33)
@export var helmet_color := Color(0.1, 0.78, 0.72)
@export var board_color := Color(0.93, 0.18, 0.45)
@export var glove_color := Color(0.12, 0.12, 0.14)
@export var pose_smoothing := 14.0
@export var rider_scale := 1.3

const THIGH := 0.46
const SHIN := 0.45

# Absolute poses. Angles in degrees. Arms: Euler (x = toward heel/back,
# z = toward nose for the lead arm) in torso space; elbow bend in degrees.
const RIDE := {hip_x = 0.0, hip_y = 0.86, hip_z = 0.02, bend = 12.0, twist = 25.0, side = 0.0,
	head_pitch = 5.0, head_yaw = 50.0, ls_x = -15.0, ls_z = 50.0, le = 25.0,
	rs_x = -10.0, rs_z = -45.0, re = 20.0, edge = 0.0, pole_up = 0.15}
const POSES := {
	toe = {hip_y = 0.76, hip_z = 0.12, bend = 22.0, edge = 30.0, ls_x = -40.0, rs_x = -30.0, ls_z = 35.0},
	heel = {hip_y = 0.68, hip_z = -0.16, bend = 32.0, edge = -30.0, ls_x = -55.0, rs_x = -50.0, ls_z = 30.0, rs_z = -30.0, head_pitch = 0.0},
	crouch = {hip_y = 0.6, bend = 38.0, ls_x = 25.0, ls_z = 25.0, rs_x = 30.0, rs_z = -20.0, le = 50.0, re = 50.0, pole_up = 0.3},
	pop = {hip_y = 0.93, bend = 2.0, ls_x = -50.0, ls_z = 95.0, rs_x = -45.0, rs_z = -95.0, le = 15.0, re = 15.0},
	tuck = {hip_y = 0.46, hip_z = 0.06, bend = 62.0, head_pitch = 25.0, ls_x = -75.0, ls_z = 5.0, le = 70.0,
		rs_x = -75.0, rs_z = -5.0, re = 70.0, pole_up = 0.7},
	land = {hip_y = 0.55, bend = 36.0, ls_z = 75.0, rs_z = -75.0, le = 20.0, re = 20.0, pole_up = 0.35},
	speed = {hip_y = 0.58, bend = 45.0, twist = 10.0, ls_x = -45.0, ls_z = 15.0, le = 80.0,
		rs_x = -40.0, rs_z = -10.0, re = 80.0, pole_up = 0.35},
	brake = {hip_y = 0.66, hip_z = -0.22, bend = 25.0, edge = -38.0, twist = 0.0, head_yaw = 70.0, ls_z = 70.0, rs_z = -70.0},
	air = {hip_y = 0.8, bend = 18.0, ls_z = 85.0, rs_z = -80.0, ls_x = -20.0, rs_x = -15.0},
	sit = {hip_x = 0.0, hip_y = 0.16, hip_z = -0.44, bend = -16.0, twist = 0.0, head_yaw = 0.0, head_pitch = 8.0,
		ls_x = -30.0, ls_z = 22.0, le = 75.0, rs_x = -30.0, rs_z = -22.0, re = 75.0, pole_up = 1.5, edge = 0.0},
	eat = {rs_x = -150.0, rs_z = -8.0, re = 135.0, head_pitch = -12.0, head_yaw = -12.0},
	plant = {hip_y = 0.34, hip_z = -0.34, side = 14.0, bend = -10.0, rs_x = 55.0, rs_z = -35.0, re = 5.0,
		ls_x = -70.0, ls_z = 30.0, head_yaw = 10.0, pole_up = 1.0},
	grab_r = {hip_y = 0.5, hip_z = 0.04, bend = 50.0, rs_x = -95.0, rs_z = 10.0, re = 15.0, ls_z = 80.0, ls_x = -10.0, pole_up = 0.6},
	grab_l = {hip_y = 0.52, hip_z = -0.04, bend = 34.0, ls_x = 55.0, ls_z = -5.0, le = 10.0, rs_z = -80.0, rs_x = -10.0, pole_up = 0.6},
	crash = {hip_y = 0.22, hip_z = -0.35, bend = -75.0, side = 20.0, ls_x = 0.0, ls_z = 120.0, le = 10.0,
		rs_x = 0.0, rs_z = -120.0, re = 10.0, head_pitch = -20.0, pole_up = 1.0},
}
const ADDITIVE := ["toe", "heel", "crouch", "pop", "tuck", "land", "speed", "brake", "air", "grab_r", "grab_l"]
const OVERRIDE := ["sit", "plant", "eat", "crash"]

## Target weights set by the rider controller every frame.
var weights := {}
var flail := 0.0
var breathe := 1.0
var mushroom_visible := false

var _w := {}
var _pose := RIDE.duplicate()
var _t := 0.0
var _parts := {}
var _mat_cache := {}
var _mushroom: MeshInstance3D
var _prop_shader: Shader = preload("res://shaders/prop.gdshader")
var hand_r_world := Vector3.ZERO
var board_node: MeshInstance3D


func _ready() -> void:
	scale = Vector3.ONE * rider_scale
	board_node = _mi("board", MeshFactory.board(board_color, Color(0.12, 0.12, 0.16)), Color.WHITE)
	var cyl := CylinderMesh.new()
	cyl.radial_segments = 6
	cyl.rings = 1
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	var box := BoxMesh.new()
	var sph := SphereMesh.new()
	sph.radial_segments = 8
	sph.rings = 5
	sph.radius = 1.0
	sph.height = 2.0
	var hemi := SphereMesh.new()
	hemi.radial_segments = 8
	hemi.rings = 3
	hemi.radius = 1.0
	hemi.height = 1.0
	hemi.is_hemisphere = true
	for n in ["thigh_l", "thigh_r", "shin_l", "shin_r"]:
		_mi(n, cyl, pants_color)
	for n in ["boot_l", "boot_r"]:
		_mi(n, box, Color(0.16, 0.14, 0.15))
	_mi("pelvis", box, pants_color)
	_mi("torso", box, jacket_color)
	_mi("hood", box, jacket_color.darkened(0.15))
	_mi("pack", box, Color(0.95, 0.85, 0.2))
	for n in ["uarm_l", "uarm_r", "farm_l", "farm_r"]:
		_mi(n, cyl, jacket_color)
	for n in ["glove_l", "glove_r"]:
		_mi(n, box, glove_color)
	_mi("head", sph, Color(0.85, 0.62, 0.5))
	_mi("helmet", hemi, helmet_color)
	_mi("goggles", box, Color(1.0, 0.72, 0.18))
	_mushroom = MeshInstance3D.new()
	_mushroom.mesh = MeshFactory.mushroom()
	_mushroom.material_override = _mat(Color.WHITE)
	add_child(_mushroom)
	for k in POSES:
		_w[k] = 0.0
		weights[k] = 0.0


func _mat(c: Color) -> ShaderMaterial:
	if _mat_cache.has(c):
		return _mat_cache[c]
	var m := ShaderMaterial.new()
	m.shader = _prop_shader
	m.set_shader_parameter("tint", c)
	m.set_shader_parameter("rim_base", 0.45)
	_mat_cache[c] = m
	return m


func _mi(n: String, mesh: Mesh, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	# Primitive meshes have no vertex colour; tint carries the colour.
	if mesh is ArrayMesh:
		mi.material_override = _mat(Color.WHITE)
	else:
		mi.material_override = _mat(c)
	add_child(mi)
	_parts[n] = mi
	return mi


## Snap all smoothing to the current targets (used on reset).
func snap() -> void:
	for k in weights:
		_w[k] = weights[k]
	_compute_pose()


func _process(dt: float) -> void:
	_t += dt
	var a := 1.0 - exp(-pose_smoothing * dt)
	for k in weights:
		var rate := a
		if k == "pop" or k == "land":
			rate = 1.0 - exp(-30.0 * dt)
		_w[k] = lerpf(_w.get(k, 0.0), weights[k], rate)
	_compute_pose()
	_apply_pose()


func _compute_pose() -> void:
	var p := RIDE.duplicate()
	for k in ADDITIVE:
		var w: float = _w.get(k, 0.0)
		if w < 0.001:
			continue
		var pose: Dictionary = POSES[k]
		for j in pose:
			p[j] += (pose[j] - RIDE[j]) * w
	for k in OVERRIDE:
		var w: float = _w.get(k, 0.0)
		if w < 0.001:
			continue
		var pose: Dictionary = POSES[k]
		for j in pose:
			p[j] = lerpf(p[j], pose[j], w)
	# Breathing and balance flailing.
	var br := sin(_t * 1.7) * breathe
	p.hip_y += br * 0.008
	p.bend += br * 2.0
	p.head_pitch += sin(_t * 1.7 - 0.6) * breathe * 2.0
	if flail > 0.01:
		p.ls_z += sin(_t * 17.0) * 45.0 * flail
		p.rs_z += sin(_t * 15.0 + 1.0) * 45.0 * flail
		p.ls_x += sin(_t * 11.0) * 30.0 * flail
		p.side += sin(_t * 9.0) * 12.0 * flail
	_pose = p


func _apply_pose() -> void:
	var p := _pose
	var edge := deg_to_rad(p.edge)
	var root := Basis(Vector3.RIGHT, edge)   # board tilts onto an edge about its long axis
	board_node.transform = Transform3D(root, Vector3.ZERO)
	var pelvis := root * Vector3(p.hip_x, p.hip_y, p.hip_z)
	var P := root * Basis.from_euler(Vector3(deg_to_rad(p.bend), deg_to_rad(p.twist), deg_to_rad(-p.side)))
	_box("pelvis", pelvis + P * Vector3(0, 0.02, 0), P, Vector3(0.34, 0.17, 0.22))
	_box("torso", pelvis + P * Vector3(0, 0.33, 0), P, Vector3(0.42, 0.48, 0.27))
	_box("hood", pelvis + P * Vector3(0, 0.56, -0.1), P, Vector3(0.3, 0.1, 0.12))
	_box("pack", pelvis + P * Vector3(0, 0.32, -0.17), P, Vector3(0.3, 0.34, 0.1))
	var HB := P * Basis.from_euler(Vector3(deg_to_rad(p.head_pitch), deg_to_rad(p.head_yaw), 0))
	var head := pelvis + P * Vector3(0, 0.72, 0.01)
	_place("head", head, HB.scaled(Vector3.ONE * 0.12))
	_place("helmet", head + HB * Vector3(0, 0.02, -0.005), HB.scaled(Vector3(0.145, 0.15, 0.145)))
	_box("goggles", head + HB * Vector3(0, 0.03, 0.1), HB, Vector3(0.2, 0.07, 0.05))
	# Arms (forward kinematics).
	for side in [["l", 1.0, p.ls_x, p.ls_z, p.le], ["r", -1.0, p.rs_x, p.rs_z, p.re]]:
		var sh: Vector3 = pelvis + P * Vector3(0.23 * side[1], 0.52, 0.0)
		var R := P * Basis.from_euler(Vector3(deg_to_rad(side[2]), 0, deg_to_rad(side[3])))
		var el := sh + R * Vector3(0, -0.3, 0)
		var R2 := R * Basis(Vector3.RIGHT, deg_to_rad(-side[4]))
		var hand := el + R2 * Vector3(0, -0.27, 0)
		_seg("uarm_" + side[0], sh, el, 0.062)
		_seg("farm_" + side[0], el, hand, 0.055)
		_box("glove_" + side[0], hand + R2 * Vector3(0, -0.04, 0), R2, Vector3(0.09, 0.11, 0.08))
		if side[0] == "r":
			hand_r_world = to_global(hand)
			_mushroom.visible = mushroom_visible
			_mushroom.transform = Transform3D(R2.scaled(Vector3.ONE * 1.4), hand + R2 * Vector3(0, -0.1, 0.04))
	# Legs (two-bone IK to fixed boot positions on the board).
	for side in [["l", 1.0], ["r", -1.0]]:
		var hip: Vector3 = pelvis + P * Vector3(0.1 * side[1], -0.04, 0)
		var ankle: Vector3 = root * Vector3(0.26 * side[1], 0.13, 0)
		var pole: Vector3 = root * Vector3(0.3 * side[1], p.pole_up, 1.0).normalized()
		var knee := _ik(hip, ankle, pole)
		_seg("thigh_" + side[0], hip, knee, 0.085)
		_seg("shin_" + side[0], knee, ankle, 0.072)
		_box("boot_" + side[0], root * Vector3(0.26 * side[1], 0.09, 0.02), root, Vector3(0.14, 0.13, 0.3))


func _ik(h: Vector3, a: Vector3, pole: Vector3) -> Vector3:
	var d := a - h
	var l := clampf(d.length(), 0.05, THIGH + SHIN - 0.002)
	var dn := d.normalized()
	var x := (THIGH * THIGH - SHIN * SHIN + l * l) / (2.0 * l)
	var y := sqrt(maxf(THIGH * THIGH - x * x, 0.0))
	var pp := (pole - dn * pole.dot(dn))
	if pp.length_squared() < 1e-6:
		pp = Vector3(0, 0, 1)
	return h + dn * x + pp.normalized() * y


func _place(n: String, pos: Vector3, b: Basis) -> void:
	_parts[n].transform = Transform3D(b, pos)


func _box(n: String, pos: Vector3, b: Basis, size: Vector3) -> void:
	_parts[n].transform = Transform3D(b * Basis.from_scale(size), pos)


func _seg(n: String, a: Vector3, b: Vector3, r: float) -> void:
	var y := b - a
	var len := maxf(y.length(), 0.001)
	var yn := y / len
	var ref := Vector3.FORWARD if absf(yn.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := yn.cross(ref).normalized()
	var z := x.cross(yn)
	_parts[n].transform = Transform3D(Basis(x * r, yn * len, z * r), (a + b) * 0.5)
