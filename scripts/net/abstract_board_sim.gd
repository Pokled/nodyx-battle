class_name AbstractBoardSim
extends RefCounted
## Mini-simulation de plateau pour un BOT (backend `local`) : pas l'arene complete,
## juste assez pour (a) produire des degats au roi credibles et (b) alimenter un
## GhostBoard avec un flux d'unites qui descendent le chemin.  Piloté en temps reel
## par `bot_commander.gd` pendant la phase COMBAT.

const CELL := 64.0

var king_hp := 100
var king_max := 100
var minerai := 160
var nourriture := 60
var towers: Array = []            ## [{cx,cy,type,lvl}]
var casernes: Dictionary = {}     ## troop_id -> niveau

var _units: Array = []            ## [{id, prog, hp, hpmax, type, team, from_send}]
var _uid := 0
var _spawn_queue: Array = []      ## [{type, at}] temps de spawn relatif
var _clock := 0.0
var _combat := false
var _round := 0
var _dps := 6.0                   ## DPS agrege des tours, recalcule au build

const _TYPE_HP := {
	"grognard": 40.0, "rodeur": 24.0, "colosse": 165.0, "soigneur": 55.0,
	"spectre": 26.0, "sorcier": 60.0,
}


func configure(khp: int) -> void:
	king_hp = khp
	king_max = khp


## Le bot "construit" : ajoute des tours / casernes selon un budget grossier.
func build_phase(round_no: int, difficulty: float) -> void:
	_round = round_no
	# revenu
	minerai += 60 + round_no * 14
	nourriture += 18 + round_no * 4
	# pose de tours tant qu'on a du budget (grille 9x9 interne, cases libres)
	var want := int(clampf(difficulty * (2.0 + round_no * 0.6), 1.0, 4.0))
	var kinds := ["canon", "gatling", "mortier", "givre"]
	for _i in want:
		if minerai < 70:
			break
		var cx := 2 + (towers.size() * 3) % 8
		var cy := 3 + (towers.size() * 2) % 8
		if _cell_taken(cx, cy):
			cx = 2 + randi() % 8
			cy = 3 + randi() % 8
		towers.append({"cx": cx, "cy": cy, "type": kinds[towers.size() % kinds.size()], "lvl": 1 + int(round_no / 4.0)})
		minerai -= 75
	# ameliore une tour existante de temps en temps
	if not towers.is_empty() and minerai > 140 and round_no % 2 == 0:
		towers[randi() % towers.size()]["lvl"] += 1
		minerai -= 140
	# casernes (offensif)
	if nourriture > 45 and round_no >= 2:
		var troop: String = ["grognard", "rodeur", "spectre", "colosse"][round_no % 4]
		casernes[troop] = int(casernes.get(troop, 0)) + 1
		nourriture -= 45
	_recompute_dps()


func _recompute_dps() -> void:
	var d := 0.0
	var tab := {"canon": 16.0, "gatling": 20.0, "mortier": 14.0, "givre": 10.0}
	for t in towers:
		var base: float = tab.get(t["type"], 12.0)
		d += base * (1.0 + 0.6 * (int(t["lvl"]) - 1))
	_dps = maxf(2.0, d)


func _cell_taken(cx: int, cy: int) -> bool:
	for t in towers:
		if t["cx"] == cx and t["cy"] == cy:
			return true
	return false


## Prepare la vague : file de spawn (vague neutre partagee + envois recus).
func begin_combat(round_no: int, neutral: Array, incoming: Dictionary) -> void:
	_combat = true
	_round = round_no
	_clock = 0.0
	_units.clear()
	_spawn_queue.clear()
	var t := 0.0
	for grp in neutral:
		var n: int = int(grp.get("n", 0))
		var gap: float = float(grp.get("gap", 0.5))
		for _i in n:
			_spawn_queue.append({"type": String(grp.get("t", "grognard")), "at": t, "send": false})
			t += gap
	# envois recus : apres la vague neutre
	var s := t + 1.0
	for troop_id in incoming:
		for _i in int(incoming[troop_id]):
			_spawn_queue.append({"type": troop_id, "at": s, "send": true})
			s += 0.3


func end_combat() -> void:
	_combat = false
	_units.clear()
	_spawn_queue.clear()


func combat_active() -> bool:
	return _combat


func board_clear() -> bool:
	if not _combat:
		return false
	if _spawn_queue.is_empty() and _units.is_empty():
		return true
	return _clock > 45.0        ## garde-fou : la manche ne traine pas indefiniment


## Avance la sim de `dt`.  Retourne les degats infliges au roi ce pas.
func step(dt: float) -> int:
	if not _combat:
		return 0
	_clock += dt
	# spawns dus
	var still: Array = []
	for s in _spawn_queue:
		if s["at"] <= _clock:
			_uid += 1
			var hpm: float = _TYPE_HP.get(s["type"], 40.0) * (1.0 + _round * 0.14)
			_units.append({"id": _uid, "prog": 0.0, "hp": hpm, "hpmax": hpm,
				"type": s["type"], "team": 1, "from_send": s["send"]})
		else:
			still.append(s)
	_spawn_queue = still

	var dmg := 0
	var speed := 0.16 + _round * 0.004       ## progression/seconde
	var per_unit_dps := _dps / maxf(1.0, float(_units.size())) if not _units.is_empty() else 0.0
	var alive: Array = []
	for u in _units:
		u["hp"] -= per_unit_dps * dt
		if u["hp"] <= 0.0:
			continue
		u["prog"] += speed * dt
		if u["prog"] >= 1.0:
			var leak := 2 + _round + (3 if u["from_send"] else 0)
			dmg += leak
			continue
		alive.append(u)
	_units = alive
	if dmg > 0:
		king_hp = maxi(0, king_hp - dmg)
	return dmg


## Etat pour le GhostBoard (meme forme que BoardDigest.capture).
func digest(path: PackedVector2Array) -> Dictionary:
	var un: Array = []
	for u in _units:
		var p := _pos_on_path(path, u["prog"])
		un.append([u["id"], int(p.x), int(p.y),
			int(clampf(u["hp"] / maxf(1.0, u["hpmax"]), 0.0, 1.0) * 255.0),
			BoardDigest.type_idx(u["type"]), 1, 2 if u["from_send"] else 0])
	var tw: Array = []
	for t in towers:
		tw.append([int(t["cx"]), int(t["cy"]), BoardDigest.type_idx(t["type"]), int(t["lvl"])])
	return {"k": king_hp, "km": king_max, "o": minerai, "f": nourriture, "w": _round,
		"ph": 1 if _combat else 0, "tw": tw, "un": un}


func _pos_on_path(path: PackedVector2Array, prog: float) -> Vector2:
	if path.size() < 2:
		return Vector2.ZERO
	var f := clampf(prog, 0.0, 1.0) * float(path.size() - 1)
	var i := int(f)
	if i >= path.size() - 1:
		return path[path.size() - 1]
	return path[i].lerp(path[i + 1], f - float(i))
