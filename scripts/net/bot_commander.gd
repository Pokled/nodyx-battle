class_name BotCommander
extends RefCounted
## Pilote un adversaire BOT (backend `local`).  Reagit aux commandes de manche du
## host (le client local) via le bus `Net`, fait tourner un `AbstractBoardSim`, et
## re-emet des commandes / snapshots comme le ferait un joueur humain.

signal out_cmd(channel: String, payload: Dictionary)
signal out_snapshot(bytes: PackedByteArray)

var id := "bot"
var name := "Bot"
var color := Color(0.85, 0.4, 0.35)
var difficulty := 1.0

var _sim := AbstractBoardSim.new()
var _incoming: Dictionary = {}
var _alive_targets: Array = []
var _path: PackedVector2Array
var _snap_acc := 0.0
var _think := -1.0
var _round := 0
var _last_king := 100
var _dead := false
var _match_over := false


func _init() -> void:
	# chemin par defaut : axe vertical de l'arene (GATE_COL 6, CELL 64, 13 rangees)
	_path = PackedVector2Array()
	for r in range(1, 14):
		_path.append(Vector2(416.0, r * 64.0 + 32.0))


func setup(pid: String, pname: String, col: Color, diff: float) -> void:
	id = pid
	name = pname
	color = col
	difficulty = diff
	_sim.configure(GameState.START_KING_HP)
	_last_king = _sim.king_hp


func roster_entry() -> Dictionary:
	return {"id": id, "name": name, "avatar_url": "", "color": color,
		"is_local": false, "is_bot": true, "ready": false}


# --- reactions au bus ------------------------------------------------

func on_match_start(_seed: int, _roster: Array) -> void:
	_round = 0


func on_message(_from_id: String, channel: String, payload: Dictionary) -> void:
	if channel != "cmd" or _match_over:
		return
	match payload.get("t", ""):
		"round_start":
			_round = int(payload.get("n", _round + 1))
			var neutral := _neutral_wave(_round)
			_sim.begin_combat(_round, neutral, _incoming.duplicate())
			_incoming.clear()
			_think = -1.0
		"send":
			if String(payload.get("to", "")) == id:
				var troops: Dictionary = payload.get("troops", {})
				for k in troops:
					_incoming[k] = int(_incoming.get(k, 0)) + int(troops[k])
		"targets":
			_alive_targets = Array(payload.get("ids", []))
		"eliminated":
			if String(payload.get("id", "")) == id:
				_dead = true
				_sim.end_combat()
		"match_over":
			_match_over = true
		"round_begin", "round_end":
			# nouvelle phase de construction : on "reflechit" puis on se declare pret
			if not _dead and _think < 0.0:
				_think = 0.6 + randf() * 0.8


func tick(dt: float) -> void:
	if _match_over or _dead:
		return
	if _sim.combat_active():
		_sim.step(dt)
		if _sim.king_hp != _last_king:
			_last_king = _sim.king_hp
			out_cmd.emit("cmd", {"t": "king", "id": id, "hp": _sim.king_hp, "max": _sim.king_max})
		_snap_acc += dt
		if _snap_acc >= 0.16:
			_snap_acc = 0.0
			out_snapshot.emit(BoardDigest.to_bytes(_sim.digest(_path)))
		if _sim.board_clear():
			_sim.end_combat()
			out_cmd.emit("cmd", {"t": "wave_done", "id": id, "n": _round})
	elif _think >= 0.0:
		_think -= dt
		if _think < 0.0:
			_do_think()


func _do_think() -> void:
	_sim.build_phase(_round + 1, difficulty)
	# decide un envoi : cible = joueur vivant au roi le plus bas (via le host, on ne
	# connait pas l'etat -> on vise le joueur local par defaut)
	var target := _pick_target()
	if target != "":
		var troops := _compose_send()
		if not troops.is_empty():
			out_cmd.emit("cmd", {"t": "send", "from": id, "to": target, "troops": troops})
	out_cmd.emit("cmd", {"t": "ready", "id": id})
	# snapshot de fin de build (montre les nouvelles tours)
	out_snapshot.emit(BoardDigest.to_bytes(_sim.digest(_path)))


func _pick_target() -> String:
	for t in _alive_targets:
		if String(t) != id:
			return String(t)
	return ""


func _compose_send() -> Dictionary:
	var out: Dictionary = {}
	var budget: int = _sim.nourriture
	var pool: Array = _sim.casernes.keys()
	if pool.is_empty():
		return out
	var costs := {"grognard": 8, "rodeur": 7, "spectre": 14, "soigneur": 20, "colosse": 30, "sorcier": 26}
	var guard := 0
	while guard < 30:
		guard += 1
		var pick: String = pool[guard % pool.size()]
		var c: int = int(costs.get(pick, 12))
		if c <= budget:
			budget -= c
			out[pick] = int(out.get(pick, 0)) + 1
		elif budget < 7:
			break
	_sim.nourriture = budget
	return out


func _neutral_wave(round_no: int) -> Array:
	var d := WaveManager.wave_data(round_no)
	return Array(d.get("g", []))
