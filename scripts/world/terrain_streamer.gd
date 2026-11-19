class_name TerrainStreamer
extends Node3D
## Streams faceted terrain chunks (one per 60 m section) around the rider in
## every direction, with instanced trees/rocks and kicker meshes.

@export var chunks_ahead := 6
@export var chunks_behind := 1
@export var chunks_side := 3
@export var builds_per_frame := 1
@export var terrain_shader: Shader = preload("res://shaders/terrain.gdshader")
@export var prop_shader: Shader = preload("res://shaders/prop.gdshader")

var terrain_material: ShaderMaterial
var tree_material: ShaderMaterial
var rock_material: ShaderMaterial
var ramp_material: ShaderMaterial
var _tree_meshes: Array[ArrayMesh] = []
var _rock_meshes: Array[ArrayMesh] = []
var _flag_meshes: Array[ArrayMesh] = []
var _chunks := {}
var _focus := Vector3.ZERO
var _fwd := Vector3(0, 0, 1)


func _ready() -> void:
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = terrain_shader
	tree_material = _prop_mat(true)
	rock_material = _prop_mat(false)
	ramp_material = _prop_mat(false)
	ramp_material.set_shader_parameter("rim_base", 0.1)
	for i in 3:
		_tree_meshes.append(MeshFactory.tree(i))
		_rock_meshes.append(MeshFactory.rock(i))
	_flag_meshes.append(MeshFactory.flag(Color(1.0, 0.25, 0.35)))
	_flag_meshes.append(MeshFactory.flag(Color(0.2, 0.55, 1.0)))
	Mountain.obstacle_removed.connect(_on_obstacle_removed)
	Mountain.world_reset.connect(clear_all)
	Settings.changed.connect(_apply_settings)
	_apply_settings()


func _prop_mat(tree: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = prop_shader
	m.set_shader_parameter("is_tree", 1.0 if tree else 0.0)
	m.set_shader_parameter("tree_height", 6.5)
	return m


func _apply_settings() -> void:
	var r := 1.0 if Settings.reduced_effects else 0.0
	for m in [terrain_material, tree_material, rock_material]:
		m.set_shader_parameter("reduced", r)


func set_focus(pos: Vector3, fwd: Vector3) -> void:
	_focus = pos
	if fwd.length() > 0.1:
		_fwd = fwd.normalized()


func clear_all() -> void:
	for c in _chunks.values():
		c.queue_free()
	_chunks.clear()


## Builds every chunk around the focus right now (used on reset).
func build_now(radius_cells := 2) -> void:
	var fc := Mountain.cell_of(_focus.x, _focus.z)
	for dz in range(-1, radius_cells + 2):
		for dx in range(-radius_cells, radius_cells + 1):
			var c := fc + Vector2i(dx, dz)
			if not _chunks.has(c):
				_chunks[c] = _build_chunk(c)


func _process(_dt: float) -> void:
	var fc := Mountain.cell_of(_focus.x, _focus.z)
	var wanted := {}
	var todo := []
	for dz in range(-chunks_behind, chunks_ahead + 1):
		for dx in range(-chunks_side, chunks_side + 1):
			var c := fc + Vector2i(dx, dz)
			wanted[c] = true
			if not _chunks.has(c):
				var center := Mountain.cell_origin(c) + Vector2(Mountain.CELL, Mountain.CELL) * 0.5
				var rel := center - Vector2(_focus.x, _focus.z)
				var score := rel.length() - rel.normalized().dot(Vector2(_fwd.x, _fwd.z)) * 40.0
				todo.append([score, c])
	todo.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(builds_per_frame, todo.size()):
		var c: Vector2i = todo[i][1]
		_chunks[c] = _build_chunk(c)
	for c in _chunks.keys():
		if not wanted.has(c) and (absi(c.x - fc.x) > chunks_side + 1 or c.y < fc.y - chunks_behind - 1 or c.y > fc.y + chunks_ahead + 1):
			_chunks[c].queue_free()
			_chunks.erase(c)
	Mountain.prune_cells(fc, chunks_ahead + 3)


func _build_chunk(c: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [c.x, c.y]
	var o := Mountain.cell_origin(c)
	var oy := Mountain.raw_height(o.x, o.y)
	root.position = Vector3(o.x, oy, o.y)
	add_child(root)
	# --- terrain
	var n := Mountain.QUADS
	var g := Mountain.GRID
	var hs := PackedFloat32Array()
	hs.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			hs[j * (n + 1) + i] = Mountain.raw_height(o.x + i * g, o.y + j * g) - oy
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(n * n * 6)
	norms.resize(n * n * 6)
	cols.resize(n * n * 6)
	var k := 0
	for j in n:
		for i in n:
			var h00 := hs[j * (n + 1) + i]
			var h10 := hs[j * (n + 1) + i + 1]
			var h01 := hs[(j + 1) * (n + 1) + i]
			var h11 := hs[(j + 1) * (n + 1) + i + 1]
			var v00 := Vector3(i * g, h00, j * g)
			var v10 := Vector3((i + 1) * g, h10, j * g)
			var v01 := Vector3(i * g, h01, (j + 1) * g)
			var v11 := Vector3((i + 1) * g, h11, (j + 1) * g)
			var na := Vector3(-(h10 - h00) / g, 1.0, -(h11 - h10) / g).normalized()
			var nb := Vector3(-(h11 - h01) / g, 1.0, -(h01 - h00) / g).normalized()
			# Subtle per-facet variation: steeper facets a touch bluer.
			var ca := Color(1, 1, 1).lerp(Color(0.8, 0.85, 1.0), clampf((1.0 - na.y) * 2.5, 0.0, 1.0)).darkened(_jit(i, j, 0))
			var cb := Color(1, 1, 1).lerp(Color(0.8, 0.85, 1.0), clampf((1.0 - nb.y) * 2.5, 0.0, 1.0)).darkened(_jit(i, j, 1))
			verts[k] = v00; verts[k + 1] = v10; verts[k + 2] = v11
			verts[k + 3] = v00; verts[k + 4] = v11; verts[k + 5] = v01
			for q in 3:
				norms[k + q] = na
				cols[k + q] = ca
				norms[k + 3 + q] = nb
				cols[k + 3 + q] = cb
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = terrain_material
	mi.extra_cull_margin = 12.0
	root.add_child(mi)
	# --- props
	var cell: Dictionary = Mountain.get_cell(c)
	var by_mesh := {}
	for ob in cell.obstacles:
		if ob.get("external", false):
			continue
		var key := "t%d" % ob.variant if ob.kind == Mountain.Kind.TREE else "r%d" % ob.variant
		if not by_mesh.has(key):
			by_mesh[key] = []
		by_mesh[key].append(ob)
	for key in by_mesh:
		var list: Array = by_mesh[key]
		var is_tree: bool = key.begins_with("t")
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _tree_meshes[int(key.substr(1))] if is_tree else _rock_meshes[int(key.substr(1))]
		mm.instance_count = list.size()
		for idx in list.size():
			var ob: Dictionary = list[idx]
			ob.mm = mm
			ob.idx = idx
			mm.set_instance_transform(idx, _ob_xform(ob, root.position))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = tree_material if is_tree else rock_material
		root.add_child(mmi)
	for r in cell.ramps:
		var rm := MeshInstance3D.new()
		rm.mesh = MeshFactory.ramp(r, root.position)
		rm.material_override = ramp_material
		root.add_child(rm)
		if not r.natural:
			var dir: Vector2 = r.dir
			var perp := Vector2(-dir.y, dir.x)
			for s in [-1, 1]:
				var p: Vector2 = r.start + dir * r.length + perp * (r.width * 0.5 + 0.4) * s
				var f := MeshInstance3D.new()
				f.mesh = _flag_meshes[0 if s < 0 else 1]
				f.material_override = ramp_material
				f.position = Vector3(p.x, Mountain.terrain(p.x, p.y).w, p.y) - root.position
				f.rotation.y = -atan2(dir.y, dir.x)
				root.add_child(f)
	return root


func _jit(i: int, j: int, k: int) -> float:
	return float((i * 73 + j * 151 + k * 37) % 7) * 0.006


func _ob_xform(ob: Dictionary, origin: Vector3) -> Transform3D:
	if not ob.alive:
		return Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(0, -500, 0))
	var s: float = ob.scale
	var b := Basis(Vector3.UP, ob.rot)
	if ob.kind == Mountain.Kind.TREE:
		b = b.scaled(Vector3(s, s * 1.05, s))
	else:
		b = b.scaled(Vector3(s * 1.3, s * 1.1, s))
	return Transform3D(b, ob.pos - origin - Vector3(0, 0.15, 0))


func _on_obstacle_removed(ob: Dictionary) -> void:
	if ob.mm != null and is_instance_valid(ob.mm) and ob.idx >= 0 and ob.idx < ob.mm.instance_count:
		ob.mm.set_instance_transform(ob.idx, _ob_xform(ob, Vector3.ZERO))
