class_name EngineFX
extends Node3D
## One engine nozzle: turbulent plume cone, hot core glow, outer halo,
## and an ion trail. Thrust and boost drive length, brightness and the
## shock-diamond pattern; idle engines flicker softly.

var radius := 0.8
var color := Color(0.35, 0.75, 1.0)
var thrust := 0.5
var boost := 0.0
var flame: MeshInstance3D
var core: MeshInstance3D
var halo: MeshInstance3D
var trail: Trail3D
var _t := randf() * 10.0
var _smooth_thrust := 0.5


func setup(pos: Vector3, r: float, c: Color, with_trail := true) -> void:
	position = pos
	radius = r
	color = c
	flame = MeshInstance3D.new()
	flame.mesh = Mats.flame_cone()
	flame.material_override = Mats.flame(c)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame)
	core = MeshInstance3D.new()
	core.mesh = Mats.quad()
	core.material_override = Mats.glow(c.lerp(Color.WHITE, 0.5), 5.0, 2.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.position = Vector3(0, 0, 0.15)
	add_child(core)
	halo = MeshInstance3D.new()
	halo.mesh = Mats.quad()
	halo.material_override = Mats.glow(c, 1.2, 3.0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.position = Vector3(0, 0, 0.4)
	add_child(halo)
	if with_trail:
		trail = Trail3D.new()
		trail.source = self
		trail.width = r * 1.3
		trail.lifetime = 0.45
		trail.max_points = 18
		trail.min_step = 2.0
		trail.color = Color(1, 1, 1, 0.6)
		trail.material_override = Mats.trail(c, 1.4)
		add_child(trail)


func _process(delta: float) -> void:
	_t += delta
	_smooth_thrust = lerpf(_smooth_thrust, thrust, 1.0 - exp(-delta * 6.0))
	var flicker := 0.92 + 0.08 * sin(_t * 41.0) * sin(_t * 17.3)
	var length := radius * (2.0 + _smooth_thrust * 5.5 + boost * 7.0) * flicker
	var w := radius * (0.85 + boost * 0.15)
	flame.scale = Vector3(w, w, length)
	flame.set_instance_shader_parameter("thrust", _smooth_thrust)
	flame.set_instance_shader_parameter("boost", boost)
	core.scale = Vector3.ONE * radius * (2.2 + _smooth_thrust * 0.8 + boost * 1.2) * flicker
	core.set_instance_shader_parameter("intensity", 0.6 + _smooth_thrust * 0.6 + boost * 0.6)
	halo.scale = Vector3.ONE * radius * (6.0 + boost * 6.0)
	halo.set_instance_shader_parameter("intensity", 0.25 + _smooth_thrust * 0.3 + boost * 0.7)
	if trail:
		trail.width = radius * (1.0 + boost * 0.8)
		trail.color.a = 0.25 + _smooth_thrust * 0.35 + boost * 0.4
