class_name MeshBuilder
extends RefCounted
## Tiny flat-shaded mesh builder. Every triangle gets its own face normal and
## colour, which gives the faceted low-poly look. Triangles are flipped
## automatically so the normal points away from `center` (when supplied).

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var center = null  # Vector3 or null


func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, uv := Vector2.ZERO) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	if center != null and n.dot((a + b + c) / 3.0 - center) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	verts.append_array([a, b, c])
	normals.append_array([n, n, n])
	colors.append_array([col, col, col])
	uvs.append_array([uv, uv, uv])


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, uv := Vector2.ZERO) -> void:
	tri(a, b, c, col, uv)
	tri(a, c, d, col, uv)


## Colour chosen per face from its normal (snow on top, base colour on sides).
func tri_snowy(a: Vector3, b: Vector3, c: Vector3, base: Color, snow: Color, thresh: float) -> void:
	var n := (c - a).cross(b - a).normalized()
	if center != null and n.dot((a + b + c) / 3.0 - center) < 0.0:
		n = -n
	tri(a, b, c, snow if n.y > thresh else base)


func commit(mesh: ArrayMesh = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_TEX_UV] = uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## Like commit(), but averages normals of coincident vertices for smooth,
## realistic shading (instead of faceted low-poly shading).
func commit_smooth(mesh: ArrayMesh = null, snap := 0.001) -> ArrayMesh:
	var acc := {}
	for i in verts.size():
		var key := (verts[i] / snap).round()
		acc[key] = acc.get(key, Vector3.ZERO) + normals[i]
	for i in verts.size():
		var key := (verts[i] / snap).round()
		var n: Vector3 = acc[key]
		normals[i] = n.normalized() if n.length_squared() > 1e-9 else normals[i]
	return commit(mesh)
