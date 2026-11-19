class_name CameraRig
extends Node3D
## Elevated chase camera. It follows the rider's *travel direction* (never the
## board's rotation), so it can't roll or flip. The rider sits in the lower
## third and the camera frames the predicted landing while airborne.
## The summit menu shot blends into the gameplay shot without a cut.

@export_group("Gameplay framing")
@export_range(10.0, 80.0) var pitch_deg := 38.0          ## camera elevation angle above the rider
@export var distance := 10.5
@export var fov := 60.0
@export var fov_at_speed := 70.0
@export var speed_for_fov := 32.0
@export_range(0.5, 0.85) var rider_screen_y := 0.68      ## 0.5 = centre, 0.67 = lower third
@export var look_ahead := 3.0
@export var follow_rate := 7.0
@export var air_pull_back := 0.4                         ## extra distance per metre of air
@export var crash_pitch_deg := 74.0
@export_group("Summit menu shot")
@export var menu_offset := Vector3(5.2, 5.6, -6.5)       ## relative to the rider at the summit
@export var menu_look_offset := Vector3(-3.0, -13.0, 26.0)
@export var menu_fov := 52.0
@export var transition_time := 2.6

var rider: Rider
var camera: Camera3D
var _blend := 0.0
var _transitioning := false
var _focus := Vector3.ZERO
var _pos := Vector3.ZERO
var _shake := 0.0
var _menu_sway := 0.0
## LB / C cycles these: [name, pitch, distance, fov].
@export var presets := [["Chase", 38.0, 10.5, 60.0], ["Close", 24.0, 6.5, 66.0], ["High", 58.0, 17.0, 54.0]]
var _preset := 0
var photo := false
var _photo_yaw := 0.0
var _photo_pitch := 0.4
var _photo_dist := 8.0


func _ready() -> void:
	camera = get_node_or_null("Camera3D")
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)
	camera.far = 6500.0
	camera.near = 0.15
	top_level = true


func cycle_preset() -> String:
	_preset = (_preset + 1) % presets.size()
	var p: Array = presets[_preset]
	pitch_deg = p[1]
	distance = p[2]
	fov = p[3]
	fov_at_speed = p[3] + 10.0
	return p[0]


func set_photo_mode(on: bool) -> void:
	photo = on
	process_mode = Node.PROCESS_MODE_ALWAYS if on else Node.PROCESS_MODE_PAUSABLE
	if on:
		var to_cam := global_position - rider.global_position
		_photo_yaw = atan2(to_cam.x, to_cam.z)
		_photo_dist = clampf(to_cam.length(), 3.0, 30.0)
		_photo_pitch = asin(clampf(to_cam.y / maxf(to_cam.length(), 0.01), -0.2, 1.4))


func _photo(dt: float) -> void:
	var look := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	look += Input.get_vector("steer_left", "steer_right", "lean_forward", "lean_back")
	if look.length() < 0.2:
		look = Vector2.ZERO
	_photo_yaw -= look.x * 1.6 * dt
	_photo_pitch = clampf(_photo_pitch - look.y * 1.2 * dt, -0.1, 1.45)
	var zoom := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	zoom += (1.0 if Input.is_key_pressed(KEY_E) else 0.0) - (1.0 if Input.is_key_pressed(KEY_Q) else 0.0)
	_photo_dist = clampf(_photo_dist - zoom * 8.0 * dt, 2.0, 40.0)
	var target := rider.global_position + Vector3(0, 0.9, 0)
	var off := Vector3(sin(_photo_yaw) * cos(_photo_pitch), sin(_photo_pitch), cos(_photo_yaw) * cos(_photo_pitch)) * _photo_dist
	var p := target + off
	p.y = maxf(p.y, Mountain.height(p.x, p.z) + 0.5)
	var xf := Transform3D(Basis.looking_at(target - p, Vector3.UP), p)
	global_transform = xf
	if camera.get_parent() != self:
		camera.global_transform = xf


func set_menu_mode() -> void:
	_blend = 0.0
	_transitioning = false
	_focus = rider.global_position
	_pos = _gameplay_position(_focus)
	_apply(0.0)


func begin_transition() -> void:
	_transitioning = true
	_focus = rider.global_position
	_pos = _gameplay_position(_focus)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _gameplay_position(focus: Vector3) -> Vector3:
	var h := rider.cam_heading
	var p := deg_to_rad(pitch_deg)
	var d := distance
	if rider.state == Rider.State.AIR:
		d += rider.max_air_height * air_pull_back
	elif rider.state == Rider.State.CRASHED:
		# Rise toward top-down so trees never hide the wipeout.
		p = deg_to_rad(lerpf(pitch_deg, crash_pitch_deg, minf(rider.crash_t * 1.5, 1.0)))
		d *= 0.85
	return focus - h * cos(p) * d + Vector3.UP * sin(p) * d


func _process(dt: float) -> void:
	if rider == null:
		return
	if photo:
		_photo(dt)
		return
	if _transitioning:
		_blend = minf(_blend + dt / transition_time, 1.0)
		if _blend >= 1.0:
			_transitioning = false
	_apply(dt)


func _apply(dt: float) -> void:
	var rp := rider.global_position
	var target_focus := rp + rider.cam_heading * look_ahead
	if rider.state == Rider.State.AIR:
		# Keep the touchdown in view during flips.
		var land := rider.predict_landing()
		target_focus = rp.lerp(land, 0.2) + rider.cam_heading * look_ahead * 0.5
		target_focus.y = lerpf(rp.y, land.y, 0.3)
	var k := 1.0 - exp(-follow_rate * dt) if dt > 0.0 else 1.0
	_focus = _focus.lerp(target_focus, k)
	var want := _gameplay_position(_focus)
	_pos = _pos.lerp(want, k)
	# Stay above the snow.
	var gy := Mountain.height(_pos.x, _pos.z) + 2.0
	if _pos.y < gy:
		_pos.y = gy
	var spd01 := clampf(rider.speed / speed_for_fov, 0.0, 1.0)
	var game_fov := lerpf(fov, fov_at_speed, spd01)
	# Aim so the focus lands at rider_screen_y (lower third).
	var game_basis := Basis.looking_at(_focus - _pos, Vector3.UP)
	var off := atan(tan(deg_to_rad(game_fov) * 0.5) * (rider_screen_y - 0.5) * 2.0)
	game_basis = game_basis * Basis(Vector3.RIGHT, off)
	var game_xf := Transform3D(game_basis, _pos)
	# Summit menu shot (gentle handheld drift).
	_menu_sway += dt
	var start := Vector3(0, Mountain.ground(0, 0).w, 0)
	var mpos := start + menu_offset + Vector3(sin(_menu_sway * 0.3) * 0.15, sin(_menu_sway * 0.23) * 0.08, 0)
	var mxf := Transform3D(Basis.looking_at(start + menu_look_offset - mpos, Vector3.UP), mpos)
	var b := smoothstep(0.0, 1.0, _blend)
	b = b * b * (3.0 - 2.0 * b)
	var xf := mxf.interpolate_with(game_xf, b)
	if _shake > 0.001:
		xf.origin += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.15
		_shake = maxf(_shake - dt * 2.0, 0.0)
	global_transform = xf
	if camera.get_parent() != self:
		camera.global_transform = xf   # camera lives in the compositor's WorldView
	camera.fov = lerpf(menu_fov, game_fov, b)


## Screen position of the rider (0..1), used to centre the protected window.
func rider_screen_uv() -> Vector2:
	var vp := camera.get_viewport().get_visible_rect().size
	var p := camera.unproject_position(rider.global_position + Vector3(0, 0.8, 0))
	return Vector2(p.x / vp.x, p.y / vp.y)
