extends Control
## Touch layout: a floating flight stick anywhere on the left half, fire /
## missile / boost buttons on the right, and a vertical throttle strip on
## the right edge. Multi-touch aware; draws its own glass widgets.

var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _buttons: Dictionary = {}  # name -> {center, radius, id}
var _throttle_id := -1
var throttle := 0.65
var throttle_active := false
var _target_pressed := false
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UI.font("display_semi")
	for n in ["fire1", "fire2", "boost", "target"]:
		_buttons[n] = {"center": Vector2.ZERO, "radius": 0.0, "id": -1}
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	var s := size.y / 1080.0 * float(Settings.get_value("hud_scale", 1.0))
	var br := Vector2(size.x - 250 * s, size.y - 230 * s)
	_buttons.fire1.center = br
	_buttons.fire1.radius = 105 * s
	_buttons.fire2.center = br + Vector2(-210 * s, 40 * s)
	_buttons.fire2.radius = 70 * s
	_buttons.boost.center = br + Vector2(-60 * s, -200 * s)
	_buttons.boost.radius = 66 * s
	_buttons.target.center = br + Vector2(-250 * s, -150 * s)
	_buttons.target.radius = 50 * s


func _throttle_rect() -> Rect2:
	var s := size.y / 1080.0
	return Rect2(size.x - 70 * s, size.y * 0.2, 46 * s, size.y * 0.32)


func state() -> Dictionary:
	var stick := Vector2.ZERO
	if _stick_id >= 0:
		var s := size.y / 1080.0
		stick = (_stick_pos - _stick_origin) / (120.0 * s)
		if stick.length() > 1.0:
			stick = stick.normalized()
	# Response shaping (deadzone + curve) happens in PlayerInput.shape().
	var tp := _target_pressed
	_target_pressed = false
	return {"stick": stick, "fire1": _buttons.fire1.id >= 0, "fire2": _buttons.fire2.id >= 0,
		"boost": _buttons.boost.id >= 0, "throttle": throttle, "throttle_active": throttle_active,
		"target_pressed": tp}


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index)
	elif event is InputEventScreenDrag:
		if event.index == _stick_id:
			_stick_pos = event.position
		elif event.index == _throttle_id:
			_set_throttle(event.position)


func _press(id: int, p: Vector2) -> void:
	if _throttle_rect().grow(30).has_point(p):
		_throttle_id = id
		throttle_active = true
		_set_throttle(p)
		return
	for n in _buttons.keys():
		var b: Dictionary = _buttons[n]
		if p.distance_to(b.center) < b.radius * 1.15:
			b.id = id
			if n == "target":
				_target_pressed = true
			Settings.vibrate(12)
			return
	if p.x < size.x * 0.5 and _stick_id < 0:
		_stick_id = id
		_stick_origin = p
		_stick_pos = p


func _release(id: int) -> void:
	if id == _stick_id:
		_stick_id = -1
	if id == _throttle_id:
		_throttle_id = -1
	for n in _buttons.keys():
		if _buttons[n].id == id:
			_buttons[n].id = -1


func _set_throttle(p: Vector2) -> void:
	var r := _throttle_rect()
	throttle = clampf(1.0 - (p.y - r.position.y) / r.size.y, 0.0, 1.0)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var a := float(Settings.get_value("touch_opacity", 0.8))
	var s := size.y / 1080.0
	if _stick_id >= 0:
		draw_circle(_stick_origin, 120 * s, Color(1, 1, 1, 0.06 * a))
		draw_arc(_stick_origin, 120 * s, 0, TAU, 48, Color(1, 1, 1, 0.25 * a), 2.0 * s, true)
		var knob := _stick_origin + (_stick_pos - _stick_origin).limit_length(120 * s)
		draw_circle(knob, 46 * s, Color(1, 1, 1, 0.3 * a))
	else:
		var hint := Vector2(260 * s, size.y - 260 * s)
		draw_arc(hint, 110 * s, 0, TAU, 48, Color(1, 1, 1, 0.08 * a), 2.0 * s, true)
		_label(hint, "STEER", 18 * s, Color(1, 1, 1, 0.25 * a))
	var names := {"fire1": "FIRE", "fire2": "MISSILE", "boost": "BOOST", "target": "TARGET"}
	var cols := {"fire1": App.BAD, "fire2": App.WARN, "boost": App.ACCENT, "target": Color(0.75, 0.85, 1.0)}
	# The missile button shows the seeker lock filling up.
	var me: Ship = Arena.current.local_ship if Arena.current else null
	if me and me.alive and me.has_missiles():
		var fb2: Dictionary = _buttons.fire2
		if me.lock_target and me.lock_progress > 0.0:
			var locked := me.lock_progress >= 1.0
			var lc := App.BAD if locked else App.WARN
			draw_arc(fb2.center, fb2.radius + 9 * s, -PI * 0.5, -PI * 0.5 + TAU * me.lock_progress, 48, Color(lc, 0.9 * a), 5.0 * s, true)
			names.fire2 = "LOCKED" if locked else "LOCKING"
		if not me.missile_ready():
			names.fire2 = "%d%%" % int(me.missile_reload_fraction() * 100.0)
	for n in _buttons.keys():
		var b: Dictionary = _buttons[n]
		var down: bool = b.id >= 0
		var col: Color = cols[n]
		draw_circle(b.center, b.radius, Color(col, (0.35 if down else 0.14) * a))
		draw_arc(b.center, b.radius, 0, TAU, 56, Color(col, 0.75 * a), 2.5 * s, true)
		_label(b.center, names[n], 22 * s if n == "fire1" else 17 * s, Color(1, 1, 1, 0.9 * a))
	var r := _throttle_rect()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.07 * a)
	sb.set_corner_radius_all(int(r.size.x * 0.5))
	sb.border_color = Color(1, 1, 1, 0.2 * a)
	sb.set_border_width_all(2)
	draw_style_box(sb, r)
	var fill := Rect2(r.position.x, r.end.y - r.size.y * throttle, r.size.x, r.size.y * throttle)
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(App.ACCENT, 0.35 * a)
	fb.set_corner_radius_all(int(r.size.x * 0.5))
	draw_style_box(fb, fill)
	_label(Vector2(r.get_center().x, r.position.y - 20 * s), "THR", 15 * s, Color(1, 1, 1, 0.5 * a))


func _label(p: Vector2, text: String, fs: float, col: Color) -> void:
	var sz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs))
	draw_string(_font, p - Vector2(sz.x * 0.5, -fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), col)
