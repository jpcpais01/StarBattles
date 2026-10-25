class_name UI
## Shared UI kit: theme, typography and small factories so every screen
## shares the same glassy, high-contrast console look.

const FONT_BODY := preload("res://assets/fonts/inter-latin-wght-normal.woff2")
const FONT_DISPLAY := preload("res://assets/fonts/rajdhani-latin-700-normal.woff2")
const FONT_DISPLAY_SEMI := preload("res://assets/fonts/rajdhani-latin-600-normal.woff2")
const FONT_DISPLAY_MED := preload("res://assets/fonts/rajdhani-latin-500-normal.woff2")

const BG := Color(0.02, 0.03, 0.055)
const PANEL := Color(0.05, 0.07, 0.11, 0.78)
const PANEL_SOLID := Color(0.06, 0.08, 0.12, 0.96)
const LINE := Color(1, 1, 1, 0.09)

static var _theme: Theme
static var _fonts: Dictionary = {}


static func font(kind := "body", weight := 450) -> Font:
	var key := "%s_%d" % [kind, weight]
	if _fonts.has(key):
		return _fonts[key]
	var f: Font
	match kind:
		"display":
			f = FONT_DISPLAY
		"display_semi":
			f = FONT_DISPLAY_SEMI
		"display_med":
			f = FONT_DISPLAY_MED
		_:
			var fv := FontVariation.new()
			fv.base_font = FONT_BODY
			fv.variation_opentype = {"wght": weight}
			f = fv
	_fonts[key] = f
	return f


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("body", 450)
	t.default_font_size = 22
	t.set_color("font_color", "Label", App.TEXT)
	# Buttons.
	var normal := _box(Color(1, 1, 1, 0.055), 12, Color(1, 1, 1, 0.1), 1)
	var hover := _box(Color(1, 1, 1, 0.12), 12, Color(App.ACCENT, 0.55), 1)
	var pressed := _box(Color(App.ACCENT, 0.28), 12, Color(App.ACCENT, 0.9), 1)
	var focus := _box(Color(0, 0, 0, 0), 12, Color(App.ACCENT, 0.95), 2)
	focus.shadow_color = Color(App.ACCENT, 0.35)
	focus.shadow_size = 10
	var disabled := _box(Color(1, 1, 1, 0.03), 12, Color(1, 1, 1, 0.05), 1)
	for s in [normal, hover, pressed, disabled]:
		s.content_margin_left = 22
		s.content_margin_right = 22
		s.content_margin_top = 12
		s.content_margin_bottom = 12
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_color("font_color", "Button", App.TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	t.set_font("font", "Button", font("display_semi"))
	t.set_font_size("font_size", "Button", 24)
	# Panels.
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())
	# Text input.
	var le := _box(Color(1, 1, 1, 0.06), 10, Color(1, 1, 1, 0.14), 1)
	le.content_margin_left = 16
	le.content_margin_right = 16
	le.content_margin_top = 12
	le.content_margin_bottom = 12
	var le_focus := le.duplicate() as StyleBoxFlat
	le_focus.border_color = App.ACCENT
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le_focus)
	t.set_color("font_color", "LineEdit", App.TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.3))
	t.set_color("caret_color", "LineEdit", App.ACCENT)
	t.set_color("selection_color", "LineEdit", Color(App.ACCENT, 0.35))
	t.set_font_size("font_size", "LineEdit", 22)
	# Sliders.
	var track := _box(Color(1, 1, 1, 0.1), 4, Color(0, 0, 0, 0), 0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := _box(App.ACCENT, 4, Color(0, 0, 0, 0), 0)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _dot_texture(22, Color.WHITE))
	t.set_icon("grabber_highlight", "HSlider", _dot_texture(26, Color.WHITE))
	# Scrollbars: slim.
	var sb := _box(Color(1, 1, 1, 0.04), 4, Color(0, 0, 0, 0), 0)
	var grab := _box(Color(1, 1, 1, 0.22), 4, Color(0, 0, 0, 0), 0)
	t.set_stylebox("scroll", "VScrollBar", sb)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	# Rich text.
	t.set_font("normal_font", "RichTextLabel", font("body", 420))
	t.set_font("bold_font", "RichTextLabel", font("body", 700))
	t.set_font_size("normal_font_size", "RichTextLabel", 21)
	t.set_font_size("bold_font_size", "RichTextLabel", 21)
	t.set_color("default_color", "RichTextLabel", Color(0.85, 0.88, 0.95))
	_theme = t
	return t


static func _box(bg: Color, radius: int, border: Color, border_w: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_w)
	s.anti_aliasing = true
	s.corner_detail = 8
	return s


static func panel_box(alpha := 0.78, radius := 20) -> StyleBoxFlat:
	var s := _box(Color(PANEL, alpha), radius, LINE, 1)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 24
	s.content_margin_left = 28
	s.content_margin_right = 28
	s.content_margin_top = 24
	s.content_margin_bottom = 24
	return s


static func pill_box(color: Color, alpha := 0.18) -> StyleBoxFlat:
	var s := _box(Color(color, alpha), 999, Color(color, 0.5), 1)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


static func _dot_texture(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length()
			var a := clampf(c - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(color, a))
	return ImageTexture.create_from_image(img)


static func label(text: String, size := 22, color := App.TEXT, kind := "body", weight := 450) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind, weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func title(text: String, size := 56) -> Label:
	var l := label(text, size, App.TEXT, "display")
	return l


## Small caps label with generous tracking.
static func caption(text: String, size := 16, color := App.TEXT_DIM) -> Label:
	var l := label(spaced(text), size, color, "display_semi")
	return l


static func spaced(text: String) -> String:
	return " ".join(text.to_upper().split(""))


static func button(text: String, callback: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	if primary:
		var n := _box(App.ACCENT, 12, Color(1, 1, 1, 0.25), 1)
		n.content_margin_left = 30
		n.content_margin_right = 30
		n.content_margin_top = 14
		n.content_margin_bottom = 14
		var h := n.duplicate() as StyleBoxFlat
		h.bg_color = App.ACCENT.lightened(0.15)
		h.shadow_color = Color(App.ACCENT, 0.45)
		h.shadow_size = 16
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", h)
		b.add_theme_stylebox_override("pressed", h)
		b.add_theme_stylebox_override("hover_pressed", h)
		b.add_theme_color_override("font_color", Color(0.02, 0.05, 0.1))
		b.add_theme_color_override("font_hover_color", Color(0.02, 0.05, 0.1))
		b.add_theme_color_override("font_pressed_color", Color(0.02, 0.05, 0.1))
		b.add_theme_color_override("font_focus_color", Color(0.02, 0.05, 0.1))
	b.pressed.connect(func():
		Sfx.ui("ui_select", -2.0)
		callback.call())
	b.mouse_entered.connect(func():
		if not b.disabled:
			Sfx.ui("ui_move", -8.0))
	b.focus_entered.connect(func(): Sfx.ui("ui_move", -10.0))
	return b


static func hspacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func vspacer(h := 0.0) -> Control:
	var c := Control.new()
	if h > 0.0:
		c.custom_minimum_size.y = h
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func margin(child: Control, l := 0, t := 0, r := 0, b := 0) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	m.add_child(child)
	return m


static func panel(child: Control, alpha := 0.78) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_box(alpha))
	p.add_child(child)
	return p


static func pill(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", pill_box(color))
	var l := label(text, 15, color.lightened(0.3), "display_semi")
	p.add_child(l)
	return p


static func stat_bar(value: float, color := App.ACCENT) -> Control:
	var bar := preload("res://ui/kit/stat_bar.gd").new()
	bar.value = value
	bar.color = color
	bar.custom_minimum_size = Vector2(180, 8)
	return bar


static func fade_in(c: CanvasItem, time := 0.35, delay := 0.0, offset := Vector2(0, 18)) -> void:
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true)
	if c is Control and c.get_parent() is Container:
		# Containers own position; ease scale in from the centre instead.
		var ctrl := c as Control
		ctrl.resized.connect(func(): ctrl.pivot_offset = ctrl.size * 0.5, CONNECT_ONE_SHOT)
		ctrl.scale = Vector2.ONE * 0.97
		tw.tween_property(ctrl, "scale", Vector2.ONE, time).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	elif c is Control and offset != Vector2.ZERO:
		var ctrl := c as Control
		var target := ctrl.position
		ctrl.position = target + offset
		tw.tween_property(ctrl, "position", target, time).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, time).set_delay(delay)
