class_name RiderAvatar
extends Node3D
## The imported snowboarder (assets/characters/snowboarder/snowboarder.glb),
## driven with the same interface as the procedural RiderModel:
##   weights (pose name -> 0..1), flail, breathe, mushroom_visible, hand_r_world, snap().
## Its own animations do the riding (Idle / Turn_Left / Turn_Right blended by
## `lean`) and the Fall clip is scrubbed for sitting, standing up and wiping out.
## RiderIK (a SkeletonModifier3D) layers crouch, tuck, landing compression,
## grabs, eating the mushroom and the hand plant on top.

const GLB := "res://assets/characters/snowboarder/snowboarder.glb"
const GLB_SCALE := 51.2          # the export is ~1/51 scale; this makes it metres

@export var avatar_scale := 1.25
@export var pose_smoothing := 14.0
@export_range(0.5, 1.0) var fall_end := 0.82   ## how far into the Fall clip counts as 'sitting'

var weights := {}
var flail := 0.0
var breathe := 1.0
var mushroom_visible := false
var hand_r_world := Vector3.ZERO
var lean := 0.0                  ## -1 hard left .. +1 hard right (in the avatar's own frame)
var crashing := false

var _w := {}
var _lean := 0.0
var _crash_time := 0.0
var _sk: Skeleton3D
var _tree: AnimationTree
var _ik: RiderIK
var _fall_len := 1.66
var _mushroom: MeshInstance3D


func _ready() -> void:
	for k in RiderModel.POSES:
		weights[k] = 0.0
		_w[k] = 0.0
	var scene: Node3D = load(GLB).instantiate()
	add_child(scene)
	# The model's board points along +Z and the rider faces +X; the game's rider
	# frame has the nose along +X, so turn it a quarter.
	scene.rotation.y = PI * 0.5
	scene.scale = Vector3.ONE * GLB_SCALE * avatar_scale
	var trail := scene.find_child("Player_001", true, false)
	if trail:
		trail.visible = false   # the game draws its own tracks
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_sk = scene.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	for a in ["Idle", "Turn_Left", "Turn_Right"]:
		ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	# The last frames of the clip scale the character away; stop before them.
	_fall_len = ap.get_animation("Fall").length * fall_end
	_build_tree(ap)
	_ik = RiderIK.new()
	_sk.add_child(_ik)
	# Mushroom in the right hand for the summit intro.
	var att := BoneAttachment3D.new()
	att.bone_name = "hand.R"
	_sk.add_child(att)
	_mushroom = MeshInstance3D.new()
	_mushroom.mesh = MeshFactory.mushroom()
	var mm := StandardMaterial3D.new()
	mm.vertex_color_use_as_albedo = true
	_mushroom.material_override = mm
	_mushroom.scale = Vector3.ONE * (1.6 / (GLB_SCALE * avatar_scale * 0.01953))
	att.add_child(_mushroom)


func _build_tree(ap: AnimationPlayer) -> void:
	var bt := AnimationNodeBlendTree.new()
	var idle := AnimationNodeAnimation.new()
	idle.animation = "Idle"
	var left := AnimationNodeAnimation.new()
	left.animation = "Turn_Left"
	var right := AnimationNodeAnimation.new()
	right.animation = "Turn_Right"
	var fall := AnimationNodeAnimation.new()
	fall.animation = "Fall"
	var lean_node := AnimationNodeBlend3.new()
	var freeze := AnimationNodeTimeScale.new()
	var seek := AnimationNodeTimeSeek.new()
	var mix := AnimationNodeBlend2.new()
	bt.add_node("idle", idle, Vector2(0, 0))
	bt.add_node("left", left, Vector2(0, 100))
	bt.add_node("right", right, Vector2(0, 200))
	bt.add_node("lean", lean_node, Vector2(200, 100))
	bt.add_node("fall", fall, Vector2(0, 300))
	bt.add_node("freeze", freeze, Vector2(200, 300))
	bt.add_node("seek", seek, Vector2(400, 300))
	bt.add_node("mix", mix, Vector2(600, 150))
	bt.connect_node("lean", 0, "left")
	bt.connect_node("lean", 1, "idle")
	bt.connect_node("lean", 2, "right")
	bt.connect_node("freeze", 0, "fall")
	bt.connect_node("seek", 0, "freeze")
	bt.connect_node("mix", 0, "lean")
	bt.connect_node("mix", 1, "seek")
	bt.connect_node("output", 0, "mix")
	_tree = AnimationTree.new()
	_tree.tree_root = bt
	ap.get_parent().add_child(_tree)
	_tree.anim_player = _tree.get_path_to(ap)
	_tree.active = true
	_tree.set("parameters/freeze/scale", 0.0)


func snap() -> void:
	for k in weights:
		_w[k] = weights[k]
	_lean = lean
	_apply(0.0)


func _process(dt: float) -> void:
	var a := 1.0 - exp(-pose_smoothing * dt)
	for k in weights:
		var rate := a
		if k == "pop" or k == "land":
			rate = 1.0 - exp(-30.0 * dt)
		_w[k] = lerpf(_w.get(k, 0.0), weights[k], rate)
	_lean = lerpf(_lean, lean, 1.0 - exp(-8.0 * dt))
	_apply(dt)


func _apply(dt: float) -> void:
	var crash_w: float = _w.get("crash", 0.0)
	if weights.get("crash", 0.0) > 0.5:
		_crash_time += dt
	else:
		_crash_time = 0.0
	var sit_w: float = clampf(_w.get("sit", 0.0) + _w.get("plant", 0.0) * 0.4, 0.0, 1.0)
	# Fall clip: 0 = riding stance ... end = sitting in the snow.
	var fall_t := _fall_len * sit_w
	if crash_w > 0.05:
		fall_t = maxf(fall_t, minf(_crash_time * 1.3, _fall_len))
	_tree.set("parameters/seek/seek_request", fall_t)
	_tree.set("parameters/mix/blend_amount", clampf(maxf(sit_w, crash_w) * 1.5, 0.0, 1.0))
	_tree.set("parameters/lean/blend_amount", clampf(_lean, -1.0, 1.0))
	var ride := 1.0 - clampf(maxf(sit_w, crash_w), 0.0, 1.0)
	_ik.crouch = ride * clampf(_w.crouch * 0.9 + _w.tuck * 1.1 + _w.land * 0.8 + _w.speed * 0.6 + _w.grab_l * 0.6 + _w.grab_r * 0.6 - _w.pop * 0.25 + _w.brake * 0.3, -0.25, 1.1)
	_ik.bend = ride * clampf(_w.tuck * 0.9 + _w.speed * 0.7 + _w.crouch * 0.4 + _w.grab_r * 0.5, 0.0, 1.0)
	_ik.grab_r = ride * _w.grab_r
	_ik.grab_l = ride * _w.grab_l
	_ik.reach = _w.tuck * ride * 0.6
	_ik.eat = _w.eat
	_ik.plant = _w.plant
	_ik.flail = flail
	_ik.breathe = breathe
	_mushroom.visible = mushroom_visible
	var hr := _sk.find_bone("forearm.R")
	if hr >= 0:
		var g := _sk.get_bone_global_pose(hr)
		hand_r_world = _sk.global_transform * (g.origin + g.basis.y * 0.25)
