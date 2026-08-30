class_name Catalog
extends RefCounted
## Registre central des elements constructibles (menu, couts, categorie).
## Les stats detaillees vivent dans tower.gd / fighter.gd / enemy.gd.

const BUILD := {
	"peon":      {"cat": "peon",    "label": "Peon",      "cost": 35, "color": Color(0.90, 0.74, 0.32),
		"desc": "Mine du minerai en continu. A poser dans le rail de MINE (gauche)."},
	"fermier":   {"cat": "fermier", "label": "Fermier",   "cost": 35, "color": Color(0.55, 0.82, 0.40),
		"desc": "Produit de la nourriture en continu. A poser dans la FERME (droite)."},
	"canon":     {"cat": "tower",   "label": "Canon",     "cost": 40, "color": Color(0.60, 0.62, 0.68),
		"desc": "Tir simple equilibre. Mur infranchissable."},
	"gatling":   {"cat": "tower",   "label": "Gatling",   "cost": 55, "color": Color(0.92, 0.72, 0.33),
		"desc": "Cadence tres rapide, degats faibles. Excellente contre les nuees."},
	"mortier":   {"cat": "tower",   "label": "Mortier",   "cost": 95, "color": Color(0.82, 0.50, 0.28),
		"desc": "Longue portee, degats de ZONE a l'impact. Anti-groupe."},
	"givre":     {"cat": "tower",   "label": "Givre",     "cost": 60, "color": Color(0.45, 0.80, 0.95),
		"desc": "Nova de gel de ZONE (proximite). Frappe et RALENTIT tout le monde autour, avec recharge."},
	"guerriere": {"cat": "fighter", "label": "Guerriere", "cost": 55, "color": Color(0.33, 0.75, 0.42),
		"desc": "Bloque et encaisse au corps a corps. Le mur du labyrinthe."},
	"archere":   {"cat": "fighter", "label": "Archere",   "cost": 70, "color": Color(0.55, 0.85, 0.45),
		"desc": "Tire a distance, tres fragile. A placer derriere les guerrieres."},

	# --- casernes (mode DUEL) : paiement en NOURRITURE, a poser dans la GARNISON.
	# chaque caserne debloque l'envoi de son type ; en empiler plusieurs monte le niveau.
	"cas_grognard": {"cat": "caserne", "troop": "grognard", "label": "Cas. Grognard", "cost": 40, "color": Color(0.55, 0.75, 0.35),
		"desc": "Caserne : debloque l'envoi de Grognards chez l'adversaire."},
	"cas_rodeur":   {"cat": "caserne", "troop": "rodeur",   "label": "Cas. Rodeur",   "cost": 40, "color": Color(0.72, 0.76, 0.82),
		"desc": "Caserne : debloque l'envoi de Rodeurs (rapides)."},
	"cas_spectre":  {"cat": "caserne", "troop": "spectre",  "label": "Cas. Spectre",  "cost": 70, "color": Color(0.64, 0.46, 0.88),
		"desc": "Caserne : debloque l'envoi de Spectres (percent les murs)."},
	"cas_soigneur": {"cat": "caserne", "troop": "soigneur", "label": "Cas. Soigneur", "cost": 65, "color": Color(0.45, 0.90, 0.50),
		"desc": "Caserne : debloque l'envoi de Soigneurs (soutien)."},
	"cas_colosse":  {"cat": "caserne", "troop": "colosse",  "label": "Cas. Colosse",  "cost": 95, "color": Color(0.72, 0.48, 0.30),
		"desc": "Caserne : debloque l'envoi de Colosses (tanks)."},
	"cas_sorcier":  {"cat": "caserne", "troop": "sorcier",  "label": "Cas. Sorcier",  "cost": 90, "color": Color(0.88, 0.74, 0.36),
		"desc": "Caserne : debloque l'envoi de Sorciers (harcelent les renforts)."},
}

const ORDER := ["peon", "fermier", "canon", "gatling", "mortier", "givre", "guerriere", "archere"]
const CASERNES := ["cas_grognard", "cas_rodeur", "cas_spectre", "cas_soigneur", "cas_colosse", "cas_sorcier"]


static func palette_ids() -> Array:
	return ORDER + CASERNES if GameState.mode == GameState.Mode.DUEL else ORDER


static func troop_of(id: String) -> String:
	return BUILD[id].get("troop", "") if BUILD.has(id) else ""

## Limite de tours : on ne peut pas tapisser toute la grille. TOWER_CAP tours max
## sur le plateau (comme la "supply" de Legion TD) -> un joueur riche ne peut pas
## se faire un mur de DPS invincible, il doit AMELIORER (niv. 4-5) et utiliser des
## heros. Petite majoration de prix des les dernieres places (signal, pas un mur).
const TOWER_CAP := 30
const TOWER_FREE := 18
const TOWER_TAX := 0.03
const TOWER_TAX_MAX := 0.8


static func cat(id: String) -> String:
	return BUILD[id]["cat"] if BUILD.has(id) else ""


static func towers_full() -> bool:
	return GameState.towers_built >= TOWER_CAP


static func tower_surcharge() -> float:
	return minf(TOWER_TAX_MAX, float(maxi(0, GameState.towers_built - TOWER_FREE)) * TOWER_TAX)


static func cost(id: String) -> int:
	if not BUILD.has(id):
		return 0
	var c := float(BUILD[id]["cost"]) * Meta.cost(BUILD[id]["cat"])
	if BUILD[id]["cat"] == "tower":
		c *= 1.0 + tower_surcharge()
	return int(round(c))


static func base_cost(id: String) -> int:
	return BUILD[id]["cost"] if BUILD.has(id) else 0


static func label(id: String) -> String:
	return BUILD[id]["label"] if BUILD.has(id) else id


static func color(id: String) -> Color:
	return BUILD[id]["color"] if BUILD.has(id) else Color.WHITE


static func desc(id: String) -> String:
	return BUILD[id]["desc"] if BUILD.has(id) else ""
