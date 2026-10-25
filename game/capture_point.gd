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

const SH_ZONE := preload("res://shaders/capture_zone.gdshader")


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
	_sphere.mesh = Mats.sphere(48, 24)
	_sphere.material_override = _mat
	_sphere.scale = Vector3.ONE * RADIUS
	_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sphere)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.97
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 96
	ring_mesh.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.mesh = ring_mesh
	_ring.scale = Vector3.ONE * RADIUS * 1.06
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_ring2 = MeshInstance3D.new()
	_ring2.mesh = ring_mesh
	_ring2.scale = Vector3.ONE * RADIUS * 0.55
	_ring2.rotation = Vector3(PI * 0.5, 0, 0)
	_ring2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring2)
	_beacon = MeshInstance3D.new()
	_beacon.mesh = Mats.quad()
	_beacon.scale = Vector3.ONE * 60.0
	add_child(_beacon)
	var pillar := CylinderMesh.new()
	pillar.top_radius = 1.0
	pillar.bottom_radius = 1.0
	pillar.height = 1.0
	pillar.radial_segments = 12
	pillar.cap_top = false
	pillar.cap_bottom = false
	_pillar = MeshInstance3D.new()
	_pillar.mesh = pillar
	_pillar.scale = Vector3(5.0, 900.0, 5.0)
	_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pillar)
	_label = Label3D.new()
	_label.text = letter
	_label.font = load("res://assets/fonts/rajdhani-latin-700-normal.woff2")
	_label.font_size = 256
	_label.pixel_size = 0.25
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.shaded = false
	_label.outline_size = 0
	_label.position = Vector3(0, 0, 0)
	add_child(_label)
	_light = OmniLight3D.new()
	_light.omni_range = RADIUS * 1.2
	_light.light_energy = 1.5
	add_child(_light)
	_apply_colors()


func _apply_colors() -> void:
	if _mat == null:
		return
	var own_col := App.team_color(owner_team)
	var cap_team := 0 if progress > 0.0 else 1
	_mat.set_shader_parameter("color", own_col)
	_mat.set_shader_parameter("capture_color", App.team_color(cap_team))
	_mat.set_shader_parameter("progress", absf(progress) if owner_team == -1 or (owner_team != cap_team) else 1.0)
	_mat.set_shader_parameter("contested", 1.0 if contested else 0.0)
	_ring.material_override = Mats.glow(own_col, 2.0, 1.0)
	_ring2.material_override = Mats.glow(own_col, 1.2, 1.0)
	_pillar.material_override = Mats.beam(own_col)
	_beacon.material_override = Mats.glow(own_col, 1.5, 3.0)
	_label.modulate = own_col.lerp(Color.WHITE, 0.3)
	_light.light_color = own_col


func _process(delta: float) -> void:
	if _ring == null:
		return
	_ring.rotate_y(delta * 0.15)
	_ring.rotation.x = sin(Time.get_ticks_msec() * 0.0003 + index) * 0.25
	_ring2.rotate_object_local(Vector3.FORWARD, delta * 0.4)
	_pillar.set_instance_shader_parameter("intensity", 0.15 + (0.1 if contested else 0.0))
	_pillar.set_instance_shader_parameter("beam_length", 900.0)
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
