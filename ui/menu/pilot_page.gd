extends "res://ui/menu/page.gd"
## Pilot profile: callsign, rank and career stats, plus the cloud account
## (guest or email). Guest accounts upgrade in place, keeping progress.

var _account: VBoxContainer
var _status: Label
var _email: LineEdit
var _pass: LineEdit
var _busy := false


func _init() -> void:
	title_text = "PILOT"
	subtitle_text = "Your career follows you to any device once you sign in."


func build() -> void:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 28)
	content.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 14)
	var lp := UI.panel(left)
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(lp)
	_build_career(left)
	_account = VBoxContainer.new()
	_account.custom_minimum_size.x = 560
	_account.add_theme_constant_override("separation", 12)
	var ap := UI.panel(_account)
	ap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(ap)
	Firebase.auth_changed.connect(func(_s): _build_account())
	_build_account()


func _build_career(v: VBoxContainer) -> void:
	v.add_child(UI.caption("Callsign"))
	var name_row := HBoxContainer.new()
	var name_edit := LineEdit.new()
	name_edit.text = Profile.callsign() if Profile.has_callsign() else ""
	name_edit.placeholder_text = "PILOT"
	name_edit.max_length = 16
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_override("font", UI.font("display"))
	name_edit.add_theme_font_size_override("font_size", 34)
	name_row.add_child(name_edit)
	var save := UI.button("SAVE", func():
		var n := name_edit.text.strip_edges()
		if n.length() >= 2:
			Profile.set_callsign(n)
			_toast("Callsign updated."))
	name_row.add_child(save)
	name_edit.text_submitted.connect(func(_t): save.pressed.emit())
	v.add_child(name_row)
	v.add_child(UI.vspacer(6))
	var rank := HBoxContainer.new()
	rank.add_theme_constant_override("separation", 18)
	var lvl := UI.label(str(int(Profile.data.level)), 72, Color.WHITE, "display")
	rank.add_child(lvl)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rv.add_child(UI.label(Profile.rank_name(), 26, App.ACCENT, "display"))
	var bar := UI.stat_bar(Profile.level_progress())
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size.y = 10
	rv.add_child(bar)
	rv.add_child(UI.label("%d / %d XP to level %d" % [int(Profile.data.xp), Profile.xp_for_level(int(Profile.data.level)), int(Profile.data.level) + 1], 16, App.TEXT_DIM, "display_semi"))
	rank.add_child(rv)
	v.add_child(rank)
	v.add_child(UI.vspacer(10))
	v.add_child(UI.caption("Career"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	v.add_child(grid)
	var d: Dictionary = Profile.data
	var win_rate := float(d.wins) / maxf(1.0, float(d.matches)) * 100.0
	for s in [["BATTLES", str(int(d.matches))], ["WIN RATE", "%d%%" % int(win_rate)], ["K / D", "%.2f" % Profile.kd()], ["KILLS", str(int(d.kills))],
			["ASSISTS", str(int(d.assists))], ["CAPTURES", str(int(d.captures))], ["BEST STREAK", str(int(d.best_streak))], ["VICTORIES", str(int(d.wins))]]:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(UI.label(s[1], 40, Color.WHITE, "display"))
		cell.add_child(UI.caption(s[0], 13))
		var box := PanelContainer.new()
		var sb := UI.panel_box(0.0, 14)
		sb.bg_color = Color(1, 1, 1, 0.04)
		sb.shadow_size = 0
		sb.content_margin_left = 18
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		box.add_theme_stylebox_override("panel", sb)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(cell)
		grid.add_child(box)


func _build_account() -> void:
	if not is_instance_valid(_account):
		return
	for c in _account.get_children():
		c.queue_free()
	_account.add_child(UI.caption("Account"))
	if not Firebase.is_configured():
		var l := UI.label("Cloud saves aren't enabled in this build. Your progress is stored on this device.", 19, App.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_account.add_child(l)
		return
	if Firebase.is_signed_in() and not Firebase.is_anonymous:
		_account.add_child(UI.pill("SIGNED IN · CLOUD SYNC ON", App.GOOD))
		_account.add_child(UI.label(Firebase.email, 26, Color.WHITE, "display_semi"))
		var l := UI.label("Your profile and settings sync automatically after every battle.", 18, App.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_account.add_child(l)
		_account.add_child(UI.vspacer())
		_account.add_child(UI.button("SYNC NOW", func():
			await Profile.pull_cloud()
			_toast("Profile synced.")))
		_account.add_child(UI.button("SIGN OUT", func(): Firebase.sign_out()))
		_status = UI.label("", 18, App.GOOD)
		_account.add_child(_status)
		return
	if Firebase.is_signed_in():
		_account.add_child(UI.pill("GUEST · SAVED TO THIS DEVICE'S ACCOUNT", App.WARN))
		var g := UI.label("Add an email to keep your guest progress forever and use it on other devices.", 18, App.TEXT_DIM)
		g.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_account.add_child(g)
	else:
		var g := UI.label("Sign in to back up your career and appear in public battles.", 18, App.TEXT_DIM)
		g.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_account.add_child(g)
	_email = LineEdit.new()
	_email.placeholder_text = "Email"
	_email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	_account.add_child(_email)
	_pass = LineEdit.new()
	_pass.placeholder_text = "Password (6+ characters)"
	_pass.secret = true
	_pass.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	_account.add_child(_pass)
	var r := HBoxContainer.new()
	var signin := UI.button("SIGN IN", _do.bind("in"), true)
	signin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(signin)
	var signup := UI.button("SAVE PROGRESS" if Firebase.is_signed_in() else "CREATE ACCOUNT", _do.bind("up"))
	signup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(signup)
	_account.add_child(r)
	_account.add_child(UI.button("FORGOT PASSWORD", _do.bind("reset")))
	if not Firebase.is_signed_in():
		_account.add_child(UI.button("CONTINUE AS GUEST", _do.bind("guest")))
	_status = UI.label("", 18, App.WARN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_account.add_child(_status)


func _do(kind: String) -> void:
	if _busy:
		return
	var mail := _email.text.strip_edges() if _email else ""
	var pw := _pass.text if _pass else ""
	if kind in ["in", "up", "reset"] and not mail.contains("@"):
		_err("Enter a valid email address.")
		return
	if kind in ["in", "up"] and pw.length() < 6:
		_err("Passwords need at least 6 characters.")
		return
	_busy = true
	_status.add_theme_color_override("font_color", App.TEXT_DIM)
	_status.text = "Contacting command…"
	var r: Dictionary
	match kind:
		"in":
			r = await Firebase.sign_in(mail, pw)
		"up":
			r = await Firebase.sign_up(mail, pw)
		"reset":
			r = await Firebase.send_password_reset(mail)
		"guest":
			r = await Firebase.sign_in_guest()
	_busy = false
	if not is_instance_valid(_status):
		return
	if not r.get("ok", false):
		_err(str(r.get("error", "Something went wrong.")))
		return
	if kind == "reset":
		_toast("Reset link sent to %s." % mail)
		return
	await Profile.pull_cloud()
	Profile.push_cloud()


func _err(msg: String) -> void:
	if is_instance_valid(_status):
		_status.add_theme_color_override("font_color", App.BAD)
		_status.text = msg
	Sfx.ui("ui_error")


func _toast(msg: String) -> void:
	if is_instance_valid(_status):
		_status.add_theme_color_override("font_color", App.GOOD)
		_status.text = msg
