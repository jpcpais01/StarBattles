extends Control
## Siege markers drawn over the 3D view: shield generators and the reactor
## as objective diamonds with health rings (pinned to the screen edge when
## off-screen), brackets on nearby turrets, and a detailed readout for the
## part you have targeted. Defenders see the same systems as things to
## protect, with a warning flash on any that are under fire.

var arena: Arena
var _font: Font
var _font_small: Font
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = UI.font("display_semi")
	_font_small = UI.font("body", 600)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if arena == null or arena.siege == null or size.y < 64.0:
		return
	var sg := arena.siege
	if sg.stage == SiegeRules.Stage.DESTROYED:
		return
	var cam := arena.camera
	var me := arena.local_ship
	var scale_f := float(Settings.get_value("hud_scale", 1.0)) * size.y / 1080.0
	var attacking := me == null or me.team == SiegeRules.ATTACKERS
	var now := Time.get_ticks_msec()
	for p in sg.parts():
		if not p.alive:
			continue
		var world := p.aim_center()
		var objective := (p.kind == "generator" and sg.stage == SiegeRules.Stage.SHIELDS) or (p.kind == "core" and p.exposed)
		var targeted: bool = me != null and me.target == p
		if objective:
			var under_fire := not attacking and now - p.last_hit_ms < 1500
			_objective(cam, me, p, world, scale_f, attacking, under_fire)
		elif p.is_turret() and me and me.alive and attacking:
			var dist := world.distance_to(me.global_position)
			if dist > 2200.0 or cam.is_position_behind(world):
				continue
			var sp := cam.unproject_position(world)
			if not Rect2(Vector2.ZERO, size).has_point(sp):
				continue
			var px := clampf(p.radius * 1100.0 / maxf(dist, 1.0), 9.0, 46.0) * scale_f
			var col := Color(App.team_color(SiegeRules.DEFENDERS).lerp(App.BAD, 0.5), clampf(1.4 - dist / 2200.0, 0.3, 0.9))
			_brackets(sp, px, col, 1.5 * scale_f)
			if p.hp < p.max_hp:
				_bar(sp + Vector2(0, px + 8.0 * scale_f), 44.0 * scale_f, p.hp / p.max_hp, col, scale_f)
		if targeted and not cam.is_position_behind(world):
			_target_box(cam, me, p, world, scale_f)


func _objective(cam: Camera3D, me: Ship, p: MothershipPart, world: Vector3, scale_f: float, attacking: bool, under_fire: bool) -> void:
	var col := App.team_color(SiegeRules.DEFENDERS) if p.kind == "generator" else Color(1.0, 0.55, 0.25)
	var margin := 60.0 * scale_f
	var rect := Rect2(Vector2(margin, margin), size - Vector2(margin, margin) * 2.0)
	var behind := cam.is_position_behind(world)
	var sp := cam.unproject_position(world)
	var edge := behind or not rect.has_point(sp)
	if edge:
		var local := cam.global_basis.inverse() * (world - cam.global_position)
		var dir := Vector2(local.x, -local.y).normalized()
		sp = (size * 0.5 + dir * Vector2(size.x * 0.45, size.y * 0.42)).clamp(rect.position, rect.end)
	var r := (24.0 if p.kind == "core" else 18.0) * scale_f
	var pulse := 1.0 + 0.08 * sin(_t * 5.0)
	var pts := PackedVector2Array([sp + Vector2(0, -r) * pulse, sp + Vector2(r, 0) * pulse, sp + Vector2(0, r) * pulse, sp + Vector2(-r, 0) * pulse])
	draw_colored_polygon(pts, Color(0.02, 0.04, 0.08, 0.55))
	pts.append(pts[0])
	var flash := under_fire and fmod(_t, 0.4) < 0.2
	draw_polyline(pts, App.BAD if flash else Color(col, 0.95), 2.0 * scale_f, true)
	# Health ring.
	var k := p.hp / p.max_hp
	draw_arc(sp, r + 6.0 * scale_f, -PI * 0.5, -PI * 0.5 + TAU * k, 40, col.lightened(0.2), 3.0 * scale_f, true)
	var tag := "G" if p.kind == "generator" else "R"
	_text(sp, tag, 18.0 * scale_f, Color.WHITE, _font)
	var sub := ""
	if me and me.alive:
		sub = "%dm" % int(me.global_position.distance_to(world))
	var verb := ("ATTACK" if p.kind == "generator" else "DESTROY") if attacking else ("UNDER FIRE" if under_fire else "DEFEND")
	if not edge:
		_text(sp + Vector2(0, -r - 14.0 * scale_f), verb, 12.0 * scale_f, App.BAD if under_fire else Color(1, 1, 1, 0.75), _font)
	_text(sp + Vector2(0, r + 18.0 * scale_f), sub, 12.0 * scale_f, Color(1, 1, 1, 0.65), _font_small)


func _target_box(cam: Camera3D, me: Ship, p: MothershipPart, world: Vector3, scale_f: float) -> void:
	var sp := cam.unproject_position(world)
	var dist := world.distance_to(me.global_position)
	var px := clampf(p.radius * 1300.0 / maxf(dist, 1.0), 16.0, 70.0) * scale_f
	var col := Color(1.0, 0.85, 0.4)
	_brackets(sp, px + 6.0 * scale_f, col, 2.0 * scale_f)
	var by := sp.y + px + 16.0 * scale_f
	_bar(Vector2(sp.x, by), 80.0 * scale_f, p.hp / p.max_hp, col, scale_f)
	var status := "" if p.exposed else "  ·  ARMORED"
	_text(Vector2(sp.x, by + 18.0 * scale_f), "%s  %dm%s" % [p.label, int(dist), status], 14.0 * scale_f, Color(1, 1, 1, 0.85), _font_small)


func _bar(c: Vector2, w: float, k: float, col: Color, scale_f: float) -> void:
	draw_rect(Rect2(c.x - w * 0.5, c.y, w, 3.0 * scale_f), Color(1, 1, 1, 0.15))
	draw_rect(Rect2(c.x - w * 0.5, c.y, w * clampf(k, 0.0, 1.0), 3.0 * scale_f), col)


func _brackets(p: Vector2, s: float, col: Color, w: float) -> void:
	var l := s * 0.4
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var corner: Vector2 = p + c * s
		draw_line(corner, corner - Vector2(c.x * l, 0), col, w, true)
		draw_line(corner, corner - Vector2(0, c.y * l), col, w, true)


func _text(p: Vector2, text: String, fs: float, col: Color, f: Font) -> void:
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, int(fs))
	draw_string(f, p - Vector2(sz.x * 0.5, -fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), col)
