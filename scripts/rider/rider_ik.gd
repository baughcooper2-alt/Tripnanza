class_name RiderIK
extends SkeletonModifier3D
## Procedural layer on top of the imported animations (runs after them each
## frame). Skeleton space: +Y up, +Z board nose, +X the way the rider faces.
## Legs: hips drop for crouch/tuck/landing while two-bone IK keeps the knees
## bending over boots that stay on the board. Arms: two-bone IK for grabs,
## eating the mushroom and planting a hand in the snow.

var crouch := 0.0     ## 0 = stance from the animation, 1 = deep crouch
var bend := 0.0       ## upper-body fold toward the board
var grab_r := 0.0
var grab_l := 0.0
var reach := 0.0      ## both hands toward the knees (tuck)
var eat := 0.0
var plant := 0.0
var flail := 0.0
var breathe := 0.0

const FACE := Vector3(1, 0, 0)
const NOSE := Vector3(0, 0, 1)
var _t := 0.0
var _ids := {}
var _rel := {}   # hand pose relative to its forearm, as animated


func _id(n: String) -> int:
	if not _ids.has(n):
		_ids[n] = get_skeleton().find_bone(n)
	return _ids[n]


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _id("spine") < 0:
		return
	_t += get_process_delta_time() if is_inside_tree() else 0.016
	for side in ["L", "R"]:
		_rel[side] = sk.get_bone_global_pose(_id("forearm." + side)).affine_inverse() * sk.get_bone_global_pose(_id("hand." + side))
	# --- remember where the boots are before moving the body
	var ank_l := sk.get_bone_global_pose(_id("foot.L")).origin
	var ank_r := sk.get_bone_global_pose(_id("foot.R")).origin
	# --- hips down + breathing
	var sp := sk.get_bone_global_pose(_id("spine"))
	sp.origin += Vector3.UP * (-crouch * 0.3 + sin(_t * 1.7) * 0.006 * breathe)
	sp.origin += FACE * crouch * 0.05
	sk.set_bone_global_pose(_id("spine"), sp)
	# --- upper body folds toward the toes
	var chest := _id("spine.002")
	if chest >= 0 and (bend > 0.001 or breathe > 0.0):
		var g := sk.get_bone_global_pose(chest)
		var ang := -bend * 0.55 - sin(_t * 1.7) * 0.02 * breathe
		g.basis = Basis(NOSE, ang) * g.basis
		sk.set_bone_global_pose(chest, g)
	# --- legs: knees over the boots, pointing the way the rider faces
	_two_bone(sk, _id("thigh.L"), _id("shin.L"), 0.45, ank_l, FACE + Vector3.UP * 0.2 + NOSE * 0.15)
	_two_bone(sk, _id("thigh.R"), _id("shin.R"), 0.45, ank_r, FACE + Vector3.UP * 0.2 - NOSE * 0.15)
	# --- arms
	var board := sk.get_bone_global_pose(_id("Snowboard")).origin
	var head := sk.get_bone_global_pose(_id("spine.006")).origin
	var hips := sk.get_bone_global_pose(_id("spine")).origin
	var hand_r := _hand_pos(sk, "R")
	var hand_l := _hand_pos(sk, "L")
	var tgt_r := hand_r
	var tgt_l := hand_l
	var knee_r := sk.get_bone_global_pose(_id("shin.R")).origin
	var knee_l := sk.get_bone_global_pose(_id("shin.L")).origin
	tgt_r = tgt_r.lerp(knee_r + FACE * 0.15, reach)
	tgt_l = tgt_l.lerp(knee_l + FACE * 0.15, reach)
	# Grabs: right hand to the toe edge, left hand to the heel edge.
	tgt_r = tgt_r.lerp(board + FACE * 0.16 + Vector3.UP * 0.08 + (ank_r - board) * Vector3(0, 0, 1) * 0.6, grab_r)
	tgt_l = tgt_l.lerp(board - FACE * 0.16 + Vector3.UP * 0.08 + (ank_l - board) * Vector3(0, 0, 1) * 0.6, grab_l)
	# Mushroom to the mouth, then a gloved hand planted in the snow behind.
	tgt_r = tgt_r.lerp(head + FACE * 0.14 - Vector3.UP * 0.08, eat)
	tgt_r = tgt_r.lerp(Vector3(hips.x, board.y + 0.05, hips.z) - FACE * 0.35, plant)
	if flail > 0.001:
		tgt_r += Vector3(sin(_t * 15.0), cos(_t * 13.0) * 0.6, sin(_t * 11.0)) * 0.25 * flail
		tgt_l += Vector3(sin(_t * 17.0 + 1.0), cos(_t * 12.0) * 0.6, sin(_t * 9.0)) * 0.25 * flail
	if (tgt_r - hand_r).length() > 0.002:
		_arm(sk, "R", tgt_r)
	else:
		_attach_hand(sk, "R")
	if (tgt_l - hand_l).length() > 0.002:
		_arm(sk, "L", tgt_l)
	else:
		_attach_hand(sk, "L")


func _hand_pos(sk: Skeleton3D, side: String) -> Vector3:
	return sk.get_bone_global_pose(_id("hand." + side)).origin


func _arm(sk: Skeleton3D, side: String, target: Vector3) -> void:
	var ua := _id("upper_arm." + side)
	var fa := _id("forearm." + side)
	_two_bone(sk, ua, fa, 0.25, target, -Vector3.UP * 0.6 - FACE * 0.4 + (NOSE if side == "L" else -NOSE) * 0.3)
	_attach_hand(sk, side)


## The hands are separate control bones in this rig: keep them on the wrists
## whenever the body moves, or the gloves get left behind.
func _attach_hand(sk: Skeleton3D, side: String) -> void:
	var f := sk.get_bone_global_pose(_id("forearm." + side))
	sk.set_bone_global_pose(_id("hand." + side), f * (_rel[side] as Transform3D))


func _two_bone(sk: Skeleton3D, b1: int, b2: int, len2: float, target: Vector3, pole: Vector3) -> void:
	if b1 < 0 or b2 < 0:
		return
	var g1 := sk.get_bone_global_pose(b1)
	var g2 := sk.get_bone_global_pose(b2)
	var a := g1.origin.distance_to(g2.origin)
	var h := g1.origin
	var d := target - h
	var l := clampf(d.length(), 0.02, a + len2 - 0.002)
	var dn := d.normalized()
	var x := (a * a - len2 * len2 + l * l) / (2.0 * l)
	var y := sqrt(maxf(a * a - x * x, 0.0))
	var pp := pole - dn * pole.dot(dn)
	if pp.length_squared() < 1e-6:
		pp = FACE
	var knee := h + dn * x + pp.normalized() * y
	g1.basis = _aim(g1.basis, knee - h)
	sk.set_bone_global_pose(b1, g1)
	g2 = sk.get_bone_global_pose(b2)
	g2.basis = _aim(g2.basis, h + dn * l - g2.origin)
	sk.set_bone_global_pose(b2, g2)


static func _aim(b: Basis, dir: Vector3) -> Basis:
	var cur := b.y.normalized()
	var want := dir.normalized()
	if cur.dot(want) > 0.99999:
		return b
	var axis := cur.cross(want)
	if axis.length_squared() < 1e-10:
		return b
	return Basis(axis.normalized(), cur.angle_to(want)) * b
