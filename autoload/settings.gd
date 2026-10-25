extends Node
## Player settings: persisted to user://settings.cfg, applied to the
## viewport/engine, and broadcast so live scenes can react (shadows, glow…).
## Also owns the input map so bindings live in one readable place.

signal changed(key: String)

const PATH := "user://settings.cfg"
const QUALITY_NAMES := ["LOW", "MEDIUM", "HIGH", "ULTRA"]
const FPS_OPTIONS := [30, 60, 90, 120, 0]
const WINDOW_MODE_NAMES := ["WINDOWED", "FULLSCREEN", "EXCLUSIVE"]

var data := {
	"quality": 2,
	"render_scale": 1.0,
	"fps_limit": 0,
	"show_fps": false,
	"vol_master": 0.9,
	"vol_sfx": 0.85,
	"vol_music": 0.55,
	"vol_ui": 0.7,
	"window_mode": 0,
	"mouse_sens": 1.0,
	"mouse_deadzone": 0.05,
	"mouse_recenter": false,
	"touch_sens": 1.0,
	"invert_y": false,
	"aim_assist": true,
	"haptics": true,
	"camera_shake": 1.0,
	"fov": 72.0,
	"hud_scale": 1.0,
	"touch_opacity": 0.8,
	"bot_difficulty": 1,
	"last_fullscreen": 1,
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("mobile"):
		data.quality = 1
		data.render_scale = 0.85
		data.fps_limit = 60
		data.hud_scale = 1.15
	else:
		data.window_mode = 1  # Desktop starts in borderless fullscreen.
	_load()
	_setup_input()
	apply.call_deferred()


func get_value(key: String, default: Variant = null) -> Variant:
	return data.get(key, default)


func set_value(key: String, value: Variant, save_now := true) -> void:
	data[key] = value
	if key == "window_mode" and int(value) != 0:
		data.last_fullscreen = int(value)
	apply()
	changed.emit(key)
	if save_now:
		save()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key in data.keys():
		if cfg.has_section_key("settings", key):
			data[key] = cfg.get_value("settings", key)


func save() -> void:
	var cfg := ConfigFile.new()
	for key in data.keys():
		cfg.set_value("settings", key, data[key])
	cfg.save(PATH)


func to_dict() -> Dictionary:
	return data.duplicate()


func from_dict(d: Dictionary) -> void:
	for key in d.keys():
		if data.has(key):
			data[key] = d[key]
	apply()
	save()
	changed.emit("*")


func quality() -> int:
	return int(data.quality)


func apply() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var q := quality()
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_2X, Viewport.MSAA_4X][q]
	var scale := clampf(float(data.render_scale), 0.5, 1.0)
	vp.scaling_3d_scale = scale
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.mesh_lod_threshold = [4.0, 2.0, 1.0, 1.0][q]
	Engine.max_fps = int(data.fps_limit)
	var shadow_size: int = [1024, 2048, 4096, 4096][q]
	RenderingServer.directional_shadow_atlas_set_size(shadow_size, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][q])
	_apply_window()
	_apply_audio()


## Desktop only: 0 windowed, 1 borderless fullscreen, 2 exclusive fullscreen.
## Only touches the window when the mode actually differs, so other settings
## changes don't flicker or resize it.
func _apply_window() -> void:
	if OS.has_feature("mobile") or DisplayServer.get_name() == "headless":
		return
	var want: DisplayServer.WindowMode = [DisplayServer.WINDOW_MODE_WINDOWED,
		DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN][clampi(int(data.window_mode), 0, 2)]
	var cur := DisplayServer.window_get_mode()
	var cur_full := cur == DisplayServer.WINDOW_MODE_FULLSCREEN or cur == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if want == cur or (want == DisplayServer.WINDOW_MODE_WINDOWED and not cur_full):
		return  # Maximised/minimised windows count as windowed.
	DisplayServer.window_set_mode(want)
	if want == DisplayServer.WINDOW_MODE_WINDOWED:
		# Come back as a comfortable, centred window instead of a screen-sized one.
		var screen := DisplayServer.window_get_current_screen()
		var area := DisplayServer.screen_get_usable_rect(screen)
		var sz := Vector2i(mini(1600, int(area.size.x * 0.85)), mini(900, int(area.size.y * 0.85)))
		DisplayServer.window_set_size(sz)
		DisplayServer.window_set_position(area.position + (area.size - sz) / 2)


func is_fullscreen() -> bool:
	return int(data.window_mode) != 0


## F11 / Alt+Enter. Remembers the last fullscreen flavour the player picked.
func toggle_fullscreen() -> void:
	if is_fullscreen():
		set_value("window_mode", 0)
	else:
		set_value("window_mode", 2 if int(data.get("last_fullscreen", 1)) == 2 else 1)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen") and not event.is_echo():
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


func _apply_audio() -> void:
	_set_bus("Master", float(data.vol_master))
	_set_bus("SFX", float(data.vol_sfx))
	_set_bus("Music", float(data.vol_music))
	_set_bus("UI", float(data.vol_ui))


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


## Particle budget multiplier per quality tier.
func fx_scale() -> float:
	return [0.4, 0.7, 1.0, 1.3][quality()]


func vibrate(ms: int) -> void:
	if data.haptics and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


# --- Input map ---------------------------------------------------------------

func _setup_input() -> void:
	_bind("throttle_up", [_key(KEY_W), _key(KEY_UP), _joy_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_bind("throttle_down", [_key(KEY_S), _key(KEY_DOWN), _joy_axis(JOY_AXIS_RIGHT_Y, 1.0)])
	_bind("roll_left", [_key(KEY_A), _joy_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_bind("roll_right", [_key(KEY_D), _joy_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_bind("strafe_left", [_key(KEY_Q)])
	_bind("strafe_right", [_key(KEY_E)])
	_bind("pitch_up", [_joy_axis(JOY_AXIS_LEFT_Y, 1.0)])
	_bind("pitch_down", [_joy_axis(JOY_AXIS_LEFT_Y, -1.0)])
	_bind("yaw_left", [_joy_axis(JOY_AXIS_LEFT_X, -1.0)])
	_bind("yaw_right", [_joy_axis(JOY_AXIS_LEFT_X, 1.0)])
	_bind("boost", [_key(KEY_SHIFT), _key(KEY_SPACE), _joy_button(JOY_BUTTON_RIGHT_SHOULDER)])
	_bind("fire_primary", [_mouse(MOUSE_BUTTON_LEFT), _joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_bind("fire_secondary", [_mouse(MOUSE_BUTTON_RIGHT), _joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_bind("target_next", [_key(KEY_T), _key(KEY_F), _joy_button(JOY_BUTTON_LEFT_SHOULDER)])
	_bind("scoreboard", [_key(KEY_TAB), _joy_button(JOY_BUTTON_BACK)])
	_bind("pause", [_key(KEY_ESCAPE), _joy_button(JOY_BUTTON_START)])
	_bind("look_back", [_key(KEY_C), _joy_button(JOY_BUTTON_RIGHT_STICK)])
	_bind("recenter_aim", [_key(KEY_X), _mouse(MOUSE_BUTTON_MIDDLE)])
	var alt_enter := _key(KEY_ENTER)
	alt_enter.alt_pressed = true
	var alt_kp_enter := _key(KEY_KP_ENTER)
	alt_kp_enter.alt_pressed = true
	_bind("toggle_fullscreen", [_key(KEY_F11), alt_enter, alt_kp_enter])


func _bind(action: String, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for e in events:
		InputMap.action_add_event(action, e)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


func _joy_button(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


func _joy_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e
