class_name WeaponMount
extends Node3D
## A weapon model mounted on a ship hardpoint. Articulated as
## base -> yaw pivot -> pitch pivot -> recoil slide -> barrels/muzzles, so it
## tracks the aim point inside its gimbal cone, kicks back when firing and
## glows with heat. Holds the per-weapon firing state for the ship.

var weapon_id := ""
var wdef: Dictionary
var group := 0
var gimbal := 0.0
var is_turret := false

var yaw_pivot: Node3D
var pitch_pivot: Node3D
var slide: Node3D
var muzzles: Array[Node3D] = []
var parts: Array[GeometryInstance3D] = []
var _muzzle_i := 0
var _recoil := 0.0
var _flash: MeshInstance3D
var _flash_t := 0.0

# Firing state (driven by Ship on the authority).
var cooldown := 0.0
var heat := 0.0
var overheated := false
var charge := 0.0
var ammo_ready := true
var beam_on := false
var beam: MeshInstance3D
var beam_glow: MeshInstance3D
var beam_hit := Vector3.ZERO


func setup(hp: Dictionary, material: Material, model_parts: Dictionary = {}) -> void:
	weapon_id = hp.weapon
	wdef = ShipLibrary.weapon(weapon_id)
	group = int(wdef.group)
	gimbal = deg_to_rad(float(hp.get("gimbal", 6.0)))
	is_turret = bool(hp.get("turret", false))
	var s := float(hp.get("scale", 1.0))
	position = hp.pos
	scale = Vector3.ONE * s
	yaw_pivot = Node3D.new()
	pitch_pivot = Node3D.new()
	slide = Node3D.new()
	add_child(yaw_pivot)
	yaw_pivot.add_child(pitch_pivot)
	pitch_pivot.add_child(slide)
	if model_parts.is_empty():
		var m := WeaponBuilder.build(wdef.model)
		yaw_pivot.position.y = m.pivot
		_add_part(self, m.base, material)
		_add_part(yaw_pivot, m.turret, material).position.y = -m.pivot
		_add_part(slide, m.barrel, material)
		for mp in m.muzzles:
			var mk := Node3D.new()
			mk.position = mp
			slide.add_child(mk)
			muzzles.append(mk)
	else:
		# Parts lifted from an imported ship model, already positioned in
		# mount space by the ship loader.
		for part in model_parts.get("base", []):
			add_child(part)
		for part in model_parts.get("barrel", []):
			slide.add_child(part)
		for mp in model_parts.get("muzzles", []):
			var mk := Node3D.new()
			mk.position = mp
			slide.add_child(mk)
			muzzles.append(mk)
	if muzzles.is_empty():
		var mk := Node3D.new()
		mk.position = Vector3(0, 0, -1)
		slide.add_child(mk)
		muzzles.append(mk)
	_flash = MeshInstance3D.new()
	_flash.mesh = Mats.quad()
	_flash.material_override = Mats.glow(wdef.color, 5.0, 1.6)
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	add_child(_flash)
	if wdef.type == "beam":
		beam = MeshInstance3D.new()
		beam.mesh = Mats.beam_mesh()
		beam.material_override = Mats.beam(wdef.color)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.top_level = true
		beam.visible = false
		beam.extra_cull_margin = 1000.0
		add_child(beam)
		beam_glow = MeshInstance3D.new()
		beam_glow.mesh = Mats.quad()
		beam_glow.material_override = Mats.glow(wdef.color, 4.0, 1.8)
		beam_glow.top_level = true
		beam_glow.visible = false
		add_child(beam_glow)


func _add_part(parent: Node3D, mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	parent.add_child(mi)
	parts.append(mi)
	return mi


## Rotates toward `world_point`, clamped to the gimbal cone.
func aim_at(world_point: Vector3, delta: float) -> void:
	if gimbal <= 0.001:
		return
	var local := global_transform.affine_inverse() * world_point
	if local.length_squared() < 1.0:
		return
	var yaw := atan2(-local.x, -local.z)
	var flat := Vector2(local.x, local.z).length()
	var pitch := atan2(local.y - yaw_pivot.position.y, flat)
	var limit := gimbal
	yaw = clampf(yaw, -limit, limit)
	pitch = clampf(pitch, -limit, limit * (1.0 if not is_turret else 1.6))
	var k := 1.0 - exp(-delta * (14.0 if not is_turret else 6.0))
	yaw_pivot.rotation.y = lerp_angle(yaw_pivot.rotation.y, yaw, k)
	pitch_pivot.rotation.x = lerp_angle(pitch_pivot.rotation.x, pitch, k)


func center_aim(delta: float) -> void:
	var k := 1.0 - exp(-delta * 4.0)
	yaw_pivot.rotation.y = lerp_angle(yaw_pivot.rotation.y, 0.0, k)
	pitch_pivot.rotation.x = lerp_angle(pitch_pivot.rotation.x, 0.0, k)


func fire_direction() -> Vector3:
	return -pitch_pivot.global_basis.z.normalized()


## Returns the next muzzle's world transform (barrels alternate).
func next_muzzle() -> Transform3D:
	var m := muzzles[_muzzle_i % muzzles.size()]
	_muzzle_i += 1
	return m.global_transform


func current_muzzle() -> Vector3:
	return muzzles[_muzzle_i % muzzles.size()].global_position


func kick(strength := 1.0) -> void:
	_recoil = minf(_recoil + 0.35 * strength, 0.6)
	_flash_t = 0.06
	_flash.visible = true
	var m := muzzles[(_muzzle_i + muzzles.size() - 1) % muzzles.size()]
	_flash.global_position = m.global_position
	_flash.scale = Vector3.ONE * randf_range(1.4, 2.2) * scale.x


func _process(delta: float) -> void:
	_recoil = move_toward(_recoil, 0.0, delta * 2.4)
	slide.position.z = _recoil * (1.0 if wdef.type != "rail" else 1.6)
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.visible = false
	var glow := heat
	if wdef.type == "rail":
		glow = maxf(heat, charge / maxf(0.01, float(wdef.charge)))
	for p in parts:
		p.set_instance_shader_parameter("heat", glow)


func set_beam(on: bool, from: Vector3, to: Vector3) -> void:
	if beam == null:
		return
	beam_on = on
	beam.visible = on
	beam_glow.visible = on
	if not on:
		return
	var length := maxf(from.distance_to(to), 0.1)
	var t := Transform3D(Basis.looking_at(to - from, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT), from)
	var w := 0.18 * scale.x * (0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.05))
	beam.global_transform = t.scaled_local(Vector3(w, w, length))
	beam.set_instance_shader_parameter("beam_length", length)
	beam_glow.global_position = to
	beam_glow.scale = Vector3.ONE * (3.0 + randf() * 1.5) * scale.x
	beam_hit = to
