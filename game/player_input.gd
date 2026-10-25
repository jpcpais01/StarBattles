class_name PlayerInput
extends Node
## Local pilot controls: mouse aim (or a mouse "virtual stick"), keyboard,
## gamepad and the on-screen touch layout. Also does target selection and a
## light aim assist that pulls toward an enemy's lead point and adds a touch of
## friction there, so tracking a target feels steady rather than twitchy.

## Mouse steering styles (Settings "mouse_steer").
const STEER_AIM := 0    # point the reticle, the ship flies to it
const STEER_STICK := 1  # the reticle is a joystick: distance from centre = turn rate

const MAX_AIM_ANGLE := deg_to_rad(52.0)
const MOUSE_AIM_RAD_PER_PX := 0.0011
const MOUSE_STICK_PER_PX := 0.0019
const ASSIST_RANGE := 1500.0
const TARGET_RANGE := 3000.0

var arena: Arena
var touch: Node  # TouchControls
var _stick := Vector2.ZERO
var throttle := 0.65
var manual_target = null  # Ship or MothershipPart picked with F / T / LB
var _auto_target = null
var _last_cycle_ms := -100000
var aim_point_screen := Vector2.ZERO

## Mouse aim: where the pilot wants the nose, in world space.
var aim_dir := Vector3.FORWARD
var _aim_ship: Ship = null
## Aim assist state, also read by the HUD.
var assist_target: Ship = null
var assist_weight := 0.0
var _friction := 1.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.relative * float(Settings.get_value("mouse_sens", 1.0)) * _friction
		if Settings.get_value("invert_y", false):
			rel.y = -rel.y
		if mouse_aim_mode():
			_turn_aim(rel * MOUSE_AIM_RAD_PER_PX)
		else:
			# The reticle stays wherever you leave it, like a joystick held over.
			_stick = (_stick + rel * MOUSE_STICK_PER_PX).limit_length(1.0)
	elif event.is_action_pressed("recenter_aim"):
		recenter_aim()
	elif event.is_action_pressed("target_next"):
		cycle_target()


func mouse_aim_mode() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and int(Settings.get_value("mouse_steer", STEER_AIM)) == STEER_AIM


func mouse_stick() -> Vector2:
	return _stick


func mouse_deadzone() -> float:
	return clampf(float(Settings.get_value("mouse_deadzone", 0.03)), 0.0, 0.4)


func recenter_aim() -> void:
	_stick = Vector2.ZERO
	var me := arena.local_ship if arena else null
	if me:
		aim_dir = -me.global_basis.z
		_aim_ship = me


## Stick shaping shared by touch, gamepad-style mouse stick and the deadzone:
## mostly linear so small motions still turn the ship, with a little expo
## (Settings "aim_expo") for fine control right around the centre.
static func shape(v: Vector2, deadzone: float) -> Vector2:
	var m := v.length()
	if m <= deadzone or m < 0.0001:
		return Vector2.ZERO
	var k := minf(1.0, (m - deadzone) / maxf(0.001, 1.0 - deadzone))
	var expo := clampf(float(Settings.get_value("aim_expo", 0.25)), 0.0, 0.9)
	return v / m * lerpf(k, k * k * k, expo)


func _turn_aim(rad: Vector2) -> void:
	var me := arena.local_ship if arena else null
	if me == null or not me.alive or arena.camera.look_back:
		return
	_sync_aim(me)
	var cb := arena.camera.global_basis
	aim_dir = aim_dir.rotated(cb.y.normalized(), -rad.x)
	aim_dir = aim_dir.rotated(cb.x.normalized(), -rad.y).normalized()
	_clamp_aim(me)


func _sync_aim(me: Ship) -> void:
	if _aim_ship != me:
		_aim_ship = me
		aim_dir = -me.global_basis.z


func _clamp_aim(me: Ship) -> void:
	var fwd := -me.global_basis.z
	var ang := fwd.angle_to(aim_dir)
	if ang > MAX_AIM_ANGLE:
		aim_dir = fwd.slerp(aim_dir, MAX_AIM_ANGLE / ang).normalized()


## Mouse-aim reticle in world space (HUD).
func aim_world_point(me: Ship) -> Vector3:
	return me.global_position + aim_dir * 900.0


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
	var fwd := -ship.global_basis.z
	var assist_amt := clampf(float(Settings.get_value("aim_assist_amt", 0.5)), 0.0, 1.0)
	var mouse_aim := mouse_aim_mode()
	# --- Aim assist: find the enemy lead point nearest where we're aiming. ---
	var aim_ref := fwd
	if mouse_aim:
		_sync_aim(ship)
		aim_ref = aim_dir
	var lead_dir := Vector3.ZERO
	assist_target = null
	var w := 0.0
	if assist_amt > 0.0:
		var cone := deg_to_rad(4.5 if not (App.is_mobile or (touch and touch.visible)) else 7.0)
		var spd := ShipLibrary.primary_projectile_speed(ship.def_id)
		for s in arena.ships:
			if s.team == ship.team or not s.alive:
				continue
			var d := s.global_position.distance_to(ship.global_position)
			if d > ASSIST_RANGE:
				continue
			var lead := Arena.lead_point(ship.global_position, ship.velocity, s.global_position, s.velocity, spd) if spd > 0.0 else s.global_position
			var ld := (lead - ship.global_position).normalized()
			var ang := aim_ref.angle_to(ld)
			if ang < cone:
				var ww := 1.0 - smoothstep(cone * 0.25, cone, ang)
				if ww > w:
					w = ww
					lead_dir = ld
					assist_target = s
	assist_weight = move_toward(assist_weight, w * assist_amt, delta * 4.0)
	_friction = 1.0 - 0.4 * assist_weight
	# --- Mouse. ---
	if mouse_aim:
		# A gentle tug toward the lead point while the reticle is close to it.
		if assist_target:
			aim_dir = aim_dir.slerp(lead_dir, minf(1.0, delta * 2.2 * assist_weight)).normalized()
		_clamp_aim(ship)
		var steer := _steer_to(ship, aim_dir)
		yaw += steer.x
		pitch += steer.y
		# Bank a little into the turn so it reads like flying, not sliding.
		if absf(roll) < 0.01:
			var local := ship.global_basis.inverse() * aim_dir
			roll += clampf(atan2(local.x, -local.z) * 0.9, -0.3, 0.3)
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Virtual stick: the ship keeps turning toward the reticle until you
		# bring it back inside the deadzone (or press X / middle mouse).
		var s := shape(_stick, mouse_deadzone())
		yaw += s.x * _friction
		pitch -= s.y * _friction
		if Settings.get_value("mouse_recenter", false):
			_stick = _stick.move_toward(Vector2.ZERO, delta * 0.8)
	# Gamepad / keys.
	var pad := Vector2(Input.get_axis("yaw_left", "yaw_right"), Input.get_axis("pitch_down", "pitch_up"))
	pad = shape(pad, 0.0)
	pitch += pad.y * (-1.0 if Settings.get_value("invert_y", false) else 1.0) * _friction
	yaw += pad.x * _friction
	var thr_axis := Input.get_axis("throttle_down", "throttle_up")
	throttle = clampf(throttle + thr_axis * delta * 0.8, 0.0, 1.0)
	var strafe := Input.get_axis("strafe_left", "strafe_right")
	if touch and touch.visible:
		var t: Dictionary = touch.state()
		var sens := float(Settings.get_value("touch_sens", 1.0))
		var st := shape(t.stick, 0.04)
		yaw += st.x * sens * _friction
		pitch -= st.y * sens * _friction * (-1.0 if Settings.get_value("invert_y", false) else 1.0)
		# Auto-bank into turns on touch so steering stays one-thumb.
		roll += st.x * 0.5
		boost = boost or t.boost
		fire1 = fire1 or t.fire1
		fire2 = fire2 or t.fire2
		if t.throttle_active:
			throttle = t.throttle
		if t.get("target_pressed", false):
			cycle_target()
	# Stick / touch / pad magnetism: a small steering nudge onto the lead point.
	if not mouse_aim and assist_target:
		var nudge := _steer_to(ship, lead_dir) * 0.3 * assist_weight
		yaw += clampf(nudge.x, -0.15, 0.15)
		pitch += clampf(nudge.y, -0.15, 0.15)
	inp.pitch = clampf(pitch, -1.0, 1.0)
	inp.yaw = clampf(yaw, -1.0, 1.0)
	inp.roll = clampf(roll, -1.0, 1.0)
	inp.throttle = throttle
	inp.boost = boost
	inp.fire1 = fire1
	inp.fire2 = fire2
	inp.strafe = strafe
	var tgt = _pick_target(ship)
	if tgt == null and arena.siege:
		tgt = arena.siege.pick_part_target(ship)
	inp.target = tgt
	inp.target_manual = tgt != null and tgt == manual_target
	inp.aim = _aim_point(ship, tgt)
	return inp


## Pitch/yaw commands that swing the nose onto `dir`: proportional on the
## angle error with a little rate damping, tuned per hull so heavy ships
## don't overshoot and light ones still feel snappy.
func _steer_to(ship: Ship, dir: Vector3) -> Vector2:
	var local := ship.global_basis.inverse() * dir
	var yaw_err := atan2(local.x, -local.z)
	var pitch_err := atan2(local.y, Vector2(local.x, local.z).length())
	var kp := clampf(float(ship.def.agility) * 0.65, 2.2, 4.2)
	var y := (yaw_err - ship.rates.y * 0.13) * kp / float(ship.def.yaw_rate)
	var p := (pitch_err - ship.rates.x * 0.13) * kp / float(ship.def.pitch_rate)
	return Vector2(clampf(y, -1.0, 1.0), clampf(p, -1.0, 1.0))


static func target_pos(t) -> Vector3:
	return t.aim_center() if t is MothershipPart else t.global_position


func _valid(t, ship: Ship, max_dist: float) -> bool:
	return t != null and is_instance_valid(t) and t.alive and t.team != ship.team \
		and target_pos(t).distance_to(ship.global_position) < max_dist


func _pick_target(ship: Ship):
	if _valid(manual_target, ship, TARGET_RANGE):
		return manual_target
	manual_target = null
	var fwd := -ship.global_basis.z
	var best = null
	var best_score := -INF
	var cur_score := -INF
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
		if s == _auto_target:
			cur_score = score
		if score > best_score:
			best_score = score
			best = s
	# Hysteresis: don't flick between two similar candidates every frame.
	if cur_score > -INF and best_score - cur_score < 0.25:
		best = _auto_target
	_auto_target = best
	return best


## F / T / LB / touch TARGET: grab the enemy closest to where you're aiming;
## press again within a couple of seconds to step to the next one out.
func cycle_target() -> void:
	var me := arena.local_ship
	if me == null or not me.alive:
		return
	var ref := aim_dir if mouse_aim_mode() else -arena.camera.global_basis.z
	var list: Array = []
	for t in arena.lock_candidates(me.team):
		if _valid(t, me, TARGET_RANGE):
			list.append([ref.angle_to((target_pos(t) - me.global_position).normalized()), t])
	if list.is_empty():
		manual_target = null
		Sfx.ui("ui_back", -8.0)
		return
	list.sort_custom(func(a, b): return a[0] < b[0])
	var now := Time.get_ticks_msec()
	var idx := 0
	var cur := -1
	for i in list.size():
		if list[i][1] == manual_target:
			cur = i
	if cur >= 0 and (now - _last_cycle_ms < 2500 or cur == 0):
		idx = (cur + 1) % list.size()
	_last_cycle_ms = now
	manual_target = list[idx][1]
	Sfx.ui("ui_move", -6.0)


## Weapons converge ahead of the nose; with aim assist they snap to the
## target's lead point when it is close to the crosshair.
func _aim_point(ship: Ship, tgt) -> Vector3:
	var fwd := -ship.global_basis.z
	var aim := ship.global_position + fwd * 700.0
	if tgt and float(Settings.get_value("aim_assist_amt", 0.5)) > 0.0:
		var tpos: Vector3 = target_pos(tgt)
		var lead := Arena.lead_point(ship.global_position, ship.velocity, tpos, tgt.velocity,
			ShipLibrary.primary_projectile_speed(ship.def_id))
		var to := (lead - ship.global_position)
		var cone := 0.985 if not App.is_mobile else 0.965
		if fwd.dot(to.normalized()) > cone and to.length() < 1400.0:
			aim = lead
	return aim
