extends Node
## Pilot profile: callsign, progression and career stats. Always saved
## locally; mirrored to Firestore (players/{uid}) when signed in. On sign-in
## the richer of local/cloud wins so no progress is ever lost.

signal changed
signal level_up(new_level: int)

const PATH := "user://profile.json"

var data := {
	"name": "",
	"xp": 0,
	"level": 1,
	"kills": 0,
	"deaths": 0,
	"assists": 0,
	"wins": 0,
	"losses": 0,
	"matches": 0,
	"captures": 0,
	"best_streak": 0,
	"ship": "vanguard",
	"created": 0,
}
var syncing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_local()
	if int(data.created) == 0:
		data.created = int(Time.get_unix_time_from_system())


func callsign() -> String:
	return str(data.name) if str(data.name) != "" else "PILOT"


func has_callsign() -> bool:
	return str(data.name).strip_edges() != ""


func set_callsign(n: String) -> void:
	data.name = n.strip_edges().substr(0, 16)
	save()


func set_ship(id: String) -> void:
	data.ship = id
	save()


static func xp_for_level(level: int) -> int:
	return 1000 + (level - 1) * 350


func level_progress() -> float:
	return clampf(float(data.xp) / float(xp_for_level(int(data.level))), 0.0, 1.0)


func rank_name() -> String:
	var ranks := ["CADET", "ENSIGN", "LIEUTENANT", "FLIGHT LEAD", "COMMANDER", "WING COMMANDER", "CAPTAIN", "ACE", "LEGEND"]
	return ranks[clampi((int(data.level) - 1) / 3, 0, ranks.size() - 1)]


func kd() -> float:
	return float(data.kills) / maxf(1.0, float(data.deaths))


## Applies a finished match. Returns a breakdown for the results screen.
func record_match(stats: Dictionary) -> Dictionary:
	var won: bool = stats.get("won", false)
	var xp_gain := 250 + int(stats.get("kills", 0)) * 100 + int(stats.get("assists", 0)) * 40 \
		+ int(stats.get("captures", 0)) * 150 + (500 if won else 0)
	data.kills = int(data.kills) + int(stats.get("kills", 0))
	data.deaths = int(data.deaths) + int(stats.get("deaths", 0))
	data.assists = int(data.assists) + int(stats.get("assists", 0))
	data.captures = int(data.captures) + int(stats.get("captures", 0))
	data.best_streak = maxi(int(data.best_streak), int(stats.get("best_streak", 0)))
	data.matches = int(data.matches) + 1
	if won:
		data.wins = int(data.wins) + 1
	else:
		data.losses = int(data.losses) + 1
	var start_level := int(data.level)
	var start_xp := int(data.xp)
	data.xp = int(data.xp) + xp_gain
	while int(data.xp) >= xp_for_level(int(data.level)):
		data.xp = int(data.xp) - xp_for_level(int(data.level))
		data.level = int(data.level) + 1
		level_up.emit(int(data.level))
	save()
	return {"xp_gain": xp_gain, "start_level": start_level, "start_xp": start_xp,
		"level": int(data.level), "xp": int(data.xp)}


func _total_xp(d: Dictionary) -> int:
	var total := int(d.get("xp", 0))
	for l in range(1, int(d.get("level", 1))):
		total += xp_for_level(l)
	return total


func _load_local() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if d is Dictionary:
		for k in d.keys():
			data[k] = d[k]


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
	changed.emit()
	push_cloud()


func push_cloud() -> void:
	if not Firebase.is_signed_in() or syncing:
		return
	var payload := data.duplicate()
	payload["total_xp"] = _total_xp(data)
	payload["settings"] = Settings.to_dict()
	payload["updated"] = int(Time.get_unix_time_from_system())
	Firebase.set_doc("players/%s" % Firebase.uid, payload)


## Pulls the cloud profile and merges it with the local one.
func pull_cloud() -> void:
	if not Firebase.is_signed_in():
		return
	syncing = true
	var r := await Firebase.get_doc("players/%s" % Firebase.uid)
	syncing = false
	if r.get("ok", false):
		var cloud: Dictionary = r.doc
		if _total_xp(cloud) > _total_xp(data):
			for k in data.keys():
				if cloud.has(k):
					data[k] = cloud[k]
			if cloud.get("settings") is Dictionary:
				Settings.from_dict(cloud.settings)
		elif str(data.name) == "" and str(cloud.get("name", "")) != "":
			data.name = cloud.name
	save()
