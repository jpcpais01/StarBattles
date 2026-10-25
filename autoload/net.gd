extends Node
## Multiplayer session layer: ENet host/join, the player roster, team
## balancing, LAN discovery over UDP broadcast, and an online lobby list
## published to Firestore. The match itself lives in game/match.gd.

signal players_changed
signal connection_succeeded
signal connection_failed(reason: String)
signal session_ended(reason: String)
signal servers_changed

const PORT := 24850
const DISCOVERY_PORT := 24851
const MAX_PLAYERS := 20
const PROTOCOL := 1

## peer_id -> {name, team, ship, level, version}
var players: Dictionary = {}
var lobby_name := ""
## Game mode the host will launch: "conquest" or "siege".
var match_mode := "conquest"
var in_session := false
var in_match := false
var dedicated := false
var public_lobby := false
var lan_servers: Dictionary = {}
var online_servers: Array = []
var public_ip := ""
var _peer: ENetMultiplayerPeer
var _broadcast: PacketPeerUDP
var _listener: PacketPeerUDP
var _broadcast_timer := 0.0
var _heartbeat_timer := 0.0
var _pending_reason := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_online() -> bool:
	return in_session and multiplayer.multiplayer_peer is ENetMultiplayerPeer


func is_host() -> bool:
	return multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id()


func local_info() -> Dictionary:
	return {"name": Profile.callsign(), "ship": str(Profile.data.ship), "level": int(Profile.data.level),
		"version": App.version, "protocol": PROTOCOL}


# --- Session lifecycle ----------------------------------------------------------

func host_game(name_text: String, make_public := true, is_dedicated := false) -> Error:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		return err
	_peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = _peer
	in_session = true
	dedicated = is_dedicated
	lobby_name = name_text if name_text != "" else "%s's Battle" % Profile.callsign()
	public_lobby = make_public
	players.clear()
	if not dedicated:
		_add_player(1, local_info())
	_start_broadcast()
	if public_lobby:
		_publish_lobby()
	players_changed.emit()
	return OK


func join_game(address: String, port := PORT) -> Error:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address.strip_edges(), port)
	if err != OK:
		return err
	_peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = _peer
	in_session = true
	return OK


func leave() -> void:
	if public_lobby and Firebase.is_signed_in() and is_host():
		Firebase.delete_doc("lobbies/%s" % Firebase.uid)
	public_lobby = false
	_stop_broadcast()
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	in_session = false
	in_match = false
	players.clear()
	players_changed.emit()


## Server: tell everyone to load the arena.
func start_match(config: Dictionary = {}) -> void:
	if not is_host():
		return
	var cfg := config.duplicate()
	if not cfg.has("seed"):
		cfg["seed"] = randi()
	cfg["online"] = is_online()
	in_match = true
	if is_online():
		_begin_match.rpc(cfg)
	_begin_match(cfg)


@rpc("authority", "call_remote", "reliable")
func _begin_match(cfg: Dictionary) -> void:
	in_match = true
	App.match_config = cfg
	App.goto_scene(App.SCENE_ARENA)


func end_match_to_lobby() -> void:
	in_match = false


# --- Roster -------------------------------------------------------------------------

func _add_player(id: int, info: Dictionary) -> void:
	var counts := [0, 0]
	for p in players.values():
		counts[int(p.team)] += 1
	info["team"] = 0 if counts[0] <= counts[1] else 1
	players[id] = info


func _on_peer_connected(id: int) -> void:
	if is_host():
		return
	# Clients only care about the server; registration happens on connect.


func _on_connected() -> void:
	_register.rpc_id(1, local_info())


@rpc("any_peer", "call_remote", "reliable")
func _register(info: Dictionary) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if int(info.get("protocol", 0)) != PROTOCOL or str(info.get("version", "")) != App.version:
		_rejected.rpc_id(id, "Version mismatch: server runs %s. Update from the home screen." % App.version_label())
		get_tree().create_timer(0.5).timeout.connect(func(): if _peer: _peer.disconnect_peer(id))
		return
	if players.size() >= MAX_PLAYERS:
		_rejected.rpc_id(id, "Server is full.")
		get_tree().create_timer(0.5).timeout.connect(func(): if _peer: _peer.disconnect_peer(id))
		return
	info["name"] = str(info.get("name", "PILOT")).substr(0, 16)
	_add_player(id, info)
	_sync_players.rpc(players, lobby_name, match_mode)
	players_changed.emit()
	if in_match:
		_begin_match.rpc_id(id, App.match_config)


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	_pending_reason = reason


@rpc("authority", "call_remote", "reliable")
func _sync_players(p: Dictionary, lname: String, mode: String) -> void:
	var first := players.is_empty()
	players = p
	lobby_name = lname
	match_mode = mode
	players_changed.emit()
	if first:
		connection_succeeded.emit()


func _on_peer_disconnected(id: int) -> void:
	if players.erase(id) and is_host():
		_sync_players.rpc(players, lobby_name, match_mode)
	players_changed.emit()


func _on_connection_failed() -> void:
	leave()
	connection_failed.emit("Could not reach the server.")


func _on_server_disconnected() -> void:
	var reason := _pending_reason if _pending_reason != "" else "Lost connection to the server."
	_pending_reason = ""
	leave()
	session_ended.emit(reason)


func set_my_ship(ship_id: String) -> void:
	if is_online():
		_update_ship.rpc_id(1, ship_id)
	elif players.has(1):
		players[1].ship = ship_id


@rpc("any_peer", "call_local", "reliable")
func _update_ship(ship_id: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id].ship = ship_id
		_sync_players.rpc(players, lobby_name, match_mode)


## Host: pick the mode for the next launch.
func set_match_mode(mode: String) -> void:
	if not is_host() or mode == match_mode:
		return
	match_mode = mode
	if is_online():
		_sync_players.rpc(players, lobby_name, match_mode)
	players_changed.emit()
	if public_lobby:
		_publish_lobby()


func swap_team(id: int) -> void:
	if is_host() and players.has(id):
		players[id].team = 1 - int(players[id].team)
		if is_online():
			_sync_players.rpc(players, lobby_name, match_mode)
		players_changed.emit()


# --- Discovery ------------------------------------------------------------------------

func _start_broadcast() -> void:
	_broadcast = PacketPeerUDP.new()
	_broadcast.set_broadcast_enabled(true)
	_broadcast.set_dest_address("255.255.255.255", DISCOVERY_PORT)


func _stop_broadcast() -> void:
	if _broadcast:
		_broadcast.close()
	_broadcast = null


func start_listening() -> void:
	stop_listening()
	_listener = PacketPeerUDP.new()
	if _listener.bind(DISCOVERY_PORT) != OK:
		_listener = null
	lan_servers.clear()
	refresh_online()


func stop_listening() -> void:
	if _listener:
		_listener.close()
	_listener = null


func refresh_online() -> void:
	online_servers.clear()
	if not Firebase.is_signed_in():
		servers_changed.emit()
		return
	var docs := await Firebase.list_docs("lobbies")
	var now := int(Time.get_unix_time_from_system())
	for d in docs:
		if now - int(d.get("updated", 0)) < 90 and str(d.get("version", "")) == App.version:
			online_servers.append(d)
	servers_changed.emit()


func _publish_lobby() -> void:
	if not Firebase.is_signed_in():
		return
	if public_ip == "":
		var http := HTTPRequest.new()
		add_child(http)
		http.request("https://api.ipify.org?format=json")
		var res: Array = await http.request_completed
		http.queue_free()
		var d = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
		if d is Dictionary:
			public_ip = str(d.get("ip", ""))
	if public_ip == "" or not in_session:
		return
	Firebase.set_doc("lobbies/%s" % Firebase.uid, {
		"name": lobby_name, "ip": public_ip, "port": PORT, "players": players.size(),
		"max": MAX_PLAYERS, "version": App.version, "in_match": in_match, "mode": match_mode,
		"updated": int(Time.get_unix_time_from_system())})


func _process(delta: float) -> void:
	if _broadcast and is_host():
		_broadcast_timer -= delta
		if _broadcast_timer <= 0.0:
			_broadcast_timer = 1.0
			var msg := JSON.stringify({"sb": PROTOCOL, "name": lobby_name, "port": PORT,
				"players": players.size(), "max": MAX_PLAYERS, "version": App.version, "in_match": in_match, "mode": match_mode})
			_broadcast.put_packet(msg.to_utf8_buffer())
	if public_lobby and is_host():
		_heartbeat_timer -= delta
		if _heartbeat_timer <= 0.0:
			_heartbeat_timer = 30.0
			_publish_lobby()
	if _listener:
		var changed := false
		while _listener.get_available_packet_count() > 0:
			var pkt := _listener.get_packet()
			var ip := _listener.get_packet_ip()
			var d = JSON.parse_string(pkt.get_string_from_utf8())
			if d is Dictionary and d.has("sb"):
				d["ip"] = ip
				d["seen"] = Time.get_ticks_msec()
				lan_servers[ip] = d
				changed = true
		for ip in lan_servers.keys():
			if Time.get_ticks_msec() - int(lan_servers[ip].seen) > 4000:
				lan_servers.erase(ip)
				changed = true
		if changed:
			servers_changed.emit()
