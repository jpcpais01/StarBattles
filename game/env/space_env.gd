class_name SpaceEnv
extends Node3D
## The Saturn theatre: sky, sun, Saturnshine fill light, and the celestial
## bodies (Saturn, rings, moons). Bodies live in a holder that follows the
## camera, so they sit "at infinity" with no parallax — exactly how a world
## thousands of kilometres away behaves — while staying inside depth range.

const SH_SKY := preload("res://shaders/sky.gdshader")
const SH_SATURN := preload("res://shaders/saturn.gdshader")
const SH_RINGS := preload("res://shaders/rings.gdshader")
const SH_MOON := preload("res://shaders/moon.gdshader")

## Direction toward the sun (light travels opposite).
var sun_direction := Vector3(-0.85, 0.3, -0.2).normalized()
var saturn_direction := Vector3(0.42, 0.2, -1.0).normalized()
var saturn_distance := 12500.0
var saturn_radius := 2350.0

var world_env: WorldEnvironment
var environment: Environment
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var holder: Node3D
var saturn: MeshInstance3D
var rings: MeshInstance3D


func _ready() -> void:
	RenderingServer.global_shader_parameter_set("sun_dir", sun_direction)
	_build_environment()
	_build_lights()
	_build_bodies()
	Settings.changed.connect(_on_settings)
	_on_settings("*")


func _build_environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SH_SKY
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.07, 0.085, 0.12)
	environment.ambient_light_energy = 1.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.05
	environment.tonemap_white = 6.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.75
	environment.glow_strength = 1.0
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.1
	environment.glow_hdr_scale = 2.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.set_glow_level(0, 0.0)
	environment.set_glow_level(1, 0.6)
	environment.set_glow_level(2, 1.0)
	environment.set_glow_level(3, 0.8)
	environment.set_glow_level(4, 0.6)
	environment.set_glow_level(5, 0.4)
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.06
	environment.adjustment_saturation = 1.1
	world_env = WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)


func _build_lights() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.light_energy = 2.4
	sun.light_specular = 1.2
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 450.0
	sun.directional_shadow_split_1 = 0.18
	sun.directional_shadow_blend_splits = true
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -sun_direction, Vector3.UP)
	# Warm light bouncing off Saturn's cloud tops.
	fill = DirectionalLight3D.new()
	fill.name = "Saturnshine"
	fill.light_color = Color(1.0, 0.82, 0.58)
	fill.light_energy = 0.22
	fill.light_specular = 0.3
	fill.shadow_enabled = false
	add_child(fill)
	fill.look_at_from_position(Vector3.ZERO, -saturn_direction, Vector3.UP)


func _build_bodies() -> void:
	holder = Node3D.new()
	holder.name = "Celestial"
	add_child(holder)
	var center := saturn_direction * saturn_distance
	# Saturn's axis tilted so the rings open up nicely toward us.
	var tilt := Basis(Vector3(1, 0, 0.3).normalized(), deg_to_rad(24.0)) * Basis(Vector3.UP, deg_to_rad(30.0))
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	var smat := ShaderMaterial.new()
	smat.shader = SH_SATURN
	saturn = MeshInstance3D.new()
	saturn.name = "Saturn"
	saturn.mesh = sphere
	saturn.material_override = smat
	saturn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	saturn.extra_cull_margin = 20000.0
	saturn.transform = Transform3D(tilt.scaled(Vector3.ONE * saturn_radius), center)
	holder.add_child(saturn)
	var rmat := ShaderMaterial.new()
	rmat.shader = SH_RINGS
	rings = MeshInstance3D.new()
	rings.name = "Rings"
	rings.mesh = _annulus(1.1, 2.36, 256)
	rings.material_override = rmat
	rings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rings.extra_cull_margin = 20000.0
	rings.transform = saturn.transform
	holder.add_child(rings)
	# Moons orbit near the ring plane; distances kept beyond the arena.
	var ring_x := tilt.x.normalized()
	var ring_z := tilt.z.normalized()
	var moons := [
		{"name": "Titan", "orbit": 3.4, "angle": 2.1, "r": 150.0, "albedo": Color(0.85, 0.6, 0.3), "dark": Color(0.7, 0.45, 0.2), "haze": 0.85},
		{"name": "Rhea", "orbit": 2.9, "angle": -2.5, "r": 62.0, "albedo": Color(0.82, 0.8, 0.78), "dark": Color(0.55, 0.53, 0.5), "haze": 0.0},
		{"name": "Enceladus", "orbit": 2.55, "angle": 3.7, "r": 34.0, "albedo": Color(0.97, 0.98, 1.0), "dark": Color(0.82, 0.86, 0.92), "haze": 0.0},
		{"name": "Mimas", "orbit": 2.45, "angle": -1.0, "r": 26.0, "albedo": Color(0.75, 0.74, 0.72), "dark": Color(0.45, 0.44, 0.42), "haze": 0.0},
		{"name": "Iapetus", "orbit": 4.6, "angle": 0.5, "r": 70.0, "albedo": Color(0.8, 0.76, 0.7), "dark": Color(0.2, 0.17, 0.14), "haze": 0.0},
	]
	for i in moons.size():
		var m: Dictionary = moons[i]
		var offset: Vector3 = (ring_x * cos(m.angle) + ring_z * sin(m.angle)) * saturn_radius * float(m.orbit)
		var pos: Vector3 = center + offset
		if pos.length() < 7000.0:
			pos = pos.normalized() * 7000.0
		var mm := ShaderMaterial.new()
		mm.shader = SH_MOON
		mm.set_shader_parameter("albedo", m.albedo)
		mm.set_shader_parameter("albedo_dark", m.dark)
		mm.set_shader_parameter("haze", m.haze)
		mm.set_shader_parameter("seed", float(i) * 3.7)
		var moon := MeshInstance3D.new()
		moon.name = m.name
		moon.mesh = Mats.sphere(48, 24)
		moon.material_override = mm
		moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		moon.extra_cull_margin = 20000.0
		moon.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * float(m.r)), pos)
		holder.add_child(moon)


func _annulus(r_in: float, r_out: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in segments:
		var a0 := TAU * float(i) / segments
		var a1 := TAU * float(i + 1) / segments
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		for v in [p0 * r_in, p0 * r_out, p1 * r_out, p0 * r_in, p1 * r_out, p1 * r_in]:
			st.add_vertex(v)
	return st.commit()


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		holder.global_position = cam.global_position


func _on_settings(_key: String) -> void:
	var q := Settings.quality()
	sun.shadow_enabled = q >= 1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q < 3 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	environment.glow_enabled = q >= 1
	environment.sky.radiance_size = Sky.RADIANCE_SIZE_64 if q == 0 else Sky.RADIANCE_SIZE_128
