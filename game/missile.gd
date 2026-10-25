class_name Missile
extends Node3D
## Seeker missile: boosts off the rail, then homes with lead pursuit and a
## limited turn rate, so hard manoeuvres can shake it. Smoke trail, hot
## exhaust and proximity fuse. Flown on every peer; damage is server-side.

var shooter_id := -1
var team := 0
var target = null  # Ship or MothershipPart
var wdef: Dictionary
var dir := Vector3.FORWARD
var speed := 120.0
var life := 0.0
var arena: Arena
var _trail: Trail3D
var _flame: MeshInstance3D
var _done := false

## Match-wide tallies for the autotest report: launched, homing, fused on a target.
static var stats := {"fired": 0, "homing": 0, "hits": 0}


func setup(a: Arena, shooter: int, t: int, origin: Vector3, direction: Vector3, tgt: Node3D, inherit: float) -> void:
	arena = a
	shooter_id = shooter
	team = t
	target = tgt
	wdef = ShipLibrary.weapon("missile_pod")
	dir = direction.normalized()
	speed = 90.0 + inherit
	life = wdef.life
	global_position = origin
	stats.fired += 1
	if tgt:
		stats.homing += 1
	if App.is_dedicated:
		return
	var k := MeshKit.new()
	k.cylinder(Vector3(0, 0, 0.6), Vector3(0, 0, -0.5), 0.12, 0.12, 6, MeshKit.HULL)
	k.cylinder(Vector3(0, 0, -0.5), Vector3(0, 0, -0.85), 0.12, 0.0, 6, MeshKit.PAINT)
	var body := MeshInstance3D.new()
	body.mesh = k.commit()
	body.material_override = Mats.hull(team, Color(1.0, 0.6, 0.3))
	add_child(body)
	_flame = MeshInstance3D.new()
	_flame.mesh = Mats.quad()
	_flame.material_override = Mats.glow(Color(1.0, 0.65, 0.3), 5.0, 2.0)
	_flame.position = Vector3(0, 0, 0.7)
	_flame.scale = Vector3.ONE * 1.6
	add_child(_flame)
	_trail = Trail3D.new()
	_trail.source = self
	_trail.width = 1.4
	_trail.lifetime = 1.6
	_trail.max_points = 40
	_trail.min_step = 3.0
	_trail.width_curve = -1.5
	_trail.color = Color(1, 1, 1, 0.9)
	_trail.material_override = Mats.smoke()
	add_child(_trail)
	look_at(global_position + dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)


func _physics_process(delta: float) -> void:
	if _done:
		return
	life -= delta
	if life <= 0.0:
		_detonate(global_position, null)
		return
	speed = move_toward(speed, float(wdef.speed), delta * 260.0)
	if target and is_instance_valid(target) and target.alive and life < float(wdef.life) - 0.25:
		var aim: Vector3 = target.aim_center() if target is MothershipPart else target.global_position
		var to := aim - global_position
		var t_hit := to.length() / maxf(speed, 1.0)
		var lead: Vector3 = aim + target.velocity * minf(t_hit, 1.5)
		var desired := (lead - global_position).normalized()
		var max_turn: float = float(wdef.turn) * delta
		var ang := dir.angle_to(desired)
		if ang > 0.0001:
			dir = dir.slerp(desired, minf(1.0, max_turn / ang)).normalized()
		if to.length() < (9.0 if target is Ship else 20.0):
			_detonate(global_position, target)
			return
	var from := global_position
	var to_pos := from + dir * speed * delta
	var exclude := []
	var shooter := arena.ship_by_id(shooter_id)
	if shooter:
		exclude.append(shooter.hit_area.get_rid())
	var hit := arena.raycast(from, to_pos, exclude)
	if not hit.is_empty():
		var col: Object = hit.collider
		var friendly := (col.has_meta("ship") and (col.get_meta("ship") as Ship).team == team) \
			or (col.has_meta("mteam") and int(col.get_meta("mteam")) == team)
		if not friendly:
			_detonate(hit.position, col.get_meta("ship") if col.has_meta("ship") else null, col)
			return
	global_position = to_pos
	if dir.length_squared() > 0.5:
		look_at(global_position + dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	if _flame:
		_flame.set_instance_shader_parameter("intensity", 0.8 + randf() * 0.4)


func _detonate(pos: Vector3, direct: Node3D, collider: Object = null) -> void:
	_done = true
	if direct:
		stats.hits += 1
	FX.explosion(arena, pos, 4.5, Color(1.0, 0.55, 0.25), false)
	if multiplayer.is_server():
		arena.ctl.server_splash(pos, float(wdef.splash), float(wdef.damage), wdef, shooter_id, team, direct)
		if arena.siege:
			arena.siege.splash(pos, float(wdef.splash), float(wdef.damage), wdef, shooter_id, team, collider)
		if collider and collider.has_meta("asteroid"):
			arena.field.damage(int(collider.get_meta("asteroid")), float(wdef.damage) * 1.5, pos, dir)
	arena.missiles.erase(self)
	if _trail:
		# Let the smoke linger after the missile is gone.
		_trail.emitting = false
		remove_child(_trail)
		arena.fx_root.add_child(_trail)
		_trail.get_tree().create_timer(_trail.lifetime + 0.1).timeout.connect(_trail.queue_free)
	queue_free()
