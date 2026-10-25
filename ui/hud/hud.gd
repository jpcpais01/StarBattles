extends CanvasLayer
## In-match HUD shell: lays out the overlay, score bar, radar, kill feed,
## banners and the full-screen states (respawn, scoreboard, pause, results).

const Overlay := preload("res://ui/hud/hud_overlay.gd")
const ScoreBar := preload("res://ui/hud/score_bar.gd")
const Radar := preload("res://ui/hud/radar.gd")
const Touch := preload("res://ui/hud/touch_controls.gd")
const SettingsPanel := preload("res://ui/menu/settings_panel.gd")

var arena: Arena
var root: Control
var overlay: Control
var touch: Control
var score_bar: Control
var radar: Control
var _feed: VBoxContainer
var _banner: VBoxContainer
var _banner_title: Label
var _banner_sub: Label
var _notify: Label
var _toast: Label
var _weapons: Label
var _countdown: Label
var _fps: Label
var _death: Control
var _death_title: Label
var _death_timer: Label
var _scoreboard: Control
var _pause: Control
var _results: Control
var _ship_cards: HBoxContainer
var _banner_tw: Tween
var _notify_tw: Tween


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.theme()
	add_child(root)
	overlay = Overlay.new()
	overlay.arena = arena
	overlay.hud = self
	root.add_child(overlay)

	score_bar = ScoreBar.new()
	score_bar.arena = arena
	score_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	score_bar.size = Vector2(760, 96)
	score_bar.position = Vector2(-380, 18)
	root.add_child(score_bar)

	radar = Radar.new()
	radar.arena = arena
	radar.size = Vector2(230, 230)
	if App.is_mobile:
		radar.set_anchors_preset(Control.PRESET_TOP_LEFT)
		radar.position = Vector2(28, 110)
		radar.size = Vector2(190, 190)
	else:
		radar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		radar.position = Vector2(36, -266)
	root.add_child(radar)

	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.position = Vector2(-460, 28)
	_feed.size = Vector2(430, 300)
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed.add_theme_constant_override("separation", 6)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_feed)

	_banner = VBoxContainer.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-500, 150)
	_banner.size = Vector2(1000, 120)
	_banner.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_title = UI.label("", 52, Color.WHITE, "display")
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub = UI.label("", 20, App.TEXT_DIM, "body", 500)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_title)
	_banner.add_child(_banner_sub)
	_banner.modulate.a = 0.0
	root.add_child(_banner)

	_notify = UI.label("", 30, App.WARN, "display")
	_notify.set_anchors_preset(Control.PRESET_CENTER)
	_notify.position = Vector2(-300, 150)
	_notify.size = Vector2(600, 40)
	_notify.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notify.modulate.a = 0.0
	root.add_child(_notify)

	_toast = UI.label("", 20, App.TEXT, "body", 500)
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.position = Vector2(-400, -150)
	_toast.size = Vector2(800, 30)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	root.add_child(_toast)

	_weapons = UI.label("", 17, Color(1, 1, 1, 0.75), "display_semi")
	_weapons.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_weapons.position = Vector2(-420, -110)
	_weapons.size = Vector2(380, 80)
	_weapons.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapons.visible = not App.is_mobile
	root.add_child(_weapons)

	_countdown = UI.label("", 140, Color.WHITE, "display")
	_countdown.set_anchors_preset(Control.PRESET_CENTER)
	_countdown.position = Vector2(-300, -260)
	_countdown.size = Vector2(600, 160)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_countdown)

	_fps = UI.label("", 14, Color(1, 1, 1, 0.5), "body", 600)
	_fps.position = Vector2(10, 6)
	root.add_child(_fps)

	touch = Touch.new()
	touch.visible = App.is_mobile
	root.add_child(touch)

	if App.is_mobile:
		var top := HBoxContainer.new()
		top.position = Vector2(24, 24)
		root.add_child(top)
		top.add_child(_small_button("II", _toggle_pause))
		top.add_child(_small_button("☰", _toggle_scoreboard))

	_build_death()
	_build_scoreboard()
	_build_pause()


func _small_button(text: String, cb: Callable) -> Button:
	var b := UI.button(text, cb)
	b.custom_minimum_size = Vector2(72, 64)
	return b


func _toggle_scoreboard() -> void:
	_scoreboard.visible = not _scoreboard.visible
	if _scoreboard.visible:
		_refresh_scoreboard()


func set_ship(_s: Ship) -> void:
	pass


func refresh_roster() -> void:
	if _scoreboard and _scoreboard.visible:
		_refresh_scoreboard()


# --- Per-frame ------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if arena == null or not arena.is_scene_ready:
		return
	var ctl := arena.ctl
	if ctl.phase == MatchController.Phase.WARMUP:
		_countdown.text = str(int(ceil(ctl.phase_time))) if ctl.phase_time <= 5.0 else ""
		if _countdown.text != "" and _countdown.get_meta("last", "") != _countdown.text:
			_countdown.set_meta("last", _countdown.text)
			Sfx.play("countdown", -2.0)
			_countdown.scale = Vector2.ONE * 1.3
			_countdown.pivot_offset = _countdown.size * 0.5
			create_tween().tween_property(_countdown, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)
	else:
		_countdown.text = ""
	_fps.visible = Settings.get_value("show_fps", false)
	if _fps.visible:
		_fps.text = "%d FPS  ·  %d bolts" % [Engine.get_frames_per_second(), arena.projectiles.count()]
	var me := arena.local_ship
	if me and me.alive:
		var lines := PackedStringArray()
		var primary := ""
		for m in me.mounts:
			if m.group == 0:
				primary = m.wdef.name.to_upper()
		lines.append(primary + ("   OVERHEATED" if me.primary_overheated() else ""))
		if me.has_missiles():
			lines.append("SEEKERS   " + ("READY" if me.missile_ready() else "%d%%" % int(me.missile_reload_fraction() * 100.0)))
		_weapons.text = "\n".join(lines)
	if _death.visible and me:
		var left := maxf(0.0, float(arena.ctl._respawn_queue.get(me.ship_id, arena.time)) - arena.time)
		_death_timer.text = "REDEPLOY IN %d" % int(ceil(left)) if left > 0.0 else "REDEPLOYING"
	if not App.is_mobile:
		var want := Input.is_action_pressed("scoreboard")
		if want != _scoreboard.visible and not (_results and _results.visible):
			_scoreboard.visible = want
			if want:
				_refresh_scoreboard()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
	elif event.is_action_pressed("look_back") and arena.camera:
		arena.camera.look_back = true
	elif event.is_action_released("look_back") and arena.camera:
		arena.camera.look_back = false


# --- Events -----------------------------------------------------------------------------

func hit_marker(kill: bool, shield: bool) -> void:
	overlay.hit_marker(kill, shield)


func damage_from(pos: Vector3, shield: bool) -> void:
	overlay.damage_from(pos, shield)


func banner(title: String, sub: String, color: Color) -> void:
	_banner_title.text = title
	_banner_title.add_theme_color_override("font_color", color.lightened(0.2))
	_banner_sub.text = sub
	if _banner_tw:
		_banner_tw.kill()
	_banner.modulate.a = 0.0
	_banner.scale = Vector2(1.08, 1.08)
	_banner.pivot_offset = _banner.size * 0.5
	_banner_tw = create_tween()
	_banner_tw.set_parallel(true)
	_banner_tw.tween_property(_banner, "modulate:a", 1.0, 0.25)
	_banner_tw.tween_property(_banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_banner_tw.chain().tween_interval(2.2)
	_banner_tw.chain().tween_property(_banner, "modulate:a", 0.0, 0.6)


func notify_points(text: String) -> void:
	_notify.text = text
	if _notify_tw:
		_notify_tw.kill()
	_notify.modulate.a = 1.0
	_notify.position.y = 150
	_notify_tw = create_tween()
	_notify_tw.tween_property(_notify, "position:y", 130.0, 1.2).set_trans(Tween.TRANS_CUBIC)
	_notify_tw.parallel().tween_property(_notify, "modulate:a", 0.0, 0.5).set_delay(0.9)


func notify_kill(victim: Ship) -> void:
	notify_points("+100  %s DOWN" % victim.pilot_name.to_upper())


func notify_assist(victim: Ship) -> void:
	notify_points("+40  ASSIST · %s" % victim.pilot_name.to_upper())


func toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.6)


func kill_feed(killer: Ship, victim: Ship) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var me := arena.local_ship
	if killer and killer != victim:
		var kl := UI.label(killer.pilot_name, 19, App.team_color(killer.team).lightened(0.2), "display_semi")
		row.add_child(kl)
		row.add_child(UI.label("  ✦  ", 16, Color(1, 1, 1, 0.5), "body"))
	var vl := UI.label(victim.pilot_name, 19, App.team_color(victim.team).lightened(0.2), "display_semi")
	row.add_child(vl)
	if killer == null or killer == victim:
		row.add_child(UI.label("  crashed", 16, Color(1, 1, 1, 0.5), "body"))
	var panel := PanelContainer.new()
	var sb := UI.pill_box(Color.WHITE, 0.06)
	if me and (killer == me or victim == me):
		sb = UI.pill_box(App.WARN, 0.14)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	panel.add_theme_stylebox_override("panel", sb)
	panel.add_child(row)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_feed.add_child(panel)
	_feed.move_child(panel, 0)
	UI.fade_in(panel, 0.25, 0.0, Vector2(30, 0))
	while _feed.get_child_count() > 6:
		_feed.get_child(_feed.get_child_count() - 1).queue_free()
		_feed.remove_child(_feed.get_child(_feed.get_child_count() - 1))
	# Owned by the panel, so it dies quietly if the feed trims it first.
	var tw := panel.create_tween()
	tw.tween_interval(7.0)
	tw.tween_property(panel, "modulate:a", 0.0, 0.5)
	tw.tween_callback(panel.queue_free)


# --- Death / respawn ----------------------------------------------------------------------

func _build_death() -> void:
	_death = Control.new()
	_death.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death.visible = false
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_death)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.02, 0.45)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.add_child(shade)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-600, -260)
	box.size = Vector2(1200, 560)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	_death.add_child(box)
	_death_title = UI.label("DESTROYED", 64, App.BAD.lightened(0.15), "display")
	_death_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_death_title)
	_death_timer = UI.label("", 26, Color.WHITE, "display_semi")
	_death_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_death_timer)
	box.add_child(UI.vspacer(20))
	var cap := UI.caption("Choose your next ship", 16)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cap)
	_ship_cards = HBoxContainer.new()
	_ship_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	_ship_cards.add_theme_constant_override("separation", 18)
	box.add_child(_ship_cards)


func _rebuild_ship_cards() -> void:
	for c in _ship_cards.get_children():
		c.queue_free()
	var current := str(Profile.data.ship)
	for id in ShipLibrary.SHIP_ORDER:
		var d := ShipLibrary.ship(id)
		var b := Button.new()
		b.custom_minimum_size = Vector2(300, 150)
		b.toggle_mode = true
		b.button_pressed = id == current
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 20
		v.offset_top = 16
		v.offset_right = -20
		v.offset_bottom = -16
		var n := UI.label(d.name, 32, Color.WHITE, "display")
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var r := UI.label(d.role.to_upper(), 15, App.ACCENT, "display_semi")
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(n)
		v.add_child(r)
		for stat in ["speed", "armor", "firepower"]:
			var row := HBoxContainer.new()
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var sl := UI.label(stat.to_upper(), 12, App.TEXT_DIM, "display_semi")
			sl.custom_minimum_size.x = 90
			sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(sl)
			var bar := UI.stat_bar(d.stats[stat])
			bar.custom_minimum_size = Vector2(150, 6)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(bar)
			v.add_child(row)
		b.add_child(v)
		b.pressed.connect(func():
			Sfx.ui("ui_select", -2.0)
			Profile.set_ship(id)
			arena.ctl.request_ship(id)
			for c in _ship_cards.get_children():
				c.button_pressed = c == b)
		_ship_cards.add_child(b)


func on_death(killer: Ship) -> void:
	_death_title.text = "DESTROYED BY %s" % killer.pilot_name.to_upper() if killer else "SHIP LOST"
	_rebuild_ship_cards()
	_death.visible = true
	_death.mouse_filter = Control.MOUSE_FILTER_PASS
	UI.fade_in(_death, 0.6, 0.6, Vector2.ZERO)
	touch.visible = false


func on_spawn(_initial: bool) -> void:
	_death.visible = false
	touch.visible = App.is_mobile


# --- Scoreboard -----------------------------------------------------------------------------

func _build_scoreboard() -> void:
	_scoreboard = PanelContainer.new()
	_scoreboard.add_theme_stylebox_override("panel", UI.panel_box(0.9))
	_scoreboard.set_anchors_preset(Control.PRESET_CENTER)
	_scoreboard.position = Vector2(-760, -380)
	_scoreboard.size = Vector2(1520, 760)
	_scoreboard.visible = false
	_scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_scoreboard)


func _refresh_scoreboard() -> void:
	for c in _scoreboard.get_children():
		c.queue_free()
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	_scoreboard.add_child(cols)
	for t in 2:
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 4)
		cols.add_child(v)
		var head := HBoxContainer.new()
		head.add_child(UI.label(App.TEAM_NAMES[t], 34, App.team_color(t), "display"))
		head.add_child(UI.hspacer())
		head.add_child(UI.label("%d" % int(arena.ctl.scores[t]), 34, Color.WHITE, "display"))
		v.add_child(head)
		v.add_child(_score_row(["PILOT", "SHIP", "K", "D", "A", "SCORE"], App.TEXT_DIM, true))
		var team_ships := arena.ships.filter(func(s): return s.team == t)
		team_ships.sort_custom(func(a, b): return a.score > b.score)
		for s in team_ships:
			var col := Color.WHITE if s != arena.local_ship else App.WARN
			v.add_child(_score_row([s.pilot_name + ("" if not s.is_bot else "  ·  AI"), ShipLibrary.ship(s.def_id).name,
				str(s.kills), str(s.deaths), str(s.assists), str(s.score)], col, false))


func _score_row(cells: Array, col: Color, header: bool) -> Control:
	var row := HBoxContainer.new()
	var widths := [280, 140, 50, 50, 50, 90]
	for i in cells.size():
		var l := UI.label(str(cells[i]), 15 if header else 19, col, "display_semi" if header else "body", 500)
		l.custom_minimum_size.x = widths[i]
		if i >= 2:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.clip_text = true
		row.add_child(l)
	return row


# --- Pause ------------------------------------------------------------------------------------

func _build_pause() -> void:
	_pause = Control.new()
	_pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	root.add_child(_pause)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.01, 0.03, 0.7)
	_pause.add_child(shade)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-220, -220)
	box.size = Vector2(440, 440)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	_pause.add_child(box)
	var t := UI.title("PAUSED", 64)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var note := UI.label("The battle continues around you.", 18, App.TEXT_DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)
	box.add_child(UI.vspacer(10))
	box.add_child(UI.button("RESUME", _toggle_pause, true))
	box.add_child(UI.button("SETTINGS", _open_settings))
	box.add_child(UI.button("LEAVE MATCH", func(): arena.quit_match()))


func _toggle_pause() -> void:
	if _results and _results.visible:
		return
	_pause.visible = not _pause.visible
	if _pause.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_pause.get_child(1).get_child(3).grab_focus()
		UI.fade_in(_pause, 0.2, 0.0, Vector2.ZERO)
	elif arena.local_ship and arena.local_ship.alive and not App.is_mobile:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _open_settings() -> void:
	var p := SettingsPanel.new()
	p.compact = true
	root.add_child(p)
	p.closed.connect(func(): p.queue_free())


# --- Results ------------------------------------------------------------------------------------

func show_results(winner: int, xp: Dictionary) -> void:
	_pause.visible = false
	_death.visible = false
	_scoreboard.visible = false
	touch.visible = false
	_results = Control.new()
	_results.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_results)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.01, 0.03, 0.75)
	_results.add_child(shade)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-600, -330)
	box.size = Vector2(1200, 660)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	_results.add_child(box)
	var me := arena.local_ship
	var title := "DRAW"
	var col := Color.WHITE
	if winner >= 0:
		if me:
			title = "VICTORY" if winner == me.team else "DEFEAT"
			col = App.team_color(me.team) if winner == me.team else App.BAD
		else:
			title = "%s WINS" % App.TEAM_NAMES[winner]
			col = App.team_color(winner)
	var tl := UI.label(title, 130, col.lightened(0.15), "display")
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tl)
	var sc := UI.label("%s  %d   —   %d  %s" % [App.TEAM_NAMES[0], int(arena.ctl.scores[0]), int(arena.ctl.scores[1]), App.TEAM_NAMES[1]], 28, Color.WHITE, "display_semi")
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sc)
	if me:
		box.add_child(UI.vspacer(20))
		var stats := HBoxContainer.new()
		stats.alignment = BoxContainer.ALIGNMENT_CENTER
		stats.add_theme_constant_override("separation", 50)
		for pair in [["KILLS", me.kills], ["DEATHS", me.deaths], ["ASSISTS", me.assists], ["CAPTURES", me.captures], ["SCORE", me.score]]:
			var v := VBoxContainer.new()
			var n := UI.label(str(pair[1]), 54, Color.WHITE, "display")
			n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var c := UI.caption(pair[0], 14)
			c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(n)
			v.add_child(c)
			stats.add_child(v)
		box.add_child(stats)
		if not xp.is_empty():
			box.add_child(UI.vspacer(24))
			var xl := UI.label("+%d XP" % int(xp.xp_gain), 32, App.WARN, "display")
			xl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(xl)
			var bar := UI.stat_bar(float(xp.start_xp) / Profile.xp_for_level(int(xp.start_level)), App.WARN)
			bar.custom_minimum_size = Vector2(520, 10)
			bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			box.add_child(bar)
			var lv := UI.label("LEVEL %d  ·  %s" % [int(xp.level), Profile.rank_name()], 18, App.TEXT_DIM, "display_semi")
			lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(lv)
			get_tree().create_timer(0.8).timeout.connect(func():
				bar.value = float(xp.xp) / Profile.xp_for_level(int(xp.level)) if int(xp.level) == int(xp.start_level) else 1.0
				if int(xp.level) > int(xp.start_level):
					lv.text = "LEVEL UP!  %d  ·  %s" % [int(xp.level), Profile.rank_name()]
					lv.add_theme_color_override("font_color", App.WARN)
					Sfx.play("capture", 0.0, 1.2))
	box.add_child(UI.vspacer(30))
	var back := UI.button("RETURN TO HANGAR", func(): arena.quit_match() if not Net.is_online() else arena.leave_match_to_menu(), true)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(back)
	UI.fade_in(box, 0.8, 0.3)
	Sfx.play("capture" if me and winner == me.team else "explosion_small", 0.0, 0.7)
