class_name CameraRig
extends Camera3D
## Third-person chase camera: critically-damped follow in the ship's frame,
## speed/boost FOV punch, trauma-based shake, look-back, a slow orbit when
## the ship is destroyed, and drifting dust motes that sell velocity.

var ship: Ship
var trauma := 0.0
var look_back := false
var orbit_center := Vector3.ZERO
var _orbit_angle := 0.0
var _noise := FastNoiseLite.new()
var _t := 0.0
var _dust: GPUParticles3D
var _fov := 72.0
var _smooth_basis := Basis.IDENTITY
var _initialized := false


func _ready() -> void:
	near = 0.3
	far = 20000.0
	_noise.frequency = 2.2
	current = true
	_build_dust()


func _build_dust() -> void:
	if App.is_dedicated:
		return
	_dust = GPUParticles3D.new()
	_dust.amount = maxi(16, int(140 * Settings.fx_scale()))
	_dust.lifetime = 3.0
	_dust.preprocess = 3.0
	_dust.local_coords = false
	_dust.visibility_aabb = AABB(Vector3(-150, -150, -150), Vector3(300, 300, 300))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(90, 60, 90)
	pm.direction = Vector3(0, 0, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.26), Color(1, 1, 1, 0.26), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	_dust.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(0.8, 0.85, 0.95)
	q.material = m
	_dust.draw_pass_1 = q
	add_child(_dust)


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount * float(Settings.get_value("camera_shake", 1.0)), 0.0, 1.0)


func _process(delta: float) -> void:
	_t += delta
	trauma = maxf(0.0, trauma - delta * 1.4)
	if ship == null or not is_instance_valid(ship):
		return
	if ship.alive:
		_follow(delta)
	else:
		_orbit(delta)
	if trauma > 0.0:
		var s := trauma * trauma
		h_offset = _noise.get_noise_2d(_t * 60.0, 0.0) * s * 0.8
		v_offset = _noise.get_noise_2d(0.0, _t * 60.0) * s * 0.8
		rotate_object_local(Vector3.FORWARD, _noise.get_noise_2d(_t * 40.0, 50.0) * s * 0.04)
	else:
		h_offset = 0.0
		v_offset = 0.0
	if _dust:
		_dust.global_position = global_position - global_basis.z * 40.0


func _follow(delta: float) -> void:
	var d: Dictionary = ship.def
	var dist: float = d.camera_dist
	var height: float = d.camera_height
	var sb := ship.global_basis.orthonormalized()
	if not _initialized:
		_smooth_basis = sb
		_initialized = true
	# Rotation lags slightly behind the ship so turns read on screen.
	_smooth_basis = _smooth_basis.slerp(sb, 1.0 - exp(-delta * 9.0)).orthonormalized()
	var speed_k := clampf(ship.velocity.length() / float(d.boost_speed), 0.0, 1.0)
	var back := dist * (1.0 + speed_k * 0.18)
	var offset := Vector3(0, height, back)
	if look_back:
		offset = Vector3(0, height * 0.8, -dist * 1.1)
	var desired_pos := ship.global_position + _smooth_basis * offset
	global_position = desired_pos
	var look_dir := -_smooth_basis.z if not look_back else _smooth_basis.z
	var focus := ship.global_position + look_dir * 80.0 + _smooth_basis.y * height * 0.35
	look_at(focus, _smooth_basis.y)
	var base_fov := float(Settings.get_value("fov", 72.0))
	var target_fov := base_fov + speed_k * 8.0 + (6.0 if ship.boosting else 0.0)
	_fov = lerpf(_fov, target_fov, 1.0 - exp(-delta * 4.0))
	fov = _fov


func _orbit(delta: float) -> void:
	_orbit_angle += delta * 0.25
	var p := orbit_center + Vector3(cos(_orbit_angle), 0.35, sin(_orbit_angle)) * 70.0
	global_position = global_position.lerp(p, 1.0 - exp(-delta * 2.0))
	look_at(orbit_center, Vector3.UP)
	_initialized = false
