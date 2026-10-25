class_name Ship
extends Node3D
## A starfighter. The owning peer (the player's client, or the server for
## bots) simulates flight and decides when weapons fire; every other peer
## renders it from interpolated snapshots. Damage is server-authoritative.

const FLAG_ALIVE := 1
const FLAG_BOOST := 2
const FLAG_FIRE1 := 4
const FLAG_FIRE2 := 8
const FLAG_BEAM := 16

var ship_id := 0
var def_id := "vanguard"
var def: Dictionary
var team := 0
var owner_peer := 1
var pilot_name := "PILOT"
var is_bot := false

var alive := false
var hull := 1.0
var shield := 1.0
var max_hull := 1.0
var max_shield := 1.0
var boost_energy := 100.0
var velocity := Vector3.ZERO
var rates := Vector3.ZERO  # pitch (+up), yaw (+right), roll (+right) in rad/s
var throttle := 0.65
var boosting := false
var firing_primary := false
var firing_secondary := false
var aim_point := Vector3.ZERO
var radius := 7.0
var last_damage_time := -100.0
var last_shield_hit := -100.0
var damagers: Dictionary = {}  # attacker ship id -> last hit time
var respawn_at := 0.0

# Stats for the scoreboard.
var kills := 0
var deaths := 0
var assists := 0
var captures := 0
var score := 0
var streak := 0
var best_streak := 0

# Targeting / missiles.
var target: Ship = null
var lock_target: Ship = null
var lock_progress := 0.0
var incoming_missiles := 0

var controller: Object = null
var visual: Node3D
var model_root: Node3D
var mounts: Array[WeaponMount] = []
var engines: Array[EngineFX] = []
var hull_parts: Array[GeometryInstance3D] = []
var hit_area: Area3D
var shield_mi: MeshInstance3D
var shield_mat: ShaderMaterial
var engine_light: OmniLight3D
var engine_audio: AudioStreamPlayer3D
var beam_audio: AudioStreamPlayer3D

var _snaps: Array = []  # [time, pos, quat, vel]
var _remote_rates := Vector3.ZERO
var _prev_basis := Basis.IDENTITY
var _bank := 0.0
var _flash := 0.0
var _fire2_was := false
var _missile_queue: Array = []
var _beam_dmg_acc: Dictionary = {}
var _lock_beep := 0.0


func setup(id: int, ship_def_id: String, ship_team: int, peer: int, name_text: String, bot: bool) -> void:
	ship_id = id
	def_id = ship_def_id
	def = ShipLibrary.ship(ship_def_id)
	team = ship_team
	owner_peer = peer
	pilot_name = name_text
	is_bot = bot
	name = "Ship_%d" % id
	max_hull = def.hull
	max_shield = def.shield
	radius = def.radius
	_build()


func is_authority() -> bool:
	if is_bot:
		return multiplayer.is_server()
	return owner_peer == multiplayer.get_unique_id()


func is_local_player() -> bool:
	return not is_bot and owner_peer == multiplayer.get_unique_id()


# --- Construction ---------------------------------------------------------------

func _build() -> void:
	for c in get_children():
		c.queue_free()
	mounts.clear()
	engines.clear()
	hull_parts.clear()
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	var hull_mat := Mats.hull(team, def.engine_color)
	var layout := _layout()
	radius = layout.radius
	if layout.has("model_root"):
		model_root = layout.model_root
		visual.add_child(model_root)
	else:
		var meshes := HullBuilder.build(def.builder)
		var mi := MeshInstance3D.new()
		mi.mesh = meshes.hull
		mi.material_override = hull_mat
		visual.add_child(mi)
		hull_parts.append(mi)
		if meshes.glass:
			var gi := MeshInstance3D.new()
			gi.mesh = meshes.glass
			gi.material_override = Mats.glass()
			visual.add_child(gi)
	for hp in layout.hardpoints:
		var m := WeaponMount.new()
		visual.add_child(m)
		m.setup(hp, hull_mat, hp.get("parts", {}))
		mounts.append(m)
	for e in layout.engines:
		var fx := EngineFX.new()
		visual.add_child(fx)
		fx.setup(e.pos, e.radius, def.engine_color, not App.is_dedicated)
		engines.append(fx)
	# Hitbox: an ellipsoid-ish capsule along the hull.
	hit_area = Area3D.new()
	hit_area.collision_layer = 2
	hit_area.collision_mask = 0
	hit_area.monitoring = false
	hit_area.set_meta("ship", self)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius * 0.42
	cap.height = radius * 1.9
	cs.shape = cap
	cs.rotation.x = PI * 0.5
	hit_area.add_child(cs)
	add_child(hit_area)
	# Shield shell.
	shield_mi = MeshInstance3D.new()
	shield_mi.mesh = Mats.sphere(32, 16)
	shield_mat = Mats.shield(App.team_color(team).lerp(Color(0.6, 0.9, 1.0), 0.4))
	shield_mi.material_override = shield_mat
	shield_mi.scale = Vector3(radius * 0.75, radius * 0.45, radius * 1.05)
	shield_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(shield_mi)
	if not App.is_dedicated:
		engine_light = OmniLight3D.new()
		engine_light.light_color = def.engine_color
		engine_light.omni_range = radius * 2.2
		engine_light.light_energy = 2.0
		engine_light.shadow_enabled = false
		var c := Vector3.ZERO
		for e in layout.engines:
			c += e.pos
		engine_light.position = c / maxf(1.0, layout.engines.size()) + Vector3(0, 0, radius * 0.4)
		visual.add_child(engine_light)
		engine_audio = Sfx.make_loop_player("engine")
		engine_audio.unit_size = 18.0
		add_child(engine_audio)
	visible = false


## Hardpoints/engines from the library entry, or from <model>.ship.json for
## imported models (see docs/SHIP_PIPELINE.md).
func _layout() -> Dictionary:
	var model_path: String = def.get("model", "")
	if model_path == "" or not ResourceLoader.exists(model_path):
		return {"hardpoints": def.hardpoints, "engines": def.engines, "radius": def.radius}
	var root: Node3D = (load(model_path) as PackedScene).instantiate()
	var json_path := model_path.get_basename() + ".ship.json"
	var spec: Dictionary = {}
	if FileAccess.file_exists(json_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		if parsed is Dictionary:
			spec = parsed
	var hull_mat := Mats.hull(team, def.engine_color)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = Mats.glass() if mi.name.to_lower().begins_with("canopy") else hull_mat
		hull_parts.append(mi)
	var hps := []
	for h in spec.get("hardpoints", []):
		var pos := _v3(h.get("pos", [0, 0, 0]))
		var parts := {"base": [], "barrel": [], "muzzles": []}
		for key in [["base_node", "base"], ["barrel_node", "barrel"]]:
			var n := root.find_child(str(h.get(key[0], "")), true, false) as Node3D
			if n:
				var xf := n.global_transform if n.is_inside_tree() else _model_xform(root, n)
				n.get_parent().remove_child(n)
				n.transform = Transform3D(Basis.IDENTITY, -pos) * xf
				parts[key[1]].append(n)
		if h.has("muzzles"):
			for mz in h.muzzles:
				parts.muzzles.append(_v3(mz) - pos)
		elif h.has("muzzle"):
			parts.muzzles.append(_v3(h.muzzle) - pos)
		hps.append({"pos": pos, "weapon": str(h.get("weapon", "pulse_cannon")), "gimbal": float(h.get("gimbal", 6.0)),
			"turret": bool(h.get("turret", false)), "scale": 1.0, "parts": parts})
	var engs := []
	for e in spec.get("engines", []):
		engs.append({"pos": _v3(e.get("pos", [0, 0, 0])), "radius": float(e.get("radius", 0.8))})
	return {"hardpoints": hps if not hps.is_empty() else def.hardpoints, "engines": engs if not engs.is_empty() else def.engines,
		"radius": float(spec.get("radius", def.radius)), "model_root": root}


func _model_xform(root: Node3D, n: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


static func _v3(a: Variant) -> Vector3:
	if a is Vector3:
		return a
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


# --- Lifecycle ------------------------------------------------------------------------

func spawn(xform: Transform3D) -> void:
	global_transform = xform
	velocity = -xform.basis.z * def.speed * 0.6
	rates = Vector3.ZERO
	hull = max_hull
	shield = max_shield
	boost_energy = def.boost_energy
	throttle = 0.65
	alive = true
	visible = true
	damagers.clear()
	target = null
	lock_target = null
	lock_progress = 0.0
	_snaps.clear()
	_prev_basis = global_basis
	hit_area.set_deferred("monitorable", true)
	for e in engines:
		if e.trail:
			e.trail.clear()
	if engine_audio and not engine_audio.playing:
		engine_audio.play()


func kill() -> void:
	alive = false
	visible = false
	firing_primary = false
	firing_secondary = false
	hit_area.set_deferred("monitorable", false)
	for m in mounts:
		m.set_beam(false, Vector3.ZERO, Vector3.ZERO)
	if engine_audio:
		engine_audio.stop()
	if beam_audio:
		beam_audio.stop()


# --- Simulation -----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not alive:
		return
	var arena := Arena.current
	if arena == null:
		return
	if is_authority():
		var input: Dictionary = controller.get_input(self, delta) if controller else {}
		_fly(delta, input)
		_collide(delta, arena)
		_update_weapons(delta, arena, input)
	else:
		_interpolate(arena.net_time())
	_update_beams(delta, arena)
	if multiplayer.is_server():
		_regen(delta, arena)


func _fly(delta: float, input: Dictionary) -> void:
	var target_rates := Vector3(
		clampf(input.get("pitch", 0.0), -1.0, 1.0) * def.pitch_rate,
		clampf(input.get("yaw", 0.0), -1.0, 1.0) * def.yaw_rate,
		clampf(input.get("roll", 0.0), -1.0, 1.0) * def.roll_rate)
	rates = rates.lerp(target_rates, 1.0 - exp(-def.agility * delta))
	rotate_object_local(Vector3.RIGHT, rates.x * delta)
	rotate_object_local(Vector3.UP, -rates.y * delta)
	rotate_object_local(Vector3.FORWARD, rates.z * delta)
	transform = transform.orthonormalized()
	throttle = clampf(input.get("throttle", throttle), 0.0, 1.0)
	boosting = input.get("boost", false) and boost_energy > 1.0
	if boosting:
		boost_energy = maxf(0.0, boost_energy - def.boost_drain * delta)
	else:
		boost_energy = minf(def.boost_energy, boost_energy + def.boost_regen * delta)
	var speed: float = def.boost_speed if boosting else lerpf(def.min_speed, def.speed, throttle)
	var fwd := -global_basis.z
	var strafe: float = input.get("strafe", 0.0)
	var desired := fwd * speed + global_basis.x * strafe * def.speed * 0.35
	# Flight assist: velocity chases the nose, leaving a little drift.
	velocity = velocity.lerp(desired, 1.0 - exp(-def.accel * delta))
	global_position += velocity * delta
	firing_primary = input.get("fire1", false)
	firing_secondary = input.get("fire2", false)
	aim_point = input.get("aim", global_position + fwd * 600.0)
	target = input.get("target", target)


func _collide(delta: float, arena: Arena) -> void:
	var hit := arena.field.collide_sphere(global_position, radius * 0.75)
	if not hit.is_empty():
		var n: Vector3 = hit.normal
		global_position += n * hit.depth
		var vn := velocity.dot(n)
		if vn < 0.0:
			velocity -= n * vn * 1.6
			var impact := -vn
			if impact > 18.0:
				arena.ctl.request_collision_damage(self, impact * 3.5, hit.id)
				if is_local_player():
					arena.camera_shake(clampf(impact / 60.0, 0.2, 1.0))
					Settings.vibrate(80)
	# Soft arena boundary pushes ships back toward the fight.
	var d := global_position.length()
	if d > Arena.BOUNDARY:
		velocity -= global_position.normalized() * (d - Arena.BOUNDARY) * delta * 2.0


func _update_weapons(delta: float, arena: Arena, input: Dictionary) -> void:
	var fwd_aim := aim_point
	for i in mounts.size():
		var m := mounts[i]
		m.aim_at(fwd_aim, delta)
		m.cooldown = maxf(0.0, m.cooldown - delta)
		var w := m.wdef
		match w.type:
			"projectile":
				m.heat = maxf(0.0, m.heat - w.cool * delta * (0.4 if firing_primary else 1.0))
				if m.overheated and m.heat < 0.35:
					m.overheated = false
				if firing_primary and not m.overheated and m.cooldown <= 0.0:
					m.cooldown = 1.0 / w.rof
					m.heat += w.heat
					if m.heat >= 1.0:
						m.overheated = true
					var mx := m.next_muzzle()
					var dir := m.fire_direction()
					var spread := deg_to_rad(w.spread)
					dir = (dir + Vector3(randf_range(-spread, spread), randf_range(-spread, spread), randf_range(-spread, spread))).normalized()
					arena.ctl.local_fire(self, i, mx.origin, dir, -1)
			"beam":
				var on := firing_primary and not m.overheated
				if on:
					m.heat += w.heat_rate * delta
					if m.heat >= 1.0:
						m.overheated = true
				else:
					m.heat = maxf(0.0, m.heat - w.cool * delta)
					if m.overheated and m.heat < 0.3:
						m.overheated = false
				m.beam_on = on
			"rail":
				if m.cooldown <= 0.0 and firing_primary:
					if m.charge <= 0.0 and is_local_player():
						Sfx.play_at("rail_charge", global_position, -4.0)
					m.charge += delta
					if m.charge >= w.charge:
						m.charge = 0.0
						m.cooldown = w.reload
						var mx := m.next_muzzle()
						arena.ctl.local_fire(self, i, mx.origin, m.fire_direction(), -1)
				else:
					m.charge = maxf(0.0, m.charge - delta * 2.0)
			"missile":
				pass
	_update_lock(delta, arena)
	# Secondary trigger fires every ready pod; locked salvos home in.
	var pressed := firing_secondary and not _fire2_was
	_fire2_was = firing_secondary
	if pressed:
		var tid := lock_target.ship_id if lock_target and lock_progress >= 1.0 else -1
		for i in mounts.size():
			var m := mounts[i]
			if m.wdef.type == "missile" and m.cooldown <= 0.0:
				m.cooldown = m.wdef.reload
				for s in int(m.wdef.salvo):
					_missile_queue.append([s * 0.18, i, tid])
	for q in _missile_queue:
		q[0] -= delta
		if q[0] <= 0.0:
			var m := mounts[q[1]]
			var mx := m.next_muzzle()
			m.kick(0.6)
			arena.ctl.local_fire(self, q[1], mx.origin, -global_basis.z, q[2])
	_missile_queue = _missile_queue.filter(func(q): return q[0] > 0.0)


func has_missiles() -> bool:
	for m in mounts:
		if m.wdef.type == "missile":
			return true
	return false


func missile_ready() -> bool:
	for m in mounts:
		if m.wdef.type == "missile" and m.cooldown <= 0.0:
			return true
	return false


func missile_reload_fraction() -> float:
	var best := 0.0
	for m in mounts:
		if m.wdef.type == "missile":
			best = maxf(best, 1.0 - m.cooldown / float(m.wdef.reload))
	return best


func primary_heat() -> float:
	var h := 0.0
	for m in mounts:
		if m.group == 0:
			h = maxf(h, m.heat)
			if m.wdef.type == "rail":
				h = maxf(h, 1.0 - m.cooldown / float(m.wdef.reload)) if m.cooldown > 0.0 else h
	return h


func primary_overheated() -> bool:
	for m in mounts:
		if m.overheated:
			return true
	return false


func _update_lock(delta: float, arena: Arena) -> void:
	if not has_missiles():
		return
	var wdef := ShipLibrary.weapon("missile_pod")
	var cone := cos(deg_to_rad(wdef.lock_cone))
	var fwd := -global_basis.z
	var candidate: Ship = null
	if target and target.alive and target.team != team:
		var to := target.global_position - global_position
		if to.length() < wdef.lock_range and fwd.dot(to.normalized()) > cone:
			candidate = target
	if candidate == null:
		var best := -1.0
		for s in arena.ships:
			if s.team == team or not s.alive:
				continue
			var to := s.global_position - global_position
			var dist := to.length()
			if dist > wdef.lock_range:
				continue
			var dot := fwd.dot(to / dist)
			if dot > cone and dot > best:
				best = dot
				candidate = s
	if candidate != lock_target:
		lock_target = candidate
		lock_progress = 0.0
	if lock_target:
		var was := lock_progress
		lock_progress = minf(1.0, lock_progress + delta / wdef.lock_time)
		if is_local_player():
			_lock_beep -= delta
			if lock_progress < 1.0 and _lock_beep <= 0.0:
				_lock_beep = 0.18
				Sfx.play("lock", -10.0, 1.0)
			elif lock_progress >= 1.0 and was < 1.0:
				Sfx.play("lock", -4.0, 1.5)
	else:
		lock_progress = 0.0


## Beams are visual on every peer; only the server applies their damage.
func _update_beams(delta: float, arena: Arena) -> void:
	var any_on := false
	for m in mounts:
		if m.wdef.type != "beam":
			continue
		var on := m.beam_on and alive
		if not on:
			if m.beam and m.beam.visible:
				m.set_beam(false, Vector3.ZERO, Vector3.ZERO)
			continue
		any_on = true
		var from := m.current_muzzle()
		var dir := m.fire_direction()
		var to: Vector3 = from + dir * float(m.wdef.range)
		var hit := arena.raycast(from, to, [hit_area.get_rid()])
		if not hit.is_empty():
			to = hit.position
			if randf() < delta * 20.0:
				FX.sparks(arena, to, hit.normal, m.wdef.color, 6)
			if multiplayer.is_server():
				var dmg: float = m.wdef.dps * delta
				var col: Object = hit.collider
				if col.has_meta("ship"):
					var s: Ship = col.get_meta("ship")
					if s.team != team:
						arena.ctl.server_damage(s, dmg, m.wdef, ship_id, to, true)
				elif col.has_meta("asteroid"):
					arena.field.damage(int(col.get_meta("asteroid")), dmg, to, dir)
		m.set_beam(true, from, to)
	if any_on and not App.is_dedicated:
		if beam_audio == null:
			beam_audio = Sfx.make_loop_player("beam")
			beam_audio.volume_db = -6.0
			add_child(beam_audio)
		if not beam_audio.playing:
			beam_audio.play()
	elif beam_audio and beam_audio.playing:
		beam_audio.stop()


func _regen(delta: float, arena: Arena) -> void:
	if arena.time - last_damage_time > def.shield_delay and shield < max_shield:
		shield = minf(max_shield, shield + def.shield_regen * delta)


## Server only. Returns true if this hit destroyed the ship.
func apply_damage(amount: float, wdef: Dictionary, attacker_id: int, now: float) -> bool:
	if not alive:
		return false
	last_damage_time = now
	if attacker_id >= 0 and attacker_id != ship_id:
		damagers[attacker_id] = now
	var vs_s: float = wdef.get("vs_shield", 1.0)
	var vs_h: float = wdef.get("vs_hull", 1.0)
	if shield > 0.0:
		var to_shield := amount * vs_s
		var absorbed := minf(shield, to_shield)
		shield -= absorbed
		amount -= absorbed / vs_s
		last_shield_hit = now
	if amount > 0.0:
		hull -= amount * vs_h
	return hull <= 0.0


# --- Networking -----------------------------------------------------------------------

func net_flags() -> int:
	var f := 0
	if alive:
		f |= FLAG_ALIVE
	if boosting:
		f |= FLAG_BOOST
	if firing_primary:
		f |= FLAG_FIRE1
	if firing_secondary:
		f |= FLAG_FIRE2
	for m in mounts:
		if m.beam_on:
			f |= FLAG_BEAM
	return f


func push_snapshot(t: float, pos: Vector3, rot: Quaternion, vel: Vector3, thr: float, flags: int, aim: Vector3) -> void:
	_snaps.append([t, pos, rot, vel])
	if _snaps.size() > 12:
		_snaps.pop_front()
	throttle = thr
	boosting = flags & FLAG_BOOST != 0
	firing_primary = flags & FLAG_FIRE1 != 0
	aim_point = aim
	var beam := flags & FLAG_BEAM != 0
	for m in mounts:
		if m.wdef.type == "beam":
			m.beam_on = beam


func _interpolate(now: float) -> void:
	if _snaps.is_empty():
		return
	var rt := now - 0.1
	var a: Array = _snaps[0]
	var b: Array = _snaps[_snaps.size() - 1]
	for i in _snaps.size() - 1:
		if _snaps[i][0] <= rt and _snaps[i + 1][0] >= rt:
			a = _snaps[i]
			b = _snaps[i + 1]
			break
	var pos: Vector3
	var rot: Quaternion
	if rt >= b[0]:
		# Extrapolate briefly from the newest snapshot.
		var dt := minf(rt - float(b[0]), 0.25)
		pos = b[1] + b[3] * dt
		rot = b[2]
	else:
		var span := maxf(0.0001, float(b[0]) - float(a[0]))
		var k := clampf((rt - float(a[0])) / span, 0.0, 1.0)
		pos = a[1].lerp(b[1], k)
		rot = (a[2] as Quaternion).slerp(b[2], k)
	global_position = pos
	global_basis = Basis(rot)
	velocity = b[3]
	for m in mounts:
		m.aim_at(aim_point, get_physics_process_delta_time())


# --- Visuals --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not alive:
		return
	var yaw_rate := rates.y
	if not is_authority():
		var d := _prev_basis.inverse() * global_basis
		var e := d.get_euler()
		_remote_rates = _remote_rates.lerp(Vector3(e.x, -e.y, e.z) / maxf(delta, 0.001), 1.0 - exp(-delta * 8.0))
		yaw_rate = _remote_rates.y
	_prev_basis = global_basis
	_bank = lerpf(_bank, clampf(-yaw_rate * 0.55, -0.6, 0.6), 1.0 - exp(-delta * 5.0))
	visual.rotation.z = _bank
	var thrust := throttle
	var b := 1.0 if boosting else 0.0
	for e in engines:
		e.thrust = thrust
		e.boost = lerpf(e.boost, b, 1.0 - exp(-delta * 6.0))
	if engine_light:
		engine_light.light_energy = (1.4 + thrust * 2.0 + b * 3.0) * (0.9 + 0.1 * sin(Time.get_ticks_msec() * 0.03))
	if engine_audio:
		engine_audio.pitch_scale = 0.75 + thrust * 0.4 + b * 0.35
		engine_audio.volume_db = -14.0 + thrust * 6.0 + b * 4.0 + (4.0 if is_local_player() else 0.0)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		for p in hull_parts:
			p.set_instance_shader_parameter("flash", _flash)
	var regen := 0.0
	var arena := Arena.current
	if arena and shield < max_shield and arena.time - last_damage_time > def.shield_delay:
		regen = 0.35
	shield_mat.set_shader_parameter("regen", regen)
	for p in hull_parts:
		p.set_instance_shader_parameter("burn", clampf(1.0 - hull / max_hull, 0.0, 1.0) * 0.6)


## Visual reaction to an impact at `world_pos` (all peers).
func show_hit(world_pos: Vector3, shielded: bool) -> void:
	if shielded:
		var local := shield_mi.global_transform.affine_inverse() * world_pos
		shield_mat.set_shader_parameter("hit_pos", local.normalized())
		shield_mat.set_shader_parameter("hit_time", float(Time.get_ticks_msec()) / 1000.0)
		shield_mat.set_shader_parameter("strength", clampf(shield / max_shield + 0.35, 0.3, 1.0))
	else:
		_flash = 1.0
