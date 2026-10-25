extends Button
## Console-style home tile: shader backdrop with animated sheen and rim,
## a vector glyph, and a label. Grows and glows when focused.

const SH := preload("res://shaders/tile_bg.gdshader")

var icon_kind := "battle"
var caption_text := ""
var tint := App.ACCENT
var base_size := Vector2(210, 210)
var focus_size := Vector2(250, 250)
var _focus := 0.0
var _target := 0.0
var _bg: ColorRect
var _mat: ShaderMaterial
var _label: Label
var _glyph: Control


func _ready() -> void:
	flat = true
	text = ""
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = base_size
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
		add_theme_stylebox_override(s, empty)
	_mat = ShaderMaterial.new()
	_mat.shader = SH
	_mat.set_shader_parameter("color_a", tint.darkened(0.45))
	_mat.set_shader_parameter("color_b", Color(0.02, 0.035, 0.07))
	_mat.set_shader_parameter("rim", tint)
	_bg = ColorRect.new()
	_bg.material = _mat
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_glyph = Control.new()
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glyph.draw.connect(_draw_glyph)
	add_child(_glyph)
	_label = UI.label(caption_text, 19, App.TEXT, "display_semi")
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.offset_top = -46
	_label.offset_bottom = -16
	add_child(_label)
	focus_entered.connect(func(): _target = 1.0)
	focus_exited.connect(func(): _target = 0.0)
	mouse_entered.connect(func():
		if not has_focus():
			grab_focus())
	pivot_offset = base_size * 0.5


func _process(delta: float) -> void:
	var f := _focus
	_focus = move_toward(_focus, _target, delta * 6.0)
	var e := ease(_focus, -2.0)
	custom_minimum_size = base_size.lerp(focus_size, e)
	_mat.set_shader_parameter("focus", e)
	_mat.set_shader_parameter("rect_size", size)
	_label.add_theme_color_override("font_color", App.TEXT_DIM.lerp(Color.WHITE, e))
	if f != _focus or e > 0.0:
		_glyph.queue_redraw()


func _draw_glyph() -> void:
	var g := _glyph
	var e := ease(_focus, -2.0)
	var c := Vector2(size.x * 0.5, size.y * 0.42)
	var s := minf(size.x, size.y) * (0.2 + 0.02 * e)
	var col := Color(1, 1, 1, 0.75 + 0.25 * e)
	var acc := tint.lerp(Color.WHITE, 0.25)
	var w := 3.0
	match icon_kind:
		"battle":
			g.draw_arc(c, s, 0.0, TAU, 48, col, w, true)
			g.draw_arc(c, s * 0.45, 0.0, TAU, 32, acc, w, true)
			for a in 4:
				var d := Vector2.RIGHT.rotated(a * PI * 0.5)
				g.draw_line(c + d * s * 0.7, c + d * s * 1.3, col, w, true)
			g.draw_circle(c, 3.5, acc)
		"multi":
			for i in 2:
				var o := c + Vector2((i - 0.5) * s * 1.05, 0.0)
				var cc := col if i == 0 else acc
				g.draw_circle(o + Vector2(0, -s * 0.45), s * 0.28, cc)
				g.draw_arc(o + Vector2(0, s * 0.62), s * 0.62, PI, TAU, 24, cc, w + 1.0, true)
		"hangar":
			var pts := PackedVector2Array([c + Vector2(0, -s * 1.15), c + Vector2(s * 0.95, s * 0.75),
				c + Vector2(0, s * 0.35), c + Vector2(-s * 0.95, s * 0.75), c + Vector2(0, -s * 1.15)])
			g.draw_polyline(pts, col, w, true)
			g.draw_line(c + Vector2(0, -s * 0.5), c + Vector2(0, s * 0.2), acc, w, true)
			g.draw_circle(c + Vector2(-s * 0.35, s * 0.9), 4.0, acc)
			g.draw_circle(c + Vector2(s * 0.35, s * 0.9), 4.0, acc)
		"pilot":
			g.draw_arc(c, s * 1.1, 0.0, TAU, 48, Color(col, 0.35), w, true)
			g.draw_arc(c, s * 1.1, -PI * 0.5, -PI * 0.5 + TAU * Profile.level_progress(), 48, acc, w + 1.0, true)
			g.draw_circle(c + Vector2(0, -s * 0.28), s * 0.32, col)
			g.draw_arc(c + Vector2(0, s * 0.62), s * 0.55, PI * 1.1, PI * 1.9, 24, col, w + 2.0, true)
		"notes":
			var r := Rect2(c - Vector2(s * 0.8, s), Vector2(s * 1.6, s * 2.0))
			g.draw_rect(r, col, false, w)
			for i in 4:
				var y := r.position.y + s * 0.45 + i * s * 0.4
				g.draw_line(Vector2(r.position.x + s * 0.3, y), Vector2(r.end.x - s * (0.3 + 0.35 * float(i == 3)), y), acc if i == 0 else col, w, true)
		"settings":
			var teeth := 8
			var pts := PackedVector2Array()
			for i in teeth * 4 + 1:
				var a := float(i) / float(teeth * 4) * TAU
				var r := s * (1.0 if (i % 4) < 2 else 0.78)
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			g.draw_polyline(pts, col, w, true)
			g.draw_arc(c, s * 0.36, 0.0, TAU, 32, acc, w, true)
		"update":
			g.draw_arc(c, s, 0.0, TAU, 48, col, w, true)
			g.draw_line(c + Vector2(0, -s * 0.55), c + Vector2(0, s * 0.4), acc, w + 1.0, true)
			g.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.4, s * 0.02), c + Vector2(0, s * 0.45), c + Vector2(s * 0.4, s * 0.02)]), acc, w + 1.0, true)
