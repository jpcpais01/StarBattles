extends "res://ui/menu/page.gd"
## Pre-battle lobby: two team columns, host can swap teams, pick the mode
## (Conquest or Mothership Siege) and launch.

var _cols: HBoxContainer
var _launch: Button
var _info: Label
var _modes: HBoxContainer


func _init() -> void:
	title_text = "BATTLE LOBBY"


func build() -> void:
	_info = UI.label("", 19, App.TEXT_DIM)
	content.add_child(_info)
	_modes = HBoxContainer.new()
	_modes.add_theme_constant_override("separation", 12)
	content.add_child(_modes)
	_cols = HBoxContainer.new()
	_cols.add_theme_constant_override("separation", 28)
	_cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_cols)
	var bottom := HBoxContainer.new()
	bottom.add_child(UI.button("LEAVE", func():
		Net.leave()
		close()))
	bottom.add_child(UI.hspacer())
	_launch = UI.button("LAUNCH BATTLE", func(): Net.start_match({"mode": Net.match_mode}), true)
	_launch.custom_minimum_size.x = 320
	bottom.add_child(_launch)
	content.add_child(bottom)
	Net.players_changed.connect(_refresh)
	Net.session_ended.connect(func(reason):
		_info.text = reason
		_info.add_theme_color_override("font_color", App.BAD))
	_refresh()


func _refresh() -> void:
	if not is_instance_valid(_cols):
		return
	if not Net.in_session:
		return
	_info.text = "%s  ·  %d pilots  ·  %s" % [Net.lobby_name, Net.players.size(),
		"You are hosting" if Net.is_host() else "Waiting for the host to launch"]
	_launch.visible = Net.is_host()
	var siege := Net.match_mode == "siege"
	for c in _modes.get_children():
		c.queue_free()
	_modes.add_child(UI.label("MODE", 18, App.TEXT_DIM, "display_semi"))
	for m in [["conquest", "CONQUEST"], ["siege", "MOTHERSHIP SIEGE"]]:
		var on: bool = Net.match_mode == m[0]
		if Net.is_host():
			var b := UI.button(m[1], Net.set_match_mode.bind(m[0]), on)
			_modes.add_child(b)
		elif on:
			_modes.add_child(UI.pill(m[1], App.ACCENT))
	if siege:
		_modes.add_child(UI.label("%s defends the %s, %s attacks it" % [App.TEAM_NAMES[SiegeRules.DEFENDERS], Mothership.DISPLAY_NAME, App.TEAM_NAMES[SiegeRules.ATTACKERS]], 16, App.TEXT_DIM))
	for c in _cols.get_children():
		c.queue_free()
	for t in 2:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		var p := UI.panel(v)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cols.add_child(p)
		var head: String = App.TEAM_NAMES[t]
		if siege:
			head += "  ·  " + ("DEFEND" if t == SiegeRules.DEFENDERS else "ATTACK")
		v.add_child(UI.label(head, 36, App.team_color(t), "display"))
		var count := 0
		for pid in Net.players.keys():
			var info: Dictionary = Net.players[pid]
			if int(info.team) != t:
				continue
			count += 1
			var row := HBoxContainer.new()
			var me: bool = pid == Net.my_id()
			row.add_child(UI.label(str(info.name) + ("  (YOU)" if me else ""), 22, App.WARN if me else Color.WHITE, "display_semi"))
			row.add_child(UI.label("LV %d · %s" % [int(info.get("level", 1)), ShipLibrary.ship(str(info.get("ship", "vanguard"))).name], 16, App.TEXT_DIM, "display_semi"))
			row.add_child(UI.hspacer())
			if Net.is_host():
				row.add_child(UI.button("SWAP", Net.swap_team.bind(pid)))
			v.add_child(row)
		for i in maxi(0, MatchController.TEAM_SIZE - count):
			if i >= 3:
				v.add_child(UI.label("+ %d more AI wingmen" % (MatchController.TEAM_SIZE - count - 3), 16, App.TEXT_DIM))
				break
			v.add_child(UI.label("AI wingman", 18, Color(1, 1, 1, 0.3)))


func close() -> void:
	super.close()
