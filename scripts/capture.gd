extends "res://scripts/main.gd"
## Capture les images de la vitrine dans widget/nodyx-battle/media/.
## Hors jeu — jamais dans l'export.
##
##   xvfb-run -a godot --rendering-driver opengl3 --audio-driver Dummy \
##            --path . --script res://scripts/capture.gd

const OUT := "res://widget/nodyx-battle/media/"


func _ready() -> void:
	GameState.mode = GameState.Mode.SOLO
	Meta.reset()
	Meta.specs = ["artillerie", "garnison", "cryomancie"]
	super._ready()
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await get_tree().create_timer(0.6).timeout
	GameState.minerai = 6000
	GameState.minerai_changed.emit(GameState.minerai)
	_build_towers()
	await get_tree().create_timer(1.0).timeout
	await _shot("shot1")                       # phase construction : arene meublee + HUD

	# vague tardive = beaucoup d'ennemis dans le labyrinthe pour l'image de couv
	GameState.wave = 8
	waves.start_wave()
	await get_tree().create_timer(3.2).timeout
	await _shot("cover")                       # combat : ennemis engages, tours qui tirent

	var tries := 0
	while not hud._recap.visible and tries < 500:
		await get_tree().create_timer(0.1).timeout
		tries += 1
	await get_tree().create_timer(0.5).timeout
	await _shot("shot2")                       # renfort du roi : les 3 cartes

	get_tree().quit()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + shot_name + ".png")
	print("[CAP] ", shot_name, "  ", img.get_size())


func _build_towers() -> void:
	# labyrinthe serpentin : une rangee sur deux laisse un passage alterne
	var mix := ["canon", "gatling", "mortier", "canon", "givre", "canon"]
	var i := 0
	for cc in range(Arena.BUILD_COL_MIN, Arena.BUILD_COL_MAX + 1):
		var rows := range(1, 8) if (cc % 2 == 0) else range(2, 9)
		for rr in rows:
			var k: String = mix[i % mix.size()]; i += 1
			var cell := Vector2i(cc, rr)
			if arena.can_build(k, cell) and GameState.spend(Catalog.cost(k)):
				arena.place(k, cell)
	for rr in range(2, 8):
		for k in ["guerriere", "archere"]:
			var cell := Vector2i(11 if k == "guerriere" else 13, rr)
			if arena.can_build(k, cell) and GameState.spend(Catalog.cost(k)):
				arena.place(k, cell)
	for cx in range(Arena.MINE_COL_MIN, Arena.MINE_COL_MAX + 1):
		for cy in range(1, 9):
			if arena.can_build("peon", Vector2i(cx, cy)) and GameState.spend(Catalog.cost("peon")):
				arena.place("peon", Vector2i(cx, cy))
	for _pass in 2:
		for t in get_tree().get_nodes_in_group("units"):
			if t is Tower and t.can_upgrade() and GameState.spend(t.upgrade_cost()):
				t.do_upgrade()
