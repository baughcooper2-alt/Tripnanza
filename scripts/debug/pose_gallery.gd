extends Node3D
## Debug scene: every rider pose side by side, seen from the gameplay angle
## (behind/above) and from the side. Run: godot --path . res://scenes/debug/pose_gallery.tscn

const POSES := ["ride", "left", "right", "crouch", "tuck", "land", "speed", "grab_r", "grab_l", "sit", "eat", "plant", "crash", "pop"]

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.75, 0.8, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.68, 0.9)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(sun)
	var view: String = Settings.args.get("view", "side")
	for i in POSES.size():
		var m = CustomRider.new() if Settings.args.has("custom") else (RiderAvatar.new() if Settings.args.has("avatar") else RiderModel.new())
		add_child(m)
		m.position = Vector3((i % 7) * 2.4, (i / 7) * -2.6, 0)
		m.rotation.y = PI * 0.5 if view == "back" else 0.0
		var p: String = POSES[i]
		for k in m.weights:
			m.weights[k] = 1.0 if k == p else 0.0
		if "lean" in m:
			m.lean = -1.0 if p == "left" else (1.0 if p == "right" else 0.0)
		m.breathe = 0.0
		m.mushroom_visible = p == "eat"
		m.snap()
		var l := Label3D.new()
		l.text = p
		l.position = m.position + Vector3(0, 2.2, 0)
		l.font_size = 64
		l.pixel_size = 0.004
		l.modulate = Color.BLACK
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(l)
	var cam := Camera3D.new()
	add_child(cam)
	if view == "back":
		cam.position = Vector3(7.2, 6.5, 9.0)
		cam.look_at(Vector3(7.2, -1.0, 0))
	else:
		cam.position = Vector3(7.2, -0.5, 13.0)
		cam.look_at(Vector3(7.2, -0.9, 0))
	cam.fov = 50
	for f in 70:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(Settings.args.get("capture", "/tmp") + "/poses_%s.png" % view)
	get_tree().quit()
