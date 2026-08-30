extends Node
## Autoload. Mode DUEL : adversaire IA ABSTRAIT (bloc de stats) + economie d'envoi.
## Tes envois sont resolus contre `enemy_defense` -> degats au roi adverse.
## L'IA depense sa nourriture en defense + en envois qui arrivent dans ta vague.

signal changed
signal attack_resolved(king_dmg: int, breach: float)   ## apres resolution de TON attaque

const KING_HP := 100

## nourriture par unite envoyee
const SEND_COST := {
	"grognard": 8, "rodeur": 7, "spectre": 14, "soigneur": 20, "colosse": 30, "sorcier": 26,
}
## "puissance de perce" d'une unite face a une defense
const SEND_POWER := {
	"grognard": 5.0, "rodeur": 4.0, "spectre": 8.0, "soigneur": 6.0, "colosse": 16.0, "sorcier": 12.0,
}
const SENDABLE := ["grognard", "rodeur", "spectre", "soigneur", "colosse", "sorcier"]

var enemy_king_hp := KING_HP
var enemy_king_max := KING_HP
var enemy_nourriture := 0
var enemy_defense := 10.0

var unlocked: Dictionary = {}    ## troop_id -> niveau de caserne (1+)
var your_queue: Dictionary = {}  ## troop_id -> nombre a envoyer a la prochaine vague
var ai_queue: Dictionary = {}    ## troop_id -> nombre que l'IA t'envoie
var last_king_dmg := 0


func reset() -> void:
	enemy_king_hp = KING_HP
	enemy_king_max = KING_HP
	enemy_nourriture = 40
	enemy_defense = 10.0
	unlocked.clear()
	your_queue.clear()
	ai_queue.clear()
	last_king_dmg = 0
	changed.emit()


func active() -> bool:
	## le DUEL-vs-IA legacy ne tourne que si aucun vrai match multijoueur n'est en cours
	return GameState.mode == GameState.Mode.DUEL and not MatchDirector.active()


# --- casernes du joueur -------------------------------------------------

func unlock(troop_id: String, level: int) -> void:
	unlocked[troop_id] = maxi(int(unlocked.get(troop_id, 0)), level)
	changed.emit()


func relock_missing(present_ids: Array) -> void:
	## appele apres une revente de caserne : garde seulement les types encore poses
	for id in unlocked.keys():
		if id not in present_ids:
			unlocked.erase(id)
			your_queue.erase(id)
	changed.emit()


func can_send(troop_id: String) -> bool:
	return unlocked.has(troop_id) and GameState.nourriture >= SEND_COST.get(troop_id, 999)


func queue_send(troop_id: String) -> bool:
	if not can_send(troop_id):
		return false
	if not GameState.spend_nourriture(int(SEND_COST[troop_id])):
		return false
	your_queue[troop_id] = int(your_queue.get(troop_id, 0)) + 1
	changed.emit()
	return true


func unqueue_send(troop_id: String) -> void:
	if int(your_queue.get(troop_id, 0)) > 0:
		your_queue[troop_id] -= 1
		if your_queue[troop_id] <= 0:
			your_queue.erase(troop_id)
		GameState.add_nourriture(int(SEND_COST[troop_id]))
		changed.emit()


func queue_total() -> int:
	var n := 0
	for k in your_queue:
		n += int(your_queue[k])
	return n


# --- resolution de TON attaque (au debut du combat) --------------------

func resolve_your_attack() -> void:
	last_king_dmg = 0
	if your_queue.is_empty():
		return
	var power := 0.0
	for id in your_queue:
		var lvl := int(unlocked.get(id, 1))
		power += float(your_queue[id]) * float(SEND_POWER.get(id, 3.0)) * (1.0 + 0.18 * (lvl - 1))
	your_queue.clear()

	var breach := clampf((power - enemy_defense) / maxf(1.0, power), 0.0, 0.85)
	var dmg := int(round(breach * power * 0.5))
	# une grosse offensive erode un peu la defense adverse pour la manche suivante
	enemy_defense = maxf(4.0, enemy_defense - power * 0.14)
	if dmg > 0:
		enemy_take_damage(dmg)
	last_king_dmg = dmg
	attack_resolved.emit(dmg, breach)


func enemy_take_damage(n: int) -> void:
	enemy_king_hp = maxi(0, enemy_king_hp - n)
	changed.emit()
	if enemy_king_hp <= 0 and not GameState.finished:
		GameState.win()


# --- tour de l'IA (pendant TA phase de construction) -------------------

func ai_take_turn(wave: int) -> void:
	if not active() or GameState.finished:
		return
	# revenu
	enemy_nourriture += 14 + wave * 2 + int(enemy_defense * 0.1)
	# croissance passive de defense (elle "construit" quoi qu'il arrive)
	enemy_defense += 2.0 + wave * 0.35

	# repartition : plus agressive si elle est en tete, plus defensive si menacee
	var hp_frac := float(enemy_king_hp) / float(enemy_king_max)
	var atk_share := clampf(0.45 + (0.5 - hp_frac) * -0.4, 0.2, 0.6)
	var budget := enemy_nourriture
	var to_def := int(budget * (1.0 - atk_share))
	var to_atk := budget - to_def
	enemy_nourriture = 0
	enemy_defense += to_def * 0.5

	# compose l'envoi : masse de base + une piece lourde selon la vague
	ai_queue.clear()
	var pool := ["grognard", "rodeur"]
	if wave >= 4:
		pool.append("spectre")
	if wave >= 6:
		pool.append("colosse")
	if wave >= 8:
		pool.append("sorcier")
	var guard := 0
	while to_atk >= 7 and guard < 40:
		guard += 1
		var pick: String = pool[guard % pool.size()]
		var c: int = int(SEND_COST[pick])
		if c <= to_atk:
			to_atk -= c
			ai_queue[pick] = int(ai_queue.get(pick, 0)) + 1
	changed.emit()


func drain_ai_queue() -> Array:
	## appele par WaveManager : liste plate de troop_id a faire apparaitre
	var out: Array = []
	for id in ai_queue:
		for _i in int(ai_queue[id]):
			out.append(id)
	ai_queue.clear()
	changed.emit()
	return out


func ai_incoming_summary() -> String:
	if ai_queue.is_empty():
		return ""
	var parts := PackedStringArray()
	for id in ai_queue:
		parts.append("%d %s" % [int(ai_queue[id]), Enemy.TYPES.get(id, {"label": id})["label"]])
	return "  ".join(parts)
