class_name PlayerInput
extends Node
## Local pilot controls: mouse "virtual stick" + keyboard, gamepad, and the
## on-screen touch layout. Also does target selection and aim assist, which
## steers gimballed weapons onto the enemy's lead point.

var arena: Arena
var touch: Node  # TouchControls
var _stick := Vector2.ZERO
var throttle := 0.65
var _target_hold := 0.0
var manual_target: Ship = null
var aim_point_screen := Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := 0.0022 * float(Settings.get_value("mouse_sens", 1.0))
		var rel: Vector2 = event.relative * sens
		if Settings.get_value("invert_y", false):
			rel.y = -rel.y
		# The reticle stays wherever you leave it, like a joystick held over.
		_stick = (_stick + rel).limit_length(1.0)
	elif event.is_action_pressed("recenter_aim"):
		recenter_aim()
	elif event.is_action_pressed("target_next"):
		_cycle_target()


func mouse_stick() -> Vector2:
	return _stick


func mouse_deadzone() -> float:
	return clampf(float(Settings.get_value("mouse_deadzone", 0.05)), 0.0, 0.4)


func recenter_aim() -> void:
	_stick = Vector2.ZERO


func get_input(ship: Ship, delta: float) -> Dictionary:
	var inp := {}
	var pitch := 0.0
	var yaw := 0.0
	var roll := Input.get_axis("roll_left", "roll_right")
	var boost := Input.is_action_pressed("boost")
	var fire1 := Input.is_action_pressed("fire_primary")
	var fire2 := Input.is_action_pressed("fire_secondary")
	if App.is_mobile:
		# Touches are mirrored as mouse clicks; only trust the gamepad here.
		fire1 = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.5
		fire2 = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT) > 0.5
	# Mouse virtual stick: the ship keeps turning toward the reticle until you
	# bring it back inside the deadzone (or press X / middle mouse).
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := _stick
		var dz := mouse_deadzone()
		if s.length() > dz:
			var k := (s.length() - dz) / (1.0 - dz)
			s = s.normalized() * (k * k * 0.5 + k * 0.5)
			yaw += s.x
			pitch -= s.y
		if Settings.get_value("mouse_recenter", false):
			_stick = _stick.move_toward(Vector2.ZERO, delta * 0.8)
	# Gamepad / keys.
	pitch += Input.get_axis("pitch_down", "pitch_up") * (-1.0 if Settings.get_value("invert_y", false) else 1.0)
	yaw += Input.get_axis("yaw_left", "yaw_right")
	var thr_axis := Input.get_axis("throttle_down", "throttle_up")
	throttle = clampf(throttle + thr_axis * delta * 0.8, 0.0, 1.0)
	var strafe := Input.get_axis("strafe_left", "strafe_right")
	if touch and touch.visible:
		var t: Dictionary = touch.state()
		var sens := float(Settings.get_value("touch_sens", 1.0))
		yaw += t.stick.x * sens
		pitch -= t.stick.y * sens * (-1.0 if Settings.get_value("invert_y", false) else 1.0)
		# Auto-bank into turns on touch so steering stays one-thumb.
		roll += t.stick.x * 0.55
		boost = boost or t.boost
		fire1 = fire1 or t.fire1
		fire2 = fire2 or t.fire2
		if t.throttle_active:
			throttle = t.throttle
	inp.pitch = clampf(pitch, -1.0, 1.0)
	inp.yaw = clampf(yaw, -1.0, 1.0)
	inp.roll = clampf(roll, -1.0, 1.0)
	inp.throttle = throttle
	inp.boost = boost
	inp.fire1 = fire1
	inp.fire2 = fire2
	inp.strafe = strafe
	var tgt: Node3D = _pick_target(ship)
	if tgt == null and arena.siege:
		tgt = arena.siege.pick_part_target(ship)
	inp.target = tgt
	inp.aim = _aim_point(ship, tgt)
	return inp


func _pick_target(ship: Ship) -> Ship:
	if manual_target and manual_target.alive and manual_target.global_position.distance_to(ship.global_position) < 2500.0:
		return manual_target
	manual_target = null
	var fwd := -ship.global_basis.z
	var best: Ship = null
	var best_score := -INF
	for s in arena.ships:
		if s.team == ship.team or not s.alive:
			continue
		var to := s.global_position - ship.global_position
		var dist := to.length()
		if dist > 2200.0:
			continue
		var dot := fwd.dot(to / dist)
		if dot < 0.6:
			continue
		var score := dot * 3.0 - dist / 1500.0
		if score > best_score:
			best_score = score
			best = s
	return best


func _cycle_target() -> void:
	var me := arena.local_ship
	if me == null:
		return
	var enemies := arena.ships.filter(func(s): return s.alive and s.team != me.team)
	if enemies.is_empty():
		return
	enemies.sort_custom(func(a, b): return a.global_position.distance_to(me.global_position) < b.global_position.distance_to(me.global_position))
	var idx := enemies.find(manual_target)
	manual_target = enemies[(idx + 1) % enemies.size()]
	Sfx.ui("ui_move", -6.0)


## Weapons converge ahead of the nose; with aim assist they snap to the
## target's lead point when it is close to the crosshair.
func _aim_point(ship: Ship, tgt) -> Vector3:
	var fwd := -ship.global_basis.z
	var aim := ship.global_position + fwd * 700.0
	if tgt and Settings.get_value("aim_assist", true):
		var tpos: Vector3 = tgt.aim_center() if tgt is MothershipPart else tgt.global_position
		var lead := Arena.lead_point(ship.global_position, ship.velocity, tpos, tgt.velocity,
			ShipLibrary.primary_projectile_speed(ship.def_id))
		var to := (lead - ship.global_position)
		var cone := 0.985 if not App.is_mobile else 0.965
		if fwd.dot(to.normalized()) > cone and to.length() < 1400.0:
			aim = lead
	return aim
