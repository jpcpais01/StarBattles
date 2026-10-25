class_name Arena
extends Node3D
## Root of a match. Builds the Jovian theatre over a few frames (heavy
## mesh work on worker threads behind the loading fade), owns the shared
## systems, and routes gameplay events to the HUD, camera and audio.

signal scene_ready

const BOUNDARY := 2500.0
const POINTS := [Vector3(-950, 60, 280), Vector3(0, -40, -120), Vector3(950, 90, 260)]

static var current: Arena

var is_scene_ready := false
var time := 0.0
var ships: Array[Ship] = []
var points: Array[CapturePoint] = []
var missiles: Array = []
var local_ship: Ship
## "conquest" or "siege".
var mode := "conquest"
var siege: SiegeRules

var env: SpaceEnv
var field: AsteroidField
var fx_root: Node3D
var ships_root: Node3D
var projectiles: ProjectileSystem
var ctl: MatchController
var camera: CameraRig
var input: PlayerInput
var hud: Node
var _ray := PhysicsRayQueryParameters3D.new()
var _autotest_t := 0.0
var _match_recorded := false
var _ships_by_id: Dictionary = {}


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	name = "Arena"
	_ray.collide_with_areas = true
	_ray.collide_with_bodies = true
	_ray.collision_mask = 1 | 2
	var cfg: Dictionary = App.match_config
	var seed := int(cfg.get("seed", randi()))
	mode = "siege" if str(cfg.get("mode", "")) == "siege" else "conquest"
	env = SpaceEnv.new()
	env.home_moon = SpaceEnv.moon_for_seed(seed)
	add_child(env)
	fx_root = Node3D.new()
	fx_root.name = "FX"
	add_child(fx_root)
	ships_root = Node3D.new()
	ships_root.name = "Ships"
	add_child(ships_root)
	field = AsteroidField.new()
	field.name = "Asteroids"
	field.arena = self
	add_child(field)
	projectiles = ProjectileSystem.new()
	projectiles.arena = self
	add_child(projectiles)
	camera = CameraRig.new()
	add_child(camera)
	camera.global_position = Vector3(-2300, 60, 0)
	input = PlayerInput.new()
	input.arena = self
	add_child(input)
	ctl = MatchController.new()
	ctl.name = "Match"
	ctl.arena = self
	add_child(ctl)
	if mode == "siege":
		siege = SiegeRules.new()
		add_child(siege)
		siege.setup(self)
	hud = preload("res://ui/hud/hud.gd").new()
	hud.arena = self
	add_child(hud)
	input.touch = hud.touch
	for i in (POINTS.size() if mode == "conquest" else 0):
		var p := CapturePoint.new()
		p.setup(i, POINTS[i])
		add_child(p)
		points.append(p)
	_build_carriers()
	await field.prepare_variants()
	var avoid := []
	for p in points:
		avoid.append([p.position, CapturePoint.RADIUS])
	if siege:
		avoid.append([SiegeRules.POSITION, siege.mothership.half_extents.z + 180.0])
	for t in 2:
		avoid.append([Vector3(-2050 if t == 0 else 2050, 0, 0), 260.0])
	field.populate(seed, avoid)
	await get_tree().process_frame
	if multiplayer.is_server():
		ctl.server_start()
	else:
		ctl.client_ready()
	Net.multiplayer.peer_disconnected.connect(ctl.on_peer_left)
	Net.session_ended.connect(_on_session_ended)
	is_scene_ready = true
	scene_ready.emit()
	Sfx.stop_music(2.0)
	print("[Arena] ready: %d ships, %d asteroids, env tris ~%d" % [ships.size(), field.records.size(), field.total_tris])


func _build_carriers() -> void:
	for t in 2:
		if siege and t == SiegeRules.DEFENDERS:
			continue  # the IRON VANGUARD is their base
		var root := Node3D.new()
		root.name = "Carrier_%d" % t
		add_child(root)
		var side := -1.0 if t == 0 else 1.0
		root.position = Vector3(side * 2380.0, 120.0, -260.0 * side)
		root.rotation.y = PI * 0.5 * side + 0.25 * side
		root.scale = Vector3.ONE * 34.0
		var mesh := HullBuilder.build("carrier")
		var mi := MeshInstance3D.new()
		mi.mesh = mesh.hull
		mi.material_override = Mats.hull(t, App.team_color(t))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		for s in [-1.0, 1.0]:
			var fx := EngineFX.new()
			root.add_child(fx)
			fx.setup(Vector3(s * 1.3, 0.0, 11.05), 0.7, App.team_color(t).lerp(Color.WHITE, 0.2), false)
			fx.thrust = 0.35
		var light := OmniLight3D.new()
		light.light_color = App.team_color(t)
		light.omni_range = 9.0
		light.light_energy = 3.0
		light.position = Vector3(0, -1.5, -3)
		root.add_child(light)


func set_local_ship(s: Ship) -> void:
	local_ship = s
	camera.ship = s
	hud.set_ship(s)


func on_local_spawn(s: Ship, initial: bool) -> void:
	input.throttle = 0.65
	input.recenter_aim()
	camera.look_back = false
	hud.on_spawn(initial)
	Sfx.play("spawn", -4.0)
	if not App.is_mobile:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Ship or mothership part by network target id (see target_id_of).
func target_by_id(id: int) -> Node3D:
	if siege and id >= SiegeRules.TARGET_PART_BASE:
		return siege.part_by_target_id(id)
	return ship_by_id(id)


func target_id_of(t: Object) -> int:
	if t is Ship:
		return (t as Ship).ship_id
	if t is MothershipPart:
		return SiegeRules.TARGET_PART_BASE + (t as MothershipPart).index
	return -1


## Everything a pilot on `team` could lock missiles onto.
func lock_candidates(team: int) -> Array:
	var out: Array = []
	for s in ships:
		if s.alive and s.team != team:
			out.append(s)
	if siege:
		out.append_array(siege.live_targets(team))
	return out


func ship_by_id(id: int) -> Ship:
	if id < 0:
		return null
	for s in ships:
		if s.ship_id == id:
			return s
	return null


func net_time() -> float:
	return time


func raycast(from: Vector3, to: Vector3, exclude: Array = []) -> Dictionary:
	_ray.from = from
	_ray.to = to
	_ray.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(_ray)


## Intercept point for a projectile fired from `p0` (moving `v0`) at speed
## `speed` toward a target at `p1` moving `v1`.
static func lead_point(p0: Vector3, v0: Vector3, p1: Vector3, v1: Vector3, speed: float) -> Vector3:
	if speed <= 0.0:
		return p1
	var rel := p1 - p0
	var rv := v1 - v0 * 0.6
	var a := rv.dot(rv) - speed * speed
	var b := 2.0 * rel.dot(rv)
	var c := rel.dot(rel)
	var t := 0.0
	if absf(a) < 0.001:
		t = -c / b if absf(b) > 0.001 else 0.0
	else:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var sq := sqrt(disc)
			var t1 := (-b - sq) / (2.0 * a)
			var t2 := (-b + sq) / (2.0 * a)
			t = minf(t1, t2) if minf(t1, t2) > 0.0 else maxf(t1, t2)
	t = clampf(t, 0.0, 3.0)
	return p1 + rv * t


func on_bolt_hit(shooter_id: int, weapon_id: String, hit: Dictionary, dir: Vector3, color: Color, team := -1) -> void:
	var col: Object = hit.collider
	var pos: Vector3 = hit.position
	if col.has_meta("ship"):
		var s: Ship = col.get_meta("ship")
		var shielded := s.shield > 0.0
		s.show_hit(pos, shielded)
		FX.impact(self, pos, hit.normal, color, shielded)
		if s == local_ship:
			Sfx.play("hit_shield" if shielded else "hit_hull", -6.0, randf_range(0.9, 1.1))
		elif not App.is_dedicated and camera.global_position.distance_to(pos) < 400.0:
			Sfx.play_at("hit_shield" if shielded else "hit_hull", pos, -6.0)
		if multiplayer.is_server():
			var w := ShipLibrary.weapon(weapon_id)
			ctl.server_damage(s, float(w.damage), w, shooter_id, pos, false)
	elif siege and siege.owns(col):
		siege.hit_fx(col, pos, hit.normal, color, team)
		if not App.is_dedicated and camera.global_position.distance_to(pos) < 500.0 and randf() < 0.5:
			Sfx.play_at("hit_shield" if siege.stage == SiegeRules.Stage.SHIELDS else "hit_hull", pos, -8.0, randf_range(0.6, 0.8))
		if multiplayer.is_server():
			var w := ShipLibrary.weapon(weapon_id)
			siege.damage_collider(col, float(w.damage), w, shooter_id, team)
	elif col.has_meta("asteroid"):
		var id := int(col.get_meta("asteroid"))
		field.rock_hit_fx(id, pos, hit.normal)
		if randf() < 0.3:
			Sfx.play_at("rock_hit", pos, -10.0, randf_range(0.8, 1.2), 600.0)
		if multiplayer.is_server():
			field.damage(id, float(ShipLibrary.weapon(weapon_id).damage), pos, dir)


func camera_shake(amount: float) -> void:
	camera.add_trauma(amount)


func explosion_shake(pos: Vector3, size: float) -> void:
	if camera == null:
		return
	var d := camera.global_position.distance_to(pos)
	var k := clampf(size * 12.0 / maxf(d, 1.0), 0.0, 0.8)
	if k > 0.05:
		camera.add_trauma(k)


# --- Events from the match controller ---------------------------------------------------

func on_hit_event(attacker_id: int, target_id: int, amount: float, shielded: bool, dead: bool) -> void:
	var attacker := ship_by_id(attacker_id)
	var target := ship_by_id(target_id)
	if attacker and attacker == local_ship:
		hud.hit_marker(dead, shielded)
	if target and target == local_ship:
		hud.damage_from(attacker.global_position if attacker else target.global_position + Vector3(randf(), randf(), randf()), shielded)
		camera.add_trauma(clampf(amount / 150.0, 0.08, 0.5))
		Settings.vibrate(30 if shielded else 60)


func on_kill(victim: Ship, killer: Ship, assists: Array, killer_id := -1) -> void:
	var by_mothership := siege != null and killer_id == SiegeRules.MOTHERSHIP_ID
	hud.kill_feed(killer, victim, Mothership.DISPLAY_NAME if by_mothership else "")
	if victim == local_ship:
		camera.orbit_center = victim.global_position
		hud.on_death(killer, Mothership.DISPLAY_NAME if by_mothership else "")
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Settings.vibrate(200)
	elif killer == local_ship:
		hud.notify_kill(victim)
		Sfx.play("kill", -2.0)
	elif local_ship and assists.has(local_ship.ship_id):
		hud.notify_assist(victim)


func on_capture(p: CapturePoint, team: int, who: Array) -> void:
	var mine := local_ship and local_ship.team == team
	hud.banner("POINT %s SECURED" % p.letter if mine else "POINT %s LOST" % p.letter,
		App.TEAM_NAMES[team] + " holds " + p.letter, App.team_color(team))
	Sfx.play("capture" if mine else "ui_error", -2.0, 1.0 if mine else 0.7)
	if local_ship and who.has(local_ship.ship_id):
		hud.notify_points("+150 CAPTURE")


func on_point_neutralized(p: CapturePoint) -> void:
	hud.toast("Point %s neutralized" % p.letter)


# --- Siege events ---------------------------------------------------------------------------

func on_siege_part_destroyed(p: MothershipPart, killer: Ship) -> void:
	var mine := local_ship != null and local_ship.team == SiegeRules.ATTACKERS
	if p.kind == "generator":
		var left := siege.generators_alive()
		var sub := ("%d generator%s left" % [left, "" if left == 1 else "s"]) if left > 0 else "The shield is failing"
		hud.banner("GENERATOR DESTROYED" if mine else "GENERATOR LOST", sub, App.team_color(SiegeRules.ATTACKERS if mine else SiegeRules.DEFENDERS))
	else:
		hud.toast("%s destroyed%s" % [p.label.capitalize(), (" by " + killer.pilot_name) if killer else ""])
	if killer and killer == local_ship:
		hud.notify_points("+%d  %s DOWN" % [int(p.spec.score), p.label])
		Sfx.play("kill", -2.0)


func on_siege_stage(stage: int) -> void:
	var team := local_ship.team if local_ship else SiegeRules.ATTACKERS
	var col := App.team_color(SiegeRules.ATTACKERS) if team == SiegeRules.ATTACKERS else App.BAD
	match stage:
		SiegeRules.Stage.ARMOR:
			hud.banner("SHIELDS DOWN", siege.objective_text(team), col)
			Sfx.play("alarm", -4.0, 0.8)
		SiegeRules.Stage.REACTOR:
			hud.banner("REACTOR EXPOSED", siege.objective_text(team), col)
	camera_shake(0.6)


func on_siege_destroyed(killer: Ship) -> void:
	hud.banner("%s DESTROYED" % Mothership.DISPLAY_NAME, ("Final blow by " + killer.pilot_name) if killer else "The reactor has gone critical", App.team_color(SiegeRules.ATTACKERS))
	camera.cinematic(siege.mothership, 2600.0, 14.0)


func on_match_end(w: int) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if siege and w == SiegeRules.DEFENDERS:
		hud.banner("%s HOLDS" % Mothership.DISPLAY_NAME, "The carrier jumps to safety", App.team_color(SiegeRules.DEFENDERS))
		var mark := Node3D.new()
		add_child(mark)
		mark.global_position = siege.mothership.global_position
		siege.mothership.play_warp()
		camera.cinematic(mark, 2400.0, 5.0)
		await get_tree().create_timer(3.6).timeout
		if not is_inside_tree():
			return
	var result := {}
	if local_ship and not _match_recorded:
		_match_recorded = true
		result = Profile.record_match({"won": w == local_ship.team, "kills": local_ship.kills, "deaths": local_ship.deaths,
			"assists": local_ship.assists, "captures": local_ship.captures, "best_streak": local_ship.best_streak})
	hud.show_results(w, result)


func leave_match_to_menu() -> void:
	if Net.is_online():
		if multiplayer.is_server():
			_net_back_to_lobby.rpc()
		Net.end_match_to_lobby()
	if App.is_dedicated:
		# Dedicated servers alternate between the two modes.
		Net.match_mode = "conquest" if mode == "siege" else "siege"
		Net.start_match({"seed": randi(), "mode": Net.match_mode})
		return
	App.goto_scene(App.SCENE_MENU)


@rpc("authority", "call_remote", "reliable")
func _net_back_to_lobby() -> void:
	Net.end_match_to_lobby()
	App.goto_scene(App.SCENE_MENU)


func quit_match() -> void:
	if Net.is_online():
		Net.leave()
	App.goto_scene(App.SCENE_MENU)


func _on_session_ended(reason: String) -> void:
	hud.toast(reason)
	await get_tree().create_timer(1.5).timeout
	App.goto_scene(App.SCENE_MENU)


func _process(delta: float) -> void:
	if App.autotest_seconds > 0.0 and is_scene_ready:
		_autotest_t += delta
		if siege and int(_autotest_t / 15.0) != int((_autotest_t - delta) / 15.0):
			_autotest_siege_line()
		if _autotest_t >= App.autotest_seconds:
			App.autotest_seconds = 0.0
			_autotest_report()


## Autotest: what each side is up to, every 15 s of a siege.
func _autotest_siege_line() -> void:
	var modes := {}
	var dist := 0.0
	var n := 0
	for s in ships:
		if s.team != SiegeRules.ATTACKERS or not s.alive or not (s.controller is BotBrain):
			continue
		var key: String = BotBrain.Mode.keys()[(s.controller as BotBrain).mode]
		modes[key] = int(modes.get(key, 0)) + 1
		dist += s.global_position.distance_to(siege.mothership.global_position)
		n += 1
	var hp := []
	for p in siege.parts():
		if p.kind == "generator" or p.kind == "core":
			hp.append(int(p.hp))
	var turrets := 0
	for p in siege.parts():
		turrets += 1 if p.is_turret() and p.alive else 0
	print("[Autotest] t=%.0f siege %s armor=%.0f tickets=%d gen/core=%s turrets=%d attackers=%s avg_dist=%.0f" % [
		_autotest_t, siege.stage_name(), siege.armor, siege.tickets, str(hp), turrets, str(modes), dist / maxf(1, n)])


func _autotest_report() -> void:
	var k := [0, 0]
	var alive := 0
	for s in ships:
		k[s.team] += s.kills
		alive += 1 if s.alive else 0
	var owners := []
	for p in points:
		owners.append(p.owner_team)
	print("[Autotest] t=%.1f mode=%s phase=%d score=%s kills=%s alive=%d points=%s asteroids=%d bolts=%d fps=%d" % [
		time, mode, ctl.phase, str(ctl.scores), str(k), alive, str(owners), field.records.size(), projectiles.count(), Engine.get_frames_per_second()])
	print("[Autotest] missiles fired=%d homing=%d hits=%d" % [Missile.stats.fired, Missile.stats.homing, Missile.stats.hits])
	if siege:
		var down := []
		for p in siege.parts():
			if not p.alive:
				down.append(p.kind)
		print("[Autotest] siege stage=%s armor=%.0f tickets=%d generators=%d destroyed=%s winner=%d" % [
			siege.stage_name(), siege.armor, siege.tickets, siege.generators_alive(), str(down), ctl.winner])
	get_tree().quit()
