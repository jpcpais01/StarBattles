extends "res://ui/menu/page.gd"
## Player-facing patch notes, grouped by the hour each update shipped.

const PATH := "res://data/patch_notes.json"


func _init() -> void:
	title_text = "PATCH NOTES"
	subtitle_text = "Every update, newest first."


static func load_groups() -> Array:
	if not FileAccess.file_exists(PATH):
		return []
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if d is Dictionary:
		d = d.get("groups", [])
	return d if d is Array else []


func build() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)
	var groups := load_groups()
	if groups.is_empty():
		col.add_child(UI.label("No notes yet.", 20, App.TEXT_DIM))
		return
	for i in groups.size():
		var g: Dictionary = groups[i]
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)
		var p := UI.panel(v, 0.74 if i == 0 else 0.6)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(p)
		var head := HBoxContainer.new()
		head.add_child(UI.label(str(g.get("title", "Update")), 30, Color.WHITE, "display"))
		if i == 0:
			head.add_child(UI.pill("LATEST", App.GOOD))
		head.add_child(UI.hspacer())
		head.add_child(UI.label(str(g.get("time", "")), 17, App.TEXT_DIM, "display_semi"))
		v.add_child(head)
		for e in g.get("entries", []):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 14)
			var dot := UI.label("•", 22, App.ACCENT, "display")
			dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			row.add_child(dot)
			var t := UI.label(str(e), 20, App.TEXT)
			t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(t)
			v.add_child(row)
		UI.fade_in(p, 0.35, 0.05 * i, Vector2.ZERO)
