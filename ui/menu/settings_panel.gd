extends "res://ui/menu/page.gd"
## Settings with tabs (Graphics, Controls, Audio, Gameplay). Uses console-
## style left/right selectors and sliders; every change applies instantly.

var _tabs: HBoxContainer
var _body: VBoxContainer
var _tab := 0
const TABS := ["GRAPHICS", "CONTROLS", "AUDIO", "GAMEPLAY"]


func _init() -> void:
	title_text = "SETTINGS"
	subtitle_text = "Changes apply instantly and sync to your pilot profile."


func build() -> void:
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	content.add_child(_tabs)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var panel := UI.panel(VBoxContainer.new(), 0.7)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	_body = panel.get_child(0)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	_show_tab(0)


func _show_tab(i: int) -> void:
	_tab = i
	for c in _tabs.get_children():
		c.queue_free()
	for t in TABS.size():
		var b := UI.button(TABS[t], _show_tab.bind(t), t == i)
		b.custom_minimum_size.x = 190
		_tabs.add_child(b)
	for c in _body.get_children():
		c.queue_free()
	match i:
		0:
			_selector("Quality preset", Settings.QUALITY_NAMES, "quality")
			_slider("Render resolution", "render_scale", 0.5, 1.0, 0.05, func(v): return "%d%%" % int(v * 100.0))
			_selector("Frame rate cap", ["30", "60", "90", "120", "UNLIMITED"], "fps_limit", Settings.FPS_OPTIONS)
			_slider("Field of view", "fov", 60.0, 95.0, 1.0, func(v): return "%d°" % int(v))
			_toggle("Show FPS counter", "show_fps")
			if not App.is_mobile:
				_selector("Display mode  (F11 / Alt+Enter)", Settings.WINDOW_MODE_NAMES, "window_mode", [0, 1, 2])
		1:
			_slider("Mouse sensitivity", "mouse_sens", 0.2, 3.0, 0.05, func(v): return "%.2f×" % v)
			if not App.is_mobile:
				_slider("Mouse aim deadzone", "mouse_deadzone", 0.0, 0.3, 0.01, func(v): return "%d%%" % int(v * 100.0))
				_toggle("Mouse aim returns to centre", "mouse_recenter")
			_slider("Touch sensitivity", "touch_sens", 0.3, 2.5, 0.05, func(v): return "%.2f×" % v)
			_toggle("Invert pitch", "invert_y")
			_toggle("Vibration", "haptics")
			_slider("Touch controls opacity", "touch_opacity", 0.2, 1.0, 0.05, func(v): return "%d%%" % int(v * 100.0))
			_slider("HUD scale", "hud_scale", 0.8, 1.4, 0.05, func(v): return "%d%%" % int(v * 100.0))
			_keys()
		2:
			_slider("Master volume", "vol_master", 0.0, 1.0, 0.01, _pct)
			_slider("Effects", "vol_sfx", 0.0, 1.0, 0.01, _pct)
			_slider("Music", "vol_music", 0.0, 1.0, 0.01, _pct)
			_slider("Interface", "vol_ui", 0.0, 1.0, 0.01, _pct)
		3:
			_toggle("Aim assist", "aim_assist")
			_slider("Camera shake", "camera_shake", 0.0, 1.5, 0.05, _pct)
			_selector("Bot difficulty", ["ROOKIE", "VETERAN", "ACE"], "bot_difficulty", [0, 1, 2])


func _pct(v: float) -> String:
	return "%d%%" % int(v * 100.0)


func _row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 64
	var l := UI.label(label_text, 22, App.TEXT, "body", 500)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	_body.add_child(row)
	var line := ColorRect.new()
	line.color = UI.LINE
	line.custom_minimum_size.y = 1
	_body.add_child(line)
	return row


func _selector(label_text: String, names: Array, key: String, values: Array = []) -> void:
	var row := _row(label_text)
	if values.is_empty():
		values = range(names.size())
	var idx := maxi(0, values.find(Settings.get_value(key)))
	var value_label := UI.label(names[idx], 22, Color.WHITE, "display_semi")
	value_label.custom_minimum_size.x = 200
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var step := func(d: int):
		var cur := maxi(0, values.find(Settings.get_value(key)))
		cur = (cur + d + values.size()) % values.size()
		Settings.set_value(key, values[cur])
		value_label.text = names[cur]
		Profile.push_cloud()
	var left := UI.button("‹", step.bind(-1))
	var right := UI.button("›", step.bind(1))
	left.custom_minimum_size = Vector2(56, 48)
	right.custom_minimum_size = Vector2(56, 48)
	row.add_child(left)
	row.add_child(value_label)
	row.add_child(right)


func _slider(label_text: String, key: String, lo: float, hi: float, stepv: float, fmt: Callable) -> void:
	var row := _row(label_text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = stepv
	s.value = float(Settings.get_value(key))
	s.custom_minimum_size = Vector2(320, 40)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := UI.label(fmt.call(s.value), 20, Color.WHITE, "display_semi")
	v.custom_minimum_size.x = 100
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(val):
		v.text = fmt.call(val)
		Settings.set_value(key, val, false))
	s.drag_ended.connect(func(_c):
		Settings.save()
		Profile.push_cloud())
	row.add_child(s)
	row.add_child(v)


func _toggle(label_text: String, key: String) -> void:
	var row := _row(label_text)
	var b := UI.button("ON" if Settings.get_value(key) else "OFF", func(): pass)
	b.custom_minimum_size = Vector2(140, 48)
	b.pressed.connect(func():
		Settings.set_value(key, not Settings.get_value(key))
		b.text = "ON" if Settings.get_value(key) else "OFF"
		Profile.push_cloud())
	row.add_child(b)


func _keys() -> void:
	var l := UI.label("Keyboard & mouse: mouse moves the aim reticle and the ship turns toward it · W/S throttle · A/D roll · Q/E strafe · Shift boost · LMB fire · RMB missiles · F target · C look back · X / middle mouse re-centre aim · F11 fullscreen · Tab scores", 17, App.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(UI.margin(l, 0, 14, 0, 4))
	var g := UI.label("Gamepad: left stick steers · right stick roll/throttle · RT fire · LT missiles · RB boost · LB target", 17, App.TEXT_DIM)
	g.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(g)
