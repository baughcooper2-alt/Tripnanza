class_name HumanPoser
extends SkeletonModifier3D
## Drives a MakeHuman "game_engine" skeleton from the procedural rider pose
## (RiderModel.joints). Works for any body shape: limb lengths are measured
## from the skeleton's rest pose and the arms/legs are solved with two-bone IK
## so hands and boots land where the pose wants them.
## Joint targets arrive in the CustomRider's local space (+X board nose,
## +Y up, +Z the way the rider faces). The human's rest pose faces +Z.

var joints := {}          ## filled by CustomRider each frame
var to_skeleton := Transform3D.IDENTITY   ## CustomRider local -> skeleton space
var scale_k := 1.0        ## human size / procedural rider size

var _ids := {}
var _rest_g := {}
var _ready_rest := false
var leg_len := 0.9


func _id(n: String) -> int:
	if not _ids.has(n):
		_ids[n] = get_skeleton().find_bone(n)
	return _ids[n]


func _cache_rest() -> void:
	var sk := get_skeleton()
	for i in sk.get_bone_count():
		_rest_g[i] = sk.get_bone_global_rest(i)
	var hip: Vector3 = _rest_g[_id("thigh_l")].origin
	var knee: Vector3 = _rest_g[_id("calf_l")].origin
	var ank: Vector3 = _rest_g[_id("foot_l")].origin
	leg_len = hip.distance_to(knee) + knee.distance_to(ank)
	scale_k = leg_len / 0.91
	_ready_rest = true


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or joints.is_empty() or _id("pelvis") < 0:
		return
	if not _ready_rest:
		_cache_rest()
	var M := to_skeleton
	var Mb := M.basis.orthonormalized()
	var k := scale_k
	var J := joints
	# Rider pose sizes are for a ~0.91 m leg; scale the body (not the board).
	var pelvis_t: Vector3 = M * (J.pelvis * Vector3(1.0, k, 1.0) + Vector3(0, 0.0, 0))
	var P: Basis = Mb * (J.P as Basis) * Mb.inverse()
	var HB: Basis = Mb * (J.HB as Basis) * Mb.inverse()
	# --- pelvis: position + whole-torso rotation
	var pel := _id("pelvis")
	var root := sk.get_bone_parent(pel)
	var root_g := sk.get_bone_global_pose(root) if root >= 0 else Transform3D.IDENTITY
	var pel_g := Transform3D(P * (_rest_g[pel] as Transform3D).basis, pelvis_t)
	_set_global(sk, pel, pel_g, root_g)
	# --- spine + neck follow the torso rotation, head gets its own
	for b in ["spine_01", "spine_02", "spine_03", "neck_01"]:
		_set_global_rot(sk, _id(b), P * (_rest_g[_id(b)] as Transform3D).basis)
	_set_global_rot(sk, _id("head"), HB * (_rest_g[_id("head")] as Transform3D).basis)
	# --- arms
	for s in ["l", "r"]:
		var ua := _id("upperarm_" + s)
		var la := _id("lowerarm_" + s)
		var hd := _id("hand_" + s)
		var sh_g := sk.get_bone_global_pose(ua).origin
		var rider_sh: Vector3 = J["sh_" + s]
		var hand_t: Vector3 = M * (rider_sh + ((J["hand_" + s] as Vector3) - rider_sh) * k)
		var elbow_hint: Vector3 = M * (rider_sh + ((J["el_" + s] as Vector3) - rider_sh) * k)
		var pole := elbow_hint - (sh_g + hand_t) * 0.5
		_two_bone(sk, ua, la, hd, hand_t, pole)
		_set_global_rot(sk, hd, sk.get_bone_global_pose(la).basis * (_rest_g[la] as Transform3D).basis.inverse() * (_rest_g[hd] as Transform3D).basis)
	# --- legs: boots stay on the board
	var Rb: Basis = Mb * (J.root as Basis) * Mb.inverse()
	for s in ["l", "r"]:
		var th := _id("thigh_" + s)
		var cf := _id("calf_" + s)
		var ft := _id("foot_" + s)
		var ank: Vector3 = M * ((J["ankle_" + s] as Vector3) + (J.root as Basis) * Vector3(0, -0.03, -0.05))
		var pole: Vector3 = Mb * (J["pole_" + s] as Vector3)
		_two_bone(sk, th, cf, ft, ank, pole)
		# Foot flat on the board, toes toward the way the rider faces.
		var ball := _id("ball_" + s)
		var rest_dir: Vector3 = ((_rest_g[ball] as Transform3D).origin - (_rest_g[ft] as Transform3D).origin).normalized() if ball >= 0 else Vector3(0, -0.4, 1).normalized()
		var want: Vector3 = Rb * Vector3(0, -0.25, 1.0).normalized()
		var fb: Basis = _rot_between(rest_dir, want) * (_rest_g[ft] as Transform3D).basis
		_set_global_rot(sk, ft, fb)


## Rotate bone b1 (to b2) and b2 (to b3) so b3's head reaches target.
func _two_bone(sk: Skeleton3D, b1: int, b2: int, b3: int, target: Vector3, pole: Vector3) -> void:
	if b1 < 0 or b2 < 0 or b3 < 0:
		return
	var r1: Transform3D = _rest_g[b1]
	var r2: Transform3D = _rest_g[b2]
	var r3: Transform3D = _rest_g[b3]
	var a := r1.origin.distance_to(r2.origin)
	var b := r2.origin.distance_to(r3.origin)
	var h := sk.get_bone_global_pose(b1).origin
	var d := target - h
	var l := clampf(d.length(), 0.02, a + b - 0.002)
	var dn := d.normalized()
	var x := (a * a - b * b + l * l) / (2.0 * l)
	var y := sqrt(maxf(a * a - x * x, 0.0))
	var pp := pole - dn * pole.dot(dn)
	if pp.length_squared() < 1e-6:
		pp = Vector3(0, 0, 1)
	var mid := h + dn * x + pp.normalized() * y
	var end := h + dn * l
	# Upper bone: rotate its rest direction onto (mid - h).
	var rest_dir1 := (r2.origin - r1.origin).normalized()
	_set_global_rot(sk, b1, _rot_between(rest_dir1, (mid - h).normalized()) * r1.basis)
	var rest_dir2 := (r3.origin - r2.origin).normalized()
	_set_global_rot(sk, b2, _rot_between(rest_dir2, (end - mid).normalized()) * r2.basis)


func _set_global_rot(sk: Skeleton3D, bone: int, global_basis: Basis) -> void:
	if bone < 0:
		return
	var parent := sk.get_bone_parent(bone)
	var pg := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
	var local := pg.orthonormalized().inverse() * global_basis.orthonormalized()
	sk.set_bone_pose_rotation(bone, local.get_rotation_quaternion())


func _set_global(sk: Skeleton3D, bone: int, g: Transform3D, parent_g: Transform3D) -> void:
	var local := parent_g.affine_inverse() * g
	sk.set_bone_pose_position(bone, local.origin)
	sk.set_bone_pose_rotation(bone, local.basis.orthonormalized().get_rotation_quaternion())


static func _rot_between(a: Vector3, b: Vector3) -> Basis:
	var c := a.cross(b)
	var d := clampf(a.dot(b), -1.0, 1.0)
	if c.length_squared() < 1e-10:
		return Basis() if d > 0.0 else Basis(Vector3(0, 1, 0), PI)
	return Basis(c.normalized(), acos(d))
