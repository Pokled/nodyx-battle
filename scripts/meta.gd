extends Node
## Autoload `Meta`. Bonus de partie: 3 specialites (ecran setup) + renforts (boons)
## tires entre les vagues. `reset()` + `apply_specs()` dans main._ready (garde `specs`).

signal changed

var dmg_mult: Dictionary = {}
var range_bonus: Dictionary = {}
var cd_mult: Dictionary = {}
var cost_mult: Dictionary = {}
var fighter_hp_bonus := 0.0
var fighter_regen := 0.0
var peon_yield_bonus := 0.0
var peon_max := 16
var king_hp_bonus := 0
var sell_refund := 0.7
var interest := 0.0
var frost_bonus := 0.0
var freeze := false
var splash_bonus := 0.0
var slow_vuln := 0.0

var specs: Array = []
var relics: Array = []

## id -> {label, tier(0=commun,1=rare), desc}
const BOONS := {
	"dmg_canon":    {"label": "Canons affutes",    "tier": 0, "desc": "+30% degats des Canons"},
	"dmg_gatling":  {"label": "Barillets huiles",  "tier": 0, "desc": "+25% degats des Gatling"},
	"dmg_mortier":  {"label": "Obus lourds",       "tier": 0, "desc": "+30% degats des Mortiers"},
	"dmg_archere":  {"label": "Fers barbeles",     "tier": 0, "desc": "+30% degats des Archeres"},
	"splash":       {"label": "Poudre instable",   "tier": 0, "desc": "+16 rayon d'explosion (Mortier)"},
	"frost":        {"label": "Coeur de glace",    "tier": 0, "desc": "Ralentissement du Givre renforce"},
	"rng_archere":  {"label": "Fleches longues",   "tier": 0, "desc": "+45 portee des Archeres"},
	"fighter_hp":   {"label": "Armures renforcees","tier": 0, "desc": "+40 PV pour les unites"},
	"peon":         {"label": "Filon riche",       "tier": 0, "desc": "+0.4 minerai/s par peon"},
	"king":         {"label": "Muraille du roi",   "tier": 0, "desc": "+22 PV max du roi (soigne aussi)"},
	"cost_tower":   {"label": "Chantier efficace", "tier": 0, "desc": "-12% cout des tours"},
	"cd_all":       {"label": "Mecanismes rodes",  "tier": 1, "desc": "-12% cooldown de toutes les tours"},
	"freeze":       {"label": "Gel absolu",        "tier": 1, "desc": "Le Givre GELE brievement (stun)"},
	"slow_vuln":    {"label": "Fragilite glacee",  "tier": 1, "desc": "+25% degats sur les ennemis ralentis"},
	"rng_all":      {"label": "Optiques longues",  "tier": 1, "desc": "+22 portee de toutes les tours"},
	"fighter_regen":{"label": "Banniere de soin",  "tier": 1, "desc": "Les unites regenerent 6 PV/s"},
	"interest":     {"label": "Coffre a interets", "tier": 1, "desc": "+5% du minerai en fin de vague (plafonne)"},
	"refund":       {"label": "Marche equitable",  "tier": 1, "desc": "Revente a 95%"},
}


func _ready() -> void:
	reset()


func reset() -> void:
	dmg_mult = {}
	range_bonus = {}
	cd_mult = {}
	cost_mult = {}
	fighter_hp_bonus = 0.0
	fighter_regen = 0.0
	peon_yield_bonus = 0.0
	peon_max = 16
	king_hp_bonus = 0
	sell_refund = 0.7
	interest = 0.0
	frost_bonus = 0.0
	freeze = false
	splash_bonus = 0.0
	slow_vuln = 0.0
	relics = []


func _mul(t: String, v: float) -> void:
	dmg_mult[t] = float(dmg_mult.get(t, 1.0)) + v


func _rng(t: String, v: float) -> void:
	range_bonus[t] = float(range_bonus.get(t, 0.0)) + v


func _cd(t: String, m: float) -> void:
	cd_mult[t] = float(cd_mult.get(t, 1.0)) * m


func _cost(cat: String, m: float) -> void:
	cost_mult[cat] = float(cost_mult.get(cat, 1.0)) * m


func dmg(t: String) -> float: return float(dmg_mult.get(t, 1.0))
func rng(t: String) -> float: return float(range_bonus.get(t, 0.0))
func cd(t: String) -> float: return float(cd_mult.get(t, 1.0))
func cost(cat: String) -> float: return float(cost_mult.get(cat, 1.0))


func apply_specs() -> void:
	for id in specs:
		if Specs.SPECS.has(id):
			Specs.apply(id)
			relics.append("spec:" + id)
	changed.emit()


func draw_choices(n := 3) -> Array:
	var common := []
	var rare := []
	for id in BOONS:
		if id in relics:
			continue
		if int(BOONS[id]["tier"]) == 0:
			common.append(id)
		else:
			rare.append(id)
	common.shuffle()
	rare.shuffle()
	var out := []
	if not rare.is_empty() and randf() < 0.4:
		out.append(rare.pop_front())
	while out.size() < n and not common.is_empty():
		out.append(common.pop_front())
	while out.size() < n and not rare.is_empty():
		out.append(rare.pop_front())
	return out


func apply(id: String) -> void:
	if not BOONS.has(id):
		return
	match id:
		"dmg_canon": _mul("canon", 0.30)
		"dmg_gatling": _mul("gatling", 0.25)
		"dmg_mortier": _mul("mortier", 0.30)
		"dmg_archere": _mul("archere", 0.30)
		"splash": splash_bonus += 16.0
		"frost": frost_bonus += 0.14
		"rng_archere": _rng("archere", 45.0)
		"fighter_hp": fighter_hp_bonus += 40.0
		"peon": peon_yield_bonus += 0.4
		"king":
			king_hp_bonus += 22
			GameState.heal_king(22)
		"cost_tower": _cost("tower", 0.88)
		"cd_all":
			for t in ["canon", "gatling", "mortier", "givre"]:
				_cd(t, 0.88)
		"freeze": freeze = true
		"slow_vuln": slow_vuln += 0.25
		"rng_all":
			for t in ["canon", "gatling", "mortier", "givre"]:
				_rng(t, 22.0)
		"fighter_regen": fighter_regen += 6.0
		"interest": interest += 0.05
		"refund": sell_refund = maxf(sell_refund, 0.95)
	relics.append(id)
	changed.emit()


func relic_label(id: String) -> String:
	if id.begins_with("spec:"):
		var s := id.substr(5)
		return Specs.SPECS[s]["label"] if Specs.SPECS.has(s) else s
	return BOONS[id]["label"] if BOONS.has(id) else id


func relic_desc(id: String) -> String:
	if id.begins_with("spec:"):
		var s := id.substr(5)
		return Specs.SPECS[s]["desc"] if Specs.SPECS.has(s) else ""
	return BOONS[id]["desc"] if BOONS.has(id) else ""


func relic_color(id: String) -> Color:
	if id.begins_with("spec:"):
		var s := id.substr(5)
		return Specs.SPECS[s]["color"] if Specs.SPECS.has(s) else Color.WHITE
	return Palette.KING
