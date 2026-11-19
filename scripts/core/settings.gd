extends Node
## Persistent player settings + personal best, and the default input map.
## Input actions are registered in code so they always exist; anything you
## add in Project Settings > Input Map with the same name takes precedence.

signal changed

const SAVE_PATH := "user://tripnanza.cfg"

var reduced_effects := false
var trip_strength := 1.0          # 0..1.5 multiplier on every trip effect
var fullscreen := false
var best_score := 0
var best_distance := 0.0
var best_trick := ""

## Command-line flags after "--" (used by the test harness / capture tools).
var args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var kv := s.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_register_inputs()
	load_settings()
	if args.has("reduced"):
		reduced_effects = true
	_apply_window()


func _register_inputs() -> void:
	# Controller layout follows Steep (Xbox): left stick steers and rotates in
	# the air, right stick brakes/tucks, RT jumps, RT/LT grab in the air.
	_action("steer_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("steer_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	# In the air: frontflip / backflip.
	_action("lean_forward", [KEY_W, KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_action("lean_back", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	# On the snow: tuck for speed / brake.
	_action("tuck", [KEY_W, KEY_UP], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_action("brake", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_action("jump", [KEY_SPACE], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_action("grab_right", [KEY_K], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_action("grab_left", [KEY_J], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_action("switch_stance", [KEY_Q], [], [])          # pad: push the sticks in opposite directions
	_action("restart", [KEY_R], [JOY_BUTTON_Y], [])     # hold to restart from the summit
	_action("camera", [KEY_C], [JOY_BUTTON_LEFT_SHOULDER], [])
	_action("photo_mode", [KEY_F], [], [])              # pad: click both sticks
	_action("bail", [KEY_X], [JOY_BUTTON_DPAD_UP], [])
	_action("ride_again", [KEY_ENTER], [JOY_BUTTON_A], [])
	_action("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START], [])


func _action(name: String, keys: Array, buttons: Array, axes: Array) -> void:
	if InputMap.has_action(name) and not InputMap.action_get_events(name).is_empty():
		return
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.25)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(name, e)
	for b in buttons:
		var j := InputEventJoypadButton.new()
		j.button_index = b
		InputMap.action_add_event(name, j)
	for ax in axes:
		var m := InputEventJoypadMotion.new()
		m.axis = ax[0]
		m.axis_value = ax[1]
		InputMap.action_add_event(name, m)


func load_settings() -> void:
	var c := ConfigFile.new()
	if c.load(SAVE_PATH) != OK:
		return
	reduced_effects = c.get_value("settings", "reduced_effects", reduced_effects)
	trip_strength = c.get_value("settings", "trip_strength", trip_strength)
	fullscreen = c.get_value("settings", "fullscreen", fullscreen)
	best_score = c.get_value("best", "score", best_score)
	best_distance = c.get_value("best", "distance", best_distance)
	best_trick = c.get_value("best", "trick", best_trick)


func save_settings() -> void:
	if args.has("no-save"):
		return
	var c := ConfigFile.new()
	c.set_value("settings", "reduced_effects", reduced_effects)
	c.set_value("settings", "trip_strength", trip_strength)
	c.set_value("settings", "fullscreen", fullscreen)
	c.set_value("best", "score", best_score)
	c.set_value("best", "distance", best_distance)
	c.set_value("best", "trick", best_trick)
	c.save(SAVE_PATH)


func set_reduced_effects(v: bool) -> void:
	reduced_effects = v
	save_settings()
	changed.emit()


func set_trip_strength(v: float) -> void:
	trip_strength = v
	save_settings()
	changed.emit()


func set_fullscreen(v: bool) -> void:
	fullscreen = v
	_apply_window()
	save_settings()
	changed.emit()


func _apply_window() -> void:
	if args.has("capture") or DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


## Returns true if this run beat the stored best score.
func submit_run(score: int, distance: float, trick: String, trick_points: int) -> bool:
	var is_best := score > best_score
	if is_best:
		best_score = score
	best_distance = maxf(best_distance, distance)
	if trick != "" and trick_points > 0 and (best_trick == "" or is_best):
		best_trick = trick
	save_settings()
	return is_best
