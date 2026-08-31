extends CanvasLayer
## Bandeau superieur (stats + palette de construction + contexte),
## banniere centrale, recap de fin de vague, ecran de defaite.

signal build_pressed(id: String)
signal start_wave_pressed
signal restart_pressed
signal speed_pressed
signal boon_pressed(id: String)
signal view_pressed(view: String)
signal demolish_pressed

var _speed_btn: Button
var _tab_battle: Button
var _tab_farm: Button
var _view := "battle"
var _col_battle: VBoxContainer     ## cartes de tours (colonne gauche, vue BATAILLE)
var _col_farm: VBoxContainer       ## cartes eco (colonne gauche, vue FERME)
var _demolir_btn: Button
var _king_panel: Control
var _ai_king_panel: Control        ## panneau ROI adverse (DUEL vs IA)
var _versus_rail: HBoxContainer    ## rail de joueurs (course aux rois)
var _chips: Dictionary = {}        ## id -> _PlayerChip (course aux rois)
var _send_target := ""             ## id de la cible d'envoi selectionnee
var _target_row: HBoxContainer
var _match_send := false

signal spectate_pressed(id: String)
var _pill_ore: Control
var _pill_food: Control
var _wave_sec: VBoxContainer       ## section PROCHAINE VAGUE (colonne droite, vue BATAILLE)
var _eco_box: VBoxContainer        ## resume ECONOMIE (colonne droite, vue FERME)
var _eco_lbls: Dictionary = {}

var _minerai_lbl: Label
var _nourriture_lbl: Label
var _nourriture_shown := 0.0
var _wave_lbl: Label
var _king_lbl: Label
var _phase_lbl: Label
var _ctx_lbl: Label
var _wave_preview: HBoxContainer
var _wave_mods_lbl: Label
var _wave_panel: PanelContainer
var _start_btn: Button
var _build_btns := {}          ## id -> Button
var _banner: Label
var _minerai_shown := 0.0

var _recap: PanelContainer
var _recap_lbl: RichTextLabel
var _boon_box: HBoxContainer
var _boon_title: Label
var _recap_tw: Tween

var _champ: Control
var _champ_bar: ProgressBar
var _relic_bar: HBoxContainer
var _stats_box: VBoxContainer
var _stat_lbls: Dictionary = {}

var _over: Control

var avatar_h := 0.0            ## hauteur du bandeau avatars (fixee par main.gd avant add_child)
var right_panel_w := 0.0       ## largeur de la colonne de droite (panneau troupes)
var _p1_card: PanelContainer   ## carte avatar du joueur local (PV du roi en direct)
var _p2_card: PanelContainer   ## carte avatar IA (PV du roi adverse, mode DUEL)
var _troop_list: VBoxContainer
var _troop_hdr: Label


func _ready() -> void:
	layer = 10
	_build_avatars()
	_build_bar()
	_build_troop_panel()
	_build_banner()
	_build_champ()
	_build_recap()
	_build_war_table()
	_build_gameover()
	_minerai_shown = GameState.minerai
	_nourriture_shown = GameState.nourriture
	Meta.changed.connect(_rebuild_relics)

	GameState.wave_changed.connect(func(_v): _refresh())
	GameState.king_hp_changed.connect(_on_king)
	GameState.phase_changed.connect(_on_phase)
	GameState.minerai_changed.connect(func(_v): _update_buttons())
	GameState.nourriture_changed.connect(func(_v): _update_buttons())
	GameState.wave_cleared.connect(_on_wave_cleared)
	GameState.game_over.connect(_on_game_over)
	GameState.champion.connect(_on_champion)

	# --- DUEL vs IA legacy : suivi du roi adverse ---
	if GameState.mode == GameState.Mode.DUEL and not MatchDirector.active():
		Versus.changed.connect(_on_versus_changed)
		Versus.attack_resolved.connect(_on_attack_resolved)
		GameState.nourriture_changed.connect(func(_v):
			if is_instance_valid(_troop_list): _rebuild_troops())
		_on_versus_changed()

	# --- COURSE AUX ROIS : rail de joueurs + envois cibles ---
	if MatchDirector.active():
		MatchDirector.roster_changed.connect(_on_match_roster)
		MatchDirector.player_digest.connect(func(_id, _d): _on_match_roster())
		MatchDirector.incoming_changed.connect(func(): if is_instance_valid(_troop_list): _rebuild_troops())
		MatchDirector.phase_changed.connect(_on_match_phase)
		MatchDirector.resync_pending.connect(func():
			banner("RECONNEXION...", Palette.TEXT_TITLE, 2.0))
		MatchDirector.resumed.connect(func():
			banner("RECONNECTE  ·  tu rejoues a la prochaine manche", Palette.HP_GOOD, 3.5))
		Net.speaking_changed.connect(func(id, on):
			if _chips.has(id) and is_instance_valid(_chips[id]): _chips[id].speaking = on
			if id == Net.local_id() and is_instance_valid(_king_panel): _king_panel.speaking = on)
		PlayerAvatars.changed.connect(func(id):
			if _chips.has(id) and is_instance_valid(_chips[id]): _chips[id].av = PlayerAvatars.tex(id))
		GameState.nourriture_changed.connect(func(_v):
			if is_instance_valid(_troop_list): _rebuild_troops())
		_on_match_roster()

	set_selection("")
	_on_king(GameState.king_hp, GameState.king_max)
	_refresh()


func _process(delta: float) -> void:
	_tick_counter(delta, GameState.minerai, _minerai_lbl, "_minerai_shown")
	_tick_counter(delta, GameState.nourriture, _nourriture_lbl, "_nourriture_shown")
	_tick_stats_box()
	_tick_rates()


## Taux de production live (ouvriers) affiche sur les pastilles.
func _tick_rates() -> void:
	if not is_instance_valid(_pill_ore):
		return
	var np: int = get_tree().get_nodes_in_group("peons").size()
	var nf: int = get_tree().get_nodes_in_group("fermiers").size()
	var yv := Peon.YIELD_PER_SEC + Meta.peon_yield_bonus
	var pr := np * yv * (18.0 / (18.0 + float(maxi(0, np - 3))))
	var fr := nf * yv * (18.0 / (18.0 + float(maxi(0, nf - 3))))
	var win := GameState.phase == GameState.Phase.COMBAT
	_pill_ore.set_rate(("+%.1f/s" % pr) if (np > 0 and win) else ("%d ouvrier%s" % [np, "s" if np > 1 else ""] if np > 0 else ""))
	_pill_food.set_rate(("+%.1f/s" % fr) if (nf > 0 and win) else ("%d ouvrier%s" % [nf, "s" if nf > 1 else ""] if nf > 0 else ""))
	if not _eco_lbls.is_empty():
		var ng: int = get_tree().get_nodes_in_group("casernes").size()
		_eco_lbls["mine"].text = ("+%.1f/s" % pr) if win else "%d péon%s" % [np, "s" if np > 1 else ""]
		_eco_lbls["champ"].text = ("+%.1f/s" % fr) if win else "%d fermier%s" % [nf, "s" if nf > 1 else ""]
		_eco_lbls["garn"].text = "%d caserne%s" % [ng, "s" if ng > 1 else ""]


func _tick_counter(delta: float, target: int, lbl: Label, field: String) -> void:
	if lbl == null:
		return
	var shown: float = get(field)
	var goal := float(target)
	if absf(shown - goal) > 0.5:
		var spd: float = maxf(30.0, absf(goal - shown) * 7.0)
		shown = move_toward(shown, goal, spd * delta)
		lbl.text = "%d" % roundi(shown)
		set(field, shown)
	elif lbl.text != str(target):
		set(field, goal)
		lbl.text = "%d" % target


# --- bandeau avatars des joueurs (placeholders) --------------------------
## Une carte par joueur : pastille + initiale, nom, niveau, barre de PV du roi,
## anneau "parle" (simule pour l'instant). Les vraies donnees Nodyx (photo de
## profil, etat vocal) viendront avec l'integration widget (Phase 2).

func _build_avatars() -> void:
	if avatar_h <= 0.0:
		return
	var strip := PanelContainer.new()
	strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	strip.offset_bottom = avatar_h
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.075, 0.065, 0.94)
	sb.border_color = Color(0.42, 0.32, 0.18, 0.7)
	sb.border_width_bottom = 2
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	strip.add_theme_stylebox_override("panel", sb)
	add_child(strip)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	strip.add_child(row)

	var duel := GameState.mode == GameState.Mode.DUEL
	var players := [
		{"name": "Toi", "color": Color(0.42, 0.68, 1.0), "speaks": true},
		{"name": "IA", "color": Color(1.0, 0.46, 0.42), "speaks": false},
	]
	for i in players.size():
		var pdata: Dictionary = players[i]
		var card := _AvatarCard.new(pdata["name"], pdata["color"], pdata["speaks"], i == 0)
		row.add_child(card)
		if i == 0:
			_p1_card = card
		else:
			_p2_card = card
			card.visible = duel

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	var vs := Label.new()
	vs.text = "DUEL  ·  course au roi" if duel else "CAMPAGNE SOLO  ·  vs vagues"
	vs.add_theme_font_size_override("font_size", 11)
	vs.add_theme_color_override("font_color", Palette.TEXT_DIM)
	vs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(vs)
	# (les connexions DUEL Versus sont dans _ready, ce bandeau est masque pour l'instant)


func _on_attack_resolved(king_dmg: int, _breach: float) -> void:
	if king_dmg > 0:
		banner("ASSAUT : -%d au roi adverse !" % king_dmg, Color(1.0, 0.55, 0.4), 1.0)
		Audio.play("wave_start")
	else:
		banner("Assaut bloque par la defense adverse.", Palette.TEXT_DIM, 0.9)


func _on_versus_changed() -> void:
	if is_instance_valid(_ai_king_panel):
		_ai_king_panel.set_hp(Versus.enemy_king_hp, Versus.enemy_king_max)
		_ai_king_panel.set_def(Versus.enemy_defense)
	if is_instance_valid(_p2_card):
		_p2_card.set_hp(float(Versus.enemy_king_hp) / float(maxi(1, Versus.enemy_king_max)))
		_p2_card.set_sub("roi %d/%d · def %d" % [
			Versus.enemy_king_hp, Versus.enemy_king_max, roundi(Versus.enemy_defense)])
	_rebuild_troops()


# --- COURSE AUX ROIS -------------------------------------------------

func _on_match_roster() -> void:
	if not is_instance_valid(_versus_rail):
		return
	var alive: Array = MatchDirector.living_ids()
	if _send_target == "" or not (_send_target in alive) or _send_target == MatchDirector.local_id():
		_send_target = ""
		for id in alive:
			if id != MatchDirector.local_id():
				_send_target = id
				break

	var wanted := {}
	for ps in MatchDirector.opponents():
		wanted[ps.id] = true
		var chip: _PlayerChip = _chips.get(ps.id, null)
		if not is_instance_valid(chip):
			chip = _PlayerChip.new()
			var pid: String = ps.id
			chip.pressed.connect(func(): spectate_pressed.emit(pid))
			_versus_rail.add_child(chip)
			_chips[ps.id] = chip
		chip.set_data(ps.id, ps.name, ps.color, PlayerAvatars.tex(ps.id),
			ps.king_hp, ps.king_max, ps.alive)
		chip.speaking = Net.speaking.get(ps.id, false)
	# retire les chips des joueurs qui ont quitte
	for id in _chips.keys():
		if not wanted.has(id):
			if is_instance_valid(_chips[id]): _chips[id].queue_free()
			_chips.erase(id)
	_rebuild_troops()


## Carte d'un adversaire dans le rail course aux rois : avatar Nodyx (rond),
## anneau qui pulse quand le micro est actif, pseudo, barre de PV du roi.
class _PlayerChip extends Button:
	var pid := ""
	var pname := ""
	var tint := Color.WHITE
	var av: Texture2D = null
	var hp := 100
	var hp_max := 100
	var alive := true
	var speaking := false : set = _set_speaking
	var _pulse := 0.0

	func _set_speaking(v: bool) -> void:
		if v == speaking: return
		speaking = v
		set_process(v)
		if not v: _pulse = 0.0
		queue_redraw()

	func _ready() -> void:
		custom_minimum_size = Vector2(150, 60)
		focus_mode = Control.FOCUS_NONE
		flat = true
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func set_data(id: String, nm: String, col: Color, tex: Texture2D, k: int, km: int, al: bool) -> void:
		pid = id; pname = nm; tint = col; av = tex; hp = k; hp_max = km; alive = al
		tooltip_text = "Espionner le plateau de %s" % nm
		queue_redraw()

	func _process(delta: float) -> void:
		_pulse += delta
		queue_redraw()

	func _draw() -> void:
		var s := size
		var bcol := tint if alive else Palette.TEXT_MUTE
		draw_rect(Rect2(Vector2.ZERO, s), Palette.PANEL_RAISED)
		draw_rect(Rect2(Vector2.ONE, s - Vector2(2, 2)), bcol, false, 2.0)

		var r := 21.0
		var c := Vector2(8 + r, s.y * 0.5)
		if speaking:
			var p := 0.5 + 0.5 * sin(_pulse * 9.0)
			draw_circle(c, r + 3.0 + p * 3.0, Color(0.42, 0.86, 0.53, 0.25 + 0.4 * p))
		if av != null:
			draw_texture_rect(av, Rect2(c - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false,
				Color(1, 1, 1, 1.0 if alive else 0.45))
		else:
			draw_circle(c, r, tint.darkened(0.35))
			draw_string(ThemeDB.fallback_font, c + Vector2(-6.5, 6.0),
				pname.substr(0, 1).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 1, 1, 0.92))
		draw_arc(c, r, 0.0, TAU, 28, bcol, 2.0, true)
		if not alive:
			draw_string(ThemeDB.fallback_font, c + Vector2(-8, 7), "☠",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.HP_LOW)

		var tx := c.x + r + 8.0
		var tw := s.x - tx - 8.0
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(tx, 22), pname, HORIZONTAL_ALIGNMENT_LEFT, tw, 13,
			Palette.TEXT if alive else Palette.TEXT_MUTE)
		draw_string(f, Vector2(tx, 38), "%s  %d/%d" % [("♛" if alive else "éliminé"), hp, hp_max],
			HORIZONTAL_ALIGNMENT_LEFT, tw, 10, Palette.TEXT_MUTE)
		var frac := clampf(float(hp) / float(maxi(1, hp_max)), 0.0, 1.0)
		draw_rect(Rect2(Vector2(tx, 46), Vector2(tw, 5)), Palette.HP_BG)
		draw_rect(Rect2(Vector2(tx, 46), Vector2(tw * frac, 5)),
			Palette.HP_GOOD if frac > 0.35 else Palette.HP_LOW)


func _on_match_phase(ph: int) -> void:
	if is_instance_valid(_start_btn):
		var build: bool = ph == MatchDirector.Phase.BUILD
		_start_btn.disabled = not build
		_start_btn.text = "PRÊT" if build else "MANCHE EN COURS…"
	_refresh_ctx()


## Carte d'un joueur : pastille + nom + GROSSE barre de PV du roi (couleur qui
## vire au rouge, flash + chiffres a chaque coup encaisse).
class _AvatarCard extends PanelContainer:
	var _disc: Control
	var _hp_bar: Control          ## _HpBar custom-draw
	var _sub: Label
	var _last_frac := 1.0

	func _init(pname: String, col: Color, speaks: bool, is_self: bool) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.095, 0.075, 0.93)
		sb.set_corner_radius_all(2)
		sb.set_border_width_all(1)
		sb.border_width_left = 3
		sb.border_color = Color(0.44, 0.33, 0.18)
		sb.content_margin_left = 8
		sb.content_margin_right = 12
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		add_theme_stylebox_override("panel", sb)

		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(h)

		_disc = _Disc.new(pname.substr(0, 1).to_upper(), col, speaks)
		_disc.custom_minimum_size = Vector2(46, 46)
		h.add_child(_disc)

		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(v)
		var nm := Label.new()
		nm.text = pname if not is_self else pname + "  (roi)"
		nm.add_theme_font_size_override("font_size", 13)
		nm.add_theme_color_override("font_color", Palette.TEXT)
		v.add_child(nm)
		_sub = Label.new()
		_sub.text = "roi 100/100"
		_sub.add_theme_font_size_override("font_size", 10)
		_sub.add_theme_color_override("font_color", Palette.TEXT_DIM)
		v.add_child(_sub)
		_hp_bar = _HpBar.new()
		_hp_bar.custom_minimum_size = Vector2(150, 13)
		v.add_child(_hp_bar)

	func set_hp(frac: float) -> void:
		frac = clampf(frac, 0.0, 1.0)
		if _hp_bar:
			if frac < _last_frac - 0.001:
				_hp_bar.hit()
			_hp_bar.target = frac
		_last_frac = frac

	func set_sub(txt: String) -> void:
		if _sub:
			_sub.text = txt


	class _HpBar extends Control:
		var target := 1.0
		var _shown := 1.0
		var _ghost := 1.0        ## barre "fantome" qui rattrape lentement (degats visibles)
		var _flash := 0.0

		func hit() -> void:
			_flash = 1.0

		func _process(delta: float) -> void:
			_shown = move_toward(_shown, target, delta * 1.5)
			_ghost = move_toward(_ghost, _shown, delta * 0.5)
			_flash = maxf(0.0, _flash - delta * 3.0)
			if absf(_shown - target) > 0.001 or _ghost > _shown + 0.001 or _flash > 0.0:
				queue_redraw()

		func _draw() -> void:
			var w := size.x
			var hgt := size.y
			# channel de pierre creuse
			draw_rect(Rect2(0, 0, w, hgt), Color(0.09, 0.05, 0.05))
			draw_rect(Rect2(0, 0, w, hgt * 0.35), Color(0, 0, 0, 0.3))
			# fantome (perte recente)
			if _ghost > _shown:
				draw_rect(Rect2(w * _shown, 1, w * (_ghost - _shown), hgt - 2), Color(0.72, 0.20, 0.16, 0.8))
			# etendard qui se retire : or -> ambre -> braise
			var fill := Color(0.80, 0.62, 0.28)
			if _shown < 0.3:
				fill = Color(0.80, 0.26, 0.15)
			elif _shown < 0.6:
				fill = Color(0.78, 0.46, 0.20)
			if _flash > 0.0:
				fill = fill.lerp(Color(1, 0.95, 0.85), _flash * 0.8)
			draw_rect(Rect2(0, 0, w * _shown, hgt), fill)
			draw_rect(Rect2(0, 0, w * _shown, hgt * 0.4), Color(1, 1, 1, 0.12))
			draw_line(Vector2(w * 0.5, 1), Vector2(w * 0.5, hgt - 1), Color(0, 0, 0, 0.25), 1.0)
			draw_rect(Rect2(0, 0, w, hgt), Color(0.44, 0.33, 0.18, 0.8), false, 1.0)

	class _Disc extends Control:
		var _letter: String
		var _col: Color
		var _speaks: bool
		var _t := 0.0
		func _init(letter: String, col: Color, speaks: bool) -> void:
			_letter = letter
			_col = col
			_speaks = speaks
			mouse_filter = Control.MOUSE_FILTER_IGNORE
		func _process(delta: float) -> void:
			if _speaks:
				_t += delta
				queue_redraw()
		func _draw() -> void:
			var c := size * 0.5
			var r := minf(c.x, c.y) - 4.0
			if _speaks:
				var pulse := r + 2.0 + sin(_t * 7.0) * 2.5
				draw_arc(c, pulse, 0.0, TAU, 32, Color(0.95, 0.72, 0.32, 0.6), 2.0)
			# medaillon de pierre : fond sombre, anneau bronze, liseré a la couleur du joueur
			draw_circle(c, r, Color(0.14, 0.12, 0.10))
			draw_arc(c, r, 0.0, TAU, 30, Color(0.44, 0.33, 0.18), 2.4)
			draw_arc(c, r - 3.0, 0.0, TAU, 28, Color(_col.r, _col.g, _col.b, 0.55), 1.4)
			var f := ThemeDB.fallback_font
			draw_string(f, c + Vector2(-r * 0.42, r * 0.42), _letter,
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(r * 1.1), Color(0.90, 0.80, 0.55))


# --- panneau des troupes (colonne de droite) ---------------------------
## DUEL : une ligne par type de troupe debloque (caserne posee). Bouton
## "+ envoyer" = ajoute une unite a ta salve (paye en nourriture). La salve
## frappe le roi adverse au debut du prochain combat, contre sa defense.

func _build_troop_panel() -> void:
	if right_panel_w <= 0.0 or GameState.mode != GameState.Mode.DUEL:
		return
	_match_send = MatchDirector.active()
	var pan := PanelContainer.new()
	pan.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	pan.offset_left = -right_panel_w
	pan.offset_top = 104.0
	pan.mouse_filter = Control.MOUSE_FILTER_PASS
	pan.add_theme_stylebox_override("panel", HudKit.sb_panel_edge(SIDE_RIGHT))
	add_child(pan)
	HudKit.add_ornament(pan, false, true)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pan.add_child(col)

	HudKit.add_section(col, "Envoyer l'assaut", "portal")

	_troop_hdr = Label.new()
	_troop_hdr.add_theme_font_size_override("font_size", 10)
	_troop_hdr.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_troop_hdr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_troop_hdr)

	if _match_send:
		var tl := Label.new()
		tl.text = "CIBLE"
		tl.add_theme_font_size_override("font_size", 10)
		tl.add_theme_color_override("font_color", Palette.TEXT_MUTE)
		col.add_child(tl)
		_target_row = HBoxContainer.new()
		_target_row.add_theme_constant_override("separation", 4)
		col.add_child(_target_row)

	col.add_child(HudKit._Rule.new())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	_troop_list = VBoxContainer.new()
	_troop_list.add_theme_constant_override("separation", 4)
	_troop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_troop_list)
	_rebuild_troops()


func _rebuild_troops() -> void:
	if not is_instance_valid(_troop_list):
		return
	for c in _troop_list.get_children():
		c.queue_free()

	if _match_send:
		_rebuild_target_row()

	# resume : ce qu'on te renvoie
	if is_instance_valid(_troop_hdr):
		var t := ""
		if _match_send:
			var inc: Dictionary = MatchDirector.incoming_summary()
			if inc.is_empty():
				t = "Vise un adversaire, choisis tes monstres. Ils arrivent chez lui la prochaine manche."
			else:
				var parts := PackedStringArray()
				for k in inc:
					parts.append("%d %s" % [int(inc[k]), Enemy.TYPES.get(k, {"label": k})["label"]])
				t = "⚠ On t'envoie : " + "  ".join(parts)
		else:
			var q := Versus.queue_total()
			t = "Salve prete : %d unite(s)." % q if q > 0 else "Aucun envoi prepare."
			if Versus.last_king_dmg > 0:
				t += "  Dernier assaut : -%d au roi adverse." % Versus.last_king_dmg
			var inc2 := Versus.ai_incoming_summary()
			if inc2 != "":
				t += "\n⚠ L'IA t'envoie : " + inc2
		_troop_hdr.text = t

	if Versus.unlocked.is_empty():
		var empty := Label.new()
		empty.text = "Construis une caserne dans la\nGARNISON pour debloquer un envoi."
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", Palette.TEXT_DIM)
		_troop_list.add_child(empty)
		return

	for tid in Versus.SENDABLE:
		if not Versus.unlocked.has(tid):
			continue
		_troop_list.add_child(_troop_row(tid))


func _rebuild_target_row() -> void:
	if not is_instance_valid(_target_row):
		return
	for c in _target_row.get_children():
		c.queue_free()
	for ps in MatchDirector.opponents():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.text = ps.name
		b.disabled = not ps.alive
		b.button_pressed = ps.id == _send_target
		b.add_theme_font_size_override("font_size", 10)
		var pid: String = ps.id
		b.pressed.connect(func():
			_send_target = pid
			_rebuild_troops())
		_target_row.add_child(b)


func _troop_row(tid: String) -> Control:
	var lvl := int(Versus.unlocked.get(tid, 1))
	var cost := int(Versus.SEND_COST.get(tid, 0))
	var queued := int(Versus.your_queue.get(tid, 0))
	var col: Color = Enemy.TYPE_COLOR.get(tid, Color.WHITE)

	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", HudKit.sb_well(col, false))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	box.add_child(v)

	var name_lbl := Label.new()
	name_lbl.text = "%s  niv %d%s" % [
		Enemy.TYPES.get(tid, {"label": tid})["label"], lvl,
		("   ·   file: %d" % queued) if queued > 0 else ""]
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", col.lightened(0.25))
	v.add_child(name_lbl)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	v.add_child(row)

	var send := Button.new()
	send.text = "+ ENVOYER  ·  %d ble" % cost
	send.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudKit.btn_primary(send)
	send.add_theme_font_size_override("font_size", 11)
	if _match_send:
		send.disabled = GameState.nourriture < cost or GameState.finished or _send_target == ""
		send.pressed.connect(func():
			if _send_target != "" and GameState.spend_nourriture(cost):
				MatchDirector.send_troops(_send_target, {tid: 1})
				Audio.play("place_fighter")
				_rebuild_troops())
	else:
		send.disabled = GameState.nourriture < cost or GameState.finished
		send.pressed.connect(func():
			if Versus.queue_send(tid):
				Audio.play("place_fighter"))
	row.add_child(send)

	if queued > 0 and not _match_send:
		var undo := Button.new()
		undo.text = "−"
		undo.custom_minimum_size = Vector2(28, 0)
		HudKit.btn_neutral(undo)
		undo.add_theme_font_size_override("font_size", 13)
		undo.pressed.connect(func(): Versus.unqueue_send(tid))
		row.add_child(undo)

	return box


# --- construction ---------------------------------------------------------

func _build_bar() -> void:
	_build_top_bar()
	_build_left_column()
	_refresh_tabs()


## BARRE HAUTE (h 104) : onglets · panneau ROI · pastilles ressources · vague ·
## boutons carres (vitesse / musique) · LANCER.
func _build_top_bar() -> void:
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 104.0
	top.mouse_filter = Control.MOUSE_FILTER_PASS
	top.add_theme_stylebox_override("panel", HudKit.sb_panel_edge(SIDE_TOP))
	add_child(top)
	HudKit.add_ornament(top, false, false)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	top.add_child(row)

	# --- onglets BATAILLE / FERME ---
	var tabs := VBoxContainer.new()
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.add_theme_constant_override("separation", 3)
	tabs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tabs)
	_tab_battle = Button.new()
	_tab_battle.text = "  BATAILLE"
	_tab_battle.custom_minimum_size = Vector2(112, 0)
	_tab_battle.pressed.connect(func(): view_pressed.emit("battle"))
	_tab_farm = Button.new()
	_tab_farm.text = "  FERME"
	_tab_farm.custom_minimum_size = Vector2(112, 0)
	_tab_farm.pressed.connect(func(): view_pressed.emit("farm"))
	tabs.add_child(_tab_battle)
	tabs.add_child(_tab_farm)

	# --- panneau ROI : medaillon + barre de PV ---
	var duel := GameState.mode == GameState.Mode.DUEL
	var match_on := MatchDirector.active()
	_king_panel = _KingPanel.new()
	_king_panel.custom_minimum_size = Vector2(200 if duel else 214, 62)
	_king_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_king_panel.player_name = PlayerAvatars.local_name
	_king_panel.av = PlayerAvatars.local_tex
	if match_on:
		_king_panel.speaking = Net.speaking.get(Net.local_id(), false)
	PlayerAvatars.local_ready.connect(func():
		if is_instance_valid(_king_panel):
			_king_panel.player_name = PlayerAvatars.local_name
			_king_panel.av = PlayerAvatars.local_tex
			_king_panel.queue_redraw())
	row.add_child(_king_panel)
	if match_on:
		_versus_rail = HBoxContainer.new()
		_versus_rail.add_theme_constant_override("separation", 6)
		_versus_rail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_versus_rail)
	elif duel:
		_ai_king_panel = _KingPanel.new()
		_ai_king_panel.is_ai = true
		_ai_king_panel.custom_minimum_size = Vector2(200, 62)
		_ai_king_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_ai_king_panel)

	# --- pastilles ressources ---
	var pills := PanelContainer.new()
	pills.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pills.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pills.add_theme_stylebox_override("panel", HudKit.sb_pill_group())
	row.add_child(pills)
	var ph := HBoxContainer.new()
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ph.add_theme_constant_override("separation", 8)
	pills.add_child(ph)
	_pill_ore = _ResPill.new("coin", Palette.ACCENT_GOLD)
	_pill_food = _ResPill.new("wheat", Palette.ACCENT_GREEN_LIT)
	ph.add_child(_pill_ore)
	ph.add_child(_pill_food)
	# labels compat (l'ancien code met a jour _minerai_lbl / _nourriture_lbl)
	_minerai_lbl = _pill_ore.value_lbl
	_nourriture_lbl = _pill_food.value_lbl

	# --- vague + phase (compact) ---
	var wv := VBoxContainer.new()
	wv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wv.add_theme_constant_override("separation", 1)
	row.add_child(wv)
	_wave_lbl = Label.new()
	_wave_lbl.add_theme_font_size_override("font_size", 14)
	_wave_lbl.add_theme_color_override("font_color", Palette.ACCENT_GREEN_LIT)
	wv.add_child(_wave_lbl)
	_phase_lbl = Label.new()
	_phase_lbl.add_theme_font_size_override("font_size", 11)
	_phase_lbl.add_theme_color_override("font_color", Palette.TEXT_DIM)
	wv.add_child(_phase_lbl)
	_king_lbl = Label.new()   ## compat (non affiche : le panneau ROI porte les PV)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)

	# --- controles : boutons carres + LANCER ---
	var ctrl := HBoxContainer.new()
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl.add_theme_constant_override("separation", 6)
	ctrl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ctrl)
	_speed_btn = _icon_btn("speed", func(): speed_pressed.emit())
	_speed_btn.tooltip_text = "Vitesse du jeu"
	ctrl.add_child(_speed_btn)
	var music_btn := _icon_btn("music", func(): pass)
	music_btn.pressed.connect(func():
		Audio.toggle_music()
		music_btn.set_meta("on", Audio.music_on)
		music_btn.queue_redraw())
	music_btn.set_meta("on", Audio.music_on)
	ctrl.add_child(music_btn)
	_start_btn = Button.new()
	_start_btn.text = "LANCER LA VAGUE"
	_start_btn.pressed.connect(func(): start_wave_pressed.emit())
	HudKit.btn_primary(_start_btn)
	_start_btn.add_theme_font_size_override("font_size", 14)
	ctrl.add_child(_start_btn)


## Petit bouton carre a icone (custom-draw).
func _icon_btn(icon: String, cb: Callable) -> Button:
	var b := _IconBtn.new()
	b.icon_kind = icon
	HudKit.btn_icon(b)
	b.pressed.connect(cb)
	return b


class _IconBtn extends Button:
	var icon_kind := "gear"
	func _draw() -> void:
		var col := Palette.TEXT_TITLE
		if icon_kind == "music" and not bool(get_meta("on", false)):
			col = Palette.TEXT_MUTE
		if icon_kind == "speed":
			var f := ThemeDB.fallback_font
			var v := int(round(Engine.time_scale))
			var t := "x%d" % maxi(1, v)
			col = Palette.ACCENT_AMBER if v > 1 else Palette.TEXT_TITLE
			var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			draw_string(f, Vector2((size.x - w) * 0.5, size.y * 0.5 + 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
			return
		HudIcon.paint(self, "pause" if icon_kind == "speed" else "gear" if icon_kind != "music" else "spark", size * 0.5, col)
		if icon_kind == "music":
			HudIcon.paint(self, "spark", size * 0.5, col)


## --- panneau du ROI : medaillon (avatar Nodyx / couronne / crane) + PV ---
class _KingPanel extends Control:
	var is_ai := false
	var av: Texture2D = null       ## avatar Nodyx du joueur local
	var player_name := ""          ## pseudo Nodyx du joueur local
	var speaking := false          ## micro actif (activite Nodyx)
	var _hp := 1.0
	var _hp_shown := 1.0
	var _cur := 100
	var _max := 100
	var _def := 0.0
	var _flash := 0.0
	var _pulse := 0.0
	func _process(d: float) -> void:
		_hp_shown = move_toward(_hp_shown, _hp, d * 1.6)
		_flash = maxf(0.0, _flash - d * 3.0)
		_pulse += d
		queue_redraw()
	func set_hp(cur: int, mx: int) -> void:
		if cur < _cur:
			_flash = 1.0
		_cur = cur
		_max = mx
		_hp = clampf(float(cur) / float(maxi(1, mx)), 0.0, 1.0)
	func set_def(d: float) -> void:
		_def = d
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var edge: Color = Palette.ACCENT_RED if is_ai else Palette.BORDER_GOLD
		draw_rect(Rect2(0, 0, w, h), Palette.PANEL_RAISED)
		draw_rect(Rect2(0, 0, w, h), edge, false, 2.0)
		draw_line(Vector2(2, 1.5), Vector2(w - 2, 1.5), Palette.BEVEL_HI, 1.0)
		draw_line(Vector2(2, h - 1.5), Vector2(w - 2, h - 1.5), Palette.BEVEL_LO, 1.5)
		# medaillon : avatar Nodyx (toi) / couronne (toi, sans avatar) / crane (IA)
		var mc := Vector2(30, h * 0.5)
		if speaking and not is_ai:
			var p := 0.5 + 0.5 * sin(_pulse * 9.0)
			draw_circle(mc, 23.0 + p * 3.0, Color(0.42, 0.86, 0.53, 0.30 + 0.35 * p))
		draw_circle(mc, 21, Color(0.13, 0.11, 0.09))
		if av != null and not is_ai:
			draw_texture_rect(av, Rect2(mc - Vector2(19, 19), Vector2(38, 38)), false)
		else:
			HudIcon.paint(self, "skull" if is_ai else "crown", mc + Vector2(0, 1), Palette.ACCENT_RED_LIT if is_ai else Palette.TEXT_TITLE)
		draw_arc(mc, 21, 0, TAU, 32, Palette.BORDER_BRONZE, 2.4)
		draw_arc(mc, 17, 0, TAU, 28, Color(edge.r, edge.g, edge.b, 0.5), 1.4)
		var f := ThemeDB.fallback_font
		var nm := "ROI ADVERSE" if is_ai else (player_name if player_name != "" else "LE ROI")
		draw_string(f, Vector2(58, 20), nm, HORIZONTAL_ALIGNMENT_LEFT, size.x - 66, 12, Palette.ACCENT_RED_LIT if is_ai else Palette.TEXT_TITLE)
		var br := Rect2(58, 27, w - 68, 12)
		draw_rect(br, Palette.TRACK_DARK)
		draw_rect(br, Color(0, 0, 0, 0.55), false, 1.0)
		var fill := Palette.FILL_RED if _hp_shown > 0.30 else Palette.HP_RED_HI
		if _flash > 0.0:
			fill = fill.lerp(Color(1, 1, 1), _flash * 0.7)
		draw_rect(Rect2(br.position, Vector2(br.size.x * _hp_shown, br.size.y)), fill)
		draw_line(br.position + Vector2(0, 1), br.position + Vector2(br.size.x * _hp_shown, 1), fill.lightened(0.3), 1.0)
		var txt := "%d / %d   ·   def %d" % [_cur, _max, roundi(_def)] if is_ai else "%d / %d" % [_cur, _max]
		draw_string(f, Vector2(58, 54), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.TEXT_DIM)


## --- pastille ressource : icone + valeur + "+X/s" ---
class _ResPill extends PanelContainer:
	var value_lbl: Label
	var rate_lbl: Label
	func _init(icon_kind: String, tint: Color) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_stylebox_override("panel", HudKit.sb_pill())
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", 6)
		add_child(h)
		var ic := HudIcon.new()
		ic.custom_minimum_size = Vector2(18, 18)
		ic.setup(icon_kind, tint)
		h.add_child(ic)
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 0)
		h.add_child(v)
		value_lbl = Label.new()
		value_lbl.add_theme_font_size_override("font_size", 17)
		value_lbl.add_theme_color_override("font_color", Palette.TEXT)
		value_lbl.text = "0"
		v.add_child(value_lbl)
		rate_lbl = Label.new()
		rate_lbl.add_theme_font_size_override("font_size", 10)
		rate_lbl.add_theme_color_override("font_color", Palette.ACCENT_GREEN_LIT)
		v.add_child(rate_lbl)
	func set_rate(txt: String) -> void:
		rate_lbl.text = txt
		rate_lbl.visible = txt != ""


## COLONNE GAUCHE : cartes de construction (BATAILLE = tours, FERME = eco) + DEMOLIR.
func _build_left_column() -> void:
	var pan := PanelContainer.new()
	pan.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	pan.offset_top = 104.0
	pan.offset_right = 232.0
	pan.mouse_filter = Control.MOUSE_FILTER_PASS
	pan.add_theme_stylebox_override("panel", HudKit.sb_panel_edge(SIDE_LEFT))
	add_child(pan)
	HudKit.add_ornament(pan, false, true)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pan.add_child(v)

	var duel := GameState.mode == GameState.Mode.DUEL

	# --- cartes BATAILLE ---
	_col_battle = VBoxContainer.new()
	_col_battle.add_theme_constant_override("separation", 6)
	v.add_child(_col_battle)
	HudKit.add_section(_col_battle, "Tours", "sword")
	for tid in Catalog.ORDER:
		if Catalog.cat(tid) == "peon" or Catalog.cat(tid) == "fermier":
			continue
		var c := _build_card(tid)
		_build_btns[tid] = c
		_col_battle.add_child(c)

	# --- cartes FERME ---
	_col_farm = VBoxContainer.new()
	_col_farm.add_theme_constant_override("separation", 6)
	v.add_child(_col_farm)
	var farm_groups := [
		{"title": "Mines", "icon": "pick", "ids": ["peon"]},
		{"title": "Fermes", "icon": "wheat", "ids": ["fermier"]},
	]
	if duel:
		farm_groups.append({"title": "Garnison", "icon": "keep", "ids": Catalog.CASERNES})
	for g in farm_groups:
		HudKit.add_section(_col_farm, g["title"], g["icon"])
		for fid in g["ids"]:
			var c := _build_card(fid)
			_build_btns[fid] = c
			_col_farm.add_child(c)
	_col_farm.visible = false

	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(grow)

	# --- conseil contextuel ---
	_ctx_lbl = Label.new()
	_ctx_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ctx_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ctx_lbl.add_theme_font_size_override("font_size", 11)
	_ctx_lbl.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_ctx_lbl.custom_minimum_size = Vector2(0, 46)
	v.add_child(_ctx_lbl)

	# --- DEMOLIR ---
	_demolir_btn = Button.new()
	_demolir_btn.text = "  DÉMOLIR"
	_demolir_btn.tooltip_text = "Revends la tour selectionnee (50 %)"
	_demolir_btn.pressed.connect(func(): demolish_pressed.emit())
	HudKit.btn_danger(_demolir_btn)
	_demolir_btn.add_theme_font_size_override("font_size", 13)
	var trash := HudIcon.new()
	trash.setup("trash", Palette.ACCENT_RED_LIT)
	trash.position = Vector2(12, 10)
	_demolir_btn.add_child(trash)
	v.add_child(_demolir_btn)


func _refresh_tabs() -> void:
	HudKit.style_tab(_tab_battle, _view == "battle")
	HudKit.style_tab(_tab_farm, _view == "farm")


## appele par main._set_view : bascule les colonnes de cartes + boutons.
func set_view(v: String) -> void:
	_view = v
	if is_instance_valid(_col_battle):
		_col_battle.visible = v == "battle"
	if is_instance_valid(_col_farm):
		_col_farm.visible = v == "farm"
	if is_instance_valid(_start_btn):
		_start_btn.visible = v == "battle"
	if is_instance_valid(_demolir_btn):
		_demolir_btn.visible = v == "battle"
	if is_instance_valid(_wave_sec):
		_wave_sec.visible = v == "battle"
	if is_instance_valid(_eco_box):
		_eco_box.visible = v == "farm"
	_refresh_tabs()
	_refresh_ctx()


## Carte de construction : puits d'icone + nom or + coup + courte description.
func _build_card(id: String) -> _BuildCard:
	var c := _BuildCard.new()
	c.setup(id)
	c.pressed.connect(func(): build_pressed.emit(id))
	c.mouse_entered.connect(func():
		var txt := Catalog.desc(id)
		if Catalog.cat(id) == "tower":
			var sc := Catalog.tower_surcharge()
			if Catalog.towers_full():
				txt += "  ·  LIMITE (%d tours) : ameliore ou revends." % Catalog.TOWER_CAP
			elif sc > 0.0:
				txt += "  ·  %d/%d tours, prix +%d%%." % [GameState.towers_built, Catalog.TOWER_CAP, roundi(sc * 100.0)]
		_ctx_lbl.text = txt)
	c.mouse_exited.connect(_refresh_ctx)
	return c


## --- carte de construction (colonne gauche) ---
class _BuildCard extends Button:
	var id := ""
	var _chosen := false

	func setup(bid: String) -> void:
		id = bid
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(0, 68)
		_restyle()

	func set_chosen(on: bool) -> void:
		if _chosen == on:
			return
		_chosen = on
		_restyle()

	func _restyle() -> void:
		add_theme_stylebox_override("normal", HudKit.sb_card("selected" if _chosen else "normal"))
		add_theme_stylebox_override("hover", HudKit.sb_card("selected" if _chosen else "hover"))
		add_theme_stylebox_override("pressed", HudKit.sb_card("pressed"))
		add_theme_stylebox_override("disabled", HudKit.sb_card("disabled"))
		queue_redraw()

	func _draw() -> void:
		var f := ThemeDB.fallback_font
		var dim := disabled
		var acc: Color = Catalog.color(id)
		# puits d'icone
		var wr := Rect2(8, (size.y - 44) * 0.5, 44, 44)
		draw_rect(wr, Palette.WELL)
		var wc: Color = Palette.BORDER_GOLD if _chosen else acc.lerp(Palette.BORDER_BRONZE, 0.55)
		if dim:
			wc = Palette.BORDER_DIM
		draw_rect(wr, wc, false, 2.0)
		HudIcon.paint(self, _sigil(), wr.get_center(), Palette.TEXT_MUTE if dim else acc)
		# nom
		var name_col: Color = Palette.TEXT_MUTE if dim else Palette.TEXT_TITLE
		draw_string(f, Vector2(62, 21), Catalog.label(id).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 70, 13, name_col)
		# cout
		var wallet: int = GameState.nourriture if Catalog.cat(id) == "caserne" else GameState.minerai
		var cost := Catalog.cost(id)
		var poor := wallet < cost
		var cost_col: Color = Palette.ACCENT_RED_LIT if (poor or dim) else Palette.ACCENT_GOLD
		HudIcon.paint(self, "coin", Vector2(68, 37), cost_col)
		draw_string(f, Vector2(78, 41), str(cost), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, cost_col)
		# courte description (1 ligne, tronquee)
		draw_string(f, Vector2(62, 58), _short(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 68, 10, Palette.TEXT_DIM)

	func _sigil() -> String:
		match id:
			"canon": return "cannon"
			"gatling": return "swords"
			"mortier": return "cannon"
			"givre": return "frost"
			"guerriere": return "shield"
			"archere": return "bow"
			"peon": return "pick"
			"fermier": return "wheat"
			_: return "keep"

	func _short() -> String:
		var d := Catalog.desc(id)
		var cut := d.find(".")
		if cut > 0:
			d = d.substr(0, cut)
		if d.length() > 24:
			var w := d.substr(0, 24).rfind(" ")
			d = d.substr(0, w if w > 10 else 23).strip_edges() + "…"
		return d



func _mini_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(cb)
	for st in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(4)
		s.content_margin_left = 8
		s.content_margin_right = 8
		s.content_margin_top = 5
		s.content_margin_bottom = 5
		s.bg_color = Palette.BTN if st == "normal" else Palette.BTN_HOVER
		b.add_theme_stylebox_override(st, s)
	b.add_theme_color_override("font_color", Palette.TEXT_DIM)
	return b


func set_speed(v: float) -> void:
	if _speed_btn:
		_speed_btn.tooltip_text = "Vitesse x%d" % roundi(v)
		_speed_btn.queue_redraw()


func _accent_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	b.add_theme_font_size_override("font_size", 14)
	for st in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(5)
		s.content_margin_left = 14
		s.content_margin_right = 14
		s.content_margin_top = 7
		s.content_margin_bottom = 7
		match st:
			"normal": s.bg_color = Color(0.44, 0.09, 0.10)
			"hover": s.bg_color = Color(0.56, 0.13, 0.13)
			"pressed": s.bg_color = Color(0.34, 0.07, 0.08)
			"disabled": s.bg_color = Palette.BTN_OFF
		s.border_color = Color(0.72, 0.54, 0.26)
		s.set_border_width_all(1 if st != "disabled" else 0)
		b.add_theme_stylebox_override(st, s)
	b.add_theme_color_override("font_color", Palette.GOLD_TEXT)
	b.add_theme_color_override("font_disabled_color", Palette.TEXT_DIM.darkened(0.25))
	return b


func _stat(parent: Node, icon_kind: String, color: Color) -> Label:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)
	var icon := HudIcon.new()
	icon.setup(icon_kind, color)
	box.add_child(icon)
	return _mk_label(box, color, 15)


func _mk_label(parent: Node, color: Color, size: int) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


# --- banniere / recap / defaite ------------------------------------------

func _build_banner() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_top = -110.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_banner = Label.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_font_size_override("font_size", 44)
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_banner.modulate.a = 0.0
	center.add_child(_banner)


## COLONNE DROITE : PROCHAINE VAGUE + STATISTIQUES + reliques.  Cadre sobre
## (sb_panel_edge + equerres), plus de parchemin surcharge.
func _build_war_table() -> void:
	if right_panel_w <= 0.0 or GameState.mode == GameState.Mode.DUEL:
		return
	var pan := PanelContainer.new()
	pan.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	pan.offset_left = -right_panel_w
	pan.offset_top = 104.0
	pan.mouse_filter = Control.MOUSE_FILTER_PASS
	pan.add_theme_stylebox_override("panel", HudKit.sb_panel_edge(SIDE_RIGHT))
	add_child(pan)
	HudKit.add_ornament(pan, false, true)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pan.add_child(v)

	# --- section PROCHAINE VAGUE (vue BATAILLE) ---
	_wave_sec = VBoxContainer.new()
	_wave_sec.add_theme_constant_override("separation", 8)
	v.add_child(_wave_sec)
	HudKit.add_section(_wave_sec, "Prochaine vague", "skull")
	_wave_preview = HBoxContainer.new()
	_wave_preview.mouse_filter = Control.MOUSE_FILTER_PASS
	_wave_preview.add_theme_constant_override("separation", 6)
	_wave_sec.add_child(_wave_preview)
	_wave_mods_lbl = _mk_label(_wave_sec, Palette.ACCENT_RED_LIT, 11)
	_wave_mods_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_wave_panel = pan

	# --- section ECONOMIE (vue FERME) : la boucle du royaume ---
	_eco_box = VBoxContainer.new()
	_eco_box.add_theme_constant_override("separation", 6)
	_eco_box.visible = false
	v.add_child(_eco_box)
	HudKit.add_section(_eco_box, "Economie", "coin")
	_eco_lbls["mine"] = _eco_row("Mine", "pick", Palette.ACCENT_BLUE)
	_eco_lbls["champ"] = _eco_row("Ferme", "wheat", Palette.ACCENT_GREEN_LIT)
	_eco_lbls["garn"] = _eco_row("Garnison", "keep", Palette.ACCENT_RED_LIT)
	var loop := Label.new()
	loop.text = "\n⛏ MINE → minerai → défenses\n🌾 FERME → blé → casernes\n⚔ GARNISON → troupes"
	loop.add_theme_font_size_override("font_size", 10)
	loop.add_theme_color_override("font_color", Palette.TEXT_MUTE)
	_eco_box.add_child(loop)

	v.add_child(HudKit._Rule.new())
	HudKit.add_section(v, "Statistiques", "gear")
	_stats_box = VBoxContainer.new()
	_stats_box.add_theme_constant_override("separation", 3)
	v.add_child(_stats_box)

	var relics_wrap := MarginContainer.new()
	relics_wrap.add_theme_constant_override("margin_top", 8)
	v.add_child(relics_wrap)
	_relic_bar = HBoxContainer.new()
	_relic_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	_relic_bar.add_theme_constant_override("separation", 4)
	relics_wrap.add_child(_relic_bar)
	_rebuild_relics()
	_refresh_stats_box()


func _eco_row(key: String, icon_kind: String, tint: Color) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eco_box.add_child(row)
	var ic := HudIcon.new()
	ic.custom_minimum_size = Vector2(15, 15)
	ic.setup(icon_kind, tint)
	row.add_child(ic)
	var k := Label.new()
	k.text = key.to_upper()
	k.add_theme_font_override("font", HudKit.tracked_font(1))
	k.add_theme_font_size_override("font_size", 11)
	k.add_theme_color_override("font_color", Palette.TEXT_DIM)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(k)
	var val := Label.new()
	val.add_theme_font_size_override("font_size", 13)
	val.add_theme_color_override("font_color", tint)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	return val


func _stat_row(key: String, icon_kind: String, tint: Color) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_box.add_child(row)
	var ic := HudIcon.new()
	ic.custom_minimum_size = Vector2(14, 14)
	ic.setup(icon_kind, tint)
	row.add_child(ic)
	var k := Label.new()
	k.text = key.to_upper()
	k.add_theme_font_override("font", HudKit.tracked_font(1))
	k.add_theme_font_size_override("font_size", 11)
	k.add_theme_color_override("font_color", Palette.TEXT_DIM)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(k)
	var val := Label.new()
	val.add_theme_font_size_override("font_size", 13)
	val.add_theme_color_override("font_color", Palette.TEXT)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	return val


func _refresh_stats_box() -> void:
	if not is_instance_valid(_stats_box):
		return
	for c in _stats_box.get_children():
		c.queue_free()
	_stat_lbls.clear()
	_stat_lbls["king"] = _stat_row("Vies du roi", "heart", Palette.ACCENT_RED_LIT)
	_stat_lbls["gold"] = _stat_row("Or actuel", "coin", Palette.ACCENT_GOLD)
	_stat_lbls["towers"] = _stat_row("Tours placees", "sword", Palette.TEXT_DIM)
	_stat_lbls["food"] = _stat_row("Ble", "wheat", Palette.ACCENT_GREEN_LIT)


func _tick_stats_box() -> void:
	if _stat_lbls.is_empty():
		return
	_stat_lbls["king"].text = "%d / %d" % [GameState.king_hp, GameState.king_max]
	_stat_lbls["gold"].text = str(GameState.minerai)
	_stat_lbls["towers"].text = "%d / %d" % [GameState.towers_built, Catalog.TOWER_CAP]
	_stat_lbls["food"].text = str(GameState.nourriture)


func _rebuild_relics() -> void:
	if not is_instance_valid(_relic_bar):
		return
	for c in _relic_bar.get_children():
		c.queue_free()
	for id in Meta.relics:
		var chip := PanelContainer.new()
		chip.custom_minimum_size = Vector2(26, 26)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.tooltip_text = "%s\n%s" % [Meta.relic_label(id), Meta.relic_desc(id)]
		var s := StyleBoxFlat.new()
		s.bg_color = Meta.relic_color(id).darkened(0.35)
		s.border_color = Meta.relic_color(id)
		s.set_border_width_all(2)
		s.set_corner_radius_all(4)
		chip.add_theme_stylebox_override("panel", s)
		var dot := Label.new()
		dot.text = Meta.relic_label(id).substr(0, 1)
		dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dot.add_theme_font_size_override("font_size", 12)
		dot.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		chip.add_child(dot)
		_relic_bar.add_child(chip)


func _build_champ() -> void:
	_champ = PanelContainer.new()
	_champ.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_champ.offset_left = -210
	_champ.offset_right = 210
	_champ.offset_top = avatar_h + 132.0
	_champ.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_champ.visible = false
	var s := StyleBoxFlat.new()
	s.bg_color = Palette.PANEL_BG
	s.set_corner_radius_all(6)
	s.border_color = Palette.DANGER_TEXT
	s.set_border_width_all(1)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 5
	s.content_margin_bottom = 6
	_champ.add_theme_stylebox_override("panel", s)
	add_child(_champ)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	_champ.add_child(v)
	var t := Label.new()
	t.text = "☠  CHAMPION"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 13)
	t.add_theme_color_override("font_color", Palette.DANGER_TEXT)
	v.add_child(t)
	_champ_bar = ProgressBar.new()
	_champ_bar.custom_minimum_size = Vector2(356, 12)
	_champ_bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Palette.DANGER_TEXT
	fg.set_corner_radius_all(3)
	_champ_bar.add_theme_stylebox_override("background", bg)
	_champ_bar.add_theme_stylebox_override("fill", fg)
	v.add_child(_champ_bar)


## Ecran de renfort de fin de vague : overlay sombre plein ecran, crete cramoisie,
## 3 grandes cartes ornees (reference : Death Must Die / Tails of Iron).
func _build_recap() -> void:
	_recap = PanelContainer.new()
	_recap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_recap.modulate.a = 0.0
	_recap.visible = false
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.015, 0.015, 0.022, 0.955)
	_recap.add_theme_stylebox_override("panel", s)
	add_child(_recap)

	var center := CenterContainer.new()
	_recap.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)

	# --- crete de titre ---
	var crest := _RecapCrest.new()
	crest.custom_minimum_size = Vector2(520, 54)
	v.add_child(crest)

	_recap_lbl = RichTextLabel.new()
	_recap_lbl.bbcode_enabled = true
	_recap_lbl.fit_content = true
	_recap_lbl.custom_minimum_size = Vector2(560, 0)
	_recap_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recap_lbl.add_theme_font_size_override("normal_font_size", 13)
	_recap_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	_recap_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_recap_lbl)

	_boon_title = Label.new()
	_boon_title.add_theme_font_size_override("font_size", 13)
	_boon_title.add_theme_color_override("font_color", Palette.KING)
	_boon_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_boon_title)

	_boon_box = HBoxContainer.new()   ## 3 cartes cote a cote
	_boon_box.add_theme_constant_override("separation", 18)
	_boon_box.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_boon_box)


func _build_gameover() -> void:
	_over = Control.new()
	_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.visible = false
	add_child(_over)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_over.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -160
	box.offset_right = 160
	box.offset_top = -70
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	_over.add_child(box)
	var t := Label.new()
	t.name = "title"
	t.text = "DEFAITE"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 46)
	t.add_theme_color_override("font_color", Palette.DANGER_TEXT)
	box.add_child(t)
	var sub := Label.new()
	sub.name = "sub"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Palette.TEXT_DIM)
	box.add_child(sub)
	var rec := Label.new()
	rec.name = "rec"
	rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rec.add_theme_font_size_override("font_size", 13)
	rec.visible = false
	box.add_child(rec)
	var cont := _accent_button("CONTINUER  ·  mode sans fin", func():
		_over.visible = false
		GameState.resume_endless())
	cont.name = "cont"
	cont.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cont.visible = false
	box.add_child(cont)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	row.add_child(_accent_button("REJOUER", func(): restart_pressed.emit()))
	var menu := _accent_button("MENU", func(): get_tree().change_scene_to_file("res://scenes/title.tscn"))
	menu.add_theme_color_override("font_color", Palette.TEXT)
	row.add_child(menu)


# --- API ----------------------------------------------------------------

func set_selection(id: String) -> void:
	for k in _build_btns:
		_build_btns[k].set_chosen(k == id)
	_refresh_ctx()


func banner(text: String, color: Color, hold := 1.0, permanent := false) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	var tw := create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.18)
	if not permanent:
		tw.tween_interval(hold)
		tw.tween_property(_banner, "modulate:a", 0.0, 0.5)


func flash(msg: String) -> void:
	_ctx_lbl.text = msg
	_ctx_lbl.add_theme_color_override("font_color", Palette.DANGER_TEXT)
	var tw := create_tween()
	tw.tween_interval(1.3)
	tw.tween_callback(_refresh_ctx)


func flash_denied() -> void:
	flash("Pas assez de minerai !")


# --- internes ----------------------------------------------------------

func _on_king(v: int, mx: int) -> void:
	if is_instance_valid(_king_lbl):
		_king_lbl.text = "%d/%d" % [v, mx]
	if is_instance_valid(_king_panel):
		_king_panel.set_hp(v, mx)
	if is_instance_valid(_p1_card):
		_p1_card.set_hp(float(v) / float(maxi(1, mx)))
		_p1_card.set_sub("roi %d/%d" % [v, mx])


func _on_phase(p: int) -> void:
	if p == GameState.Phase.COMBAT:
		banner("VAGUE %d" % GameState.wave, Palette.SPAWN, 0.9)
		_hide_recap(true)
	_refresh()


func _on_wave_cleared(w: int) -> void:
	if _match_send:
		var ls = MatchDirector.local_state()
		if ls != null and ls.alive:
			banner("MANCHE %d TENUE : construis, puis clique PRÊT" % w, Palette.HP_GOOD, 1.4)
		return
	banner("VAGUE %d REPOUSSEE" % w, Palette.HP_GOOD, 1.2)
	_show_recap()


func _on_champion(cur: float, maxhp: float, alive: bool) -> void:
	_champ.visible = alive
	if alive and maxhp > 0.0:
		_champ_bar.max_value = maxhp
		_champ_bar.value = cur


func _offer_boons() -> void:
	for c in _boon_box.get_children():
		c.queue_free()
	var ids: Array = Meta.draw_choices(3)
	_boon_title.text = "RENFORT DU ROI  ·  choisis-en un"
	for i in ids.size():
		var id: String = ids[i]
		var info: Dictionary = Meta.BOONS[id]
		var card := _BoonCard.new(String(info["label"]), String(info["desc"]), i == 1)
		card.id_txt = id
		card.rare = int(info.get("tier", 0)) == 1
		card.pressed.connect(func(): _pick_boon(id))
		_boon_box.add_child(card)


func _pick_boon(id: String) -> void:
	Meta.apply(id)
	Audio.play("boon")
	Fx.shake(3.0)
	boon_pressed.emit(id)
	for c in _boon_box.get_children():
		if c is _BoonCard:
			c.chosen = String(Meta.BOONS[id]["label"]) == c.title_txt
			c.disabled = true
			c.queue_redraw()
	_boon_title.text = "Renfort acquis :  %s" % Meta.BOONS[id]["label"]
	if _recap_tw and _recap_tw.is_valid():
		_recap_tw.kill()
	_recap_tw = create_tween()
	_recap_tw.tween_interval(1.8)
	_recap_tw.tween_property(_recap, "modulate:a", 0.0, 0.6)
	_recap_tw.tween_callback(func(): _recap.visible = false)


func _on_game_over(win: bool) -> void:
	_banner.modulate.a = 0.0
	_hide_recap(true)
	_champ.visible = false
	var t := _over.find_child("title", true, false)
	var sub := _over.find_child("sub", true, false)
	var cont := _over.find_child("cont", true, false)
	var duel := GameState.mode == GameState.Mode.DUEL
	if t:
		t.text = "VICTOIRE" if win else "DEFAITE"
		t.add_theme_color_override("font_color", Palette.HP_GOOD if win else Palette.DANGER_TEXT)
	if sub:
		if duel:
			sub.text = ("Le roi adverse est tombe (vague %d) !" % GameState.wave) if win \
				else "Ton roi est tombe a la vague %d." % GameState.wave
		elif win:
			sub.text = "Les %d vagues repoussees. Continue pour voir jusqu'ou tu tiens." % GameState.WIN_WAVE
		elif GameState.endless:
			sub.text = "Mode sans fin : tu as tenu jusqu'a la vague %d." % GameState.wave
		else:
			sub.text = "Le roi est tombe a la vague %d." % GameState.wave
	if cont:
		cont.visible = win and not duel
	var rec := _over.find_child("rec", true, false)
	if rec:
		_fill_over_records(rec)
	_over.visible = true
	_update_buttons()


## Ligne records sur l'ecran de fin : stats a jour + tete du classement.
## N'apparait qu'en activite Nodyx (l'autoload Records a un pont).
func _fill_over_records(rec: Label) -> void:
	if not GameState.in_nodyx_activity:
		rec.visible = false
		return
	var s: Dictionary = Records.stats
	var parts := PackedStringArray()
	if Records.beat_record:
		rec.add_theme_color_override("font_color", Palette.KING)
		parts.append("NOUVEAU RECORD  ·  vague %d" % int(s.get("best_wave", 0)))
	else:
		rec.add_theme_color_override("font_color", Palette.TEXT_DIM)
		if not s.is_empty():
			parts.append("%d parties  ·  %d victoires  ·  record vague %d" % [
				int(s.get("games", 0)), int(s.get("wins", 0)), int(s.get("best_wave", 0))])
	var board: Array = Records.leaderboard
	if not board.is_empty():
		var top: Dictionary = board[0]
		parts.append("classement : %s en tete (%d victoires)" % [
			String(top.get("name", "?")), int(top.get("wins", 0))])
	rec.text = "\n".join(parts)
	rec.visible = parts.size() > 0


func _show_recap() -> void:
	var r: Dictionary = GameState.wave_recap
	if r.is_empty():
		return
	var leaks := int(r.get("leaks", 0))
	var lines := PackedStringArray()
	lines.append("[b]Vague %d[/b]" % GameState.wave)
	lines.append("Tues : [color=#8fdc7f]%d[/color]      Minerai : [color=#f2c14e]+%d[/color] primes  [color=#f2c14e]+%d[/color] fin de vague" % [
		int(r.get("kills", 0)), int(r.get("gold", 0)), int(r.get("income", 0))])
	if leaks == 0:
		var deep := int(round(float(r.get("deepest", 0.0)) * 100.0))
		lines.append("[color=#8fdc7f]Aucune fuite.[/color]  Menace la plus profonde : %d%% du parcours." % deep)
	else:
		var by := PackedStringArray()
		for tid in r.get("leak_types", {}):
			var lbl: String = "CHAMPION" if tid == "CHAMPION" else Enemy.TYPES[tid]["label"]
			by.append("%d x %s" % [int(r["leak_types"][tid]), lbl])
		lines.append("[color=#ff6f5c]Fuites : %d  (%s)   -%d PV roi[/color]" % [
			leaks, ", ".join(by), int(r.get("hp_lost", 0))])
	var healed := int(round(float(r.get("healed", 0.0))))
	if healed > 0:
		lines.append("[color=#6fdc8f]Soins ennemis : %d PV[/color]  (les Soigneurs, vise-les ou frappe en zone)" % healed)
	_recap_lbl.text = "\n".join(lines)

	_offer_boons()

	if _recap_tw and _recap_tw.is_valid():
		_recap_tw.kill()
	_recap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_recap.z_index = 50
	_recap.modulate.a = 0.0
	_recap.visible = true
	# masque le reste du HUD -> vrai ecran modal
	if _wave_panel: _wave_panel.visible = false
	if _champ: _champ.visible = false
	_recap_tw = create_tween()
	_recap_tw.tween_property(_recap, "modulate:a", 1.0, 0.25)


func _hide_recap(now: bool) -> void:
	if _recap_tw and _recap_tw.is_valid():
		_recap_tw.kill()
	if now:
		_recap.modulate.a = 0.0
		_recap.visible = false
	else:
		_recap_tw = create_tween()
		_recap_tw.tween_property(_recap, "modulate:a", 0.0, 0.4)
		_recap_tw.tween_callback(func(): _recap.visible = false)
	if _wave_panel: _wave_panel.visible = true


func _update_buttons() -> void:
	var m := GameState.minerai
	var build := GameState.phase == GameState.Phase.BUILD and not GameState.finished
	var full := Catalog.towers_full()
	for id in _build_btns:
		var b: Button = _build_btns[id]
		var kind := Catalog.cat(id)
		var is_tower := kind == "tower"
		var is_caserne := kind == "caserne"
		var free := kind == "peon" or kind == "fermier" or build
		var wallet: int = GameState.nourriture if is_caserne else m
		b.disabled = GameState.finished or not free or wallet < Catalog.cost(id) or (is_tower and full)
		b.queue_redraw()
	if _start_btn and not _match_send:
		_start_btn.disabled = not build
	elif _start_btn and _match_send:
		var ls = MatchDirector.local_state()
		var mine_ready: bool = ls != null and ls.ready
		_start_btn.disabled = MatchDirector.phase != MatchDirector.Phase.BUILD or mine_ready
		_start_btn.text = ("PRÊT ✓" if mine_ready else "PRÊT") if MatchDirector.phase == MatchDirector.Phase.BUILD else "MANCHE EN COURS…"
	if _demolir_btn:
		_demolir_btn.disabled = not build


func _refresh_ctx() -> void:
	if GameState.finished:
		return
	_ctx_lbl.add_theme_color_override("font_color", Palette.TEXT_DIM)
	if _view == "farm":
		_ctx_lbl.text = "Place tes ouvriers : MINE -> minerai (defenses), FERME -> ble (casernes), GARNISON -> troupes. Ils produisent pendant le combat."
		if is_instance_valid(_wave_sec):
			_wave_sec.visible = false
		return
	var build := GameState.phase == GameState.Phase.BUILD
	if is_instance_valid(_wave_sec):
		_wave_sec.visible = true
	var pre := "SANS FIN · " if GameState.endless else ""
	if not build:
		_ctx_lbl.text = pre + "Vague %d en cours, tiens la ligne !" % GameState.wave
		return
	if GameState.endless:
		_ctx_lbl.text = "SANS FIN · vague %d survecue. Chaque vague est plus dure, tiens le plus longtemps." % GameState.wave
	elif GameState.wave > 0:
		_ctx_lbl.text = "Vague %d survecue. Renforce, ameliore, puis lance la suivante." % GameState.wave
	else:
		_ctx_lbl.text = "Compose ton labyrinthe de tours. Espace ou LANCER pour demarrer."
	_rebuild_preview(GameState.wave + 1)


func _rebuild_preview(w: int) -> void:
	if not is_instance_valid(_wave_preview):
		return
	for c in _wave_preview.get_children():
		c.queue_free()
	var d := WaveManager.wave_data(w)
	for g in d["g"]:
		var card := WaveCard.new()
		card.setup(g["t"], int(g["n"]), false)
		_wave_preview.add_child(card)
	if WaveManager.has_champion(w):
		var cc := WaveCard.new()
		cc.setup("colosse", 1, true)
		_wave_preview.add_child(cc)
	if not is_instance_valid(_wave_mods_lbl):
		return
	if d["m"].is_empty():
		_wave_mods_lbl.text = ""
	else:
		var ml := PackedStringArray()
		for x in d["m"]:
			ml.append(Enemy.MOD_LABEL.get(x, x))
		_wave_mods_lbl.text = "toute la vague : " + " + ".join(ml)


func _refresh() -> void:
	if GameState.finished:
		_update_buttons()
		return
	var build := GameState.phase == GameState.Phase.BUILD
	_wave_lbl.text = "VAGUE %d / %d" % [maxi(1, GameState.wave), GameState.WIN_WAVE]
	_phase_lbl.text = "Construction : prepare ta defense" if build else "Combat : tiens la ligne"
	_refresh_ctx()
	_update_buttons()


## Panneau de droite : page de grimoire : vellum, ferrures, chaines, sceau,
## plaque de titre bordeaux, accent bleu pour l'element vif.  (ref : Tails of Iron)
class _WarTable extends Control:
	var _t := 0.0
	const INK := Color(0.14, 0.10, 0.06)
	const INK_DIM := Color(0.30, 0.23, 0.14)
	const BLUE := Color(0.29, 0.55, 0.66)     ## accent interactif
	const BURG := Color(0.34, 0.10, 0.11)     ## bordeaux des plaques

	func _ready() -> void:
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		if int(_t * 2.0) != int((_t - delta) * 2.0):
			queue_redraw()

	## chaine decorative horizontale (maillons ovales)
	func _chain(y: float, x0: float, x1: float) -> void:
		var x := x0
		var k := 0
		while x < x1:
			var vert := k % 2 == 0
			var w := 6.0 if vert else 9.0
			var h := 9.0 if vert else 5.0
			draw_arc(Vector2(x + 4, y), maxf(w, h) * 0.5, 0, TAU, 10, INK, 1.6)
			x += 8.0
			k += 1

	## plaque : rectangle arrondi (approx) rempli + contour encre
	func _plaque(rc: Rect2, fill: Color) -> void:
		draw_rect(rc, fill)
		draw_rect(Rect2(rc.position - Vector2(0, 3), Vector2(rc.size.x, 3)), fill.darkened(0.2))
		draw_rect(rc.grow(2), INK, false, 2.0)
		draw_rect(rc, Color(0, 0, 0, 0.25), false, 1.0)

	## cadre a fente : boite d'icone facon inventaire
	func _slot(rc: Rect2) -> void:
		draw_rect(rc, Color(0.16, 0.13, 0.09, 0.6))
		draw_rect(rc, INK, false, 2.0)
		draw_line(rc.position + Vector2(2, 2), rc.position + Vector2(rc.size.x - 2, 2), Color(1, 1, 1, 0.08), 1.0)

	func _draw() -> void:
		var s := size
		var vell_top := Color(0.66, 0.58, 0.43, 0.97)
		var vell_bot := Color(0.50, 0.43, 0.30, 0.97)
		# reliure : bande de cuir sombre tout autour
		draw_rect(Rect2(Vector2(-6, -6), s + Vector2(12, 12)), Color(0.06, 0.04, 0.02, 0.85))
		draw_rect(Rect2(Vector2(-4, -4), s + Vector2(8, 8)), Color(0.16, 0.11, 0.07))
		# --- feuille de parchemin : contour DECHIQUETE (pas un rectangle propre) ---
		var edge := PackedVector2Array()
		var per := 44
		for i in per:
			var tt := float(i) / float(per)
			var e: Vector2
			if tt < 0.25: e = Vector2(lerp(4.0, s.x - 4.0, tt / 0.25), 4.0)
			elif tt < 0.5: e = Vector2(s.x - 4.0, lerp(4.0, s.y - 4.0, (tt - 0.25) / 0.25))
			elif tt < 0.75: e = Vector2(lerp(s.x - 4.0, 4.0, (tt - 0.5) / 0.25), s.y - 4.0)
			else: e = Vector2(4.0, lerp(s.y - 4.0, 4.0, (tt - 0.75) / 0.25))
			var jit := (absf(fmod(sin(float(i) * 17.3) * 9421.0, 1.0)) - 0.5) * 7.0
			var inw := Vector2(signf(s.x * 0.5 - e.x), signf(s.y * 0.5 - e.y))
			edge.append(e + inw * absf(jit))
		draw_colored_polygon(edge, vell_top)
		# degrade vertical par-dessus (garde dans la feuille)
		var n := 40
		for i in n:
			var ff := float(i) / float(n - 1)
			draw_rect(Rect2(Vector2(6, s.y * ff - 0.5), Vector2(s.x - 12, s.y / n + 1.5)),
				Color(0, 0, 0, 0) if i == 0 else vell_top.lerp(vell_bot, ff))
		draw_colored_polygon(edge, vell_top)   ## re-couche pour la teinte
		draw_polyline(edge, Color(0.22, 0.15, 0.08, 0.7), 2.0)
		# ombre interne (le bord de la page s'incurve)
		for k in 5:
			var kv := float(k) / 5.0
			draw_rect(Rect2(Vector2(6 + k * 2.0, 6 + k * 2.0), s - Vector2(12 + k * 4.0, 12 + k * 4.0)),
				Color(0.15, 0.10, 0.05, 0.12 * (1.0 - kv)), false, 3.0)
		# taches de the : contours irreguliers, jamais concentriques
		for k in 3:
			var hx := absf(fmod(sin(float(k) * 12.9898) * 43758.5453, 1.0))
			var hy := absf(fmod(sin(float(k) * 78.233 + 1.3) * 43758.5453, 1.0))
			var rr := 20.0 + hx * 26.0
			var rc := Vector2(clampf(hx * s.x, rr, s.x - rr), clampf(hy * s.y, rr, s.y - rr))
			var blob := PackedVector2Array()
			for a in 16:
				var jr := 0.72 + absf(fmod(sin(float(k * 31 + a) * 6.27) * 1731.0, 1.0)) * 0.5
				blob.append(rc + Vector2.RIGHT.rotated(a * TAU / 16.0) * rr * jr)
			draw_colored_polygon(blob, Color(0.40, 0.28, 0.14, 0.07))
			# depot plus fonce sur un bord seulement (auréole partielle)
			var a0 := hx * TAU
			draw_arc(rc + Vector2.RIGHT.rotated(a0) * rr * 0.2, rr * 0.9, a0, a0 + PI * 1.1, 14,
				Color(0.28, 0.18, 0.08, 0.13), 2.0)
		# BRULURE de bord : degrade sombre irregulier qui epouse le contour
		for b in 16:
			var bf := float(b) / 16.0
			var ins := 14.0 * bf
			var jj := (absf(fmod(sin(float(b) * 4.7) * 4e4, 1.0)) - 0.5) * 6.0
			draw_rect(Rect2(Vector2(ins + jj, ins), s - Vector2(ins * 2.0 + jj, ins * 2.0)),
				Color(0.08, 0.05, 0.03, 0.16 * (1.0 - bf)), false, 2.0)
		# ferrures de coin riveteees, plus grosses
		var iron := Color(0.15, 0.16, 0.18)
		for cx: float in [0.0, s.x]:
			for cy: float in [0.0, s.y]:
				var dx := 1.0 if cx == 0.0 else -1.0
				var dy := 1.0 if cy == 0.0 else -1.0
				var brk := PackedVector2Array([
					Vector2(cx, cy), Vector2(cx + dx * 34, cy), Vector2(cx + dx * 34, cy + dy * 10),
					Vector2(cx + dx * 10, cy + dy * 10), Vector2(cx + dx * 10, cy + dy * 34), Vector2(cx, cy + dy * 34), Vector2(cx, cy)])
				draw_colored_polygon(brk, iron)
				draw_polyline(brk, INK, 1.5)
				for rv: Vector2 in [Vector2(6, 6), Vector2(26, 6), Vector2(6, 26)]:
					draw_circle(Vector2(cx + dx * rv.x, cy + dy * rv.y), 2.2, iron.lightened(0.45))
					draw_circle(Vector2(cx + dx * rv.x, cy + dy * rv.y), 2.2, INK, false, 0.8)
		# sangles de cuir verticales aux 1/3
		for sx: float in [s.x * 0.32, s.x * 0.68]:
			draw_rect(Rect2(Vector2(sx - 5, -4), Vector2(10, 6)), Color(0.20, 0.13, 0.08))
			draw_rect(Rect2(Vector2(sx - 5, s.y - 2), Vector2(10, 6)), Color(0.20, 0.13, 0.08))
		var ink := INK
		var ink_dim := INK_DIM
		var threat := Color(0.46, 0.12, 0.08)
		var f := ThemeDB.fallback_font
		# --- plaque de titre bordeaux ---
		_plaque(Rect2(14, 12, s.x - 28, 24), BURG)
		draw_string(f, Vector2(0, 30), "TABLE  DE  GUERRE", HORIZONTAL_ALIGNMENT_CENTER, s.x, 13, Color(0.86, 0.78, 0.62))
		_chain(48, 14, s.x - 14)
		draw_string(f, Vector2(16, 68), "Defends le Roi.", HORIZONTAL_ALIGNMENT_LEFT, s.x - 32, 11, ink_dim)
		draw_string(f, Vector2(16, 86), "Vague  %d / 20" % maxi(1, GameState.wave), HORIZONTAL_ALIGNMENT_LEFT, s.x - 32, 12, threat)
		# le panneau _wave_panel (PROCHAIN ASSAUT + chip a accent bleu) se pose entre y~104 et y~150
		_chain(168, 14, s.x - 14)

		# --- meter de sante du roi : ruban ferme aux deux bouts ---
		var my := 210.0
		draw_string(f, Vector2(16, my - 8), "SANTE DU ROI", HORIZONTAL_ALIGNMENT_LEFT, s.x - 32, 10, ink_dim)
		var mr := Rect2(24, my, s.x - 66, 13)
		draw_rect(mr, Color(0.11, 0.09, 0.06))
		var kf := clampf(float(GameState.king_hp) / float(maxi(1, GameState.king_max)), 0.0, 1.0)
		var kcol := Color(0.60, 0.15, 0.12) if kf > 0.35 else Color(0.82, 0.32, 0.12)
		draw_rect(Rect2(mr.position, Vector2(mr.size.x * kf, mr.size.y)), kcol)
		draw_rect(mr, INK, false, 1.8)
		# fanions : pointe vers l'exterieur a gauche, queue d'aronde a droite
		draw_colored_polygon(PackedVector2Array([
			Vector2(mr.position.x, mr.position.y - 2), Vector2(mr.position.x - 7, mr.position.y + 6.5),
			Vector2(mr.position.x, mr.position.y + 15)]), Color(0.40, 0.09, 0.08))
		draw_colored_polygon(PackedVector2Array([
			Vector2(mr.end.x, mr.position.y - 2), Vector2(mr.end.x + 7, mr.position.y - 2),
			Vector2(mr.end.x + 3, mr.position.y + 6.5), Vector2(mr.end.x + 7, mr.position.y + 15),
			Vector2(mr.end.x, mr.position.y + 15)]), Color(0.40, 0.09, 0.08))
		draw_string(f, Vector2(16, my + 28), "%d / %d PV" % [GameState.king_hp, GameState.king_max],
			HORIZONTAL_ALIGNMENT_LEFT, s.x - 32, 11, ink)

		# --- plan tactique du val (carte a l'encre sur le vellum) ---
		draw_string(f, Vector2(16, my + 52), "LE VAL DE LA HERSE", HORIZONTAL_ALIGNMENT_LEFT, s.x - 32, 10, ink_dim)
		var map := Rect2(16, my + 60, s.x - 32, 150)
		draw_colored_polygon(PackedVector2Array([map.position, Vector2(map.end.x, map.position.y), map.end, Vector2(map.position.x, map.end.y)]),
			Color(0.58, 0.50, 0.36, 0.55))
		draw_rect(map.grow(2), INK, false, 2.0)
		draw_rect(map, Color(0.30, 0.22, 0.12, 0.5), false, 1.0)
		var arena = get_node_or_null("/root/Main/World/Arena")
		if arena and arena.has_method("enemy_path"):
			var bs: Vector2 = arena.board_size()
			var to_map := func(p: Vector2) -> Vector2:
				return map.position + Vector2(p.x / bs.x * map.size.x, p.y / bs.y * map.size.y)
			# teintes de zones : mines / champs / casernes
			var zt := [
				[Rect2(0, 64, 3 * 64, 8 * 64), Color(0.34, 0.30, 0.20, 0.35)],
				[Rect2(16 * 64, 64, 3 * 64, 8 * 64), Color(0.40, 0.38, 0.16, 0.32)],
				[Rect2(64, 10 * 64, 17 * 64, 4 * 64), Color(0.32, 0.20, 0.12, 0.3)]]
			for zz in zt:
				var zr: Rect2 = zz[0]
				var a0: Vector2 = to_map.call(zr.position)
				var a1: Vector2 = to_map.call(zr.end)
				draw_rect(Rect2(a0, a1 - a0), zz[1])
			# chemin ennemi : trace epais a l'encre
			var pts: PackedVector2Array = arena.enemy_path()
			var mp := PackedVector2Array()
			for p in pts:
				mp.append(to_map.call(p))
			if mp.size() >= 2:
				draw_polyline(mp, Color(0.16, 0.11, 0.06, 0.9), 3.0)
				draw_polyline(mp, Color(0.55, 0.16, 0.10, 0.5), 1.5)
			# tours posees
			for c in arena.occupied:
				var wp: Vector2 = to_map.call(Vector2((c.x + 0.5) * 64.0, (c.y + 0.5) * 64.0))
				draw_circle(wp, 2.4, Color(0.20, 0.15, 0.09))
			# entree (fente) + trone (couronne)
			if mp.size() >= 2:
				var e0: Vector2 = mp[0]
				draw_line(e0 + Vector2(-4, -4), e0 + Vector2(-4, 4), Color(0.20, 0.45, 0.42), 2.5)
				var t0: Vector2 = mp[mp.size() - 1]
				draw_colored_polygon(PackedVector2Array([
					t0 + Vector2(-5, 3), t0 + Vector2(5, 3), t0 + Vector2(4, -3),
					t0 + Vector2(2, 1), t0 + Vector2(0, -4), t0 + Vector2(-2, 1), t0 + Vector2(-4, -3)]),
					Color(0.72, 0.55, 0.20))
		else:
			draw_string(f, map.position + Vector2(8, 20), "(plan indisponible)", HORIZONTAL_ALIGNMENT_LEFT, map.size.x, 10, ink_dim)

		# --- chronique : jalons de vagues franchies ---
		var cy0 := map.end.y + 22.0
		draw_string(f, Vector2(16, cy0 - 8), "CHRONIQUE  ·  vague %d / 20" % maxi(1, GameState.wave), HORIZONTAL_ALIGNMENT_LEFT, s.x - 32, 10, ink_dim)
		for w in 20:
			var wx := 20.0 + (w % 10) * ((s.x - 44.0) / 10.0)
			var wy := cy0 + 6.0 + float(floori(w / 10.0)) * 14.0
			var done := w < maxi(0, GameState.wave - 1)
			if done:
				draw_circle(Vector2(wx, wy), 3.5, Color(0.55, 0.16, 0.10))
			else:
				draw_arc(Vector2(wx, wy), 3.5, 0, TAU, 10, ink_dim, 1.2)

		# --- decret ---
		var dl := ["Par ordre du Roi : que nul", "monstre n'atteigne le trone."]
		for i in dl.size():
			draw_string(f, Vector2(16, cy0 + 44 + i * 14), dl[i], HORIZONTAL_ALIGNMENT_LEFT, s.x - 32, 10, ink_dim)

		# --- renforts acquis : liste sur le bas de la page ---
		var ry0 := cy0 + 86.0
		_chain(ry0 - 12.0, 14, s.x - 14)
		draw_string(f, Vector2(16, ry0 + 4.0), "RENFORTS DU ROI", HORIZONTAL_ALIGNMENT_LEFT, s.x - 32, 10, ink_dim)
		var acquired: Array = []
		for rid in Meta.relics:
			if not String(rid).begins_with("spec:"):
				acquired.append(rid)
		if acquired.is_empty():
			draw_string(f, Vector2(16, ry0 + 24.0), "aucun pour l'instant", HORIZONTAL_ALIGNMENT_LEFT, s.x - 32, 9, ink_dim)
		else:
			for i in mini(acquired.size(), 8):
				var ly := ry0 + 18.0 + i * 17.0
				draw_colored_polygon(PackedVector2Array([
					Vector2(20, ly), Vector2(26, ly - 5), Vector2(32, ly), Vector2(26, ly + 5)]), Color(0.72, 0.55, 0.20))
				draw_string(f, Vector2(40, ly + 4.0), Meta.relic_label(acquired[i]), HORIZONTAL_ALIGNMENT_LEFT, s.x - 52, 10, ink)

		# --- blason : ecu + epees croisees, au-dessus du sceau ---
		var bc := Vector2(s.x * 0.5, s.y - 78.0)
		draw_colored_polygon(PackedVector2Array([
			bc + Vector2(-16, -18), bc + Vector2(16, -18), bc + Vector2(16, 6),
			bc + Vector2(0, 22), bc + Vector2(-16, 6)]), Color(0.32, 0.24, 0.14))
		draw_polyline(PackedVector2Array([
			bc + Vector2(-16, -18), bc + Vector2(16, -18), bc + Vector2(16, 6),
			bc + Vector2(0, 22), bc + Vector2(-16, 6), bc + Vector2(-16, -18)]), Color(0.14, 0.10, 0.05), 1.5)
		for sgn: float in [-1.0, 1.0]:
			draw_line(bc + Vector2(sgn * -13, 14), bc + Vector2(sgn * 13, -12), Color(0.55, 0.44, 0.26), 2.0)
			draw_line(bc + Vector2(sgn * 9, 12), bc + Vector2(sgn * 15, 12), Color(0.55, 0.44, 0.26), 2.0)
		draw_circle(bc + Vector2(0, -4), 3.0, Color(0.62, 0.50, 0.24))

		# sceau de cire
		var sc := Vector2(s.x - 26, s.y - 26)
		draw_circle(sc, 15.0, Color(0.55, 0.13, 0.12))
		draw_circle(sc, 15.0, Color(0.32, 0.06, 0.06), false, 1.5)
		draw_circle(sc, 9.0, Color(0.62, 0.16, 0.14))
		draw_string(f, sc - Vector2(4, -4), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.30, 0.05, 0.05))


## Crete du titre de l'ecran de renfort : plaque cramoisie + crane aile grave.
class _RecapCrest extends Control:
	func _draw() -> void:
		var s := size
		var ink := Color(0.09, 0.07, 0.05)
		# plaque
		var pl := Rect2(40, 14, s.x - 80, s.y - 20)
		draw_rect(pl, Color(0.30, 0.09, 0.10))
		draw_rect(Rect2(pl.position, Vector2(pl.size.x, 3)), Color(0.42, 0.14, 0.14))
		draw_rect(pl.grow(3), ink, false, 2.5)
		draw_rect(pl.grow(6), Color(0.35, 0.28, 0.16, 0.6), false, 1.0)
		# filigranes aux bouts
		for sgn: float in [-1.0, 1.0]:
			var cx := s.x * 0.5 + sgn * (s.x * 0.5 - 24.0)
			draw_line(Vector2(cx, s.y * 0.5 - 12), Vector2(cx - sgn * 16, s.y * 0.5), ink, 3.0)
			draw_line(Vector2(cx, s.y * 0.5 + 12), Vector2(cx - sgn * 16, s.y * 0.5), ink, 3.0)
		# crane aile : monte sur un petit ecusson qui rejoint la plaque
		var cc := Vector2(s.x * 0.5, 9.0)
		draw_colored_polygon(PackedVector2Array([
			cc + Vector2(-9, 2), cc + Vector2(9, 2), cc + Vector2(6, 10), cc + Vector2(-6, 10)]), Color(0.30, 0.09, 0.10))
		draw_line(cc + Vector2(0, 6), cc + Vector2(0, 14), ink, 2.0)
		draw_circle(cc, 7.0, Color(0.80, 0.76, 0.66))
		draw_circle(cc + Vector2(-3, 1), 1.6, ink)
		draw_circle(cc + Vector2(3, 1), 1.6, ink)
		for wsn: float in [-1.0, 1.0]:
			for k in 3:
				draw_line(cc + Vector2(wsn * 7, 0), cc + Vector2(wsn * (16 + k * 7), -3 + k * 3), Color(0.62, 0.55, 0.40), 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(0, s.y * 0.5 + 6.0), "RENFORT DE FIN DE VAGUE",
			HORIZONTAL_ALIGNMENT_CENTER, s.x, 16, Color(0.90, 0.82, 0.62))


## Carte de renfort ornee (cadre encre + coins bronze + icone losange + textes).
class _BoonCard extends Button:
	var title_txt := ""
	var desc_txt := ""
	var id_txt := ""
	var featured := false
	var rare := false
	var chosen := false
	var _hov := false

	func _init(t: String, d: String, feat: bool) -> void:
		title_txt = t
		desc_txt = d
		featured = feat
		custom_minimum_size = Vector2(198, 250)
		focus_mode = Control.FOCUS_NONE
		flat = true
		mouse_entered.connect(func(): _hov = true; queue_redraw())
		mouse_exited.connect(func(): _hov = false; queue_redraw())
		set_process(true)

	func _process(_dt: float) -> void:
		if featured or _hov or chosen:
			queue_redraw()

	func _kind() -> String:
		if id_txt.begins_with("dmg"): return "sword"
		if id_txt.begins_with("rng"): return "arrow"
		if id_txt == "splash": return "burst"
		if id_txt in ["frost", "freeze", "slow_vuln"]: return "frost"
		if id_txt in ["fighter_hp", "fighter_regen", "king"]: return "shield"
		if id_txt in ["peon", "interest", "refund", "cost_tower"]: return "coin"
		return "gear"

	func _glyph(c: Vector2, kind: String, col: Color) -> void:
		match kind:
			"sword":
				draw_line(c + Vector2(-6, 7), c + Vector2(6, -7), col, 2.4)
				draw_line(c + Vector2(-7, 3), c + Vector2(-2, 8), col, 2.4)
				draw_line(c + Vector2(3, -9), c + Vector2(8, -4), col, 2.0)
			"arrow":
				draw_line(c + Vector2(-8, 8), c + Vector2(8, -8), col, 2.2)
				draw_polyline(PackedVector2Array([c + Vector2(2, -8), c + Vector2(8, -8), c + Vector2(8, -2)]), col, 2.2)
			"burst":
				for a in 8:
					var d := Vector2.RIGHT.rotated(a * TAU / 8.0)
					draw_line(c + d * 3.0, c + d * 9.0, col, 2.0)
			"frost":
				for a in 3:
					var d := Vector2.RIGHT.rotated(a * PI / 3.0)
					draw_line(c - d * 9.0, c + d * 9.0, col, 2.0)
					for sgnb: float in [-1.0, 1.0]:
						var tip := c + d * (9.0 * sgnb)
						draw_line(tip, tip - d * (4.0 * sgnb) + d.orthogonal() * 3.0, col, 1.5)
						draw_line(tip, tip - d * (4.0 * sgnb) - d.orthogonal() * 3.0, col, 1.5)
			"shield":
				draw_polyline(PackedVector2Array([c + Vector2(-7, -7), c + Vector2(7, -7), c + Vector2(7, 2),
					c + Vector2(0, 9), c + Vector2(-7, 2), c + Vector2(-7, -7)]), col, 2.2)
			"coin":
				draw_arc(c, 8.0, 0, TAU, 24, col, 2.2)
				draw_arc(c, 4.5, 0, TAU, 16, Color(col.r, col.g, col.b, 0.7), 1.6)
				for a in 4:
					var d := Vector2.RIGHT.rotated(a * TAU / 4.0 + PI / 4.0)
					draw_line(c + d * 8.0, c + d * 10.5, col, 1.6)
			_:
				draw_arc(c, 7.0, 0, TAU, 18, col, 2.0)
				for a in 6:
					var d := Vector2.RIGHT.rotated(a * TAU / 6.0)
					draw_line(c + d * 6.0, c + d * 9.5, col, 2.0)

	func _draw() -> void:
		var s := size
		var ink := Color(0.08, 0.065, 0.05)
		var vell := Color(0.135, 0.118, 0.10)
		var gold := Color(0.82, 0.64, 0.30)
		var hot := featured or _hov or chosen
		var accent := gold if hot else Color(0.28, 0.24, 0.18)
		# lueur de selection : halo chaud rayonnant vers l'exterieur (jamais un liseré net)
		if hot:
			var pulse := 0.6 + 0.4 * sin(float(Time.get_ticks_msec()) * 0.004)
			for k in 7:
				var kf := float(k) / 7.0
				draw_rect(Rect2(Vector2(-k * 2.5, -k * 2.5), s + Vector2(k * 5.0, k * 5.0)),
					Color(gold.r, gold.g, gold.b, 0.18 * (1.0 - kf) * pulse), false, 2.5)
		# corps vellum + degrade vertical
		draw_rect(Rect2(Vector2.ZERO, s), vell)
		for i in 8:
			var t := float(i) / 8.0
			draw_rect(Rect2(Vector2(0, s.y * t), Vector2(s.x, s.y / 8.0 + 1.0)),
				Color(0, 0, 0, 0.05 + t * 0.12))
		# bandeau de tete : pierre sombre, liseré or, mention rarete
		var band_h := 44.0
		draw_rect(Rect2(Vector2.ZERO, Vector2(s.x, band_h)), Color(0.16, 0.10, 0.09) if not rare else Color(0.12, 0.11, 0.16))
		draw_line(Vector2(0, band_h), Vector2(s.x, band_h), gold, 1.5)
		draw_string(ThemeDB.fallback_font, Vector2(0, 15), "RENFORT" if not rare else "RENFORT RARE",
			HORIZONTAL_ALIGNMENT_CENTER, s.x, 9, Color(gold.r, gold.g, gold.b, 0.8))
		# cadres
		draw_rect(Rect2(Vector2.ZERO, s), ink, false, 2.5)
		draw_rect(Rect2(Vector2(2, 2), s - Vector2(4, 4)), accent, false, 1.5 if hot else 1.0)
		# equerres bronze aux 4 coins
		var brz := Color(0.40, 0.31, 0.17)
		for cx: float in [0.0, s.x]:
			for cy: float in [0.0, s.y]:
				var dx := 1.0 if cx == 0.0 else -1.0
				var dy := 1.0 if cy == 0.0 else -1.0
				var br := PackedVector2Array([Vector2(cx, cy), Vector2(cx + dx * 22, cy),
					Vector2(cx + dx * 22, cy + dy * 5), Vector2(cx + dx * 5, cy + dy * 5),
					Vector2(cx + dx * 5, cy + dy * 22), Vector2(cx, cy + dy * 22), Vector2(cx, cy)])
				draw_colored_polygon(br, brz)
				draw_polyline(br, ink, 1.2)
		# medaillon losange + glyphe propre a la categorie
		var ic := Vector2(s.x * 0.5, band_h + 26.0)
		var dia := PackedVector2Array([ic + Vector2(0, -24), ic + Vector2(24, 0), ic + Vector2(0, 24), ic + Vector2(-24, 0)])
		draw_colored_polygon(dia, Color(0.18, 0.11, 0.09))
		draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), gold, 2.0)
		_glyph(ic, _kind(), Color(0.94, 0.80, 0.52))
		# titre + filet
		var f := ThemeDB.fallback_font
		var ty := band_h + 66.0
		draw_string(f, Vector2(6, ty), title_txt, HORIZONTAL_ALIGNMENT_CENTER, s.x - 12, 15, Color(0.92, 0.80, 0.52))
		draw_line(Vector2(s.x * 0.22, ty + 8.0), Vector2(s.x * 0.78, ty + 8.0), Color(gold.r, gold.g, gold.b, 0.5), 1.0)
		# palier de niveau
		var ly := ty + 30.0
		draw_string(f, Vector2(0, ly), "N I V E A U", HORIZONTAL_ALIGNMENT_CENTER, s.x, 9, Color(0.55, 0.52, 0.44))
		draw_string(f, Vector2(s.x * 0.5 - 30, ly + 20.0), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.72, 0.70, 0.62))
		draw_colored_polygon(PackedVector2Array([
			Vector2(s.x * 0.5 - 8, ly + 9.0), Vector2(s.x * 0.5 + 6, ly + 15.0), Vector2(s.x * 0.5 - 8, ly + 21.0)]), gold)
		draw_string(f, Vector2(s.x * 0.5 + 16, ly + 20.0), "1", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.92, 0.82, 0.55))
		# description : bloc centre dans le bas de la carte
		draw_multiline_string(f, Vector2(14, ly + 48.0), desc_txt, HORIZONTAL_ALIGNMENT_CENTER, s.x - 28, 11, 4, Color(0.76, 0.72, 0.62))
		# fleuron de pied
		var fy := s.y - 16.0
		draw_line(Vector2(s.x * 0.3, fy), Vector2(s.x * 0.7, fy), Color(gold.r, gold.g, gold.b, 0.4), 1.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(s.x * 0.5, fy - 4.0), Vector2(s.x * 0.5 + 4.0, fy), Vector2(s.x * 0.5, fy + 4.0), Vector2(s.x * 0.5 - 4.0, fy)]),
			Color(gold.r, gold.g, gold.b, 0.55))
		if chosen:
			draw_string(f, Vector2(0, s.y * 0.5), "✓ ACQUIS", HORIZONTAL_ALIGNMENT_CENTER, s.x, 13, gold)
