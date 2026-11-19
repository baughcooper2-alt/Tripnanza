class_name TripCompositor
extends Node
## Render pipeline for the trip:
##   WorldView (SubViewport)  - the 3D world, rendered off-screen by the game camera
##   Trails    (SubViewport)  - never cleared; each frame paints the world over itself
##                              at partial opacity, so moving things leave tracers
##   PostFX/Trip (ColorRect)  - composite shader (shaders/trip_post.gdshader) that
##                              reads both and does every screen-space trip effect
## The UI draws on top of all of it on its own CanvasLayer.

var world_view: SubViewport
var trails_view: SubViewport
var trail_mat: ShaderMaterial
var composite: ShaderMaterial


func setup(camera: Camera3D, composite_mat: ShaderMaterial) -> void:
	composite = composite_mat
	world_view = SubViewport.new()
	world_view.name = "WorldView"
	world_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_view.msaa_3d = ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0)
	world_view.audio_listener_enable_3d = true
	add_child(world_view)
	camera.reparent(world_view, false)
	camera.current = true

	trails_view = SubViewport.new()
	trails_view.name = "Trails"
	trails_view.disable_3d = true
	trails_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	trails_view.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	add_child(trails_view)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	trail_mat = ShaderMaterial.new()
	trail_mat.shader = preload("res://shaders/trip_trails.gdshader")
	trail_mat.set_shader_parameter("world_tex", world_view.get_texture())
	rect.material = trail_mat
	trails_view.add_child(rect)

	composite.set_shader_parameter("world_tex", world_view.get_texture())
	composite.set_shader_parameter("trail_tex", trails_view.get_texture())
	get_window().size_changed.connect(_resize)
	_resize()


func _resize() -> void:
	var s := get_window().size
	if s.x < 8 or s.y < 8:
		return
	world_view.size = s
	trails_view.size = s
	(trails_view.get_child(0) as Control).size = Vector2(s)


## 0 = no tracers, ~0.9 = long smeared trails.
func set_trail_keep(keep: float) -> void:
	if trail_mat:
		trail_mat.set_shader_parameter("keep", clampf(keep, 0.0, 0.95))
