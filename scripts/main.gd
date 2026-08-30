extends Node2D
## Point d'entree. Fond (shaders) + monde (arene + effets) + vagues + HUD + bulle tour.

const VIEW_W := 1280.0
const VIEW_H := 1000.0
const AVATAR_H := 0.0             ## bandeau avatars : replie dans le panneau ROI (DUEL a part)
const TOP_H := 104.0              ## barre haute HUD (ROI + ressources + vague + controles)
const LEFT_COL_W := 232.0         ## colonne gauche : cartes de construction
const RIGHT_PANEL_W := 236.0      ## colonne droite
const SPEEDS := [1.0, 2.0, 5.0]
var _speed_i := 0

var world: Node2D
var farm_world: Node2D
var _board_zoom := 1.0
var arena: Arena
var farm: FarmView
var _view := "battle"         ## "battle" | "farm"
var waves: WaveManager
var hud: CanvasLayer
var popup: TowerPopup
var _pending := ""            ## id du catalogue, ou ""
var _selected: Node = null    ## Tour, Fighter ou Caserne

# --- multijoueur (course aux rois) ---
var _ghost_layer: CanvasLayer
var _ghost_board: GhostBoard
var _spectate_bar: Label
var _spectating := ""


func _ready() -> void:
	GameState.reset()
	Meta.reset()
	Meta.apply_specs()
	Versus.reset()
	RenderingServer.set_default_clear_color(Palette.BG)

	_build_background()

	world = Node2D.new()
	world.name = "World"
	add_child(world)

	arena = preload("res://scenes/arena.tscn").instantiate()
	arena.name = "Arena"
	world.add_child(arena)

	# La carte est le heros : encadree par la barre haute, la colonne gauche
	# (construction) et la colonne droite (infos).  Centree dans l'espace restant.
	var bs := arena.board_size()
	var map_x := LEFT_COL_W
	var map_w := VIEW_W - LEFT_COL_W - RIGHT_PANEL_W
	var map_h := VIEW_H - TOP_H - 12.0
	_board_zoom = minf(map_h / bs.y, map_w / bs.x)
	world.scale = Vector2(_board_zoom, _board_zoom)
	world.position = Vector2(
		roundi(map_x + (map_w - bs.x * _board_zoom) * 0.5),
		roundi(TOP_H + (map_h - bs.y * _board_zoom) * 0.5))

	var effects := Node2D.new()
	effects.name = "Effects"
	effects.z_index = 20
	world.add_child(effects)
	Fx.setup(effects, world, world.position)

	# --- vue FERME : monde parallele, cadre pour sa propre grille ---
	farm_world = Node2D.new()
	farm_world.name = "FarmWorld"
	add_child(farm_world)
	farm = preload("res://scenes/farm_view.tscn").instantiate()
	farm.name = "Farm"
	farm_world.add_child(farm)
	var fbs: Vector2 = farm.board_size()
	# marge haute : les plaques d'enseigne des zones montent au-dessus des murs.
	var farm_h := map_h - 34.0
	var fzoom: float = minf(farm_h / fbs.y, map_w / fbs.x)
	farm_world.scale = Vector2(fzoom, fzoom)
	farm_world.position = Vector2(
		roundi(map_x + (map_w - fbs.x * fzoom) * 0.5),
		roundi(TOP_H + 30.0 + (farm_h - fbs.y * fzoom) * 0.5))
	farm_world.visible = false

	_build_dust()
	# le post-process (BackBufferCopy + shader plein cadre chaque frame) coute cher
	# en WebGL2 -> desactive sur l'export web (le grain/vignette de l'arene suffisent).
	if not OS.has_feature("web"):
		_build_postfx()

	waves = WaveManager.new()
	waves.name = "Waves"
	waves.arena = arena
	add_child(waves)
	if Versus.active():
		Versus.ai_take_turn(1)

	hud = preload("res://scripts/hud.gd").new()
	hud.avatar_h = AVATAR_H
	hud.right_panel_w = RIGHT_PANEL_W
	add_child(hud)
	Engine.time_scale = 1.0
	hud.set_speed(1.0)
	hud.build_pressed.connect(_set_pending)
	hud.start_wave_pressed.connect(func():
		if MatchDirector.active():
			MatchDirector.set_local_ready(true)
		else:
			waves.start_wave())
	hud.speed_pressed.connect(_cycle_speed)
	hud.view_pressed.connect(_set_view)
	hud.demolish_pressed.connect(func():
		if is_instance_valid(_selected):
			_on_sell())
	hud.restart_pressed.connect(func():
		Engine.time_scale = 1.0
		get_tree().reload_current_scene())
	hud.boon_pressed.connect(func(_id: String):
		if is_instance_valid(_selected):
			popup.open(_selected))

	popup = TowerPopup.new()
	popup.upgrade_pressed.connect(_on_upgrade)
	popup.sell_pressed.connect(_on_sell)
	popup.priority_pressed.connect(_on_priority)
	hud.add_child(popup)

	if MatchDirector.active():
		_setup_match()

	GameState.game_over.connect(func(win: bool):
		Engine.time_scale = 1.0
		_speed_i = 0
		hud.set_speed(1.0)
		Audio.play("victory" if win else "game_over")
		Fx.shake(14.0))


## --- COURSE AUX ROIS : rattache le MatchDirector, cree le calque de spectate ---
func _setup_match() -> void:
	MatchDirector.attach(arena, GameState, waves)

	_ghost_layer = CanvasLayer.new()
	_ghost_layer.layer = 11
	_ghost_layer.visible = false
	add_child(_ghost_layer)
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.035, 0.032, 0.045, 1.0)
	backdrop.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_close_spectate())
	_ghost_layer.add_child(backdrop)
	var gb_holder := Node2D.new()
	gb_holder.z_index = 5
	_ghost_layer.add_child(gb_holder)
	_ghost_board = GhostBoard.new()
	gb_holder.add_child(_ghost_board)
	var gbs: Vector2 = _ghost_board.board_size()
	var gz: float = minf((VIEW_H - 120.0) / gbs.y, (VIEW_W - 80.0) / gbs.x)
	gb_holder.scale = Vector2(gz, gz)
	gb_holder.position = Vector2(roundi((VIEW_W - gbs.x * gz) * 0.5), roundi(70.0 + (VIEW_H - 70.0 - gbs.y * gz) * 0.5))
	_spectate_bar = Label.new()
	_spectate_bar.add_theme_font_size_override("font_size", 18)
	_spectate_bar.add_theme_color_override("font_color", Palette.TEXT_TITLE)
	_spectate_bar.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_spectate_bar.add_theme_constant_override("outline_size", 4)
	_spectate_bar.position = Vector2(24, 22)
	_spectate_bar.z_index = 20
	_ghost_layer.add_child(_spectate_bar)

	MatchDirector.player_digest.connect(func(id: String, d: Dictionary):
		if id == _spectating and is_instance_valid(_ghost_board):
			_ghost_board.apply_digest(d))
	MatchDirector.match_over.connect(func(winner: String):
		_close_spectate()
		if winner == MatchDirector.local_id():
			GameState.win()
		elif not GameState.finished:
			GameState.finished = true
			GameState.game_over.emit(false))
	if hud.has_signal("spectate_pressed"):
		hud.spectate_pressed.connect(_toggle_spectate)


func _toggle_spectate(id: String) -> void:
	if _spectating == id or id == "":
		_close_spectate()
		return
	_spectating = id
	_ghost_layer.visible = true
	var ps = MatchDirector.players.get(id, null)
	_spectate_bar.text = "SPECTATE  —  %s     (clic / Échap pour revenir)" % (ps.name if ps else id)
	if ps != null and not ps.digest.is_empty():
		_ghost_board.apply_digest(ps.digest)


func _close_spectate() -> void:
	_spectating = ""
	if is_instance_valid(_ghost_layer):
		_ghost_layer.visible = false


func _cycle_speed() -> void:
	_speed_i = (_speed_i + 1) % SPEEDS.size()
	Engine.time_scale = SPEEDS[_speed_i]
	hud.set_speed(SPEEDS[_speed_i])
	Audio.play("place_fighter")


## bascule BATAILLE <-> FERME.
func _set_view(v: String) -> void:
	if v == _view:
		return
	_view = v
	_set_pending("")
	_deselect()
	world.visible = _view == "battle"
	farm_world.visible = _view == "farm"
	hud.set_view(_view)
	Audio.play("place_fighter")


## grille active (celle qui recoit les clics / le survol).
func _grid() -> Node2D:
	if _view == "farm":
		return farm
	return arena


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _build_background() -> void:
	var cl := CanvasLayer.new()
	cl.layer = -100
	add_child(cl)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/background.gdshader")
	mat.set_shader_parameter("farm_edge", 1.0)
	mat.set_shader_parameter("top_edge", TOP_H / VIEW_H)
	rect.material = mat
	cl.add_child(rect)


func _build_postfx() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 5
	add_child(cl)
	var bb := BackBufferCopy.new()
	bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	cl.add_child(bb)
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/postfx.gdshader")
	rect.material = mat
	cl.add_child(rect)
	# ancre plein-cadre APRES l'ajout a l'arbre (Godot 4.7 : set_size hors-arbre -> erreur)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_dust() -> void:
	var dust := CPUParticles2D.new()
	dust.amount = 32
	dust.lifetime = 7.0
	dust.preprocess = 4.0
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = arena.board_size() * 0.5
	dust.position = arena.board_size() * 0.5
	dust.direction = Vector2(1, -0.35)
	dust.spread = 45.0
	dust.gravity = Vector2.ZERO
	dust.initial_velocity_min = 3.0
	dust.initial_velocity_max = 11.0
	dust.scale_amount_min = 1.0
	dust.scale_amount_max = 2.4
	dust.color = Color(1, 1, 1, 0.05)
	dust.z_index = 3
	world.add_child(dust)


func _set_pending(id: String) -> void:
	_pending = id
	arena.pending_tool = id
	if farm != null:
		farm.pending_tool = id
	hud.set_selection(id)
	if id != "":
		_deselect()


func _deselect() -> void:
	if is_instance_valid(_selected):
		_selected.selected = false
	_selected = null
	popup.close()


func _select(u: Node) -> void:
	_deselect()
	_selected = u
	u.selected = true
	popup.open(u)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _spectating != "":
			_close_spectate()
			return
		if event.keycode == KEY_M:
			Audio.toggle_music()
		elif event.keycode == KEY_SPACE and GameState.phase == GameState.Phase.BUILD:
			if MatchDirector.active():
				MatchDirector.set_local_ready(true)
			else:
				waves.start_wave()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var idx: int = event.keycode - KEY_1
			if idx < Catalog.ORDER.size():
				_set_pending(Catalog.ORDER[idx])
		elif event.keycode == KEY_ESCAPE:
			_set_pending("")
			_deselect()
		elif event.keycode == KEY_TAB:
			_cycle_speed()
		return
	if event is InputEventMouseMotion:
		var g := _grid()
		g.hover_cell = g.world_to_cell(g.get_local_mouse_position())
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _pending != "":
				_try_place()
			else:
				_try_select()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_set_pending("")
			_deselect()


func _try_select() -> void:
	var g := _grid()
	var cell: Vector2i = g.world_to_cell(g.get_local_mouse_position())
	var node = g.occupied.get(cell)
	if node is Tower or node is Fighter or node is Caserne:
		_select(node)
	else:
		_deselect()


func _try_place() -> void:
	if _pending == "":
		return
	var g := _grid()
	var cell: Vector2i = g.world_to_cell(g.get_local_mouse_position())

	var cat := Catalog.cat(_pending)
	if cat != "peon" and cat != "fermier" and GameState.phase != GameState.Phase.BUILD:
		Audio.play("denied")
		hud.flash("Construction impossible pendant le combat.")
		return

	if not g.can_build(_pending, cell):
		Audio.play("denied")
		hud.flash(_reason(cell))
		return

	var paid := GameState.spend_nourriture(Catalog.cost(_pending)) if cat == "caserne" \
		else GameState.spend(Catalog.cost(_pending))
	if not paid:
		Audio.play("denied")
		hud.flash_denied()
		return

	Audio.play("place_tower" if Catalog.cat(_pending) == "tower" else "place_fighter")
	var n: Node2D = g.place(_pending, cell)
	if n != null and _view == "battle":
		Fx.ring(n.position, Catalog.color(_pending), 6.0, 28.0, 0.28)


func _on_upgrade() -> void:
	if not (_selected is Tower) or not _selected.can_upgrade():
		return
	if GameState.phase != GameState.Phase.BUILD or GameState.finished:
		return
	var c: int = _selected.upgrade_cost()
	if not GameState.spend(c):
		Audio.play("denied")
		hud.flash_denied()
		return
	_selected.do_upgrade()
	Audio.play("upgrade")
	Fx.ring(_selected.position, _selected.body_color.lightened(0.3), 8.0, 46.0, 0.4)
	Fx.burst(_selected.position, _selected.body_color.lightened(0.3), 10, 90.0)
	popup.open(_selected)


func _on_sell() -> void:
	if not is_instance_valid(_selected):
		return
	if GameState.phase != GameState.Phase.BUILD or GameState.finished:
		return
	var v: int = _selected.sell_value()
	var p: Vector2 = _selected.position
	var col: Color = _selected._tint if _selected is Caserne else _selected.body_color
	if _selected is Caserne:
		GameState.add_nourriture(v)
	else:
		GameState.add_minerai(v)
	Audio.play("sell")
	Fx.text(p, "+%d" % v, Palette.GOLD_TEXT)
	Fx.shards(p, col, 9)
	Fx.ring(p, col, 6.0, 34.0, 0.35)
	_selected.queue_free()
	_deselect()


func _on_priority() -> void:
	if not (_selected is Tower):
		return
	_selected.cycle_priority()
	Audio.play("shoot")
	popup.open(_selected)


func _reason(cell: Vector2i) -> String:
	var cat := Catalog.cat(_pending)
	if cat == "peon":
		if get_tree().get_nodes_in_group("peons").size() >= Meta.peon_max:
			return "Maximum %d peons atteint." % Meta.peon_max
		return "Les peons se placent dans la zone MINE (onglet FERME)."
	if cat == "fermier":
		if get_tree().get_nodes_in_group("fermiers").size() >= Meta.peon_max:
			return "Maximum %d fermiers atteint." % Meta.peon_max
		return "Les fermiers se placent dans la zone FERME (onglet FERME)."
	if cat == "caserne":
		return "Les casernes se placent dans la zone GARNISON (onglet FERME)."
	if _view == "farm":
		return "Sur cet onglet on ne place que peons / fermiers / casernes."
	if cat == "tower" and Catalog.towers_full():
		return "Limite de %d tours atteinte : ameliore ou revends." % Catalog.TOWER_CAP
	if cat == "tower" and arena.in_battle_build(cell) and not arena.occupied.has(cell):
		return "Ca bloquerait completement le passage des ennemis !"
	if cat == "tower" or cat == "fighter":
		return "Construction seulement dans l'arene de bataille (centre)."
	return "Placement invalide ici."
