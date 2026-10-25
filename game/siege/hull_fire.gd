extends Node3D
## A breach that keeps burning on the mothership: a flickering core of
## flame, a column of smoke venting along the surface normal and a slow
## spray of embers. Lives until the arena goes away.

var _glow: MeshInstance3D
var _glow2: MeshInstance3D
var _smoke: GPUParticles3D
var _embers: GPUParticles3D
var _light: OmniLight3D
var _size := 30.0
var _t := randf() * 10.0

static var _smoke_pm: ParticleProcessMaterial
static var _ember_pm: ParticleProcessMaterial
static var _smoke_mesh: QuadMesh
static var _ember_mesh: QuadMesh


func setup(normal: Vector3, size: float) -> void:
	_size = size
	var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT
	global_basis = Basis.looking_at(-normal, up)
	_glow = MeshInstance3D.new()
	_glow.mesh = Mats.quad()
	_glow.material_override = Mats.glow(Color(1.0, 0.45, 0.12), 4.0, 1.6)
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.position = Vector3(0, 0, -size * 0.2)
	add_child(_glow)
	_glow2 = MeshInstance3D.new()
	_glow2.mesh = Mats.quad()
	_glow2.material_override = Mats.glow(Color(1.0, 0.75, 0.4), 5.0, 2.4)
	_glow2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow2.position = Vector3(0, 0, -size * 0.1)
	add_child(_glow2)
	_materials()
	_smoke = GPUParticles3D.new()
	_smoke.amount = maxi(6, int(18 * Settings.fx_scale()))
	_smoke.lifetime = 5.0
	_smoke.preprocess = 2.0
	_smoke.process_material = _smoke_pm
	_smoke.draw_pass_1 = _smoke_mesh
	_smoke.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke.visibility_aabb = AABB(Vector3.ONE * -12.0, Vector3.ONE * 24.0)
	_smoke.scale = Vector3.ONE * size
	_smoke.local_coords = false
	add_child(_smoke)
	_embers = GPUParticles3D.new()
	_embers.amount = maxi(4, int(14 * Settings.fx_scale()))
	_embers.lifetime = 2.2
	_embers.process_material = _ember_pm
	_embers.draw_pass_1 = _ember_mesh
	_embers.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_embers.visibility_aabb = AABB(Vector3.ONE * -10.0, Vector3.ONE * 20.0)
	_embers.scale = Vector3.ONE * size
	add_child(_embers)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.2)
	_light.omni_range = size * 4.0
	_light.light_energy = 2.0
	_light.position = Vector3(0, 0, -size * 0.6)
	add_child(_light)


func scale_up(k: float) -> void:
	_size *= k
	_smoke.scale = Vector3.ONE * _size
	_embers.scale = Vector3.ONE * _size
	_light.omni_range = _size * 4.0


static func _materials() -> void:
	if _smoke_pm:
		return
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 18.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.1
	pm.damping_min = 0.05
	pm.damping_max = 0.15
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.35))
	curve.add_point(Vector2(1, 2.4))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.12, 0.4, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.55, 0.25, 0.0), Color(0.75, 0.45, 0.3, 0.75), Color(0.35, 0.33, 0.32, 0.55), Color(0.2, 0.2, 0.2, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	_smoke_pm = pm
	_smoke_mesh = QuadMesh.new()
	_smoke_mesh.size = Vector2(1, 1)
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/dust.gdshader")
	sm.set_shader_parameter("color", Color(0.5, 0.47, 0.45))
	_smoke_mesh.material = sm
	var em := ParticleProcessMaterial.new()
	em.direction = Vector3(0, 0, -1)
	em.spread = 45.0
	em.initial_velocity_min = 0.6
	em.initial_velocity_max = 1.8
	em.damping_min = 0.1
	em.damping_max = 0.3
	em.gravity = Vector3.ZERO
	em.scale_min = 0.5
	em.scale_max = 1.0
	var er := Gradient.new()
	er.set_color(0, Color(1.0, 0.85, 0.5, 1.0))
	er.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	var egt := GradientTexture1D.new()
	egt.gradient = er
	em.color_ramp = egt
	_ember_pm = em
	_ember_mesh = QuadMesh.new()
	_ember_mesh.size = Vector2(0.03, 0.25)
	var esm := ShaderMaterial.new()
	esm.shader = preload("res://shaders/spark.gdshader")
	esm.set_shader_parameter("tint", Color(1.0, 0.6, 0.25))
	_ember_mesh.material = esm


func _process(delta: float) -> void:
	_t += delta
	var f := 0.8 + 0.2 * sin(_t * 13.0) * sin(_t * 7.3)
	_glow.scale = Vector3.ONE * _size * 1.6 * f
	_glow2.scale = Vector3.ONE * _size * 0.7 * (0.85 + 0.3 * sin(_t * 21.0))
	_light.light_energy = 2.2 * f
