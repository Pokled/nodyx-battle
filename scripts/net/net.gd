extends Node
## Autoload `Net`.  Colonne vertebrale du multijoueur : etat de session + routage
## vers un backend interchangeable (`local` / `ws` / `nodyx`).  AUCUNE logique de jeu.
##
## Le jeu vit dans un salon vocal Nodyx : les membres du salon SONT le roster.
## En dev, le backend `local` simule ce salon avec des bots.

signal lobby_changed(players: Array)
signal player_joined(p: Dictionary)
signal player_left(id: String)
signal match_started(seed: int, roster: Array)
signal message(from_id: String, channel: String, payload: Dictionary)
signal snapshot(from_id: String, bytes: PackedByteArray)
signal speaking_changed(id: String, on: bool)
signal disconnected(reason: String)

enum Phase { OFFLINE, LOBBY, MATCH }

var phase := Phase.OFFLINE
var players: Array = []            ## [{id,name,avatar_url,color,is_local,is_bot,ready}]
var roster: Array = []             ## fige au lancement du match
var match_seed := 0
var speaking: Dictionary = {}      ## id -> bool

var _backend: NetBackend = null
var _backend_name := "local"


# --- configuration -----------------------------------------------------

## `name` : "local" | "ws" | "nodyx".  Defaut : nodyx si le pont existe, sinon local.
func configure(backend := "") -> void:
	if backend == "":
		backend = _detect_backend()
	if _backend != null:
		_backend.queue_free()
		_backend = null
	_backend_name = backend
	match backend:
		"ws":
			_backend = load("res://scripts/net/net_ws.gd").new()
		"nodyx":
			_backend = load("res://scripts/net/net_nodyx.gd").new()
		_:
			_backend = load("res://scripts/net/net_local.gd").new()
	_backend.name = "Backend"
	add_child(_backend)
	_backend.lobby_changed.connect(_on_lobby_changed)
	_backend.player_joined.connect(func(p): player_joined.emit(p))
	_backend.player_left.connect(func(id): player_left.emit(id))
	_backend.match_started.connect(_on_match_started)
	_backend.message.connect(func(f, c, p): message.emit(f, c, p))
	_backend.snapshot.connect(func(f, b): snapshot.emit(f, b))
	_backend.speaking_changed.connect(_on_speaking)
	_backend.disconnected.connect(func(r):
		phase = Phase.OFFLINE
		disconnected.emit(r))


## Lit une option `key` : CLI (`--key=val` / `key=val`) ou, sur web, `?key=val`.
func cmdline_opt(key: String) -> String:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
		if a.begins_with("%s=" % key):
			return a.substr(key.length() + 1)
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("new URLSearchParams(location.search).get('%s') || ''" % key, true)
		if v is String:
			return v
	return ""


func has_cmdline_net() -> bool:
	return cmdline_opt("net") != ""


func _detect_backend() -> String:
	var n := cmdline_opt("net")
	if n != "":
		return n
	if OS.has_feature("web"):
		var w = JavaScriptBridge.get_interface("window")
		if w != null and w.NodyxBattle:
			return "nodyx"
	return "local"


# --- session ---------------------------------------------------------

func open(opts := {}) -> void:
	if _backend == null:
		configure()
	# complete depuis la ligne de commande / l'URL (?room= ?code= ?name= ?host=)
	if not opts.has("room"):
		var r := cmdline_opt("room")
		if r == "":
			r = cmdline_opt("code")
		if r != "":
			opts["room"] = r
	if not opts.has("name"):
		var n := cmdline_opt("name")
		if n != "":
			opts["name"] = n
	if not opts.has("host"):
		var h := cmdline_opt("host")
		if h != "":
			opts["host"] = h
	phase = Phase.LOBBY
	_backend.open(opts)


func room() -> String:
	return _backend.room if _backend != null else ""


func leave() -> void:
	if _backend != null:
		_backend.close()
	phase = Phase.OFFLINE
	players.clear()
	roster.clear()


func set_ready(on: bool) -> void:
	if _backend != null:
		_backend.set_ready(on)


func start_match(opts := {}) -> void:
	if _backend != null:
		_backend.start_match(opts)


func send(channel: String, payload: Dictionary, reliable := true, to := "") -> void:
	if _backend != null:
		_backend.send(channel, payload, reliable, to)


func broadcast_snapshot(bytes: PackedByteArray) -> void:
	if _backend != null:
		_backend.broadcast_snapshot(bytes)


# --- accesseurs -----------------------------------------------------

func local_id() -> String:
	return _backend.local_id if _backend != null else ""


func is_host() -> bool:
	return _backend != null and _backend.is_host


func in_match() -> bool:
	return phase == Phase.MATCH


func player(id: String) -> Dictionary:
	for p in players:
		if p.get("id", "") == id:
			return p
	return {}


func opponents() -> Array:
	var out := []
	for p in roster:
		if p.get("id", "") != local_id():
			out.append(p)
	return out


func speaking_ids() -> Array:
	var out := []
	for k in speaking:
		if speaking[k]:
			out.append(k)
	return out


# --- relais des signaux backend -------------------------------------

const _PAL := [Color(0.42, 0.68, 1.0), Color(0.85, 0.40, 0.35), Color(0.60, 0.45, 0.85),
	Color(0.90, 0.72, 0.30), Color(0.45, 0.80, 0.55), Color(0.85, 0.55, 0.30),
	Color(0.55, 0.75, 0.85), Color(0.80, 0.40, 0.60)]

## Les backends texte (ws/nodyx) ne peuvent pas serialiser une Color -> on la
## renormalise ici (hex "#rrggbb", [r,g,b], ou null -> couleur par index).
func _normalize(pl: Array) -> Array:
	for i in pl.size():
		var p: Dictionary = pl[i]
		var c = p.get("color", null)
		if c is Color:
			pass
		elif c is String and c != "":
			p["color"] = Color(c)
		elif c is Array and c.size() >= 3:
			p["color"] = Color(c[0], c[1], c[2])
		else:
			p["color"] = _PAL[i % _PAL.size()]
		p["is_local"] = p.get("id", "") == local_id()
	return pl


func _on_lobby_changed(pl: Array) -> void:
	players = _normalize(pl)
	lobby_changed.emit(players)


func _on_match_started(seed_val: int, r: Array) -> void:
	match_seed = seed_val
	roster = _normalize(r.duplicate(true))
	phase = Phase.MATCH
	match_started.emit(seed_val, roster)


func _on_speaking(id: String, on: bool) -> void:
	speaking[id] = on
	speaking_changed.emit(id, on)
