extends Control
## Base for full-screen menu pages: dimmed backdrop, header with back
## button and title, a content column, slide-in/out transitions.

signal closed

var title_text := ""
var subtitle_text := ""
var content: VBoxContainer
var header: HBoxContainer
var compact := false
## Backdrop dim; pages that show off the 3D scene use less.
var shade_alpha := 0.62
var _closing := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.01, 0.015, 0.03, 0.82 if compact else shade_alpha)
	add_child(shade)
	var wrap := MarginContainer.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := 90 if not App.is_mobile else 48
	wrap.add_theme_constant_override("margin_left", m)
	wrap.add_theme_constant_override("margin_right", m)
	wrap.add_theme_constant_override("margin_top", 56)
	wrap.add_theme_constant_override("margin_bottom", 48)
	add_child(wrap)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 24)
	wrap.add_child(col)
	header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 22)
	col.add_child(header)
	var back := UI.button("‹  BACK", close)
	back.custom_minimum_size = Vector2(150, 56)
	header.add_child(back)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.add_child(UI.title(title_text, 54))
	if subtitle_text != "":
		tv.add_child(UI.label(subtitle_text, 19, App.TEXT_DIM))
	header.add_child(tv)
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 18)
	col.add_child(content)
	build()
	modulate.a = 0.0
	position.x = 60
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.25)
	tw.tween_property(self, "position:x", 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	back.grab_focus.call_deferred()


## Override to fill `content`.
func build() -> void:
	pass


func close() -> void:
	if _closing:
		return
	_closing = true
	Sfx.ui("ui_back", -4.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_property(self, "position:x", 40.0, 0.2)
	tw.chain().tween_callback(func():
		closed.emit()
		queue_free())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		close()
	if OS.has_feature("android") and event is InputEventKey and event.pressed and event.keycode == KEY_BACK:
		get_viewport().set_input_as_handled()
		close()


func section(text: String) -> Label:
	var l := UI.caption(text, 16)
	content.add_child(l)
	return l
