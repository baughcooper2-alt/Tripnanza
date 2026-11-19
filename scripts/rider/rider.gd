class_name Rider
extends Node3D
## Snowboarder controller: carving physics, ollies and kicker launches,
## flips/spins, landing judgement, collisions, the summit intro and wipeouts.

signal control_started
signal took_off
signal trick_changed(text: String)
signal landed(result: Dictionary)
signal crashed(reason: String)

enum State { SEATED, INTRO, RIDING, AIR, CRASHED }

@export_group("Handling")
@export var gravity := 13.0
@export var tap_turn_rate := 0.5            ## rad/s while a direction is held, before lean builds
@export var carve_turn_rate := 1.15           ## extra rad/s at full lean
@export var lean_build_time := 0.55          ## seconds of holding to reach a full carve
@export var lean_release_rate := 5.0
@export var edge_switch_boost := 2.2         ## faster edge-to-edge transitions when linking turns
@export var edge_grip := 7.5
@export var carve_speed_keep := 0.9          ## share of sideways speed redirected along the board
@export var snow_friction := 0.035
@export var air_drag := 0.0052
@export var tuck_drag_mult := 0.55
@export var brake_decel := 9.0
@export var max_speed := 36.0
@export var start_push := 5.0
@export_group("Jumping")
@export var ollie_strength := 4.6
@export var ollie_charge_bonus := 2.6
@export var charge_time := 0.5
@export var lip_pop_window := 0.18           ## releasing jump this soon after a lip adds pop
@export var lip_pop_bonus := 2.4
@export var leave_ground_speed := 2.8
@export var stick_distance := 0.35
@export_group("Tricks")
@export var flip_speed_deg := 430.0          ## frontflip/backflip rotation speed
@export var spin_speed_deg := 560.0          ## spin rotation speed
@export var rotation_accel_deg := 2600.0
@export var untuck_decay_deg := 900.0        ## how fast rotation slows once you untuck
@export var land_assist_deg := 45.0          ## near-upright landings get nudged straight
@export var clean_tilt_deg := 35.0
@export var clean_spin_deg := 30.0
@export var sketchy_tilt_deg := 80.0
@export var sketchy_spin_deg := 68.0
@export var max_impact_speed := 32.0
@export_group("Collisions")
@export var body_radius := 0.38
@export var safe_bump_speed := 3.5
@export var crash_into_speed := 11.0   ## only hits faster than this straight into a tree/rock end the run
@export var bump_speed_loss := 0.45

var state := State.SEATED
var vel := Vector3.ZERO
var fwd := Vector3(1, 0, 0)
var normal := Vector3.UP
var lean := 0.0
var switch_stance := false
var charge := 0.0
var braking := false
var tucking := false
var invincible := false
var ai = null                   ## Optional Dictionary of inputs (test harness)

var air_time := 0.0
var flip := 0.0
var spin := 0.0
var flip_vel := 0.0
var spin_vel := 0.0
var air_up := Vector3.UP
var air_head := Vector3.FORWARD
var max_air_height := 0.0
var since_takeoff := 0.0
var from_ramp := false
var land_comp := 0.0
var sketchy_t := 0.0
var pop_t := 0.0
var crash_t := 0.0
var crash_spin := Vector3.ZERO
var intro_t := 0.0
var speed := 0.0
var cam_heading := Vector3(0, 0, 1)

var model   ## RiderAvatar (imported snowboarder) or RiderModel (procedural fallback)
var powder: Powder
var tracks: Tracks
var _vis_q := Quaternion.IDENTITY
var _jump_was := false
var _last_trick := ""
var _ground_y := 0.0
var _spin_locked := false
var _pitch_locked := false
var _popped := false
var _switch_was := false
var _model_yaw := 0.0
var grab_l := false
var grab_r := false
var grab_time := 0.0
var _grab_armed := false


@export var use_imported_rider := true   ## false = the original procedural rider

func _ready() -> void:
	if use_imported_rider and ResourceLoader.exists(RiderAvatar.GLB):
		model = RiderAvatar.new()
	else:
		model = RiderModel.new()
	model.name = "Model"
	add_child(model)


func now() -> float:
	return TripDirector.now


# ------------------------------------------------------------------ public

func reset_to_summit() -> void:
	state = State.SEATED
	var g := Mountain.ground(0.0, 0.0)
	position = Vector3(0, g.w, 0)
	_ground_y = g.w
	# The imported rider's sit pose already has the board across the slope.
	fwd = Vector3(0, 0, 1) if model is RiderAvatar else Vector3(1, 0, 0)
	normal = Vector3(g.x, g.y, g.z)
	vel = Vector3.ZERO
	lean = 0.0
	switch_stance = false
	charge = 0.0
	flip = 0.0
	spin = 0.0
	land_comp = 0.0
	sketchy_t = 0.0
	invincible = false
	cam_heading = Vector3(0, 0, 1)
	model.position = Vector3.ZERO
	model.rotation = Vector3.ZERO
	_set_weights({sit = 1.0})
	model.breathe = 1.0
	model.mushroom_visible = false
	model.snap()
	_vis_q = _ground_basis().get_rotation_quaternion()
	transform.basis = Basis(_vis_q)


func begin_intro() -> void:
	if state != State.SEATED:
		return
	state = State.INTRO
	intro_t = 0.0


func is_controllable() -> bool:
	return state == State.RIDING or state == State.AIR


# ------------------------------------------------------------------ input

func _inp() -> Dictionary:
	if ai != null:
		var d: Dictionary = ai.duplicate()
		d.merge({tuck = ai.get("forward", false), brake = ai.get("back", false), grab_l = false, grab_r = false})
		return d
	return {
		steer = Input.get_axis("steer_left", "steer_right"),
		forward = Input.is_action_pressed("lean_forward"),     # air: frontflip
		back = Input.is_action_pressed("lean_back"),           # air: backflip
		tuck = Input.is_action_pressed("tuck"),                # snow: tuck
		brake = Input.is_action_pressed("brake"),              # snow: brake
		jump = Input.is_action_pressed("jump"),
		grab_l = Input.is_action_pressed("grab_left"),
		grab_r = Input.is_action_pressed("grab_right"),
	}


## Steep-style stance switch: Q, or push the two sticks in opposite directions.
func _switch_requested() -> bool:
	if ai != null:
		return false
	var pad := false
	var lx := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	if absf(lx) > 0.6 and absf(rx) > 0.6 and signf(lx) != signf(rx):
		pad = true
	var want := pad or Input.is_action_pressed("switch_stance")
	var fire := want and not _switch_was
	_switch_was = want
	return fire


## D-pad up / X: deliberately fall.
func bail() -> void:
	if state == State.RIDING or state == State.AIR:
		_crash_start("Bailed")


# ------------------------------------------------------------------ loop

func _physics_process(dt: float) -> void:
	match state:
		State.SEATED:
			_set_weights({sit = 1.0})
		State.INTRO:
			_intro(dt)
		State.RIDING:
			_ride(dt)
		State.AIR:
			_air(dt)
		State.CRASHED:
			_crash(dt)
	speed = vel.length()
	var hv := Vector3(vel.x, 0, vel.z)
	if hv.length() > 2.0:
		cam_heading = cam_heading.slerp(hv.normalized(), 1.0 - exp(-(1.2 if state == State.AIR else 2.6) * dt)).normalized()
	# Visual orientation: smooth, never snaps.
	var target_q: Quaternion
	if state == State.AIR:
		target_q = _air_basis().get_rotation_quaternion()
	elif state == State.CRASHED:
		target_q = (_ground_basis() * Basis.from_euler(crash_spin * crash_t * exp(-crash_t * 1.5))).get_rotation_quaternion()
	else:
		target_q = _ground_basis().get_rotation_quaternion()
	var rate := 30.0 if state == State.AIR else 16.0
	_vis_q = _vis_q.slerp(target_q, 1.0 - exp(-rate * dt))
	transform.basis = Basis(_vis_q)
	# Stance flips are animated as a quick 180 pivot.
	_model_yaw = lerp_angle(_model_yaw, PI if switch_stance else 0.0, 1.0 - exp(-14.0 * dt))
	model.rotation.y = _model_yaw
	if "lean" in model:
		# The avatar's turn clips lean the way you steer (mirrored when riding switch).
		var steer_lean := lean if state == State.RIDING else 0.0
		model.lean = -steer_lean if switch_stance else steer_lean


func _ground_basis() -> Basis:
	var x := (fwd - normal * fwd.dot(normal)).normalized()
	var z := x.cross(normal).normalized()
	return Basis(x, normal, z)


func _air_basis() -> Basis:
	var x := (air_head - air_up * air_head.dot(air_up)).normalized()
	var base := Basis(x, air_up, x.cross(air_up).normalized())
	return base * Basis(Vector3(0, 0, 1), flip) * Basis(Vector3.UP, spin)


# ------------------------------------------------------------------ intro

func _intro(dt: float) -> void:
	intro_t += dt
	var t := intro_t
	model.breathe = lerpf(1.0, 0.3, clampf(t / 2.0, 0.0, 1.0))
	var w := {sit = 1.0}
	# 0.0-1.15: eat the mushroom.
	w.eat = smoothstep(0.05, 0.45, t) * (1.0 - smoothstep(1.0, 1.25, t))
	model.mushroom_visible = t > 0.18 and t < 1.0
	# 1.15-1.6: plant a gloved hand in the snow.
	w.plant = smoothstep(1.1, 1.4, t) * (1.0 - smoothstep(1.55, 1.8, t))
	if t >= 1.42 and t - dt < 1.42 and powder:
		powder.burst(model.hand_r_world, Vector3.UP, 16, 2.2, 0.35)
	# 1.6-1.9: pop up onto the board.
	w.sit = 1.0 - smoothstep(1.45, 2.05, t)
	w.crouch = smoothstep(1.55, 1.8, t) * (1.0 - smoothstep(1.9, 2.05, t))
	w.pop = smoothstep(1.85, 1.95, t) * (1.0 - smoothstep(2.0, 2.15, t))
	# 1.9-2.25: hop and swing the board to point downhill.
	var swing := smoothstep(1.9, 2.25, t)
	var ang := -PI * 0.5 * swing
	if not (model is RiderAvatar):
		fwd = Vector3(1, 0, 0).rotated(Vector3.UP, ang)
	var hop := maxf(0.0, sin(clampf((t - 1.9) / 0.35, 0.0, 1.0) * PI)) * 0.35
	model.position.y = hop
	w.land = smoothstep(2.2, 2.28, t) * (1.0 - smoothstep(2.3, 2.6, t))
	_set_weights(w)
	if t >= 2.25:
		model.position.y = 0.0
		fwd = Vector3(0, 0, 1)
		vel = fwd * start_push
		state = State.RIDING
		land_comp = 0.5
		if powder:
			powder.burst(global_position, Vector3.UP, 10, 2.5, 0.4)
		control_started.emit()


# ------------------------------------------------------------------ riding

func _ride(dt: float) -> void:
	var i := _inp()
	var s: float = i.steer
	braking = i.brake
	tucking = i.tuck and not braking
	if _switch_requested() and vel.length() > 1.0:
		switch_stance = not switch_stance
	# Lean builds while a direction is held; quick taps barely lean.
	if absf(s) > 0.05:
		var rate := 1.0 / lean_build_time
		if signf(s) != signf(lean) and absf(lean) > 0.05:
			rate *= edge_switch_boost
		lean = move_toward(lean, s, rate * dt)
	else:
		lean = move_toward(lean, 0.0, lean_release_rate * dt)
	var spd := vel.length()
	var speed_fac := clampf(1.15 - spd / 60.0, 0.6, 1.1)
	var turn := (s * tap_turn_rate + lean * carve_turn_rate) * speed_fac
	if braking:
		turn *= 0.6
	fwd = fwd.rotated(normal, -turn * dt)
	# Gravity along the slope.
	var g := Vector3(0, -gravity, 0)
	vel += (g - normal * g.dot(normal)) * dt
	vel -= normal * vel.dot(normal)
	fwd = (fwd - normal * fwd.dot(normal)).normalized()
	var lat := normal.cross(fwd).normalized()
	var vf := vel.dot(fwd)
	var vl := vel.dot(lat)
	if vf < -0.5:
		# Rolling backwards: the board is symmetric, ride it switch.
		fwd = -fwd
		lat = -lat
		vf = -vf
		vl = -vl
		switch_stance = not switch_stance
	# Edge grip turns sideways slide into forward speed (carving keeps speed).
	var grip := edge_grip * (0.45 + 0.55 * absf(lean))
	if braking:
		grip = 2.2
	var new_vl := vl * exp(-grip * dt)
	var lost := vl * vl - new_vl * new_vl
	vf = sqrt(maxf(vf * vf + lost * (0.0 if braking else carve_speed_keep), 0.0))
	vel = fwd * vf + lat * new_vl
	# Resistance.
	spd = vel.length()
	var drag := air_drag * (tuck_drag_mult if tucking else 1.0)
	var decel := snow_friction * gravity * normal.y + drag * spd * spd + absf(lean) * 0.25
	if braking:
		decel += brake_decel
	if spd > 0.001:
		vel = vel / spd * maxf(spd - decel * dt, 0.0)
	if tucking:
		vel += fwd * 0.8 * dt
	if vel.length() > max_speed:
		vel = vel.normalized() * max_speed
	# Jump: hold to crouch, release to pop.
	var jump: bool = i.jump
	if jump:
		charge = minf(charge + dt / charge_time, 1.0)
	var released := _jump_was and not jump
	_jump_was = jump
	# Move and follow the ground.
	var on_ramp_before := not Mountain.on_ramp(position.x, position.z).is_empty()
	position += vel * dt
	var gr := Mountain.ground(position.x, position.z)
	var nn := Vector3(gr.x, gr.y, gr.z)
	var above := position.y - gr.w
	var vn := vel.dot(nn)
	if released:
		var pop := ollie_strength + charge * ollie_charge_bonus
		charge = 0.0
		position.y = maxf(position.y, gr.w)
		vel += nn * pop
		_popped = true
		_take_off(false)
		pop_t = 0.3
		return
	if above > stick_distance or vn > leave_ground_speed:
		_take_off(on_ramp_before)
		return
	position.y = gr.w
	normal = normal.slerp(nn, 1.0 - exp(-25.0 * dt)).normalized()
	vel -= nn * vel.dot(nn)
	if not jump:
		charge = move_toward(charge, 0.0, dt * 4.0)
	_check_obstacles()
	if state != State.RIDING:
		return
	land_comp = move_toward(land_comp, 0.0, dt * 2.5)
	sketchy_t = maxf(sketchy_t - dt, 0.0)
	_ground_fx(dt, lat)
	# Pose.
	var toe := lean if not switch_stance else -lean
	_set_weights({
		toe = clampf(toe, 0.0, 1.0) * (0.6 + 0.4 * minf(spd / 20.0, 1.0)),
		heel = clampf(-toe, 0.0, 1.0) * (0.6 + 0.4 * minf(spd / 20.0, 1.0)),
		crouch = charge,
		speed = 1.0 if tucking else 0.0,
		brake = 1.0 if braking else 0.0,
		land = land_comp,
	})
	model.flail = sketchy_t / 0.8
	model.breathe = 0.25


func _ground_fx(dt: float, lat: Vector3) -> void:
	var spd := vel.length()
	if tracks:
		tracks.add(position, fwd, normal, lean if not switch_stance else -lean, now())
	if powder == null or spd < 4.0:
		return
	var amount := absf(lean) * spd * 0.55 + (spd * 0.8 if braking else 0.0)
	var n := int(amount * dt * 4.0 + randf())
	var side := signf(lean) if absf(lean) > 0.05 else 0.0
	for k in n:
		var out := lat * side if side != 0.0 else lat * (1.0 if randf() < 0.5 else -1.0)
		var p := position + out * 0.25 + Vector3(0, 0.1, 0) - fwd * randf_range(-0.6, 0.6)
		var v := out * spd * randf_range(0.12, 0.28) + normal * randf_range(1.0, 3.0) + vel * 0.35
		if braking:
			v += fwd * spd * 0.25
		powder.emit(p, v, randf_range(0.25, 0.55), randf_range(0.4, 0.9))


func _take_off(from_lip: bool) -> void:
	state = State.AIR
	air_time = 0.0
	since_takeoff = 0.0
	flip = 0.0
	spin = 0.0
	flip_vel = 0.0
	spin_vel = 0.0
	air_up = normal
	from_ramp = from_lip
	max_air_height = 0.0
	var hv := Vector3(vel.x, 0, vel.z)
	air_head = fwd if hv.length() < 1.0 else fwd
	_last_trick = ""
	_grab_seen = ""
	# Unplanned air (rolling off a lip or roller without popping): inputs that
	# were already held for carving or tucking don't start a spin or flip until
	# they are released and pressed again. A deliberate pop allows pre-winding.
	var i := _inp()
	grab_l = false
	grab_r = false
	grab_time = 0.0
	# RT is both jump and right grab: it only grabs after it's been let go.
	_grab_armed = not i.jump
	_spin_locked = not _popped and absf(i.steer) > 0.1
	_pitch_locked = not _popped and (i.forward or i.back)
	_popped = false
	took_off.emit()


# ------------------------------------------------------------------ air

func _air(dt: float) -> void:
	var i := _inp()
	air_time += dt
	since_takeoff += dt
	pop_t = maxf(pop_t - dt, 0.0)
	var jump: bool = i.jump
	if _jump_was and not jump and since_takeoff < lip_pop_window and from_ramp:
		vel.y += lip_pop_bonus + charge * ollie_charge_bonus * 0.5
		pop_t = 0.3
		charge = 0.0
		_spin_locked = false
		_pitch_locked = false
	_jump_was = jump
	vel.y -= gravity * dt
	position += vel * dt
	var gr := Mountain.ground(position.x, position.z)
	var gn := Vector3(gr.x, gr.y, gr.z)
	max_air_height = maxf(max_air_height, position.y - gr.w)
	# Rotation: hold to tuck and rotate, release to untuck and slow down.
	# Grabs: RT / K = right hand (Indy), LT / J = left hand (Melon), both = Japan.
	if not i.jump:
		_grab_armed = true
	grab_r = i.grab_r and _grab_armed
	grab_l = i.grab_l
	if grab_l or grab_r:
		grab_time += dt
	var pitch_in := (1.0 if i.back else 0.0) - (1.0 if i.forward else 0.0)
	var spin_in: float = i.steer
	if _spin_locked:
		if absf(spin_in) < 0.1:
			_spin_locked = false
		spin_in = 0.0
	if _pitch_locked:
		if absf(pitch_in) < 0.1:
			_pitch_locked = false
		pitch_in = 0.0
	var acc := deg_to_rad(rotation_accel_deg) * dt
	var dec := deg_to_rad(untuck_decay_deg) * dt
	if absf(pitch_in) > 0.1:
		flip_vel = move_toward(flip_vel, pitch_in * deg_to_rad(flip_speed_deg), acc)
	else:
		flip_vel = move_toward(flip_vel, 0.0, dec)
	if absf(spin_in) > 0.1:
		spin_vel = move_toward(spin_vel, -spin_in * deg_to_rad(spin_speed_deg), acc)
	else:
		spin_vel = move_toward(spin_vel, 0.0, dec)
	flip += flip_vel * dt
	spin += spin_vel * dt
	var assist := deg_to_rad(land_assist_deg)
	if absf(flip_vel) < 0.5:
		var r := wrapf(flip, -PI, PI)
		if absf(r) < assist:
			flip -= r * minf(1.0, 3.5 * dt)
	if absf(spin_vel) < 0.5:
		var r := wrapf(spin, -PI * 0.5, PI * 0.5)
		if absf(r) < assist * 0.7:
			spin -= r * minf(1.0, 3.5 * dt)
	# Neutral attitude eases toward the slope below so a plain air lands flat.
	air_up = air_up.slerp(gn, 1.0 - exp(-2.2 * dt)).normalized()
	var hv := Vector3(vel.x, 0, vel.z)
	if hv.length() > 1.0:
		air_head = air_head.slerp(hv.normalized(), 1.0 - exp(-2.0 * dt)).normalized()
	var t := trick_name(false)
	if t != _last_trick:
		_last_trick = t
		trick_changed.emit(t)
	var rot01 := clampf(absf(flip_vel) / deg_to_rad(flip_speed_deg) + absf(spin_vel) / deg_to_rad(spin_speed_deg) * 0.6, 0.0, 1.0)
	var gw := 1.0 if (grab_l or grab_r) else 0.0
	_set_weights({air = (1.0 - rot01) * (1.0 - gw), tuck = rot01 * (1.0 - gw * 0.6), pop = 1.0 if pop_t > 0.15 else 0.0,
		grab_r = 1.0 if grab_r else 0.0, grab_l = 1.0 if grab_l else 0.0})
	model.flail = 0.0
	_check_obstacles()
	if state != State.AIR:
		return
	if position.y <= gr.w:
		position.y = gr.w
		_land(gn)


func _land(n: Vector3) -> void:
	var b := _air_basis()
	var up := b.y
	var tilt := rad_to_deg(up.angle_to(n))
	var bx := (b.x - n * b.x.dot(n)).normalized()
	var vp := vel - n * vel.dot(n)
	var spin_err := 0.0
	if vp.length() > 1.0:
		spin_err = rad_to_deg(acos(clampf(absf(bx.dot(vp.normalized())), 0.0, 1.0)))
	var impact := -vel.dot(n)
	var quality := "clean"
	if tilt > sketchy_tilt_deg or spin_err > sketchy_spin_deg or impact > max_impact_speed:
		quality = "crash"
	elif tilt > clean_tilt_deg or spin_err > clean_spin_deg or impact > max_impact_speed * 0.8 or grab_l or grab_r:
		# Still holding a grab at touchdown is sketchy, like in Steep.
		quality = "sketchy"
	var result := trick_result()
	result.quality = quality
	result.impact = impact
	result.tilt = tilt
	result.spin_err = spin_err
	result.position = position
	if quality == "crash" and not invincible:
		normal = n
		_crash_start("Bad landing" if impact <= max_impact_speed else "Landed too hard")
		result.points = 0
		landed.emit(result)
		return
	# Touch down: keep the board pointing the way it actually landed.
	if bx.length() > 0.1:
		fwd = bx if bx.dot(vp) >= 0.0 else -bx
		if bx.dot(vp) < 0.0:
			switch_stance = not switch_stance
	# The landed visual must not jump: rebuild the smoothed quaternion target.
	normal = n
	vel = vp * (1.0 - clampf((impact - 6.0) / 40.0, 0.0, 0.3))
	if quality == "sketchy":
		vel *= 0.75
		sketchy_t = 0.8
	land_comp = clampf(impact / 12.0, 0.35, 1.0)
	flip = 0.0
	spin = 0.0
	state = State.RIDING
	_jump_was = false
	if powder:
		var count := 14 + int(impact * 1.5)
		powder.burst(position, n, count, 2.0 + impact * 0.25, 0.5)
	landed.emit(result)


## Trick being performed (or just performed). Spins counted in 180s.
func trick_result() -> Dictionary:
	var flips := int(roundf(absf(flip) / TAU))
	var spins := int(roundf(absf(spin) / PI))
	var name := trick_name(true)
	var pts := 0
	if air_time > 0.45:
		pts += int(air_time * 60.0)
	pts += spins * 120
	pts += flips * 500
	if grab_time >= 0.25:
		pts += 150 + int(grab_time * 200.0)
	if flips > 0 and spins > 0:
		pts = int(pts * 1.5)
	return {name = name, flips = flips, spins = spins, air = air_time, points = pts,
		backflip = flip > 0.0}


func trick_name(final: bool) -> String:
	var f := absf(flip)
	var s := absf(spin)
	var flips := int(roundf(f / TAU)) if final else int(floorf((f + deg_to_rad(50.0)) / TAU))
	var spins := int(roundf(s / PI)) if final else int(floorf((s + deg_to_rad(35.0)) / PI))
	var parts := []
	if flips > 0:
		var fname := "Backflip" if flip > 0.0 else "Frontflip"
		parts.append(["", "", "Double ", "Triple ", "Quad "][mini(flips, 4)] + fname)
	if spins > 0:
		parts.append(str(spins * 180))
	var g := grab_name()
	if g != "":
		parts.append(g)
	if parts.is_empty():
		if air_time > 1.1 or max_air_height > 2.5:
			return "Big Air"
		if air_time > 0.45:
			return "Ollie" if not from_ramp else "Air"
		return ""
	if switch_stance and spins == 0:
		parts.push_front("Switch")
	return " ".join(parts)


var _grab_seen := ""

## The grab you've been holding this air (kept after you let go).
func grab_name() -> String:
	if grab_l and grab_r:
		_grab_seen = "Japan"
	elif grab_r and _grab_seen == "":
		_grab_seen = "Indy"
	elif grab_l and _grab_seen == "":
		_grab_seen = "Melon"
	return _grab_seen if grab_time >= 0.25 or (grab_l or grab_r) else ""


# ------------------------------------------------------------------ collisions & crash

func _check_obstacles() -> void:
	for o in Mountain.obstacles_near(position.x, position.z):
		var d := Vector2(position.x - o.pos.x, position.z - o.pos.z)
		var rr: float = o.r + body_radius
		if d.length() < rr and position.y < o.pos.y + o.top and position.y + 1.6 > o.pos.y - 0.3:
			var hv := Vector2(vel.x, vel.z)
			var into := -hv.dot(d.normalized())
			if into > crash_into_speed and not invincible:
				_crash_start("Hit a tree" if o.kind == Mountain.Kind.TREE else "Hit a rock")
				vel *= 0.25
				return
			# Glancing hit: stumble (lose speed, wobble) and slide along it.
			var dn := d.normalized()
			if into > safe_bump_speed:
				vel *= 1.0 - bump_speed_loss * clampf(into / crash_into_speed, 0.3, 1.0)
				sketchy_t = 0.8
				if powder:
					powder.burst(position + Vector3(0, 1.0, 0), Vector3.UP, 12, 3.0, 0.5)
			position.x = o.pos.x + dn.x * rr
			position.z = o.pos.z + dn.y * rr
			var v2 := Vector2(vel.x, vel.z)
			v2 -= dn * minf(v2.dot(dn), 0.0)
			vel.x = v2.x
			vel.z = v2.y


func _crash_start(reason: String) -> void:
	state = State.CRASHED
	crash_t = 0.0
	crash_spin = Vector3(randf_range(-2, 2), randf_range(-3, 3), randf_range(2, 4))
	_set_weights({crash = 1.0})
	model.flail = 0.0
	if powder:
		powder.burst(position + Vector3(0, 0.5, 0), Vector3.UP, 40, 5.0, 0.7)
	crashed.emit(reason)


func _crash(dt: float) -> void:
	crash_t += dt
	vel.y -= gravity * dt
	position += vel * dt
	var gr := Mountain.ground(position.x, position.z)
	if position.y <= gr.w:
		position.y = gr.w
		normal = Vector3(gr.x, gr.y, gr.z)
		vel -= normal * minf(vel.dot(normal), 0.0)
		var spd := vel.length()
		if spd > 0.01:
			vel = vel / spd * maxf(spd - 9.0 * dt, 0.0)
		if powder and spd > 2.0 and randf() < 0.6:
			powder.emit(position + Vector3(0, 0.2, 0), Vector3(randf_range(-1, 1), 2, randf_range(-1, 1)) + vel * 0.3, 0.5, 0.8)
	_set_weights({crash = 1.0})


func _set_weights(w: Dictionary) -> void:
	for k in model.weights:
		model.weights[k] = w.get(k, 0.0)


## Predicts where an airborne rider will touch down (for the camera).
func predict_landing() -> Vector3:
	var p := position
	var v := vel
	for k in 40:
		v.y -= gravity * 0.08
		p += v * 0.08
		if p.y <= Mountain.height(p.x, p.z):
			return p
	return p
