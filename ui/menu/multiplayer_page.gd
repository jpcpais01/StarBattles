extends "res://ui/menu/page.gd"
## Host or join online battles: LAN discovery, the public lobby list
## (Firestore) and direct IP join. Empty slots are always filled by AI.

signal open_lobby

var _list: VBoxContainer
var _ip: LineEdit
var _status: Label
var _name: LineEdit


func _init() -> void:
	title_text = "MULTIPLAYER"
	subtitle_text = "10 v 10 Conquest. Up to 20 pilots; AI wingmen fill the empty seats."


func build() -> void:
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cols)
	# Left: host + direct join.
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 520
	left.add_theme_constant_override("separation", 14)
	cols.add_child(UI.panel(left))
	left.add_child(UI.caption("Host a battle"))
	_name = LineEdit.new()
	_name.placeholder_text = "%s's Battle" % Profile.callsign()
	_name.max_length = 28
	left.add_child(_name)
	var host := UI.button("HOST BATTLE", _host, true)
	left.add_child(host)
	var note := UI.label("Friends on your Wi-Fi see it automatically. For internet play, forward UDP port %d on your router." % Net.PORT, 16, App.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(note)
	left.add_child(UI.vspacer(16))
	left.add_child(UI.caption("Join by address"))
	var row := HBoxContainer.new()
	_ip = LineEdit.new()
	_ip.placeholder_text = "192.168.1.20  or  host:port"
	_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_ip)
	row.add_child(UI.button("JOIN", func(): _join_text(_ip.text)))
	left.add_child(row)
	_status = UI.label("", 18, App.WARN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_status)
	# Right: discovered servers.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	var rp := UI.panel(right)
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(rp)
	var head := HBoxContainer.new()
	head.add_child(UI.caption("Open battles"))
	head.add_child(UI.hspacer())
	head.add_child(UI.button("REFRESH", func(): Net.refresh_online()))
	right.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	Net.servers_changed.connect(_refresh)
	Net.connection_failed.connect(_on_fail)
	Net.connection_succeeded.connect(_on_joined)
	Net.start_listening()
	_refresh()


func _exit_tree() -> void:
	Net.stop_listening()


func _refresh() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	var entries := []
	for ip in Net.lan_servers.keys():
		var d: Dictionary = Net.lan_servers[ip]
		entries.append({"name": d.get("name", "Battle"), "ip": ip, "port": int(d.get("port", Net.PORT)), "players": int(d.get("players", 0)),
			"max": int(d.get("max", 20)), "tag": "LAN", "version": str(d.get("version", "")), "in_match": d.get("in_match", false)})
	for d in Net.online_servers:
		entries.append({"name": d.get("name", "Battle"), "ip": d.get("ip", ""), "port": int(d.get("port", Net.PORT)), "players": int(d.get("players", 0)),
			"max": int(d.get("max", 20)), "tag": "ONLINE", "version": str(d.get("version", "")), "in_match": d.get("in_match", false)})
	if entries.is_empty():
		var empty := UI.label("Scanning for battles…\nHost one, or ask a friend for their address." if Firebase.is_signed_in() or true else "", 19, App.TEXT_DIM)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(UI.margin(empty, 0, 40, 0, 0))
		if not Firebase.is_signed_in():
			var hint := UI.label("Sign in on the Pilot page to see public internet battles.", 16, App.TEXT_DIM)
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_list.add_child(hint)
		return
	for e in entries:
		var b := Button.new()
		b.custom_minimum_size.y = 76
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var compatible: bool = e.version == App.version
		b.disabled = not compatible
		var h := HBoxContainer.new()
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 18
		h.offset_right = -18
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tag := UI.pill(e.tag, App.ACCENT if e.tag == "LAN" else App.GOOD)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(tag)
		var n := UI.label(str(e.name), 24, Color.WHITE, "display_semi")
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(n)
		var info := UI.label(("IN BATTLE · " if e.in_match else "") + "%d / %d" % [e.players, e.max] + ("" if compatible else "  ·  v" + e.version), 18, App.TEXT_DIM, "display_semi")
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(info)
		b.add_child(h)
		b.pressed.connect(func():
			Sfx.ui("ui_select")
			_join(str(e.ip), int(e.port)))
		_list.add_child(b)


func _host() -> void:
	var err := Net.host_game(_name.text.strip_edges(), true)
	if err != OK:
		_status.text = "Couldn't open port %d (error %d). Is another game hosting?" % [Net.PORT, err]
		Sfx.ui("ui_error")
		return
	open_lobby.emit()
	close()


func _join_text(t: String) -> void:
	t = t.strip_edges()
	if t == "":
		_status.text = "Enter the host's address."
		return
	var port := Net.PORT
	if t.contains(":"):
		port = int(t.get_slice(":", 1))
		t = t.get_slice(":", 0)
	_join(t, port)


func _join(ip: String, port: int) -> void:
	_status.add_theme_color_override("font_color", App.TEXT)
	_status.text = "Connecting to %s…" % ip
	if Net.join_game(ip, port) != OK:
		_on_fail("Invalid address.")


func _on_fail(reason: String) -> void:
	_status.add_theme_color_override("font_color", App.BAD)
	_status.text = reason
	Sfx.ui("ui_error")


func _on_joined() -> void:
	open_lobby.emit()
	close()
