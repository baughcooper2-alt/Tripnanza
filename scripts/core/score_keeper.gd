class_name ScoreKeeper
extends Node
## Score = distance points + banked tricks + blinker bonuses.

signal trick_banked(name: String, points: int, quality: String)
signal bonus_banked(label: String, points: int)

@export var points_per_metre := 2.0
@export var clean_bonus := 1.1
@export var sketchy_mult := 0.5

var distance := 0.0
var trick_points := 0
var bonus_points := 0
var best_trick := ""
var best_trick_points := 0
var tricks_landed := 0
var blinkers := 0


func reset() -> void:
	distance = 0.0
	trick_points = 0
	bonus_points = 0
	best_trick = ""
	best_trick_points = 0
	tricks_landed = 0
	blinkers = 0


func total() -> int:
	return int(distance * points_per_metre) + trick_points + bonus_points


func update_distance(z: float) -> void:
	distance = maxf(distance, z)


func on_landed(r: Dictionary) -> void:
	if r.quality == "crash" or r.name == "":
		return
	var pts: int = r.points
	if pts <= 0:
		return
	if r.quality == "sketchy":
		pts = int(pts * sketchy_mult)
	else:
		pts = int(pts * clean_bonus)
	trick_points += pts
	tricks_landed += 1
	if pts > best_trick_points:
		best_trick_points = pts
		best_trick = r.name
	trick_banked.emit(r.name, pts, r.quality)


func on_blinker(index: int, bonus: int) -> void:
	bonus_points += bonus
	blinkers = index
	bonus_banked.emit("BLINKER %d" % index, bonus)
