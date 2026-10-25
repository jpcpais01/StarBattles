class_name Mats
## Cached materials and shared meshes so hundreds of effects reuse a
## handful of GPU resources.

static var _cache: Dictionary = {}
static var _meshes: Dictionary = {}

const SH_HULL := preload("res://shaders/hull.gdshader")
const SH_GLASS := preload("res://shaders/glass.gdshader")
const SH_FLAME := preload("res://shaders/engine_flame.gdshader")
const SH_GLOW := preload("res://shaders/glow_sprite.gdshader")
const SH_TRAIL := preload("res://shaders/trail.gdshader")
const SH_SMOKE := preload("res://shaders/smoke_trail.gdshader")
const SH_BOLT := preload("res://shaders/bolt.gdshader")
const SH_BEAM := preload("res://shaders/beam.gdshader")
const SH_SHIELD := preload("res://shaders/shield.gdshader")
const SH_FIREBALL := preload("res://shaders/fireball.gdshader")
const SH_SHOCK := preload("res://shaders/shockwave.gdshader")
const SH_ASTEROID := preload("res://shaders/asteroid.gdshader")


static func _cached(key: String, maker: Callable) -> Material:
	if not _cache.has(key):
		_cache[key] = maker.call()
	return _cache[key]


static func _shader(sh: Shader, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	for k in params.keys():
		m.set_shader_parameter(k, params[k])
	return m


static func hull(team: int, glow: Color) -> ShaderMaterial:
	var paint := App.team_color(team)
	return _cached("hull_%d_%s" % [team, glow.to_html()], func():
		return _shader(SH_HULL, {"paint_color": paint * Color(0.85, 0.85, 0.85), "glow_color": glow}))


static func hull_neutral() -> ShaderMaterial:
	return _cached("hull_neutral", func():
		return _shader(SH_HULL, {"paint_color": Color(0.75, 0.76, 0.8), "glow_color": Color(1.0, 0.85, 0.6)}))


static func glass() -> ShaderMaterial:
	return _cached("glass", func(): return _shader(SH_GLASS, {}))


static func flame(color: Color) -> ShaderMaterial:
	return _cached("flame_" + color.to_html(), func(): return _shader(SH_FLAME, {"color": color}))


static func glow(color: Color, energy := 3.0, softness := 2.2) -> ShaderMaterial:
	return _cached("glow_%s_%.2f_%.2f" % [color.to_html(), energy, softness], func():
		return _shader(SH_GLOW, {"color": color, "energy": energy, "softness": softness}))


## Solid glowing surface (reactor cores, generator orbs, energy rings).
static func glow_solid(color: Color, energy := 4.0) -> StandardMaterial3D:
	return _cached("glow_solid_%s_%.2f" % [color.to_html(), energy], func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.BLACK
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
		m.roughness = 1.0
		m.metallic_specular = 0.0
		return m)


static func trail(color: Color, energy := 1.6) -> ShaderMaterial:
	return _cached("trail_%s_%.2f" % [color.to_html(), energy], func():
		return _shader(SH_TRAIL, {"color": color, "energy": energy}))


static func smoke() -> ShaderMaterial:
	return _cached("smoke", func(): return _shader(SH_SMOKE, {}))


static func bolt() -> ShaderMaterial:
	return _cached("bolt", func(): return _shader(SH_BOLT, {}))


static func beam(color: Color) -> ShaderMaterial:
	return _cached("beam_" + color.to_html(), func(): return _shader(SH_BEAM, {"color": color}))


static func fireball() -> ShaderMaterial:
	return _cached("fireball", func(): return _shader(SH_FIREBALL, {}))


static func shockwave(color: Color) -> ShaderMaterial:
	return _cached("shock_" + color.to_html(), func(): return _shader(SH_SHOCK, {"color": color}))


static func asteroid(variant: int) -> ShaderMaterial:
	return _cached("asteroid_%d" % variant, func():
		var palettes := [
			[Color(0.32, 0.29, 0.27), Color(0.16, 0.15, 0.14), Color(0.45, 0.4, 0.34)],
			[Color(0.36, 0.33, 0.31), Color(0.2, 0.18, 0.17), Color(0.5, 0.46, 0.42)],
			[Color(0.28, 0.25, 0.22), Color(0.12, 0.11, 0.1), Color(0.5, 0.38, 0.28)],
		]
		var p: Array = palettes[variant % palettes.size()]
		return _shader(SH_ASTEROID, {"rock_a": p[0], "rock_b": p[1], "rock_c": p[2]}))


static func shield(color: Color) -> ShaderMaterial:
	# Unique per ship: impact position/time are per-instance state.
	return _shader(SH_SHIELD, {"color": color, "hit_time": -10.0})


# --- Shared meshes -----------------------------------------------------------

static func quad() -> QuadMesh:
	if not _meshes.has("quad"):
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		_meshes["quad"] = q
	return _meshes["quad"]


## Unit cone along +Z (radius 1 at z=0 tapering to a point at z=1).
static func flame_cone() -> ArrayMesh:
	if _meshes.has("cone"):
		return _meshes["cone"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 14
	var rings := 6
	for r in rings:
		var z0 := float(r) / rings
		var z1 := float(r + 1) / rings
		var r0 := pow(1.0 - z0, 0.7) * (1.0 + 0.25 * sin(z0 * PI))
		var r1 := pow(1.0 - z1, 0.7) * (1.0 + 0.25 * sin(z1 * PI))
		for i in sides:
			var a0 := TAU * float(i) / sides
			var a1 := TAU * float(i + 1) / sides
			var p00 := Vector3(cos(a0) * r0, sin(a0) * r0, z0)
			var p01 := Vector3(cos(a1) * r0, sin(a1) * r0, z0)
			var p10 := Vector3(cos(a0) * r1, sin(a0) * r1, z1)
			var p11 := Vector3(cos(a1) * r1, sin(a1) * r1, z1)
			var n0 := Vector3(cos(a0), sin(a0), 0.3).normalized()
			var n1 := Vector3(cos(a1), sin(a1), 0.3).normalized()
			for v in [[p00, n0, Vector2(float(i) / sides, z0)], [p10, n0, Vector2(float(i) / sides, z1)], [p11, n1, Vector2(float(i + 1) / sides, z1)],
					[p00, n0, Vector2(float(i) / sides, z0)], [p11, n1, Vector2(float(i + 1) / sides, z1)], [p01, n1, Vector2(float(i + 1) / sides, z0)]]:
				st.set_normal(v[1])
				st.set_uv(v[2])
				st.add_vertex(v[0])
	_meshes["cone"] = st.commit()
	return _meshes["cone"]


## Two crossed quads along -Z, for bolts (UV.y runs along the length).
static func bolt_mesh() -> ArrayMesh:
	if _meshes.has("bolt"):
		return _meshes["bolt"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in [Vector3.RIGHT, Vector3.UP]:
		var a: Vector3 = axis * 0.5
		var verts := [[-a + Vector3(0, 0, 0.5), Vector2(0, 0)], [a + Vector3(0, 0, 0.5), Vector2(1, 0)],
			[a + Vector3(0, 0, -0.5), Vector2(1, 1)], [-a + Vector3(0, 0, -0.5), Vector2(0, 1)]]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_uv(verts[idx][1])
			st.set_normal(Vector3.BACK)
			st.add_vertex(verts[idx][0])
	_meshes["bolt"] = st.commit()
	return _meshes["bolt"]


## Unit cylinder from z=0 to z=-1 (beams, rail tracers).
static func beam_mesh() -> ArrayMesh:
	if _meshes.has("beam"):
		return _meshes["beam"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 8
	for i in sides:
		var a0 := TAU * float(i) / sides
		var a1 := TAU * float(i + 1) / sides
		var d0 := Vector3(cos(a0), sin(a0), 0)
		var d1 := Vector3(cos(a1), sin(a1), 0)
		for v in [[d0, 0.0], [d1, 0.0], [d1, -1.0], [d0, 0.0], [d1, -1.0], [d0, -1.0]]:
			st.set_normal(v[0])
			st.set_uv(Vector2(0, -v[1]))
			st.add_vertex(v[0] + Vector3(0, 0, v[1]))
	_meshes["beam"] = st.commit()
	return _meshes["beam"]


static func sphere(radial := 24, rings := 12) -> SphereMesh:
	var key := "sphere_%d_%d" % [radial, rings]
	if not _meshes.has(key):
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = radial
		s.rings = rings
		_meshes[key] = s
	return _meshes[key]
