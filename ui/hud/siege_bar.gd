extends Control
## Top-centre status for Mothership Siege: the clock, the IRON VANGUARD's
## integrity as three stage segments (shield generators, armour, reactor),
## and the attackers' remaining reinforcements.

var arena: Arena
var _font: Font
var _font_big: Font
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UI.font("display_semi")
	_font_big = UI.font("display")
	custom_minimum_size = Vector2(760, 96)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if arena == null or arena.siege == null:
		return
	var sg := arena.siege
	var ctl := arena.ctl
	var s := size.y / 96.0
	var cx := size.x * 0.5
	var def_col := App.team_color(SiegeRules.DEFENDERS)
	var att_col := App.team_color(SiegeRules.ATTACKERS)
	var me_team := arena.local_ship.team if arena.local_ship else -1
	# Clock pill.
	var clock := App.format_time(ctl.time_left if ctl.phase != MatchController.Phase.WARMUP else ctl.phase_time)
	var pill := Rect2(cx - 62 * s, 4 * s, 124 * s, 40 * s)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.09, 0.8)
	sb.set_corner_radius_all(int(20 * s))
	sb.border_color = Color(1, 1, 1, 0.1)
	sb.set_border_width_all(1)
	draw_style_box(sb, pill)
	var low := ctl.phase == MatchController.Phase.LIVE and ctl.time_left < 60.0 and fmod(_t, 1.0) < 0.5
	_text(Vector2(cx, 24 * s), clock, int(28 * s), App.WARN if low else Color.WHITE, _font_big, 0)
	# Left: the carrier and what is happening to it.
	var lx := cx - 82 * s
	_text(Vector2(lx, 16 * s), Mothership.DISPLAY_NAME + ("  (DEFEND)" if me_team == SiegeRules.DEFENDERS else ""), int(17 * s), def_col.lightened(0.25), _font, -1)
	var status := ""
	match sg.stage:
		SiegeRules.Stage.SHIELDS:
			status = "SHIELDS UP  ·  %d GENERATOR%s" % [sg.generators_alive(), "" if sg.generators_alive() == 1 else "S"]
		SiegeRules.Stage.ARMOR:
			status = "SHIELDS DOWN  ·  ARMOR %d%%" % int(ceil(sg.armor_fraction() * 100.0))
		SiegeRules.Stage.REACTOR:
			var c := sg.core()
			status = "REACTOR EXPOSED  ·  %d%%" % int(ceil(c.hp / c.max_hp * 100.0)) if c else "REACTOR EXPOSED"
		SiegeRules.Stage.DESTROYED:
			status = "DESTROYED"
	var warn := sg.stage >= SiegeRules.Stage.REACTOR and fmod(_t, 0.8) < 0.45
	_text(Vector2(lx, 36 * s), status, int(14 * s), App.BAD if warn else Color(1, 1, 1, 0.7), _font, -1)
	# Right: attacker reinforcements.
	var rx := cx + 82 * s
	_text(Vector2(rx, 16 * s), App.TEAM_NAMES[SiegeRules.ATTACKERS] + ("  (ATTACK)" if me_team == SiegeRules.ATTACKERS else ""), int(17 * s), att_col.lightened(0.25), _font, 1)
	var tk_col := App.BAD if sg.tickets <= 10 else Color(1, 1, 1, 0.7)
	_text(Vector2(rx, 36 * s), "%d REINFORCEMENTS" % sg.tickets, int(14 * s), tk_col, _font, 1)
	# Integrity: three stage segments.
	var w := 600.0 * s
	var gap := 8.0 * s
	var seg := (w - gap * 2.0) / 3.0
	var y := 58 * s
	var h := 10 * s
	var fills := _stage_fills()
	for i in 3:
		var x0 := cx - w * 0.5 + i * (seg + gap)
		var r := Rect2(x0, y, seg, h)
		draw_rect(r, Color(1, 1, 1, 0.08))
		var f: float = fills[i]
		var col := def_col if i < 2 else Color(1.0, 0.55, 0.25)
		if i == int(sg.stage) and sg.stage != SiegeRules.Stage.DESTROYED:
			col = col.lerp(Color.WHITE, 0.25 + 0.2 * sin(_t * 6.0))
		if i == 0:
			# One cell per generator.
			var gens := []
			for p in sg.parts():
				if p.kind == "generator":
					gens.append(p)
			var cw := (seg - (gens.size() - 1) * 3.0 * s) / maxf(1.0, gens.size())
			for g in gens.size():
				var p: MothershipPart = gens[g]
				var gr := Rect2(x0 + g * (cw + 3.0 * s), y, cw * (p.hp / p.max_hp), h)
				draw_rect(gr, col)
		else:
			draw_rect(Rect2(x0, y, seg * f, h), col)
		var label: String = ["GENERATORS", "ARMOR", "REACTOR"][i]
		_text(Vector2(x0 + seg * 0.5, y + h + 12 * s), label, int(11 * s), Color(1, 1, 1, 0.55 if i == int(sg.stage) else 0.3), _font, 0)


func _stage_fills() -> Array:
	var sg := arena.siege
	var gens := 0.0
	var gens_max := 0.0
	for p in sg.parts():
		if p.kind == "generator":
			gens += p.hp
			gens_max += p.max_hp
	var c := sg.core()
	var core_f := c.hp / c.max_hp if c else 1.0
	return [gens / maxf(gens_max, 1.0), sg.armor_fraction(), core_f]


## align: -1 right-aligned at p, 0 centred, 1 left-aligned.
func _text(p: Vector2, text: String, fs: int, col: Color, f: Font, align: int) -> void:
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var x := p.x - sz.x * 0.5
	if align < 0:
		x = p.x - sz.x
	elif align > 0:
		x = p.x
	draw_string(f, Vector2(x, p.y + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
