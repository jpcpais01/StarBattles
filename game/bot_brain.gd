class_name BotBrain
extends RefCounted
## AI pilot. Picks between capturing objectives and dogfighting, flies with
## bank-to-turn steering and asteroid avoidance, leads its shots with skill-
## dependent error, jinks when under fire and fires missiles on lock.

enum Mode { CAPTURE, ATTACK, EVADE }

var arena: Arena
var skill := 0.5
var mode := Mode.CAPTURE
var objective: CapturePoint
var enemy: Ship
var _think := 0.0
var _jink := Vector2.ZERO
var _jink_t := 0.0
var _evade_t := 0.0
var _last_hull := 0.0
var _orbit_sign := 1.0
var _aim_err := Vector3.ZERO
var _personality := randf()


func _init(a: Arena, s: float) -> void:
	arena = a
	skill = s
	_orbit_sign = 1.0 if randf() > 0.5 else -1.0


func get_input(ship: Ship, delta: float) -> Dictionary:
	_think -= delta
	if _think <= 0.0:
		_think = randf_range(0.35, 0.7)
		_decide(ship)
	if ship.hull < _last_hull - 1.0 and randf() < 0.6 * delta * 10.0:
		_evade_t = randf_range(0.8, 1.6) * (1.2 - skill * 0.4)
	_last_hull = ship.hull
	var inp := {"throttle": 0.8, "boost": false, "fire1": false, "fire2": false, "roll": 0.0, "strafe": 0.0}
	var dest := ship.global_position - ship.global_basis.z * 200.0
	var aim := ship.global_position - ship.global_basis.z * 700.0
	match mode:
		Mode.CAPTURE:
			if objective:
				var c := objective.global_position
				var to := c - ship.global_position
				if to.length() < CapturePoint.RADIUS * 0.8:
					# Circle inside the zone instead of overshooting it.
					var side := to.cross(Vector3.UP).normalized() * _orbit_sign
					dest = c + side * CapturePoint.RADIUS * 0.5 + Vector3.UP * sin(Time.get_ticks_msec() * 0.0005 + _personality * 10.0) * 40.0
					inp.throttle = 0.45
				else:
					dest = c
					inp.boost = to.length() > 900.0 and ship.boost_energy > 40.0
		Mode.ATTACK:
			if enemy and enemy.alive:
				var proj_speed := ShipLibrary.primary_projectile_speed(ship.def_id)
				if proj_speed <= 0.0:
					proj_speed = 3000.0
				var lead := Arena.lead_point(ship.global_position, ship.velocity, enemy.global_position, enemy.velocity, proj_speed)
				var dist := ship.global_position.distance_to(enemy.global_position)
				# Aim error shrinks with skill and wanders slowly.
				_aim_err = _aim_err.lerp(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (1.0 - skill) * 22.0, delta * 2.0)
				aim = lead + _aim_err
				dest = lead
				if dist < 120.0:
					# Too close: break off past them.
					dest = ship.global_position - ship.global_basis.z * 300.0 + ship.global_basis.x * 200.0 * _orbit_sign
					inp.throttle = 1.0
				elif dist > 700.0:
					inp.throttle = 1.0
					inp.boost = dist > 1100.0 and ship.boost_energy > 30.0
				else:
					inp.throttle = clampf(0.55 + (dist - 300.0) / 800.0, 0.35, 1.0)
				var to_aim := (aim - ship.global_position).normalized()
				var dot := (-ship.global_basis.z).dot(to_aim)
				var max_range := 1150.0
				for m in ship.mounts:
					if m.group == 0:
						max_range = minf(max_range, float(m.wdef.range))
				inp.fire1 = dot > 0.992 - (1.0 - skill) * 0.01 and dist < max_range and not ship.primary_overheated()
				inp.fire2 = ship.lock_progress >= 1.0 and ship.missile_ready() and randf() < delta * 2.0
				inp.target = enemy
	if _evade_t > 0.0:
		_evade_t -= delta
		_jink_t -= delta
		if _jink_t <= 0.0:
			_jink_t = randf_range(0.25, 0.5)
			_jink = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
		inp.boost = ship.boost_energy > 20.0
		inp.throttle = 1.0
	dest = _avoid(ship, dest)
	_steer(ship, dest, inp)
	if _evade_t > 0.0:
		inp.yaw = clampf(inp.yaw + _jink.x * 0.8, -1, 1)
		inp.pitch = clampf(inp.pitch + _jink.y * 0.8, -1, 1)
	inp.aim = aim
	return inp


func _decide(ship: Ship) -> void:
	# Closest threatening enemy.
	enemy = null
	var best := INF
	for s in arena.ships:
		if s.team == ship.team or not s.alive:
			continue
		var d := s.global_position.distance_to(ship.global_position)
		var facing := (-ship.global_basis.z).dot((s.global_position - ship.global_position).normalized())
		var score := d - facing * 250.0
		if score < best:
			best = score
			enemy = s
	# Best objective: not owned, closest, prefer contested ones.
	objective = null
	var best_obj := INF
	for p in arena.points:
		var d := p.global_position.distance_to(ship.global_position)
		var want := 0.0 if p.owner_team != ship.team else 900.0
		if p.contested:
			want -= 300.0
		want += d
		if want < best_obj:
			best_obj = want
			objective = p
	var enemy_dist := best if enemy else INF
	var aggression := 650.0 + _personality * 500.0 + skill * 200.0
	if enemy and (enemy_dist < aggression or objective == null or (objective.owner_team == ship.team and not objective.contested)):
		mode = Mode.ATTACK
	else:
		mode = Mode.CAPTURE


## Deflects the destination around asteroids on the flight path.
func _avoid(ship: Ship, dest: Vector3) -> Vector3:
	var fwd := ship.velocity.normalized() if ship.velocity.length() > 5.0 else -ship.global_basis.z
	var look := clampf(ship.velocity.length() * 2.2, 120.0, 500.0)
	var hit := arena.field.probe(ship.global_position, fwd, look, ship.radius + 12.0)
	if hit.is_empty():
		var d := ship.global_position.length()
		if d > Arena.BOUNDARY * 0.92:
			return Vector3.ZERO
		return dest
	var c: Vector3 = hit.center
	var away := (ship.global_position + fwd * float(hit.t)) - c
	if away.length() < 0.1:
		away = ship.global_basis.y
	away = away.normalized()
	return c + away * (float(hit.radius) + ship.radius + 80.0) + fwd * 60.0


## Bank-to-turn: roll the target into the pitch plane, then pull.
func _steer(ship: Ship, dest: Vector3, inp: Dictionary) -> void:
	var local := ship.global_basis.inverse() * (dest - ship.global_position)
	var dir := local.normalized()
	var behind := dir.z > 0.0
	var yaw := clampf(dir.x * 3.0, -1.0, 1.0)
	var pitch := clampf(dir.y * 3.0, -1.0, 1.0)
	if behind:
		pitch = 1.0 if dir.y >= 0.0 else -1.0
		yaw = signf(dir.x) * 0.6
	var roll_err := atan2(dir.x, maxf(0.1, dir.y))
	var roll := 0.0
	if absf(dir.x) > 0.15 and Vector2(dir.x, dir.y).length() > 0.25:
		roll = clampf(roll_err * 1.2, -1.0, 1.0)
	else:
		# Level out gently relative to the arena's "up" when cruising.
		roll = clampf(-ship.global_basis.x.dot(Vector3.UP) * 1.5, -0.5, 0.5)
	var finesse := 0.75 + skill * 0.25
	inp.yaw = yaw * finesse
	inp.pitch = pitch * finesse
	inp.roll = roll * 0.8
