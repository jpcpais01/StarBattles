extends Control
## Circular tactical radar in the ship's frame: forward is up, blips show
## height above/below with stems, objectives as lettered rings.

var arena: Arena
const RANGE := 1800.0
var _font: Font
var _sweep := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UI.font("display_semi")


func _process(delta: float) -> void:
	_sweep = fmod(_sweep + delta * 1.2, TAU)
	queue_redraw()


func _draw() -> void:
	var me := arena.local_ship if arena else null
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 2.0
	draw_circle(c, r, Color(0.02, 0.04, 0.08, 0.6))
	draw_arc(c, r, 0, TAU, 64, Color(1, 1, 1, 0.14), 1.5, true)
	draw_arc(c, r * 0.5, 0, TAU, 48, Color(1, 1, 1, 0.06), 1.0, true)
	draw_line(c + Vector2(0, -r), c + Vector2(0, r), Color(1, 1, 1, 0.05), 1.0)
	draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), Color(1, 1, 1, 0.05), 1.0)
	for i in 10:
		var a := _sweep - i * 0.05
		draw_line(c, c + Vector2(cos(a), sin(a)) * r, Color(App.ACCENT, 0.06 * (1.0 - i / 10.0)), 2.0, true)
	if me == null or not me.alive:
		return
	var inv := me.global_basis.inverse()
	for p in arena.points:
		var l := inv * (p.global_position - me.global_position)
		var v := Vector2(l.x, l.z) / RANGE * r
		if v.length() > r - 8.0:
			v = v.normalized() * (r - 8.0)
		var col := App.team_color(p.owner_team)
		draw_arc(c + v, 8.0, 0, TAU, 20, col, 1.5, true)
		var fs := 11
		draw_string(_font, c + v + Vector2(-3.5, 4), p.letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	for s in arena.ships:
		if s == me or not s.alive:
			continue
		var l := inv * (s.global_position - me.global_position)
		if l.length() > RANGE:
			continue
		var v := Vector2(l.x, l.z) / RANGE * r
		var h := clampf(l.y / RANGE * r, -r * 0.4, r * 0.4)
		var col := App.team_color(s.team)
		var p := c + v
		draw_line(p, p - Vector2(0, h), Color(col, 0.4), 1.0)
		if s.team != me.team:
			draw_rect(Rect2(p - Vector2(0, h) - Vector2(2.5, 2.5), Vector2(5, 5)), col)
		else:
			draw_circle(p - Vector2(0, h), 2.5, col)
	# Own ship glyph.
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(5, 5), c + Vector2(0, 2), c + Vector2(-5, 5)]), Color.WHITE)
