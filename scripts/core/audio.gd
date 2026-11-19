extends Node
## Audio (autoload): music playlist, synthesized sound effects, continuous
## snow/wind loops, trip-reactive music processing and controller rumble.
## All effects are generated in code at startup (no sound files needed);
## replace any of them by dropping a file in SFX_OVERRIDES below.

const MUSIC := ["res://assets/music/high_hills.mp3", "res://assets/music/i_can_fly_away.mp3"]
const RATE := 22050
## Optional: map an effect name to a sound file to use it instead of the synth.
const SFX_OVERRIDES := {}

var music_volume := 0.8
var sfx_volume := 0.75

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _track := 0
var _fading := false
var _sfx := {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_i := 0
var _carve: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _air: AudioStreamPlayer
var _scrape: AudioStreamPlayer
var _phaser: AudioEffectPhaser
var _chorus: AudioEffectChorus
var _delay: AudioEffectDelay
var _filter: AudioEffectLowPassFilter
var _music_bus := 0
var _sfx_bus := 0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	music_volume = Settings.music_volume
	sfx_volume = Settings.sfx_volume
	_setup_buses()
	_build_sfx()
	for i in 16:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_carve = _loop_player("carve_loop")
	_wind = _loop_player("wind_loop")
	_air = _loop_player("air_loop")
	_scrape = _loop_player("scrape_loop")
	_music_a = _music_player()
	_music_b = _music_player()
	if not Settings.args.has("no-music"):
		_start_track(_music_a, 0)
	apply_volumes()


# ------------------------------------------------------------------ buses

func _setup_buses() -> void:
	for name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	_music_bus = AudioServer.get_bus_index("Music")
	_sfx_bus = AudioServer.get_bus_index("SFX")
	# Trip processing on the music: everything starts disabled/dry.
	_filter = AudioEffectLowPassFilter.new()
	_filter.cutoff_hz = 20000.0
	_phaser = AudioEffectPhaser.new()
	_phaser.depth = 0.0
	_chorus = AudioEffectChorus.new()
	_chorus.wet = 0.0
	_delay = AudioEffectDelay.new()
	_delay.tap1_level_db = -60.0
	_delay.tap2_level_db = -60.0
	_delay.feedback_active = true
	_delay.feedback_level_db = -60.0
	for e in [_filter, _phaser, _chorus, _delay]:
		AudioServer.add_bus_effect(_music_bus, e)
	# Keep stacked effects + music from clipping.
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, lim)


func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(_music_bus, linear_to_db(maxf(music_volume, 0.0001)))
	AudioServer.set_bus_volume_db(_sfx_bus, linear_to_db(maxf(sfx_volume, 0.0001)))


## Trip intensity 0..1: the music starts to swirl, double and echo.
func set_trip(intensity: float, reduced: bool) -> void:
	var k := clampf(intensity, 0.0, 1.0) * (0.4 if reduced else 1.0)
	_phaser.depth = smoothstep(0.15, 0.7, k) * 0.8
	_phaser.rate_hz = lerpf(0.1, 0.6, k)
	_phaser.feedback = 0.5 * k
	_chorus.wet = smoothstep(0.3, 0.9, k) * 0.45
	_chorus.dry = 1.0 - _chorus.wet * 0.3
	var echo := smoothstep(0.55, 1.0, k)
	_delay.tap1_level_db = lerpf(-60.0, -11.0, echo)
	_delay.tap2_level_db = lerpf(-60.0, -15.0, echo)
	_delay.feedback_level_db = lerpf(-60.0, -14.0, echo)


## Muffle the music briefly (wipeout / pause).
func set_muffled(on: bool) -> void:
	var tw := create_tween()
	tw.tween_property(_filter, "cutoff_hz", 900.0 if on else 20000.0, 0.4)


# ------------------------------------------------------------------ music

func _music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	add_child(p)
	p.finished.connect(_on_track_finished.bind(p))
	return p


func _start_track(p: AudioStreamPlayer, index: int) -> void:
	if not ResourceLoader.exists(MUSIC[index]):
		return
	var s: AudioStream = load(MUSIC[index])
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = false
	p.stream = s
	p.volume_db = 0.0
	p.play()
	_track = index


func _process(dt: float) -> void:
	# Crossfade into the next song a few seconds before this one ends.
	var cur := _music_a if _music_a.playing and not _fading else null
	if cur and cur.stream:
		var left := cur.stream.get_length() - cur.get_playback_position()
		if left < 4.0:
			_crossfade()


func _crossfade() -> void:
	_fading = true
	var nxt := (_track + 1) % MUSIC.size()
	_start_track(_music_b, nxt)
	_music_b.volume_db = -40.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_music_b, "volume_db", 0.0, 3.5)
	tw.tween_property(_music_a, "volume_db", -40.0, 3.5)
	tw.chain().tween_callback(func():
		_music_a.stop()
		var t := _music_a
		_music_a = _music_b
		_music_b = t
		_fading = false)


func _on_track_finished(p: AudioStreamPlayer) -> void:
	if p == _music_a and not _fading:
		_start_track(_music_a, (_track + 1) % MUSIC.size())


# ------------------------------------------------------------------ sfx API

## Fire a one-shot effect. volume 0..1, pitch multiplier.
func play(name: String, volume := 1.0, pitch := 1.0) -> void:
	var s = _sfx.get(name)
	if s == null:
		return
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = s
	p.volume_db = linear_to_db(maxf(volume, 0.0001))
	p.pitch_scale = clampf(pitch * rng.randf_range(0.96, 1.04), 0.3, 3.0)
	p.play()


## Continuous riding sound, updated every frame by the rider.
func set_riding(on_snow: bool, speed: float, edge: float, braking: bool, airborne: bool, spin_rate: float) -> void:
	var s01 := clampf(speed / 30.0, 0.0, 1.0)
	_set_loop(_carve, (s01 * (0.2 + 0.4 * absf(edge))) if on_snow else 0.0, 0.7 + s01 * 0.6 + absf(edge) * 0.2)
	_set_loop(_scrape, (s01 * 0.5 + 0.12) if (braking and on_snow and speed > 2.0) else 0.0, 0.9 + s01 * 0.3)
	_set_loop(_wind, 0.04 + s01 * s01 * 0.3, 0.6 + s01 * 0.8)
	_set_loop(_air, clampf(spin_rate / 9.0, 0.0, 1.0) * 0.4 if airborne else 0.0, 0.8 + clampf(spin_rate / 9.0, 0.0, 1.0) * 0.6)


func stop_riding() -> void:
	for p in [_carve, _wind, _air, _scrape]:
		_set_loop(p, 0.0, 1.0)


func _set_loop(p: AudioStreamPlayer, vol: float, pitch: float) -> void:
	var target := linear_to_db(maxf(vol, 0.0001))
	p.volume_db = lerpf(p.volume_db, target, 0.15)
	p.pitch_scale = lerpf(p.pitch_scale, clampf(pitch, 0.3, 3.0), 0.1)


func _loop_player(name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	p.stream = _sfx[name]
	p.volume_db = -80.0
	add_child(p)
	p.play()
	return p


## Controller rumble (weak, strong: 0..1).
func rumble(weak: float, strong: float, seconds: float) -> void:
	if not Settings.rumble:
		return
	for d in Input.get_connected_joypads():
		Input.start_joy_vibration(d, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), seconds)


# ------------------------------------------------------------------ synthesis

func _build_sfx() -> void:
	rng.seed = 4242
	_sfx.carve_loop = _wav(_noise_loop(2.0, 0.55, 0.0), true)
	_sfx.scrape_loop = _wav(_noise_loop(1.5, 0.25, 0.35), true)
	_sfx.wind_loop = _wav(_noise_loop(3.0, 0.97, 0.0), true)
	_sfx.air_loop = _wav(_noise_loop(1.2, 0.85, 0.0, 6.0), true)
	_sfx.pop = _wav(_mix([_thump(0.12, 120.0, 55.0, 0.9), _click(0.03, 0.6), _burst(0.12, 0.3, 0.5)]))
	_sfx.land = _wav(_mix([_thump(0.25, 90.0, 40.0, 1.0), _burst(0.35, 0.45, 0.8)]))
	_sfx.land_soft = _wav(_mix([_thump(0.18, 110.0, 60.0, 0.6), _burst(0.25, 0.55, 0.5)]))
	_sfx.sketchy = _wav(_mix([_thump(0.2, 80.0, 45.0, 0.8), _burst(0.6, 0.3, 0.8, 0.2)]))
	_sfx.crash = _wav(_mix([_thump(0.4, 70.0, 30.0, 1.0), _burst(0.9, 0.5, 1.0), _thump(0.3, 140.0, 60.0, 0.5, 0.12)]))
	_sfx.bump = _wav(_mix([_thump(0.2, 100.0, 50.0, 0.9), _burst(0.2, 0.35, 0.5), _click(0.02, 0.4)]))
	_sfx.grab = _wav(_burst(0.25, 0.9, 0.35, 0.0, true))
	_sfx.whoosh = _wav(_burst(0.6, 0.93, 0.6, 0.0, true))
	_sfx.puff = _wav(_burst(0.3, 0.6, 0.6))
	_sfx.munch = _wav(_mix([_click(0.03, 0.7), _burst(0.08, 0.2, 0.5), _click(0.03, 0.6, 0.18), _burst(0.08, 0.2, 0.4, 0.18)]))
	_sfx.board_slap = _wav(_mix([_thump(0.12, 160.0, 90.0, 0.8), _click(0.02, 0.8)]))
	_sfx.trick_clean = _wav(_arp([659.3, 830.6, 987.8, 1318.5], 0.07, 0.5, 0.45))
	_sfx.trick_sketchy = _wav(_arp([523.3, 493.9, 466.2], 0.09, 0.35, 0.35))
	_sfx.blinker = _wav(_mix([_arp([523.3, 659.3, 784.0, 1046.5, 1318.5, 1568.0], 0.05, 1.4, 0.35), _shimmer(1.6, 0.25)]))
	_sfx.blinker_near = _wav(_tone(0.5, 880.0, 0.12, 0.05))
	_sfx.phase = _wav(_swell(2.2, 110.0, 0.45))
	_sfx.ui_move = _wav(_tone(0.05, 1200.0, 0.25, 0.005))
	_sfx.ui_click = _wav(_mix([_tone(0.08, 900.0, 0.35, 0.005), _tone(0.08, 1350.0, 0.2, 0.005)]))
	_sfx.start = _wav(_mix([_arp([392.0, 523.3, 659.3, 784.0], 0.06, 0.6, 0.35), _burst(0.5, 0.9, 0.3, 0.0, true)]))
	_sfx.wipe = _wav(_burst(0.5, 0.92, 0.5, 0.0, true))
	_sfx.score_tick = _wav(_tone(0.03, 1600.0, 0.15, 0.002))
	for k in SFX_OVERRIDES:
		if ResourceLoader.exists(SFX_OVERRIDES[k]):
			_sfx[k] = load(SFX_OVERRIDES[k])


func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## Filtered noise loop. smooth: 0 = hiss, ~1 = deep rumble. crackle adds grit.
func _noise_loop(seconds: float, smooth: float, crackle: float, gust_hz := 0.0) -> PackedFloat32Array:
	var b := _buf(seconds)
	var y := 0.0
	var y2 := 0.0
	var n := b.size()
	for i in n:
		var x := rng.randf_range(-1.0, 1.0)
		y = lerpf(x, y, smooth)
		y2 = lerpf(y, y2, smooth * 0.6)
		var v := y2 * (1.0 / maxf(1.0 - smooth, 0.08)) * 0.35
		if crackle > 0.0 and rng.randf() < crackle * 0.05:
			v += rng.randf_range(-0.8, 0.8)
		if gust_hz > 0.0:
			v *= 0.6 + 0.4 * sin(TAU * gust_hz * i / RATE)
		b[i] = v
	# Crossfade the ends so the loop is seamless.
	var f := int(0.05 * RATE)
	for i in f:
		var t := float(i) / f
		b[i] = lerpf(b[n - f + i], b[i], t)
	return b


func _burst(seconds: float, smooth: float, vol: float, delay := 0.0, swell := false) -> PackedFloat32Array:
	var b := _buf(seconds + delay)
	var y := 0.0
	var start := int(delay * RATE)
	for i in range(start, b.size()):
		var t := float(i - start) / (b.size() - start)
		var env := sin(PI * t) if swell else exp(-t * 5.0) * minf(t * 60.0, 1.0)
		y = lerpf(rng.randf_range(-1.0, 1.0), y, smooth)
		b[i] = y * env * vol * (1.0 / maxf(1.0 - smooth, 0.12)) * 0.4
	return b


func _thump(seconds: float, f0: float, f1: float, vol: float, delay := 0.0) -> PackedFloat32Array:
	var b := _buf(seconds + delay)
	var ph := 0.0
	var start := int(delay * RATE)
	for i in range(start, b.size()):
		var t := float(i - start) / (b.size() - start)
		ph += TAU * lerpf(f0, f1, t) / RATE
		b[i] = sin(ph) * exp(-t * 6.0) * vol
	return b


func _click(seconds: float, vol: float, delay := 0.0) -> PackedFloat32Array:
	var b := _buf(seconds + delay)
	var start := int(delay * RATE)
	for i in range(start, b.size()):
		var t := float(i - start) / (b.size() - start)
		b[i] = rng.randf_range(-1.0, 1.0) * exp(-t * 25.0) * vol
	return b


func _tone(seconds: float, freq: float, vol: float, attack: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	for i in b.size():
		var t := float(i) / RATE
		var env := minf(t / maxf(attack, 0.001), 1.0) * exp(-t / seconds * 4.0)
		b[i] = (sin(TAU * freq * t) + 0.3 * sin(TAU * freq * 2.0 * t)) * env * vol
	return b


func _arp(notes: Array, step: float, tail: float, vol: float) -> PackedFloat32Array:
	var b := _buf(step * notes.size() + tail)
	for k in notes.size():
		var st := int(k * step * RATE)
		var f: float = notes[k]
		for i in range(st, b.size()):
			var t := float(i - st) / RATE
			var env := minf(t / 0.004, 1.0) * exp(-t * 4.5)
			b[i] += (sin(TAU * f * t) + 0.25 * sin(TAU * f * 3.0 * t) * exp(-t * 10.0)) * env * vol / sqrt(notes.size())
	return b


func _shimmer(seconds: float, vol: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	for i in b.size():
		var t := float(i) / RATE
		var env := sin(PI * minf(t / seconds, 1.0))
		var f := 2000.0 + 600.0 * sin(t * 9.0)
		b[i] = sin(TAU * f * t) * sin(TAU * 7.0 * t) * env * vol
	return b


func _swell(seconds: float, f: float, vol: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	for i in b.size():
		var t := float(i) / RATE
		var u := t / seconds
		var env := pow(u, 2.0) * (1.0 - smoothstep(0.85, 1.0, u))
		b[i] = (sin(TAU * f * t) + sin(TAU * f * 1.5 * t) * 0.6 + sin(TAU * f * 2.01 * t) * 0.4) * env * vol * 0.5
	return b


func _mix(parts: Array) -> PackedFloat32Array:
	var n := 0
	for p in parts:
		n = maxi(n, p.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for p in parts:
		for i in p.size():
			out[i] += p[i]
	return out
