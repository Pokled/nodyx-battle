extends Node
## Jetable : capture le jeu dans un etat donne par MODE, pour la QA visuelle.
##   build   : phase construction, labyrinthe partiel
##   combat  : vague lancee, ennemis a l'ecran
##   recap   : ecran de renfort de fin de vague
##   empty   : plateau nu (aucune tour)

const MODE := "build"

func _ready() -> void:
	if MODE == "duel" or MODE == "versus":
		GameState.mode = GameState.Mode.DUEL
	if MODE == "versus":
		Net.configure("local")
		Net.open({"bots": 1, "difficulty": 1.0})
		Net.start_match({"seed": 4242})
		await get_tree().process_frame
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var arena = main.get_node("World/Arena")
	GameState.minerai = 99999
	GameState.nourriture = 9999
	if MODE == "duel" or MODE == "versus":
		var farm = main.get_node("FarmWorld/Farm")
		for cell: Vector2i in [Vector2i(3, 9), Vector2i(4, 9), Vector2i(5, 10)]:
			if farm.can_build("cas_grognard", cell):
				farm.place("cas_grognard", cell)
		if farm.can_build("cas_rodeur", Vector2i(6, 9)):
			farm.place("cas_rodeur", Vector2i(6, 9))
		for cell: Vector2i in [Vector2i(5, 2), Vector2i(5, 3), Vector2i(7, 6), Vector2i(9, 5)]:
			if arena.can_build("canon", cell):
				arena.place("canon", cell)
		main._set_view("battle")
		if MODE == "versus":
			MatchDirector.set_local_ready(true)
			for _k in 260:
				await get_tree().process_frame
			main._toggle_spectate("bot1")
			for _k in 90:
				await get_tree().process_frame
		else:
			main.get_node("Waves").start_wave()
			for _k in 90:
				await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://_shot.png")
		get_tree().quit()
		return
	var plan := {
		"canon": [Vector2i(5, 2), Vector2i(5, 3), Vector2i(9, 5), Vector2i(9, 6), Vector2i(13, 2), Vector2i(13, 3)],
		"gatling": [Vector2i(7, 6), Vector2i(7, 7), Vector2i(11, 2), Vector2i(11, 3)],
		"givre": [Vector2i(6, 4), Vector2i(12, 6)],
		"mortier": [Vector2i(10, 7)],
	}
	if MODE != "empty":
		for id: String in plan:
			for cell: Vector2i in plan[id]:
				if arena.can_build(id, cell):
					arena.place(id, cell)
	if MODE == "farm":
		main._set_view("farm")
	if MODE == "combat":
		main.get_node("Waves").start_wave()
	if MODE == "recap":
		GameState.wave_recap = {"kills": 24, "gold": 40, "income": 60, "leaks": 0, "deepest": 0.62, "healed": 0.0, "leak_types": {}}
		GameState.wave = 3
		GameState.wave_cleared.emit(3)
	var frames := 95 if MODE == "combat" else 80
	for _i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://_shot.png")
	get_tree().quit()
