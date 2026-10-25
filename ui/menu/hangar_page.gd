extends "res://ui/menu/page.gd"
## Ship selection. The 3D showcase behind the page swaps to the focused
## ship; stats, weapons and hardpoints are listed on the right.

signal ship_focused(id: String)

var _detail: VBoxContainer


func _init() -> void:
	title_text = "HANGAR"
	subtitle_text = "Pick your starfighter. Weapons are mounted on hardpoints and can be refitted in future updates."
	compact = false
	shade_alpha = 0.18


func build() -> void:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 24)
	content.add_child(row)
	var list := VBoxContainer.new()
	list.custom_minimum_size.x = 360
	list.add_theme_constant_override("separation", 12)
	row.add_child(list)
	for id in ShipLibrary.SHIP_ORDER:
		var d := ShipLibrary.ship(id)
		var b := UI.button("%s\n%s" % [d.name, d.role.to_upper()], _select.bind(id))
		b.custom_minimum_size = Vector2(360, 96)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = id == str(Profile.data.ship)
		b.focus_entered.connect(func(): _show(id))
		b.mouse_entered.connect(func(): _show(id))
		b.set_meta("id", id)
		list.add_child(b)
	row.add_child(UI.hspacer())
	_detail = VBoxContainer.new()
	_detail.custom_minimum_size.x = 520
	_detail.add_theme_constant_override("separation", 10)
	var p := UI.panel(_detail, 0.72)
	p.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(p)
	_show(str(Profile.data.ship))


func _show(id: String) -> void:
	ship_focused.emit(id)
	for c in _detail.get_children():
		c.queue_free()
	var d := ShipLibrary.ship(id)
	_detail.add_child(UI.label(d.name, 48, Color.WHITE, "display"))
	_detail.add_child(UI.label(d.role.to_upper(), 18, App.ACCENT, "display_semi"))
	var desc := UI.label(d.desc, 18, App.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(desc)
	_detail.add_child(UI.vspacer(8))
	for stat in ["speed", "agility", "armor", "firepower"]:
		var r := HBoxContainer.new()
		var l := UI.label(stat.to_upper(), 15, App.TEXT_DIM, "display_semi")
		l.custom_minimum_size.x = 130
		r.add_child(l)
		var bar := UI.stat_bar(d.stats[stat])
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.custom_minimum_size.y = 8
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(bar)
		_detail.add_child(r)
	_detail.add_child(UI.vspacer(8))
	_detail.add_child(UI.caption("Hardpoints"))
	var counts := {}
	for hp in d.hardpoints:
		counts[hp.weapon] = counts.get(hp.weapon, 0) + 1
	for w in counts.keys():
		_detail.add_child(UI.label("%d×  %s" % [counts[w], ShipLibrary.weapon(w).name], 19, Color.WHITE, "body", 500))
	_detail.add_child(UI.label("HULL %d  ·  SHIELD %d  ·  TOP SPEED %d M/S" % [int(d.hull), int(d.shield), int(d.boost_speed)], 15, App.TEXT_DIM, "display_semi"))


func _select(id: String) -> void:
	Profile.set_ship(id)
	Net.set_my_ship(id)
	for b in content.get_child(0).get_child(0).get_children():
		b.button_pressed = b.get_meta("id") == id
	_show(id)
