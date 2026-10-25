extends Node3D
## Self-animating transient effect (flash, explosion, debris, tracer).
## Each mode sets up children and a tick function; the node frees itself.

var _life := 0.0
var _duration := 1.0
var _tick: Callable
var _glows: Array = []  # [mesh, base_size, life]
var _fireballs: Array = []  # [mesh, start_scale, end_scale, delay, seed]
var _shock: MeshInstance3D
var _light: OmniLight3D
var _vel := Vector3.ZERO
var _spin := Vector3.ZERO
var _trail: Trail3D
var _beam: MeshInstance3D
var _size := 1.0


func _process(delta: float) -> void:
	_life += delta
	if _tick.is_valid():
		_tick.call(delta)
	if _life >= _duration:
		queue_free()


func add_glow(color: Color, size: float, life: float, energy := 3.0, spikes := 0.0) -> void:
	var g := MeshInstance3D.new()
	g.mesh = Mats.quad()
	g.material_override = Mats.glow(color, energy, 1.8, spikes)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.scale = Vector3.ONE * size
	add_child(g)
	_glows.append([g, size, life])
	_duration = maxf(_duration if _tick.is_valid() else 0.0, life)
	if not _tick.is_valid():
		_tick = _tick_glows


func _tick_glows(_delta: float) -> void:
	for g in _glows:
		var k := clampf(_life / float(g[2]), 0.0, 1.0)
		(g[0] as MeshInstance3D).set_instance_shader_parameter("intensity", (1.0 - k) * (1.0 - k))
		(g[0] as MeshInstance3D).scale = Vector3.ONE * float(g[1]) * (1.0 + k * 0.6)


func explosion(size: float, color: Color) -> void:
	_size = size
	# Detonation flash (with lens spikes), then the wider hot glow.
	add_glow(Color(1.0, 0.92, 0.8), size * 5.0, 0.22, 7.0, 0.6)
	add_glow(color, size * 6.0, 0.7, 1.6)
	_duration = 2.2
	var n := int(clampf(size * 0.8, 4.0, 9.0))
	for i in n:
		var fb := MeshInstance3D.new()
		fb.mesh = Mats.quad()
		fb.material_override = Mats.fireball()
		fb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fb.position = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * size * 0.35
		var s0 := size * randf_range(0.6, 1.1)
		fb.scale = Vector3.ONE * s0
		fb.set_instance_shader_parameter("seed", randf())
		fb.set_instance_shader_parameter("life", 0.0)
		add_child(fb)
		_fireballs.append([fb, s0, s0 * randf_range(2.2, 3.4), randf_range(0.0, 0.15), randf()])
	_shock = MeshInstance3D.new()
	_shock.mesh = Mats.quad()
	_shock.material_override = Mats.shockwave(color.lerp(Color(1, 0.8, 0.6), 0.5))
	_shock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shock)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.3)
	_light.omni_range = size * 9.0
	_light.light_energy = 5.0
	add_child(_light)
	_tick = _tick_explosion


func _tick_explosion(delta: float) -> void:
	_tick_glows(delta)
	for f in _fireballs:
		var t := clampf((_life - float(f[3])) / 1.8, 0.0, 1.0)
		var mi: MeshInstance3D = f[0]
		var e := 1.0 - pow(1.0 - t, 3.0)
		mi.scale = Vector3.ONE * lerpf(f[1], f[2], e)
		mi.set_instance_shader_parameter("life", t)
		mi.position *= 1.0 + delta * 0.8
	var st := clampf(_life / 0.8, 0.0, 1.0)
	_shock.scale = Vector3.ONE * _size * (1.0 + st * 9.0)
	_shock.set_instance_shader_parameter("life", st)
	_light.light_energy = 5.0 * pow(maxf(0.0, 1.0 - _life / 0.9), 2.0)


func debris(mesh: Mesh, velocity: Vector3, scale_f: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Mats.hull_neutral()
	mi.scale = Vector3.ONE * maxf(0.5, scale_f)
	mi.set_instance_shader_parameter("burn", 0.8)
	mi.set_instance_shader_parameter("heat", 1.0)
	add_child(mi)
	_vel = velocity
	_spin = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	_duration = randf_range(2.0, 3.5)
	_trail = Trail3D.new()
	_trail.source = self
	_trail.width = 1.2
	_trail.lifetime = 0.8
	_trail.min_step = 1.0
	_trail.color = Color(1, 1, 1, 0.9)
	_trail.material_override = Mats.trail(Color(1.0, 0.45, 0.12), 2.0)
	add_child(_trail)
	_tick = func(delta: float):
		global_position += _vel * delta
		_vel *= 1.0 - delta * 0.3
		rotation += _spin * delta
		var k := _life / _duration
		_trail.color.a = 0.9 * (1.0 - k)
		mi.set_instance_shader_parameter("heat", 1.0 - k)
		if k > 0.85:
			mi.scale = Vector3.ONE * maxf(0.5, scale_f) * (1.0 - (k - 0.85) / 0.15)


func tracer(from: Vector3, to: Vector3, color: Color) -> void:
	_beam = MeshInstance3D.new()
	_beam.mesh = Mats.beam_mesh()
	_beam.material_override = Mats.beam(color)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	_beam.extra_cull_margin = 3000.0
	add_child(_beam)
	var length := maxf(0.1, from.distance_to(to))
	var up := Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT
	var base := Transform3D(Basis.looking_at(to - from, up), from)
	_beam.global_transform = base.scaled_local(Vector3(0.35, 0.35, length))
	_beam.set_instance_shader_parameter("beam_length", length)
	add_glow(color, 6.0, 0.25, 5.0)
	_duration = 0.7
	_tick = func(_delta: float):
		_tick_glows(_delta)
		var k := _life / _duration
		var w := 0.35 + k * 1.2
		_beam.global_transform = base.scaled_local(Vector3(w, w, length))
		_beam.set_instance_shader_parameter("intensity", pow(1.0 - k, 2.0) * 2.0)
