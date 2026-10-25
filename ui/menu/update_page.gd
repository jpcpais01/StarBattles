extends "res://ui/menu/page.gd"
## What's new in the available update, then a full download screen with a
## progress ring, transfer speed and ETA, and a one-tap install.

const Ring := preload("res://ui/kit/progress_ring.gd")

var _stack: Control
var _info_view: Control
var _dl_view: Control
var _ring: Control
var _pct: Label
var _bytes: Label
var _speed: Label
var _state: Label
var _action: Button
var _cancel: Button


func _init() -> void:
	title_text = "UPDATE"


func build() -> void:
	var l: Dictionary = Updater.latest
	subtitle_text = ""
	_stack = Control.new()
	_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_stack)
	_info_view = _build_info(l)
	_stack.add_child(_info_view)
	_dl_view = _build_download()
	_dl_view.visible = false
	_stack.add_child(_dl_view)
	Updater.download_progress.connect(_on_progress)
	Updater.download_finished.connect(_on_finished)
	if Updater.downloading:
		_show_download()


func _build_info(l: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 32)
	# Left: version jump + actions.
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 520
	left.add_theme_constant_override("separation", 14)
	row.add_child(UI.panel(left))
	left.add_child(UI.caption("New version available" if Updater.available else "You're up to date"))
	var jump := HBoxContainer.new()
	jump.add_theme_constant_override("separation", 18)
	jump.add_child(UI.label(App.version_label(), 40, App.TEXT_DIM, "display_semi"))
	jump.add_child(UI.label("›", 40, App.ACCENT, "display"))
	jump.add_child(UI.label("v%s" % str(l.get("version", App.version)), 64, Color.WHITE, "display"))
	left.add_child(jump)
	var name_l := UI.label(str(l.get("name", "")), 22, App.TEXT, "body", 600)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(name_l)
	var meta := PackedStringArray()
	if int(l.get("asset_size", 0)) > 0:
		meta.append(_mb(int(l.asset_size)))
	var pub := str(l.get("published", ""))
	if pub.length() >= 10:
		meta.append("Released " + pub.substr(0, 10))
	left.add_child(UI.label("  ·  ".join(meta), 18, App.TEXT_DIM, "display_semi"))
	left.add_child(UI.vspacer())
	if Updater.available:
		if Updater.platform_supported() and str(l.get("asset_url", "")) != "":
			var b := UI.button("DOWNLOAD & INSTALL", _start, true)
			b.custom_minimum_size.y = 72
			left.add_child(b)
			var hint := UI.label("Your pilot profile and settings are kept." + ("\nAndroid will ask you to confirm the install." if OS.has_feature("android") else "\nThe game restarts automatically."), 16, App.TEXT_DIM)
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			left.add_child(hint)
			b.grab_focus.call_deferred()
		else:
			left.add_child(UI.button("OPEN RELEASE PAGE", func(): OS.shell_open(str(l.get("html_url", "https://github.com/%s/releases/latest" % App.REPO))), true))
	# Right: release notes.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rp := UI.panel(right, 0.7)
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(rp)
	right.add_child(UI.caption("What's new"))
	var notes := RichTextLabel.new()
	notes.bbcode_enabled = true
	notes.fit_content = false
	notes.scroll_active = true
	notes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var md := str(l.get("notes", "")).strip_edges()
	notes.text = Updater.markdown_to_bbcode(md) if md != "" else "[color=#8890a0]No release notes.[/color]"
	right.add_child(notes)
	return row


func _build_download() -> Control:
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	var ring_box := Control.new()
	ring_box.custom_minimum_size = Vector2(380, 380)
	ring_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ring_box)
	_ring = Ring.new()
	_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ring.indeterminate = true
	ring_box.add_child(_ring)
	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 0)
	ring_box.add_child(center)
	_pct = UI.label("0%", 84, Color.WHITE, "display")
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_pct)
	_state = UI.caption("Downloading")
	_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_state)
	var title := UI.label("Star Battles v%s" % str(Updater.latest.get("version", "")), 30, Color.WHITE, "display_semi")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_bytes = UI.label("", 20, App.TEXT, "display_semi")
	_bytes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_bytes)
	_speed = UI.label("", 18, App.TEXT_DIM, "display_semi")
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_speed)
	v.add_child(UI.vspacer(16))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 18)
	_cancel = UI.button("CANCEL", _cancel_download)
	_cancel.custom_minimum_size = Vector2(220, 64)
	buttons.add_child(_cancel)
	_action = UI.button("INSTALL NOW", _install, true)
	_action.custom_minimum_size = Vector2(300, 64)
	_action.visible = false
	buttons.add_child(_action)
	v.add_child(buttons)
	return v


func _show_download() -> void:
	_info_view.visible = false
	_dl_view.visible = true
	UI.fade_in(_dl_view, 0.35, 0.0, Vector2.ZERO)
	_cancel.grab_focus.call_deferred()


func _start() -> void:
	_show_download()
	_ring.indeterminate = true
	_action.visible = false
	_cancel.visible = true
	_state.text = UI.spaced("Connecting")
	Updater.start_download()


func _cancel_download() -> void:
	Updater.cancel_download()
	_dl_view.visible = false
	_info_view.visible = true


func _on_progress(done: int, total: int, speed: float) -> void:
	if not is_instance_valid(_ring):
		return
	_state.text = UI.spaced("Downloading")
	if total > 0:
		_ring.indeterminate = false
		_ring.value = float(done) / float(total)
		_pct.text = "%d%%" % int(_ring.value * 100.0)
		_bytes.text = "%s  /  %s" % [_mb(done), _mb(total)]
		if speed > 1.0:
			var eta := float(total - done) / speed
			_speed.text = "%s/s  ·  %s remaining" % [_mb(int(speed)), _eta(eta)]
	else:
		_bytes.text = _mb(done)


func _on_finished(ok: bool, msg: String) -> void:
	if not is_instance_valid(_ring):
		return
	_ring.indeterminate = false
	if ok:
		_ring.value = 1.0
		_ring.color = App.GOOD
		_pct.text = "100%"
		_state.text = UI.spaced("Ready to install")
		_speed.text = "Download verified."
		_cancel.visible = false
		_action.visible = true
		_action.grab_focus()
		Sfx.ui("capture")
	else:
		_ring.color = App.BAD
		_state.text = UI.spaced("Failed")
		_speed.text = msg
		_cancel.text = "BACK"
		Sfx.ui("ui_error")


func _install() -> void:
	_state.text = UI.spaced("Installing")
	if not Updater.install():
		_speed.text = "Opened the release page in your browser."


func close() -> void:
	if Updater.downloading:
		# Keep downloading in the background; the banner tracks it.
		pass
	super.close()


static func _mb(b: int) -> String:
	if b >= 1048576:
		return "%.1f MB" % (float(b) / 1048576.0)
	return "%d KB" % int(float(b) / 1024.0)


static func _eta(s: float) -> String:
	if s < 60.0:
		return "%ds" % int(ceil(s))
	return "%dm %02ds" % [int(s) / 60, int(s) % 60]
