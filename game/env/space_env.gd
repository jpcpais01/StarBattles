class_name SpaceEnv
extends Node3D
## The Jovian theatre: the battle hangs 2,000 km above one of Jupiter's
## Galilean moons (Europa by default; Io or Ganymede on some maps), with
## Jupiter and the other moons in the sky at their true angular sizes and
## true orbital geometry. Also owns the sky, sunlight, light bounced off
## Jupiter and the home moon, exposure / eye adaptation, bloom and the
## reflection probe that puts Jupiter and the moon into every hull.
##
## Real distances do not fit in a depth buffer, so each body is drawn at a
## compressed distance with its radius scaled to keep the exact angular
## size. Bodies live in a holder that follows the camera: worlds hundreds
## of thousands of kilometres away show no parallax, exactly as in reality.

const SH_SKY := preload("res://shaders/sky.gdshader")
const SH_PLANET := preload("res://shaders/planet.gdshader")

## Visual layer used only by the celestial bodies, so the reflection probe
## can capture them (and the sky) without the battle itself.
const CELESTIAL_LAYER := 1 << 19
## How far above the home moon's surface the arena sits (km).
const ALTITUDE_KM := 2000.0
const JUPITER_R_EQ := 71492.0
const JUPITER_R_POL := 66854.0

## Real radii and orbital radii (km), plus look parameters for the shader.
const MOONS := {
	"europa": {"name": "Europa", "kind": 1, "r": 1560.8, "a": 671034.0, "map": "res://assets/planets/europa.jpg",
		"light": Color(1.0, 0.98, 0.95), "dark": Color(0.72, 0.5, 0.34), "albedo": 0.67, "phase": 1.3},
	"io": {"name": "Io", "kind": 2, "r": 1821.6, "a": 421700.0, "map": "res://assets/planets/io.jpg",
		"light": Color(1, 1, 1), "dark": Color(1, 1, 1), "albedo": 0.63, "phase": 0.2},
	"ganymede": {"name": "Ganymede", "kind": 3, "r": 2634.1, "a": 1070412.0, "map": "res://assets/planets/ganymede.jpg",
		"light": Color(0.7, 0.68, 0.64), "dark": Color(0.3, 0.27, 0.23), "albedo": 0.43, "phase": 2.6},
	"callisto": {"name": "Callisto", "kind": 4, "r": 2410.3, "a": 1882709.0, "map": "res://assets/planets/callisto.jpg",
		"light": Color(0.52, 0.49, 0.45), "dark": Color(0.2, 0.18, 0.16), "albedo": 0.22, "phase": 4.1},
}

## Which moon the battle is fought over ("europa", "io" or "ganymede").
var home_moon := "europa"

## Direction toward the sun (light travels opposite).
var sun_direction := Vector3(0.9, 0.35, 0.25).normalized()
var jupiter_direction := Vector3(-0.55, 0.32, -0.77).normalized()
var moon_direction := Vector3(0.3, -0.62, -0.72).normalized()

var world_env: WorldEnvironment
var environment: Environment
## Eye adaptation state: the exposure the "eye" has settled on, and recent
## bright flashes (explosions) that dazzle it: [position, size, time].
var adapted := 1.0
static var flashes: Array = []
var _ang_r := {}
var sun: DirectionalLight3D
var jupiter_light: DirectionalLight3D
var moon_light: DirectionalLight3D
var probe: ReflectionProbe
var holder: Node3D
var jupiter: MeshInstance3D
var moon: MeshInstance3D
var bodies: Array[MeshInstance3D] = []


## Picks the moon for a match from its shared seed so every peer agrees.
static func moon_for_seed(seed: int) -> String:
	var r := absi(seed) % 8
	return "io" if r == 3 or r == 6 else ("ganymede" if r == 5 else "europa")


func home_name() -> String:
	return MOONS[home_moon].name


func _ready() -> void:
	RenderingServer.global_shader_parameter_set("sun_dir", sun_direction)
	_build_environment()
	_build_bodies()
	_build_lights()
	_build_probe()
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
	# Space has almost no ambient light: shadows are deep, and the fills
	# below (Jupiter, the moon) do the honest work.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.032, 0.036, 0.046)
	environment.ambient_light_energy = 1.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.0
	environment.tonemap_agx_white = 4.0
	environment.tonemap_agx_contrast = 1.3
	environment.glow_enabled = true
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	environment.glow_intensity = 0.6
	environment.glow_strength = 1.0
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 1.0
	environment.glow_hdr_scale = 2.2
	environment.glow_hdr_luminance_cap = 4.0
	environment.set_glow_level(0, 0.0)
	environment.set_glow_level(1, 0.35)
	environment.set_glow_level(2, 0.8)
	environment.set_glow_level(3, 1.0)
	environment.set_glow_level(4, 0.7)
	environment.set_glow_level(5, 0.3)
	environment.set_glow_level(6, 0.0)
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.04
	environment.adjustment_saturation = 1.05
	world_env = WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)


func _build_lights() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.97, 0.93)
	sun.light_energy = 2.5
	sun.light_specular = 1.3
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 450.0
	sun.directional_shadow_split_1 = 0.18
	sun.directional_shadow_blend_splits = true
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -sun_direction, Vector3.UP)
	# Sunlight bounced off Jupiter's cloud tops: warm, scaled by how much of
	# its lit face we see and how big it hangs in the sky.
	var jdata := _body_layout()["jupiter"] as Dictionary
	var j_lit := (1.0 - sun_direction.dot(jupiter_direction)) * 0.5
	var j_size: float = pow(sin(float(jdata.ang)), 2.0)
	jupiter_light = DirectionalLight3D.new()
	jupiter_light.name = "Jupitershine"
	jupiter_light.light_color = Color(1.0, 0.86, 0.66)
	jupiter_light.light_energy = clampf(0.52 * j_lit * j_size * 45.0, 0.05, 0.35)
	jupiter_light.light_specular = 0.25
	jupiter_light.shadow_enabled = false
	add_child(jupiter_light)
	jupiter_light.look_at_from_position(Vector3.ZERO, -jupiter_direction, Vector3.UP)
	# The home moon fills half the sky below: its sunlit ice lights the
	# underside of every ship.
	var m: Dictionary = MOONS[home_moon]
	var m_ang := asin(float(m.r) / (float(m.r) + ALTITUDE_KM))
	var m_lit := (1.0 - sun_direction.dot(moon_direction)) * 0.5
	moon_light = DirectionalLight3D.new()
	moon_light.name = "Moonshine"
	moon_light.light_color = (m.light as Color).lerp(Color.WHITE, 0.3)
	moon_light.light_energy = float(m.albedo) * pow(sin(m_ang), 2.0) * m_lit * sun.light_energy * 1.4
	moon_light.light_specular = 0.4
	moon_light.shadow_enabled = false
	add_child(moon_light)
	moon_light.look_at_from_position(Vector3.ZERO, -moon_direction, Vector3.UP)


## Compressed draw distance for a real distance (km): monotonic, so
## nearer bodies always occlude farther ones, and far enough out that all
## arena geometry (rubble shell included) is always in front.
static func _draw_distance(km: float) -> float:
	return 18000.0 + 9500.0 * log(km / 3500.0) / log(10.0)


## Real geometry of the system as seen from the arena: direction, true
## distance and angular radius of every body.
func _body_layout() -> Dictionary:
	var home: Dictionary = MOONS[home_moon]
	var out := {}
	var a_home: float = home.a
	# Jupiter's spin axis is the orbital pole; we orbit in its equatorial
	# plane, so the other moons line up along the plane of its belts.
	var pole := (Vector3(0.18, 1.0, 0.12) - jupiter_direction * jupiter_direction.dot(Vector3(0.18, 1.0, 0.12))).normalized()
	var e1 := -jupiter_direction
	var e2 := pole.cross(e1).normalized()
	var j_km := a_home
	out["jupiter"] = {"dir": jupiter_direction, "km": j_km, "ang": asin(JUPITER_R_EQ / j_km), "pole": pole}
	var home_km := float(home.r) + ALTITUDE_KM
	out[home_moon] = {"dir": moon_direction, "km": home_km, "ang": asin(float(home.r) / home_km)}
	for key in MOONS.keys():
		if key == home_moon:
			continue
		var m: Dictionary = MOONS[key]
		var phase: float = m.phase
		var pos := Vector3.ZERO
		# Nudge any moon that would hide behind Jupiter or the home moon.
		for tries in 12:
			var rel := (e1 * cos(phase) + e2 * sin(phase)) * float(m.a)
			pos = jupiter_direction * j_km + rel
			var dir := pos.normalized()
			var hidden_j := dir.angle_to(jupiter_direction) < asin(JUPITER_R_EQ / j_km) * 1.4 and pos.length() > j_km
			var hidden_m := dir.angle_to(moon_direction) < float(out[home_moon].ang) * 1.1
			if not hidden_j and not hidden_m:
				break
			phase += 0.35
		out[key] = {"dir": pos.normalized(), "km": pos.length(), "ang": asin(float(m.r) / pos.length())}
	return out


func _build_bodies() -> void:
	holder = Node3D.new()
	holder.name = "Celestial"
	add_child(holder)
	var layout := _body_layout()
	var jd: Dictionary = layout["jupiter"]
	var pole: Vector3 = jd.pole
	_ang_r["jupiter"] = sin(float(jd.ang))
	_ang_r["moon"] = sin(float(layout[home_moon].ang))
	# Jupiter: oblate spheroid, axis on the orbital pole.
	var jdist := _draw_distance(float(jd.km))
	var jr := jdist * sin(float(jd.ang))
	var jx := pole.cross(Vector3(0.3, 0.1, 1.0)).normalized()
	var jz := jx.cross(pole).normalized()
	var jbasis := Basis(jx, pole, jz) * Basis.from_scale(Vector3(1.0, JUPITER_R_POL / JUPITER_R_EQ, 1.0))
	jupiter = _body("Jupiter", 0, "res://assets/planets/jupiter.jpg", jbasis.scaled_local(Vector3.ONE * jr / 0.95), jupiter_direction * jdist)
	(jupiter.material_override as ShaderMaterial).set_shader_parameter("lon_offset", 0.18)
	for key in MOONS.keys():
		var m: Dictionary = MOONS[key]
		var md: Dictionary = layout[key]
		var dist := _draw_distance(float(md.km))
		var r := dist * sin(float(md.ang))
		# Tidally locked, north on Jupiter's pole: the same face always
		# looks at Jupiter, as it does for the real Galilean moons.
		var to_j: Vector3 = (jupiter_direction * float(jd.km) - (md.dir as Vector3) * float(md.km)).normalized()
		var mz := (to_j - pole * to_j.dot(pole)).normalized()
		var mbasis := Basis(pole.cross(mz).normalized(), pole, mz)
		var mi := _body(m.name, int(m.kind), m.map, mbasis.scaled_local(Vector3.ONE * r / 0.95), (md.dir as Vector3) * dist)
		var mat := mi.material_override as ShaderMaterial
		mat.set_shader_parameter("tint_light", m.light)
		mat.set_shader_parameter("tint_dark", m.dark)
		mat.set_shader_parameter("lon_offset", 0.25)
		mat.set_shader_parameter("brightness", 1.2 if key == "europa" else 1.0)
		var js := pow(sin(float(jd.ang)), 2.0) * 9.0 if key == home_moon else 0.0
		mat.set_shader_parameter("jupiter_dir", (jupiter_direction * float(jd.km) - (md.dir as Vector3) * float(md.km)).normalized())
		mat.set_shader_parameter("jupiter_shine", js)
		if key == home_moon:
			moon = mi
			mat.set_shader_parameter("detail", 1.0)
		else:
			mat.set_shader_parameter("detail", 0.0)


func _body(body_name: String, kind: int, map_path: String, basis: Basis, pos: Vector3) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = SH_PLANET
	mat.set_shader_parameter("kind", kind)
	mat.set_shader_parameter("surface_map", load(map_path))
	mat.set_shader_parameter("body_scale", 0.95)
	var mi := MeshInstance3D.new()
	mi.name = body_name
	mi.mesh = Mats.sphere(32, 16)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 1 | CELESTIAL_LAYER
	mi.extra_cull_margin = 60000.0
	mi.transform = Transform3D(basis, pos)
	holder.add_child(mi)
	bodies.append(mi)
	return mi


## One static capture of Jupiter, the moons and the Sun: polished hulls
## and canopies mirror the real sky around them.
func _build_probe() -> void:
	probe = ReflectionProbe.new()
	probe.name = "SkyProbe"
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.size = Vector3.ONE * 16000.0
	probe.max_distance = 60000.0
	probe.cull_mask = CELESTIAL_LAYER
	probe.box_projection = false
	probe.interior = false
	probe.enable_shadows = false
	probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
	probe.intensity = 1.0
	add_child(probe)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		holder.global_position = cam.global_position
		_adapt(cam, delta)


## Registers a bright flash (explosion) for eye adaptation.
static func flash(pos: Vector3, size: float) -> void:
	flashes.append([pos, size, Time.get_ticks_msec() / 1000.0])
	if flashes.size() > 16:
		flashes.pop_front()


## Eye adaptation. Mobile GPUs can't afford (and Godot's Mobile renderer
## doesn't support) measuring the frame's luminance, so the eye works from
## what it knows is on screen: a coarse grid of view rays is traced against
## the home moon, Jupiter and the Sun (with their real phase lighting), and
## nearby explosions add a dazzle term. Exposure then eases toward the
## result like a pupil: quick to close in glare, slow to open in the dark.
func _adapt(cam: Camera3D, delta: float) -> void:
	if Settings.quality() == 0:
		environment.tonemap_exposure = 1.0
		return
	var b := cam.global_basis
	var fwd := -b.z
	var ty := tan(deg_to_rad(cam.fov * 0.5))
	var tx := ty * get_viewport().get_visible_rect().size.aspect()
	var total := 0.0
	var n := 0
	for iy in 4:
		for ix in 6:
			var u := (float(ix) + 0.5) / 6.0 * 2.0 - 1.0
			var v := (float(iy) + 0.5) / 4.0 * 2.0 - 1.0
			var d := (fwd + b.x * u * tx + b.y * v * ty).normalized()
			total += _ray_luminance(d)
			n += 1
	var lum := 0.045 + total / float(n)
	var now := Time.get_ticks_msec() / 1000.0
	for i in range(flashes.size() - 1, -1, -1):
		var f: Array = flashes[i]
		var age: float = now - float(f[2])
		if age > 1.5:
			flashes.remove_at(i)
			continue
		var to: Vector3 = (f[0] as Vector3) - cam.global_position
		var dist := maxf(to.length(), 1.0)
		var facing := clampf(to.normalized().dot(fwd) * 1.4 - 0.2, 0.0, 1.0)
		lum += minf(pow(float(f[1]) * 3.0 / dist, 2.0), 1.5) * facing * exp(-age * 3.0)
	var target := clampf(pow(0.065 / lum, 0.6), 0.62, 1.45)
	var rate := 3.5 if target < adapted else 1.1
	adapted = lerpf(adapted, target, 1.0 - exp(-delta * rate))
	environment.tonemap_exposure = adapted


func _ray_luminance(d: Vector3) -> float:
	if d.dot(sun_direction) > 0.99995:
		return 12.0
	var lum := 0.0
	for key in ["moon", "jupiter"]:
		var c: Vector3 = moon_direction if key == "moon" else jupiter_direction
		var sr: float = _ang_r.get(key, 0.0)
		var bdot := d.dot(c)
		var disc := sr * sr - (1.0 - bdot * bdot)
		if bdot <= 0.0 or disc <= 0.0:
			continue
		var t := bdot - sqrt(disc)
		var nrm := (d * t - c) / sr
		var albedo := 0.75 if key == "moon" else 0.5
		lum = maxf(lum, albedo * maxf(nrm.dot(sun_direction), 0.0) * 0.9)
	return lum


func _on_settings(_key: String) -> void:
	var q := Settings.quality()
	sun.shadow_enabled = q >= 1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q < 3 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	environment.glow_enabled = q >= 1
	probe.visible = q >= 1
	environment.sky.radiance_size = Sky.RADIANCE_SIZE_64 if q == 0 else Sky.RADIANCE_SIZE_128
	for b in bodies:
		var m := b.material_override as ShaderMaterial
		if b != jupiter and b != moon:
			continue
		m.set_shader_parameter("detail", 1.0 if q >= 1 else 0.0)
