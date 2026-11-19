extends Node
func _ready():
	for f in ["res://assets/characters/human/male/top_elvs_hooded_sweat_jacket1.glb", "res://assets/characters/human/male/hair_short02.glb", "res://assets/characters/human/male/body.glb"]:
		var sc: Node = load(f).instantiate()
		for mi in sc.find_children("*", "MeshInstance3D", true, false):
			for si in mi.mesh.get_surface_count():
				var m = mi.get_active_material(si)
				var mm = mi.mesh.surface_get_material(si)
				print(f.get_file(), " ", mi.name, " s", si, " active=", m, " mesh_mat=", mm, " tex=", (m.albedo_texture if m is BaseMaterial3D else "n/a"), " transp=", (m.transparency if m is BaseMaterial3D else ""))
	get_tree().quit()
