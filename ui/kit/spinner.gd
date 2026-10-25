extends Control
## Minimal arc spinner drawn with _draw so it keeps animating while the
## main thread is mostly idle during threaded loads.

@export var color := Color(0.42, 0.82, 1.0)
@export var thickness := 3.0
var _t := 0.0


func _process(delta: float) -> void:
	if modulate.a <= 0.01 or not is_visible_in_tree():
		return
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - thickness
	draw_arc(c, r, 0.0, TAU, 64, Color(color, 0.12), thickness, true)
	var start := _t * 5.0
	var sweep := 1.2 + sin(_t * 2.4) * 0.8
	draw_arc(c, r, start, start + sweep, 32, color, thickness, true)
