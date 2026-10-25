extends SceneTree
## CI helper: loads every GDScript and shader so parse errors fail the build.

func _init() -> void:
	# Autoloads only exist once the tree has started.
	process_frame.connect(_check, CONNECT_ONE_SHOT)


func _check() -> void:
	var failed := 0
	for path in _walk("res://"):
		if path.ends_with(".gd") or path.ends_with(".gdshader"):
			var res := load(path)
			if res == null:
				printerr("FAILED: ", path)
				failed += 1
			elif res is GDScript and not (res as GDScript).can_instantiate() and not path.ends_with("check_scripts.gd"):
				printerr("FAILED: ", path)
				failed += 1
	print("Checked scripts: %d failure(s)" % failed)
	quit(1 if failed > 0 else 0)


func _walk(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		out.append(dir.path_join(f))
	for sub in d.get_directories():
		if sub.begins_with(".") or sub == "addons":
			continue
		out.append_array(_walk(dir.path_join(sub)))
	return out
