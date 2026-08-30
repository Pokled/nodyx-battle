extends Node
## Autoload global. Etat de la partie: economie, vague courante, PV du roi, phase.

signal minerai_changed(value: int)
signal nourriture_changed(value: int)
signal wave_changed(value: int)
signal king_hp_changed(value: int, max_value: int)
signal phase_changed(phase: int)
signal wave_cleared(wave: int)
signal game_over(win: bool)
signal champion(cur: float, maxhp: float, alive: bool)

enum Phase { BUILD, COMBAT }
enum Mode { SOLO, DUEL }

var mode := Mode.SOLO   ## fixe par l'ecran de setup ; NON reinitialise par reset()

const START_MINERAI := 175
const START_NOURRITURE := 60
const START_KING_HP := 100
const BASE_INCOME := 10
const WIN_WAVE := 20

var king_max := START_KING_HP

var minerai := 0
var nourriture := 0     ## monnaie de garnison : troupes + casernes
var wave := 0
var king_hp := 0
var phase := Phase.BUILD
var finished := false
var endless := false   ## continue apres la vague WIN_WAVE (plus de victoire, on tient)
var wave_recap := {}   ## rempli par WaveManager a la fin de chaque vague
var towers_built := 0  ## tours actuellement sur le plateau -> majoration de prix (Catalog)


func _ready() -> void:
	reset()


func reset() -> void:
	king_max = START_KING_HP
	minerai = START_MINERAI
	nourriture = START_NOURRITURE
	wave = 0
	king_hp = START_KING_HP
	phase = Phase.BUILD
	finished = false
	endless = false
	wave_recap = {}
	towers_built = 0
	minerai_changed.emit(minerai)
	nourriture_changed.emit(nourriture)
	wave_changed.emit(wave)
	king_hp_changed.emit(king_hp, king_max)
	phase_changed.emit(phase)


func heal_king(amount: int) -> void:
	king_max += amount
	king_hp = mini(king_max, king_hp + amount)
	king_hp_changed.emit(king_hp, king_max)


func can_afford(cost: int) -> bool:
	return minerai >= cost


func spend(cost: int) -> bool:
	if not can_afford(cost):
		return false
	minerai -= cost
	minerai_changed.emit(minerai)
	return true


func add_minerai(amount: int) -> void:
	minerai += amount
	minerai_changed.emit(minerai)


func add_nourriture(amount: int) -> void:
	nourriture += amount
	nourriture_changed.emit(nourriture)


func spend_nourriture(cost: int) -> bool:
	if nourriture < cost:
		return false
	nourriture -= cost
	nourriture_changed.emit(nourriture)
	return true


func take_king_damage(amount: int) -> void:
	if finished:
		return
	king_hp = maxi(0, king_hp - amount)
	king_hp_changed.emit(king_hp, king_max)
	if king_hp <= 0:
		finished = true
		game_over.emit(false)


func set_phase(p: Phase) -> void:
	phase = p
	phase_changed.emit(phase)


func win() -> void:
	if finished:
		return
	finished = true
	game_over.emit(true)


## Reprise en mode sans fin apres la victoire vague 20.
func resume_endless() -> void:
	finished = false
	endless = true
	set_phase(Phase.BUILD)
	wave_changed.emit(wave)


func next_wave() -> void:
	wave += 1
	wave_changed.emit(wave)
