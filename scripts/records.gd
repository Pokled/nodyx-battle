extends Node
## Autoload `Records`.  Persiste les records du joueur (scope 'user', cle 'stats')
## et le classement de l'instance (scope 'instance', cle 'leaderboard') via le pont
## nodyx-activity.js -> POST /api/v1/extensions/<id>/storage.
##
## N'a d'effet que dans une activite Nodyx (web + window.NodyxBattle + jeton).
## Cf SPECS/NODYX_ACTIVITIES_CDC.md §10.
##
## Modele d'ecriture :
##   - chaque joueur ecrit SES stats en fin de partie (scope 'user')
##   - seul l'arbitre (Net.is_host(), siege 0) ecrit le classement (scope 'instance')

signal changed

var stats: Dictionary = {}        ## {games, wins, losses, best_wave}
var leaderboard: Array = []        ## [{id, name, wins, games}] trie, plafonne a 20

var _js: JavaScriptObject = null
var _recorded := false             ## une seule ecriture par partie


func _ready() -> void:
	if not _bridge():
		return
	# Nouvelle partie : GameState.reset() (main.gd) emet wave_changed(0).
	GameState.wave_changed.connect(func(w): if w == 0: _recorded = false)
	MatchDirector.match_over.connect(_on_match_over)
	GameState.game_over.connect(_on_solo_over)
	_js.call("loadStats")
	_js.call("loadBoard")
	_poll(0)


func _bridge() -> bool:
	if _js != null:
		return true
	if not OS.has_feature("web"):
		return false
	var w = JavaScriptBridge.get_interface("window")
	if w == null or not w.NodyxBattle:
		return false
	_js = w.NodyxBattle
	return true


## Le pont resout les lectures /storage de facon asynchrone : on rescrute le
## cache quelques secondes, comme PlayerAvatars._poll_local.
func _poll(tries: int) -> void:
	var s = JSON.parse_string(String(JavaScriptBridge.eval(
		"window.NodyxBattle && window.NodyxBattle.statsJson ? window.NodyxBattle.statsJson() : 'null'", true)))
	if s is Dictionary and s != stats:
		stats = s
		changed.emit()
	var b = JSON.parse_string(String(JavaScriptBridge.eval(
		"window.NodyxBattle && window.NodyxBattle.boardJson ? window.NodyxBattle.boardJson() : 'null'", true)))
	if b is Array and b != leaderboard:
		leaderboard = b
		changed.emit()
	if tries < 18:
		await get_tree().create_timer(0.4).timeout
		_poll(tries + 1)


func has_stats() -> bool:
	return not stats.is_empty()


# --- ecriture -----------------------------------------------------

func _bump_stats(won: bool, wave: int) -> void:
	var s := stats.duplicate()
	s["games"] = int(s.get("games", 0)) + 1
	if won:
		s["wins"] = int(s.get("wins", 0)) + 1
	else:
		s["losses"] = int(s.get("losses", 0)) + 1
	if wave > int(s.get("best_wave", 0)):
		s["best_wave"] = wave
	stats = s
	changed.emit()
	if _bridge():
		_js.call("saveStats", JSON.stringify(s))


func _on_match_over(winner_id: String) -> void:
	if _recorded:
		return
	_recorded = true
	var me := MatchDirector.local_id()
	_bump_stats(winner_id == me, MatchDirector.round_no)
	if Net.is_host():
		_write_leaderboard(winner_id)


func _on_solo_over(win: bool) -> void:
	if MatchDirector.active() or _recorded:
		return   # une COURSE AUX ROIS est comptee par _on_match_over
	_recorded = true
	_bump_stats(win, GameState.wave)


## L'arbitre fusionne l'issue de la partie dans le classement partage.
## Fusion idempotente (ON CONFLICT cote serveur) : au pire une ecriture de trop.
func _write_leaderboard(winner_id: String) -> void:
	if not _bridge():
		return
	var by_id: Dictionary = {}
	for e in leaderboard:
		if e is Dictionary and e.has("id"):
			by_id[String(e["id"])] = (e as Dictionary).duplicate()
	for id in MatchDirector.players:
		var ps = MatchDirector.players[id]
		if ps.is_bot:
			continue
		var row: Dictionary = by_id.get(id, {"id": id, "name": ps.name, "wins": 0, "games": 0})
		row["name"] = ps.name
		row["games"] = int(row.get("games", 0)) + 1
		if id == winner_id:
			row["wins"] = int(row.get("wins", 0)) + 1
		by_id[id] = row
	var arr: Array = by_id.values()
	arr.sort_custom(func(a, b):
		var wa := int(a.get("wins", 0)); var wb := int(b.get("wins", 0))
		if wa != wb:
			return wa > wb
		return int(a.get("games", 0)) < int(b.get("games", 0)))
	if arr.size() > 20:
		arr = arr.slice(0, 20)
	leaderboard = arr
	changed.emit()
	_js.call("saveBoard", JSON.stringify(arr))
