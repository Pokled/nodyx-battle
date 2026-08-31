extends Node
## Autoload `MatchDirector`.  Cerveau du match FFA "course aux rois" (2-8).
## Actif quand `Net.in_match()` et roster > 1.  Barriere de manche pilotee par le
## host, envois cibles, elimination, victoire.  Le SOLO et le DUEL-vs-IA legacy
## ne passent pas par ici (gardes par `active()`).

signal roster_changed
signal phase_changed(phase: int)                 ## Phase
signal round_started(n: int, wave_seed: int)
signal player_digest(id: String, digest: Dictionary)
signal player_eliminated(id: String)
signal match_over(winner_id: String)
signal incoming_changed
signal resync_pending                             ## on a rejoint, on attend l'etat de l'hote
signal resumed                                    ## etat du match restaure apres reconnexion

enum Phase { IDLE, BUILD, COMBAT, DONE }

const BUILD_DEADLINE := 60.0

class PlayerState:
	var id := ""
	var name := ""
	var avatar_url := ""
	var color := Color.WHITE
	var king_hp := 100
	var king_max := 100
	var alive := true
	var is_local := false
	var is_bot := false
	var ready := false
	var wave_done := false
	var digest: Dictionary = {}

var players: Dictionary = {}          ## id -> PlayerState
var phase := Phase.IDLE
var round_no := 0
var wave_seed := 0
var winner := ""
var cmd_log: Array = []               ## journal ordonne (base d'un validateur re-sim futur)

var _incoming: Dictionary = {}        ## troop_id -> n (recus, en attente de la manche)
var _arena: Node = null
var _gs: Node = null
var _waves: Node = null
var _deadline := -1.0
var _digest_acc := 0.0
var _straggler := -1.0        ## compte a rebours apres le 1er wave_done d'une manche
var _resumed := false         ## on a rejoint un match en cours (etat restaure par l'hote)
var _grace: Dictionary = {}   ## id -> secondes avant elimination (fenetre de reconnexion)
var expect_resume := false    ## pose par title.gd : on entre dans main.tscn pour un match deja lance
var _resync_wait := -1.0      ## filet : delai avant de repartir en BUILD si aucun match_state ne vient

const RECONNECT_GRACE := 45.0


func _ready() -> void:
	Net.match_started.connect(_on_match_started)
	Net.message.connect(_on_message)
	Net.snapshot.connect(_on_snapshot)
	Net.player_left.connect(_on_player_left)
	Net.host_changed.connect(_on_host_changed)
	Net.sync_requested.connect(_on_sync_requested)
	set_process(false)


func active() -> bool:
	return Net.in_match() and players.size() > 1


func local_id() -> String:
	return Net.local_id()


func local_state() -> PlayerState:
	return players.get(local_id(), null)


func opponents() -> Array:
	var out: Array = []
	for id in players:
		if id != local_id():
			out.append(players[id])
	return out


func living_ids() -> Array:
	var out: Array = []
	for id in players:
		if players[id].alive:
			out.append(id)
	return out


# --- cycle de vie du match ----------------------------------------

func _on_match_started(seed_val: int, roster: Array) -> void:
	players.clear()
	cmd_log.clear()
	_incoming.clear()
	_grace.clear()
	_resumed = false
	expect_resume = false
	_resync_wait = -1.0
	wave_seed = seed_val
	winner = ""
	round_no = 0
	for e in roster:
		var ps := PlayerState.new()
		ps.id = String(e.get("id", ""))
		ps.name = String(e.get("name", ps.id))
		ps.avatar_url = String(e.get("avatar_url", ""))
		ps.color = e.get("color", Color.WHITE)
		ps.is_bot = bool(e.get("is_bot", false))
		ps.is_local = ps.id == local_id()
		ps.king_hp = GameState.START_KING_HP
		ps.king_max = GameState.START_KING_HP
		players[ps.id] = ps
	phase = Phase.IDLE
	roster_changed.emit()


## Appele par main._ready quand l'arene locale est prete.
func attach(arena: Node, gs: Node, waves: Node) -> void:
	if not active():
		return
	_arena = arena
	_gs = gs
	_waves = waves
	set_process(true)
	if not GameState.king_hp_changed.is_connected(_on_local_king):
		GameState.king_hp_changed.connect(_on_local_king)
	# Reconnexion : l'hote a deja restaure manche / phase / PV. On ne repart
	# PAS a la manche 1 ; on spectate la manche en cours et on rejoue au
	# prochain round_begin (le plateau se reconstruit vide en BUILD).
	if _resumed or round_no > 0:
		phase_changed.emit(phase)
		return
	if expect_resume:
		# On entre dans main.tscn pour un match deja lance mais l'etat detaille
		# n'est pas encore arrive : on le demande et on patiente en spectateur.
		phase = Phase.COMBAT
		phase_changed.emit(phase)
		resync_pending.emit()
		Net.send("cmd", {"t": "resync_plz"})
		_resync_wait = 6.0    # filet : personne ne repond -> on repart en BUILD
		return
	_begin_build(1)


func detach() -> void:
	set_process(false)
	_arena = null
	_gs = null
	_waves = null


# --- barriere de manche -----------------------------------------

func _begin_build(n: int) -> void:
	round_no = n
	phase = Phase.BUILD
	for id in players:
		players[id].ready = not players[id].alive       ## un elimine "compte comme pret"
		players[id].wave_done = not players[id].alive
	_deadline = BUILD_DEADLINE if Net.is_host() else -1.0
	phase_changed.emit(phase)
	if Net.is_host():
		Net.send("cmd", {"t": "round_begin", "n": n})   ## nudge : les bots/pairs relancent leur build


func set_local_ready(on := true) -> void:
	if phase != Phase.BUILD:
		return
	_broadcast_cmd({"t": "ready", "id": local_id(), "on": on})


func _try_start_round() -> void:
	if not Net.is_host() or phase != Phase.BUILD:
		return
	for id in players:
		if players[id].alive and not players[id].ready:
			return
	_deadline = -1.0
	var seed_r := wave_seed ^ (round_no * 0x9E3779B9)
	_broadcast_cmd({"t": "targets", "ids": living_ids()})
	_broadcast_cmd({"t": "round_start", "n": round_no, "seed": seed_r})


func _on_round_start(n: int, seed_r: int) -> void:
	round_no = n
	wave_seed = seed_r
	phase = Phase.COMBAT
	for id in players:
		players[id].wave_done = not players[id].alive
	_digest_acc = 0.0
	phase_changed.emit(phase)
	round_started.emit(n, seed_r)
	if _waves != null and _waves.has_method("start_wave"):
		_waves.start_wave(seed_r)


func on_local_wave_done() -> void:
	if phase == Phase.COMBAT:
		_broadcast_cmd({"t": "wave_done", "id": local_id(), "n": round_no})


func _try_end_round() -> void:
	if not Net.is_host() or phase != Phase.COMBAT:
		return
	var any_done := false
	for id in players:
		if players[id].alive and players[id].wave_done:
			any_done = true
		if players[id].alive and not players[id].wave_done:
			if any_done and _straggler < 0.0:
				_straggler = 20.0     ## laisse 20 s aux retardataires
			return
	_straggler = -1.0
	_broadcast_cmd({"t": "round_end", "n": round_no})


func _on_round_end() -> void:
	if phase == Phase.DONE:
		return
	_straggler = -1.0
	_begin_build(round_no + 1)


# --- envois cibles --------------------------------------------

func send_troops(target_id: String, troops: Dictionary) -> void:
	if target_id == "" or troops.is_empty():
		return
	_broadcast_cmd({"t": "send", "from": local_id(), "to": target_id, "troops": troops})


func drain_incoming() -> Array:
	var out: Array = []
	for k in _incoming:
		for _i in int(_incoming[k]):
			out.append(k)
	_incoming.clear()
	incoming_changed.emit()
	return out


func incoming_summary() -> Dictionary:
	return _incoming.duplicate()


# --- degats au roi / elimination -----------------------------

func _on_local_king(hp: int, mx: int) -> void:
	if not active():
		return
	var ps: PlayerState = players.get(local_id(), null)
	if ps == null or (ps.king_hp == hp and ps.king_max == mx):
		return
	ps.king_hp = hp
	ps.king_max = mx
	_broadcast_cmd({"t": "king", "id": local_id(), "hp": hp, "max": mx})
	roster_changed.emit()


func _apply_king(id: String, hp: int, mx: int) -> void:
	var ps: PlayerState = players.get(id, null)
	if ps == null:
		return
	ps.king_hp = hp
	ps.king_max = mx
	roster_changed.emit()
	if hp <= 0 and ps.alive:
		if Net.is_host():
			_broadcast_cmd({"t": "eliminated", "id": id})


func _apply_eliminated(id: String) -> void:
	var ps: PlayerState = players.get(id, null)
	if ps == null or not ps.alive:
		return
	ps.alive = false
	ps.ready = true
	ps.wave_done = true
	player_eliminated.emit(id)
	roster_changed.emit()
	var alive := living_ids()
	if Net.is_host() and alive.size() <= 1 and phase != Phase.DONE:
		_broadcast_cmd({"t": "match_over", "winner": alive[0] if alive.size() == 1 else ""})


func _apply_match_over(w: String) -> void:
	winner = w
	phase = Phase.DONE
	phase_changed.emit(phase)
	match_over.emit(w)


# --- bus -----------------------------------------------------

func _broadcast_cmd(payload: Dictionary) -> void:
	cmd_log.append(payload)
	Net.send("cmd", payload)
	_apply_cmd(local_id(), payload)     ## le bus ne renvoie pas a l'expediteur


func _on_message(from_id: String, channel: String, payload: Dictionary) -> void:
	if channel == "cmd":
		_apply_cmd(from_id, payload)


func _apply_cmd(from_id: String, p: Dictionary) -> void:
	# Tout signe de vie d'un joueur en fenetre de reconnexion annule sa
	# future elimination.
	if from_id != "" and _grace.has(from_id):
		_grace.erase(from_id)
	match p.get("t", ""):
		"resync_plz":
			_on_sync_requested(from_id)
		"match_state":
			_apply_match_state(p)
		"ready":
			var ps: PlayerState = players.get(String(p.get("id", from_id)), null)
			if ps != null:
				ps.ready = bool(p.get("on", true))
				roster_changed.emit()
				_try_start_round()
		"targets", "round_begin":
			pass
		"round_start":
			_on_round_start(int(p.get("n", round_no)), int(p.get("seed", wave_seed)))
		"send":
			if String(p.get("to", "")) == local_id():
				var trp: Dictionary = p.get("troops", {})
				for k in trp:
					_incoming[k] = int(_incoming.get(k, 0)) + int(trp[k])
				incoming_changed.emit()
		"king":
			_apply_king(String(p.get("id", "")), int(p.get("hp", 0)), int(p.get("max", 100)))
		"wave_done":
			var wp: PlayerState = players.get(String(p.get("id", from_id)), null)
			if wp != null:
				wp.wave_done = true
				_try_end_round()
		"round_end":
			_on_round_end()
		"eliminated":
			_apply_eliminated(String(p.get("id", "")))
		"match_over":
			_apply_match_over(String(p.get("winner", "")))


func _on_snapshot(from_id: String, bytes: PackedByteArray) -> void:
	if not active():
		return
	var d := BoardDigest.from_bytes(bytes)
	if d.is_empty():
		return
	var ps: PlayerState = players.get(from_id, null)
	if ps != null:
		ps.digest = d
		ps.king_hp = int(d.get("k", ps.king_hp))
		ps.king_max = int(d.get("km", ps.king_max))
	player_digest.emit(from_id, d)


func _on_player_left(id: String) -> void:
	# Un onglet qui plante ou une coupure passagere ne doit pas eliminer
	# instantanement : on arme une fenetre de reconnexion. Tout cmd du joueur,
	# ou son retour dans le salon, annule le compte a rebours (cf _apply_cmd,
	# _on_host_changed via lobby).
	if players.has(id) and players[id].alive and not _grace.has(id):
		_grace[id] = RECONNECT_GRACE


func _on_host_changed(now_host: bool) -> void:
	# Le siege 0 a quitte le salon en cours de partie : un autre membre reprend
	# l'arbitrage. Il suivait deja le bus cmd, il ne lui manque que d'armer les
	# echeances host-only.
	if not active():
		return
	if now_host:
		if phase == Phase.BUILD:
			_deadline = BUILD_DEADLINE
			_try_start_round()
		elif phase == Phase.COMBAT:
			_try_end_round()
	else:
		_deadline = -1.0
		_straggler = -1.0


func _on_sync_requested(from_id: String) -> void:
	# Un pair (re)demarre : l'arbitre lui renvoie l'etat detaille du match.
	if not Net.is_host() or phase == Phase.IDLE or players.is_empty():
		return
	var ps_arr: Array = []
	for id in players:
		var ps: PlayerState = players[id]
		ps_arr.append({"id": id, "hp": ps.king_hp, "mx": ps.king_max, "al": ps.alive})
	var msg := {"t": "match_state", "seed": wave_seed, "n": round_no, "ph": phase, "players": ps_arr}
	if from_id != "":
		Net.send("cmd", msg, true, from_id)
	else:
		Net.send("cmd", msg)


## Recu par un client qui vient de (re)joindre un match en cours.
func _apply_match_state(p: Dictionary) -> void:
	if _resumed or round_no > 0:
		return   # deja restaure, on ne se fait pas remonter le temps
	wave_seed = int(p.get("seed", wave_seed))
	round_no = maxi(1, int(p.get("n", 1)))
	phase = int(p.get("ph", Phase.BUILD)) as Phase
	for e in p.get("players", []):
		var ps: PlayerState = players.get(String(e.get("id", "")), null)
		if ps == null:
			continue
		ps.king_hp = int(e.get("hp", ps.king_hp))
		ps.king_max = int(e.get("mx", ps.king_max))
		ps.alive = bool(e.get("al", true))
		ps.ready = not ps.alive
		ps.wave_done = not ps.alive
	_resumed = true
	expect_resume = false
	_resync_wait = -1.0
	roster_changed.emit()
	phase_changed.emit(phase)
	resumed.emit()


# --- diffusion du digest local (appele par main durant COMBAT) ----

func _process(delta: float) -> void:
	# Filet de reconnexion : si l'etat detaille n'est jamais venu, on repart.
	if _resync_wait > 0.0:
		_resync_wait -= delta
		if _resync_wait <= 0.0:
			_resync_wait = -1.0
			if not _resumed and expect_resume:
				expect_resume = false
				_begin_build(1)

	# Fenetre de reconnexion : quand elle expire, l'arbitre elimine.
	if not _grace.is_empty():
		for id in _grace.keys():
			_grace[id] -= delta
			if _grace[id] <= 0.0:
				_grace.erase(id)
				if Net.is_host() and players.has(id) and players[id].alive:
					_broadcast_cmd({"t": "eliminated", "id": id})

	if _deadline > 0.0:
		_deadline -= delta
		if _deadline <= 0.0:
			_deadline = -1.0
			# echeance : on force les retardataires en "pret"
			for id in players:
				players[id].ready = true
			_try_start_round()

	if phase == Phase.COMBAT:
		if _straggler > 0.0:
			_straggler -= delta
			if _straggler <= 0.0:
				_straggler = -1.0
				if Net.is_host():
					for id in players:
						players[id].wave_done = true
					_broadcast_cmd({"t": "round_end", "n": round_no})
		if _arena != null and _gs != null:
			_digest_acc += delta
			if _digest_acc >= 0.16:
				_digest_acc = 0.0
				Net.broadcast_snapshot(BoardDigest.to_bytes(BoardDigest.capture(_arena, _gs)))
