class_name Arena
extends Node3D
## Root of a match. Builds the Saturn theatre over a few frames (heavy
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
	env = SpaceEnv.new()
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
	hud = preload("res://ui/hud/hud.gd").new()
	hud.arena = self
	add_child(hud)
	input.touch = hud.touch
	for i in POINTS.size():
		var p := CapturePoint.new()
		p.setup(i, POINTS[i])
		add_child(p)
		points.append(p)
	_build_carriers()
	await field.prepare_variants()
	var avoid := []
	for p in POINTS:
		avoid.append([p, CapturePoint.RADIUS])
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
	camera.look_back = false
	hud.on_spawn(initial)
	Sfx.play("spawn", -4.0)
	if not App.is_mobile:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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


func on_bolt_hit(shooter_id: int, weapon_id: String, hit: Dictionary, dir: Vector3, color: Color) -> void:
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


func on_kill(victim: Ship, killer: Ship, assists: Array) -> void:
	hud.kill_feed(killer, victim)
	if victim == local_ship:
		camera.orbit_center = victim.global_position
		hud.on_death(killer)
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


func on_match_end(w: int) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
		Net.start_match({"seed": randi()})
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
		if _autotest_t >= App.autotest_seconds:
			App.autotest_seconds = 0.0
			_autotest_report()


func _autotest_report() -> void:
	var k := [0, 0]
	var alive := 0
	for s in ships:
		k[s.team] += s.kills
		alive += 1 if s.alive else 0
	var owners := []
	for p in points:
		owners.append(p.owner_team)
	print("[Autotest] t=%.1f phase=%d score=%s kills=%s alive=%d points=%s asteroids=%d bolts=%d fps=%d" % [
		time, ctl.phase, str(ctl.scores), str(k), alive, str(owners), field.records.size(), projectiles.count(), Engine.get_frames_per_second()])
	get_tree().quit()
