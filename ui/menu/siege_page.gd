extends "res://ui/menu/page.gd"
## Mothership Siege briefing: the IRON VANGUARD hangs in the backdrop while
## you read how the siege plays out and pick a side.

signal capital_focused(on: bool)

const STAGES := [
	["SHIELD GENERATORS", "Four generators on the hull power a bubble that makes the carrier untouchable. Knock them all out."],
	["ARMOR", "With the shield down, every hit on the hull counts. Breaches erupt as the armour fails."],
	["REACTOR", "The core's shutters blow open. Destroy it and the IRON VANGUARD tears itself apart."],
]


func _init() -> void:
	title_text = "MOTHERSHIP SIEGE"
	subtitle_text = "A 1.5 km carrier, sixteen turrets and a shield bubble. One side brings it down, the other keeps it alive."
	shade_alpha = 0.12


func build() -> void:
	capital_focused.emit.call_deferred(true)
	content.add_child(UI.vspacer(0))
	var col := VBoxContainer.new()
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 16)
	content.add_child(col)
	var steps := VBoxContainer.new()
	steps.add_theme_constant_override("separation", 12)
	steps.custom_minimum_size.x = 640
	for i in STAGES.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var n := UI.label(str(i + 1), 44, App.team_color(SiegeRules.ATTACKERS).lightened(0.2), "display")
		n.custom_minimum_size.x = 36
		row.add_child(n)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UI.label(STAGES[i][0], 22, Color.WHITE, "display_semi"))
		var d := UI.label(STAGES[i][1], 16, App.TEXT_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)
		row.add_child(v)
		steps.add_child(row)
	var note := UI.label("Attackers share %d reinforcements (more when a stage falls). Defenders win if the clock runs out or the attack runs dry." % SiegeRules.TICKETS, 15, App.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	steps.add_child(note)
	var sp := UI.panel(steps, 0.72)
	sp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(sp)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 18)
	col.add_child(buttons)
	buttons.add_child(_side_button(SiegeRules.ATTACKERS, "ATTACK", "Fly with %s and break the carrier" % App.TEAM_NAMES[SiegeRules.ATTACKERS]))
	buttons.add_child(_side_button(SiegeRules.DEFENDERS, "DEFEND", "Fly with %s and hold the line" % App.TEAM_NAMES[SiegeRules.DEFENDERS]))


func _side_button(team: int, verb: String, sub: String) -> Button:
	var tint := App.team_color(team)
	var b := Button.new()
	b.custom_minimum_size = Vector2(310, 110)
	b.add_theme_stylebox_override("normal", UI.pill_box(tint, 0.16))
	b.add_theme_stylebox_override("hover", UI.pill_box(tint, 0.34))
	b.add_theme_stylebox_override("focus", UI.pill_box(tint, 0.34))
	b.add_theme_stylebox_override("pressed", UI.pill_box(tint, 0.5))
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 26
	v.offset_right = -20
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -2)
	var t := UI.label(verb, 40, tint.lightened(0.35), "display")
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var s := UI.label(sub, 15, App.TEXT, "body", 500)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(s)
	b.add_child(v)
	b.pressed.connect(func():
		Sfx.ui("ui_select")
		if App.transitioning:
			return
		Net.leave()
		Net.start_match({"mode": "siege", "team": team}))
	return b


func close() -> void:
	capital_focused.emit(false)
	super.close()
