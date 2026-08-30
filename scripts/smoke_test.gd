extends "res://scripts/main.gd"
## Banc d'essai d'equilibrage : un "bon" joueur (labyrinthe mixte + upgrades + heros)
## joue en auto, on logue roi/minerai/vague. S'arrete a la vague STOP_WAVE.

const STOP_WAVE := 40
var _prev_king := 0
var _peak_min := 0


func _ready() -> void:
	Meta.reset(); Meta.specs = ["artillerie", "garnison", "cryomancie"]
	super._ready()
	_cycle_speed(); _cycle_speed()   # x5 : au-dela la simulation devient imprecise
	_prev_king = GameState.king_hp
	_build()
	_loop()


func _build() -> void:
	var plan := {"mortier": [[5, 2], [5, 6]], "gatling": [[6, 3], [6, 4], [6, 5]],
		"givre": [[8, 4]], "canon": []}
	# bon joueur : tente de remplir l'arene, can_build garde toujours un chemin
	# -> labyrinthe serpentin dense (exposition max des ennemis aux tours).
	for cc in range(Arena.BUILD_COL_MIN, Arena.BUILD_COL_MAX + 1):
		for rr in range(1, 9):
			plan["canon"].append([cc, rr])
	for k in plan:
		for p in plan[k]:
			var cell := Vector2i(p[0], p[1])
			if GameState.minerai > Catalog.cost(k) + 20 and arena.can_build(k, cell) and GameState.spend(Catalog.cost(k)):
				arena.place(k, cell)
	for rr in range(1, 9):
		if GameState.minerai > 80 and arena.can_build("guerriere", Vector2i(11, rr)) and GameState.spend(Catalog.cost("guerriere")):
			arena.place("guerriere", Vector2i(11, rr))
	for rr in [3, 4, 5, 6]:
		if GameState.minerai > 90 and arena.can_build("archere", Vector2i(13, rr)) and GameState.spend(Catalog.cost("archere")):
			arena.place("archere", Vector2i(13, rr))
	for cx in range(Arena.MINE_COL_MIN, Arena.MINE_COL_MAX + 1):
		for cy in range(1, 9):
			if arena.can_build("peon", Vector2i(cx, cy)) and GameState.minerai > 40 and GameState.spend(Catalog.cost("peon")):
				arena.place("peon", Vector2i(cx, cy))
	# upgrade : priorite aux tours qui tirent
	for _pass in 3:
		for t in get_tree().get_nodes_in_group("units"):
			if t is Tower and t.can_upgrade() and GameState.minerai > t.upgrade_cost() + 60 and GameState.spend(t.upgrade_cost()):
				t.do_upgrade()


func _loop() -> void:
	await get_tree().create_timer(0.8).timeout
	_peak_min = maxi(_peak_min, int(GameState.minerai))

	if GameState.finished:
		if not GameState.endless and GameState.king_hp > 0:
			print("[S] *** VICTOIRE v20 roi=%d/%d -> endless ***" % [GameState.king_hp, GameState.king_max])
			GameState.resume_endless()
		else:
			print("[S] === MORT v%d ===  (min crete %d)" % [GameState.wave, _peak_min])
			get_tree().quit(); return

	if GameState.wave >= STOP_WAVE:
		print("[S] === STOP v%d roi=%d/%d  (min crete %d) : un bon build tient sans soucis ===" % [
			GameState.wave, GameState.king_hp, GameState.king_max, _peak_min])
		get_tree().quit(); return

	if GameState.phase == GameState.Phase.BUILD:
		var d := GameState.king_hp - _prev_king
		var nt := 0
		for t in get_tree().get_nodes_in_group("units"):
			if t is Tower: nt += 1
		print("[S] v%d  roi=%d/%d (%+d)  min=%d  tours=%d  endless=%s" % [
			GameState.wave, GameState.king_hp, GameState.king_max, d, int(GameState.minerai), nt, GameState.endless])
		_prev_king = GameState.king_hp
		for c in hud._boon_box.get_children():
			if c is Button: c.pressed.emit(); break
		_build()
		await get_tree().create_timer(0.1).timeout
		waves.start_wave()
	_loop()
