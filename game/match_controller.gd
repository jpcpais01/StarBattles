class_name MatchController
extends Node
## Rules and netcode for a 10v10 match. Conquest scoring lives here; in
## Mothership Siege the objective rules live in SiegeRules (arena.siege) and
## this keeps doing pilots, damage, respawns and streaming. The server owns
## scoring, damage, deaths, respawns, bots and asteroid fractures; owners
## stream their own ship state; everyone simulates projectiles for visuals.

enum Phase { WARMUP, LIVE, ENDED }

const TEAM_SIZE := 10
const SCORE_LIMIT := 600
const TIME_LIMIT := 600.0
const WARMUP := 6.0
const RESPAWN_TIME := 5.0
const SNAP_RATE := 20.0
const CLIENT_RATE := 30.0
const KILL_POINTS := 3
const SPAWN_PROTECT := 2.5

const BOT_NAMES := ["Viper", "Nomad", "Halcyon", "Jinx", "Rook", "Sable", "Comet", "Vex", "Quill", "Talon",
	"Echo", "Mako", "Wisp", "Rune", "Kestrel", "Onyx", "Pike", "Zephyr", "Brisk", "Cinder", "Ghost", "Lumen"]

var arena: Arena
var phase := Phase.WARMUP
var phase_time := WARMUP
var scores := [0.0, 0.0]
var time_left := TIME_LIMIT
var winner := -1
var _next_ship_id := 1
var _snap_timer := 0.0
var _client_timer := 0.0
var _score_tick := 0.0
var _respawn_queue: Dictionary = {}  # ship_id -> time
var _pending_ship: Dictionary = {}  # ship_id -> def id for next spawn
var _spawned_at: Dictionary = {}
var _hit_confirm_acc: Dictionary = {}
var _countdown_last := -1
var _ended_handled := false
var _ready_peers: Dictionary = {}  # server: peers whose arena has loaded


func online() -> bool:
	return Net.is_online()


func is_server() -> bool:
	return multiplayer.is_server()


# --- Setup -----------------------------------------------------------------------

## Server: create every pilot. Humans from the roster, bots fill the rest.
func server_start() -> void:
	var humans := []
	if online():
		for pid in Net.players.keys():
			humans.append({"peer": pid, "name": Net.players[pid].name, "team": int(Net.players[pid].team), "ship": str(Net.players[pid].ship)})
	elif not App.is_dedicated:
		var my_team := clampi(int(App.match_config.get("team", 0)), 0, 1)
		humans.append({"peer": 1, "name": Profile.callsign(), "team": my_team, "ship": str(Profile.data.ship)})
	var records := []
	var per_team := [0, 0]
	for h in humans:
		records.append(_record(h.peer, h.name, h.team, h.ship, false))
		per_team[h.team] += 1
	var names := BOT_NAMES.duplicate()
	names.shuffle()
	var bi := 0
	for t in 2:
		while per_team[t] < TEAM_SIZE:
			var def_id: String = ShipLibrary.SHIP_ORDER[randi() % ShipLibrary.SHIP_ORDER.size()]
			records.append(_record(1, names[bi % names.size()], t, def_id, true))
			bi += 1
			per_team[t] += 1
	for r in records:
		_create_ship(r)
	for s in arena.ships:
		_respawn_now(s, true)


func _record(peer: int, pname: String, team: int, def_id: String, bot: bool) -> Dictionary:
	var r := {"id": _next_ship_id, "peer": peer, "name": pname, "team": team, "def": def_id, "bot": bot,
		"skill": clampf(randf_range(0.35, 0.75) + (float(Settings.get_value("bot_difficulty", 1)) - 1.0) * 0.2, 0.15, 0.95)}
	_next_ship_id += 1
	return r


func _create_ship(r: Dictionary) -> Ship:
	var existing := arena.ship_by_id(int(r.id))
	if existing:
		return existing
	var s := Ship.new()
	arena.ships_root.add_child(s)
	s.setup(int(r.id), str(r.def), int(r.team), int(r.peer), str(r.name), bool(r.bot))
	arena.ships.append(s)
	_next_ship_id = maxi(_next_ship_id, int(r.id) + 1)
	if s.is_bot and is_server():
		s.controller = BotBrain.new(arena, float(r.get("skill", 0.5)))
	elif s.is_local_player():
		s.controller = arena.input if App.autotest_seconds <= 0.0 else BotBrain.new(arena, 0.6)
		arena.set_local_ship(s)
	return s


func _ship_record(s: Ship) -> Dictionary:
	return {"id": s.ship_id, "peer": s.owner_peer, "name": s.pilot_name, "team": s.team, "def": s.def_id, "bot": s.is_bot,
		"alive": s.alive, "hull": s.hull, "shield": s.shield, "xf": s.global_transform,
		"stats": [s.kills, s.deaths, s.assists, s.captures, s.score]}


func spawn_transform(team: int, slot: int) -> Transform3D:
	if arena.siege:
		return arena.siege.spawn_transform(team, slot)
	return default_spawn(team, slot)


## Conquest spawn lanes at each end of the arena, facing the middle.
func default_spawn(team: int, slot: int) -> Transform3D:
	var side := -1.0 if team == 0 else 1.0
	var row := slot % 5
	var col := slot / 5
	var pos := Vector3(side * 2050.0 + side * col * 60.0, (row - 2) * 28.0 + randf_range(-6, 6), (row - 2) * 55.0 + col * 30.0 + randf_range(-10, 10))
	return Transform3D(Basis.looking_at(Vector3(0, 0, pos.z * 0.3) - pos, Vector3.UP), pos)


func _respawn_now(s: Ship, initial := false) -> void:
	if _pending_ship.has(s.ship_id):
		s.def_id = _pending_ship[s.ship_id]
		_pending_ship.erase(s.ship_id)
	var slot := randi() % 10
	var xf := spawn_transform(s.team, slot)
	_spawned_at[s.ship_id] = arena.time
	if online():
		_send("_net_respawn", [s.ship_id, s.def_id, xf, initial])
	_net_respawn(s.ship_id, s.def_id, xf, initial)


@rpc("authority", "call_remote", "reliable")
func _net_respawn(id: int, def_id: String, xf: Transform3D, initial: bool) -> void:
	var s := arena.ship_by_id(id)
	if s == null:
		return
	if s.def_id != def_id or s.mounts.is_empty():
		s.setup(id, def_id, s.team, s.owner_peer, s.pilot_name, s.is_bot)
	s.spawn(xf)
	if s.is_local_player():
		arena.on_local_spawn(s, initial)


func request_ship(def_id: String) -> void:
	var me := arena.local_ship
	if me == null:
		return
	if is_server():
		_pending_ship[me.ship_id] = def_id
	else:
		_net_request_ship.rpc_id(1, me.ship_id, def_id)


@rpc("any_peer", "call_remote", "reliable")
func _net_request_ship(id: int, def_id: String) -> void:
	var s := arena.ship_by_id(id)
	if s and s.owner_peer == multiplayer.get_remote_sender_id() and ShipLibrary.SHIPS.has(def_id):
		_pending_ship[id] = def_id


# --- Late join / full state ------------------------------------------------------------

func client_ready() -> void:
	_net_client_ready.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _net_client_ready() -> void:
	var peer := multiplayer.get_remote_sender_id()
	# A human joining mid-match takes over a bot slot on their team.
	var has_ship := false
	for s in arena.ships:
		if s.owner_peer == peer and not s.is_bot:
			has_ship = true
	if not has_ship and Net.players.has(peer):
		var info: Dictionary = Net.players[peer]
		var team := int(info.team)
		var replaced: Ship = null
		for s in arena.ships:
			if s.is_bot and s.team == team:
				replaced = s
				break
		if replaced:
			_remove_ship(replaced.ship_id)
		var r := _record(peer, str(info.name), team, str(info.ship), false)
		var s := _create_ship(r)
		_send("_net_add_ship", [r])
		_respawn_queue[s.ship_id] = arena.time + 1.0
	var ships := []
	for s in arena.ships:
		ships.append(_ship_record(s))
	var pts := []
	for p in arena.points:
		pts.append([p.progress, p.owner_team, p.contested])
	_net_full_state.rpc_id(peer, {"ships": ships, "asteroids": arena.field.get_state(), "points": pts,
		"scores": scores, "time_left": time_left, "phase": phase, "phase_time": phase_time, "time": arena.time,
		"siege": arena.siege.get_state() if arena.siege else {}})
	_ready_peers[peer] = true


func ready_peers() -> Array:
	return _ready_peers.keys()


## Server: sends an RPC to every client whose arena has finished loading
## (others get everything at once in the full state when they report ready).
func _send(method: StringName, args: Array) -> void:
	var connected := multiplayer.get_peers()
	for peer in _ready_peers.keys():
		if peer in connected:
			callv("rpc_id", [peer, method] + args)


@rpc("authority", "call_remote", "reliable")
func _net_full_state(state: Dictionary) -> void:
	arena.time = float(state.time)
	scores = state.scores
	time_left = float(state.time_left)
	phase = int(state.phase) as Phase
	phase_time = float(state.phase_time)
	arena.field.apply_state(state.asteroids)
	for i in mini(state.points.size(), arena.points.size()):
		var p: Array = state.points[i]
		arena.points[i].set_state(p[0], p[1], p[2])
	if arena.siege and not (state.get("siege", {}) as Dictionary).is_empty():
		arena.siege.apply_state(state.siege)
	for r in state.ships:
		var s := _create_ship(r)
		s.kills = r.stats[0]
		s.deaths = r.stats[1]
		s.assists = r.stats[2]
		s.captures = r.stats[3]
		s.score = r.stats[4]
		if r.alive:
			s.spawn(r.xf)
			s.hull = r.hull
			s.shield = r.shield
			if s.is_local_player():
				arena.on_local_spawn(s, true)
	arena.hud.refresh_roster()


@rpc("authority", "call_remote", "reliable")
func _net_add_ship(r: Dictionary) -> void:
	_create_ship(r)
	arena.hud.refresh_roster()


func _remove_ship(id: int) -> void:
	if online() and is_server():
		_send("_net_remove_ship", [id])
	_net_remove_ship(id)


@rpc("authority", "call_remote", "reliable")
func _net_remove_ship(id: int) -> void:
	var s := arena.ship_by_id(id)
	if s:
		arena.ships.erase(s)
		s.queue_free()
		arena.hud.refresh_roster()


## Server: a human left — hand their slot back to a bot.
func on_peer_left(peer: int) -> void:
	if not is_server():
		return
	_ready_peers.erase(peer)
	for s in arena.ships.duplicate():
		if s.owner_peer == peer and not s.is_bot:
			var team: int = s.team
			_remove_ship(s.ship_id)
			var r := _record(1, BOT_NAMES[randi() % BOT_NAMES.size()], team, ShipLibrary.SHIP_ORDER[randi() % ShipLibrary.SHIP_ORDER.size()], true)
			_create_ship(r)
			if online():
				_send("_net_add_ship", [r])
			_respawn_queue[int(r.id)] = arena.time + 2.0


# --- Main loop ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if arena == null or not arena.is_scene_ready:
		return
	arena.time += delta
	if is_server():
		_server_tick(delta)
	if online():
		_net_tick(delta)


func _server_tick(delta: float) -> void:
	match phase:
		Phase.WARMUP:
			phase_time -= delta
			var c := int(ceil(phase_time))
			if c != _countdown_last and c <= 3 and c > 0:
				_countdown_last = c
			if phase_time <= 0.0:
				_set_phase(Phase.LIVE, arena.siege.time_limit() if arena.siege else TIME_LIMIT)
		Phase.LIVE:
			time_left -= delta
			if arena.siege:
				arena.siege.server_tick(delta)
				_tick_respawns()
				return
			for p in arena.points:
				var cap := p.simulate(delta, arena.ships)
				if cap >= 0:
					var who := []
					for s in arena.ships:
						if s.alive and s.team == cap and s.global_position.distance_to(p.global_position) < CapturePoint.RADIUS:
							who.append(s.ship_id)
					if online():
						_send("_net_capture", [p.index, cap, who])
					_net_capture(p.index, cap, who)
			_score_tick += delta
			if _score_tick >= 1.0:
				_score_tick -= 1.0
				for p in arena.points:
					if p.owner_team >= 0:
						scores[p.owner_team] += 1.0
			if scores[0] >= SCORE_LIMIT or scores[1] >= SCORE_LIMIT or time_left <= 0.0:
				var w := -1
				if scores[0] != scores[1]:
					w = 0 if scores[0] > scores[1] else 1
				_end(w)
		Phase.ENDED:
			phase_time -= delta
			if phase_time <= 0.0 and not _ended_handled:
				_ended_handled = true
				arena.leave_match_to_menu()
	_tick_respawns()


func _tick_respawns() -> void:
	for id in _respawn_queue.keys():
		if arena.time >= float(_respawn_queue[id]):
			_respawn_queue.erase(id)
			var s := arena.ship_by_id(id)
			if s and phase != Phase.ENDED:
				_respawn_now(s)


func _set_phase(p: Phase, t: float) -> void:
	if online():
		_send("_net_phase", [p, t])
	_net_phase(p, t)


@rpc("authority", "call_remote", "reliable")
func _net_phase(p: int, t: float) -> void:
	phase = p as Phase
	if phase == Phase.LIVE:
		time_left = t
		if arena.siege:
			var my_team := arena.local_ship.team if arena.local_ship else SiegeRules.ATTACKERS
			arena.hud.banner("ATTACK" if my_team == SiegeRules.ATTACKERS else "DEFEND", arena.siege.objective_text(my_team), App.team_color(my_team))
		else:
			arena.hud.banner("ENGAGE", "Capture and hold the objectives", App.ACCENT)
		Sfx.play("capture", -2.0, 0.8)
	else:
		phase_time = t


## Server: finish the match with winner `w` (-1 for a draw).
func end_match(w: int) -> void:
	if phase != Phase.ENDED:
		_end(w)


func _end(w: int) -> void:
	var stats := {}
	for s in arena.ships:
		stats[s.ship_id] = [s.kills, s.deaths, s.assists, s.captures, s.score, s.best_streak]
	if online():
		_send("_net_end", [w, scores, stats])
	_net_end(w, scores, stats)


@rpc("authority", "call_remote", "reliable")
func _net_end(w: int, final_scores: Array, stats: Dictionary) -> void:
	phase = Phase.ENDED
	phase_time = 14.0
	winner = w
	scores = final_scores
	for id in stats.keys():
		var s := arena.ship_by_id(int(id))
		if s:
			var st: Array = stats[id]
			s.kills = st[0]
			s.deaths = st[1]
			s.assists = st[2]
			s.captures = st[3]
			s.score = st[4]
			s.best_streak = st[5]
	arena.on_match_end(w)


# --- Weapons & damage -----------------------------------------------------------------

## Called by the ship's owner when a weapon fires.
func local_fire(ship: Ship, mount_idx: int, origin: Vector3, dir: Vector3, target_id: int) -> void:
	_spawn_shot(ship, mount_idx, origin, dir, target_id)
	if not online():
		return
	if is_server():
		_send("_net_fire", [ship.ship_id, mount_idx, origin, dir, target_id])
	else:
		_net_fire_up.rpc_id(1, ship.ship_id, mount_idx, origin, dir, target_id)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _net_fire_up(id: int, mount_idx: int, origin: Vector3, dir: Vector3, target_id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var s := arena.ship_by_id(id)
	if s == null or s.owner_peer != sender or not s.alive:
		return
	_spawn_shot(s, mount_idx, origin, dir, target_id)
	for peer in _ready_peers:
		if peer != sender:
			_net_fire.rpc_id(peer, id, mount_idx, origin, dir, target_id)


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_fire(id: int, mount_idx: int, origin: Vector3, dir: Vector3, target_id: int) -> void:
	var s := arena.ship_by_id(id)
	if s and s.alive:
		_spawn_shot(s, mount_idx, origin, dir, target_id)


func _spawn_shot(ship: Ship, mount_idx: int, origin: Vector3, dir: Vector3, target_id: int) -> void:
	if mount_idx < 0 or mount_idx >= ship.mounts.size():
		return
	var m := ship.mounts[mount_idx]
	var w := m.wdef
	match w.type:
		"projectile":
			arena.projectiles.spawn(ship.ship_id, ship.team, origin, dir, m.weapon_id, ship.velocity)
			m.kick()
			if not App.is_dedicated:
				Sfx.play_at(w.sound, origin, -3.0 if ship.is_local_player() else -8.0, randf_range(0.92, 1.08), 1200.0)
		"rail":
			m.kick(1.6)
			var to := origin + dir * float(w.range)
			var hit := arena.raycast(origin, to, [ship.hit_area.get_rid()])
			if not hit.is_empty():
				to = hit.position
				FX.sparks(arena, to, hit.normal, w.color, 18, true)
				if is_server():
					var col: Object = hit.collider
					if col.has_meta("ship"):
						var t: Ship = col.get_meta("ship")
						if t.team != ship.team:
							server_damage(t, float(w.damage), w, ship.ship_id, to, false)
					elif arena.siege and arena.siege.owns(col):
						arena.siege.damage_collider(col, float(w.damage), w, ship.ship_id, ship.team)
					elif col.has_meta("asteroid"):
						arena.field.damage(int(col.get_meta("asteroid")), float(w.damage) * 2.0, to, dir)
				if hit.collider.has_meta("ship"):
					var t2: Ship = hit.collider.get_meta("ship")
					t2.show_hit(to, t2.shield > 0.0)
				elif arena.siege and arena.siege.owns(hit.collider):
					arena.siege.hit_fx(hit.collider, to, hit.normal, w.color, ship.team)
			FX.rail_tracer(arena, origin, to, w.color)
			Sfx.play_at("rail", origin, 0.0 if ship.is_local_player() else -4.0, 1.0, 2400.0)
			if ship.is_local_player():
				arena.camera_shake(0.25)
		"missile":
			var m2 := Missile.new()
			arena.fx_root.add_child(m2)
			m2.setup(arena, ship.ship_id, ship.team, origin, dir, arena.target_by_id(target_id), ship.velocity.length())
			arena.missiles.append(m2)
			Sfx.play_at("missile", origin, -2.0, randf_range(0.9, 1.1), 1400.0)


## Server: apply damage and broadcast the consequences.
func server_damage(target: Ship, amount: float, wdef: Dictionary, attacker_id: int, pos: Vector3, continuous: bool) -> void:
	if not target.alive or phase == Phase.ENDED:
		return
	if arena.time - float(_spawned_at.get(target.ship_id, -100.0)) < SPAWN_PROTECT:
		return
	var shield_before := target.shield
	var dead := target.apply_damage(amount, wdef, attacker_id, arena.time)
	var attacker := arena.ship_by_id(attacker_id)
	# Batch beam hits into ~10 confirmations per second.
	var key := "%d_%d" % [attacker_id, target.ship_id]
	var acc: float = _hit_confirm_acc.get(key, 0.0) + amount
	if continuous and not dead and acc < amount * 6.0:
		_hit_confirm_acc[key] = acc
	else:
		_hit_confirm_acc.erase(key)
		_send_hit(attacker, target, acc if continuous else amount, shield_before > 0.0, dead)
	if dead:
		_kill(target, attacker_id, pos)


func _send_hit(attacker: Ship, target: Ship, amount: float, shielded: bool, dead: bool) -> void:
	var a_id := attacker.ship_id if attacker else -1
	for s in [attacker, target]:
		if s == null or s.is_bot:
			continue
		if s.owner_peer == multiplayer.get_unique_id():
			_net_hit(a_id, target.ship_id, amount, shielded, dead)
		elif online():
			_net_hit.rpc_id(s.owner_peer, a_id, target.ship_id, amount, shielded, dead)


@rpc("authority", "call_remote", "unreliable")
func _net_hit(attacker_id: int, target_id: int, amount: float, shielded: bool, dead: bool) -> void:
	arena.on_hit_event(attacker_id, target_id, amount, shielded, dead)


func server_splash(pos: Vector3, radius: float, damage: float, wdef: Dictionary, attacker_id: int, team: int, direct: Node3D) -> void:
	for s in arena.ships:
		if not s.alive or s.team == team:
			continue
		var d := s.global_position.distance_to(pos) - s.radius * 0.5
		if s == direct or d < radius:
			var k := 1.0 if s == direct else clampf(1.0 - d / radius, 0.2, 1.0)
			server_damage(s, damage * k, wdef, attacker_id, pos, false)


func request_collision_damage(ship: Ship, amount: float, asteroid_id: int) -> void:
	if is_server():
		_collision(ship.ship_id, amount, asteroid_id)
	else:
		_net_collision.rpc_id(1, ship.ship_id, amount, asteroid_id)


@rpc("any_peer", "call_remote", "reliable")
func _net_collision(id: int, amount: float, asteroid_id: int) -> void:
	var s := arena.ship_by_id(id)
	if s and s.owner_peer == multiplayer.get_remote_sender_id():
		_collision(id, minf(amount, 600.0), asteroid_id)


func _collision(id: int, amount: float, asteroid_id: int) -> void:
	var s := arena.ship_by_id(id)
	if s == null:
		return
	server_damage(s, amount, {"vs_shield": 0.6, "vs_hull": 1.0}, -1, s.global_position, false)
	arena.field.damage(asteroid_id, amount * 0.5, s.global_position, s.velocity.normalized())


func _kill(victim: Ship, killer_id: int, pos: Vector3) -> void:
	var assists := []
	for a in victim.damagers.keys():
		if a != killer_id and arena.time - float(victim.damagers[a]) < 12.0:
			assists.append(a)
	if killer_id < 0 and killer_id != SiegeRules.MOTHERSHIP_ID and not victim.damagers.is_empty():
		# Credit the last attacker for collisions/boundary deaths.
		var last := -1.0
		for a in victim.damagers.keys():
			if float(victim.damagers[a]) > last:
				last = victim.damagers[a]
				killer_id = a
		assists.erase(killer_id)
	if arena.siege:
		arena.siege.on_death(victim)
	if arena.siege == null or arena.siege.can_respawn(victim):
		_respawn_queue[victim.ship_id] = arena.time + RESPAWN_TIME
	var killer := arena.ship_by_id(killer_id)
	if killer and killer.team != victim.team and phase == Phase.LIVE:
		scores[killer.team] += KILL_POINTS
	if online():
		_send("_net_kill", [victim.ship_id, killer_id, assists, pos])
	_net_kill(victim.ship_id, killer_id, assists, pos)


@rpc("authority", "call_remote", "reliable")
func _net_kill(victim_id: int, killer_id: int, assists: Array, pos: Vector3) -> void:
	var v := arena.ship_by_id(victim_id)
	var k := arena.ship_by_id(killer_id)
	if v == null:
		return
	v.kill()
	v.deaths += 1
	v.streak = 0
	if k and k != v:
		k.kills += 1
		k.score += 100
		k.streak += 1
		k.best_streak = maxi(k.best_streak, k.streak)
	for a in assists:
		var s := arena.ship_by_id(int(a))
		if s:
			s.assists += 1
			s.score += 40
	FX.explosion(arena, pos, v.radius * 1.4, App.team_color(v.team).lerp(Color(1, 0.6, 0.3), 0.6))
	arena.on_kill(v, k, assists, killer_id)


@rpc("authority", "call_remote", "reliable")
func _net_capture(idx: int, team: int, who: Array) -> void:
	var p: CapturePoint = arena.points[idx]
	p.owner_team = team
	p.progress = 1.0 if team == 0 else -1.0
	for id in who:
		var s := arena.ship_by_id(int(id))
		if s:
			s.captures += 1
			s.score += 150
	arena.on_capture(p, team, who)


func broadcast_asteroid_break(id: int, impact: Vector3, children: Array) -> void:
	if online():
		_send("_net_asteroid_break", [id, impact, children])
	_net_asteroid_break(id, impact, children)


@rpc("authority", "call_remote", "reliable")
func _net_asteroid_break(id: int, impact: Vector3, children: Array) -> void:
	arena.field.apply_break(id, impact, children)


# --- State streaming --------------------------------------------------------------------

func _net_tick(delta: float) -> void:
	if is_server():
		_snap_timer -= delta
		if _snap_timer <= 0.0:
			_snap_timer = 1.0 / SNAP_RATE
			_send_snapshot()
	else:
		_client_timer -= delta
		var me := arena.local_ship
		if _client_timer <= 0.0 and me and me.alive:
			_client_timer = 1.0 / CLIENT_RATE
			var buf := PackedByteArray()
			buf.resize(64)
			var n := _pack_ship(buf, 0, me)
			buf.resize(n)
			_net_client_state.rpc_id(1, buf)


func _pack_ship(buf: PackedByteArray, o: int, s: Ship) -> int:
	if buf.size() < o + 48:
		buf.resize(o + 64)
	var p := s.global_position
	var q := s.global_basis.get_rotation_quaternion()
	var aim := s.aim_point - p
	buf.encode_u16(o, s.ship_id)
	buf.encode_float(o + 2, p.x)
	buf.encode_float(o + 6, p.y)
	buf.encode_float(o + 10, p.z)
	buf.encode_half(o + 14, q.x)
	buf.encode_half(o + 16, q.y)
	buf.encode_half(o + 18, q.z)
	buf.encode_half(o + 20, q.w)
	buf.encode_half(o + 22, s.velocity.x)
	buf.encode_half(o + 24, s.velocity.y)
	buf.encode_half(o + 26, s.velocity.z)
	buf.encode_half(o + 28, aim.x)
	buf.encode_half(o + 30, aim.y)
	buf.encode_half(o + 32, aim.z)
	buf.encode_u16(o + 34, int(clampf(s.hull / s.max_hull, 0.0, 1.0) * 65535.0))
	buf.encode_u16(o + 36, int(clampf(s.shield / s.max_shield, 0.0, 1.0) * 65535.0))
	buf.encode_u8(o + 38, int(s.throttle * 255.0))
	buf.encode_u8(o + 39, s.net_flags())
	return o + 40


func _unpack_ship(buf: PackedByteArray, o: int) -> Dictionary:
	var p := Vector3(buf.decode_float(o + 2), buf.decode_float(o + 6), buf.decode_float(o + 10))
	var q := Quaternion(buf.decode_half(o + 14), buf.decode_half(o + 16), buf.decode_half(o + 18), buf.decode_half(o + 20)).normalized()
	return {"id": buf.decode_u16(o), "pos": p, "rot": q,
		"vel": Vector3(buf.decode_half(o + 22), buf.decode_half(o + 24), buf.decode_half(o + 26)),
		"aim": p + Vector3(buf.decode_half(o + 28), buf.decode_half(o + 30), buf.decode_half(o + 32)),
		"hull": buf.decode_u16(o + 34) / 65535.0, "shield": buf.decode_u16(o + 36) / 65535.0,
		"thr": buf.decode_u8(o + 38) / 255.0, "flags": buf.decode_u8(o + 39)}


func _send_snapshot() -> void:
	var buf := PackedByteArray()
	buf.resize(arena.ships.size() * 40 + 32)
	var o := 0
	var count := 0
	for s in arena.ships:
		if not s.alive:
			continue
		o = _pack_ship(buf, o, s)
		count += 1
	buf.resize(o)
	var pts := PackedFloat32Array()
	for p in arena.points:
		pts.append(p.progress)
		pts.append(float(p.owner_team))
		pts.append(1.0 if p.contested else 0.0)
	_send("_net_snapshot", [arena.time, PackedFloat32Array([scores[0], scores[1], time_left, phase_time, float(phase)]), pts, buf])


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_snapshot(t: float, header: PackedFloat32Array, pts: PackedFloat32Array, buf: PackedByteArray) -> void:
	# Keep our clock close to the server's.
	if absf(arena.time - t) > 0.5:
		arena.time = t
	else:
		arena.time = lerpf(arena.time, t, 0.1)
	scores = [header[0], header[1]]
	time_left = header[2]
	phase_time = header[3]
	for i in arena.points.size():
		var change := arena.points[i].set_state(pts[i * 3], int(pts[i * 3 + 1]), pts[i * 3 + 2] > 0.5)
		if change == -1:
			arena.on_point_neutralized(arena.points[i])
	var o := 0
	while o + 40 <= buf.size():
		var d := _unpack_ship(buf, o)
		o += 40
		var s := arena.ship_by_id(d.id)
		if s == null or not s.alive:
			continue
		s.hull = d.hull * s.max_hull
		s.shield = d.shield * s.max_shield
		if not s.is_local_player():
			s.push_snapshot(t, d.pos, d.rot, d.vel, d.thr, d.flags, d.aim)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _net_client_state(buf: PackedByteArray) -> void:
	if buf.size() < 40:
		return
	var d := _unpack_ship(buf, 0)
	var s := arena.ship_by_id(d.id)
	if s == null or s.owner_peer != multiplayer.get_remote_sender_id() or not s.alive:
		return
	s.push_snapshot(arena.time, d.pos, d.rot, d.vel, d.thr, d.flags, d.aim)
	s.firing_secondary = d.flags & Ship.FLAG_FIRE2 != 0
