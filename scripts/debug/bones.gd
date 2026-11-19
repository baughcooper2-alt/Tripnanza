extends Node
func _ready():
	var scene: Node3D = load("res://assets/characters/snowboarder/snowboarder.glb").instantiate()
	add_child(scene)
	var sk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
	print("skeleton path ", scene.get_path_to(sk), " xf ", sk.global_transform)
	for n in scene.find_children("*", "", true, false):
		print("node ", scene.get_path_to(n), " ", n.get_class())
	for i in sk.get_bone_count():
		var r := sk.get_bone_rest(i)
		print(i, " ", sk.get_bone_name(i), " parent=", sk.get_bone_parent(i), " rest_origin=", r.origin, " global=", sk.get_bone_global_rest(i).origin)
	get_tree().quit()
