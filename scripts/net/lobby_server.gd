extends SceneTree
## Relais WebSocket headless pour le backend `ws`.  Serveur WS BRUT (TCPServer +
## WebSocketPeer.accept_stream).  Multi-salons : chaque client indique son `room`
## au `hello` ; le relai cloisonne roster / diffusion / lancement par salon.
##
##   Godot_v4.7.2-stable_win64.exe --headless --path . --script res://scripts/net/lobby_server.gd
##   (--port=XXXX ; --verbose)

const DEFAULT_PORT := 9871
const HANDSHAKE_TIMEOUT := 8.0

var _tcp := TCPServer.new()
var _pending: Array = []           ## [{sock, t0}]
var _clients: Dictionary = {}      ## cid -> {sock, p, room}
var _order: Array = []
var _rooms: Dictionary = {}        ## room -> {order:[cid], started:bool, seed:int}
var _next_id := 1
var _verbose := false
var _palette := ["6cadff", "d9665a", "9973d9", "e6b84d", "73cc8c", "d98c4d", "8cbfd9", "cc6699"]


func _init() -> void:
	var port := DEFAULT_PORT
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--port="):
			port = int(a.substr(7))
		if a == "--verbose":
			_verbose = true
	var err := _tcp.listen(port)
	if err != OK:
		push_error("lobby_server: listen(%d) -> %s" % [port, error_string(err)])
		quit(1)
		return
	print("[lobby_server] ecoute sur ws://0.0.0.0:%d" % port)


func _log(s: String) -> void:
	print("[lobby_server] " + s)


func _process(delta: float) -> bool:
	while _tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		if ws.accept_stream(_tcp.take_connection()) == OK:
			_pending.append({"sock": ws, "t0": 0.0})

	var still: Array = []
	for e in _pending:
		var ws: WebSocketPeer = e["sock"]
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			var cid := _next_id
			_next_id += 1
			_clients[cid] = {"sock": ws, "room": "", "p": {
				"id": "p%d" % cid, "name": "Joueur %d" % cid, "avatar_url": "",
				"color": "#" + _palette[_clients.size() % _palette.size()],
				"is_local": false, "is_bot": false, "ready": false}}
			_order.append(cid)
		elif st == WebSocketPeer.STATE_CONNECTING and e["t0"] + delta < HANDSHAKE_TIMEOUT:
			e["t0"] += delta
			still.append(e)
	_pending = still

	var dead: Array = []
	for cid in _clients:
		var ws: WebSocketPeer = _clients[cid]["sock"]
		ws.poll()
		if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
			dead.append(cid)
			continue
		while ws.get_available_packet_count() > 0:
			_handle(cid, ws.get_packet())
	for cid in dead:
		_drop(cid)
	return false


# --- salons -------------------------------------------------------

func _room_of(cid: int) -> String:
	return _clients[cid]["room"] if _clients.has(cid) else ""


func _room(name: String) -> Dictionary:
	if not _rooms.has(name):
		_rooms[name] = {"order": [], "started": false, "seed": 0}
	return _rooms[name]


func _room_host(rm: String) -> int:
	for cid in _room(rm)["order"]:
		if _clients.has(cid):
			return cid
	return 0


func _room_roster(rm: String) -> Array:
	var out: Array = []
	for cid in _room(rm)["order"]:
		if _clients.has(cid):
			out.append(_clients[cid]["p"])
	return out


func _join_room(cid: int, name: String) -> void:
	name = name.strip_edges().to_upper()
	if name == "":
		name = "PUBLIC"
	_clients[cid]["room"] = name
	var r := _room(name)
	if cid not in r["order"]:
		r["order"].append(cid)
	_log("p%d rejoint le salon %s  (%d joueur(s))" % [cid, name, _room_roster(name).size()])
	_broadcast_lobby(name)


func _drop(cid: int) -> void:
	if not _clients.has(cid):
		return
	var rm: String = _clients[cid]["room"]
	var pid: String = _clients[cid]["p"]["id"]
	_clients.erase(cid)
	_order.erase(cid)
	if rm != "" and _rooms.has(rm):
		_rooms[rm]["order"].erase(cid)
		_broadcast(rm, {"t": "left", "id": pid})
		_broadcast_lobby(rm)
		if _room_roster(rm).is_empty():
			_rooms.erase(rm)
			_log("salon %s vide -> ferme" % rm)


func _handle(cid: int, raw: PackedByteArray) -> void:
	var d = JSON.parse_string(raw.get_string_from_utf8())
	if not (d is Dictionary) or not _clients.has(cid):
		return
	var p: Dictionary = _clients[cid]["p"]
	var kind := String(d.get("t", ""))
	if _verbose:
		_log("<- %s de %s [%s]" % [kind, p["id"], _room_of(cid)])
	match kind:
		"hello":
			p["name"] = String(d.get("name", p["name"]))
			p["avatar_url"] = String(d.get("avatar_url", ""))
			_join_room(cid, String(d.get("room", "")))
			_send(cid, {"t": "welcome", "id": p["id"], "host": cid == _room_host(_room_of(cid)), "room": _room_of(cid)})
			_broadcast_lobby(_room_of(cid))
		"ready":
			p["ready"] = bool(d.get("on", false))
			_broadcast_lobby(_room_of(cid))
		"start":
			var rm := _room_of(cid)
			var r := _room(rm)
			if r["started"]:
				_log("start %s ignore (deja lance)" % rm)
			elif _room_roster(rm).size() < 2:
				_log("start %s ignore (%d joueur)" % [rm, _room_roster(rm).size()])
			else:
				r["started"] = true
				r["seed"] = int(d.get("seed", randi()))
				_log("*** LANCEMENT salon %s (seed %d, %d joueurs) ***" % [rm, r["seed"], _room_roster(rm).size()])
				_broadcast(rm, {"t": "match_started", "seed": r["seed"], "roster": _room_roster(rm)})
		"cmd":
			var rm2 := _room_of(cid)
			var msg := {"t": "cmd", "from": p["id"], "ch": d.get("ch", "cmd"), "p": d.get("p", {})}
			var to := String(d.get("to", ""))
			if to == "":
				_broadcast(rm2, msg, cid)
			else:
				for other in _room(rm2)["order"]:
					if _clients.has(other) and _clients[other]["p"]["id"] == to:
						_send(other, msg)
		"snap":
			_broadcast(_room_of(cid), {"t": "snap", "from": p["id"], "b": d.get("b", "")}, cid)
		"speaking":
			_broadcast(_room_of(cid), {"t": "speaking", "id": p["id"], "on": bool(d.get("on", false))}, cid)


func _broadcast_lobby(rm: String) -> void:
	if rm == "":
		return
	_broadcast(rm, {"t": "lobby", "players": _room_roster(rm), "host": "p%d" % _room_host(rm), "room": rm})


func _broadcast(rm: String, d: Dictionary, except := -1) -> void:
	if not _rooms.has(rm):
		return
	var txt := JSON.stringify(d)
	for cid in _rooms[rm]["order"]:
		if cid != except:
			_send_txt(cid, txt)


func _send(cid: int, d: Dictionary) -> void:
	_send_txt(cid, JSON.stringify(d))


func _send_txt(cid: int, txt: String) -> void:
	if not _clients.has(cid):
		return
	var ws: WebSocketPeer = _clients[cid]["sock"]
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(txt)
