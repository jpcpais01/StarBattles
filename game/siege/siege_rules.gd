class_name SiegeRules
extends Node
## Mothership Siege. AEGIS defends the IRON VANGUARD; KRONOS has to tear it
## down in three stages:
##   SHIELDS  - four shield generators keep the hull untouchable.
##   ARMOR    - the bubble is gone; every hit on the hull chips the armour.
##   REACTOR  - the armour has failed and the core's shutters blow open.
## Destroying the core wins for the attackers. The defenders win if the
## clock runs out or the attackers run out of reinforcements (tickets).
## Turrets are server-run AI; the server owns every hit point and streams
## a compact state to the peers. Lives at Arena/Siege so RPC paths match.

enum Stage { SHIELDS, ARMOR, REACTOR, DESTROYED }

const DEFENDERS := 0
const ATTACKERS := 1
## Kill-feed / damage id for the mothership's own guns.
const MOTHERSHIP_ID := -2
const TIME_LIMIT := 720.0
const TICKETS := 110
const STAGE_BONUS_TICKETS := 25
const ARMOR := 50000.0
const STATE_RATE := 10.0
const TURRET_THINK := 0.3
## Mothership pose in the arena: broadside to the attackers, bow angled at them.
const POSITION := Vector3(-1150, 40, 0)
const YAW := -0.3
const TARGET_PART_BASE := 10000

var arena: Arena
var mothership: Mothership
var stage := Stage.SHIELDS
var armor := ARMOR
var tickets := TICKETS
var _state_t := 0.0
var _think_t := 0.0
var _fire_batch := PackedFloat32Array()
var _breaches := 0
var _end_at := -1.0
var _end_winner := -1
var _attacker_dmg: Dictionary = {}  # ship id -> damage dealt to the mothership


func setup(a: Arena) -> void:
	arena = a
	name = "Siege"
	mothership = Mothership.new()
	arena.add_child(mothership)
	mothership.setup(arena, DEFENDERS, Transform3D(Basis(Vector3.UP, YAW), POSITION))


func parts() -> Array[MothershipPart]:
	return mothership.parts


func core() -> MothershipPart:
	for p in mothership.parts:
		if p.kind == "core":
			return p
	return null


func generators_alive() -> int:
	var n := 0
	for p in mothership.parts:
		if p.kind == "generator" and p.alive:
			n += 1
	return n


func armor_fraction() -> float:
	return clampf(armor / ARMOR, 0.0, 1.0)


## 0..1 progress of the whole siege, for the HUD and bots.
func progress() -> float:
	match stage:
		Stage.SHIELDS:
			var hp := 0.0
			var mx := 0.0
			for p in mothership.parts:
				if p.kind == "generator":
					hp += p.hp
					mx += p.max_hp
			return (1.0 - hp / maxf(mx, 1.0)) / 3.0
		Stage.ARMOR:
			return 1.0 / 3.0 + (1.0 - armor_fraction()) / 3.0
		Stage.REACTOR:
			var c := core()
			return 2.0 / 3.0 + (1.0 - c.hp / c.max_hp) / 3.0
	return 1.0


func objective_text(team: int) -> String:
	var attack := team == ATTACKERS
	match stage:
		Stage.SHIELDS:
			return "Destroy the shield generators" if attack else "Protect the shield generators"
		Stage.ARMOR:
			return "Shields are down: pound the hull" if attack else "Shields down: keep them off the hull"
		Stage.REACTOR:
			return "The reactor is exposed: destroy it" if attack else "The reactor is exposed: defend it at all costs"
	return ""


func stage_name() -> String:
	return ["SHIELDS", "ARMOR", "REACTOR", "DESTROYED"][stage]


func time_limit() -> float:
	return TIME_LIMIT


func is_server() -> bool:
	return multiplayer.is_server()


# --- Spawning ----------------------------------------------------------------------

## Defenders launch from the far side of the hull, sheltered from the attack.
func spawn_transform(team: int, slot: int) -> Transform3D:
	if team != DEFENDERS:
		return arena.ctl.default_spawn(team, slot)
	var m := mothership.global_transform
	var e := mothership.half_extents
	var row := slot % 5
	var col := slot / 5
	var local := Vector3(-(e.x + 140.0 + col * 70.0), (row - 2) * 45.0 + randf_range(-8, 8), -e.z * 0.35 + row * 90.0 + col * 40.0)
	var pos := m * local
	var fwd := (m.basis * Vector3(-0.35, 0.0, -1.0)).normalized()
	return Transform3D(Basis.looking_at(fwd, Vector3.UP), pos)


func can_respawn(s: Ship) -> bool:
	return s.team != ATTACKERS or tickets > 0


## Server: a pilot died.
func on_death(victim: Ship) -> void:
	if victim.team == ATTACKERS and stage != Stage.DESTROYED:
		tickets = maxi(0, tickets - 1)


# --- Targets -----------------------------------------------------------------------

func part_by_target_id(id: int) -> MothershipPart:
	var i := id - TARGET_PART_BASE
	if i >= 0 and i < mothership.parts.size():
		return mothership.parts[i]
	return null


## Parts an attacker can usefully shoot right now.
func live_targets(for_team: int) -> Array:
	var out := []
	if for_team == DEFENDERS or stage == Stage.DESTROYED:
		return out
	for p in mothership.parts:
		if p.alive and p.exposed:
			out.append(p)
	return out


## Best part in front of the player's nose (aim assist and lock fallback).
func pick_part_target(ship: Ship) -> MothershipPart:
	var fwd := -ship.global_basis.z
	var best: MothershipPart = null
	var best_score := -INF
	for p in live_targets(ship.team):
		var to: Vector3 = p.aim_center() - ship.global_position
		var dist := to.length()
		if dist > 2400.0:
			continue
		var dot := fwd.dot(to / dist)
		if dot < 0.9:
			continue
		var score := dot * 4.0 - dist / 1500.0 + (0.3 if p.kind == "generator" or p.kind == "core" else 0.0)
		if score > best_score:
			best_score = score
			best = p
	return best


## What an attacking bot should go after: {part, point, normal}.
func pick_strike(ship: Ship, personality: float) -> Dictionary:
	var pos := ship.global_position
	var options := []
	for p in mothership.parts:
		if not p.alive or not p.exposed:
			continue
		var w := 1.0
		match p.kind:
			"generator":
				w = 6.0 if stage == Stage.SHIELDS else 0.0
			"core":
				w = 12.0
			"heavy":
				w = 1.3 + personality
			"flak":
				w = 0.8 + personality * 0.6
		if w <= 0.0:
			continue
		var d := pos.distance_to(p.aim_center())
		options.append([w / (0.5 + d / 1500.0), p])
	if stage == Stage.ARMOR and not mothership.surface.is_empty():
		# Hull strafing runs on the side facing the attacker.
		for i in 6:
			var s: Array = mothership.surface[randi() % mothership.surface.size()]
			var wp := mothership.world_point(s)
			var n := mothership.world_normal(s)
			var facing := maxf(0.1, n.dot((pos - wp).normalized()))
			options.append([3.0 * facing / (0.5 + pos.distance_to(wp) / 1500.0), {"point": wp, "normal": n}])
	if options.is_empty():
		return {}
	var total := 0.0
	for o in options:
		total += float(o[0])
	var r := randf() * total
	for o in options:
		r -= float(o[0])
		if r <= 0.0:
			return _strike_of(o[1])
	return _strike_of(options[options.size() - 1][1])


func _strike_of(o: Variant) -> Dictionary:
	if o is MothershipPart:
		var p: MothershipPart = o
		return {"part": p, "point": p.aim_center(), "normal": p.global_basis.y}
	return {"part": null, "point": o.point, "normal": o.normal}


# --- Damage (server) ----------------------------------------------------------------

func owns(col: Object) -> bool:
	return col.has_meta("mship") or col.has_meta("mpart")


## Every peer: visual reaction to a hit on the ship or one of its parts.
func hit_fx(col: Object, pos: Vector3, normal: Vector3, color: Color, team: int) -> void:
	if col.has_meta("mpart"):
		var p := mothership.parts[int(col.get_meta("mpart"))]
		if p.kind == "core" and not p.exposed:
			FX.sparks(arena, pos, normal, Color(1.0, 0.8, 0.5), 4)
		else:
			p.show_hit()
			FX.impact(arena, pos, normal, color, false)
	elif stage == Stage.SHIELDS and team != DEFENDERS:
		mothership.shield_hit(pos)
		FX.impact(arena, pos, normal, color, true)
	else:
		FX.impact(arena, pos, normal, color, false)
		if randf() < 0.25:
			FX.dust(arena, pos, normal, 2.0, 3)


## Server: route damage from a collider. Returns true if it was ours.
func damage_collider(col: Object, amount: float, wdef: Dictionary, attacker_id: int, team: int) -> bool:
	if not owns(col):
		return false
	if team == DEFENDERS or stage == Stage.DESTROYED:
		return true
	if col.has_meta("mpart"):
		damage_part(mothership.parts[int(col.get_meta("mpart"))], amount, wdef, attacker_id)
	else:
		damage_hull(amount, wdef, attacker_id)
	return true


func damage_part(p: MothershipPart, amount: float, wdef: Dictionary, attacker_id: int) -> void:
	if not p.alive or not p.exposed or stage == Stage.DESTROYED:
		return
	var dmg := amount * float(wdef.get("vs_hull", 1.0))
	p.hp -= dmg
	_credit(attacker_id, dmg)
	if p.hp <= 0.0:
		p.hp = 0.0
		if p.kind == "core":
			_core_destroyed(attacker_id)
		else:
			_send("_net_part_destroyed", [p.index, attacker_id])
			_net_part_destroyed(p.index, attacker_id)
			if p.kind == "generator" and generators_alive() == 0:
				_set_stage(Stage.ARMOR)


func damage_hull(amount: float, wdef: Dictionary, attacker_id: int) -> void:
	if stage != Stage.ARMOR:
		return
	var dmg := amount * float(wdef.get("vs_hull", 1.0))
	armor -= dmg
	_credit(attacker_id, dmg)
	mothership.set_damage(1.0 - armor_fraction())
	# Every 12.5 % of armour lost blows a breach somewhere on the hull.
	var due := int((1.0 - armor_fraction()) * 8.0)
	while _breaches < due and _breaches < 8:
		_breaches += 1
		var seed := randi()
		_send("_net_breach", [seed, _breaches % 2 == 0])
		_net_breach(seed, _breaches % 2 == 0)
	if armor <= 0.0:
		armor = 0.0
		_set_stage(Stage.REACTOR)


## Server: blast damage from a missile against every part in range.
func splash(pos: Vector3, radius: float, damage: float, wdef: Dictionary, attacker_id: int, team: int, collider: Object) -> void:
	if team == DEFENDERS or stage == Stage.DESTROYED:
		return
	var hit_hull := collider != null and collider.has_meta("mship")
	for p in mothership.parts:
		if not p.alive or not p.exposed:
			continue
		var d := p.aim_center().distance_to(pos) - p.radius
		if d < radius:
			damage_part(p, damage * clampf(1.0 - d / radius, 0.35, 1.0), wdef, attacker_id)
	if hit_hull:
		damage_hull(damage, wdef, attacker_id)


func _credit(attacker_id: int, dmg: float) -> void:
	if attacker_id < 0:
		return
	_attacker_dmg[attacker_id] = float(_attacker_dmg.get(attacker_id, 0.0)) + dmg


func _set_stage(s: Stage) -> void:
	if s == Stage.ARMOR or s == Stage.REACTOR:
		tickets += STAGE_BONUS_TICKETS
	_send("_net_stage", [s, true])
	_net_stage(s, true)


func _core_destroyed(killer_id: int) -> void:
	stage = Stage.DESTROYED
	_send("_net_destroyed", [killer_id])
	_net_destroyed(killer_id)
	# Let the break-up play before the results come up.
	_end_at = arena.time + 8.5
	_end_winner = ATTACKERS


# --- Server tick -------------------------------------------------------------------

func server_tick(delta: float) -> void:
	var ctl := arena.ctl
	if _end_at > 0.0:
		if arena.time >= _end_at and ctl.phase == MatchController.Phase.LIVE:
			_end_at = -1.0
			ctl.end_match(_end_winner)
		return
	if ctl.phase != MatchController.Phase.LIVE or stage == Stage.DESTROYED:
		return
	if ctl.time_left <= 0.0:
		ctl.end_match(DEFENDERS)
		return
	if tickets <= 0:
		var any_alive := false
		for s in arena.ships:
			if s.team == ATTACKERS and s.alive:
				any_alive = true
				break
		if not any_alive:
			ctl.end_match(DEFENDERS)
			return
	_run_turrets(delta)


func _run_turrets(delta: float) -> void:
	_think_t -= delta
	var think := _think_t <= 0.0
	if think:
		_think_t = TURRET_THINK
	var diff := float(Settings.get_value("bot_difficulty", 1))
	for p in mothership.parts:
		if not p.alive or not p.is_turret():
			continue
		if think:
			_pick_turret_target(p)
		var t := arena.ship_by_id(p.target_id)
		if t == null or not t.alive:
			p.target_id = -1
			continue
		var w := ShipLibrary.weapon(str(p.spec.weapon))
		var muzzle := p.muzzles[0].global_position
		var lead := Arena.lead_point(muzzle, Vector3.ZERO, t.global_position, t.velocity, float(w.speed))
		if randf() < delta * 1.5:
			var err := (28.0 if p.kind == "flak" else 14.0) * (1.25 - diff * 0.2)
			p.aim_error = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * err
		var off := p.track(lead + p.aim_error, delta)
		p.cooldown -= delta
		if p.burst_left > 0:
			p.burst_t -= delta
			if p.burst_t <= 0.0:
				p.burst_t = float(p.spec.burst_gap)
				p.burst_left -= 1
				_turret_shot(p, w)
		elif p.cooldown <= 0.0 and off < 0.08:
			p.burst_left = int(p.spec.burst)
			p.burst_t = 0.0
			p.cooldown = float(p.spec.reload) + float(p.spec.burst) * float(p.spec.burst_gap)
	if not _fire_batch.is_empty():
		_send("_net_fire", [_fire_batch])
		_fire_batch = PackedFloat32Array()


func _pick_turret_target(p: MothershipPart) -> void:
	var best: Ship = null
	var best_score := INF
	var range_m := float(p.spec.range)
	var from := p.aim_center() + p.global_basis.y * p.radius
	for s in arena.ships:
		if not s.alive or s.team == DEFENDERS:
			continue
		var d := s.global_position.distance_to(from)
		if d > range_m or not p.can_see(s.global_position):
			continue
		# Stick with the current target a little to avoid twitching.
		var score := d - (300.0 if s.ship_id == p.target_id else 0.0)
		if score < best_score:
			var blocked := mothership.probe(from, (s.global_position - from) / d, d)
			if not blocked.is_empty():
				continue
			best_score = score
			best = s
	p.target_id = best.ship_id if best else -1


func _turret_shot(p: MothershipPart, w: Dictionary) -> void:
	var origin := p.next_muzzle()
	var spread := deg_to_rad(float(w.spread))
	var dir := (p.fire_direction() + Vector3(randf_range(-spread, spread), randf_range(-spread, spread), randf_range(-spread, spread))).normalized()
	_fire_batch.append_array(PackedFloat32Array([p.index, origin.x, origin.y, origin.z, dir.x, dir.y, dir.z]))
	_spawn_turret_shot(p, origin, dir)


func _spawn_turret_shot(p: MothershipPart, origin: Vector3, dir: Vector3) -> void:
	var weapon := str(p.spec.weapon)
	arena.projectiles.spawn(MOTHERSHIP_ID, DEFENDERS, origin, dir, weapon, Vector3.ZERO)
	p.kick(origin)
	if not App.is_dedicated:
		var heavy := p.kind == "heavy"
		Sfx.play_at("cannon" if heavy else "flak", origin, 4.0 if heavy else -1.0, randf_range(0.9, 1.1), 3200.0 if heavy else 1800.0)


## Every tick on clients: turrets follow their server-picked targets.
func _process(delta: float) -> void:
	if arena == null or is_server():
		return
	for p in mothership.parts:
		if not p.alive or not p.is_turret():
			continue
		var t := arena.ship_by_id(p.target_id)
		if t and t.alive:
			p.track(t.global_position + t.velocity * 0.6, delta)


func _physics_process(delta: float) -> void:
	if arena == null or not arena.is_scene_ready or not Net.is_online() or not is_server():
		return
	_state_t -= delta
	if _state_t <= 0.0:
		_state_t = 1.0 / STATE_RATE
		_send("_net_state", [_pack_state()])


# --- Networking ----------------------------------------------------------------------

func _send(method: StringName, args: Array) -> void:
	if not Net.is_online() or not is_server():
		return
	var connected := multiplayer.get_peers()
	for peer in arena.ctl.ready_peers():
		if peer in connected:
			callv("rpc_id", [peer, method] + args)


func _pack_state() -> PackedFloat32Array:
	var out := PackedFloat32Array([stage, armor, tickets])
	for p in mothership.parts:
		out.append(p.hp)
		out.append(p.target_id)
	return out


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(st: PackedFloat32Array) -> void:
	if st.size() < 3:
		return
	armor = st[1]
	tickets = int(st[2])
	mothership.set_damage(1.0 - armor_fraction() if stage >= Stage.ARMOR else 0.0)
	var n := mothership.parts.size()
	for i in n:
		if 3 + i * 2 + 1 >= st.size():
			break
		var p := mothership.parts[i]
		if p.alive:
			p.hp = st[3 + i * 2]
			p.target_id = int(st[3 + i * 2 + 1])


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_fire(batch: PackedFloat32Array) -> void:
	var i := 0
	while i + 7 <= batch.size():
		var idx := int(batch[i])
		if idx >= 0 and idx < mothership.parts.size():
			var p := mothership.parts[idx]
			if p.alive:
				_spawn_turret_shot(p, Vector3(batch[i + 1], batch[i + 2], batch[i + 3]), Vector3(batch[i + 4], batch[i + 5], batch[i + 6]))
		i += 7


@rpc("authority", "call_remote", "reliable")
func _net_part_destroyed(idx: int, killer_id: int) -> void:
	var p := mothership.parts[idx]
	if not p.alive:
		return
	mothership.part_destroyed(p)
	var k := arena.ship_by_id(killer_id)
	if k:
		k.captures += 1
		k.score += int(p.spec.score)
	arena.on_siege_part_destroyed(p, k)


@rpc("authority", "call_remote", "reliable")
func _net_breach(seed: int, big: bool) -> void:
	mothership.breach(seed, big)
	if arena.local_ship and arena.local_ship.alive:
		arena.explosion_shake(mothership.global_position, 30.0)


@rpc("authority", "call_remote", "reliable")
func _net_stage(s: int, animated: bool) -> void:
	var prev := stage
	stage = s as Stage
	if stage >= Stage.ARMOR and prev < Stage.ARMOR:
		mothership.collapse_shield(animated)
	if stage >= Stage.REACTOR and prev < Stage.REACTOR:
		var c := core()
		if c:
			mothership.reveal_core(c, animated)
	mothership.set_damage(1.0 - armor_fraction() if stage >= Stage.ARMOR else 0.0)
	if animated:
		arena.on_siege_stage(stage)


@rpc("authority", "call_remote", "reliable")
func _net_destroyed(killer_id: int) -> void:
	stage = Stage.DESTROYED
	var c := core()
	var pos := c.aim_center() if c else mothership.global_position
	var k := arena.ship_by_id(killer_id)
	if k and c:
		k.captures += 1
		k.score += int(c.spec.score)
	mothership.play_destruction(pos)
	arena.on_siege_destroyed(k)


func get_state() -> Dictionary:
	var hp := []
	for p in mothership.parts:
		hp.append(p.hp if p.alive else 0.0)
	return {"stage": stage, "armor": armor, "tickets": tickets, "hp": hp, "breaches": _breaches}


func apply_state(st: Dictionary) -> void:
	armor = float(st.get("armor", ARMOR))
	tickets = int(st.get("tickets", TICKETS))
	_breaches = int(st.get("breaches", 0))
	var hp: Array = st.get("hp", [])
	for i in mini(hp.size(), mothership.parts.size()):
		var p := mothership.parts[i]
		if float(hp[i]) <= 0.0:
			if p.alive:
				mothership.part_destroyed(p, true)
		else:
			p.hp = float(hp[i])
	_net_stage(int(st.get("stage", 0)), false)
	for i in _breaches:
		mothership.add_fire(mothership.world_point(mothership.surface[(i * 37) % mothership.surface.size()]),
			mothership.world_normal(mothership.surface[(i * 37) % mothership.surface.size()]), 40.0)
