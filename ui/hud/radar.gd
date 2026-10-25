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
	if arena.siege and not arena.siege.mothership.destroyed:
		_draw_mothership(me, inv, c, r)
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


## Siege: the carrier's footprint and its objectives, clipped to the scope.
func _draw_mothership(me: Ship, inv: Basis, c: Vector2, r: float) -> void:
	var m := arena.siege.mothership
	var e := m.half_extents
	var col := App.team_color(SiegeRules.DEFENDERS)
	var pts := PackedVector2Array()
	for corner in [Vector3(-e.x, 0, -e.z * 0.85), Vector3(0, 0, -e.z), Vector3(e.x, 0, -e.z * 0.85), Vector3(e.x, 0, e.z), Vector3(-e.x, 0, e.z)]:
		var l: Vector3 = inv * (m.global_transform * (corner as Vector3) - me.global_position)
		pts.append(c + Vector2(l.x, l.z) / RANGE * r)
	# Clip to the scope; seen edge-on (or from far off) nothing may be left.
	var scope := PackedVector2Array()
	for i in 32:
		scope.append(c + Vector2.from_angle(i * TAU / 32.0) * (r - 2.0))
	if absf(_area(pts)) < 1.0:
		pts = PackedVector2Array()
	for poly in (Geometry2D.intersect_polygons(pts, scope) if not pts.is_empty() else []):
		if absf(_area(poly)) < 1.0:
			continue
		draw_colored_polygon(poly, Color(col, 0.18))
		var outline: PackedVector2Array = poly.duplicate()
		outline.append(poly[0])
		draw_polyline(outline, Color(col, 0.6), 1.5, true)
	for p in arena.siege.parts():
		if not p.alive or not (p.kind == "generator" or (p.kind == "core" and p.exposed)):
			continue
		var l := inv * (p.aim_center() - me.global_position)
		var v := Vector2(l.x, l.z) / RANGE * r
		if v.length() > r - 6.0:
			v = v.normalized() * (r - 6.0)
		var q := c + v
		var k := 4.5 if p.kind == "generator" else 6.0
		var pc := col.lightened(0.4) if p.kind == "generator" else Color(1.0, 0.55, 0.25)
		draw_colored_polygon(PackedVector2Array([q + Vector2(0, -k), q + Vector2(k, 0), q + Vector2(0, k), q + Vector2(-k, 0)]), pc)


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return a * 0.5
