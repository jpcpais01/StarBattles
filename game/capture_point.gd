class_name CapturePoint
extends Node3D
## Holographic objective. Progress runs -1 (KRONOS) .. +1 (AEGIS); owner
## flips at the extremes. Server simulates, clients receive progress.

const RADIUS := 170.0
const CAPTURE_TIME := 14.0

var index := 0
var letter := "A"
var progress := 0.0
var owner_team := -1
var contested := false
var counts := [0, 0]

var _sphere: MeshInstance3D
var _mat: ShaderMaterial
var _ring: MeshInstance3D
var _ring2: MeshInstance3D
var _pillar: MeshInstance3D
var _label: Label3D
var _light: OmniLight3D
var _beacon: MeshInstance3D
var _station: MeshInstance3D
var _ring_mat: ShaderMaterial
var _ring2_mat: ShaderMaterial
var _shown_owner := -99
static var _station_cache: ArrayMesh

const SH_ZONE := preload("res://shaders/capture_zone.gdshader")
const SH_RING := preload("res://shaders/holo_ring.gdshader")


func setup(i: int, pos: Vector3) -> void:
	index = i
	letter = ["A", "B", "C", "D", "E"][i]
	position = pos
	name = "Point_" + letter
	if App.is_dedicated:
		return
	_mat = ShaderMaterial.new()
	_mat.shader = SH_ZONE
	_sphere = MeshInstance3D.new()
	_sphere.mesh = Mats.sphere(64, 32)
	_sphere.material_override = _mat
	_sphere.scale = Vector3.ONE * RADIUS
	_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sphere)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.995
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 128
	ring_mesh.ring_segments = 4
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = SH_RING
	_ring_mat.set_shader_parameter("dashes", 72.0)
	_ring_mat.set_shader_parameter("speed", 0.01)
	_ring_mat.set_shader_parameter("energy", 0.9)
	_ring2_mat = ShaderMaterial.new()
	_ring2_mat.shader = SH_RING
	_ring2_mat.set_shader_parameter("dashes", 24.0)
	_ring2_mat.set_shader_parameter("speed", -0.04)
	_ring2_mat.set_shader_parameter("energy", 1.4)
	_ring = MeshInstance3D.new()
	_ring.mesh = ring_mesh
	_ring.material_override = _ring_mat
	_ring.scale = Vector3.ONE * RADIUS * 1.04
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_ring2 = MeshInstance3D.new()
	_ring2.mesh = ring_mesh
	_ring2.material_override = _ring2_mat
	_ring2.scale = Vector3.ONE * 34.0
	_ring2.rotation = Vector3(PI * 0.5, 0, 0)
	_ring2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring2)
	_station = MeshInstance3D.new()
	_station.mesh = _station_mesh()
	_station.material_override = Mats.hull_neutral()
	add_child(_station)
	_beacon = MeshInstance3D.new()
	_beacon.mesh = Mats.quad()
	_beacon.scale = Vector3.ONE * 26.0
	_beacon.position = Vector3(0, 19.5, 0)
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beacon)
	_pillar = MeshInstance3D.new()
	_pillar.mesh = Mats.beam_mesh()
	# Beam mesh runs along -Z: tip it up so the pillar stands through the zone.
	_pillar.rotation = Vector3(PI * 0.5, 0, 0)
	_pillar.position = Vector3(0, -450.0, 0)
	_pillar.scale = Vector3(1.6, 1.6, 900.0)
	_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pillar.extra_cull_margin = 500.0
	add_child(_pillar)
	_label = Label3D.new()
	_label.text = letter
	_label.font = load("res://assets/fonts/rajdhani-latin-700-normal.woff2")
	_label.font_size = 256
	_label.pixel_size = 0.12
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.shaded = false
	_label.outline_size = 0
	_label.position = Vector3(0, 48, 0)
	add_child(_label)
	_light = OmniLight3D.new()
	_light.omni_range = 120.0
	_light.light_energy = 1.2
	_light.position = Vector3(0, 19.5, 0)
	add_child(_light)
	_apply_colors()


## A compact relay station at the heart of the zone: a pressurised core,
## a habitat torus, radiator vanes and a beacon mast (~40 m across).
static func _station_mesh() -> ArrayMesh:
	if _station_cache:
		return _station_cache
	var k := MeshKit.new()
	k.cylinder(Vector3(0, -12, 0), Vector3(0, 12, 0), 4.2, 4.2, 16, MeshKit.HULL)
	k.cylinder(Vector3(0, 12, 0), Vector3(0, 15, 0), 4.2, 2.2, 16, MeshKit.DARK)
	k.cylinder(Vector3(0, -12, 0), Vector3(0, -15, 0), 4.2, 2.6, 16, MeshKit.DARK)
	k.cylinder(Vector3(0, 15, 0), Vector3(0, 19, 0), 0.35, 0.35, 6, MeshKit.DARK)
	k.ring(Vector3(0, 0, 0), Vector3.UP, 17.0, 14.5, 3.2, 40, MeshKit.PAINT)
	k.ring(Vector3(0, 0, 0), Vector3.UP, 14.6, 14.2, 0.8, 40, MeshKit.GLOW)
	for a in 4:
		var d := Vector3(cos(a * PI * 0.5 + PI * 0.25), 0, sin(a * PI * 0.5 + PI * 0.25))
		k.cylinder(d * 4.0, d * 14.5, 0.7, 0.7, 6, MeshKit.HULL)
		k.box(Vector3(0, -8, 0) + d * 9.0, Vector3(absf(d.x) * 4.5 + 0.15, 3.0, absf(d.z) * 4.5 + 0.15), MeshKit.DARK, 0.1)
	k.box(Vector3(0, 6, 0), Vector3(4.6, 0.8, 0.8), MeshKit.GLOW, 0.05)
	k.box(Vector3(0, -6, 0), Vector3(0.8, 0.8, 4.6), MeshKit.GLOW, 0.05)
	_station_cache = k.commit()
	return _station_cache


func _apply_colors() -> void:
	if _mat == null:
		return
	var own_col := App.team_color(owner_team)
	var cap_team := 0 if progress > 0.0 else 1
	_mat.set_shader_parameter("color", own_col)
	_mat.set_shader_parameter("capture_color", App.team_color(cap_team))
	_mat.set_shader_parameter("progress", absf(progress) if owner_team == -1 or (owner_team != cap_team) else 1.0)
	_mat.set_shader_parameter("contested", 1.0 if contested else 0.0)
	_ring_mat.set_shader_parameter("color", own_col)
	_ring2_mat.set_shader_parameter("color", own_col)
	if _shown_owner != owner_team:
		_shown_owner = owner_team
		_pillar.material_override = Mats.beam(own_col)
		_beacon.material_override = Mats.glow(own_col, 2.4, 2.4, 0.6)
		_station.material_override = Mats.hull_neutral() if owner_team == -1 else Mats.hull(owner_team, own_col)
		_label.modulate = own_col.lerp(Color.WHITE, 0.3)
		_light.light_color = own_col


func _process(delta: float) -> void:
	if _ring == null:
		return
	_ring.rotate_y(delta * 0.05)
	_ring.rotation.x = sin(Time.get_ticks_msec() * 0.0002 + index) * 0.2
	_ring2.rotate_object_local(Vector3.FORWARD, delta * 0.3)
	_station.rotate_y(delta * 0.08)
	_pillar.set_instance_shader_parameter("intensity", 0.08 + (0.08 if contested else 0.0))
	_pillar.set_instance_shader_parameter("beam_length", 900.0)
	_beacon.set_instance_shader_parameter("intensity", 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.004 + index))
	_apply_colors()


## Server tick. Returns the team that just captured it, or -1.
func simulate(delta: float, ships: Array) -> int:
	counts = [0, 0]
	for s in ships:
		if s.alive and s.global_position.distance_to(global_position) < RADIUS:
			counts[s.team] += 1
	contested = counts[0] > 0 and counts[1] > 0
	var diff: int = counts[0] - counts[1]
	if diff != 0 and not contested:
		var rate := (1.0 + minf(absf(diff) - 1.0, 3.0) * 0.35) / CAPTURE_TIME
		progress = clampf(progress + signf(diff) * rate * delta, -1.0, 1.0)
	elif counts[0] + counts[1] == 0 and owner_team == -1:
		progress = move_toward(progress, 0.0, delta / (CAPTURE_TIME * 2.0))
	var captured := -1
	if progress >= 1.0 and owner_team != 0:
		owner_team = 0
		captured = 0
	elif progress <= -1.0 and owner_team != 1:
		owner_team = 1
		captured = 1
	elif owner_team == 0 and progress <= 0.0:
		owner_team = -1
	elif owner_team == 1 and progress >= 0.0:
		owner_team = -1
	return captured


func set_state(p: float, owner: int, is_contested: bool) -> int:
	var prev := owner_team
	progress = p
	owner_team = owner
	contested = is_contested
	return owner if owner != prev else -2
