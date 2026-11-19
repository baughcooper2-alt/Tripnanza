extends Node3D
## Game flow: SUMMIT (menu) -> INTRO (mushroom, hand plant, pop up, drop in;
## one continuous shot) -> RIDING -> WIPEOUT -> Ride Again -> INTRO ...
## Each system lives on its own node; this script only wires them together.

enum Flow { SUMMIT, INTRO, RIDING, WIPEOUT }

@export var wipeout_card_delay := 1.1
@export var wind_powder_rate := 26.0
@export_range(5.0, 60.0) var sun_elevation_deg := 21.0   ## low sun = long blue shadows
@export_range(-180.0, 180.0) var sun_azimuth_deg := 62.0

@onready var rider: Rider = $Rider
@onready var cam: CameraRig = $CameraRig
@onready var terrain: TerrainStreamer = $Terrain
@onready var backdrop: Backdrop = $Backdrop
@onready var trip: TripDirector = $TripDirector
@onready var encounters: Encounters = $Encounters
@onready var blinkers: BlinkerManager = $Blinkers
@onready var score: ScoreKeeper = $Score
@onready var ui: GameUI = $UI
@onready var post_rect: ColorRect = $PostFX/Trip
@onready var sun: DirectionalLight3D = $Sun
@onready var powder: Powder = $Powder
@onready var tracks: Tracks = $Tracks
@onready var compositor: TripCompositor = $Compositor
@onready var apparitions: Apparitions = $Apparitions

var flow := Flow.SUMMIT
var paused := false
var _crash_reason := ""
var _crash_timer := -1.0
var _restarting := false
var _restart_hold := 0.0
var photo := false
@export var restart_hold_time := 0.6


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var el := deg_to_rad(sun_elevation_deg)
	var az := deg_to_rad(sun_azimuth_deg)
	var to_sun := Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az))
	sun.basis = Basis.looking_at(-to_sun, Vector3.UP)
	terrain.terrain_material.set_shader_parameter("sun_dir", to_sun)
	for n in [rider, cam, terrain, trip, encounters, blinkers, powder, tracks, backdrop, apparitions]:
		n.process_mode = Node.PROCESS_MODE_PAUSABLE
	rider.powder = powder
	rider.tracks = tracks
	tracks.terrain_material = terrain.terrain_material
	cam.rider = rider
	trip.rider = rider
	trip.camera_rig = cam
	trip.encounters = encounters
	trip.post = post_rect.material
	compositor.setup(cam.camera, post_rect.material)
	trip.compositor = compositor
	apparitions.rider = rider
	apparitions.trip = trip
	blinkers.rider = rider
	blinkers.tracks = tracks
	rider.control_started.connect(_on_control)
	rider.trick_changed.connect(ui.set_trick)
	rider.landed.connect(_on_landed)
	rider.crashed.connect(_on_crashed)
	blinkers.crossed.connect(_on_blinker)
	score.trick_banked.connect(ui.bank_trick)
	score.trick_banked.connect(func(_n, _p, q): Audio.play("trick_clean" if q == "clean" else "trick_sketchy", 0.7))
	trip.phase_changed.connect(func(p): if p != "Sober" and flow == Flow.RIDING: Audio.play("phase", 0.6))
	ui.start_pressed.connect(start_run)
	ui.ride_again_pressed.connect(ride_again)
	ui.menu_pressed.connect(to_summit_menu)
	ui.resume_pressed.connect(func(): _set_paused(false))
	_reset_world()
	ui.show_menu()
	if Settings.args.has("scenario"):
		var pt: Node = load("res://scripts/debug/playtest.gd").new()
		pt.set("main", self)
		pt.set("rider", rider)
		pt.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(pt)
	if Settings.args.has("autostart"):
		start_run.call_deferred()


func _reset_world() -> void:
	Mountain.reset_world()
	encounters.clear_all()
	apparitions.clear_all()
	powder.clear()
	tracks.clear()
	rider.reset_to_summit()
	terrain.set_focus(rider.global_position, Vector3(0, 0, 1))
	terrain.build_now(2)
	cam.set_menu_mode()
	trip.reset()
	score.reset()
	blinkers.reset()
	flow = Flow.SUMMIT
	_crash_timer = -1.0
	Audio.set_muffled(false)


func start_run() -> void:
	if flow != Flow.SUMMIT:
		return
	ui.hide_menu()
	Audio.play("start", 0.6)
	Audio.set_muffled(false)
	flow = Flow.INTRO
	rider.begin_intro()
	cam.begin_transition()
	trip.start()
	ui.show_hud()


func ride_again() -> void:
	if _restarting:
		return
	_restarting = true
	_set_paused(false)
	Audio.play("wipe", 0.6)
	ui.powder_wipe(func():
		_reset_world()
		ui.hide_menu()
		start_run()
		_restarting = false)


func to_summit_menu() -> void:
	if _restarting:
		return
	_restarting = true
	_set_paused(false)
	ui.powder_wipe(func():
		_reset_world()
		ui.show_menu()
		_restarting = false)


func _set_paused(on: bool) -> void:
	paused = on
	Audio.set_muffled(on)
	get_tree().paused = on
	ui.show_pause(on)


func _unhandled_input(e: InputEvent) -> void:
	if photo:
		if e.is_action_pressed("photo_mode") or e.is_action_pressed("pause") or _is_photo_combo(e):
			_set_photo(false)
			get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("photo_mode") or _is_photo_combo(e):
		if flow == Flow.RIDING or flow == Flow.WIPEOUT:
			_set_photo(true)
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("camera") and not paused:
		ui.toast("Camera: " + cam.cycle_preset())
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("bail") and flow == Flow.RIDING and not paused:
		rider.bail()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("restart") and flow == Flow.WIPEOUT and _crash_timer < 0.0:
		ride_again()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("pause"):
		if flow == Flow.RIDING or flow == Flow.INTRO:
			_set_paused(not paused)
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("ride_again") and flow == Flow.WIPEOUT and _crash_timer < 0.0:
		ride_again()
		get_viewport().set_input_as_handled()


## Photo mode (Steep: click both sticks). Freezes the run, hides the HUD and
## lets you orbit the camera.
func _set_photo(on: bool) -> void:
	photo = on
	get_tree().paused = on
	cam.set_photo_mode(on)
	ui.visible = not on


func _is_photo_combo(e: InputEvent) -> bool:
	if e is InputEventJoypadButton and e.pressed:
		var l := Input.is_joy_button_pressed(e.device, JOY_BUTTON_LEFT_STICK)
		var r := Input.is_joy_button_pressed(e.device, JOY_BUTTON_RIGHT_STICK)
		return l and r
	return false


func _on_control() -> void:
	flow = Flow.RIDING


func _on_landed(r: Dictionary) -> void:
	if r.quality == "crash":
		ui.clear_trick()
		return
	score.on_landed(r)
	if r.name == "":
		ui.clear_trick()
	if r.flips > 0 or r.spins >= 2:
		# A landed trick sends a wave of colour downhill across the snow.
		RenderingServer.global_shader_parameter_set("wave_origin", r.position)
		RenderingServer.global_shader_parameter_set("wave_time", TripDirector.now)
	if r.impact > 10.0:
		cam.shake(clampf(r.impact / 25.0, 0.0, 0.8))


func _on_blinker(index: int, bonus: int) -> void:
	score.on_blinker(index, bonus)
	trip.on_blinker(index)
	ui.bank_blinker("BLINKER %d" % index, bonus, trip.phase)
	Audio.play("blinker", 0.8)
	Audio.rumble(0.4, 0.2, 0.25)
	print("[game] blinker %d crossed at z=%.1f" % [index, rider.global_position.z])


func _on_crashed(reason: String) -> void:
	flow = Flow.WIPEOUT
	_crash_reason = reason
	_crash_timer = wipeout_card_delay
	Audio.set_muffled(true)
	cam.shake(0.9)
	ui.clear_trick()
	print("[game] wipeout: %s at %.0f m, score %d" % [reason, score.distance, score.total()])


func _process(dt: float) -> void:
	if paused or photo:
		return
	# Steep: hold Y (or R) to restart the run from the summit.
	if Input.is_action_pressed("restart") and (flow == Flow.RIDING or flow == Flow.INTRO):
		_restart_hold += dt
		if _restart_hold >= restart_hold_time:
			_restart_hold = -10.0
			ride_again()
	else:
		_restart_hold = 0.0
	var rp := rider.global_position
	terrain.set_focus(rp, rider.cam_heading)
	backdrop.follow(rp)
	sun.global_position = rp
	if flow == Flow.RIDING:
		score.update_distance(rp.z)
	if flow == Flow.RIDING or flow == Flow.INTRO:
		ui.update_hud(score.total(), score.distance, blinkers.next_index, blinkers.next_z() - rp.z, blinkers.interval, trip.phase)
	if _crash_timer >= 0.0:
		_crash_timer -= dt
		if _crash_timer < 0.0:
			var best := Settings.submit_run(score.total(), score.distance, score.best_trick, score.best_trick_points)
			ui.show_wipeout(_crash_reason, score.total(), score.distance, score.best_trick, best)
	_wind(dt)


## Powder blowing past on the wind (strongest at the summit).
func _wind(dt: float) -> void:
	var rate := wind_powder_rate * (1.0 if flow == Flow.SUMMIT or flow == Flow.INTRO else 0.35)
	var n := int(rate * dt + randf())
	var base := rider.global_position
	for i in n:
		var p := base + Vector3(randf_range(-12, 6), randf_range(0.0, 3.5), randf_range(-8, 14))
		var v := Vector3(randf_range(3.5, 6.5), randf_range(-0.2, 0.6), randf_range(-1.0, 1.0)) + rider.vel * 0.6
		powder.emit(p, v, randf_range(0.08, 0.2), randf_range(1.2, 2.2), Color(1, 1, 1, 0.55))
