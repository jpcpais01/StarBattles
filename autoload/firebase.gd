extends Node
## Firebase over REST: Identity Toolkit auth (guest / email), token refresh,
## and Firestore documents. Config comes from res://config/firebase.json,
## which CI writes from repository secrets. Without it the game runs fully
## offline with a local profile.

signal auth_changed(signed_in: bool)

const CONFIG_PATH := "res://config/firebase.json"
const SESSION_PATH := "user://session.cfg"

var api_key := ""
var project_id := ""
var uid := ""
var email := ""
var display_name := ""
var is_anonymous := true
var id_token := ""
var refresh_token := ""
var _expires_at := 0.0
var last_error := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if FileAccess.file_exists(CONFIG_PATH):
		var cfg = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if cfg is Dictionary:
			api_key = str(cfg.get("apiKey", ""))
			project_id = str(cfg.get("projectId", ""))
	var s := ConfigFile.new()
	if s.load(SESSION_PATH) == OK:
		refresh_token = s.get_value("auth", "refresh_token", "")
		uid = s.get_value("auth", "uid", "")
		email = s.get_value("auth", "email", "")
		is_anonymous = s.get_value("auth", "anonymous", true)


func is_configured() -> bool:
	return api_key != "" and project_id != ""


func is_signed_in() -> bool:
	return id_token != "" and uid != ""


func has_saved_session() -> bool:
	return refresh_token != ""


# --- HTTP ---------------------------------------------------------------------

func _request(url: String, method: int, body: Variant = null, headers: PackedStringArray = PackedStringArray(), raw_body := "") -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	var h := PackedStringArray(["Content-Type: application/json"])
	h.append_array(headers)
	var payload := raw_body
	if body != null:
		payload = JSON.stringify(body)
	var err := http.request(url, h, method, payload)
	if err != OK:
		http.queue_free()
		return {"ok": false, "code": 0, "data": {}, "error": "Network unavailable"}
	var res: Array = await http.request_completed
	http.queue_free()
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	var data: Variant = JSON.parse_string(text) if text != "" else {}
	if data == null:
		data = {}
	var ok: bool = res[0] == HTTPRequest.RESULT_SUCCESS and int(res[1]) >= 200 and int(res[1]) < 300
	var error := ""
	if not ok:
		error = "Network error" if res[0] != HTTPRequest.RESULT_SUCCESS else _friendly_error(data)
	return {"ok": ok, "code": int(res[1]), "data": data, "error": error}


func _friendly_error(data: Variant) -> String:
	var msg := ""
	if data is Dictionary and data.has("error"):
		var e = data["error"]
		msg = str(e.get("message", e)) if e is Dictionary else str(e)
	var table := {
		"EMAIL_EXISTS": "That email already has an account.",
		"EMAIL_NOT_FOUND": "No account with that email.",
		"INVALID_PASSWORD": "Wrong password.",
		"INVALID_LOGIN_CREDENTIALS": "Wrong email or password.",
		"INVALID_EMAIL": "That email doesn't look right.",
		"USER_DISABLED": "This account is disabled.",
		"TOO_MANY_ATTEMPTS_TRY_LATER": "Too many attempts. Try again later.",
		"OPERATION_NOT_ALLOWED": "This sign-in method is disabled in Firebase.",
		"ADMIN_ONLY_OPERATION": "Guest sign-in is disabled in Firebase.",
	}
	for k in table.keys():
		if msg.begins_with(k):
			return table[k]
	if msg.begins_with("WEAK_PASSWORD"):
		return "Password needs at least 6 characters."
	return msg if msg != "" else "Request failed"


func _auth_url(endpoint: String) -> String:
	return "https://identitytoolkit.googleapis.com/v1/accounts:%s?key=%s" % [endpoint, api_key]


func _apply_auth(d: Dictionary, anonymous: bool) -> void:
	id_token = str(d.get("idToken", d.get("id_token", "")))
	refresh_token = str(d.get("refreshToken", d.get("refresh_token", refresh_token)))
	uid = str(d.get("localId", d.get("user_id", uid)))
	if d.has("email"):
		email = str(d.email)
	if d.has("displayName"):
		display_name = str(d.displayName)
	is_anonymous = anonymous
	_expires_at = Time.get_unix_time_from_system() + float(d.get("expiresIn", d.get("expires_in", 3600))) - 60.0
	var s := ConfigFile.new()
	s.set_value("auth", "refresh_token", refresh_token)
	s.set_value("auth", "uid", uid)
	s.set_value("auth", "email", email)
	s.set_value("auth", "anonymous", is_anonymous)
	s.save(SESSION_PATH)
	auth_changed.emit(true)


# --- Auth ---------------------------------------------------------------------

func sign_in_guest() -> Dictionary:
	if not is_configured():
		return {"ok": false, "error": "Cloud services are not configured."}
	var r := await _request(_auth_url("signUp"), HTTPClient.METHOD_POST, {"returnSecureToken": true})
	if r.ok:
		_apply_auth(r.data, true)
	last_error = r.error
	return r


func sign_up(mail: String, password: String) -> Dictionary:
	if not is_configured():
		return {"ok": false, "error": "Cloud services are not configured."}
	var r: Dictionary
	if is_signed_in() and is_anonymous:
		# Upgrade the guest account in place so progress carries over.
		r = await _request(_auth_url("update"), HTTPClient.METHOD_POST,
			{"idToken": id_token, "email": mail, "password": password, "returnSecureToken": true})
	else:
		r = await _request(_auth_url("signUp"), HTTPClient.METHOD_POST,
			{"email": mail, "password": password, "returnSecureToken": true})
	if r.ok:
		_apply_auth(r.data, false)
	last_error = r.error
	return r


func sign_in(mail: String, password: String) -> Dictionary:
	if not is_configured():
		return {"ok": false, "error": "Cloud services are not configured."}
	var r := await _request(_auth_url("signInWithPassword"), HTTPClient.METHOD_POST,
		{"email": mail, "password": password, "returnSecureToken": true})
	if r.ok:
		_apply_auth(r.data, false)
	last_error = r.error
	return r


func send_password_reset(mail: String) -> Dictionary:
	return await _request(_auth_url("sendOobCode"), HTTPClient.METHOD_POST,
		{"requestType": "PASSWORD_RESET", "email": mail})


func restore_session() -> bool:
	if not is_configured() or refresh_token == "":
		return false
	var url := "https://securetoken.googleapis.com/v1/token?key=%s" % api_key
	var r := await _request(url, HTTPClient.METHOD_POST, null,
		PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]),
		"grant_type=refresh_token&refresh_token=%s" % refresh_token.uri_encode())
	if r.ok:
		_apply_auth(r.data, is_anonymous)
		return true
	if r.code == 400:
		sign_out()
	return false


func sign_out() -> void:
	id_token = ""
	refresh_token = ""
	uid = ""
	email = ""
	is_anonymous = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))
	auth_changed.emit(false)


func _ensure_token() -> bool:
	if not is_signed_in():
		return false
	if Time.get_unix_time_from_system() > _expires_at:
		return await restore_session()
	return true


# --- Firestore ----------------------------------------------------------------

func _doc_url(path: String) -> String:
	return "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents/%s" % [project_id, path]


func _auth_header() -> PackedStringArray:
	return PackedStringArray(["Authorization: Bearer %s" % id_token])


func get_doc(path: String) -> Dictionary:
	if not await _ensure_token():
		return {"ok": false, "error": "Not signed in"}
	var r := await _request(_doc_url(path), HTTPClient.METHOD_GET, null, _auth_header())
	if r.ok:
		r["doc"] = decode_fields(r.data.get("fields", {}))
	return r


func set_doc(path: String, fields: Dictionary) -> Dictionary:
	if not await _ensure_token():
		return {"ok": false, "error": "Not signed in"}
	return await _request(_doc_url(path), HTTPClient.METHOD_PATCH, {"fields": encode_fields(fields)}, _auth_header())


func delete_doc(path: String) -> Dictionary:
	if not await _ensure_token():
		return {"ok": false, "error": "Not signed in"}
	return await _request(_doc_url(path), HTTPClient.METHOD_DELETE, null, _auth_header())


func list_docs(collection: String, page_size := 50) -> Array:
	if not await _ensure_token():
		return []
	var r := await _request(_doc_url(collection) + "?pageSize=%d" % page_size, HTTPClient.METHOD_GET, null, _auth_header())
	var out := []
	if r.ok:
		for d in r.data.get("documents", []):
			var item := decode_fields(d.get("fields", {}))
			item["_id"] = str(d.get("name", "")).get_file()
			out.append(item)
	return out


## Top documents of a collection ordered by a numeric field.
func query_top(collection: String, field: String, limit := 20) -> Array:
	if not await _ensure_token():
		return []
	var url := "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents:runQuery" % project_id
	var q := {"structuredQuery": {
		"from": [{"collectionId": collection}],
		"orderBy": [{"field": {"fieldPath": field}, "direction": "DESCENDING"}],
		"limit": limit}}
	var r := await _request(url, HTTPClient.METHOD_POST, q, _auth_header())
	var out := []
	if r.ok and r.data is Array:
		for row in r.data:
			if row is Dictionary and row.has("document"):
				var item := decode_fields(row.document.get("fields", {}))
				item["_id"] = str(row.document.get("name", "")).get_file()
				out.append(item)
	return out


static func encode_value(v: Variant) -> Dictionary:
	match typeof(v):
		TYPE_NIL:
			return {"nullValue": null}
		TYPE_BOOL:
			return {"booleanValue": v}
		TYPE_INT:
			return {"integerValue": str(v)}
		TYPE_FLOAT:
			return {"doubleValue": v}
		TYPE_STRING, TYPE_STRING_NAME:
			return {"stringValue": str(v)}
		TYPE_ARRAY:
			var vals := []
			for x in v:
				vals.append(encode_value(x))
			return {"arrayValue": {"values": vals}}
		TYPE_DICTIONARY:
			return {"mapValue": {"fields": encode_fields(v)}}
	return {"stringValue": str(v)}


static func encode_fields(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		out[str(k)] = encode_value(d[k])
	return out


static func decode_value(v: Dictionary) -> Variant:
	if v.has("stringValue"):
		return v.stringValue
	if v.has("integerValue"):
		return int(v.integerValue)
	if v.has("doubleValue"):
		return float(v.doubleValue)
	if v.has("booleanValue"):
		return bool(v.booleanValue)
	if v.has("timestampValue"):
		return v.timestampValue
	if v.has("arrayValue"):
		var out := []
		for x in v.arrayValue.get("values", []):
			out.append(decode_value(x))
		return out
	if v.has("mapValue"):
		return decode_fields(v.mapValue.get("fields", {}))
	return null


static func decode_fields(f: Dictionary) -> Dictionary:
	var out := {}
	for k in f.keys():
		out[k] = decode_value(f[k])
	return out
