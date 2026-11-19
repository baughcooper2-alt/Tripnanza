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
var _fir_meshes: Array[ArrayMesh] = []
var _boulder_meshes: Array[ArrayMesh] = []
var fir_bark: ShaderMaterial
var fir_needles: ShaderMaterial
@export var tree_lod_distance := 210.0
var _flag_meshes: Array[ArrayMesh] = []
var _chunks := {}
var _focus := Vector3.ZERO
var _fwd := Vector3(0, 0, 1)


func _ready() -> void:
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = terrain_shader
	tree_material = _prop_mat(true)
	rock_material = ShaderMaterial.new()
	rock_material.shader = preload("res://shaders/rock.gdshader")
	# Kickers are packed snow: same material as the slope (wood sides via vertex colour).
	ramp_material = terrain_material
	fir_bark = ShaderMaterial.new()
	fir_bark.shader = preload("res://shaders/foliage.gdshader")
	fir_bark.set_shader_parameter("is_foliage", 0.0)
	fir_needles = ShaderMaterial.new()
	fir_needles.shader = fir_bark.shader
	fir_needles.set_shader_parameter("is_foliage", 1.0)
	for i in 3:
		_tree_meshes.append(MeshFactory.tree(i))
		_rock_meshes.append(MeshFactory.rock(i))
		var fm := MeshFactory.fir(i)
		fm.surface_set_material(0, fir_bark)
		fm.surface_set_material(1, fir_needles)
		_fir_meshes.append(fm)
		_boulder_meshes.append(MeshFactory.boulder(i))
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
	for m in [terrain_material, tree_material, fir_bark, fir_needles]:
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
	# --- terrain: indexed grid, smooth normals (same triangles the rider touches)
	var n := Mountain.QUADS
	var g := Mountain.GRID
	var w := n + 3   # one extra ring for central-difference normals
	var hs := PackedFloat32Array()
	hs.resize(w * w)
	for j in w:
		for i in w:
			hs[j * w + i] = Mountain.raw_height(o.x + (i - 1) * g, o.y + (j - 1) * g) - oy
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize((n + 1) * (n + 1))
	norms.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var hc := hs[(j + 1) * w + i + 1]
			var dx := (hs[(j + 1) * w + i + 2] - hs[(j + 1) * w + i]) / (2.0 * g)
			var dz := (hs[(j + 2) * w + i + 1] - hs[j * w + i + 1]) / (2.0 * g)
			verts[j * (n + 1) + i] = Vector3(i * g, hc, j * g)
			norms[j * (n + 1) + i] = Vector3(-dx, 1.0, -dz).normalized()
	var idx := PackedInt32Array()
	idx.resize(n * n * 6)
	var k := 0
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := a + 1
			var c2 := a + (n + 1)
			var d := c2 + 1
			idx[k] = a; idx[k + 1] = b; idx[k + 2] = d
			idx[k + 3] = a; idx[k + 4] = d; idx[k + 5] = c2
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = terrain_material
	mi.extra_cull_margin = 12.0
	root.add_child(mi)
	# --- props: realistic firs near, simple firs far (automatic LOD), boulders
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
		var v := int(key.substr(1))
		var lods: Array = [[_fir_meshes[v], 0.0, tree_lod_distance]] if is_tree else [[_boulder_meshes[v], 0.0, 0.0]]
		if is_tree:
			lods.append([_tree_meshes[v], tree_lod_distance, 0.0])
		for li in lods.size():
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = lods[li][0]
			mm.instance_count = list.size()
			for ii in list.size():
				var ob: Dictionary = list[ii]
				if li == 0:
					ob.mm = mm
				else:
					ob.mm2 = mm
				ob.idx = ii
				mm.set_instance_transform(ii, _ob_xform(ob, root.position))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			if is_tree and li == 1:
				mmi.material_override = tree_material
			elif not is_tree:
				mmi.material_override = rock_material
			mmi.visibility_range_begin = lods[li][1]
			mmi.visibility_range_end = lods[li][2]
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
	for key in ["mm", "mm2"]:
		var m = ob.get(key)
		if m != null and is_instance_valid(m) and ob.idx >= 0 and ob.idx < m.instance_count:
			m.set_instance_transform(ob.idx, _ob_xform(ob, Vector3.ZERO))
