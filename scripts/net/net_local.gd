class_name NetLocal
extends NetBackend
## Backend `local` : 1 humain + K bots, tout en process.  Simule un salon vocal
## Nodyx pour le dev / le solo.  Le client local est toujours host.

var _bots: Array = []              ## BotCommander
var _ready_state: Dictionary = {}  ## id -> bool
var _human := {}
var _started := false


func open(opts: Dictionary) -> void:
	local_id = "you"
	is_host = true
	_human = {"id": "you", "name": String(opts.get("name", "Toi")), "avatar_url": "",
		"color": Color(0.42, 0.68, 1.0), "is_local": true, "is_bot": false, "ready": false}
	var nbots := int(opts.get("bots", 1))
	var diff := float(opts.get("difficulty", 1.0))
	var cols := [Color(0.85, 0.40, 0.35), Color(0.60, 0.45, 0.85), Color(0.90, 0.72, 0.30),
		Color(0.45, 0.80, 0.55), Color(0.85, 0.55, 0.30), Color(0.55, 0.75, 0.85), Color(0.80, 0.40, 0.60)]
	_bots.clear()
	for i in nbots:
		var b := BotCommander.new()
		b.setup("bot%d" % (i + 1), "Bot %d" % (i + 1), cols[i % cols.size()], diff)
		b.out_cmd.connect(_on_bot_cmd.bind(b))
		b.out_snapshot.connect(_on_bot_snap.bind(b))
		_bots.append(b)
	_emit_lobby()


func close() -> void:
	_bots.clear()
	_started = false


func _players_list() -> Array:
	var out: Array = [_human.duplicate()]
	out[0]["ready"] = bool(_ready_state.get("you", false))
	for b in _bots:
		var e: Dictionary = b.roster_entry()
		e["ready"] = bool(_ready_state.get(b.id, true))   ## les bots sont toujours prets
		out.append(e)
	return out


func _emit_lobby() -> void:
	lobby_changed.emit(_players_list())


func set_ready(on: bool) -> void:
	_ready_state["you"] = on
	_emit_lobby()


func start_match(opts: Dictionary) -> void:
	if _started:
		return
	_started = true
	var seed_val := int(opts.get("seed", randi()))
	var roster := _players_list()
	for b in _bots:
		b.on_match_start(seed_val, roster)
	match_started.emit(seed_val, roster)


func send(channel: String, payload: Dictionary, _reliable := true, to := "") -> void:
	# client local -> bots
	for b in _bots:
		if to == "" or to == b.id:
			b.on_message(local_id, channel, payload)


func broadcast_snapshot(_bytes: PackedByteArray) -> void:
	# les bots simulent leur board independamment : rien a leur transmettre
	pass


func _process(delta: float) -> void:
	if not _started:
		return
	for b in _bots:
		b.tick(delta)


func _on_bot_cmd(channel: String, payload: Dictionary, bot) -> void:
	# une commande de bot est vue par le host local ET redispatchee aux autres bots
	message.emit(bot.id, channel, payload)
	for other in _bots:
		if other != bot:
			other.on_message(bot.id, channel, payload)


func _on_bot_snap(bytes: PackedByteArray, bot) -> void:
	snapshot.emit(bot.id, bytes)
