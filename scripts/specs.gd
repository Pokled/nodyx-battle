class_name Specs
extends RefCounted
## Les 5 specialites. Le joueur en choisit 3 au depart (ecran setup).

const SPECS := {
	"artillerie": {
		"label": "Artillerie", "color": Color(0.85, 0.40, 0.35),
		"desc": "Canon & Mortier : +18% degats, -10% cout tours. Mortier +16 rayon.",
	},
	"mecanique": {
		"label": "Mecanique", "color": Color(0.95, 0.68, 0.30),
		"desc": "Gatling & Givre : -18% cooldown. Toutes tours : -8% cout.",
	},
	"negoce": {
		"label": "Negoce", "color": Color(0.90, 0.74, 0.32),
		"desc": "Peons : +0.5/s, max 22. Revente 90%. Interets +8%. +60 minerai.",
	},
	"garnison": {
		"label": "Garnison", "color": Color(0.33, 0.75, 0.42),
		"desc": "Unites : +45 PV, +12% degats, -15% cout. Regeneration 5 PV/s.",
	},
	"cryomancie": {
		"label": "Cryomancie", "color": Color(0.45, 0.80, 0.95),
		"desc": "Le Givre GELE. Ennemis ralentis : +25% degats subis. Mortier +12 rayon.",
	},
}

const ORDER := ["artillerie", "mecanique", "negoce", "garnison", "cryomancie"]


static func apply(id: String) -> void:
	match id:
		"artillerie":
			Meta._mul("canon", 0.18)
			Meta._mul("mortier", 0.18)
			Meta._cost("tower", 0.90)
			Meta.splash_bonus += 16.0
		"mecanique":
			Meta._cd("gatling", 0.82)
			Meta._cd("givre", 0.82)
			Meta._cost("tower", 0.92)
		"negoce":
			Meta.peon_yield_bonus += 0.5
			Meta.peon_max = 22
			Meta.sell_refund = maxf(Meta.sell_refund, 0.90)
			Meta.interest += 0.08
			GameState.add_minerai(60)
		"garnison":
			Meta.fighter_hp_bonus += 45.0
			Meta._mul("guerriere", 0.12)
			Meta._mul("archere", 0.12)
			Meta._cost("fighter", 0.85)
			Meta.fighter_regen += 5.0
		"cryomancie":
			Meta.freeze = true
			Meta.slow_vuln += 0.25
			Meta.frost_bonus += 0.10
			Meta.splash_bonus += 12.0
