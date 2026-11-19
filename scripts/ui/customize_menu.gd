class_name CustomizeMenu
extends Control
## Rider customization: BODY (gender, skin, eyes, height, face shape),
## HAIR (style + colour), OUTFIT (jacket, pants, boots, gloves, hat,
## eyewear, each with colour) and BOARD (graphic + three colours).
## Works with mouse, keyboard and controller (focus moves row to row;
## left/right on a row changes it). Changes apply live to the rider.

signal done

const PALETTE := [
	Color(1.0, 0.42, 0.1), Color(0.86, 0.12, 0.14), Color(0.95, 0.3, 0.6), Color(0.55, 0.25, 0.85),
	Color(0.15, 0.35, 0.9), Color(0.1, 0.15, 0.35), Color(0.1, 0.7, 0.68), Color(0.2, 0.55, 0.25),
	Color(0.65, 0.85, 0.15), Color(1.0, 0.85, 0.2), Color(0.95, 0.95, 0.95), Color(0.55, 0.56, 0.6),
	Color(0.1, 0.1, 0.12), Color(0.4, 0.27, 0.16), Color(0.75, 0.65, 0.5),
]
const HAIR_COLORS := [
	Color(0.09, 0.07, 0.06), Color(0.25, 0.16, 0.09), Color(0.45, 0.3, 0.16), Color(0.75, 0.6, 0.35),
	Color(0.93, 0.85, 0.6), Color(0.6, 0.22, 0.1), Color(0.6, 0.6, 0.62), Color(0.95, 0.4, 0.7),
	Color(0.2, 0.5, 0.95), Color(0.3, 0.85, 0.5),
]
const BOARD_PATTERNS := ["Solid", "Racing stripes", "Chevrons", "Split", "Dots", "Flames", "Trip swirl", "Wood"]
const SLOT_NAMES := {top = "Jacket / top", bottom = "Pants", shoes = "Boots", gloves = "Gloves", hat = "Hat", eyewear = "Goggles / glasses", hair = "Hair"}

var rider_model: CustomRider
var font: Font
var _catalog := {}
var _tab := "BODY"
var _list: VBoxContainer
var _tabs: HBoxContainer
var _first_focus: Control


func setup(model: CustomRider, f: Font) -> void:
	rider_model = model
	font = f
	_catalog = CustomRider.load_catalog()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.16, 0.88)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(40, 40)
	panel.custom_minimum_size = Vector2(470, 640)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	v.add_child(_title("CUSTOMIZE", 34))
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	v.add_child(_tabs)
	for t in ["BODY", "HAIR", "OUTFIT", "BOARD"]:
		var b := _btn(t, 16)
		b.custom_minimum_size = Vector2(100, 38)
		b.pressed.connect(func(): _show(t))
		_tabs.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var done_b := _btn("DONE", 22)
	done_b.custom_minimum_size = Vector2(200, 52)
	done_b.pressed.connect(_finish)
	v.add_child(done_b)
	var hint := _title("Rotate the rider: LB / RB or Q / E", 13)
	hint.modulate.a = 0.7
	v.add_child(hint)


func open() -> void:
	visible = true
	_show("BODY")


func _finish() -> void:
	Settings.look = rider_model.look.duplicate(true)
	Settings.save_settings()
	done.emit()


# ------------------------------------------------------------------ tabs

func _show(tab: String) -> void:
	_tab = tab
	for c in _list.get_children():
		c.queue_free()
	_first_focus = null
	var l := rider_model.look
	match tab:
		"BODY":
			_selector("Body", ["Man", "Woman"], 0 if l.gender == "male" else 1, func(i):
				var nl: Dictionary = rider_model.look.duplicate(true)
				nl.gender = "male" if i == 0 else "female"
				# Pick valid items for the new body.
				for slot in SLOT_NAMES:
					var ids := _ids(slot, nl.gender)
					if not ids.has(nl.get(slot, "")) and not String(nl.get(slot, "")).begins_with("proc_"):
						nl[slot] = ids[0] if not ids.is_empty() and slot != "hat" else ""
				rider_model.apply_look(nl)
				_show("BODY"))
			var skins: Array = _catalog.get("bodies", {}).get(l.gender, {}).get("skins", [])
			_selector("Skin", skins.map(func(s): return s.name), int(l.skin), func(i):
				var nl: Dictionary = rider_model.look.duplicate(true)
				nl.skin = i
				rider_model.apply_look(nl))
			var eyes: Array = _catalog.get("eyes", [])
			_selector("Eyes", eyes.map(func(s): return s.name), int(l.eyes), func(i):
				var nl: Dictionary = rider_model.look.duplicate(true)
				nl.eyes = i
				rider_model.apply_look(nl))
			_slider("Height", 0.9, 1.1, float(l.height), func(x):
				rider_model.look.height = x
				rider_model.scale = Vector3.ONE * x)
			var morphs: Array = _catalog.get("bodies", {}).get(l.gender, {}).get("morphs", [])
			for m in morphs:
				_slider(m.name, -1.0, 1.0, float(l.morphs.get(m.id, 0.0)), func(x): rider_model.set_morph(m.id, x))
		"HAIR":
			_item_selector("hair")
			_swatches("Hair colour", HAIR_COLORS, "hair")
		"OUTFIT":
			for slot in ["top", "bottom", "shoes", "gloves", "hat", "eyewear"]:
				_item_selector(slot)
				if l.get(slot, "") != "":
					_swatches("", PALETTE, slot)
		"BOARD":
			_selector("Graphic", BOARD_PATTERNS, int(l.board_pattern), func(i):
				rider_model.look.board_pattern = i
				rider_model._apply_board())
			for k in [["Base colour", "board_base"], ["Accent colour", "board_accent"], ["Third colour", "board_third"]]:
				_board_swatches(k[0], k[1])
	if _first_focus:
		_first_focus.call_deferred("grab_focus")


func _ids(slot: String, gender: String) -> Array:
	return _catalog.get("items", {}).get(gender, {}).get(slot, []).map(func(it): return it.id)


func _item_selector(slot: String) -> void:
	var items: Array = CustomRider.BUILTIN.get(slot, []) + _catalog.get("items", {}).get(rider_model.look.gender, {}).get(slot, [])
	var names: Array = ["None"] + items.map(func(it): return it.name)
	var ids: Array = [""] + items.map(func(it): return it.id)
	var cur := maxi(ids.find(rider_model.look.get(slot, "")), 0)
	_selector(SLOT_NAMES[slot], names, cur, func(i):
		var nl: Dictionary = rider_model.look.duplicate(true)
		nl[slot] = ids[i]
		rider_model.apply_look(nl)
		if (cur == 0) != (i == 0):
			_show(_tab))


# ------------------------------------------------------------------ widgets

func _title(t: String, size: int) -> Label:
	var l := Label.new()
	l.text = t
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = size
	l.label_settings = ls
	return l


func _btn(t: String, size: int) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", size)
	b.focus_entered.connect(func(): Audio.play("ui_move", 0.4))
	b.pressed.connect(func(): Audio.play("ui_click", 0.5))
	return b


func _row(label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := _title(label, 16)
	l.custom_minimum_size = Vector2(150, 0)
	h.add_child(l)
	_list.add_child(h)
	return h


## "◀ value ▶" row. Left/right while focused also changes it.
func _selector(label: String, options: Array, index: int, on_change: Callable) -> void:
	if options.is_empty():
		return
	var h := _row(label)
	var state := {i = clampi(index, 0, options.size() - 1)}
	var prev := _btn("◀", 16)
	var val := _btn(str(options[state.i]), 15)
	val.custom_minimum_size = Vector2(190, 34)
	val.clip_text = true
	var next := _btn("▶", 16)
	var step := func(d: int):
		state.i = posmod(state.i + d, options.size())
		val.text = str(options[state.i])
		on_change.call(state.i)
	prev.pressed.connect(func(): step.call(-1))
	next.pressed.connect(func(): step.call(1))
	val.pressed.connect(func(): step.call(1))
	val.gui_input.connect(func(e: InputEvent):
		if e.is_action_pressed("ui_left"):
			step.call(-1)
			val.accept_event()
		elif e.is_action_pressed("ui_right"):
			step.call(1)
			val.accept_event())
	h.add_child(prev)
	h.add_child(val)
	h.add_child(next)
	if _first_focus == null:
		_first_focus = val


func _slider(label: String, lo: float, hi: float, value: float, on_change: Callable) -> void:
	var h := _row(label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01
	s.value = value
	s.custom_minimum_size = Vector2(240, 28)
	s.value_changed.connect(on_change)
	h.add_child(s)
	if _first_focus == null:
		_first_focus = s


func _swatches(label: String, colors: Array, slot: String) -> void:
	var box := VBoxContainer.new()
	if label != "":
		box.add_child(_title(label, 16))
	var grid := GridContainer.new()
	grid.columns = 8
	box.add_child(grid)
	var orig := _btn("Original", 13)
	orig.pressed.connect(func(): rider_model.set_color(slot, Color.WHITE, 0.0))
	grid.add_child(orig)
	for c in colors:
		grid.add_child(_swatch(c, func(): rider_model.set_color(slot, c, 1.0)))
	_list.add_child(box)


func _board_swatches(label: String, key: String) -> void:
	var box := VBoxContainer.new()
	box.add_child(_title(label, 16))
	var grid := GridContainer.new()
	grid.columns = 8
	box.add_child(grid)
	for c in PALETTE:
		grid.add_child(_swatch(c, func():
			rider_model.look[key] = [c.r, c.g, c.b]
			rider_model._apply_board()))
	_list.add_child(box)


func _swatch(c: Color, on_press: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(38, 30)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(6)
		if st != "normal":
			sb.border_color = Color.WHITE
			sb.set_border_width_all(3)
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(on_press)
	b.pressed.connect(func(): Audio.play("ui_click", 0.5))
	return b
