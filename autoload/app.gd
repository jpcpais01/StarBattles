extends Node
## Global app services: build info, platform flags, scene routing with
## cinematic fades, and the shared palette used by UI and gameplay.

signal scene_change_started(path: String)
signal scene_change_finished(path: String)

const REPO := "jpcpais01/StarBattles"
const GAME_TITLE := "STAR BATTLES"

const TEAM_NAMES := ["AEGIS", "KRONOS"]
const TEAM_COLORS := [Color(0.27, 0.72, 1.0), Color(1.0, 0.44, 0.22)]
const ACCENT := Color(0.42, 0.82, 1.0)
const TEXT := Color(0.93, 0.95, 1.0)
const TEXT_DIM := Color(0.58, 0.63, 0.74)
const GOOD := Color(0.42, 1.0, 0.72)
const WARN := Color(1.0, 0.78, 0.3)
const BAD := Color(1.0, 0.36, 0.36)

const SCENE_BOOT := "res://scenes/boot.tscn"
const SCENE_MENU := "res://scenes/menu.tscn"
const SCENE_ARENA := "res://scenes/arena.tscn"

var version := "0.1.0"
var build := 0
var commit := "dev"
var build_date := ""
var is_mobile := false
var is_dedicated := false
var autotest_seconds := 0.0
## Autotest only: join this host instead of starting a local battle.
var autotest_join := ""
## Command line only: game mode for autotest / dedicated hosts ("" = default).
var cli_mode := ""
## Command line only: team for the local pilot in an autotest (-1 = default).
var cli_team := -1
## Config for the next match, read by the arena when it loads.
var match_config: Dictionary = {}
var current_scene_path := ""
var transitioning := false

var _layer: CanvasLayer
var _fade: ColorRect
var _spinner: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	version = str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	_load_build_info()
	is_mobile = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	is_dedicated = args.has("--server") or OS.has_feature("dedicated_server")
	for a in args:
		if a.begins_with("--autotest"):
			autotest_seconds = 25.0
			var parts := a.split("=")
			if parts.size() > 1:
				autotest_seconds = float(parts[1])
		elif a.begins_with("--join="):
			autotest_join = a.get_slice("=", 1)
		elif a.begins_with("--mode="):
			cli_mode = a.get_slice("=", 1)
		elif a.begins_with("--team="):
			cli_team = int(a.get_slice("=", 1))
	_build_fade_layer()
	get_tree().auto_accept_quit = true
	get_tree().quit_on_go_back = false


func _load_build_info() -> void:
	var path := "res://config/build_info.json"
	if not FileAccess.file_exists(path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		version = str(data.get("version", version))
		build = int(data.get("build", 0))
		commit = str(data.get("commit", "dev"))
		build_date = str(data.get("date", ""))


func version_label() -> String:
	return "v%s" % version


func _build_fade_layer() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 120
	add_child(_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.008, 0.01, 0.02, 1.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_layer.add_child(_fade)
	_spinner = preload("res://ui/kit/spinner.gd").new()
	_spinner.set_anchors_preset(Control.PRESET_CENTER)
	_spinner.custom_minimum_size = Vector2(64, 64)
	_spinner.position = Vector2(-32, -32)
	_spinner.modulate.a = 0.0
	_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.add_child(_spinner)


## Fade to black, load the target scene on a worker thread (keeps the
## spinner animating), swap it in, wait until it reports ready, fade back.
func goto_scene(path: String, fade_time := 0.45) -> void:
	if transitioning:
		return
	transitioning = true
	scene_change_started.emit(path)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, fade_time).set_trans(Tween.TRANS_SINE)
	await tw.finished
	_spinner.modulate.a = 1.0
	ResourceLoader.load_threaded_request(path, "PackedScene", true)
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(path) as PackedScene
	if packed == null:
		push_error("Failed to load scene %s" % path)
		transitioning = false
		_spinner.modulate.a = 0.0
		_fade.modulate.a = 0.0
		return
	get_tree().change_scene_to_packed(packed)
	await get_tree().process_frame
	await get_tree().process_frame
	var scene := get_tree().current_scene
	if scene and scene.has_signal("scene_ready") and not scene.get("is_scene_ready"):
		await scene.scene_ready
	current_scene_path = path
	_spinner.modulate.a = 0.0
	var tw2 := create_tween()
	tw2.tween_property(_fade, "modulate:a", 0.0, fade_time * 1.4).set_trans(Tween.TRANS_SINE)
	await tw2.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transitioning = false
	scene_change_finished.emit(path)


func flash(color: Color, time := 0.25) -> void:
	_fade.color = color
	_fade.modulate.a = 0.6
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 0.0, time)
	tw.tween_callback(func(): _fade.color = Color(0.008, 0.01, 0.02, 1.0))


static func team_color(team: int) -> Color:
	if team < 0 or team > 1:
		return Color(0.85, 0.88, 0.95)
	return TEAM_COLORS[team]


static func format_time(seconds: float) -> String:
	var s := maxi(0, int(ceil(seconds)))
	return "%d:%02d" % [s / 60, s % 60]


## Compare dotted versions. Returns 1 if a > b, -1 if a < b, 0 if equal.
static func compare_versions(a: String, b: String) -> int:
	var pa := a.trim_prefix("v").split(".")
	var pb := b.trim_prefix("v").split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0
