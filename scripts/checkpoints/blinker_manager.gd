class_name BlinkerManager
extends Node3D
## BLINKER distance checkpoints. The next gate is placed on the rider's
## projected line well ahead of time, between two trees, with a luminous seam
## across the whole slope so it can be crossed (and seen) from anywhere.

signal crossed(index: int, bonus: int)

@export var interval := 150.0           ## metres between blinkers
@export var first_at := 150.0
@export var spawn_ahead := 140.0        ## how far ahead the gate appears
@export var bonus_base := 500
@export var bonus_step := 250
@export var gate_width := 12.0

var rider: Rider
var tracks: Tracks
var next_index := 1
var _gate: BlinkerGate
var _old: Array[Node3D] = []


func gate_z(i: int) -> float:
	return first_at + (i - 1) * interval


func next_z() -> float:
	return gate_z(next_index)


func reset() -> void:
	next_index = 1
	for g in _old:
		if is_instance_valid(g):
			g.queue_free()
	_old.clear()
	if _gate:
		_gate.queue_free()
		_gate = null
	RenderingServer.global_shader_parameter_set("gate_line_z", next_z())
	RenderingServer.global_shader_parameter_set("gate_line_glow", 0.0)


func _process(_dt: float) -> void:
	if rider == null:
		return
	var z := next_z()
	var to_go := z - rider.global_position.z
	RenderingServer.global_shader_parameter_set("gate_line_z", z)
	RenderingServer.global_shader_parameter_set("gate_line_glow", smoothstep(spawn_ahead + 40.0, 30.0, to_go) * 1.2)
	if _gate == null and to_go < spawn_ahead and rider.is_controllable():
		_spawn(z)
	if _gate:
		_gate.approach(rider.global_position)
	if to_go <= 0.0 and rider.is_controllable():
		var idx := next_index
		var bonus := bonus_base + bonus_step * (idx - 1)
		next_index += 1
		if _gate:
			_gate.cross(rider)
			_old.append(_gate)
			_gate = null
		RenderingServer.global_shader_parameter_set("gate_wave_origin", rider.global_position)
		RenderingServer.global_shader_parameter_set("gate_wave_time", TripDirector.now)
		if tracks:
			tracks.split(2.6, TripDirector.now)
		crossed.emit(idx, bonus)
	for g in _old.duplicate():
		if not is_instance_valid(g):
			_old.erase(g)
		elif g.global_position.z < rider.global_position.z - 120.0:
			g.queue_free()
			_old.erase(g)


func _spawn(z: float) -> void:
	# Aim at where the rider's current heading will cross the line.
	var p := rider.global_position
	var h := rider.cam_heading
	var dz := z - p.z
	var x := p.x
	if h.z > 0.3:
		x += clampf(h.x / h.z * dz, -30.0, 30.0)
	var center := Vector2(x, z)
	Mountain.clear_area(center, gate_width * 0.5 + 6.0)
	_gate = BlinkerGate.new()
	_gate.style = (next_index - 1) % 4
	_gate.index = next_index
	_gate.width = gate_width
	add_child(_gate)
	_gate.global_position = Vector3(x, Mountain.terrain(x, z).w, z)
	_gate.build()
