class_name WaveManager
extends Node
## Compose et fait apparaitre les vagues, tient le recap, rend la main quand tout
## est mort. Modificateurs de vague (BTD-style) + Champion toutes les 5 vagues.

const WAVES := [
	{"g": [{"t": "grognard", "n": 6, "gap": 0.6}], "m": []},
	{"g": [{"t": "grognard", "n": 10, "gap": 0.5}], "m": []},
	{"g": [{"t": "grognard", "n": 6, "gap": 0.55}, {"t": "rodeur", "n": 6, "gap": 0.28}], "m": []},
	{"g": [{"t": "grognard", "n": 9, "gap": 0.5}], "m": ["blinde"]},
	{"g": [{"t": "rodeur", "n": 18, "gap": 0.26}], "m": ["rapide"]},
	{"g": [{"t": "grognard", "n": 7, "gap": 0.45}, {"t": "soigneur", "n": 2, "gap": 1.0}, {"t": "colosse", "n": 1, "gap": 1.2}], "m": ["regen"]},
	{"g": [{"t": "grognard", "n": 8, "gap": 0.4}, {"t": "spectre", "n": 5, "gap": 0.4}], "m": []},
	{"g": [{"t": "colosse", "n": 4, "gap": 1.0}, {"t": "rodeur", "n": 12, "gap": 0.22}], "m": ["blinde"]},
	{"g": [{"t": "grognard", "n": 9, "gap": 0.35}, {"t": "sorcier", "n": 3, "gap": 1.1}, {"t": "colosse", "n": 2, "gap": 1.0}], "m": ["rapide"]},
	{"g": [{"t": "grognard", "n": 10, "gap": 0.35}, {"t": "rodeur", "n": 12, "gap": 0.2}, {"t": "colosse", "n": 4, "gap": 0.9}], "m": []},
	{"g": [{"t": "rodeur", "n": 16, "gap": 0.18}, {"t": "spectre", "n": 8, "gap": 0.3}], "m": ["rapide"]},
	{"g": [{"t": "grognard", "n": 12, "gap": 0.3}, {"t": "soigneur", "n": 3, "gap": 0.7}, {"t": "sorcier", "n": 3, "gap": 0.9}, {"t": "colosse", "n": 4, "gap": 0.8}], "m": ["blinde", "regen"]},
	{"g": [{"t": "grognard", "n": 14, "gap": 0.28}, {"t": "spectre", "n": 10, "gap": 0.22}], "m": []},
	{"g": [{"t": "colosse", "n": 7, "gap": 0.7}, {"t": "grognard", "n": 14, "gap": 0.26}], "m": ["blinde"]},
]

var arena: Arena
var _alive := 0
var _spawning := false
var _path: PackedVector2Array
var stat := {}


static func wave_data(w: int) -> Dictionary:
	if w >= 1 and w <= WAVES.size():
		return WAVES[w - 1]
	var over := w - WAVES.size()          # 1, 2, 3...  (vagues 15, 16, 17...)
	# past = vagues APRES la victoire (w > WIN_WAVE) : la ou la montee devient raide.
	var past := maxi(0, w - GameState.WIN_WAVE)
	var mset := [
		["blinde", "regen"], ["rapide", "spectre"], ["blinde", "rapide"],
		["regen", "spectre"], ["blinde", "regen", "rapide"], ["spectre", "regen"],
	]
	var hard_mset := [
		["blinde", "regen", "rapide"], ["spectre", "regen", "rapide"],
		["blinde", "rapide", "spectre"], ["blinde", "regen", "spectre"],
	]
	# jusqu'a la vague 20 : montee douce (comme avant). Au-dela (mode sans fin) :
	# la masse ET la vitesse grimpent vite -> meme un labyrinthe plein (30 tours max)
	# de niveau 5 finit deborde. Pas de plafond : c'est le challenge infini.
	var pg := float(past)
	return {
		"g": [
			{"t": "grognard", "n": 11 + over * 2 + int(pg * pg * 0.35 + pg * 4.0), "gap": maxf(0.07, 0.26 - over * 0.010 - pg * 0.005)},
			{"t": "rodeur", "n": 9 + over * 2 + int(pg * pg * 0.32 + pg * 3.6), "gap": maxf(0.06, 0.16 - over * 0.005 - pg * 0.004)},
			{"t": "spectre", "n": 3 + int(over * 0.9) + int(pg * 1.5), "gap": maxf(0.14, 0.35 - pg * 0.02)},
			{"t": "colosse", "n": 3 + int(over * 0.7) + int(pg * pg * 0.12 + pg * 1.6), "gap": maxf(0.30, 0.8 - pg * 0.04)},
			{"t": "sorcier", "n": 1 + int(over / 3.0) + int(pg / 2.5), "gap": 0.8},
			{"t": "soigneur", "n": 2 + int(over / 3.0) + int(pg / 1.5), "gap": 0.5},
		],
		"m": hard_mset[(past - 1) % hard_mset.size()] if past >= 1 else mset[(over - 1) % mset.size()],
	}


static func has_champion(w: int) -> bool:
	return w % 5 == 0


static func wave_summary(w: int) -> String:
	var d := wave_data(w)
	var parts := PackedStringArray()
	for g in d["g"]:
		parts.append("%dx %s" % [int(g["n"]), Enemy.TYPES.get(g["t"], {"label": g["t"]})["label"]])
	if has_champion(w):
		parts.append("1x CHAMPION")
	var s := "   ".join(parts)
	if not d["m"].is_empty():
		var ml := PackedStringArray()
		for x in d["m"]:
			ml.append(Enemy.MOD_LABEL.get(x, x))
		s += "     [ %s ]" % " + ".join(ml)
	return s


func start_wave(_wave_seed := 0) -> void:
	if GameState.phase != GameState.Phase.BUILD or GameState.finished:
		return
	GameState.next_wave()
	GameState.set_phase(GameState.Phase.COMBAT)
	Audio.play("wave_start")
	_path = arena.enemy_path()
	Enemy.heal_tally = 0.0
	stat = {"kills": 0, "leaks": 0, "hp_lost": 0, "gold": 0, "leak_types": {}, "mods": [], "deepest": 0.0}
	_spawning = true

	var w := GameState.wave
	var d := wave_data(w)
	stat["mods"] = Array(d["m"])
	var mods := PackedStringArray(d["m"])

	# --- envois recus ce round ---
	var ai_sends: Array = []
	if MatchDirector.active():
		ai_sends = MatchDirector.drain_incoming()
	elif Versus.active():
		Versus.resolve_your_attack()
		ai_sends = Versus.drain_ai_queue()

	for g in d["g"]:
		for i in int(g["n"]):
			if not is_inside_tree() or GameState.finished:
				_spawning = false
				return
			_spawn_one(g["t"], w, mods, false)
			await get_tree().create_timer(float(g["gap"])).timeout

	# DUEL : les monstres envoyes par l'IA arrivent apres la salve neutre
	for tid in ai_sends:
		if not is_inside_tree() or GameState.finished:
			break
		_spawn_one(tid, w, PackedStringArray(), false, true)
		await get_tree().create_timer(0.35).timeout

	if has_champion(w):
		await get_tree().create_timer(0.8).timeout
		if is_inside_tree() and not GameState.finished:
			_spawn_one("colosse", w, PackedStringArray(), true)

	_spawning = false
	_check_end()


func _spawn_one(type_id: String, wave: int, mods: PackedStringArray, champ: bool, from_send := false) -> void:
	var e := Enemy.new()
	e.configure(type_id, wave, PackedStringArray(["champion"]) if champ else mods)
	e.from_send = from_send
	e.position = arena.cell_to_world(arena.spawn_cell) + Vector2(0, randf_range(-16.0, 40.0))
	e.set_path(_path)
	e.gone.connect(_on_enemy_gone.bind(e))
	arena.add_child(e)
	var col: Color = Color(1.0, 0.5, 0.4) if from_send else Palette.SPAWN
	Fx.burst(e.position, col, 8 if champ else 5, 80.0 if champ else 60.0)
	if champ:
		Audio.play("champion")
		Fx.shake(8.0)
	_alive += 1


func _on_enemy_gone(leaked: bool, e: Enemy) -> void:
	_alive -= 1
	stat["deepest"] = maxf(stat["deepest"], 1.0 if leaked else e.path_fraction())
	if leaked:
		stat["leaks"] += 1
		stat["hp_lost"] += e.leak_damage
		var lt: Dictionary = stat["leak_types"]
		var key := "CHAMPION" if e.is_champion else e.type_id
		lt[key] = int(lt.get(key, 0)) + 1
	else:
		stat["kills"] += 1
		stat["gold"] += e.bounty
		if e.from_send:
			# recompense du defenseur : tuer un envoi adverse rapporte de la nourriture
			GameState.add_nourriture(2)
	if not _spawning:
		_check_end()


func _check_end() -> void:
	if GameState.phase != GameState.Phase.COMBAT or GameState.finished:
		return
	if _alive <= 0:
		var base_income := GameState.BASE_INCOME + GameState.wave * 2
		var interest := mini(int(GameState.minerai * Meta.interest), 120)
		stat["income"] = base_income
		stat["interest"] = interest
		stat["healed"] = Enemy.heal_tally
		GameState.set_phase(GameState.Phase.BUILD)
		GameState.add_minerai(base_income + interest)
		GameState.wave_recap = stat.duplicate(true)
		if MatchDirector.active():
			MatchDirector.on_local_wave_done()
		elif Versus.active():
			Versus.ai_take_turn(GameState.wave + 1)
		GameState.wave_cleared.emit(GameState.wave)
		Audio.play("wave_clear")
		if GameState.wave >= GameState.WIN_WAVE and not GameState.endless and GameState.mode == GameState.Mode.SOLO:
			GameState.win()
