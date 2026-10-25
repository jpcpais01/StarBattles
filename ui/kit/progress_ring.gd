extends Control
## Large circular progress gauge with a glowing head, used by the update
## download screen. `value` is 0..1; set `indeterminate` while waiting.

var value := 0.0
var indeterminate := false
var color := App.ACCENT
var thickness := 10.0
var _shown := 0.0
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	_shown = lerpf(_shown, value, 1.0 - exp(-delta * 8.0))
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - thickness * 2.0
	draw_arc(c, r, 0.0, TAU, 96, Color(1, 1, 1, 0.07), thickness, true)
	draw_arc(c, r + thickness * 1.4, 0.0, TAU, 96, Color(1, 1, 1, 0.04), 1.0, true)
	# Tick marks.
	for i in 60:
		var a := float(i) / 60.0 * TAU - PI * 0.5
		var on := float(i) / 60.0 <= _shown
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * (r - thickness * 1.6), c + d * (r - thickness * 1.6 - (6.0 if i % 5 == 0 else 3.0)),
			Color(color, 0.8) if on else Color(1, 1, 1, 0.12), 2.0, true)
	var start := -PI * 0.5
	var sweep := TAU * _shown
	if indeterminate:
		start = _t * 4.0
		sweep = 1.0 + sin(_t * 2.0) * 0.6
	if sweep > 0.001:
		draw_arc(c, r, start, start + sweep, 96, Color(color, 0.25), thickness * 2.2, true)
		draw_arc(c, r, start, start + sweep, 96, color, thickness, true)
		var head := c + Vector2(cos(start + sweep), sin(start + sweep)) * r
		draw_circle(head, thickness * 1.2, Color(color, 0.35))
		draw_circle(head, thickness * 0.6, Color.WHITE)
