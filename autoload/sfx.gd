extends Node
## Procedural audio: every sound effect and the menu score are synthesized
## at boot on a worker thread (no audio files shipped), then played through
## pooled 2D/3D players on dedicated buses.

signal generated

const RATE := 22050
const MUSIC_RATE := 11025

var streams: Dictionary = {}
var ready_sounds := false
var progress := 0.0

var _pool: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _music: AudioStreamPlayer
var _music_name := ""
var _seed := 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)


func _setup_buses() -> void:
	for bus_name in ["SFX", "Music", "UI"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	var sfx := AudioServer.get_bus_index("SFX")
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.55
	reverb.damping = 0.6
	reverb.wet = 0.12
	reverb.dry = 0.95
	AudioServer.add_bus_effect(sfx, reverb)
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.8
	AudioServer.add_bus_effect(0, limiter)


# --- Playback ----------------------------------------------------------------

func play(sound: String, volume_db := 0.0, pitch := 1.0, bus := "SFX") -> void:
	var s: AudioStream = streams.get(sound)
	if s == null:
		return
	var player: AudioStreamPlayer = null
	for p in _pool:
		if not p.playing:
			player = p
			break
	if player == null:
		player = _pool[randi() % _pool.size()]
	player.stream = s
	player.bus = bus
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func ui(sound: String, volume_db := 0.0) -> void:
	play(sound, volume_db, 1.0, "UI")


## Positional one-shot. Players live under the current scene so they are
## cleaned up with it; a small pool is reused round-robin.
func play_at(sound: String, pos: Vector3, volume_db := 0.0, pitch := 1.0, max_dist := 900.0) -> void:
	var s: AudioStream = streams.get(sound)
	if s == null:
		return
	var scene := get_tree().current_scene
	if scene == null or not scene is Node3D:
		return
	var player: AudioStreamPlayer3D = null
	for p in _pool3d:
		if is_instance_valid(p) and not p.playing:
			player = p
			break
	_pool3d = _pool3d.filter(func(p): return is_instance_valid(p))
	if player == null:
		if _pool3d.size() >= 32:
			player = _pool3d[randi() % _pool3d.size()]
		else:
			player = AudioStreamPlayer3D.new()
			player.bus = "SFX"
			player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			player.unit_size = 40.0
			player.max_db = 3.0
			player.panning_strength = 0.8
			scene.add_child(player)
			_pool3d.append(player)
	player.stream = s
	player.max_distance = max_dist
	player.volume_db = volume_db
	player.pitch_scale = pitch * randf_range(0.95, 1.05)
	player.global_position = pos
	player.play()


func make_loop_player(sound: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = streams.get(sound)
	p.bus = "SFX"
	p.unit_size = 25.0
	p.max_distance = 600.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	return p


func play_music(track: String, fade := 2.0) -> void:
	if _music_name == track and _music.playing:
		return
	var s: AudioStream = streams.get(track)
	if s == null:
		return
	_music_name = track
	_music.stream = s
	_music.volume_db = -40.0
	_music.play()
	create_tween().tween_property(_music, "volume_db", 0.0, fade)


func stop_music(fade := 1.5) -> void:
	_music_name = ""
	var tw := create_tween()
	tw.tween_property(_music, "volume_db", -40.0, fade)
	tw.tween_callback(_music.stop)


# --- Generation ---------------------------------------------------------------

## Synthesizes every effect. Safe to call from a worker thread: it only
## builds resources and touches no scene nodes.
func generate_all() -> void:
	var defs := [
		["ui_move", _ui_move], ["ui_select", _ui_select], ["ui_back", _ui_back],
		["ui_error", _ui_error], ["pulse", _pulse], ["beam", _beam_loop],
		["rail", _rail], ["rail_charge", _rail_charge], ["missile", _missile],
		["explosion", _explosion.bind(2.4, 1.0)], ["explosion_small", _explosion.bind(0.9, 0.55)],
		["hit_hull", _hit_hull], ["hit_shield", _hit_shield], ["rock_hit", _rock_hit],
		["rock_break", _rock_break], ["engine", _engine_loop], ["boost", _boost],
		["capture", _capture], ["lock", _lock_tone], ["alarm", _alarm], ["kill", _kill],
		["countdown", _countdown], ["spawn", _spawn_whoosh],
	]
	for i in defs.size():
		var buf: PackedFloat32Array = defs[i][1].call()
		var loop: bool = defs[i][0] in ["beam", "engine"]
		streams[defs[i][0]] = _to_wav(buf, RATE, loop)
		progress = float(i + 1) / float(defs.size() + 2)
	streams["music_menu"] = _to_wav(_music_menu(), MUSIC_RATE, true)
	progress = 1.0
	ready_sounds = true
	call_deferred("emit_signal", "generated")


func _to_wav(buf: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		var v := buf[i]
		v = v / (1.0 + absf(v) * 0.25) * 1.25
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w


func _noise() -> float:
	_seed = (_seed * 1103515245 + 12345) & 0x7fffffff
	return float(_seed) / 1073741823.5 - 1.0


func _buf(dur: float, rate := RATE) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * rate))
	return b


## Crossfades the tail into the head so a buffer loops without clicks.
func _make_loop(b: PackedFloat32Array, xfade: int) -> PackedFloat32Array:
	var n := b.size() - xfade
	var out := b.slice(0, n)
	for i in xfade:
		var t := float(i) / float(xfade)
		out[i] = out[i] * t + b[n + i] * (1.0 - t)
	return out


func _ui_move() -> PackedFloat32Array:
	var b := _buf(0.06)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = sin(TAU * 1750.0 * t) * exp(-t * 90.0) * 0.35 + sin(TAU * 3500.0 * t) * exp(-t * 140.0) * 0.1
	return b


func _ui_select() -> PackedFloat32Array:
	var b := _buf(0.32)
	for i in b.size():
		var t := float(i) / RATE
		var s := sin(TAU * 880.0 * t) * exp(-t * 18.0) * 0.4
		if t > 0.06:
			var u := t - 0.06
			s += sin(TAU * 1318.5 * u) * exp(-u * 12.0) * 0.38 + sin(TAU * 2637.0 * u) * exp(-u * 30.0) * 0.08
		b[i] = s
	return b


func _ui_back() -> PackedFloat32Array:
	var b := _buf(0.22)
	for i in b.size():
		var t := float(i) / RATE
		var f := 740.0 - t * 900.0
		b[i] = sin(TAU * f * t) * exp(-t * 16.0) * 0.35
	return b


func _ui_error() -> PackedFloat32Array:
	var b := _buf(0.3)
	for i in b.size():
		var t := float(i) / RATE
		var sq := signf(sin(TAU * 196.0 * t)) * 0.15 + sin(TAU * 392.0 * t) * 0.15
		b[i] = sq * (1.0 if fmod(t, 0.15) < 0.1 else 0.0) * exp(-t * 4.0)
	return b


func _pulse() -> PackedFloat32Array:
	var b := _buf(0.2)
	var ph := 0.0
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 1700.0 * exp(-t * 26.0) + 210.0
		ph += f / RATE
		var x := sin(TAU * ph) + 0.35 * sin(TAU * ph * 3.0) + 0.2 * sin(TAU * ph * 0.5)
		lp += (_noise() - lp) * 0.3
		b[i] = (x * 0.45 * exp(-t * 18.0) + lp * 0.6 * exp(-t * 45.0))
	return b


func _beam_loop() -> PackedFloat32Array:
	var b := _buf(1.0)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var saw := fmod(t * 92.0, 1.0) * 2.0 - 1.0
		var trem := 0.75 + 0.25 * sin(TAU * 8.0 * t)
		lp += (_noise() - lp) * 0.08
		b[i] = (saw * 0.22 + sin(TAU * 184.0 * t + 0.6 * sin(TAU * 4.0 * t)) * 0.28 + sin(TAU * 1104.0 * t) * 0.05 + lp * 0.5) * trem
	return b


func _rail() -> PackedFloat32Array:
	var b := _buf(1.1)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (_noise() - lp) * 0.5
		var crack := lp * exp(-t * 28.0) * 0.9
		var boom := sin(TAU * (48.0 + 60.0 * exp(-t * 9.0)) * t) * exp(-t * 3.5) * 0.7
		var zing := sin(TAU * (4200.0 * exp(-t * 4.0) + 400.0) * t) * exp(-t * 5.0) * 0.12
		b[i] = crack + boom + zing
	return b


func _rail_charge() -> PackedFloat32Array:
	var b := _buf(0.9)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += (300.0 + t * t * 2600.0) / RATE
		b[i] = sin(TAU * ph) * 0.18 * minf(t * 4.0, 1.0) + sin(TAU * ph * 2.01) * 0.06
	return b


func _missile() -> PackedFloat32Array:
	var b := _buf(1.2)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var cut := 0.04 + 0.25 * minf(t * 3.0, 1.0)
		lp += (_noise() - lp) * cut
		lp2 += (lp - lp2) * cut
		var env := minf(t * 20.0, 1.0) * exp(-t * 2.2)
		b[i] = lp2 * 1.6 * env + sin(TAU * (140.0 + t * 90.0) * t) * 0.15 * env
	return b


func _explosion(dur: float, scale: float) -> PackedFloat32Array:
	var b := _buf(dur)
	var lp := 0.0
	var lp2 := 0.0
	var crack_t := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var cut := 0.02 + 0.3 * exp(-t * 5.0 / scale)
		lp += (_noise() - lp) * cut
		lp2 += (lp - lp2) * cut
		var env := minf(t * 200.0, 1.0) * exp(-t * 2.4 / scale)
		var rumble := sin(TAU * (32.0 + 50.0 * exp(-t * 3.0)) * t) * exp(-t * 2.0 / scale) * 0.6
		var crackle := 0.0
		if _noise() > 0.9985 - t * 0.0005:
			crack_t = 0.004
		if crack_t > 0.0:
			crack_t -= 1.0 / RATE
			crackle = _noise() * 0.5 * exp(-t * 1.5)
		b[i] = (lp2 * 2.2 * env + rumble + crackle) * scale
	return b


func _hit_hull() -> PackedFloat32Array:
	var b := _buf(0.32)
	var freqs := [523.0, 1187.0, 1873.0, 2650.0, 3410.0]
	for i in b.size():
		var t := float(i) / RATE
		var s := _noise() * 0.5 * exp(-t * 60.0)
		for k in freqs.size():
			s += sin(TAU * freqs[k] * t) * exp(-t * (14.0 + k * 9.0)) * (0.22 / (1.0 + k * 0.5))
		b[i] = s
	return b


func _hit_shield() -> PackedFloat32Array:
	var b := _buf(0.45)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += (2600.0 * exp(-t * 6.0) + 700.0) / RATE
		var shimmer := 0.6 + 0.4 * sin(TAU * 38.0 * t)
		b[i] = sin(TAU * ph) * shimmer * exp(-t * 7.0) * 0.32 + sin(TAU * ph * 1.5) * exp(-t * 12.0) * 0.1
	return b


func _rock_hit() -> PackedFloat32Array:
	var b := _buf(0.25)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (_noise() - lp) * 0.18
		b[i] = lp * 1.5 * exp(-t * 22.0) + sin(TAU * 85.0 * t) * exp(-t * 18.0) * 0.5
	return b


func _rock_break() -> PackedFloat32Array:
	var b := _buf(1.6)
	var lp := 0.0
	var grain := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (_noise() - lp) * (0.05 + 0.2 * exp(-t * 4.0))
		if _noise() > 0.996:
			grain = 1.0
		grain *= 0.995
		var g := _noise() * grain * 0.4 * exp(-t * 2.0)
		b[i] = lp * 2.0 * exp(-t * 2.8) + g + sin(TAU * (45.0 + 30.0 * exp(-t * 5.0)) * t) * exp(-t * 3.0) * 0.6
	return b


func _engine_loop() -> PackedFloat32Array:
	var xf := int(RATE * 0.25)
	var b := _buf(1.25)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (_noise() - lp) * 0.035
		lp2 += (lp - lp2) * 0.05
		b[i] = lp2 * 3.5 + sin(TAU * 55.0 * t) * 0.14 + sin(TAU * 110.0 * t) * 0.07 + _noise() * 0.015
	return _make_loop(b, xf)


func _boost() -> PackedFloat32Array:
	var b := _buf(1.0)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (_noise() - lp) * (0.03 + 0.3 * t)
		var env := minf(t * 8.0, 1.0) * exp(-t * 2.5)
		b[i] = lp * 2.2 * env + sin(TAU * (80.0 + 200.0 * t) * t) * 0.2 * env
	return b


func _bell(b: PackedFloat32Array, start: float, freq: float, amp: float, decay: float) -> void:
	var s0 := int(start * RATE)
	for i in range(s0, b.size()):
		var t := float(i - s0) / RATE
		var e := exp(-t * decay)
		if e < 0.001:
			break
		b[i] += (sin(TAU * freq * t) + 0.3 * sin(TAU * freq * 2.76 * t) * exp(-t * 6.0)) * amp * e


func _capture() -> PackedFloat32Array:
	var b := _buf(1.4)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for k in notes.size():
		_bell(b, k * 0.09, notes[k], 0.2, 3.5)
	return b


func _lock_tone() -> PackedFloat32Array:
	var b := _buf(0.09)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = signf(sin(TAU * 1320.0 * t)) * 0.12 * minf(1.0, (0.09 - t) * 80.0)
	return b


func _alarm() -> PackedFloat32Array:
	var b := _buf(0.5)
	for i in b.size():
		var t := float(i) / RATE
		var f := 980.0 if t < 0.25 else 740.0
		b[i] = (signf(sin(TAU * f * t)) * 0.1 + sin(TAU * f * t) * 0.12) * (1.0 if fmod(t, 0.25) < 0.2 else 0.0)
	return b


func _kill() -> PackedFloat32Array:
	var b := _buf(0.9)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = sin(TAU * (90.0 * exp(-t * 6.0) + 40.0) * t) * exp(-t * 7.0) * 0.6
	_bell(b, 0.04, 1567.98, 0.14, 5.0)
	_bell(b, 0.1, 2093.0, 0.1, 5.0)
	return b


func _countdown() -> PackedFloat32Array:
	var b := _buf(0.25)
	_bell(b, 0.0, 987.77, 0.25, 9.0)
	return b


func _spawn_whoosh() -> PackedFloat32Array:
	var b := _buf(1.4)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (_noise() - lp) * (0.02 + 0.12 * sin(PI * minf(t / 1.4, 1.0)))
		b[i] = lp * 2.4 * sin(PI * minf(t / 1.4, 1.0)) + sin(TAU * (60.0 + t * 40.0) * t) * 0.15 * exp(-t * 2.0)
	return b


## 16 s ambient score: four slow chords of detuned sine pads over a sub
## drone with a sparse high shimmer, crossfaded into a seamless loop.
func _music_menu() -> PackedFloat32Array:
	var rate := MUSIC_RATE
	var chord_len := 4.0
	var total := chord_len * 4.0 + 2.0
	var b := _buf(total, rate)
	var chords := [
		[146.83, 174.61, 220.0, 329.63],
		[116.54, 174.61, 233.08, 293.66],
		[98.0, 146.83, 233.08, 349.23],
		[110.0, 164.81, 220.0, 293.66],
	]
	for c in chords.size():
		var start := c * chord_len
		var s0 := int(start * rate)
		var s1 := mini(b.size(), int((start + chord_len + 2.0) * rate))
		for i in range(s0, s1):
			var t := float(i - s0) / rate
			var env := minf(t / 1.6, 1.0) * clampf((chord_len + 2.0 - t) / 2.0, 0.0, 1.0)
			var s := 0.0
			for f in chords[c]:
				s += sin(TAU * f * t) + sin(TAU * f * 1.0035 * t + 1.3) * 0.8 + sin(TAU * f * 2.0 * t) * 0.12
			b[i] += s * env * 0.045
	for i in b.size():
		var t := float(i) / rate
		b[i] += sin(TAU * 36.71 * t) * 0.12 * (0.8 + 0.2 * sin(TAU * t / 8.0))
		b[i] += sin(TAU * 1174.66 * t) * 0.012 * maxf(0.0, sin(TAU * t / 5.3)) ** 4.0
	return _make_loop(b, int(2.0 * rate))
