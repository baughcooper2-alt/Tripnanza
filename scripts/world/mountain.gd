extends Node
## Mountain (autoload): the single source of truth for the world's shape.
##
## * raw_height(): smooth analytic height field (summit peak + endless slope).
## * ground(): the *triangulated* surface the rider touches. It matches the
##   faceted terrain mesh exactly, then adds kickers on top.
## * get_cell(): deterministic content for each 60 m x 60 m section
##   (trees, rocks, kickers) generated lazily from the world seed.
##
## Downhill is +Z. The summit, where every run starts, is at the origin.

signal world_reset

const CELL := 60.0
const GRID := 2.0
const QUADS := 30

enum Kind { TREE, ROCK }
enum Section { SUMMIT, OPEN, TREES, ROCKS, JUMPS, FIRST_JUMP, BACKSIDE, SIDE }

@export var world_seed := 20261118
@export_group("Slope shape")
@export var base_slope := 0.32          ## average fall-line gradient (0.32 = ~18 deg)
@export var slope_wave_amp := 12.0      ## steeper / gentler pitches along the run
@export var slope_wave_len := 150.0
@export var summit_height := 14.0
@export var gully_depth := 8.0          ## long downhill ridges and gullies
@export_group("Content")
@export var density_growth_per_km := 0.35
@export var max_density_mult := 1.8

var _n_big := FastNoiseLite.new()
var _n_mid := FastNoiseLite.new()
var _n_small := FastNoiseLite.new()
var _n_gully := FastNoiseLite.new()
var _cells := {}
var start_height := 0.0


func _ready() -> void:
	_setup_noise()


func _setup_noise() -> void:
	var list := [_n_big, _n_mid, _n_small, _n_gully]
	var freqs := [1.0 / 230.0, 1.0 / 46.0, 1.0 / 11.0, 1.0 / 95.0]
	for i in list.size():
		var n: FastNoiseLite = list[i]
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
		n.seed = world_seed + i * 7919
		n.frequency = freqs[i]
	start_height = raw_height(0.0, 0.0)


func reset_world() -> void:
	_cells.clear()
	world_reset.emit()


# ---------------------------------------------------------------- height field

static func _smin(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


func raw_height(x: float, z: float) -> float:
	var front := -base_slope * z - slope_wave_amp * sin(z / slope_wave_len)
	var back := 0.62 * z
	var h := _smin(front, back, 8.0)
	h += summit_height * exp(-(x * x) / 2888.0) * exp(-(z * z) / 5000.0)
	var d := sqrt(x * x + z * z)
	var rough := smoothstep(10.0, 70.0, d)
	var n := _n_big.get_noise_2d(x, z) * 7.0 + _n_mid.get_noise_2d(x, z) * 2.4 \
		+ _n_small.get_noise_2d(x, z) * 0.45
	var g := _n_gully.get_noise_2d(x, z * 0.3)
	n += (g * absf(g)) * gully_depth
	h += n * rough
	# Flat ledge where the rider sits at the summit.
	var ledge := 1.0 - smoothstep(3.5, 9.0, d)
	return lerpf(h, summit_height - 2.0, ledge)


## Triangulated terrain only: Vector4(normal.x, normal.y, normal.z, height).
func terrain(x: float, z: float) -> Vector4:
	var x0 := floorf(x / GRID) * GRID
	var z0 := floorf(z / GRID) * GRID
	var fx := (x - x0) / GRID
	var fz := (z - z0) / GRID
	var h00 := raw_height(x0, z0)
	var h11 := raw_height(x0 + GRID, z0 + GRID)
	var dhdx: float
	var dhdz: float
	if fx >= fz:
		var h10 := raw_height(x0 + GRID, z0)
		dhdx = (h10 - h00) / GRID
		dhdz = (h11 - h10) / GRID
	else:
		var h01 := raw_height(x0, z0 + GRID)
		dhdx = (h11 - h01) / GRID
		dhdz = (h01 - h00) / GRID
	var h := h00 + dhdx * (x - x0) + dhdz * (z - z0)
	var n := Vector3(-dhdx, 1.0, -dhdz).normalized()
	return Vector4(n.x, n.y, n.z, h)


## Full ground including kickers. Vector4(normal, height). w is height.
func ground(x: float, z: float) -> Vector4:
	var t := terrain(x, z)
	var best := t
	var cx := int(floorf(x / CELL + 0.5))
	var cz := int(floorf(z / CELL))
	for dz in [-1, 0]:
		for dx in [-1, 0, 1]:
			var cell: Dictionary = get_cell(Vector2i(cx + dx, cz + dz))
			for r in cell.ramps:
				var s := _ramp_sample(r, x, z, t)
				if s.w > best.w:
					best = s
	return best


func height(x: float, z: float) -> float:
	return ground(x, z).w


func on_ramp(x: float, z: float) -> Dictionary:
	var cx := int(floorf(x / CELL + 0.5))
	var cz := int(floorf(z / CELL))
	for dz in [-1, 0]:
		for dx in [-1, 0, 1]:
			var cell: Dictionary = get_cell(Vector2i(cx + dx, cz + dz))
			for r in cell.ramps:
				var lp := ramp_local(r, x, z)
				if lp.x >= 0.0 and lp.x <= r.length and absf(lp.y) <= r.width * 0.5:
					return r
	return {}


# ---------------------------------------------------------------- kickers

static func ramp_profile(r: Dictionary, s: float, t: float) -> float:
	if s < 0.0:
		return 0.0
	var p := 0.0
	if s <= r.length:
		p = r.height * pow(s / r.length, 1.7)
	elif s <= r.length + r.back:
		var u: float = (s - r.length) / r.back
		p = r.height * (1.0 - u) * (1.0 - u)
	else:
		return 0.0
	var half: float = r.width * 0.5
	var at := absf(t)
	if at > half:
		return 0.0
	if r.natural:
		p *= smoothstep(half, half - 1.8, at)
	return p


func ramp_local(r: Dictionary, x: float, z: float) -> Vector2:
	var d: Vector2 = Vector2(x, z) - r.start
	var dir: Vector2 = r.dir
	return Vector2(d.dot(dir), d.dot(Vector2(-dir.y, dir.x)))


func _ramp_sample(r: Dictionary, x: float, z: float, t: Vector4) -> Vector4:
	var lp := ramp_local(r, x, z)
	var p := ramp_profile(r, lp.x, lp.y)
	if p <= 0.0:
		return Vector4(0, 1, 0, -1e9)
	var e := 0.15
	var ps := (ramp_profile(r, lp.x + e, lp.y) - ramp_profile(r, lp.x - e, lp.y)) / (2.0 * e)
	var pt := (ramp_profile(r, lp.x, lp.y + e) - ramp_profile(r, lp.x, lp.y - e)) / (2.0 * e)
	var dir: Vector2 = r.dir
	var perp := Vector2(-dir.y, dir.x)
	var grad := dir * ps + perp * pt
	var gx := -t.x / t.y + grad.x
	var gz := -t.z / t.y + grad.y
	var n := Vector3(-gx, 1.0, -gz).normalized()
	return Vector4(n.x, n.y, n.z, t.w + p)


# ---------------------------------------------------------------- obstacles

func obstacles_near(x: float, z: float) -> Array:
	var out := []
	var cx := int(floorf(x / CELL + 0.5))
	var cz := int(floorf(z / CELL))
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var cell: Dictionary = get_cell(Vector2i(cx + dx, cz + dz))
			for o in cell.obstacles:
				if o.alive and absf(o.pos.x - x) < 8.0 and absf(o.pos.z - z) < 8.0:
					out.append(o)
	return out


## Removes obstacles in a circle (used to keep blinker gates clean).
signal obstacle_removed(o: Dictionary)

func clear_area(center: Vector2, radius: float) -> void:
	var cx := int(floorf(center.x / CELL + 0.5))
	var cz := int(floorf(center.y / CELL))
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var cell: Dictionary = get_cell(Vector2i(cx + dx, cz + dz))
			for o in cell.obstacles:
				if o.alive and not o.get("external", false) \
						and Vector2(o.pos.x, o.pos.z).distance_to(center) < radius + o.r:
					o.alive = false
					obstacle_removed.emit(o)


func add_external_obstacle(pos: Vector3, r: float, top: float) -> Dictionary:
	var o := {pos = pos, r = r, top = top, kind = Kind.TREE, alive = true, external = true,
		scale = 1.0, rot = 0.0, variant = 0, mm = null, idx = -1}
	var cell: Dictionary = get_cell(cell_of(pos.x, pos.z))
	cell.obstacles.append(o)
	return o


func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(int(floorf(x / CELL + 0.5)), int(floorf(z / CELL)))


func cell_origin(c: Vector2i) -> Vector2:
	## World x/z of the cell's min corner.
	return Vector2((c.x - 0.5) * CELL, c.y * CELL)


# ---------------------------------------------------------------- section content

func get_cell(c: Vector2i) -> Dictionary:
	var cell = _cells.get(c)
	if cell == null:
		cell = _generate_cell(c)
		_cells[c] = cell
	return cell


func prune_cells(focus: Vector2i, keep_radius: int) -> void:
	for k in _cells.keys():
		if absi(k.x - focus.x) > keep_radius or absi(k.y - focus.y) > keep_radius:
			_cells.erase(k)


func section_for(c: Vector2i) -> int:
	if c.y < 0:
		return Section.BACKSIDE
	if c == Vector2i(0, 0):
		return Section.SUMMIT
	if c == Vector2i(0, 1):
		return Section.FIRST_JUMP
	if c.y <= 1:
		return Section.SIDE
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(c.x, c.y, world_seed + 11))
	var r := rng.randf()
	if c.y == 2:
		return Section.OPEN if r < 0.6 else Section.TREES
	if r < 0.24:
		return Section.OPEN
	if r < 0.50:
		return Section.TREES
	if r < 0.72:
		return Section.ROCKS
	return Section.JUMPS


func _generate_cell(c: Vector2i) -> Dictionary:
	var cell := {coord = c, section = section_for(c), obstacles = [], ramps = [], clear = []}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(c.x, c.y, world_seed))
	var o := cell_origin(c)
	var dist_km := maxf(0.0, o.y) / 1000.0
	var dens := minf(1.0 + dist_km * density_growth_per_km, max_density_mult)
	# The summit + first-jump line is always kept clear.
	cell.clear.append({a = Vector2(0, -6), b = Vector2(0, 64), r = 9.0})
	match cell.section:
		Section.SUMMIT:
			_cluster(cell, rng, Vector2(-21, 34), 7, 6.0, Kind.TREE)
			_cluster(cell, rng, Vector2(22, 44), 6, 6.0, Kind.TREE)
			_scatter(cell, rng, o, 3, Kind.ROCK, Rect2(20, 10, 10, 45))
		Section.FIRST_JUMP:
			var r := _add_ramp(cell, Vector2(0, 66), Vector2(0, 1), 7.5, 9.0, 1.7, false)
			r.first = true
			cell.clear.append({a = Vector2(0, 60), b = Vector2(0, 122), r = 11.0})
			_cluster(cell, rng, Vector2(-17, 72), 5, 5.0, Kind.TREE)
			_cluster(cell, rng, Vector2(18, 70), 5, 5.0, Kind.TREE)
			_scatter(cell, rng, o, 4, Kind.TREE, Rect2(0, 0, 60, 60))
		Section.SIDE:
			_scatter(cell, rng, o, int(6 * dens), Kind.TREE, Rect2(0, 0, 60, 60))
			_cluster(cell, rng, o + Vector2(rng.randf_range(10, 50), rng.randf_range(10, 50)),
				6, 6.0, Kind.TREE)
		Section.BACKSIDE:
			_scatter(cell, rng, o, 5, Kind.TREE, Rect2(0, 0, 60, 60))
			_scatter(cell, rng, o, 2, Kind.ROCK, Rect2(0, 0, 60, 60))
		Section.OPEN:
			_scatter(cell, rng, o, int(rng.randi_range(3, 6) * dens), Kind.TREE, Rect2(0, 0, 60, 60))
			_scatter(cell, rng, o, int(rng.randi_range(1, 3) * dens), Kind.ROCK, Rect2(0, 0, 60, 60))
			if rng.randf() < 0.55:
				var p := o + Vector2(rng.randf_range(15, 45), rng.randf_range(8, 30))
				_add_ramp(cell, p, Vector2(rng.randf_range(-0.2, 0.2), 1).normalized(),
					6.0, rng.randf_range(7, 10), rng.randf_range(1.0, 1.5), true)
		Section.TREES:
			_tree_band(cell, rng, o, dens)
		Section.ROCKS:
			_rock_garden(cell, rng, o, dens)
		Section.JUMPS:
			_jump_line(cell, rng, o, dens)
	return cell


func _in_clear(cell: Dictionary, p: Vector2, r: float) -> bool:
	for z in cell.clear:
		if _seg_dist(p, z.a, z.b) < z.r + r:
			return true
	return false


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _place(cell: Dictionary, rng: RandomNumberGenerator, p: Vector2, kind: int, scale: float) -> bool:
	var o := cell_origin(cell.coord)
	if p.x < o.x + 0.5 or p.x > o.x + CELL - 0.5 or p.y < o.y + 0.5 or p.y > o.y + CELL - 0.5:
		return false
	var r := (0.55 + 0.25 * scale) if kind == Kind.TREE else 0.85 * scale
	if p.length() < 24.0:
		return false
	if _in_clear(cell, p, r):
		return false
	for e in cell.obstacles:
		if Vector2(e.pos.x, e.pos.z).distance_to(p) < e.r + r + 0.8:
			return false
	for rp in cell.ramps:
		var lp := ramp_local(rp, p.x, p.y)
		if lp.x > -8.0 and lp.x < rp.length + rp.back + 3.0 and absf(lp.y) < rp.width * 0.5 + r + 2.0:
			return false
	var y := terrain(p.x, p.y).w
	var top := (6.0 + 5.0 * scale) if kind == Kind.TREE else 1.2 * scale + 0.4
	cell.obstacles.append({pos = Vector3(p.x, y, p.y), r = r, top = top, kind = kind,
		scale = scale, rot = rng.randf() * TAU, variant = rng.randi() % 3, alive = true,
		mm = null, idx = -1})
	return true


func _scatter(cell: Dictionary, rng: RandomNumberGenerator, o: Vector2, n: int, kind: int, area: Rect2) -> void:
	for i in n:
		var p := o + area.position + Vector2(rng.randf() * area.size.x, rng.randf() * area.size.y)
		if kind == Kind.TREE and rng.randf() < 0.5:
			_cluster(cell, rng, p, rng.randi_range(2, 4), 4.0, kind)
		else:
			_place(cell, rng, p, kind, rng.randf_range(0.6, 1.3))


func _cluster(cell: Dictionary, rng: RandomNumberGenerator, c: Vector2, n: int, spread: float, kind: int) -> void:
	for i in n:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * spread
		var s := rng.randf_range(0.6, 1.25) if kind == Kind.TREE else rng.randf_range(0.6, 2.0)
		_place(cell, rng, c + Vector2(cos(a), sin(a)) * d, kind, s)


func _tree_band(cell: Dictionary, rng: RandomNumberGenerator, o: Vector2, dens: float) -> void:
	# A tight belt of trees across the section with 1-2 lanes to thread.
	var z0 := o.y + rng.randf_range(12, 30)
	var depth := rng.randf_range(12, 20)
	var lanes := 1 + int(rng.randf() < 0.6)
	for i in lanes:
		var lx := o.x + rng.randf_range(10, 50)
		var w := rng.randf_range(4.5, 6.5)
		cell.clear.append({a = Vector2(lx, z0 - 12), b = Vector2(lx + rng.randf_range(-4, 4), z0 + depth + 12), r = w})
	var spacing := 4.6 / sqrt(dens)
	var x := o.x + 1.0
	while x < o.x + CELL:
		var z := z0
		while z < z0 + depth:
			_place(cell, rng, Vector2(x + rng.randf_range(-1.4, 1.4), z + rng.randf_range(-1.4, 1.4)),
				Kind.TREE, rng.randf_range(0.7, 1.3))
			z += spacing
		x += spacing
	_scatter(cell, rng, o, 3, Kind.TREE, Rect2(0, 0, 60, 10))
	_scatter(cell, rng, o, 1, Kind.ROCK, Rect2(0, 40, 60, 20))


func _rock_garden(cell: Dictionary, rng: RandomNumberGenerator, o: Vector2, dens: float) -> void:
	# 2-3 rock clusters with a guaranteed open route beside them.
	var route_x := o.x + rng.randf_range(8, 52)
	cell.clear.append({a = Vector2(route_x, o.y - 5), b = Vector2(route_x + rng.randf_range(-10, 10), o.y + CELL + 5), r = 5.0})
	for i in 2 + int(rng.randf() < 0.5 * dens):
		var c := o + Vector2(rng.randf_range(6, 54), rng.randf_range(8, 52))
		_cluster(cell, rng, c, int(rng.randi_range(4, 7) * dens), 6.0, Kind.ROCK)
	_scatter(cell, rng, o, 2, Kind.TREE, Rect2(0, 0, 60, 60))


func _jump_line(cell: Dictionary, rng: RandomNumberGenerator, o: Vector2, dens: float) -> void:
	var kx := o.x + rng.randf_range(14, 46)
	var kz := o.y + rng.randf_range(4, 16)
	var dir := Vector2(rng.randf_range(-0.15, 0.15), 1).normalized()
	var big := rng.randf() < 0.65
	var h := rng.randf_range(2.0, 2.9) if big else rng.randf_range(1.3, 1.8)
	var l := h * 4.2
	var r := _add_ramp(cell, Vector2(kx, kz), dir, l, rng.randf_range(6.0, 8.0), h, false)
	var lip: Vector2 = r.start + dir * r.length
	cell.clear.append({a = lip, b = lip + dir * 46.0, r = 9.0})
	if rng.randf() < 0.55:
		# Narrow approach: hazards flank the run-in, with a safe route out wide.
		var perp := Vector2(-dir.y, dir.x)
		for i in 4:
			var p: Vector2 = r.start - dir * (3.0 + i * 3.5)
			_place(cell, rng, p + perp * rng.randf_range(4.8, 6.0), Kind.ROCK, rng.randf_range(0.8, 1.4))
			_place(cell, rng, p - perp * rng.randf_range(4.8, 6.0), Kind.ROCK, rng.randf_range(0.8, 1.4))
		cell.clear.append({a = r.start - dir * 16.0, b = r.start, r = 3.0})
	else:
		cell.clear.append({a = r.start - dir * 25.0, b = r.start, r = 6.0})
	_scatter(cell, rng, o, int(4 * dens), Kind.TREE, Rect2(0, 0, 60, 60))


func _add_ramp(cell: Dictionary, start: Vector2, dir: Vector2, length: float, width: float, h: float, natural: bool) -> Dictionary:
	var r := {start = start, dir = dir.normalized(), length = length, width = width, height = h,
		natural = natural, back = 5.0 if natural else 0.0, first = false}
	cell.ramps.append(r)
	return r
