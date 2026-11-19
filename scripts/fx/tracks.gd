class_name Tracks
extends Node3D
## Persistent pair of board-edge marks plus short-lived rainbow "split"
## ribbons after a blinker. Also feeds the recent track polyline to the
## terrain shader (for the colour echo and contour lines).

@export var point_spacing := 0.45
@export var points_per_segment := 64
@export var max_segments := 40
@export var edge_half_width := 0.13
@export var mark_width := 0.07

var terrain_material: ShaderMaterial
var _mat: ShaderMaterial
var _segments: Array = []      # [{mesh, mi, pts: Array}]
var _last := Vector3(INF, INF, INF)
var _split_until := -1.0
var _polyline: Array = []
var _poly_last := Vector3(INF, 0, 0)
var _time := 0.0
const SPLIT_OFFSETS := [-1.1, -0.65, -0.3, 0.3, 0.65, 1.1]


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/track.gdshader")
	top_level = true


func clear() -> void:
	for s in _segments:
		s.mi.queue_free()
	_segments.clear()
	_last = Vector3(INF, INF, INF)
	_polyline.clear()
	_poly_last = Vector3(INF, 0, 0)
	_push_polyline()


func split(seconds: float, now: float) -> void:
	_split_until = now + seconds


## Called every frame the board is on the snow.
func add(pos: Vector3, fwd: Vector3, normal: Vector3, edge: float, now: float) -> void:
	_time = now
	if pos.distance_to(_last) < point_spacing:
		return
	_last = pos
	var lat := normal.cross(fwd).normalized()
	var seg = _segments.back() if not _segments.is_empty() else null
	if seg == null or seg.pts.size() >= points_per_segment:
		var nseg := {mesh = ArrayMesh.new(), mi = MeshInstance3D.new(), pts = []}
		nseg.mi.mesh = nseg.mesh
		nseg.mi.material_override = _mat
		nseg.mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nseg.mi.extra_cull_margin = 50.0
		add_child(nseg.mi)
		if seg != null:
			nseg.pts.append(seg.pts.back())  # continuous ribbon
		_segments.append(nseg)
		seg = nseg
		if _segments.size() > max_segments:
			_segments.pop_front().mi.queue_free()
	seg.pts.append({p = pos + normal * 0.02, lat = lat, edge = edge, t = now, split = now < _split_until})
	_rebuild(seg)
	if pos.distance_to(_poly_last) > 4.0:
		_poly_last = pos
		_polyline.push_front(Vector3(pos.x, pos.z, now))
		if _polyline.size() > 24:
			_polyline.pop_back()
		_push_polyline()


func _push_polyline() -> void:
	if terrain_material == null:
		return
	var arr := PackedVector3Array()
	arr.resize(24)
	for i in _polyline.size():
		arr[i] = _polyline[i]
	terrain_material.set_shader_parameter("track_pts", arr)
	terrain_material.set_shader_parameter("track_count", _polyline.size())


func _rebuild(seg: Dictionary) -> void:
	var pts: Array = seg.pts
	if pts.size() < 2:
		return
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	for i in pts.size() - 1:
		var a: Dictionary = pts[i]
		var b: Dictionary = pts[i + 1]
		# Two edges; when carving hard one edge bites deeper (wider, darker).
		for s in [-1.0, 1.0]:
			var bite := clampf(1.0 + s * a.edge * 1.4, 0.4, 2.2)
			var w := mark_width * bite
			_strip(v, c, uv, a.p + a.lat * edge_half_width * s, b.p + b.lat * edge_half_width * s,
				a.lat, b.lat, w, Color(1, 1, 1, 1), a.t, b.t)
		if a.split and b.split:
			for k in SPLIT_OFFSETS.size():
				var off: float = SPLIT_OFFSETS[k]
				var col := Color.from_hsv(float(k) / SPLIT_OFFSETS.size(), 0.85, 1.0, 0.0)
				_strip(v, c, uv, a.p + a.lat * off, b.p + b.lat * off, a.lat, b.lat, 0.16, col, a.t, b.t)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_TEX_UV] = uv
	seg.mesh.clear_surfaces()
	seg.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)


func _strip(v: PackedVector3Array, c: PackedColorArray, uv: PackedVector2Array, a: Vector3, b: Vector3,
		la: Vector3, lb: Vector3, w: float, col: Color, ta: float, tb: float) -> void:
	var a0 := a - la * w * 0.5
	var a1 := a + la * w * 0.5
	var b0 := b - lb * w * 0.5
	var b1 := b + lb * w * 0.5
	v.append_array([a0, b0, b1, a0, b1, a1])
	for i in 6:
		c.append(col)
	uv.append_array([Vector2(ta, 0), Vector2(tb, 0), Vector2(tb, 1), Vector2(ta, 0), Vector2(tb, 1), Vector2(ta, 1)])
