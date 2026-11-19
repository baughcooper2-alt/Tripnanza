class_name GameUI
extends CanvasLayer
## All interface: summit menu, settings, HUD, trick + blinker feedback,
## pause and the wipeout card. Built in code so it is easy to restyle here.

signal start_pressed
signal ride_again_pressed
signal menu_pressed
signal resume_pressed

const WHITE := Color(1, 1, 1)
const INK := Color(0.08, 0.1, 0.2)
const ORANGE := Color(1.0, 0.42, 0.12)
const TEAL := Color(0.25, 0.95, 0.85)

var font: SystemFont
var menu: Control
var settings_panel: Control
var hud: Control
var wipeout: Control
var pause_panel: Control
var wipe_rect: ColorRect
var start_button: Button
var ride_button: Button
var best_label: Label

var score_label: Label
var dist_label: Label
var blinker_label: Label
var blinker_dist: Label
var bar_fill: ColorRect
var bar_back: ColorRect
var phase_label: Label
var trick_label: Label
var bank_label: Label
var check_label: Label
var wipe_title: Label
var wipe_stats: Label
var new_best: Label

var _shown_score := 0.0
var _target_score := 0
var _bar_rainbow := 0.0
const BANK_Y := 160.0


func _ready() -> void:
	layer = 10
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Avenir Next", "Futura", "Segoe UI", "Helvetica Neue", "Arial", "DejaVu Sans"])
	font.font_weight = 800
	_build_hud()
	_build_menu()
	_build_wipeout()
	_build_pause()
	wipe_rect = ColorRect.new()
	wipe_rect.color = Color(0.97, 0.98, 1.0, 0.0)
	wipe_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wipe_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wipe_rect)


# ------------------------------------------------------------------ helpers

func _label(text: String, size: int, col := WHITE, outline := 6) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = size
	ls.font_color = col
	ls.outline_size = outline
	ls.outline_color = Color(INK, 0.85)
	ls.shadow_color = Color(0, 0, 0, 0.25)
	ls.shadow_offset = Vector2(0, 3)
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, big := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 30 if big else 20)
	b.custom_minimum_size = Vector2(300 if big else 240, 64 if big else 46)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 22
		sb.content_margin_right = 22
		match st:
			"normal":
				sb.bg_color = ORANGE if big else Color(INK, 0.55)
			"hover", "focus":
				sb.bg_color = ORANGE.lightened(0.15) if big else Color(INK, 0.8)
				sb.border_color = WHITE
				sb.set_border_width_all(3)
			"pressed":
				sb.bg_color = ORANGE.darkened(0.2)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", WHITE)
	b.add_theme_color_override("font_focus_color", WHITE)
	b.add_theme_color_override("font_hover_color", WHITE)
	return b


# ------------------------------------------------------------------ menu

func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu)
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(INK, 0.55))
	grad.set_color(1, Color(INK, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.anchor_bottom = 1.0
	shade.anchor_right = 0.5
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(shade)
	var col := VBoxContainer.new()
	col.position = Vector2(64, 0)
	col.anchor_top = 0.0
	col.anchor_bottom = 1.0
	col.offset_top = 70
	col.offset_bottom = -40
	col.add_theme_constant_override("separation", 14)
	menu.add_child(col)
	var title := _label("TRIPNANZA", 76, WHITE, 10)
	col.add_child(title)
	var sub := _label("the mountain is starting to move", 20, Color(1, 0.9, 0.8), 4)
	col.add_child(sub)
	col.add_child(_spacer(26))
	start_button = _button("START RUN", true)
	start_button.pressed.connect(func(): start_pressed.emit())
	col.add_child(start_button)
	var sb := _button("SETTINGS")
	sb.pressed.connect(func(): _show_settings(true))
	col.add_child(sb)
	var qb := _button("QUIT")
	qb.pressed.connect(func(): get_tree().quit())
	col.add_child(qb)
	col.add_child(_spacer(10))
	best_label = _label("", 20, WHITE, 4)
	col.add_child(best_label)
	var help := _label("Controller (Steep layout): left stick steer / flip / spin · RT jump · RT/LT grab · right stick brake / tuck · LB camera · hold Y restart\nKeyboard: A/D carve · Space jump · W/S flip (air) or tuck/brake (snow) · J/K grab · Q switch · C camera · F photo · hold R restart · X bail", 14, Color(1, 1, 1, 0.85), 4)
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_left = 64
	help.offset_top = -78
	menu.add_child(help)
	_build_settings()


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _build_settings() -> void:
	settings_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(INK, 0.88)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(26)
	settings_panel.add_theme_stylebox_override("panel", sb)
	settings_panel.position = Vector2(64, 200)
	settings_panel.visible = false
	menu.add_child(settings_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	settings_panel.add_child(v)
	v.add_child(_label("SETTINGS", 30))
	var red := CheckButton.new()
	red.text = "Reduced trip effects"
	red.button_pressed = Settings.reduced_effects
	red.add_theme_font_override("font", font)
	red.add_theme_font_size_override("font_size", 18)
	red.toggled.connect(Settings.set_reduced_effects)
	v.add_child(red)
	v.add_child(_label("Trip strength", 18, WHITE, 0))
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.5
	sl.step = 0.05
	sl.value = Settings.trip_strength
	sl.custom_minimum_size = Vector2(280, 24)
	sl.value_changed.connect(Settings.set_trip_strength)
	v.add_child(sl)
	var fs := CheckButton.new()
	fs.text = "Fullscreen"
	fs.button_pressed = Settings.fullscreen
	fs.add_theme_font_override("font", font)
	fs.add_theme_font_size_override("font_size", 18)
	fs.toggled.connect(Settings.set_fullscreen)
	v.add_child(fs)
	var back := _button("BACK")
	back.pressed.connect(func(): _show_settings(false))
	v.add_child(back)


func _show_settings(on: bool) -> void:
	settings_panel.visible = on
	if not on:
		start_button.grab_focus()


func show_menu() -> void:
	menu.visible = true
	hud.visible = false
	wipeout.visible = false
	pause_panel.visible = false
	settings_panel.visible = false
	var t := "Personal best  %s" % _fmt(Settings.best_score)
	if Settings.best_distance > 0.0:
		t += "  ·  %s m" % _fmt(int(Settings.best_distance))
	if Settings.best_trick != "":
		t += "\nBest trick  %s" % Settings.best_trick
	best_label.text = t
	start_button.grab_focus()


func hide_menu() -> void:
	menu.visible = false


# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.visible = false
	add_child(hud)
	score_label = _label("0", 44, WHITE, 8)
	score_label.position = Vector2(32, 18)
	hud.add_child(score_label)
	dist_label = _label("0 m", 22, Color(1, 1, 1, 0.92), 5)
	dist_label.position = Vector2(34, 72)
	hud.add_child(dist_label)
	# Blinker progress, top centre.
	var holder := Control.new()
	holder.anchor_left = 0.5
	holder.anchor_right = 0.5
	holder.offset_left = -170
	holder.offset_right = 170
	holder.offset_top = 20
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(holder)
	blinker_label = _label("BLINKER 1", 18, TEAL, 5)
	blinker_label.position = Vector2(0, 0)
	holder.add_child(blinker_label)
	blinker_dist = _label("150 m", 18, WHITE, 5)
	blinker_dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	blinker_dist.position = Vector2(200, 0)
	blinker_dist.size = Vector2(140, 24)
	holder.add_child(blinker_dist)
	bar_back = ColorRect.new()
	bar_back.color = Color(INK, 0.45)
	bar_back.position = Vector2(0, 30)
	bar_back.size = Vector2(340, 8)
	holder.add_child(bar_back)
	bar_fill = ColorRect.new()
	bar_fill.color = TEAL
	bar_fill.position = Vector2(0, 30)
	bar_fill.size = Vector2(0, 8)
	holder.add_child(bar_fill)
	check_label = _label("", 22, WHITE, 6)
	check_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	check_label.position = Vector2(-30, 44)
	check_label.size = Vector2(400, 30)
	check_label.modulate.a = 0.0
	holder.add_child(check_label)
	phase_label = _label("", 16, Color(1, 1, 1, 0.8), 4)
	phase_label.anchor_left = 1.0
	phase_label.anchor_right = 1.0
	phase_label.offset_left = -220
	phase_label.offset_right = -28
	phase_label.offset_top = 24
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(phase_label)
	# Trick text: upper third, away from the rider and the line ahead.
	trick_label = _label("", 40, WHITE, 8)
	trick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trick_label.anchor_left = 0.5
	trick_label.anchor_right = 0.5
	trick_label.offset_left = -400
	trick_label.offset_right = 400
	trick_label.offset_top = 100
	trick_label.offset_bottom = 152
	trick_label.pivot_offset = Vector2(400, 26)
	hud.add_child(trick_label)
	bank_label = _label("", 26, TEAL, 6)
	bank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bank_label.anchor_left = 0.5
	bank_label.anchor_right = 0.5
	bank_label.offset_left = -300
	bank_label.offset_right = 300
	bank_label.offset_top = BANK_Y
	bank_label.offset_bottom = BANK_Y + 36
	bank_label.pivot_offset = Vector2(300, 18)
	bank_label.modulate.a = 0.0
	hud.add_child(bank_label)


func show_hud() -> void:
	hud.visible = true
	wipeout.visible = false
	trick_label.text = ""
	bank_label.modulate.a = 0.0
	check_label.modulate.a = 0.0
	_shown_score = 0.0


func update_hud(score: int, distance: float, next_blinker: int, to_next: float, interval: float, phase: String) -> void:
	_target_score = score
	dist_label.text = "%s m" % _fmt(int(distance))
	blinker_label.text = "BLINKER %d" % next_blinker
	blinker_dist.text = "%d m" % maxi(int(ceil(to_next)), 0)
	var prog := clampf(1.0 - to_next / interval, 0.0, 1.0)
	bar_fill.size.x = 340.0 * prog
	phase_label.text = "" if phase == "Sober" else phase.to_upper()


func _process(dt: float) -> void:
	# Score rolls up (makes the blinker bonus count in).
	_shown_score = move_toward(_shown_score, _target_score, maxf(absf(_target_score - _shown_score) * 4.0, 60.0) * dt)
	score_label.text = _fmt(int(_shown_score))
	if _bar_rainbow > 0.0:
		_bar_rainbow = maxf(_bar_rainbow - dt, 0.0)
		bar_fill.color = Color.from_hsv(fmod(Time.get_ticks_msec() / 900.0, 1.0), 0.7, 1.0)
		bar_back.color = Color(INK, 0.45).lerp(Color(1, 1, 1, 0.6), _bar_rainbow * 0.5)
	else:
		bar_fill.color = TEAL
		bar_back.color = Color(INK, 0.45)


func set_trick(text: String) -> void:
	if text == "":
		return
	trick_label.text = text.to_upper()
	trick_label.modulate = Color(1, 1, 1, 1)
	trick_label.rotation = 0.0
	var tw := create_tween()
	trick_label.scale = Vector2(1.25, 1.25)
	tw.tween_property(trick_label, "scale", Vector2.ONE, 0.15)


func clear_trick() -> void:
	var tw := create_tween()
	tw.tween_property(trick_label, "modulate:a", 0.0, 0.25)


## Clean: crisp pop + teal "CLEAN +pts" that flies up into the score.
## Sketchy: wobble + orange "SKETCHY +pts" at half value.
func bank_trick(name: String, points: int, quality: String) -> void:
	trick_label.text = name.to_upper()
	var clean := quality == "clean"
	bank_label.text = ("CLEAN  +%s" if clean else "SKETCHY  +%s") % _fmt(points)
	bank_label.label_settings.font_color = TEAL if clean else ORANGE
	bank_label.modulate = Color(1, 1, 1, 1)
	bank_label.position.y = BANK_Y
	var tw := create_tween().set_parallel(true)
	trick_label.modulate = Color(1, 1, 1, 1)
	if clean:
		trick_label.scale = Vector2(1.45, 1.45)
		tw.tween_property(trick_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		bank_label.scale = Vector2(0.6, 0.6)
		tw.tween_property(bank_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		trick_label.scale = Vector2.ONE
		for i in 6:
			tw.chain().tween_property(trick_label, "rotation", 0.08 * (1 if i % 2 == 0 else -1), 0.05)
		tw.chain().tween_property(trick_label, "rotation", 0.0, 0.05)
	var tw2 := create_tween()
	tw2.tween_interval(0.9)
	tw2.set_parallel(true)
	tw2.tween_property(trick_label, "modulate:a", 0.0, 0.35)
	tw2.tween_property(bank_label, "modulate:a", 0.0, 0.45)
	tw2.tween_property(bank_label, "position:y", BANK_Y - 24.0, 0.45).set_ease(Tween.EASE_IN)


## Blinker: rainbow sweep across the progress bar and a slide-in tag beneath.
func bank_blinker(label: String, points: int, phase: String) -> void:
	_bar_rainbow = 1.6
	check_label.text = "%s  ✦  +%s" % [label, _fmt(points)]
	if phase != "Sober":
		check_label.text += "   ·   %s" % phase.to_upper()
	check_label.modulate = Color(1, 1, 1, 1)
	check_label.position.x = -220
	var tw := create_tween()
	tw.tween_property(check_label, "position:x", -30.0, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.8)
	tw.tween_property(check_label, "modulate:a", 0.0, 0.5)


# ------------------------------------------------------------------ wipeout & pause

func _build_wipeout() -> void:
	wipeout = Control.new()
	wipeout.set_anchors_preset(Control.PRESET_FULL_RECT)
	wipeout.visible = false
	add_child(wipeout)
	var dim := ColorRect.new()
	dim.color = Color(INK, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wipeout.add_child(dim)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(INK, 0.9)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(34)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	wipeout.add_child(panel)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	wipe_title = _label("WIPEOUT", 54, ORANGE, 0)
	wipe_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(wipe_title)
	new_best = _label("NEW PERSONAL BEST", 20, TEAL, 0)
	new_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(new_best)
	wipe_stats = _label("", 22, WHITE, 0)
	wipe_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(wipe_stats)
	v.add_child(_spacer(8))
	ride_button = _button("RIDE AGAIN", true)
	ride_button.custom_minimum_size = Vector2(340, 72)
	ride_button.pressed.connect(func(): ride_again_pressed.emit())
	v.add_child(ride_button)
	var hint := _label("R / Enter", 14, Color(1, 1, 1, 0.6), 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	var mb := _button("SUMMIT MENU")
	mb.pressed.connect(func(): menu_pressed.emit())
	mb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(mb)


func show_wipeout(reason: String, score: int, distance: float, best_trick: String, is_best: bool) -> void:
	wipeout.visible = true
	wipe_title.text = "WIPEOUT"
	new_best.visible = is_best
	var t := "%s\n\nScore   %s\nDistance   %s m\nBest trick   %s" % [reason, _fmt(score), _fmt(int(distance)), best_trick if best_trick != "" else "—"]
	wipe_stats.text = t
	wipeout.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(wipeout, "modulate:a", 1.0, 0.25)
	ride_button.grab_focus()


func _build_pause() -> void:
	pause_panel = PanelContainer.new()
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(INK, 0.88)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(30)
	pause_panel.add_theme_stylebox_override("panel", sb)
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	pause_panel.visible = false
	add_child(pause_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pause_panel.add_child(v)
	var t := _label("PAUSED", 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var r := _button("RESUME", true)
	r.pressed.connect(func(): resume_pressed.emit())
	v.add_child(r)
	var a := _button("RESTART FROM SUMMIT")
	a.pressed.connect(func(): ride_again_pressed.emit())
	v.add_child(a)
	var m := _button("SUMMIT MENU")
	m.pressed.connect(func(): menu_pressed.emit())
	v.add_child(m)


func show_pause(on: bool) -> void:
	pause_panel.visible = on
	if on:
		(pause_panel.get_child(0).get_child(1) as Button).grab_focus()


## Quick powder wipe used when restarting from a crash.
func powder_wipe(mid: Callable) -> void:
	var tw := create_tween()
	tw.tween_property(wipe_rect, "color:a", 1.0, 0.16)
	tw.tween_callback(mid)
	tw.tween_property(wipe_rect, "color:a", 0.0, 0.32)


## Small message at the bottom of the screen (camera changes, etc.).
func toast(text: String) -> void:
	if _toast == null:
		_toast = _label("", 20, WHITE, 5)
		_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast.anchor_left = 0.5
		_toast.anchor_right = 0.5
		_toast.anchor_top = 1.0
		_toast.anchor_bottom = 1.0
		_toast.offset_left = -200
		_toast.offset_right = 200
		_toast.offset_top = -70
		add_child(_toast)
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.4)


var _toast: Label


static func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
