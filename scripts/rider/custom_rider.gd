class_name CustomRider
extends Node3D
## The player's customizable, realistic rider (MakeHuman body + clothing,
## hair, eyewear, hats and a custom board). Same interface as RiderModel /
## RiderAvatar so the Rider controller can use any of them:
##   weights, flail, breathe, mushroom_visible, hand_r_world, lean, snap().
## Posing comes from a hidden procedural RiderModel; HumanPoser bends the
## MakeHuman skeleton to match it every frame.

const CATALOG := "res://assets/characters/human/catalog.json"
const ROOT := "res://assets/characters/human/"

var weights := {}
var flail := 0.0:
	set(v):
		flail = v
		if _pose:
			_pose.flail = v
var breathe := 1.0:
	set(v):
		breathe = v
		if _pose:
			_pose.breathe = v
var mushroom_visible := false
var hand_r_world := Vector3.ZERO
var lean := 0.0

var look := {}
var _pose: RiderModel
var _human: Node3D
var _sk: Skeleton3D
var _poser: HumanPoser
var _body_mesh: MeshInstance3D
var _parts := {}             # slot -> Array[MeshInstance3D]
var _board: MeshInstance3D
var _board_mat: ShaderMaterial
var _mushroom: MeshInstance3D
var _catalog := {}


static func available() -> bool:
	return ResourceLoader.exists(ROOT + "catalog.json") or FileAccess.file_exists(CATALOG)


static func load_catalog() -> Dictionary:
	if not FileAccess.file_exists(CATALOG):
		return {}
	var f := FileAccess.open(CATALOG, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _ready() -> void:
	_catalog = load_catalog()
	_pose = RiderModel.new()
	_pose.visible = false
	add_child(_pose)
	weights = _pose.weights
	_board_mat = ShaderMaterial.new()
	_board_mat.shader = preload("res://shaders/board.gdshader")
	_board = MeshInstance3D.new()
	_board.mesh = MeshFactory.board(Color.WHITE, Color.WHITE)
	_board.material_override = _board_mat
	add_child(_board)
	_mushroom = MeshInstance3D.new()
	_mushroom.mesh = MeshFactory.mushroom()
	var mm := StandardMaterial3D.new()
	mm.vertex_color_use_as_albedo = true
	_mushroom.material_override = mm
	_mushroom.scale = Vector3.ONE * 1.5
	add_child(_mushroom)
	apply_look(Settings.look if not Settings.look.is_empty() else default_look(_catalog))


static func default_look(cat: Dictionary) -> Dictionary:
	var g := "male"
	var items: Dictionary = cat.get("items", {}).get(g, {})
	var first := func(slot: String) -> String:
		var l: Array = items.get(slot, [])
		return l[0].id if not l.is_empty() else ""
	return {
		gender = g, skin = 0, eyes = 0, height = 1.0, morphs = {},
		hair = first.call("hair"), hair_color = [0.25, 0.16, 0.09], hair_dye = 0.0,
		top = first.call("top"), top_color = [1.0, 0.42, 0.1], top_dye = 1.0,
		bottom = first.call("bottom"), bottom_color = [0.12, 0.15, 0.3], bottom_dye = 1.0,
		shoes = first.call("shoes"), shoes_color = [0.15, 0.13, 0.12], shoes_dye = 0.6,
		gloves = first.call("gloves"), gloves_color = [0.1, 0.1, 0.12], gloves_dye = 1.0,
		hat = "proc_beanie", hat_color = [0.1, 0.75, 0.7], hat_dye = 1.0,
		eyewear = "proc_goggles", eyewear_color = [1.0, 0.55, 0.15], eyewear_dye = 0.0,
		board_pattern = 1, board_base = [0.93, 0.18, 0.45], board_accent = [0.08, 0.08, 0.1], board_third = [1.0, 0.85, 0.25],
	}


# ------------------------------------------------------------------ assembly

func apply_look(l: Dictionary) -> void:
	var defaults := default_look(_catalog)
	for k in defaults:
		if not l.has(k):
			l[k] = defaults[k]
	var rebuild_body: bool = look.get("gender", "") != l.gender or _human == null
	look = l.duplicate(true)
	if rebuild_body:
		_build_body()
	for slot in ["hair", "top", "bottom", "shoes", "gloves", "hat", "eyewear"]:
		_equip(slot, look.get(slot, ""))
	_apply_skin()
	_apply_morphs()
	_apply_hiding()
	_apply_board()
	scale = Vector3.ONE * float(look.get("height", 1.0))


func _build_body() -> void:
	if _human:
		_mushroom.reparent(self, false)
		_human.queue_free()
	_parts.clear()
	var info: Dictionary = _catalog.get("bodies", {}).get(look.gender, {})
	if info.is_empty():
		return
	_human = (load(ROOT + info.body) as PackedScene).instantiate()
	add_child(_human)
	_sk = _human.find_children("*", "Skeleton3D", true, false)[0]
	for mi in _human.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh and mi.mesh.get_blend_shape_count() > 0 or String(mi.name).to_lower().contains("body"):
			_body_mesh = mi
	if _body_mesh == null:
		_body_mesh = _human.find_children("*", "MeshInstance3D", true, false)[0]
	_poser = HumanPoser.new()
	_sk.add_child(_poser)
	var att := BoneAttachment3D.new()
	att.bone_name = "hand_r"
	_sk.add_child(att)
	_mushroom.reparent(att, false)
	_mushroom.position = Vector3(0, 0.08, 0.03)


## Ski goggles / beanies built from primitives and pinned to the head bone.
func _equip_builtin(slot: String, id: String) -> void:
	var head := _sk.find_bone("head")
	if head < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = "head"
	_sk.add_child(att)
	_parts[slot] = [att]
	var r := 0.105
	var c: Array = look.get(slot + "_color", [1, 1, 1])
	var col := Color(c[0], c[1], c[2])
	if slot == "eyewear":
		var strap := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r * 1.02
		tm.outer_radius = r * 1.12
		tm.rings = 32
		strap.mesh = tm
		strap.position = Vector3(0, 0.075, 0.0)
		strap.scale = Vector3(1.0, 0.35, 1.08)
		strap.material_override = _flat_mat(Color(0.08, 0.08, 0.09), 0.9)
		att.add_child(strap)
		var lens := MeshInstance3D.new()
		var bm := CapsuleMesh.new()
		bm.radius = 0.045
		bm.height = 0.17
		bm.radial_segments = 24
		lens.mesh = bm
		lens.rotation_degrees = Vector3(0, 0, 90)
		lens.position = Vector3(0, 0.075, r * 0.98)
		lens.scale = Vector3(0.9, 1.0, 0.45)
		var lm := StandardMaterial3D.new()
		lm.albedo_color = col if id == "proc_goggles" else col.lightened(0.3)
		lm.metallic = 0.2 if id == "proc_goggles" else 0.95
		lm.roughness = 0.08
		lm.rim_enabled = true
		lens.material_override = lm
		att.add_child(lens)
	else:
		var cap := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = r * 1.13
		sm.height = r * 1.6
		sm.is_hemisphere = true
		sm.radial_segments = 32
		sm.rings = 12
		cap.mesh = sm
		cap.position = Vector3(0, 0.12, -0.005)
		cap.material_override = _knit_mat(col)
		att.add_child(cap)
		var cuff := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r * 1.16
		cm.bottom_radius = r * 1.16
		cm.height = 0.045
		cm.radial_segments = 32
		cuff.mesh = cm
		cuff.position = Vector3(0, 0.125, -0.005)
		cuff.material_override = _knit_mat(col.darkened(0.15))
		att.add_child(cuff)
		if id == "proc_beanie_pom":
			var pom := MeshInstance3D.new()
			var pm := SphereMesh.new()
			pm.radius = 0.04
			pm.height = 0.08
			pom.mesh = pm
			pom.position = Vector3(0, 0.12 + r * 0.8, -0.005)
			pom.material_override = _knit_mat(Color(0.95, 0.95, 0.95))
			att.add_child(pom)


func _flat_mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _knit_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	var n := NoiseTexture2D.new()
	n.as_normal_map = true
	n.bump_strength = 6.0
	var fn := FastNoiseLite.new()
	fn.frequency = 0.08
	n.noise = fn
	m.normal_enabled = true
	m.normal_texture = n
	m.uv1_scale = Vector3(6, 2, 1)
	return m


func _item(slot: String, id: String) -> Dictionary:
	for it in BUILTIN.get(slot, []):
		if it.id == id:
			return it
	for it in _catalog.get("items", {}).get(look.gender, {}).get(slot, []):
		if it.id == id:
			return it
	return {}


## Built-in items that don't come from the MakeHuman packs.
const BUILTIN := {
	"hat": [{id = "proc_beanie", name = "Knit beanie", hides = []}, {id = "proc_beanie_pom", name = "Pom-pom beanie", hides = []}],
	"eyewear": [{id = "proc_goggles", name = "Ski goggles", hides = []}, {id = "proc_goggles_mirror", name = "Mirror goggles", hides = []}],
}


func _equip(slot: String, id: String) -> void:
	for mi in _parts.get(slot, []):
		if is_instance_valid(mi):
			mi.queue_free()
	_parts[slot] = []
	if id == "" or _sk == null:
		return
	if id.begins_with("proc_"):
		_equip_builtin(slot, id)
		return
	var it := _item(slot, id)
	if it.is_empty():
		return
	var scene: Node = (load(ROOT + it.file) as PackedScene).instantiate()
	# Re-home the item's skinned meshes onto the body's skeleton.
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		m.get_parent().remove_child(m)
		_sk.add_child(m)
		m.skeleton = m.get_path_to(_sk)
		_dress(m, slot, it)
		_parts[slot].append(m)
	scene.free()


func _dress(m: MeshInstance3D, slot: String, it: Dictionary) -> void:
	for si in m.mesh.get_surface_count():
		var src := m.get_active_material(si)
		var dm := ShaderMaterial.new()
		dm.shader = preload("res://shaders/dye.gdshader")
		if src is BaseMaterial3D:
			dm.set_shader_parameter("albedo_tex", src.albedo_texture)
			if src.normal_enabled and src.normal_texture:
				dm.set_shader_parameter("normal_tex", src.normal_texture)
				dm.set_shader_parameter("use_normal", 1.0)
		var c: Array = look.get(slot + "_color", [1, 1, 1])
		dm.set_shader_parameter("dye_color", Color(c[0], c[1], c[2]))
		dm.set_shader_parameter("dye_amount", float(look.get(slot + "_dye", 0.0)))
		dm.set_shader_parameter("alpha_cut", 0.35 if it.get("alpha", false) else 0.0)
		dm.set_shader_parameter("roughness", 0.55 if slot == "hair" else (0.25 if slot == "eyewear" else 0.85))
		dm.set_shader_parameter("sheen", 0.3 if slot == "hair" else 0.08)
		m.set_surface_override_material(si, dm)


## Recolour one slot without reloading it (used live by the menu).
func set_color(slot: String, c: Color, dye: float) -> void:
	look[slot + "_color"] = [c.r, c.g, c.b]
	look[slot + "_dye"] = dye
	if String(look.get(slot, "")).begins_with("proc_"):
		_equip(slot, look[slot])
		return
	for m in _parts.get(slot, []):
		for si in m.mesh.get_surface_count():
			var dm := m.get_surface_override_material(si) as ShaderMaterial
			if dm:
				dm.set_shader_parameter("dye_color", c)
				dm.set_shader_parameter("dye_amount", dye)


func _apply_skin() -> void:
	if _body_mesh == null:
		return
	var info: Dictionary = _catalog.get("bodies", {}).get(look.gender, {})
	var skins: Array = info.get("skins", [])
	var eyes: Array = _catalog.get("eyes", [])
	for si in _body_mesh.mesh.get_surface_count():
		var src := _body_mesh.mesh.surface_get_material(si)
		var name := String(src.resource_name).to_lower() if src else ""
		if name.contains("eye") and not name.contains("brow") and not name.contains("lash"):
			if not eyes.is_empty():
				var e: Dictionary = eyes[clampi(int(look.eyes), 0, eyes.size() - 1)]
				var em := StandardMaterial3D.new()
				em.albedo_texture = load(ROOT + e.albedo)
				em.roughness = 0.15
				_body_mesh.set_surface_override_material(si, em)
			continue
		if name.contains("brow") or name.contains("lash") or name.contains("teeth") or name.contains("tongue"):
			continue
		var sm := ShaderMaterial.new()
		sm.shader = preload("res://shaders/skin.gdshader")
		if not skins.is_empty():
			var s: Dictionary = skins[clampi(int(look.skin), 0, skins.size() - 1)]
			sm.set_shader_parameter("albedo_tex", load(ROOT + s.albedo))
			if s.has("normal"):
				sm.set_shader_parameter("normal_tex", load(ROOT + s.normal))
				sm.set_shader_parameter("use_normal", 1.0)
		elif src is BaseMaterial3D:
			sm.set_shader_parameter("albedo_tex", src.albedo_texture)
		_body_mesh.set_surface_override_material(si, sm)


## Face sliders are two-way (-1..1). The body carries shape keys named
## m:<id>:<incr|decr>:<n> (n = left/right halves where they exist).
func _apply_morphs() -> void:
	if _body_mesh == null or _body_mesh.mesh == null:
		return
	var m: Dictionary = look.get("morphs", {})
	for i in _body_mesh.mesh.get_blend_shape_count():
		var parts := String(_body_mesh.mesh.get_blend_shape_name(i)).split(":")
		if parts.size() < 3 or parts[0] != "m":
			continue
		var v := float(m.get(parts[1], 0.0))
		_body_mesh.set_blend_shape_value(i, maxf(v, 0.0) if parts[2] == "incr" else maxf(-v, 0.0))


func set_morph(id: String, v: float) -> void:
	look.morphs[id] = v
	_apply_morphs()


## Hide skin under clothing so it never pokes through.
func _apply_hiding() -> void:
	var hide := {}
	for slot in ["top", "bottom", "shoes", "gloves", "hat"]:
		var it := _item(slot, look.get(slot, ""))
		for h in it.get("hides", []):
			hide[h] = true
	for si in (_body_mesh.mesh.get_surface_count() if _body_mesh else 0):
		var sm := _body_mesh.get_surface_override_material(si) as ShaderMaterial
		if sm and sm.shader == preload("res://shaders/skin.gdshader"):
			sm.set_shader_parameter("hide", Vector4(1.0 if hide.has("torso") else 0.0, 1.0 if hide.has("arms") else 0.0,
				1.0 if hide.has("legs") else 0.0, 1.0 if hide.has("feet") else 0.0))
			sm.set_shader_parameter("hide_hands", 1.0 if hide.has("hands") else 0.0)


func _apply_board() -> void:
	var c := func(k: String) -> Color:
		var a: Array = look.get(k, [1, 1, 1])
		return Color(a[0], a[1], a[2])
	_board_mat.set_shader_parameter("pattern", int(look.get("board_pattern", 0)))
	_board_mat.set_shader_parameter("base_color", c.call("board_base"))
	_board_mat.set_shader_parameter("accent_color", c.call("board_accent"))
	_board_mat.set_shader_parameter("third_color", c.call("board_third"))


# ------------------------------------------------------------------ per frame

func snap() -> void:
	_pose.snap()


func _process(_dt: float) -> void:
	_pose.mushroom_visible = mushroom_visible
	_mushroom.visible = mushroom_visible
	# Board rides the procedural pose's edge tilt.
	var root: Basis = _pose.joints.get("root", Basis())
	_board.transform = Transform3D(root, Vector3.ZERO)
	if _poser and _sk:
		_poser.joints = _pose.joints
		_poser.to_skeleton = _sk.global_transform.affine_inverse() * global_transform
		var hb := _sk.find_bone("hand_r")
		if hb >= 0:
			hand_r_world = _sk.global_transform * _sk.get_bone_global_pose(hb).origin
