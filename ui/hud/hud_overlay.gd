extends Control
## Immediate-mode combat overlay: crosshair, gun convergence, hull/shield/
## boost arcs, target brackets with lead pip, missile lock ring, objective
## markers, off-screen threat arrows, hit markers and damage indicators.

var arena: Arena
var hud: Node
var _hit_t := 0.0
var _hit_kill := false
var _hit_shield := false
var _damage: Array = []  # [world_pos, time_left, shielded]
var _t := 0.0
var _font: Font
var _font_small: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = UI.font("display_semi")
	_font_small = UI.font("body", 600)


func hit_marker(kill: bool, shield: bool) -> void:
	_hit_t = 0.35 if not kill else 0.7
	_hit_kill = kill
	_hit_shield = shield


func damage_from(pos: Vector3, shield: bool) -> void:
	_damage.append([pos, 1.2, shield])
	if _damage.size() > 6:
		_damage.pop_front()


func _process(delta: float) -> void:
	_t += delta
	_hit_t = maxf(0.0, _hit_t - delta)
	for d in _damage:
		d[1] -= delta
	_damage = _damage.filter(func(d): return d[1] > 0.0)
	queue_redraw()


func _draw() -> void:
	if arena == null or size.y < 64.0:
		return
	var cam := arena.camera
	var me := arena.local_ship
	var center := size * 0.5
	var scale_f := float(Settings.get_value("hud_scale", 1.0)) * size.y / 1080.0
	_draw_points(cam, me, scale_f)
	if me == null or not me.alive:
		return
	_draw_ships(cam, me, scale_f)
	# Crosshair.
	var ch_col := Color(1, 1, 1, 0.85) if not me.primary_overheated() else App.BAD
	var r := 16.0 * scale_f
	for i in 4:
		var a := PI * 0.25 + i * PI * 0.5
		var dir := Vector2(cos(a), sin(a))
		draw_line(center + dir * r * 0.55, center + dir * r, ch_col, 2.0 * scale_f, true)
	draw_circle(center, 1.6 * scale_f, ch_col)
	# Gun convergence pip.
	if not cam.is_position_behind(me.aim_point):
		var ap := cam.unproject_position(me.aim_point)
		if ap.distance_to(center) > 3.0:
			_diamond(ap, 6.0 * scale_f, Color(App.ACCENT, 0.9), 1.5 * scale_f)
	# Mouse aim: the reticle marks where you're pointing; the ship's nose
	# (crosshair) swings onto it. Glows when aim assist is helping.
	if arena.input.mouse_aim_mode() and not arena.camera.look_back:
		var wp: Vector3 = arena.input.aim_world_point(me)
		if not cam.is_position_behind(wp):
			var rp := cam.unproject_position(wp)
			var aw: float = arena.input.assist_weight
			var rc := Color(1, 1, 1, 0.85).lerp(Color(App.ACCENT, 1.0), clampf(aw * 2.0, 0.0, 1.0))
			var rr := 11.0 * scale_f
			draw_arc(rp, rr, 0, TAU, 32, rc, 1.75 * scale_f, true)
			for i in 4:
				var dv := Vector2.from_angle(i * PI * 0.5)
				draw_line(rp + dv * rr * 0.45, rp + dv * rr * 0.8, rc, 1.5 * scale_f, true)
			var off := rp.distance_to(center)
			if off > r * 1.2:
				# A faint tether from nose to reticle shows which way you're turning.
				var dirv := (rp - center) / off
				draw_line(center + dirv * r * 1.1, rp - dirv * rr * 1.3, Color(rc, 0.18), 1.0 * scale_f, true)
	# Mouse virtual stick: a reticle that stays where you put it.
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var st: Vector2 = arena.input.mouse_stick()
		var dz: float = arena.input.mouse_deadzone()
		var sr := 150.0 * scale_f
		draw_arc(center, sr, 0, TAU, 64, Color(1, 1, 1, 0.05), 1.0, true)
		if dz > 0.01:
			draw_arc(center, sr * dz, 0, TAU, 24, Color(1, 1, 1, 0.08), 1.0, true)
		var mag := st.length()
		if mag > dz:
			var k := (mag - dz) / (1.0 - dz)
			var p := center + st * sr
			var col := Color(1, 1, 1, 0.75).lerp(Color(App.ACCENT, 0.95), k)
			draw_line(center + st.normalized() * sr * maxf(dz, 0.12), p, Color(col, 0.1 + 0.25 * k), 1.5 * scale_f, true)
			draw_arc(p, 7.0 * scale_f, 0, TAU, 20, col, 1.5 * scale_f, true)
			draw_circle(p, 1.5 * scale_f, col)
			# Light the rim in the turn direction; brightest when pinned at the edge.
			var a := st.angle()
			draw_arc(center, sr, a - 0.35, a + 0.35, 16, Color(col, 0.15 + 0.45 * k * k), 2.0 * scale_f, true)
		elif mag > 0.01:
			draw_arc(center + st * sr, 5.0 * scale_f, 0, TAU, 16, Color(1, 1, 1, 0.3), 1.0 * scale_f, true)
	# Hull (left) / shield (right) / boost (bottom) arcs.
	var ar := 92.0 * scale_f
	var w := 4.0 * scale_f
	_meter_arc(center, ar, PI * 0.78, PI * 1.22, me.hull / me.max_hull, App.GOOD if me.hull / me.max_hull > 0.35 else App.BAD, w, true)
	_meter_arc(center, ar, -PI * 0.22, PI * 0.22, me.shield / me.max_shield, Color(0.45, 0.8, 1.0), w, false)
	_meter_arc(center, ar + 10.0 * scale_f, PI * 0.36, PI * 0.64, me.boost_energy / float(me.def.boost_energy), App.WARN if me.boosting else Color(1, 1, 1, 0.6), w * 0.7, false)
	var heat := me.primary_heat()
	if heat > 0.02:
		_meter_arc(center, ar - 10.0 * scale_f, -PI * 0.64, -PI * 0.36, heat, App.BAD if me.primary_overheated() else Color(1.0, 0.6, 0.3), w * 0.7, false)
	var spd := "%d" % int(me.velocity.length())
	_text(center + Vector2(0, ar + 44.0 * scale_f), spd, 26.0 * scale_f, Color(1, 1, 1, 0.92), _font)
	_text(center + Vector2(0, ar + 64.0 * scale_f), "M/S", 12.0 * scale_f, Color(1, 1, 1, 0.45), _font)
	# Hit marker.
	if _hit_t > 0.0:
		var k := _hit_t / (0.7 if _hit_kill else 0.35)
		var hc := App.BAD if _hit_kill else (Color(0.6, 0.85, 1.0) if _hit_shield else Color.WHITE)
		var s := (10.0 + (1.0 - k) * 6.0) * scale_f
		for i in 4:
			var a := PI * 0.25 + i * PI * 0.5
			var dir := Vector2(cos(a), sin(a))
			draw_line(center + dir * s, center + dir * (s + 9.0 * scale_f), Color(hc, k), 2.5 * scale_f, true)
	# Damage direction.
	for d in _damage:
		var to: Vector3 = d[0] - me.global_position
		var local := cam.global_basis.inverse() * to
		var ang := atan2(local.x, local.y if absf(local.z) < 0.01 else -local.z)
		ang = atan2(local.x, -local.z) - PI * 0.5
		var a := clampf(float(d[1]) / 1.2, 0.0, 1.0)
		var col := Color(0.5, 0.8, 1.0, a) if d[2] else Color(1.0, 0.25, 0.2, a)
		draw_arc(center, 150.0 * scale_f, ang - 0.28, ang + 0.28, 16, col, 6.0 * scale_f, true)
	_draw_seekers(cam, me, center, ar, scale_f)
	# Incoming missiles.
	var incoming := 0
	for m in arena.missiles:
		if is_instance_valid(m) and m.target == me:
			incoming += 1
	if incoming > 0 and fmod(_t, 0.5) < 0.32:
		_text(center + Vector2(0, -ar - 50.0 * scale_f), "MISSILE INBOUND", 22.0 * scale_f, App.BAD, _font)
	if me.global_position.length() > Arena.BOUNDARY * 0.94 and fmod(_t, 0.8) < 0.55:
		_text(center + Vector2(0, -ar - 80.0 * scale_f), "LEAVING COMBAT ZONE", 22.0 * scale_f, App.WARN, _font)


func _meter_arc(c: Vector2, r: float, a0: float, a1: float, v: float, col: Color, w: float, reverse: bool) -> void:
	draw_arc(c, r, a0, a1, 24, Color(1, 1, 1, 0.1), w, true)
	v = clampf(v, 0.0, 1.0)
	if v <= 0.001:
		return
	if reverse:
		draw_arc(c, r, a1 - (a1 - a0) * v, a1, 24, col, w, true)
	else:
		draw_arc(c, r, a0, a0 + (a1 - a0) * v, 24, col, w, true)


func _diamond(p: Vector2, s: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0), p + Vector2(0, -s)])
	draw_polyline(pts, col, w, true)


func _text(p: Vector2, text: String, fs: float, col: Color, f: Font) -> void:
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, int(fs))
	draw_string(f, p - Vector2(sz.x * 0.5, -fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), col)


func _brackets(p: Vector2, s: float, col: Color, w: float) -> void:
	var l := s * 0.45
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var corner: Vector2 = p + c * s
		draw_line(corner, corner - Vector2(c.x * l, 0), col, w, true)
		draw_line(corner, corner - Vector2(0, c.y * l), col, w, true)


func _draw_ships(cam: Camera3D, me: Ship, scale_f: float) -> void:
	var center := size * 0.5
	var tgt = me.target
	for s in arena.ships:
		if s == me or not s.alive:
			continue
		var enemy := s.team != me.team
		var col := App.team_color(s.team)
		var dist := s.global_position.distance_to(me.global_position)
		var behind := cam.is_position_behind(s.global_position)
		var p := cam.unproject_position(s.global_position)
		var on_screen := not behind and Rect2(Vector2.ZERO, size).grow(-20).has_point(p)
		if not on_screen:
			if enemy and (dist < 1400.0 or s == tgt):
				_edge_arrow(cam, s.global_position, col, scale_f, s == tgt, "%dm" % int(dist) if s == tgt else "")
			continue
		var px := clampf(s.radius * 900.0 / maxf(dist, 1.0), 10.0, 60.0) * scale_f
		if enemy:
			if s == tgt:
				_brackets(p, px + 6.0 * scale_f, Color(col, 1.0), 2.0 * scale_f)
				if arena.input.manual_target == s:
					_text(Vector2(p.x, p.y - px - 18.0 * scale_f), "TARGET", 12.0 * scale_f, Color(col.lightened(0.35), 0.95), _font_small)
				# Shield/hull bars and range.
				var bw := 64.0 * scale_f
				var by := p.y + px + 16.0 * scale_f
				draw_rect(Rect2(p.x - bw * 0.5, by, bw, 3.0 * scale_f), Color(1, 1, 1, 0.15))
				draw_rect(Rect2(p.x - bw * 0.5, by, bw * s.shield / s.max_shield, 3.0 * scale_f), Color(0.5, 0.82, 1.0))
				draw_rect(Rect2(p.x - bw * 0.5, by + 5.0 * scale_f, bw, 3.0 * scale_f), Color(1, 1, 1, 0.15))
				draw_rect(Rect2(p.x - bw * 0.5, by + 5.0 * scale_f, bw * s.hull / s.max_hull, 3.0 * scale_f), col)
				_text(Vector2(p.x, by + 22.0 * scale_f), "%s  %dm" % [s.pilot_name.to_upper(), int(dist)], 14.0 * scale_f, Color(1, 1, 1, 0.85), _font_small)
				# Lead pip.
				var spd := ShipLibrary.primary_projectile_speed(me.def_id)
				if spd > 0.0:
					var lead := Arena.lead_point(me.global_position, me.velocity, s.global_position, s.velocity, spd)
					if not cam.is_position_behind(lead):
						var lp := cam.unproject_position(lead)
						draw_line(p, lp, Color(col, 0.35), 1.0, true)
						draw_arc(lp, 7.0 * scale_f, 0, TAU, 20, Color(1, 1, 1, 0.95), 2.0 * scale_f, true)
						draw_circle(lp, 2.0 * scale_f, col)
			else:
				var a := clampf(1.3 - dist / 1600.0, 0.35, 1.0)
				_brackets(p, px, Color(col, a), 1.5 * scale_f)
		else:
			var a := clampf(1.2 - dist / 1400.0, 0.25, 0.9)
			var tri := PackedVector2Array([p + Vector2(-6, -px - 10) * Vector2(scale_f, 1), p + Vector2(6 * scale_f, -px - 10), p + Vector2(0, -px - 2)])
			draw_colored_polygon(tri, Color(col, a))
			if dist < 500.0:
				_text(p + Vector2(0, -px - 22.0 * scale_f), s.pilot_name, 13.0 * scale_f, Color(col.lightened(0.3), a), _font_small)


func _edge_arrow(cam: Camera3D, world: Vector3, col: Color, scale_f: float, is_target: bool, label := "") -> void:
	var center := size * 0.5
	var local := cam.global_basis.inverse() * (world - cam.global_position)
	var dir := Vector2(local.x, -local.y)
	if dir.length() < 0.001:
		dir = Vector2(0, 1)
	dir = dir.normalized()
	var radius := Vector2(size.x * 0.42, size.y * 0.4)
	var p := center + dir * radius
	var ang := dir.angle()
	var s := (12.0 if is_target else 8.0) * scale_f
	var pts := PackedVector2Array([p + Vector2(s, 0).rotated(ang), p + Vector2(-s * 0.6, s * 0.7).rotated(ang), p + Vector2(-s * 0.6, -s * 0.7).rotated(ang)])
	draw_colored_polygon(pts, Color(col, 0.9 if is_target else 0.55))
	if is_target:
		draw_arc(p, s * 1.7, 0, TAU, 24, Color(col, 0.6 + 0.3 * sin(_t * 6.0)), 1.5 * scale_f, true)
		if label != "":
			_text(p - dir * 30.0 * scale_f, label, 13.0 * scale_f, Color(1, 1, 1, 0.8), _font_small)


func _draw_points(cam: Camera3D, me: Ship, scale_f: float) -> void:
	for pt in arena.points:
		var world := pt.global_position
		var col := App.team_color(pt.owner_team)
		var p: Vector2
		var behind := cam.is_position_behind(world)
		p = cam.unproject_position(world)
		var margin := 60.0 * scale_f
		var rect := Rect2(Vector2(margin, margin), size - Vector2(margin, margin) * 2.0)
		if behind or not rect.has_point(p):
			var local := cam.global_basis.inverse() * (world - cam.global_position)
			var dir := Vector2(local.x, -local.y).normalized()
			p = size * 0.5 + dir * Vector2(size.x * 0.45, size.y * 0.42)
			p = p.clamp(rect.position, rect.end)
		var r := 20.0 * scale_f
		draw_circle(p, r, Color(0.02, 0.04, 0.08, 0.55))
		draw_arc(p, r, 0, TAU, 40, Color(col, 0.9), 2.0 * scale_f, true)
		if pt.owner_team == -1 or pt.contested or absf(pt.progress) < 0.999:
			var cap_col := App.team_color(0 if pt.progress > 0.0 else 1)
			draw_arc(p, r + 4.0 * scale_f, -PI * 0.5, -PI * 0.5 + TAU * absf(pt.progress), 40, cap_col, 3.0 * scale_f, true)
		if pt.contested and fmod(_t, 0.6) < 0.3:
			draw_arc(p, r + 9.0 * scale_f, 0, TAU, 40, Color(App.WARN, 0.8), 1.5 * scale_f, true)
		_text(p, pt.letter, 22.0 * scale_f, Color.WHITE, _font)
		if me and me.alive:
			var d := int(me.global_position.distance_to(world))
			var inside := d < CapturePoint.RADIUS
			_text(p + Vector2(0, r + 14.0 * scale_f), "INSIDE" if inside else "%dm" % d, 12.0 * scale_f, Color(1, 1, 1, 0.65), _font_small)


## Seeker missiles: lock cone around the nose, lock ring + closing brackets on
## the target, and a status line under the speed readout.
func _draw_seekers(cam: Camera3D, me: Ship, center: Vector2, ar: float, scale_f: float) -> void:
	if not me.has_missiles():
		return
	var wdef := ShipLibrary.weapon("missile_pod")
	var lt = me.lock_target
	var has_lock: bool = lt != null and is_instance_valid(lt) and lt.alive
	var locked: bool = has_lock and me.lock_progress >= 1.0
	var ready := me.missile_ready()
	# Lock cone: keep the target inside this circle to build a lock.
	var cone_px := tan(deg_to_rad(float(wdef.lock_cone))) / tan(deg_to_rad(cam.fov * 0.5)) * size.y * 0.5
	var cone_col := Color(1, 1, 1, 0.07)
	if has_lock:
		cone_col = Color(App.BAD if locked else App.WARN, 0.22)
	for i in 4:
		var a0 := PI * 0.25 + i * PI * 0.5
		draw_arc(center, cone_px, a0 - 0.32, a0 + 0.32, 12, cone_col, 1.5 * scale_f, true)
	if has_lock:
		var wp: Vector3 = PlayerInput.target_pos(lt)
		if not cam.is_position_behind(wp):
			var lp := cam.unproject_position(wp)
			var lr := 34.0 * scale_f
			var lc := App.BAD if locked else App.WARN
			draw_arc(lp, lr, 0, TAU, 48, Color(lc, 0.15), 2.0 * scale_f, true)
			draw_arc(lp, lr, -PI * 0.5, -PI * 0.5 + TAU * me.lock_progress, 48, lc, 2.5 * scale_f, true)
			# Four ticks that close in as the lock completes.
			var tick := lerpf(lr * 2.2, lr * 1.15, me.lock_progress)
			for i in 4:
				var dv := Vector2.from_angle(PI * 0.25 + i * PI * 0.5 + (0.0 if locked else _t * 2.0))
				draw_line(lp + dv * tick, lp + dv * (tick + 9.0 * scale_f), lc, 2.0 * scale_f, true)
			if locked:
				var pulse := 0.75 + 0.25 * sin(_t * 10.0)
				_diamond(lp, lr * 0.55, Color(lc, pulse), 2.0 * scale_f)
				_text(lp + Vector2(0, -lr - 12.0 * scale_f), "LOCKED", 15.0 * scale_f, lc, _font)
	# Status line.
	var line := ""
	var col := Color(1, 1, 1, 0.55)
	if me.missile_event_t > 0.0 and me.missile_event > 0:
		match me.missile_event:
			1:
				line = "SEEKERS AWAY"
				col = App.BAD
			2:
				line = "DUMBFIRE  ·  NO LOCK"
				col = Color(1, 1, 1, 0.75)
			3:
				line = "SEEKERS RELOADING"
				col = App.WARN
	elif not ready:
		line = "SEEKERS  %d%%" % int(me.missile_reload_fraction() * 100.0)
		col = Color(1, 1, 1, 0.4)
	elif locked:
		line = "LOCKED  ·  " + ("MISSILE" if App.is_mobile else "RMB") + " TO FIRE"
		col = Color(App.BAD, 0.75 + 0.25 * sin(_t * 10.0))
	elif has_lock:
		line = "LOCKING  %d%%" % int(me.lock_progress * 100.0)
		col = App.WARN
	else:
		line = "SEEKERS READY"
		col = Color(1, 1, 1, 0.4)
	_text(center + Vector2(0, ar + 88.0 * scale_f), line, 14.0 * scale_f, col, _font)
