extends Node
## In-game updater. Reads the latest GitHub release, compares it with the
## running build, downloads the platform asset with live progress, then
## hands off to the Android package installer or swaps the Windows .exe.

signal checked(available: bool)
signal download_progress(downloaded: int, total: int, speed: float)
signal download_finished(ok: bool, message: String)

const API := "https://api.github.com/repos/%s/releases/latest"

var available := false
var checking := false
var downloading := false
## {version, name, notes, published, url, asset_url, asset_size, html_url}
var latest: Dictionary = {}
var download_path := ""
var _http: HTTPRequest
var _speed_samples: Array = []
var _last_bytes := 0
var _last_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func platform_supported() -> bool:
	return OS.has_feature("android") or OS.has_feature("windows")


func asset_extension() -> String:
	if OS.has_feature("android"):
		return ".apk"
	if OS.has_feature("windows"):
		return ".exe"
	return ""


func check() -> void:
	if checking or OS.has_feature("editor"):
		return
	checking = true
	var http := HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	var err := http.request(API % App.REPO, PackedStringArray(["User-Agent: StarBattles-Game", "Accept: application/vnd.github+json"]))
	if err != OK:
		http.queue_free()
		checking = false
		checked.emit(false)
		return
	var res: Array = await http.request_completed
	http.queue_free()
	checking = false
	if res[0] != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		checked.emit(false)
		return
	var d = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if not d is Dictionary:
		checked.emit(false)
		return
	var tag := str(d.get("tag_name", "")).trim_prefix("v")
	latest = {
		"version": tag,
		"name": str(d.get("name", tag)),
		"notes": str(d.get("body", "")),
		"published": str(d.get("published_at", "")),
		"html_url": str(d.get("html_url", "")),
		"asset_url": "",
		"asset_size": 0,
	}
	var ext := asset_extension()
	for a in d.get("assets", []):
		if ext != "" and str(a.get("name", "")).to_lower().ends_with(ext):
			latest.asset_url = str(a.get("browser_download_url", ""))
			latest.asset_size = int(a.get("size", 0))
	available = tag != "" and App.compare_versions(tag, App.version) > 0
	checked.emit(available)


func start_download() -> void:
	if downloading or str(latest.get("asset_url", "")) == "":
		download_finished.emit(false, "No download available for this platform.")
		return
	DirAccess.make_dir_recursive_absolute("user://update")
	download_path = "user://update/StarBattles-%s%s" % [latest.version, asset_extension()]
	if FileAccess.file_exists(download_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(download_path))
	_http = HTTPRequest.new()
	_http.download_file = download_path
	_http.download_chunk_size = 262144
	_http.use_threads = true
	_http.max_redirects = 10
	add_child(_http)
	_http.request_completed.connect(_on_download_done)
	var err := _http.request(str(latest.asset_url), PackedStringArray(["User-Agent: StarBattles-Game"]))
	if err != OK:
		_http.queue_free()
		download_finished.emit(false, "Could not start the download.")
		return
	downloading = true
	_last_bytes = 0
	_last_time = Time.get_ticks_msec() / 1000.0
	_speed_samples.clear()
	set_process(true)


func cancel_download() -> void:
	if _http:
		_http.cancel_request()
		_http.queue_free()
		_http = null
	downloading = false
	set_process(false)


func _process(_delta: float) -> void:
	if _http == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var bytes := _http.get_downloaded_bytes()
	var total := _http.get_body_size()
	if total <= 0:
		total = int(latest.get("asset_size", 0))
	if now - _last_time >= 0.25:
		_speed_samples.append(float(bytes - _last_bytes) / (now - _last_time))
		if _speed_samples.size() > 8:
			_speed_samples.pop_front()
		_last_bytes = bytes
		_last_time = now
	var speed := 0.0
	for s in _speed_samples:
		speed += s
	if _speed_samples.size() > 0:
		speed /= _speed_samples.size()
	download_progress.emit(bytes, total, speed)


func _on_download_done(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	downloading = false
	set_process(false)
	if _http:
		_http.queue_free()
		_http = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		download_finished.emit(false, "Download failed (%d / %d)." % [result, code])
		return
	download_finished.emit(true, "Download complete.")


## Launches the platform installer. Returns false if it had to fall back
## to opening the release page in the browser.
func install() -> bool:
	var abs_path := ProjectSettings.globalize_path(download_path)
	if OS.has_feature("android"):
		var err := OS.shell_open(abs_path)
		if err != OK:
			OS.shell_open(str(latest.get("html_url", "https://github.com/%s/releases/latest" % App.REPO)))
			return false
		return true
	if OS.has_feature("windows"):
		var exe := OS.get_executable_path()
		var bat := ProjectSettings.globalize_path("user://update/apply_update.bat")
		var pid := OS.get_process_id()
		var script := "@echo off\r\n" \
			+ "title Star Battles Updater\r\n" \
			+ ":wait\r\n" \
			+ "tasklist /FI \"PID eq %d\" 2>nul | find \"%d\" >nul && (timeout /t 1 /nobreak >nul & goto wait)\r\n" % [pid, pid] \
			+ "copy /y \"%s\" \"%s\" >nul\r\n" % [abs_path.replace("/", "\\"), exe.replace("/", "\\")] \
			+ "start \"\" \"%s\"\r\n" % exe.replace("/", "\\") \
			+ "del \"%s\"\r\n" % abs_path.replace("/", "\\") \
			+ "(goto) 2>nul & del \"%~f0\"\r\n"
		var f := FileAccess.open("user://update/apply_update.bat", FileAccess.WRITE)
		if f == null:
			return false
		f.store_string(script)
		f.close()
		OS.create_process("cmd.exe", ["/c", bat], false)
		get_tree().quit()
		return true
	OS.shell_open(str(latest.get("html_url", "")))
	return false


## Converts GitHub-flavoured release markdown into BBCode for RichTextLabel.
static func markdown_to_bbcode(md: String) -> String:
	var out := PackedStringArray()
	for raw in md.replace("\r", "").split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("### "):
			out.append("[font_size=24][color=#9fdcff]%s[/color][/font_size]" % line.substr(4))
		elif line.begins_with("## "):
			out.append("[font_size=28][b]%s[/b][/font_size]" % line.substr(3))
		elif line.begins_with("# "):
			out.append("[font_size=32][b]%s[/b][/font_size]" % line.substr(2))
		elif line.begins_with("- ") or line.begins_with("* "):
			out.append("  [color=#6fd0ff]•[/color]  %s" % _inline(line.substr(2)))
		else:
			out.append(_inline(line))
	return "\n".join(out)


static func _inline(s: String) -> String:
	var re := RegEx.new()
	re.compile("\\*\\*(.+?)\\*\\*")
	s = re.sub(s, "[b]$1[/b]", true)
	re.compile("`(.+?)`")
	s = re.sub(s, "[code]$1[/code]", true)
	return s
