extends Control
## Boot / loading screen. Everything heavy runs off the main thread (audio
## synthesis, scene loading) or asynchronously (cloud sign-in, update
## check), so the animated backdrop and progress bar never hitch. A hidden
## viewport draws every core material once to warm the shader pipelines.

const TIPS := [
	"Hold all three relays to bleed the enemy score twice as fast.",
	"Boost to break a missile lock, then turn hard across its path.",
	"Your guns aim on gimbals. Lead the target pip, not the ship.",
	"Shields recharge after a few seconds without taking damage.",
	"Shooting asteroids splits them. Big rocks make great cover.",
	"Railguns charge before they fire. Release when the ring closes.",
	"Capturing a relay with wingmen nearby is faster.",
	"Kills are worth 3 points, so a strong fleet can win without relays.",
]
const MIN_TIME := 2.4

var _bg: ColorRect
var _bg_mat: ShaderMaterial
var _bar_fill: ColorRect
var _bar_glow: ColorRect
var _bar_w := 560.0
var _status: Label
var _tip: Label
var _pct: Label
var _progress := 0.0
var _shown := 0.0
var _t := 0.0
var _tip_i := 0
var _tip_t := 0.0
var _audio_thread: Thread
var _menu_scene: PackedScene
var _warm: SubViewport


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	if App.is_dedicated:
		_start_dedicated()
		return
	_build()
	_run()


func _build() -> void:
	_bg = ColorRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = preload("res://shaders/loading_bg.gdshader")
	_bg_mat.set_shader_parameter("reveal", 0.0)
	_bg.material = _bg_mat
	add_child(_bg)
	var m := 48 if App.is_mobile else 110
	var logo := VBoxContainer.new()
	logo.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	logo.offset_left = m
	logo.offset_top = -150
	logo.offset_right = m + 1000
	logo.offset_bottom = 60
	logo.add_theme_constant_override("separation", -10)
	add_child(logo)
	logo.add_child(UI.caption("A 10 v 10 space combat game", 18, App.ACCENT))
	logo.add_child(UI.label(App.GAME_TITLE, 150, Color.WHITE, "display"))
	logo.add_child(UI.caption("Europa orbit", 22, Color(1, 1, 1, 0.55)))
	UI.fade_in(logo, 1.0, 0.25, Vector2(-30, 0))
	# Bottom: status, thin glowing bar, tip.
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.offset_left = m
	bottom.offset_top = -190
	bottom.offset_right = m + 900
	bottom.offset_bottom = -70
	bottom.add_theme_constant_override("separation", 12)
	add_child(bottom)
	var srow := HBoxContainer.new()
	_status = UI.caption("Initialising", 16, App.TEXT)
	srow.add_child(_status)
	srow.add_child(UI.hspacer())
	_pct = UI.label("0%", 18, App.ACCENT, "display_semi")
	srow.add_child(_pct)
	srow.custom_minimum_size.x = _bar_w
	srow.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bottom.add_child(srow)
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.1)
	track.custom_minimum_size = Vector2(_bar_w, 3)
	track.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bottom.add_child(track)
	_bar_glow = ColorRect.new()
	_bar_glow.color = Color(App.ACCENT, 0.25)
	_bar_glow.position = Vector2(0, -3)
	_bar_glow.size = Vector2(0, 9)
	track.add_child(_bar_glow)
	_bar_fill = ColorRect.new()
	_bar_fill.color = App.ACCENT
	_bar_fill.size = Vector2(0, 3)
	track.add_child(_bar_fill)
	bottom.add_child(UI.vspacer(6))
	_tip = UI.label(TIPS[0], 20, App.TEXT_DIM)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size.x = 800
	bottom.add_child(_tip)
	_tip_i = randi() % TIPS.size()
	_tip.text = "TIP  ·  " + TIPS[_tip_i]
	var ver := UI.label("%s  ·  build %d  ·  %s" % [App.version_label(), App.build, App.commit.substr(0, 7)], 15, Color(1, 1, 1, 0.35), "display_semi")
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.offset_right = -m
	ver.offset_bottom = -40
	add_child(ver)
	create_tween().tween_method(func(v): _bg_mat.set_shader_parameter("reveal", v), 0.0, 1.0, 1.4).set_trans(Tween.TRANS_SINE)


func _process(delta: float) -> void:
	if _bg == null:
		return
	_t += delta
	_bg_mat.set_shader_parameter("resolution", size)
	_shown = move_toward(_shown, _progress, delta * 0.9)
	_bar_fill.size.x = _bar_w * _shown
	_bar_glow.size.x = _bar_w * _shown
	_pct.text = "%d%%" % int(_shown * 100.0)
	_tip_t += delta
	if _tip_t > 4.5:
		_tip_t = 0.0
		_tip_i = (_tip_i + 1) % TIPS.size()
		var tw := create_tween()
		tw.tween_property(_tip, "modulate:a", 0.0, 0.3)
		tw.tween_callback(func(): _tip.text = "TIP  ·  " + TIPS[_tip_i])
		tw.tween_property(_tip, "modulate:a", 1.0, 0.3)


func _set_status(text: String) -> void:
	_status.text = UI.spaced(text)


func _run() -> void:
	var start := Time.get_ticks_msec() / 1000.0
	# 1. Audio synthesis on a worker thread.
	_set_status("Synthesising audio")
	_audio_thread = Thread.new()
	_audio_thread.start(Sfx.generate_all)
	# 2. Menu scene on the resource loader's threads.
	ResourceLoader.load_threaded_request(App.SCENE_MENU, "PackedScene", true)
	# 3. Cloud session + update check run concurrently.
	var cloud_done := [false]
	_cloud.call_deferred(cloud_done)
	Updater.check()
	await get_tree().process_frame
	# 4. Shader warm-up while the rest finishes.
	_set_status("Preparing shaders")
	_build_warmup()
	while true:
		var a := Sfx.progress
		var load_p := []
		var st := ResourceLoader.load_threaded_get_status(App.SCENE_MENU, load_p)
		var lp: float = 1.0 if st != ResourceLoader.THREAD_LOAD_IN_PROGRESS else float(load_p[0]) if load_p.size() > 0 else 0.0
		var elapsed := Time.get_ticks_msec() / 1000.0 - start
		_progress = clampf(a * 0.45 + lp * 0.35 + (0.1 if cloud_done[0] else 0.0) + minf(elapsed / MIN_TIME, 1.0) * 0.1, 0.0, 1.0)
		if a >= 1.0 and st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if not cloud_done[0]:
				_set_status("Contacting command")
			elif elapsed >= MIN_TIME:
				break
		elif a >= 1.0:
			_set_status("Loading hangar")
		if elapsed > 12.0 and a >= 1.0 and st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			break  # Never let a slow network hold the player at boot.
		await get_tree().process_frame
	_audio_thread.wait_to_finish()
	_menu_scene = ResourceLoader.load_threaded_get(App.SCENE_MENU)
	_progress = 1.0
	_set_status("Ready")
	while _shown < 0.999:
		await get_tree().process_frame
	if _warm:
		_warm.queue_free()
	App.goto_scene(App.SCENE_MENU, 0.6)


func _cloud(done: Array) -> void:
	if Firebase.is_configured() and Firebase.has_saved_session():
		if await Firebase.restore_session():
			await Profile.pull_cloud()
	done[0] = true


## Draws the core materials once in an offscreen viewport so the GPU
## pipelines exist before the first battle frame needs them.
func _build_warmup() -> void:
	_warm = SubViewport.new()
	_warm.size = Vector2i(128, 72)
	_warm.own_world_3d = true
	_warm.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_warm)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 12)
	_warm.add_child(cam)
	var light := DirectionalLight3D.new()
	light.shadow_enabled = true
	light.rotation = Vector3(-0.6, 0.4, 0)
	_warm.add_child(light)
	var quad := Mats.quad()
	var mats: Array = [Mats.hull(0, App.team_color(0)), Mats.hull(1, App.team_color(1)), Mats.glass(), Mats.flame(App.ACCENT),
		Mats.glow(App.ACCENT), Mats.trail(App.ACCENT), Mats.smoke(), Mats.bolt(), Mats.beam(App.ACCENT), Mats.fireball(),
		Mats.shockwave(App.ACCENT), Mats.shield(App.ACCENT)]
	for i in 3:
		mats.append(Mats.asteroid(i))
	var meshes := HullBuilder.build("vanguard")
	for i in mats.size():
		var mi := MeshInstance3D.new()
		mi.mesh = meshes.hull if i < 2 else (Mats.sphere(12, 6) if i >= 11 else quad)
		mi.material_override = mats[i]
		mi.position = Vector3((i % 5 - 2) * 3.0, (i / 5 - 1) * 3.0, 0)
		mi.scale = Vector3.ONE * (0.2 if i < 2 else 1.0)
		_warm.add_child(mi)


func _start_dedicated() -> void:
	print("[Server] Star Battles dedicated server %s on UDP %d" % [App.version_label(), Net.PORT])
	var err := Net.host_game("Dedicated Battle", true, true)
	if err != OK:
		push_error("Could not host on port %d (%d)" % [Net.PORT, err])
		get_tree().quit(1)
		return
	await get_tree().process_frame
	Net.match_mode = "siege" if App.cli_mode == "siege" else "conquest"
	Net.start_match({"mode": Net.match_mode})


func _exit_tree() -> void:
	if _audio_thread and _audio_thread.is_started():
		_audio_thread.wait_to_finish()
