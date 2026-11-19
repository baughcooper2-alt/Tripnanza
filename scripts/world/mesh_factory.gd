class_name MeshFactory
extends RefCounted
## Procedural, original low-poly models used across the game.

const SNOW := Color(0.96, 0.97, 1.0)
const PINE := Color(0.13, 0.27, 0.24)
const PINE_DARK := Color(0.09, 0.19, 0.18)
const BARK := Color(0.33, 0.22, 0.16)
const ROCK := Color(0.25, 0.25, 0.28)
const ROCK_DARK := Color(0.17, 0.17, 0.2)


## Snowy pine, 1 unit = ~1 m before instance scaling. Base at origin.
static func tree(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + variant
	var b := MeshBuilder.new()
	var sides := 6 + variant % 2
	# trunk
	_prism(b, Vector3.ZERO, 0.22, 0.16, 1.3, 5, BARK)
	var tiers := 3 + (variant % 2)
	var y := 0.9
	var radius := 2.0 + variant * 0.15
	for t in tiers:
		var h := 2.6 - t * 0.35
		var top := Vector3(rng.randf_range(-0.1, 0.1), y + h, rng.randf_range(-0.1, 0.1))
		var ring := []
		var off := rng.randf() * TAU
		for i in sides:
			var a := off + TAU * i / sides
			var rr := radius * rng.randf_range(0.85, 1.1)
			ring.append(Vector3(cos(a) * rr, y + rng.randf_range(-0.15, 0.2), sin(a) * rr))
		b.center = Vector3(0, y + h * 0.3, 0)
		for i in sides:
			var p0: Vector3 = ring[i]
			var p1: Vector3 = ring[(i + 1) % sides]
			var mid := (p0 + p1) * 0.5
			# Split each face: snowy upper half, dark needles below.
			var m0 := p0.lerp(top, 0.45)
			var m1 := p1.lerp(top, 0.45)
			var col := PINE if i % 2 == 0 else PINE_DARK
			b.quad(p0, p1, m1, m0, col)
			b.tri(m0, m1, top, SNOW if (i + t) % 3 != 0 else SNOW.darkened(0.06))
			# underside
			b.center = Vector3(0, y + 2.0, 0)
			b.tri(p0, p1, Vector3(0, y - 0.1, 0), PINE_DARK)
			b.center = Vector3(0, y + h * 0.3, 0)
			var _u := mid
		y += h * 0.55
		radius *= 0.72
	return b.commit()


static func _prism(b: MeshBuilder, base: Vector3, r0: float, r1: float, h: float, sides: int, col: Color) -> void:
	b.center = base + Vector3(0, h * 0.5, 0)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := base + Vector3(cos(a0) * r0, 0, sin(a0) * r0)
		var p1 := base + Vector3(cos(a1) * r0, 0, sin(a1) * r0)
		var q0 := base + Vector3(cos(a0) * r1, h, sin(a0) * r1)
		var q1 := base + Vector3(cos(a1) * r1, h, sin(a1) * r1)
		b.quad(p0, p1, q1, q0, col)
		b.tri(q0, q1, base + Vector3(0, h, 0), col)


## Angular rock with snow caught on its upper facets. ~1 m radius.
static func rock(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 400 + variant * 31
	var b := MeshBuilder.new()
	b.center = Vector3(0, 0.25, 0)
	var rings := 3
	var sides := 6
	var pts := []
	for r in rings + 1:
		var ring := []
		var v := float(r) / rings
		var y := -0.35 + v * (1.25 + rng.randf_range(-0.1, 0.15))
		var rad := sin(lerpf(0.55, 3.0, v) * 0.5 + 0.35) * 1.15
		if r == rings:
			rad = 0.15
		for i in sides:
			var a := TAU * i / sides + rng.randf_range(-0.25, 0.25) + r * 0.4
			var rr := rad * rng.randf_range(0.7, 1.25)
			ring.append(Vector3(cos(a) * rr * 1.2, y + rng.randf_range(-0.12, 0.12), sin(a) * rr))
		pts.append(ring)
	for r in rings:
		for i in sides:
			var a: Vector3 = pts[r][i]
			var c: Vector3 = pts[r][(i + 1) % sides]
			var d: Vector3 = pts[r + 1][(i + 1) % sides]
			var e: Vector3 = pts[r + 1][i]
			var base := ROCK if (i + r) % 2 == 0 else ROCK_DARK
			b.tri_snowy(a, c, d, base, SNOW, 0.62)
			b.tri_snowy(a, d, e, base, SNOW, 0.62)
	var top := Vector3(rng.randf_range(-0.1, 0.1), pts[rings][0].y + 0.1, 0)
	for i in sides:
		b.tri(pts[rings][i], pts[rings][(i + 1) % sides], top, SNOW)
	return b.commit()


## Kicker geometry, built in world space so it sits exactly on the terrain.
static func ramp(r: Dictionary, origin: Vector3) -> ArrayMesh:
	var b := MeshBuilder.new()
	var dir: Vector2 = r.dir
	var perp := Vector2(-dir.y, dir.x)
	var total: float = r.length + r.back
	var ns := 12 if r.natural else 9
	var nt := 6 if r.natural else 2
	var half: float = r.width * 0.5
	var snow := Color(0.95, 0.97, 1.0)
	var grid := []
	for i in ns + 1:
		var s := total * i / ns
		if not r.natural:
			s = r.length * i / ns
		var row := []
		for j in nt + 1:
			var t: float = -half + r.width * j / nt
			var p: Vector2 = r.start + dir * s + perp * t
			var tg := Mountain.terrain(p.x, p.y).w
			var h := tg + Mountain.ramp_profile(r, minf(s, total - 0.001), t * 0.999)
			row.append(Vector3(p.x, h + 0.01, p.y) - origin)
		grid.append(row)
	for i in ns:
		for j in nt:
			var shade := snow.darkened(0.03 * ((i + j) % 2))
			b.quad(grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j], shade)
	# Fix triangle winding: the top surface faces up.
	_force_up(b)
	if not r.natural:
		# Wooden side walls and a bright lip so the takeoff reads instantly.
		var wood := Color(0.55, 0.36, 0.22)
		for side in [0, nt]:
			for i in ns:
				var a: Vector3 = grid[i][side]
				var c: Vector3 = grid[i + 1][side]
				var a2 := a
				var c2 := c
				var p := Vector2(a.x + origin.x, a.z + origin.z)
				var q := Vector2(c.x + origin.x, c.z + origin.z)
				a2.y = Mountain.terrain(p.x, p.y).w - origin.y - 0.2
				c2.y = Mountain.terrain(q.x, q.y).w - origin.y - 0.2
				b.center = (a + c) * 0.5 + Vector3(perp.x, 0, perp.y) * (-1.0 if side == 0 else 1.0) * -5.0
				b.quad(a, c, c2, a2, wood if i % 2 == 0 else wood.darkened(0.12))
		var l0: Vector3 = grid[ns][0]
		var l1: Vector3 = grid[ns][nt]
		var down := Vector3(0, -0.0, 0)
		var front := Vector3(dir.x, 0, dir.y)
		# lip face
		var g0 := l0
		var g1 := l1
		g0.y = Mountain.terrain(l0.x + origin.x, l0.z + origin.z).w - origin.y - 0.2
		g1.y = Mountain.terrain(l1.x + origin.x, l1.z + origin.z).w - origin.y - 0.2
		b.center = (l0 + l1) * 0.5 - front * 3.0 + down
		b.quad(l0, l1, g1, g0, wood.darkened(0.2))
		# lip stripe
		var up := Vector3(0, 0.03, 0)
		var back := -front * 0.35
		b.center = null
		b.quad(l0 + up, l1 + up, l1 + up + back, l0 + up + back, Color(0.1, 0.55, 1.0))
		_force_up_last(b, 6)
	return b.commit()


static func _force_up(b: MeshBuilder) -> void:
	var i := 0
	while i < b.verts.size():
		if b.normals[i].y < 0.0:
			var t := b.verts[i + 1]
			b.verts[i + 1] = b.verts[i + 2]
			b.verts[i + 2] = t
			for k in 3:
				b.normals[i + k] = -b.normals[i + k]
		i += 3


static func _force_up_last(b: MeshBuilder, count: int) -> void:
	var i := b.verts.size() - count
	while i < b.verts.size():
		if b.normals[i].y < 0.0:
			var t := b.verts[i + 1]
			b.verts[i + 1] = b.verts[i + 2]
			b.verts[i + 2] = t
			for k in 3:
				b.normals[i + k] = -b.normals[i + k]
		i += 3


## Marker flag on a pole (used on kicker lips and blinker trees).
static func flag(col: Color) -> ArrayMesh:
	var b := MeshBuilder.new()
	_prism(b, Vector3.ZERO, 0.05, 0.04, 2.4, 4, Color(0.15, 0.15, 0.18))
	b.center = null
	var p0 := Vector3(0, 2.35, 0)
	var p1 := Vector3(0, 1.75, 0)
	var p2 := Vector3(0.75, 2.1, 0.05)
	b.tri(p0, p2, p1, col)
	b.tri(p0, p1, p2, col.darkened(0.2))
	return b.commit()


## A single huge faceted peak for the horizon. `seed` varies the outline.
static func peak(seed: int, ghost := false) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := MeshBuilder.new()
	var sides := 7
	var levels := 4
	var rings := []
	for l in levels:
		var v := float(l) / (levels - 1)
		var ring := []
		for i in sides:
			var a := TAU * i / sides + rng.randf_range(-0.2, 0.2)
			var rr := (1.0 - v * 0.82) * rng.randf_range(0.75, 1.2)
			ring.append(Vector3(cos(a) * rr, v * 0.75 + rng.randf_range(-0.04, 0.04), sin(a) * rr))
		rings.append(ring)
	var top := Vector3(rng.randf_range(-0.15, 0.15), 1.0, rng.randf_range(-0.1, 0.1))
	b.center = Vector3(0, 0.3, 0)
	var rockc := Color(0.42, 0.44, 0.52)
	for l in levels - 1:
		for i in sides:
			var a: Vector3 = rings[l][i]
			var c: Vector3 = rings[l][(i + 1) % sides]
			var d: Vector3 = rings[l + 1][(i + 1) % sides]
			var e: Vector3 = rings[l + 1][i]
			var th := 0.35 + l * 0.08
			b.tri_snowy(a, c, d, rockc, SNOW, th)
			b.tri_snowy(a, d, e, rockc.lightened(0.08), SNOW, th)
	for i in sides:
		b.tri(rings[levels - 1][i], rings[levels - 1][(i + 1) % sides], top, SNOW)
	var m := b.commit()
	return m


## The mushroom the rider eats at the top.
static func mushroom() -> ArrayMesh:
	var b := MeshBuilder.new()
	_prism(b, Vector3.ZERO, 0.018, 0.014, 0.06, 5, Color(0.96, 0.9, 0.78))
	b.center = Vector3(0, 0.06, 0)
	var sides := 7
	var cap := Color(0.85, 0.2, 0.12)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(cos(a0) * 0.05, 0.055, sin(a0) * 0.05)
		var p1 := Vector3(cos(a1) * 0.05, 0.055, sin(a1) * 0.05)
		b.tri(p0, p1, Vector3(0, 0.1, 0), cap if i % 3 else Color(1, 0.95, 0.9))
		b.tri(p0, p1, Vector3(0, 0.05, 0), Color(0.95, 0.88, 0.75))
	return b.commit()


## Snowboard: tapered outline, nose at +X. Top face y=0.03, base y=0.
static func board(top_col: Color, base_col: Color) -> ArrayMesh:
	var b := MeshBuilder.new()
	var outline := []
	var n := 14
	for i in n:
		var x := -0.78 + 1.56 * i / (n - 1)
		var w := 0.135
		var e := absf(x) - 0.62
		if e > 0.0:
			w = 0.135 * sqrt(maxf(0.0, 1.0 - pow(e / 0.17, 2))) + 0.02
		outline.append(Vector2(x, w))
	var nose_up := func(x: float) -> float: return maxf(0.0, absf(x) - 0.6) * 0.5
	b.center = Vector3(0, 0.015, 0)
	for i in n - 1:
		var a: Vector2 = outline[i]
		var c: Vector2 = outline[i + 1]
		var ya: float = nose_up.call(a.x)
		var yc: float = nose_up.call(c.x)
		var t0 := Vector3(a.x, 0.03 + ya, -a.y)
		var t1 := Vector3(c.x, 0.03 + yc, -c.y)
		var t2 := Vector3(c.x, 0.03 + yc, c.y)
		var t3 := Vector3(a.x, 0.03 + ya, a.y)
		var stripe := top_col if (i < 4 or i > n - 6) else top_col.lightened(0.25)
		b.center = Vector3((a.x + c.x) * 0.5, -5.0, 0)
		b.quad(t0, t1, t2, t3, stripe)
		b.center = Vector3((a.x + c.x) * 0.5, 5.0, 0)
		var d := Vector3(0, -0.03, 0)
		b.quad(t0 + d, t1 + d, t2 + d, t3 + d, base_col)
		b.center = Vector3((a.x + c.x) * 0.5, 0.015 + ya, 0)
		b.quad(t0, t1, t1 + d, t0 + d, base_col.darkened(0.3))
		b.quad(t3, t2, t2 + d, t3 + d, base_col.darkened(0.3))
	return b.commit()


## A self-similar branching flower (decorative hallucination, ~10 m tall).
static func fractal_flower(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := MeshBuilder.new()
	_branch(b, rng, Vector3.ZERO, Vector3.UP, 4.5, 0.32, 0)
	return b.commit()


static func _branch(b: MeshBuilder, rng: RandomNumberGenerator, p: Vector3, d: Vector3, length: float, w: float, depth: int) -> void:
	var e := p + d * length
	var side := d.cross(Vector3(0.3, 0.1, 1.0)).normalized() * w
	var side2 := d.cross(side).normalized() * w
	var depthc := Color(float(depth) / 4.0, 0, 0)  # depth encoded in red for the shader
	b.center = null
	b.quad(p - side, p + side, e + side * 0.6, e - side * 0.6, depthc, Vector2(0, depth))
	b.quad(p - side2, p + side2, e + side2 * 0.6, e - side2 * 0.6, depthc, Vector2(0, depth))
	# Flower head: ring of petals at every tip, repeated at each scale.
	var petals := 7
	var pr := length * 0.42
	var basis := Basis.looking_at(d, Vector3(0.01, 0.0, 1.0) if absf(d.y) > 0.9 else Vector3.UP)
	for i in petals:
		var a := TAU * i / petals
		var dir := basis * Vector3(cos(a), sin(a), 0.0)
		var tip := e + dir * pr + d * pr * 0.35
		var l := e + basis * Vector3(cos(a + 0.35), sin(a + 0.35), 0.0) * pr * 0.45
		var r := e + basis * Vector3(cos(a - 0.35), sin(a - 0.35), 0.0) * pr * 0.45
		var pc := Color(float(depth) / 4.0, float(i) / petals, 1.0)
		b.tri(e, l, tip, pc, Vector2(1, depth))
		b.tri(e, tip, r, pc, Vector2(1, depth))
	if depth >= 3:
		return
	var kids := 3
	for i in kids:
		var a := TAU * i / kids + rng.randf_range(-0.3, 0.3)
		var nd := (d * 1.1 + basis * Vector3(cos(a), sin(a), 0.0) * 0.9).normalized()
		var at := p.lerp(e, rng.randf_range(0.55, 0.85))
		_branch(b, rng, at, nd, length * 0.55, w * 0.6, depth + 1)
