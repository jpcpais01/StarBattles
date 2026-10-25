extends Node3D
## Home screen. A live 3D hangar shot (your ship idling in front of Jupiter)
## sits behind a console-style UI: top bar with pilot and network status,
## a focused-tile headline, and a row of animated tiles that open pages.
## The siege briefing swaps the fighter for the full-size IRON VANGUARD.

signal scene_ready

const Tile := preload("res://ui/menu/tile.gd")
const PAGES := {
	"siege": preload("res://ui/menu/siege_page.gd"),
	"multiplayer": preload("res://ui/menu/multiplayer_page.gd"),
	"lobby": preload("res://ui/menu/lobby_page.gd"),
	"hangar": preload("res://ui/menu/hangar_page.gd"),
	"pilot": preload("res://ui/menu/pilot_page.gd"),
	"notes": preload("res://ui/menu/patch_notes_page.gd"),
	"settings": preload("res://ui/menu/settings_panel.gd"),
	"update": preload("res://ui/menu/update_page.gd"),
}
const TILES := [
	{"id": "quick", "label": "QUICK BATTLE", "icon": "battle", "tint": Color(0.42, 0.82, 1.0),
		"title": "QUICK BATTLE", "desc": "Drop straight into a 10 v 10 Conquest battle against AI squadrons. Hold the three relay stations or out-gun the enemy fleet to win."},
	{"id": "siege", "label": "SIEGE", "icon": "siege", "tint": Color(1.0, 0.45, 0.3),
		"title": "MOTHERSHIP SIEGE", "desc": "A 1.5 km carrier, sixteen turrets and a shield bubble. Tear it down with the attack wing, or fly escort and keep it alive."},
	{"id": "multiplayer", "label": "MULTIPLAYER", "icon": "multi", "tint": Color(0.45, 1.0, 0.75),
		"title": "MULTIPLAYER", "desc": "Host or join battles with friends over Wi-Fi or the internet. Up to 20 pilots, with AI wingmen filling every empty seat."},
	{"id": "hangar", "label": "HANGAR", "icon": "hangar", "tint": Color(1.0, 0.62, 0.3),
		"title": "HANGAR", "desc": "Choose your starfighter. Each hull carries its own hardpoints, engines and handling."},
	{"id": "pilot", "label": "PILOT", "icon": "pilot", "tint": Color(0.75, 0.6, 1.0),
		"title": "PILOT", "desc": "Callsign, rank and career stats. Sign in to keep your progress safe in the cloud."},
	{"id": "notes", "label": "PATCH NOTES", "icon": "notes", "tint": Color(1.0, 0.85, 0.4),
		"title": "PATCH NOTES", "desc": "See what changed in every update."},
	{"id": "settings", "label": "SETTINGS", "icon": "settings", "tint": Color(0.7, 0.78, 0.9),
		"title": "SETTINGS", "desc": "Graphics, controls, audio and gameplay. Every change applies instantly."},
]

var is_scene_ready := false
var env: SpaceEnv
var camera: Camera3D
var showcase: Node3D
var ship: Ship
var _ship_id := ""
var capital: Mothership
var _capital_fill: OmniLight3D
var _rocks: Array[Node3D] = []
var _t := 0.0

var ui: CanvasLayer
var home: Control
var pages_root: Control
var _tiles: Array[Button] = []
var _focus_index := 0
var _head_title: Label
var _head_desc: Label
var _head_hint: Label
var _head_box: VBoxContainer
var _clock: Label
var _net_chip: PanelContainer
var _update_chip: Button
var _profile_name: Label
var _profile_rank: Label
var _profile_level: Label
var _page: Control


func _ready() -> void:
	name = "Menu"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_world()
	_build_ui()
	Profile.changed.connect(_refresh_profile)
	Firebase.auth_changed.connect(func(_s): _refresh_status())
	Updater.checked.connect(func(_a): _refresh_status())
	Updater.download_progress.connect(func(_d, _t2, _s): _refresh_status())
	_refresh_profile()
	_refresh_status()
	if Sfx.ready_sounds:
		Sfx.play_music("music_menu")
	is_scene_ready = true
	scene_ready.emit()
	_intro()
	if App.autotest_seconds > 0.0 and App.autotest_join != "":
		get_tree().create_timer(1.0).timeout.connect(func(): Net.join_game(App.autotest_join))
	elif App.autotest_seconds > 0.0:
		get_tree().create_timer(1.0).timeout.connect(_quick_battle)
	elif Net.in_session and not App.is_dedicated:
		open_page("lobby")
	elif not Profile.has_callsign():
		_welcome()


# --- 3D backdrop -------------------------------------------------------------------

func _build_world() -> void:
	env = SpaceEnv.new()
	add_child(env)
	camera = Camera3D.new()
	camera.fov = 46.0
	camera.near = 0.2
	camera.far = 60000.0
	add_child(camera)
	camera.make_current()
	showcase = Node3D.new()
	showcase.name = "Showcase"
	add_child(showcase)
	_show_ship(str(Profile.data.ship))
	# A few lit rocks drifting past for depth.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var spots := [Vector3(-26, -9, -48), Vector3(34, 14, -90), Vector3(-60, 22, -140), Vector3(18, -22, -30), Vector3(80, -10, -170), Vector3(-14, 30, -75)]
	for i in spots.size():
		var data := AsteroidMesh.generate(9100 + i * 13, 3 if i < 3 else 2)
		var mi := MeshInstance3D.new()
		mi.mesh = AsteroidMesh.to_mesh(data)
		mi.material_override = Mats.asteroid(i)
		mi.position = spots[i]
		mi.scale = Vector3.ONE * rng.randf_range(2.5, 7.0)
		mi.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)
		mi.set_meta("spin", Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.1, 0.1), rng.randf_range(-0.05, 0.05)))
		add_child(mi)
		_rocks.append(mi)


func _show_ship(id: String) -> void:
	if id == _ship_id:
		return
	_ship_id = id
	if ship:
		ship.queue_free()
	ship = Ship.new()
	showcase.add_child(ship)
	ship.setup(0, id, 0, 1, Profile.callsign(), false)
	ship.visible = true
	ship.alive = true
	ship.throttle = 0.5
	ship.rotation.y = deg_to_rad(146.0)
	if ship.hit_area:
		ship.hit_area.monitorable = false
	ship.scale = Vector3.ONE * 0.0001
	create_tween().tween_property(ship, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_t += delta
	if capital:
		_frame_capital(delta)
	elif ship and is_instance_valid(ship):
		var r := ship.radius
		var dist := r * 3.15
		# Framed toward Jupiter so the planet hangs behind the ship.
		var look := env.jupiter_direction.rotated(Vector3.UP, deg_to_rad(-16.0 + sin(_t * 0.07) * 9.0))
		look = look.rotated(look.cross(Vector3.UP).normalized(), deg_to_rad(-6.0 + sin(_t * 0.05) * 3.0))
		var center := Vector3(0, 0, 0)
		camera.global_position = center - look * dist + Vector3(0, r * 0.35, 0)
		camera.look_at(camera.global_position + look, Vector3.UP)
		camera.h_offset = -r * 0.95 if not _page else 0.0
		camera.v_offset = -r * 0.22
		showcase.position = Vector3(0, sin(_t * 0.8) * r * 0.04, 0)
		showcase.rotation = Vector3(sin(_t * 0.37) * 0.04, sin(_t * 0.11) * 0.18, sin(_t * 0.53) * 0.05)
		ship.rates = Vector3(0, sin(_t * 0.11) * 0.4, 0)
		for m in ship.mounts:
			m.aim_at(ship.global_position + ship.global_basis * Vector3(sin(_t * 0.6) * 30.0, cos(_t * 0.43) * 12.0, -120.0), delta)
		for e in ship.engines:
			e.boost = 0.5 + 0.5 * sin(_t * 0.4) if sin(_t * 0.4) > 0.6 else 0.0
	for rock in _rocks:
		var s: Vector3 = rock.get_meta("spin")
		rock.rotation += s * delta
		rock.position.x += 0.6 * delta
	if _clock:
		var tm := Time.get_time_dict_from_system()
		_clock.text = "%02d:%02d" % [tm.hour, tm.minute]


# --- UI ------------------------------------------------------------------------------

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.theme()
	ui.add_child(root)
	var vig := ColorRect.new()
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = preload("res://shaders/vignette.gdshader")
	vig.material = vm
	root.add_child(vig)
	home = Control.new()
	home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(home)
	_build_top_bar()
	_build_headline()
	_build_tiles()
	pages_root = Control.new()
	pages_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pages_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pages_root)


func _side_margin() -> int:
	return 48 if App.is_mobile else 90


func _build_top_bar() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = _side_margin()
	bar.offset_right = -_side_margin()
	bar.offset_top = 40
	bar.offset_bottom = 120
	bar.add_theme_constant_override("separation", 18)
	home.add_child(bar)
	var mark := VBoxContainer.new()
	mark.add_theme_constant_override("separation", -6)
	mark.add_child(UI.label(App.GAME_TITLE, 44, Color.WHITE, "display"))
	mark.add_child(UI.caption("Europa orbit  ·  %s" % App.version_label(), 14, App.ACCENT))
	bar.add_child(mark)
	bar.add_child(UI.hspacer())
	_update_chip = UI.button("", func(): open_page("update"))
	_update_chip.visible = false
	_update_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_update_chip.add_theme_stylebox_override("normal", UI.pill_box(App.WARN, 0.2))
	_update_chip.add_theme_stylebox_override("hover", UI.pill_box(App.WARN, 0.4))
	_update_chip.add_theme_color_override("font_color", App.WARN.lightened(0.4))
	_update_chip.add_theme_font_size_override("font_size", 18)
	_update_chip.focus_mode = Control.FOCUS_NONE
	bar.add_child(_update_chip)
	_net_chip = UI.pill("OFFLINE", App.TEXT_DIM)
	_net_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_net_chip)
	# Profile chip: level badge + callsign/rank. Opens the pilot page.
	var chip := Button.new()
	chip.focus_mode = Control.FOCUS_NONE
	chip.custom_minimum_size = Vector2(300, 72)
	var sb := UI.pill_box(Color.WHITE, 0.06)
	sb.content_margin_left = 8
	chip.add_theme_stylebox_override("normal", sb)
	var sbh := UI.pill_box(App.ACCENT, 0.16)
	sbh.content_margin_left = 8
	chip.add_theme_stylebox_override("hover", sbh)
	chip.add_theme_stylebox_override("pressed", sbh)
	chip.pressed.connect(func():
		Sfx.ui("ui_select")
		open_page("pilot"))
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	h.offset_right = -22
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 14)
	var badge := PanelContainer.new()
	var bs := UI.pill_box(App.ACCENT, 0.9)
	bs.content_margin_left = 0
	bs.content_margin_right = 0
	badge.add_theme_stylebox_override("panel", bs)
	badge.custom_minimum_size = Vector2(56, 56)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_profile_level = UI.label("1", 28, Color(0.02, 0.05, 0.1), "display")
	_profile_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_profile_level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(_profile_level)
	h.add_child(badge)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", -4)
	pv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_profile_name = UI.label("PILOT", 24, Color.WHITE, "display")
	_profile_rank = UI.label("CADET", 14, App.TEXT_DIM, "display_semi")
	pv.add_child(_profile_name)
	pv.add_child(_profile_rank)
	h.add_child(pv)
	chip.add_child(h)
	bar.add_child(chip)
	_clock = UI.label("--:--", 30, App.TEXT, "display_semi")
	_clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_clock)


func _build_headline() -> void:
	_head_box = VBoxContainer.new()
	_head_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_head_box.offset_left = _side_margin()
	_head_box.offset_top = -560
	_head_box.offset_bottom = -340
	_head_box.offset_right = _side_margin() + 820
	_head_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_head_box.alignment = BoxContainer.ALIGNMENT_END
	_head_box.add_theme_constant_override("separation", 6)
	_head_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home.add_child(_head_box)
	_head_title = UI.label("", 92, Color.WHITE, "display")
	_head_box.add_child(_head_title)
	_head_desc = UI.label("", 22, App.TEXT)
	_head_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_head_desc.custom_minimum_size.x = 760
	_head_box.add_child(_head_desc)
	_head_hint = UI.caption("", 15, App.ACCENT)
	_head_box.add_child(_head_hint)


func _build_tiles() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_left = _side_margin()
	row.offset_right = -_side_margin()
	row.offset_top = -330
	row.offset_bottom = -64
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home.add_child(row)
	var compact := App.is_mobile or get_viewport().get_visible_rect().size.x < 1700.0
	for i in TILES.size():
		var d: Dictionary = TILES[i]
		var t: Button = Tile.new()
		t.icon_kind = d.icon
		t.caption_text = d.label
		t.tint = d.tint
		if compact:
			t.base_size = Vector2(180, 180)
			t.focus_size = Vector2(214, 214)
		t.size_flags_vertical = Control.SIZE_SHRINK_END
		t.focus_entered.connect(_on_tile_focus.bind(i))
		t.pressed.connect(_on_tile_pressed.bind(i))
		row.add_child(t)
		_tiles.append(t)


func _intro() -> void:
	for i in _tiles.size():
		var t := _tiles[i]
		t.modulate.a = 0.0
		var tw := t.create_tween()
		tw.tween_interval(0.25 + i * 0.06)
		tw.tween_property(t, "modulate:a", 1.0, 0.4)
	UI.fade_in(_head_box, 0.6, 0.2, Vector2.ZERO)
	_tiles[0].grab_focus.call_deferred()


func _on_tile_focus(i: int) -> void:
	_focus_index = i
	var d: Dictionary = TILES[i]
	_head_title.text = d.title
	_head_desc.text = d.desc
	_head_hint.text = UI.spaced("Tap to open" if App.is_mobile else "Press enter to open")
	if d.id == "siege":
		_head_hint.text = UI.spaced("Tap to choose a side" if App.is_mobile else "Press enter to choose a side")
	if d.id == "quick":
		_head_hint.text = UI.spaced("Tap to launch" if App.is_mobile else "Press enter to launch")
	if d.id == "hangar":
		_head_hint.text = UI.spaced("Current ship: " + ShipLibrary.ship(str(Profile.data.ship)).name)
	_head_title.modulate.a = 0.0
	_head_title.create_tween().tween_property(_head_title, "modulate:a", 1.0, 0.25)


func _on_tile_pressed(i: int) -> void:
	var id: String = TILES[i].id
	if id == "quick":
		_quick_battle()
	else:
		open_page(id)


func _quick_battle() -> void:
	if App.transitioning:
		return
	Net.leave()
	if App.autotest_seconds > 0.0 and App.cli_mode == "siege":
		Net.start_match({"mode": "siege", "team": App.cli_team if App.cli_team >= 0 else SiegeRules.ATTACKERS})
		return
	Net.start_match({"mode": "quick"})


# --- Siege showcase ---------------------------------------------------------------

func _show_capital(on: bool) -> void:
	if on == (capital != null):
		return
	if ship:
		ship.visible = not on
	for rock in _rocks:
		rock.visible = not on
	if not on:
		capital.queue_free()
		capital = null
		_capital_fill.queue_free()
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		return
	# Broadside-on at true scale, bow angled slightly toward the camera.
	var side := env.jupiter_direction.cross(Vector3.UP).normalized()
	var z := -side.rotated(Vector3.UP, deg_to_rad(-20.0))
	var b := Basis(Vector3.UP.cross(z).normalized(), Vector3.UP, z)
	capital = Mothership.new()
	add_child(capital)
	capital.setup(null, SiegeRules.DEFENDERS, Transform3D(b, Vector3.ZERO))
	# Jupiter sits behind it, so the near side would be in shadow: a soft fill.
	_capital_fill = OmniLight3D.new()
	_capital_fill.light_color = Color(0.7, 0.8, 1.0)
	_capital_fill.omni_range = 4200.0
	_capital_fill.omni_attenuation = 0.6
	_capital_fill.light_energy = 1.6
	_capital_fill.position = -env.jupiter_direction * 1500.0 + Vector3(0, 900.0, 0)
	add_child(_capital_fill)


func _frame_capital(delta: float) -> void:
	var look := env.jupiter_direction.rotated(Vector3.UP, deg_to_rad(-10.0 + sin(_t * 0.04) * 6.0))
	look = look.rotated(look.cross(Vector3.UP).normalized(), deg_to_rad(-9.0 + sin(_t * 0.03) * 2.0))
	camera.global_position = -look * 2300.0 + Vector3(0, 320.0, 0)
	camera.look_at(camera.global_position + look, Vector3.UP)
	camera.h_offset = -620.0
	camera.v_offset = 60.0
	capital.position = Vector3(0, sin(_t * 0.25) * 6.0, 0)
	for p in capital.parts:
		if p.is_turret():
			p.track(capital.to_global(p.position + p.up_local * 600.0 + Vector3(sin(_t * 0.2 + p.index) * 900.0, 0, cos(_t * 0.17 + p.index) * 900.0)), delta)


func open_page(id: String) -> void:
	if _page and is_instance_valid(_page):
		_page.queue_free()
	var p: Control = PAGES[id].new()
	_page = p
	pages_root.add_child(p)
	_set_home_visible(false)
	if p.has_signal("open_lobby"):
		p.open_lobby.connect(func(): open_page.call_deferred("lobby"))
	if p.has_signal("ship_focused"):
		p.ship_focused.connect(_show_ship)
	if p.has_signal("capital_focused"):
		p.capital_focused.connect(_show_capital)
	p.closed.connect(func():
		if _page == p:
			_page = null
			_show_capital(false)
			_show_ship(str(Profile.data.ship))
			_set_home_visible(true)
			_tiles[_focus_index].grab_focus())


func _set_home_visible(v: bool) -> void:
	var tw := home.create_tween()
	tw.tween_property(home, "modulate:a", 1.0 if v else 0.0, 0.25)
	home.visible = true
	if not v:
		tw.tween_callback(func(): home.visible = _page == null)


func _refresh_profile() -> void:
	if not _profile_name:
		return
	_profile_name.text = Profile.callsign()
	_profile_rank.text = "%s  ·  %d%% TO LV %d" % [Profile.rank_name(), int(Profile.level_progress() * 100.0), int(Profile.data.level) + 1]
	_profile_level.text = str(int(Profile.data.level))
	for t in _tiles:
		t.queue_redraw()


func _refresh_status() -> void:
	if not _net_chip:
		return
	var lbl: Label = _net_chip.get_child(0)
	var col := App.TEXT_DIM
	if Firebase.is_signed_in():
		lbl.text = "ONLINE" if not Firebase.is_anonymous else "ONLINE · GUEST"
		col = App.GOOD
	elif Firebase.is_configured():
		lbl.text = "OFFLINE"
	else:
		lbl.text = "LOCAL PROFILE"
	lbl.add_theme_color_override("font_color", col.lightened(0.3))
	_net_chip.add_theme_stylebox_override("panel", UI.pill_box(col))
	if Updater.downloading:
		_update_chip.visible = true
		var total := int(Updater.latest.get("asset_size", 0))
		_update_chip.text = "DOWNLOADING UPDATE"
		if total > 0 and Updater._http:
			_update_chip.text = "DOWNLOADING  %d%%" % int(Updater._http.get_downloaded_bytes() * 100.0 / total)
	elif Updater.available:
		_update_chip.visible = true
		_update_chip.text = "UPDATE  v%s  AVAILABLE" % str(Updater.latest.get("version", ""))
	else:
		_update_chip.visible = false


# --- First run -------------------------------------------------------------------

func _welcome() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.01, 0.03, 0.7)
	pages_root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = 640
	v.add_theme_constant_override("separation", 14)
	center.add_child(UI.panel(v, 0.9))
	v.add_child(UI.caption("Welcome to the Europa front", 16, App.ACCENT))
	v.add_child(UI.title("CHOOSE YOUR CALLSIGN", 48))
	var d := UI.label("This is the name other pilots see in battle. You can change it any time on the Pilot page.", 19, App.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	var edit := LineEdit.new()
	edit.max_length = 16
	edit.placeholder_text = "e.g. NOVA"
	edit.add_theme_font_override("font", UI.font("display"))
	edit.add_theme_font_size_override("font_size", 38)
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(edit)
	var err := UI.label("", 17, App.BAD)
	v.add_child(err)
	var go := func():
		var n := edit.text.strip_edges()
		if n.length() < 2:
			err.text = "At least 2 characters."
			Sfx.ui("ui_error")
			return
		Profile.set_callsign(n)
		var tw := shade.create_tween()
		tw.tween_property(shade, "modulate:a", 0.0, 0.3)
		tw.tween_callback(shade.queue_free)
		_tiles[0].grab_focus()
	v.add_child(UI.button("ENLIST", go, true))
	edit.text_submitted.connect(func(_t): go.call())
	UI.fade_in(v, 0.45)
	edit.grab_focus.call_deferred()
