extends Node
## Automated playtest driver (only active with command-line flags):
##   godot --path . -- --scenario=first_minute --capture=/some/dir
##   godot --path . -- --scenario=long_run --capture=/some/dir --trip-offset=60
## It drives the rider through Rider.ai inputs, prints events and saves
## screenshots from the real gameplay camera.

var main: Node
var rider: Rider
var scenario := ""
var capture_dir := ""
var t := 0.0
var phase := "menu"
var _shots := {}
var _log_t := 0.0
var _ai := {steer = 0.0, forward = false, back = false, jump = false, grab_r = false, grab_l = false}
var _events := []
var _crash_target = null
var _retry_done := false
var _ramp_done := false
var _end_t := 1e9
var _flip_hold := 0.0
var _phase_t := 0.0


func _ready() -> void:
	scenario = Settings.args.get("scenario", "")
	capture_dir = Settings.args.get("capture", "")
	if capture_dir != "":
		DirAccess.make_dir_recursive_absolute(capture_dir)
	rider.landed.connect(func(r): _ev(("x=%.1f vel=%s " % [rider.position.x, rider.vel]) + "landed %s quality=%s pts=%d tilt=%.0f spin_err=%.0f impact=%.1f air=%.2fs" % [r.name, r.quality, r.points, r.tilt, r.spin_err, r.impact, r.air]))
	rider.took_off.connect(func(): _ev("takeoff x=%.1f z=%.1f vel=%s fwd=%s lean=%.2f ramp=%s" % [rider.position.x, rider.position.z, rider.vel, rider.fwd, rider.lean, rider.from_ramp]))
	rider.crashed.connect(func(reason): _ev("CRASH " + reason))
	main.blinkers.crossed.connect(func(i, b): _ev("BLINKER %d +%d" % [i, b]); _shot_once("blinker_%d" % i, 0.25))
	main.trip.phase_changed.connect(func(p): _ev("phase -> " + p))
	if scenario == "long_run":
		_end_t = float(Settings.args.get("duration", "150"))


func _ev(s: String) -> void:
	var line := "[t=%6.2f] %s" % [t, s]
	print(line)
	_events.append(line)


func _shot_once(name: String, delay := 0.0) -> void:
	if _shots.has(name):
		return
	_shots[name] = true
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	shot(name)


func shot(name: String) -> void:
	if capture_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [capture_dir, name])
	print("[shot] ", name)


func _process(dt: float) -> void:
	t += dt
	_phase_t += dt
	if scenario == "first_minute" and rider.state == Rider.State.CRASHED and phase in ["to_ramp", "air", "to_blinker", "ride_on"]:
		_ev("UNEXPECTED crash during " + phase + " at x=%.1f z=%.1f" % [rider.position.x, rider.position.z])
		_set_phase("wipeout")
	match scenario:
		"first_minute":
			_first_minute()
		"long_run":
			_long_run()
		"summit":
			if t > 2.0:
				_shot_once("summit_menu")
			if t > 3.0:
				get_tree().quit()
	if rider.state == Rider.State.AIR and phase != "air" and not (scenario == "long_run" and _ai.back):
		_ai.steer = 0.0
	_log_t += dt
	if _log_t > 2.0 and rider.is_controllable():
		_log_t = 0.0
		print("[state] t=%.1f z=%.1f x=%.1f speed=%.1f score=%d phase=%s I=%.2f chunks=%d fps=%d proc=%.1fms phys=%.1fms bot=%.1fms" % [t, rider.position.z, rider.position.x, rider.speed, main.score.total(), main.trip.phase, main.trip.intensity, main.terrain.get_child_count(), Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, bot_us / 1000.0])
	if t > _end_t:
		_finish()


func _finish() -> void:
	print("[done] events:")
	for e in _events:
		print("   ", e)
	get_tree().quit()


func _set_phase(p: String) -> void:
	phase = p
	_phase_t = 0.0
	_ev("phase " + p)


# --------------------------------------------------------------- first minute

func _first_minute() -> void:
	match phase:
		"menu":
			if t > 1.5:
				_shot_once("01_summit_menu")
			if t > 2.5:
				rider.ai = _ai
				main.start_run()
				_set_phase("intro")
		"intro":
			if _phase_t > 0.5:
				_shot_once("02_intro_mushroom")
			if _phase_t > 1.45:
				_shot_once("03_intro_handplant")
			if _phase_t > 2.05:
				_shot_once("04_intro_popup")
			if rider.state == Rider.State.RIDING:
				_set_phase("to_ramp")
		"to_ramp":
			_steer_to(Vector2(0.0, 72.0) if rider.position.z < 58.0 else Vector2(0.0, 140.0), 4.0)
			# Carve a little on the way so the screenshot shows an edge.
			if rider.position.z > 12 and rider.position.z < 18:
				_ai.steer = 0.75
				_shot_once("05_carving", 0.25)
			elif rider.position.z >= 18 and rider.position.z < 24:
				_ai.steer = -0.75
			_ai.jump = rider.position.z > 66.0
			if rider.position.z > 72.9 and rider.state == Rider.State.RIDING:
				_ai.jump = false
			if rider.state == Rider.State.AIR:
				_ai.jump = false
				_set_phase("air")
		"air":
			_ai.steer = 0.0
			# Backflip: hold, then release so the assist lands it clean.
			_ai.back = absf(rider.flip) < deg_to_rad(265.0)
			_ai.grab_r = rider.air_time > 0.25 and rider.air_time < 0.85
			if rider.flip > PI * 0.6:
				_shot_once("06_backflip_tuck")
			if rider.state != Rider.State.AIR:
				_ai.back = false
				_ai.grab_r = false
				_shot_once("07_landing", 0.15)
				_set_phase("to_blinker")
		"to_blinker":
			var gx: float = main.blinkers._gate.global_position.x if main.blinkers._gate else rider.position.x
			_avoid_steer(1.0, Vector2(gx, 150.0))
			if rider.position.z > 125:
				_shot_once("08_blinker_approach")
			if main.blinkers.next_index > 1 and _phase_t > 0.1:
				_set_phase("ride_on")
		"ride_on":
			_avoid_steer(1.0)
			if rider.state == Rider.State.AIR:
				_ai.steer = 0.0
			if _phase_t > 2.5:
				_shot_once("09_after_blinker")
			if Settings.args.has("stop_after_blinker") and _phase_t > 3.5:
				_finish()
			if _phase_t > 6.0:
				_set_phase("find_tree")
		"find_tree":
			if _crash_target == null:
				var best = null
				var bd := 1e9
				for dz in range(15, 60, 5):
					for o in Mountain.obstacles_near(rider.position.x, rider.position.z + dz):
						if o.kind == Mountain.Kind.TREE and o.pos.z > rider.position.z + 15:
							var d: float = absf(o.pos.x - rider.position.x) + (o.pos.z - rider.position.z) * 0.3
							if d < bd:
								bd = d
								best = o
				_crash_target = best
				if best:
					_ev("aiming at tree at %.1f,%.1f" % [best.pos.x, best.pos.z])
			if _crash_target:
				_steer_to(Vector2(_crash_target.pos.x, _crash_target.pos.z), 4.0)
			else:
				_avoid_steer(1.0)
			if rider.state == Rider.State.CRASHED:
				_shot_once("10_crash", 0.3)
				_set_phase("wipeout")
		"wipeout":
			if _phase_t > 1.8:
				_shot_once("11_wipeout_card")
			if _phase_t > 2.6:
				main.ride_again()
				_set_phase("retry")
		"retry":
			if _phase_t > 0.7:
				_shot_once("12_retry_intro")
			if rider.state == Rider.State.RIDING and _phase_t > 3.0:
				_shot_once("13_retry_riding")
				_ev("retry OK: rider riding again at z=%.1f" % rider.position.z)
				_finish()


# --------------------------------------------------------------- long run

func _long_run() -> void:
	match phase:
		"menu":
			if t > 0.5:
				rider.ai = _ai
				rider.invincible = Settings.args.has("invincible")
				main.start_run()
				_set_phase("ride")
		"ride":
			if rider.state == Rider.State.AIR:
				_ai.steer = 0.0
				_ai.back = int(t) % 20 < 10 and absf(rider.flip) < deg_to_rad(300)
			else:
				_ai.back = false
				_avoid_steer(1.0)
				# Occasionally ollie to show trick feedback.
				_ai.jump = fmod(t, 9.0) < 0.4
			var every := float(Settings.args.get("shot_every", "15"))
			var k := int(t / every)
			_shot_once("long_%03d" % k)
			if rider.state == Rider.State.CRASHED:
				_ev("crashed in long run at z=%.0f; restarting" % rider.position.z)
				_set_phase("restart")
		"restart":
			if _phase_t > 2.0:
				main.ride_again()
				_set_phase("ride")


# --------------------------------------------------------------- steering helpers

func _steer_to(target: Vector2, gain := 2.5) -> void:
	var p := Vector2(rider.position.x, rider.position.z)
	var d := (target - p)
	if d.y < 4.0:
		d.y = 4.0
	var want := Vector3(d.x, 0, d.y).normalized()
	_steer_dir(want, gain)


func _steer_dir(want: Vector3, gain: float) -> void:
	var h := Vector3(rider.vel.x, 0, rider.vel.z) if rider.speed > 2.0 else rider.fwd
	h.y = 0
	h = h.normalized()
	var c := h.cross(want).y
	_ai.steer = clampf(-c * gain, -1.0, 1.0)


var bot_us := 0.0
func _avoid_steer(gain: float, target = null) -> void:
	var _t0 := Time.get_ticks_usec()
	_avoid_inner(gain, target)
	bot_us = Time.get_ticks_usec() - _t0


func _avoid_inner(gain: float, target = null) -> void:
	var p := rider.position
	var best_dir := Vector3(0, 0, 1)
	var best_score := -1e9
	var aim := Vector3(0, 0, 1)
	if target != null:
		aim = Vector3(target.x - p.x, 0, maxf(target.y - p.z, 6.0)).normalized()
	for a in range(-60, 61, 6):
		var dir := aim.rotated(Vector3.UP, deg_to_rad(a))
		if dir.z < 0.35:
			continue
		var clear := 40.0
		for s in range(3, 40, 3):
			var q := p + dir * s
			for o in Mountain.obstacles_near(q.x, q.z):
				var dd: float = Vector2(q.x - o.pos.x, q.z - o.pos.z).length() - o.r
				if dd < 2.6:
					clear = minf(clear, float(s))
		var score := minf(clear, 30.0) - absf(a) * 0.08
		if score > best_score:
			best_score = score
			best_dir = dir
	_steer_dir(best_dir, 3.0 * gain)
	_ai.forward = best_score > 30.0
