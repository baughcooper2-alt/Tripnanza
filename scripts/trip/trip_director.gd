class_name TripDirector
extends Node
## Owns trip intensity. Overall intensity climbs with survival time (an
## editable Curve) and steps up at every blinker; individual effects ride
## their own slow waves on top so they rise and fall independently.
## Everything is pushed to the global shader uniforms each frame.

signal phase_changed(phase: String)

## Shared clock for shaders / tracks (seconds, never paused by gameplay).
static var now := 0.0

@export var intensity_over_time: Curve       ## x: 0..1 of `ramp_seconds`, y: base intensity
@export var ramp_seconds := 240.0            ## survival time that maps to the end of the curve
@export var blinker_step := 0.035            ## permanent boost per blinker crossed
@export var blinker_pulse := 0.16            ## temporary surge after a blinker
@export var pulse_decay := 0.18              ## per second
@export_range(0.0, 2.0) var strength := 1.0  ## global multiplier (also set from Settings)
@export var preview_intensity := -1.0        ## >= 0 forces an intensity (testing in the editor)
@export_group("Encounters")
@export var encounter_from := 0.5            ## deep trip starts here
@export var encounter_gap := Vector2(16.0, 26.0)  ## seconds of breathing room between encounters

## False-colour palettes (dark -> light), one per reference. The trip starts on
## the first and moves to the next at every BLINKER, cross-fading over a few seconds.
const PALETTES := {
	"Dusk Smear": [Color(0.15, 0.13, 0.12), Color(0.1, 0.48, 0.5), Color(0.95, 0.45, 0.2), Color(1.0, 0.55, 0.7), Color(1.0, 0.88, 0.75)],
	"Infrared": [Color(0.08, 0.05, 0.3), Color(0.45, 0.1, 0.55), Color(0.95, 0.15, 0.5), Color(1.0, 0.5, 0.15), Color(1.0, 0.93, 0.55)],
	"Cyan Forest": [Color(0.03, 0.04, 0.15), Color(0.1, 0.35, 0.6), Color(0.15, 0.85, 0.85), Color(1.0, 0.35, 0.35), Color(0.85, 0.8, 1.0)],
	"Paint By Number": [Color(0.08, 0.08, 0.45), Color(0.45, 0.15, 0.75), Color(0.95, 0.25, 0.55), Color(1.0, 0.6, 0.15), Color(1.0, 0.95, 0.4)],
	"Net Of Being": [Color(0.2, 0.02, 0.05), Color(0.7, 0.08, 0.08), Color(0.95, 0.45, 0.2), Color(0.98, 0.85, 0.65), Color(0.6, 0.8, 1.0)],
}

const PHASES := [[0.0, "Sober"], [0.06, "Onset"], [0.3, "Rising"], [0.55, "Deep"], [0.8, "Peak"]]

var rider: Rider
var camera_rig: CameraRig
var post: ShaderMaterial
var encounters: Node
var active := false
var survival := 0.0
var intensity := 0.0
var bonus := 0.0
var pulse := 0.0
var phase := "Sober"
var levels := {}
var _gap := 12.0
var _enc_index := 0
var _hue := 0.0
var compositor: TripCompositor
var palette_name := "Dusk Smear"
var _pal_from := "Dusk Smear"
var _pal_mix := 1.0
var _pal_index := 0


func _ready() -> void:
	if intensity_over_time == null:
		intensity_over_time = Curve.new()
		for p in [Vector2(0, 0), Vector2(0.08, 0.06), Vector2(0.25, 0.3), Vector2(0.5, 0.55), Vector2(0.78, 0.8), Vector2(1, 1)]:
			intensity_over_time.add_point(p)
	if Settings.args.has("trip-offset"):
		survival = float(Settings.args["trip-offset"])


func reset() -> void:
	active = false
	survival = float(Settings.args.get("trip-offset", "0"))
	bonus = 0.0
	pulse = 0.0
	intensity = 0.0
	phase = "Sober"
	phase_changed.emit(phase)
	_pal_index = 0
	palette_name = PALETTES.keys()[0]
	_pal_from = palette_name
	_pal_mix = 1.0
	_gap = 10.0
	if Settings.args.has("encounter_gap"):
		# Test hook: bring encounters closer together.
		_gap = 2.0
		var g := float(Settings.args["encounter_gap"])
		encounter_gap = Vector2(g, g)
	_enc_index = 0
	if encounters:
		encounters.clear_all()


func start() -> void:
	active = true


func on_blinker(index: int) -> void:
	bonus += blinker_step
	pulse = blinker_pulse
	next_palette()
	_gap = minf(_gap, 4.0)


## Cross-fade to the next reference palette (each blinker = a different trip).
func next_palette() -> void:
	_pal_index = (_pal_index + 1) % PALETTES.size()
	_pal_from = palette_name
	palette_name = PALETTES.keys()[_pal_index]
	_pal_mix = 0.0


func base_intensity() -> float:
	return intensity_over_time.sample(clampf(survival / ramp_seconds, 0.0, 1.0))


func _process(dt: float) -> void:
	now += dt
	if active and rider and rider.is_controllable():
		survival += dt
	pulse = maxf(pulse - pulse_decay * dt, 0.0)
	var target := clampf(base_intensity() + bonus + pulse, 0.0, 1.0)
	if preview_intensity >= 0.0:
		target = preview_intensity
	if not active and preview_intensity < 0.0:
		target = 0.0
	intensity = lerpf(intensity, target, 1.0 - exp(-1.5 * dt))
	var reduced := Settings.reduced_effects
	var s := strength * Settings.trip_strength * (0.4 if reduced else 1.0)
	var I := intensity
	_hue += dt * (0.01 + I * 0.03)
	# Individual effects: each fades in over its own band of intensity and
	# breathes on its own slow wave so they rise and fall independently.
	levels = {
		grain = _band(I, 0.03, 0.25) * _wave(0.11, 0.0, 0.5),
		breathe = _band(I, 0.05, 0.3) * _wave(0.07, 1.3, 0.4),
		echo = _band(I, 0.05, 0.25) * _wave(0.09, 2.0, 0.35),
		contour = _band(I, 0.25, 0.5) * _wave(0.06, 0.7, 0.45),
		ribbons = _band(I, 0.28, 0.55) * _wave(0.05, 3.1, 0.5),
		fold = _band(I, 0.3, 0.6) * _wave(0.045, 4.2, 0.5),
		marble = _band(I, 0.5, 0.95) * _wave(0.035, 5.0, 0.35),
		warp = _band(I, 0.55, 1.0) * _wave(0.03, 0.2, 0.3),
		sky = _band(I, 0.4, 0.9) * _wave(0.02, 1.0, 0.25),
		eyes = _band(I, 0.45, 0.85) * _wave(0.03, 1.7, 0.5) * (0.3 if reduced else 1.0),
	}
	for k in levels:
		levels[k] *= s
	var split := 0.0
	if encounters:
		split = encounters.peak_split
	RenderingServer.global_shader_parameter_set("trip_intensity", I * s)
	RenderingServer.global_shader_parameter_set("trip_time", now)
	RenderingServer.global_shader_parameter_set("trip_hue", _hue)
	for k in levels:
		RenderingServer.global_shader_parameter_set("trip_" + k, levels[k])
	RenderingServer.global_shader_parameter_set("trip_split", split * s)
	if rider:
		RenderingServer.global_shader_parameter_set("rider_pos", rider.global_position)
		RenderingServer.global_shader_parameter_set("travel_dir", rider.cam_heading)
	_update_post(dt, I * s, reduced)
	_update_phase()
	_update_encounters(dt)


func _band(i: float, a: float, b: float) -> float:
	return smoothstep(a, b, i)


func _wave(freq: float, phase_off: float, depth: float) -> float:
	return 1.0 - depth * (0.5 + 0.5 * sin(now * TAU * freq + phase_off))


func _update_post(dt: float, I: float, reduced: bool) -> void:
	if post == null:
		return
	var spd01 := 0.0
	if rider:
		spd01 = clampf(rider.speed / 34.0, 0.0, 1.0)
	post.set_shader_parameter("kaleido", smoothstep(0.6, 1.0, I) * _wave(0.025, 2.4, 0.5) * (0.0 if reduced else 1.0))
	post.set_shader_parameter("echo", smoothstep(0.55, 0.95, I) * (0.5 + 0.5 * spd01))
	post.set_shader_parameter("melt", smoothstep(0.7, 1.0, I) * _wave(0.03, 1.1, 0.6))
	post.set_shader_parameter("aberration", smoothstep(0.3, 0.8, I))
	post.set_shader_parameter("speed01", spd01 * smoothstep(0.75, 1.0, I))
	post.set_shader_parameter("reduced", 1.0 if reduced else 0.0)
	# Reference-driven layers (see shaders/trip_post.gdshader).
	var s := Settings.trip_strength * strength
	var trail := _band(I, 0.3, 0.8) * _wave(0.05, 2.2, 0.4) * s * (0.0 if reduced else 1.0)
	post.set_shader_parameter("trail_amt", trail)
	if compositor:
		compositor.set_trail_keep(lerpf(0.55, 0.9, _band(I, 0.3, 1.0)) if trail > 0.01 else 0.0)
	post.set_shader_parameter("false_amt", _band(I, 0.12, 0.7) * _wave(0.04, 0.9, 0.3) * 0.9 * s * (0.5 if reduced else 1.0))
	post.set_shader_parameter("grain", _band(I, 0.3, 0.8) * 0.8 * s * (0.3 if reduced else 1.0))
	post.set_shader_parameter("poster_amt", _band(I, 0.55, 0.95) * _wave(0.03, 0.4, 0.6) * s * (0.0 if reduced else 1.0))
	post.set_shader_parameter("poster_levels", lerpf(12.0, 5.0, _band(I, 0.6, 1.0)))
	post.set_shader_parameter("unpainted", _band(I, 0.78, 1.0) * _wave(0.02, 3.0, 0.7) * (0.0 if reduced else 1.0))
	_pal_mix = minf(_pal_mix + dt / 4.0, 1.0)
	post.set_shader_parameter("pal_a", _pal_array(_pal_from))
	post.set_shader_parameter("pal_b", _pal_array(palette_name))
	post.set_shader_parameter("pal_mix", smoothstep(0.0, 1.0, _pal_mix))
	if camera_rig and rider:
		var uv := camera_rig.rider_screen_uv()
		var f: Vector2 = post.get_shader_parameter("focus")
		# The protected window covers the rider and the line ahead of them.
		var want := Vector2(uv.x, uv.y - 0.12)
		post.set_shader_parameter("focus", f.lerp(want, 1.0 - exp(-4.0 * dt)))
		post.set_shader_parameter("rider_uv", uv)


func _pal_array(name: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	for c in PALETTES[name]:
		out.append(Vector3(c.r, c.g, c.b))
	return out


func _update_phase() -> void:
	# Phases only move forward during a run (no flicker as a blinker surge fades).
	var p := "Sober"
	var cur := 0
	for i in PHASES.size():
		if PHASES[i][1] == phase:
			cur = i
	for i in PHASES.size():
		if intensity >= PHASES[i][0] and (i >= cur or not active):
			p = PHASES[i][1]
	if active and _phase_index(p) < cur:
		p = phase
	if p != phase:
		phase = p
		phase_changed.emit(p)


func _phase_index(p: String) -> int:
	for i in PHASES.size():
		if PHASES[i][1] == p:
			return i
	return 0


func _update_encounters(dt: float) -> void:
	if encounters == null or not active or rider == null or not rider.is_controllable():
		return
	if intensity < encounter_from or encounters.busy():
		return
	_gap -= dt
	if _gap > 0.0:
		return
	var kinds := ["tunnel", "garden", "peaks"]
	encounters.start(kinds[_enc_index % kinds.size()], rider, intensity)
	_enc_index += 1
	_gap = randf_range(encounter_gap.x, encounter_gap.y) * lerpf(1.0, 0.75, smoothstep(0.8, 1.0, intensity))
