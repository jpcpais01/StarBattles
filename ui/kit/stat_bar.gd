extends Control
## Rounded horizontal meter that animates toward its value.

@export var value := 0.5
@export var color := Color(0.42, 0.82, 1.0)
@export var back := Color(1, 1, 1, 0.08)
var _shown := 0.0


func _process(delta: float) -> void:
	if absf(_shown - value) > 0.001:
		_shown = lerpf(_shown, value, 1.0 - exp(-delta * 8.0))
		queue_redraw()


func _draw() -> void:
	var r := size.y * 0.5
	var bb := StyleBoxFlat.new()
	bb.bg_color = back
	bb.set_corner_radius_all(int(r))
	draw_style_box(bb, Rect2(Vector2.ZERO, size))
	var w := maxf(size.y, size.x * clampf(_shown, 0.0, 1.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(r))
	draw_style_box(sb, Rect2(Vector2.ZERO, Vector2(w, size.y)))
