extends Node3D
## Debug: renders the imported snowboarder from 4 angles and samples each animation.
## godot --path . res://scenes/debug/model_viewer.tscn -- --capture=/dir
func _ready() -> void:
	var out: String = Settings.args.get("capture", "/tmp")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.7, 0.75, 0.85)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var scene: Node3D = load("res://assets/characters/snowboarder/snowboarder.glb").instantiate()
	add_child(scene)
	var ap0: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	ap0.play("Idle")
	ap0.seek(0.5, true)
	var sk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
	var lo := INF
	var hi := -INF
	for bi in sk.get_bone_count():
		var p := (sk.global_transform * sk.get_bone_global_pose(bi)).origin
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
		if sk.get_bone_name(bi) in ["spine.006", "foot.L", "Snowboard", "toe.L", "hand.L"]:
			print("bone ", sk.get_bone_name(bi), " ", p)
	print("bone height span ", hi - lo)
	scene.scale = Vector3.ONE * (1.6 / maxf(hi - lo, 1e-6))
	print("scale applied ", scene.scale.x)
	await get_tree().process_frame
	var aabb := AABB()
	var first := true
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var bb: AABB = AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
		print("mesh ", mi.name, " aabb ", bb)
		aabb = bb if first else aabb.merge(bb)
		first = false
	print("total aabb ", aabb)
	var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	print("anims ", ap.get_animation_list())
	# Axis markers: red +X, green +Y, blue +Z
	for ax in [[Vector3.RIGHT, Color.RED], [Vector3.UP, Color.GREEN], [Vector3.BACK, Color.BLUE]]:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * 0.06 + ax[0].abs() * aabb.size.length() * 0.5
		m.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = ax[1]
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material_override = mat
		m.position = ax[0] * aabb.size.length() * 0.25
		add_child(m)
	var cam := Camera3D.new()
	add_child(cam)
	var c := aabb.get_center()
	var r := aabb.size.length() * 1.2
	var views := {"front_+z": Vector3(0, 0.3, 1), "side_+x": Vector3(1, 0.3, 0), "top": Vector3(0.01, 1, 0.01), "behind_-z": Vector3(0, 0.3, -1)}
	ap.play("Idle")
	ap.seek(0.5, true)
	for k in views:
		cam.position = c + views[k].normalized() * r
		cam.look_at(c)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/view_%s.png" % [out, k])
	cam.position = c + Vector3(1, 0.5, 1).normalized() * r
	cam.look_at(c)
	for an in ap.get_animation_list():
		if an == "RESET":
			continue
		var len := ap.get_animation(an).length
		for f in 3:
			ap.play(an)
			ap.seek(len * (0.15 + 0.35 * f), true)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/anim_%s_%d.png" % [out, an, f])
	get_tree().quit()
