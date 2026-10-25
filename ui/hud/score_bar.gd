extends Control
## Top-centre match status: team scores racing toward the limit, objective
## chips with capture progress, and the match clock.

var arena: Arena
var _font: Font
var _font_big: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UI.font("display_semi")
	_font_big = UI.font("display")
	custom_minimum_size = Vector2(760, 96)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if arena == null:
		return
	var ctl := arena.ctl
	var s := size.y / 96.0
	var cx := size.x * 0.5
	var me_team := arena.local_ship.team if arena.local_ship else 0
	# Clock pill.
	var clock := App.format_time(ctl.time_left if ctl.phase != MatchController.Phase.WARMUP else ctl.phase_time)
	var pill := Rect2(cx - 62 * s, 4 * s, 124 * s, 40 * s)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.09, 0.8)
	sb.set_corner_radius_all(int(20 * s))
	sb.border_color = Color(1, 1, 1, 0.1)
	sb.set_border_width_all(1)
	draw_style_box(sb, pill)
	_center_text(Vector2(cx, 24 * s), clock, int(28 * s), Color.WHITE, _font_big)
	# Team score bars.
	for t in 2:
		var dir := -1.0 if t == 0 else 1.0
		var col := App.team_color(t)
		var x0 := cx + dir * 78 * s
		var w := 250.0 * s
		var y := 14 * s
		var bar := Rect2(x0 if dir > 0 else x0 - w, y + 6 * s, w, 8 * s)
		draw_rect(bar, Color(1, 1, 1, 0.08))
		var frac := clampf(float(ctl.scores[t]) / MatchController.SCORE_LIMIT, 0.0, 1.0)
		var fill := Rect2(bar.position.x if dir > 0 else bar.end.x - w * frac, bar.position.y, w * frac, bar.size.y)
		draw_rect(fill, col)
		var label := "%s%s" % [App.TEAM_NAMES[t], "  (YOU)" if t == me_team and arena.local_ship else ""]
		var lx := x0 + dir * 4 * s
		_side_text(Vector2(lx, y + 34 * s), label, int(15 * s), Color(col.lightened(0.25), 0.9), dir)
		_side_text(Vector2(x0 + dir * (w + 12 * s), y + 16 * s), "%d" % int(ctl.scores[t]), int(34 * s), Color.WHITE, dir, _font_big)
	# Objective chips.
	var n := arena.points.size()
	for i in n:
		var p: CapturePoint = arena.points[i]
		var px := cx + (i - (n - 1) * 0.5) * 46 * s
		var py := 70 * s
		var col := App.team_color(p.owner_team)
		draw_circle(Vector2(px, py), 16 * s, Color(col, 0.22))
		draw_arc(Vector2(px, py), 16 * s, 0, TAU, 32, col, 2 * s, true)
		if absf(p.progress) < 0.999 or p.owner_team == -1:
			draw_arc(Vector2(px, py), 20 * s, -PI * 0.5, -PI * 0.5 + TAU * absf(p.progress), 32, App.team_color(0 if p.progress > 0 else 1), 2.5 * s, true)
		_center_text(Vector2(px, py), p.letter, int(18 * s), Color.WHITE, _font)


func _center_text(p: Vector2, text: String, fs: int, col: Color, f: Font = null) -> void:
	f = f if f else _font
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(f, p + Vector2(-sz.x * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _side_text(p: Vector2, text: String, fs: int, col: Color, dir: float, f: Font = null) -> void:
	f = f if f else _font
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var x := p.x if dir > 0 else p.x - sz.x
	draw_string(f, Vector2(x, p.y + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
