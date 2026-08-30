class_name NetWs
extends NetBackend
## Backend `ws` : vrai multijoueur via un relais WebSocket headless
## (`scripts/net/lobby_server.gd`).  Browser-safe (contrairement a ENet).
## Chaque client fait tourner son propre plateau autoritaire ; on echange des
## commandes (fiable) et des BoardDigest (best-effort).
##
## Lancer le relais :  Godot --headless --path . --script res://scripts/net/lobby_server.gd
## Lancer un client :  Godot --path . -- --net=ws --host=127.0.0.1:9871

var _sock := WebSocketPeer.new()
var _url := "ws://127.0.0.1:9871"
var _open_sent := false
var _my := {}


func open(opts: Dictionary) -> void:
	var host := String(opts.get("host", ""))
	if host == "":
		host = "127.0.0.1:9871"
	var scheme := "ws://"
	if host.begins_with("ws://") or host.begins_with("wss://"):
		_url = host
	else:
		if OS.has_feature("web"):
			var https = JavaScriptBridge.eval("location.protocol === 'https:'", true)
			if https:
				scheme = "wss://"
		_url = scheme + host
	_my = {
		"name": String(opts.get("name", "Joueur")),
		"avatar_url": String(opts.get("avatar_url", "")),
		"room": String(opts.get("room", "")),
	}
	var err := _sock.connect_to_url(_url)
	if err != OK:
		disconnected.emit("connexion impossible (%s)" % error_string(err))


func close() -> void:
	_sock.close()


func _process(_delta: float) -> void:
	_sock.poll()
	var st := _sock.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _open_sent:
			_open_sent = true
			_tx({"t": "hello", "name": _my.get("name", "Joueur"),
				"avatar_url": _my.get("avatar_url", ""), "room": _my.get("room", "")})
		while _sock.get_available_packet_count() > 0:
			_rx(_sock.get_packet())
	elif st == WebSocketPeer.STATE_CLOSED and _open_sent:
		_open_sent = false
		disconnected.emit("relais deconnecte (%d)" % _sock.get_close_code())


func set_ready(on: bool) -> void:
	_tx({"t": "ready", "on": on})


func start_match(opts: Dictionary) -> void:
	_tx({"t": "start", "seed": int(opts.get("seed", randi()))})


func send(channel: String, payload: Dictionary, reliable := true, to := "") -> void:
	_tx({"t": "cmd", "ch": channel, "p": payload, "to": to, "rel": reliable})


func broadcast_snapshot(bytes: PackedByteArray) -> void:
	_tx({"t": "snap", "b": Marshalls.raw_to_base64(bytes)})


# --- io ------------------------------------------------------------

func _tx(d: Dictionary) -> void:
	if _sock.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_sock.send_text(JSON.stringify(d))


func _rx(pkt: PackedByteArray) -> void:
	var d = JSON.parse_string(pkt.get_string_from_utf8())
	if not (d is Dictionary):
		return
	match d.get("t", ""):
		"welcome":
			local_id = String(d.get("id", ""))
			is_host = bool(d.get("host", false))
			room = String(d.get("room", ""))
		"lobby":
			is_host = String(d.get("host", "")) == local_id
			room = String(d.get("room", room))
			lobby_changed.emit(Array(d.get("players", [])))
		"match_started":
			match_started.emit(int(d.get("seed", 0)), Array(d.get("roster", [])))
		"cmd":
			message.emit(String(d.get("from", "")), String(d.get("ch", "cmd")), d.get("p", {}))
		"snap":
			snapshot.emit(String(d.get("from", "")), Marshalls.base64_to_raw(String(d.get("b", ""))))
		"speaking":
			speaking_changed.emit(String(d.get("id", "")), bool(d.get("on", false)))
		"left":
			player_left.emit(String(d.get("id", "")))
