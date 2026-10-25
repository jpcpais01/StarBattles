class_name MothershipPart
extends Node3D
## One destructible system on the mothership: a flak or heavy turret, a
## shield generator, or the reactor core. Turrets are articulated (base ->
## yaw ring -> pitch cradle -> recoiling barrels) and slew toward whatever the
## server tells them to track. Exposes the same duck-typed fields a Ship
## does (alive, team, velocity, radius) so bots, missiles and the HUD can
## treat it as a target.

const KINDS := {
	"flak": {"hp": 2600.0, "radius": 26.0, "label": "FLAK BATTERY", "weapon": "capital_flak",
		"slew": 1.5, "burst": 4, "burst_gap": 0.11, "reload": 1.1, "range": 1650.0, "score": 250},
	"heavy": {"hp": 5200.0, "radius": 40.0, "label": "HEAVY CANNON", "weapon": "capital_cannon",
		"slew": 0.55, "burst": 3, "burst_gap": 0.3, "reload": 3.4, "range": 2700.0, "score": 400},
	"generator": {"hp": 3500.0, "radius": 46.0, "label": "SHIELD GENERATOR", "score": 600},
	"core": {"hp": 9000.0, "radius": 70.0, "label": "REACTOR CORE", "score": 1500},
}

var index := 0
var kind := "flak"
var team := 0
var spec: Dictionary
var hp := 1.0
var max_hp := 1.0
var alive := true
## The core only takes damage once the armour is gone.
var exposed := true
var radius := 30.0
var velocity := Vector3.ZERO
var label := ""
var up_local := Vector3.UP

# Turret state (server drives target and firing; every peer animates).
var target_id := -1
var cooldown := 0.0
var burst_left := 0
var burst_t := 0.0
var aim_error := Vector3.ZERO
## Local time of the last visible hit (HUD warnings for defenders).
var last_hit_ms := -100000

var yaw_pivot: Node3D
var pitch_pivot: Node3D
var slide: Node3D
var muzzles: Array[Node3D] = []
var hit_area: Area3D
var meshes: Array[GeometryInstance3D] = []
var _muzzle_i := 0
var _recoil := 0.0
var _flash: MeshInstance3D
var _flash_t := 0.0
var _glow: MeshInstance3D
var _glow_ring: MeshInstance3D
var _beam: MeshInstance3D
var _shutters: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _hit_flash := 0.0
var _t := randf() * 10.0


func setup(i: int, k: String, t: int, pos: Vector3, up: Vector3, material: Material) -> void:
	index = i
	kind = k
	team = t
	spec = KINDS[k]
	max_hp = float(spec.hp)
	hp = max_hp
	radius = float(spec.radius)
	label = str(spec.label)
	exposed = kind != "core"
	name = "%s_%d" % [kind.capitalize(), i]
	up_local = up.normalized()
	# Stand on the surface: +Y along the surface normal, -Z toward the bow.
	var z := Vector3.BACK - up_local * up_local.dot(Vector3.BACK)
	if z.length() < 0.1:
		z = Vector3.RIGHT
	z = z.normalized()
	var x := up_local.cross(z).normalized()
	transform = Transform3D(Basis(x, up_local, z), pos)
	yaw_pivot = Node3D.new()
	add_child(yaw_pivot)
	pitch_pivot = Node3D.new()
	yaw_pivot.add_child(pitch_pivot)
	slide = Node3D.new()
	pitch_pivot.add_child(slide)
	match kind:
		"flak":
			_build_flak(material)
		"heavy":
			_build_heavy(material)
		"generator":
			_build_generator(material)
		"core":
			_build_core(material)
	hit_area = Area3D.new()
	hit_area.collision_layer = 2
	hit_area.collision_mask = 0
	hit_area.monitoring = false
	hit_area.set_meta("mpart", index)
	hit_area.set_meta("mteam", team)
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = radius * (0.8 if kind != "core" else 0.9)
	cs.shape = sph
	cs.position = Vector3(0, radius * 0.45, 0)
	hit_area.add_child(cs)
	add_child(hit_area)


func is_turret() -> bool:
	return kind == "flak" or kind == "heavy"


## World-space point bots and HUD markers aim at.
func aim_center() -> Vector3:
	return global_transform * Vector3(0, radius * 0.45, 0)


# --- Models ------------------------------------------------------------------------

func _mi(parent: Node3D, mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	parent.add_child(mi)
	meshes.append(mi)
	return mi


func _build_flak(material: Material) -> void:
	yaw_pivot.position.y = 7.0
	pitch_pivot.position = Vector3(0, 5.0, -2.0)
	if App.is_dedicated:
		_add_muzzles([Vector3(-3.2, 0, -30.0), Vector3(3.2, 0, -30.0)])
		return
	var base := MeshKit.new()
	base.cylinder(Vector3(0, -6, 0), Vector3(0, 7, 0), 16.0, 14.0, 12, MeshKit.DARK)
	base.ring(Vector3(0, 6.5, 0), Vector3.UP, 15.0, 11.0, 1.2, 12, MeshKit.GLOW)
	_mi(self, base.commit(), material)
	var house := MeshKit.new()
	house.box(Vector3(0, 4.5, 1.0), Vector3(10.0, 4.5, 11.0), MeshKit.PAINT, 3.0)
	house.box(Vector3(0, 9.6, 3.5), Vector3(5.0, 1.2, 5.0), MeshKit.HULL, 1.0)
	house.box(Vector3(-10.4, 4.0, 3.0), Vector3(0.6, 1.0, 6.0), MeshKit.GLOW)
	house.box(Vector3(10.4, 4.0, 3.0), Vector3(0.6, 1.0, 6.0), MeshKit.GLOW)
	_mi(yaw_pivot, house.commit(), material)
	var bar := MeshKit.new()
	bar.box(Vector3(0, 0, 0.0), Vector3(6.0, 2.6, 4.0), MeshKit.DARK, 1.0)
	for s in [-1.0, 1.0]:
		var x: float = s * 3.2
		bar.cylinder(Vector3(x, 0, -2.0), Vector3(x, 0, -27.0), 1.3, 1.1, 8, MeshKit.HEAT)
		bar.cylinder(Vector3(x, 0, -24.5), Vector3(x, 0, -30.0), 1.9, 1.7, 8, MeshKit.DARK)
		for i in 3:
			bar.cylinder(Vector3(x, 0, -6.0 - i * 3.0), Vector3(x, 0, -7.2 - i * 3.0), 1.7, 1.7, 8, MeshKit.DARK, false)
	_mi(slide, bar.commit(), material)
	_add_muzzles([Vector3(-3.2, 0, -30.5), Vector3(3.2, 0, -30.5)])
	_add_flash(Color(1.0, 0.7, 0.35))


func _build_heavy(material: Material) -> void:
	yaw_pivot.position.y = 9.0
	pitch_pivot.position = Vector3(0, 9.0, -6.0)
	if App.is_dedicated:
		_add_muzzles([Vector3(-5.5, 0, -52.0), Vector3(0, 0, -52.0), Vector3(5.5, 0, -52.0)])
		return
	var base := MeshKit.new()
	base.cylinder(Vector3(0, -8, 0), Vector3(0, 9, 0), 25.0, 22.0, 14, MeshKit.DARK)
	base.ring(Vector3(0, 8.5, 0), Vector3.UP, 23.5, 18.0, 1.6, 14, MeshKit.GLOW)
	_mi(self, base.commit(), material)
	var house := MeshKit.new()
	house.loft([[-20.0, 15.0, 7.0, 7.5], [8.0, 18.0, 9.0, 8.0], [22.0, 14.0, 7.0, 7.0]], MeshKit.profile_box(), 0.0, [MeshKit.PAINT, MeshKit.HULL])
	house.box(Vector3(0, 17.0, 12.0), Vector3(6.0, 2.0, 6.0), MeshKit.DARK, 1.5)
	house.box(Vector3(-11.0, 16.6, 10.0), Vector3(1.2, 0.6, 5.0), MeshKit.GLOW)
	house.box(Vector3(11.0, 16.6, 10.0), Vector3(1.2, 0.6, 5.0), MeshKit.GLOW)
	_mi(yaw_pivot, house.commit(), material)
	var bar := MeshKit.new()
	for i in 3:
		var x := (i - 1) * 5.5
		bar.cylinder(Vector3(x, 0, -4.0), Vector3(x, 0, -46.0), 2.3, 1.9, 10, MeshKit.HEAT)
		bar.cylinder(Vector3(x, 0, -44.0), Vector3(x, 0, -52.0), 3.0, 2.8, 10, MeshKit.DARK)
		bar.cylinder(Vector3(x, 0, -10.0), Vector3(x, 0, -14.0), 2.9, 2.9, 10, MeshKit.DARK, false)
	_mi(slide, bar.commit(), material)
	_add_muzzles([Vector3(-5.5, 0, -53.0), Vector3(0, 0, -53.0), Vector3(5.5, 0, -53.0)])
	_add_flash(Color(1.0, 0.55, 0.25))


func _build_generator(material: Material) -> void:
	if App.is_dedicated:
		return
	var k := MeshKit.new()
	k.cylinder(Vector3(0, -6, 0), Vector3(0, 10, 0), 36.0, 30.0, 16, MeshKit.DARK)
	k.ring(Vector3(0, 10.5, 0), Vector3.UP, 31.0, 24.0, 1.4, 16, MeshKit.GLOW)
	k.cylinder(Vector3(0, 10, 0), Vector3(0, 52, 0), 13.0, 8.0, 10, MeshKit.HULL)
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		var d := Vector3(cos(a), 0, sin(a))
		k.box(d * 20.0 + Vector3(0, 22, 0), Vector3(4.0, 14.0, 4.0), MeshKit.PAINT, 1.2)
		k.cylinder(d * 20.0 + Vector3(0, 36, 0), d * 9.0 + Vector3(0, 62, 0), 2.2, 1.6, 6, MeshKit.DARK)
	k.ring(Vector3(0, 66, 0), Vector3.UP, 26.0, 22.0, 3.0, 20, MeshKit.HULL)
	_mi(self, k.commit(), material)
	_glow = MeshInstance3D.new()
	_glow.mesh = Mats.sphere(20, 10)
	_glow.material_override = Mats.glow_solid(App.team_color(team).lerp(Color.WHITE, 0.35), 6.0)
	_glow.position = Vector3(0, 66, 0)
	_glow.scale = Vector3.ONE * 14.0
	add_child(_glow)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.9
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 6
	_glow_ring = MeshInstance3D.new()
	_glow_ring.mesh = ring_mesh
	_glow_ring.material_override = Mats.glow_solid(App.team_color(team), 4.0)
	_glow_ring.position = Vector3(0, 66, 0)
	_glow_ring.scale = Vector3.ONE * 34.0
	add_child(_glow_ring)
	# Energy column feeding the bubble.
	_beam = MeshInstance3D.new()
	_beam.mesh = Mats.beam_mesh()
	_beam.material_override = Mats.beam(App.team_color(team))
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.extra_cull_margin = 400.0
	_beam.position = Vector3(0, 70, 0)
	_beam.rotation.x = -PI * 0.5
	_beam.scale = Vector3(5.0, 5.0, 240.0)
	add_child(_beam)
	_light = OmniLight3D.new()
	_light.light_color = App.team_color(team)
	_light.omni_range = 220.0
	_light.light_energy = 4.0
	_light.position = Vector3(0, 66, 0)
	add_child(_light)


func _build_core(material: Material) -> void:
	if App.is_dedicated:
		return
	var k := MeshKit.new()
	k.cylinder(Vector3(0, -10, 0), Vector3(0, 12, 0), 72.0, 66.0, 18, MeshKit.DARK)
	k.ring(Vector3(0, 12.5, 0), Vector3.UP, 66.0, 54.0, 2.0, 18, MeshKit.GLOW)
	_mi(self, k.commit(), material)
	_glow = MeshInstance3D.new()
	_glow.mesh = Mats.sphere(28, 14)
	_glow.material_override = Mats.glow_solid(Color(1.0, 0.55, 0.2), 9.0)
	_glow.position = Vector3(0, 30, 0)
	_glow.scale = Vector3.ONE * 42.0
	_glow.visible = false
	add_child(_glow)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.92
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 64
	ring_mesh.ring_segments = 6
	_glow_ring = MeshInstance3D.new()
	_glow_ring.mesh = ring_mesh
	_glow_ring.material_override = Mats.glow_solid(Color(1.0, 0.4, 0.15), 5.0)
	_glow_ring.position = Vector3(0, 30, 0)
	_glow_ring.scale = Vector3.ONE * 60.0
	_glow_ring.visible = false
	add_child(_glow_ring)
	# Armoured shutters: six petals closed over the core until the armour fails.
	for i in 6:
		var s := MeshKit.new()
		var a0 := TAU * i / 6.0
		var a1 := TAU * (i + 1) / 6.0
		var p0 := Vector3(cos(a0), 0, sin(a0)) * 64.0 + Vector3(0, 12, 0)
		var p1 := Vector3(cos(a1), 0, sin(a1)) * 64.0 + Vector3(0, 12, 0)
		var top := Vector3(0, 62, 0)
		var m0 := p0.lerp(top, 0.55) + Vector3(cos(a0), 0, sin(a0)) * 10.0
		var m1 := p1.lerp(top, 0.55) + Vector3(cos(a1), 0, sin(a1)) * 10.0
		var inside := Vector3(0, 20, 0)
		s.quad(p0, p1, m1, m0, MeshKit.HULL, inside)
		s.tri(m0, m1, top, MeshKit.PAINT, inside)
		s.quad(p0 + Vector3(0, -0.01, 0), p1, m1, m0, MeshKit.HULL, top * 3.0)
		var mi := _mi(self, s.commit(), material)
		_shutters.append(mi)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.2)
	_light.omni_range = 380.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, 30, 0)
	add_child(_light)


func _add_muzzles(points: Array) -> void:
	for p in points:
		var mk := Node3D.new()
		mk.position = p
		slide.add_child(mk)
		muzzles.append(mk)


func _add_flash(color: Color) -> void:
	_flash = MeshInstance3D.new()
	_flash.mesh = Mats.quad()
	_flash.material_override = Mats.glow(color, 5.0, 1.6)
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	_flash.top_level = true
	add_child(_flash)


# --- Behaviour ----------------------------------------------------------------------

## Slews toward `world_point`. Returns the angle (radians) still to go.
func track(world_point: Vector3, delta: float) -> float:
	var local := global_transform.affine_inverse() * world_point
	var yaw := atan2(-local.x, -local.z)
	var flat := Vector2(local.x, local.z).length()
	var pitch := clampf(atan2(local.y - pitch_pivot.position.y - yaw_pivot.position.y, flat), deg_to_rad(-8.0), deg_to_rad(86.0))
	var step := float(spec.slew) * delta
	var dy := wrapf(yaw - yaw_pivot.rotation.y, -PI, PI)
	yaw_pivot.rotation.y += clampf(dy, -step, step)
	var dp := pitch - pitch_pivot.rotation.x
	pitch_pivot.rotation.x += clampf(dp, -step, step)
	return absf(dy) + absf(dp)


func can_see(world_point: Vector3) -> bool:
	var local := global_transform.affine_inverse() * world_point
	return local.y > -radius * 0.2


func fire_direction() -> Vector3:
	return -pitch_pivot.global_basis.z.normalized()


func next_muzzle() -> Vector3:
	var m := muzzles[_muzzle_i % muzzles.size()]
	_muzzle_i += 1
	return m.global_position


## Visual kick for a shot from `origin` (every peer).
func kick(origin: Vector3) -> void:
	_recoil = minf(_recoil + 0.5, 1.0)
	if _flash:
		_flash_t = 0.07
		_flash.visible = true
		_flash.global_position = origin
		_flash.scale = Vector3.ONE * (14.0 if kind == "heavy" else 8.0) * randf_range(0.8, 1.2)


func show_hit() -> void:
	_hit_flash = 1.0
	last_hit_ms = Time.get_ticks_msec()


func set_exposed(on: bool) -> void:
	exposed = on
	if kind != "core" or App.is_dedicated:
		return
	if on:
		for i in _shutters.size():
			var s := _shutters[i]
			if not s.visible:
				continue
			# Blow the petals off along their own outward direction.
			var a := TAU * (i + 0.5) / 6.0
			var out := global_basis * (Vector3(cos(a), 0.9, sin(a)).normalized())
			var start := s.global_transform
			s.top_level = true
			s.global_transform = start
			var tw := s.create_tween().set_parallel(true)
			tw.tween_property(s, "global_position", start.origin + out * 900.0, 6.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			tw.tween_property(s, "rotation", s.rotation + Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4)), 6.0)
			tw.chain().tween_callback(func(): s.visible = false)
			s.set_instance_shader_parameter("burn", 0.6)
		_glow.visible = true
		_glow_ring.visible = true
	else:
		for s in _shutters:
			s.visible = true
			s.top_level = false
			s.transform = Transform3D.IDENTITY
		_glow.visible = false
		_glow_ring.visible = false


func destroy() -> void:
	alive = false
	hp = 0.0
	target_id = -1
	if hit_area:
		hit_area.set_deferred("monitorable", false)
	if App.is_dedicated:
		return
	for m in meshes:
		m.set_instance_shader_parameter("burn", 1.0)
	if is_turret():
		# Barrels droop, the housing sags off its ring.
		var tw := create_tween().set_parallel(true)
		tw.tween_property(pitch_pivot, "rotation:x", deg_to_rad(-6.0), 1.2).set_trans(Tween.TRANS_BOUNCE)
		tw.tween_property(yaw_pivot, "rotation:z", randf_range(-0.25, 0.25), 1.2)
	for n in [_glow, _glow_ring, _beam]:
		if n:
			n.visible = false
	if _light:
		_light.light_energy = 0.0


func restore() -> void:
	alive = true
	hp = max_hp
	hit_area.set_deferred("monitorable", true)
	for m in meshes:
		m.set_instance_shader_parameter("burn", 0.0)


func _process(delta: float) -> void:
	_t += delta
	_recoil = move_toward(_recoil, 0.0, delta * (1.6 if kind == "heavy" else 3.0))
	if slide:
		slide.position.z = _recoil * (6.0 if kind == "heavy" else 3.0)
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.visible = false
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta * 5.0)
		for m in meshes:
			m.set_instance_shader_parameter("flash", _hit_flash)
	if not alive:
		return
	var hurt := 1.0 - hp / max_hp
	if kind == "generator" and _glow:
		var pulse := 0.85 + 0.15 * sin(_t * (3.0 + hurt * 14.0))
		_glow.scale = Vector3.ONE * 14.0 * pulse
		_glow_ring.rotation = Vector3(sin(_t * 0.7) * 0.5, _t * 0.9, cos(_t * 0.5) * 0.4)
		_light.light_energy = 4.0 * pulse
		_beam.set_instance_shader_parameter("intensity", (0.5 + 0.3 * sin(_t * 9.0)) * (1.0 - hurt * 0.6))
		_beam.set_instance_shader_parameter("beam_length", 240.0)
	elif kind == "core" and exposed and _glow:
		var pulse := 0.88 + 0.12 * sin(_t * (2.5 + hurt * 10.0))
		_glow.scale = Vector3.ONE * 42.0 * pulse
		_glow_ring.rotation = Vector3(_t * 0.6, _t * 0.25, sin(_t * 0.4) * 0.6)
		_light.light_energy = 6.0 * pulse
