class_name Arena
extends Node2D
## Le plateau. Arène de bataille centrale close par des murs (portes gauche =
## entrée, droite = roi). Rail de MINE a gauche (peons -> minerai, gere les tours),
## rail de FERME a droite (fermiers -> nourriture, gere les troupes), bande de
## GARNISON sous l'arene (casernes -> recrutement/envoi de monstres).
## Tours = murs infranchissables -> pathfinding A* pour contourner.

const CELL := 64.0
const COLS := 13
const ROWS := 15

## --- ARENE DE BATAILLE v11 : flux VERTICAL, ennemis haut -> bas ---
## Grille jouable 9 large x 11 haut.  Portes centrees dans les murs HAUT et BAS.
## L'economie (mines / champs / garnison) est sortie -> fenetre "FERME" separee.
const BATTLE_COL_MIN := 1          ## mur GAUCHE
const BATTLE_COL_MAX := 11         ## mur DROIT
const BATTLE_ROW_MIN := 1          ## mur HAUT (porte d'entree, faille)
const BATTLE_ROW_MAX := 13         ## mur BAS (porte du roi)
const BUILD_COL_MIN := 2
const BUILD_COL_MAX := 10          ## 9 colonnes jouables
const BUILD_ROW_MIN := 2
const BUILD_ROW_MAX := 12          ## 11 rangees jouables
const GATE_COL := 6               ## colonne de la porte (haut ET bas)

## compat : d'anciens appels utilisent WALK_ROW_MIN/MAX (etendue verticale de l'arene)
const WALK_ROW_MIN := BUILD_ROW_MIN
const WALK_ROW_MAX := BUILD_ROW_MAX
const GATE_ROWS := [GATE_COL]      ## compat (certains appels iterent dessus)

## --- economie : DEPLACEE dans la fenetre FERME.  Constantes gardees a 0 pour
## que l'ancien code (checks in_mine/in_ferme/...) compile et renvoie toujours faux. ---
const ECON_ROW_MIN := -9
const ECON_ROW_MAX := -9
const MINE_COL_MIN := -9
const MINE_COL_MAX := -9
const FERME_COL_MIN := -9
const FERME_COL_MAX := -9
const GARRISON_ROW_MIN := -9
const GARRISON_ROW_MAX := -9
const GARRISON_COL_MIN := -9
const GARRISON_COL_MAX := -9
const FARM_ROW_MIN := -9
const FARM_ROW_MAX := -9

var spawn_cell := Vector2i(GATE_COL, BATTLE_ROW_MIN)
var king_cell := Vector2i(GATE_COL, BATTLE_ROW_MAX)

## Ancres D'ART : la faille est logee dans la porte HAUTE, le trone dans la porte BASSE.
const RIFT_ANCHOR := Vector2(GATE_COL * CELL + CELL * 0.5, BATTLE_ROW_MIN * CELL + CELL * 0.5 + 8.0)
const THRONE_ANCHOR := Vector2(GATE_COL * CELL + CELL * 0.5, BATTLE_ROW_MAX * CELL + CELL * 0.5 - 8.0)

var occupied: Dictionary = {}
var hover_cell := Vector2i(-1, -1)
var pending_tool := ""

var _astar := AStarGrid2D.new()
var _t := 0.0
var _lights: Node2D = null
var _crown: Node2D = null
var _fx: Node2D = null
var _static_dirty := true

var _trail_pts: PackedVector2Array = PackedVector2Array()

# =========================================================================
#  DIRECTION ARTISTIQUE  —  "SALLE DU DONJON" (reference : Tails of Iron)
#  Pierre taillee peinte, contours a l'encre, palette DESATUREE gris-vert /
#  brun / ocre, accent CRAMOISI (bannieres, heraldique).  Peu d'effets : une
#  cle chaude venue d'en haut, des torches MURALES contenues, forte vignette.
#  Lisibilite d'abord : le decor sert le jeu, il ne l'ecrase pas.
# =========================================================================

# -- tension de temperature : PIERRE froide gris-vert  vs  LUMIERE chaude ambre --
# -- pierre des murs : gris-vert DESATURE et froid (#3C4642 / #4A544E) --
const _STONE_DEEP  := Color(0.040, 0.045, 0.042)   ## noir de perimetre
const _STONE_LO    := Color(0.156, 0.180, 0.168)
const _STONE_MID   := Color(0.235, 0.275, 0.259)   ## #3C4642
const _STONE_HI    := Color(0.322, 0.360, 0.338)
const _INK         := Color(0.078, 0.070, 0.055)   ## encre brun-noir
const _MORTAR      := Color(0.052, 0.058, 0.054)
const _MOSS        := Color(0.22, 0.29, 0.15, 0.5)

# -- MURS D'ENCEINTE : UN SEUL kit de pierre bleu-gris, 3 angles de vue (spec v7) --
# la pierre est FROIDE (B > R partout) ; la chaleur est AJOUTEE par-dessus (torches + bounce).
# UN SEUL calcaire gris-brun chaud, lumiere en haut-a-gauche.  R >= G >= B PARTOUT
# (sinon la pierre hors torche vire au bleu et lit comme un 2e batiment).  Le seul
# accent froid autorise = _K_SKY_RIM, 1px sur les aretes hautes / nord uniquement.
# cale sur la ref "tripleAAA" : pierre grise CLAIRE et propre, chaleur = torches only.
const _K_CAP_LIT  := Color(0.640, 0.618, 0.575)   ## dessus des merlons / aretes eclairees a ciel ouvert
const _K_CAP_CORE := Color(0.492, 0.474, 0.442)   ## dalle du chemin de ronde (la grande surface)
const _K_FACE_HI  := Color(0.470, 0.440, 0.400)   ## haut de chaque assise d'une face verticale
const _K_FACE_MID := Color(0.360, 0.334, 0.300)   ## face principale d'un bloc (fill de base)
const _K_FACE_LO  := Color(0.225, 0.208, 0.188)   ## pied de bloc, AO dans le joint de lit
const _K_MORTAR   := Color(0.140, 0.130, 0.120)   ## tous les joints
const _K_QUOIN    := Color(0.530, 0.500, 0.452)   ## pierre de taille : quoins, jambages, voussoirs
const _K_MERLON_SH:= Color(0.115, 0.107, 0.100)   ## creneaux, meurtrieres, fond d'alcove, sous-face de surplomb
const _K_SKY_RIM  := Color(0.460, 0.520, 0.575, 0.42) ## liseré 1px sur les aretes hautes / nord SEULEMENT
const _K_WARM     := Color(1.000, 0.600, 0.270)   ## spill de torche (additif + cible de lerp)
const _K_AMBWARM  := Color(0.550, 0.380, 0.240)   ## plancher chaud ambiant : lerp 0.06 sur TOUTE face -> jamais gris neutre
const _K_BOUNCE   := Color(0.470, 0.330, 0.190)   ## rebond chaud du sol, bas de chaque face (alpha ~0.2)
const _K_INK      := Color(0.048, 0.046, 0.044)   ## trait de silhouette dessine main
const _K_WARM_BLK := Color(0.050, 0.040, 0.035)   ## noir des ombres portees (tiede)
# alias retro-compat (anciens appels)
const _WALL_CAP     := _K_CAP_CORE
const _WALL_CAP_HI  := _K_CAP_LIT
const _WALL_FACE_HI := _K_FACE_HI
const _WALL_FACE    := _K_FACE_MID
const _WALL_FACE_LO := _K_FACE_LO
const _WALL_MORTAR  := _K_MORTAR
const _WALL_QUOIN   := _K_QUOIN
const _WALL_MERLON_LO := _K_MERLON_SH
const _RIM_SKY      := _K_SKY_RIM
const _SPILL_WARM   := _K_WARM
const _COURSE_H   := 18.0                          ## hauteur d'assise, IDENTIQUE partout
const _WALL_H     := 96.0                          ## face visible du mur haut (spec §2.1)

# -- sol de l'arene : brun-ocre froid a l'ombre, chaud sous la lumiere --
const _FLOOR_LIT   := Color(0.430, 0.335, 0.205)
const _FLOOR_SHAD  := Color(0.150, 0.150, 0.135)   ## a l'ombre : neutre froid, lisible
const _HAY         := Color(0.74, 0.58, 0.30)
const _HAY_DK      := Color(0.44, 0.35, 0.18)

const _AO          := Color(0, 0, 0, 0.5)
const _EDGE_HI     := Color(1.0, 0.93, 0.78, 0.16)  ## ciseau : arete haute
const _EDGE_LO     := Color(0, 0, 0, 0.6)

# -- ambiance --
const _GROUND_TINT := Color(0.078, 0.083, 0.070)
const _KEY_WARM    := Color(1.0, 0.80, 0.46)
const _VIGN        := Color(0.020, 0.016, 0.012)

# -- feu (torches murales) --
const _FIRE_CORE   := Color(1.0, 0.957, 0.847)      ## coeur quasi blanc (#FFF4D8)
const _FIRE_MID    := Color(0.98, 0.58, 0.22)
const _FIRE_LOW    := Color(0.70, 0.24, 0.09)
const _IRON        := Color(0.09, 0.085, 0.09)

# -- faille (gauche) : vert-cyan malsain, contenu --
const _RIFT_CORE   := Color(0.62, 0.92, 0.80)
const _RIFT_OUTER  := Color(0.09, 0.17, 0.16)
const _RIFT_CRACK  := Color(0.38, 0.74, 0.62)

# -- trone (droite) --
const _GOLD        := Color(0.82, 0.64, 0.30)
const _GOLD_LT     := Color(0.98, 0.86, 0.58)
const _BANNER      := Color(0.478, 0.082, 0.094)    ## cramoisi sang (#7A1518)
const _BANNER_FOLD := Color(0.290, 0.047, 0.055)    ## pli d'ombre (#4A0C0E)
const _BANNER_LT   := Color(0.60, 0.14, 0.13)

# -- zones d'economie --
# zones d'eco : RE-CALEES dans l'harmonie du hall (jamais plus claires que le trone)
const _MINE_ROCK   := Color(0.132, 0.124, 0.114)
const _MINE_ORE    := Color(0.74, 0.56, 0.26)
const _MINE_TIMBER := Color(0.20, 0.145, 0.092)
const _MINE_RAIL   := Color(0.27, 0.25, 0.22)
const _FIELD       := Color(0.205, 0.175, 0.110)
const _FIELD_HI    := Color(0.320, 0.270, 0.160)
const _GARR_EARTH  := Color(0.118, 0.099, 0.076)
const _GARR_EARTH2 := Color(0.090, 0.075, 0.058)
const _PLOT        := Color(0.52, 0.45, 0.30, 0.5)


func _ready() -> void:
	y_sort_enabled = true
	# region = l'arene jouable + la case-porte haute et basse (pour que le chemin
	# spawn(GATE_COL, ROW_MIN) -> king(GATE_COL, ROW_MAX) existe).
	_astar.region = Rect2i(BUILD_COL_MIN, BATTLE_ROW_MIN,
		BUILD_COL_MAX - BUILD_COL_MIN + 1, BATTLE_ROW_MAX - BATTLE_ROW_MIN + 1)
	_astar.cell_size = Vector2(CELL, CELL)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()
	# la rangee du mur haut / bas est solide SAUF la case-porte
	for c in range(BUILD_COL_MIN, BUILD_COL_MAX + 1):
		if c != GATE_COL:
			_astar.set_point_solid(Vector2i(c, BATTLE_ROW_MIN), true)
			_astar.set_point_solid(Vector2i(c, BATTLE_ROW_MAX), true)
	_refresh_trail()
	# calque de lumiere ADDITIF : vraies nappes de glow (torches / faille / trone)
	_lights = _LightLayer.new()
	_lights.arena = self
	_lights.z_index = 6
	var lm := CanvasItemMaterial.new()
	lm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_lights.material = lm
	add_child(_lights)
	# calque "couronne" : redessine le dessus des murs PAR-DESSUS la lumiere ->
	# les torches sont fixees a la face interne, leur lueur est coupee par le mur.
	_crown = _CrownLayer.new()
	_crown.arena = self
	_crown.z_index = 8
	add_child(_crown)
	# calque FX : elements animes (faille, brume, chevrons, survol, bannieres) ->
	# le gros dessin statique de l'arene (murs/sol/props) ne se redessine plus qu'a
	# la pose d'une tour ; ce calque-ci suit l'animation.
	_fx = _ArenaFx.new()
	_fx.arena = self
	_fx.z_index = 7
	add_child(_fx)


func board_size() -> Vector2:
	return Vector2(COLS * CELL, ROWS * CELL)


## PEU de sources, FORTES.  Chacune : position, couleur, rayon.
func light_sources() -> Array:
	var xL := BATTLE_COL_MIN * CELL + CELL - 8.0            ## face interne du mur gauche
	var xR := BATTLE_COL_MAX * CELL + 8.0                   ## face interne du mur droit
	var yT := BATTLE_ROW_MIN * CELL + CELL - 8.0            ## face interne du mur haut
	var yB := BATTLE_ROW_MAX * CELL + 8.0                   ## face interne du mur bas
	var r1 := (BUILD_ROW_MIN + 2) * CELL + CELL * 0.5
	var r2 := (BUILD_ROW_MAX - 2) * CELL + CELL * 0.5
	var c1 := (BUILD_COL_MIN + 2) * CELL + CELL * 0.5
	var c2 := (BUILD_COL_MAX - 2) * CELL + CELL * 0.5
	var wc := Color(1.0, 0.60, 0.24)
	var out := [
		# torches des 2 murs lateraux (2 par cote)
		{"p": Vector2(xL, r1), "col": wc, "r": 150.0},
		{"p": Vector2(xL, r2), "col": wc, "r": 150.0},
		{"p": Vector2(xR, r1), "col": wc, "r": 150.0},
		{"p": Vector2(xR, r2), "col": wc, "r": 150.0},
		# torches des murs haut / bas (de part et d'autre de la porte)
		{"p": Vector2(c1, yT), "col": wc, "r": 150.0},
		{"p": Vector2(c2, yT), "col": wc, "r": 150.0},
		{"p": Vector2(c1, yB), "col": wc, "r": 150.0},
		{"p": Vector2(c2, yB), "col": wc, "r": 150.0},
		# trone : la source la plus chaude, focale
		{"p": THRONE_ANCHOR, "col": Color(0.95, 0.74, 0.38), "r": 82.0},
		# faille : froide, contenue
		{"p": RIFT_ANCHOR, "col": Color(0.40, 0.98, 0.74), "r": 96.0},
	]
	return out


## true si la source L n'atteint pas le point p (clip en x -> pas de bave sur MINES/CHAMPS).
func _light_clipped(L: Dictionary, p: Vector2) -> bool:
	return (L.has("xmin") and p.x < L["xmin"]) or (L.has("xmax") and p.x > L["xmax"])


## Eclairement 0..1 : chute nette (knee dur) -> vrai noir entre les sources.
func lit_at(p: Vector2) -> float:
	var best := 0.0
	for L in light_sources():
		if _light_clipped(L, p):
			continue
		var x: float = clampf(1.0 - p.distance_to(L["p"]) / L["r"], 0.0, 1.0)
		best = maxf(best, x * x * (3.0 - 2.0 * x))   ## smoothstep
	return best


## Couleur de la source la plus proche (pour le "spill" chaud sur la geometrie).
func nearest_light_col(p: Vector2) -> Color:
	var bd := 1e9
	var bc := Color(1.0, 0.62, 0.26)
	for L in light_sources():
		if _light_clipped(L, p):
			continue
		var d: float = p.distance_to(L["p"])
		if d < bd:
			bd = d
			bc = L["col"]
	return bc


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * CELL + CELL * 0.5, cell.y * CELL + CELL * 0.5)


func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < COLS and cell.y >= 0 and cell.y < ROWS


func in_battle_build(cell: Vector2i) -> bool:
	return cell.x >= BUILD_COL_MIN and cell.x <= BUILD_COL_MAX \
		and cell.y >= BUILD_ROW_MIN and cell.y <= BUILD_ROW_MAX


## economie sortie dans la fenetre FERME -> ces zones n'existent plus dans l'arene.
func in_mine(_cell: Vector2i) -> bool:
	return false


func in_ferme(_cell: Vector2i) -> bool:
	return false


func in_farm(_cell: Vector2i) -> bool:
	return false


func in_garrison(_cell: Vector2i) -> bool:
	return false


func can_build(id: String, cell: Vector2i) -> bool:
	if not in_bounds(cell) or occupied.has(cell):
		return false
	match Catalog.cat(id):
		"peon":
			return in_mine(cell) and get_tree().get_nodes_in_group("peons").size() < Meta.peon_max
		"fermier":
			return in_ferme(cell) and get_tree().get_nodes_in_group("fermiers").size() < Meta.peon_max
		"fighter":
			return in_battle_build(cell)
		"tower":
			return in_battle_build(cell) and not Catalog.towers_full() and _path_survives(cell)
		"caserne":
			return GameState.mode == GameState.Mode.DUEL and in_garrison(cell)
	return false


func _path_survives(extra_solid: Vector2i) -> bool:
	_astar.set_point_solid(extra_solid, true)
	var path := _astar.get_id_path(spawn_cell, king_cell)
	_astar.set_point_solid(extra_solid, false)
	return path.size() > 0


func place(id: String, cell: Vector2i) -> Node2D:
	var n: Node2D
	var is_tower := false
	match Catalog.cat(id):
		"tower":
			is_tower = true
			var tw := Tower.new()
			tw.configure(id)
			tw.invested = Catalog.cost(id)
			n = tw
			_astar.set_point_solid(cell, true)
		"fighter":
			var fg := Fighter.new()
			fg.configure(id)
			fg.invested = Catalog.cost(id)
			n = fg
		"peon":
			n = Peon.new()
		"fermier":
			var fm := Peon.new()
			fm.kind = "fermier"
			n = fm
		"caserne":
			var cs := Caserne.new()
			cs.configure(id)
			cs.invested = Catalog.cost(id)
			n = cs
	var is_caserne := n is Caserne
	n.position = cell_to_world(cell)
	add_child(n)
	occupied[cell] = n
	_static_dirty = true
	n.tree_exited.connect(func() -> void:
		if occupied.get(cell) == n:
			occupied.erase(cell)
			_static_dirty = true
			if is_tower:
				GameState.towers_built = maxi(0, GameState.towers_built - 1)
				_astar.set_point_solid(cell, false)
				_recompute_synergy()
				_refresh_trail()
			if is_caserne:
				_recompute_casernes())
	if is_tower:
		GameState.towers_built += 1
		_recompute_synergy()
		_refresh_trail()
	if is_caserne:
		_recompute_casernes()
	return n


func _recompute_casernes() -> void:
	## reconstruit Versus.unlocked : niveau = nombre de casernes de ce type
	var counts: Dictionary = {}
	for c in occupied:
		var o = occupied[c]
		if o is Caserne:
			counts[o.troop] = int(counts.get(o.troop, 0)) + 1
	Versus.unlocked.clear()
	for troop_id in counts:
		Versus.unlocked[troop_id] = counts[troop_id]
	Versus.changed.emit()


const _NB4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

func _recompute_synergy() -> void:
	for c in occupied:
		var t = occupied[c]
		if not (t is Tower):
			continue
		var n := 0
		for d in _NB4:
			var o = occupied.get(c + d)
			if o is Tower and o.type_id == t.type_id:
				n += 1
		t.set_synergy(n)


func enemy_path() -> PackedVector2Array:
	var out := PackedVector2Array()
	var ids := _astar.get_id_path(spawn_cell, king_cell)
	if ids.is_empty():
		out.append(cell_to_world(spawn_cell))
		out.append(cell_to_world(king_cell))
		return out
	for id in ids:
		out.append(cell_to_world(id))
	return out


func _process(delta: float) -> void:
	_t += delta
	# le gros dessin statique (murs/sol/props) ne se redessine QUE sur changement
	# d'etat -> les elements animes vivent dans _ArenaFx / _LightLayer.
	if _static_dirty:
		_static_dirty = false
		queue_redraw()
		if is_instance_valid(_crown):
			_crown.queue_redraw()
		if is_instance_valid(_lights):
			_lights.queue_redraw()


func mark_dirty() -> void:
	_static_dirty = true


# =========================================================================
#  RENDU  —  "SALLE DU DONJON"  (reference : Tails of Iron)
#  Pierre taillee peinte + contours encre, palette desaturee, accent cramoisi.
#  Peu d'effets, torches MURALES, forte vignette.  Le decor sert le jeu.
# =========================================================================

## STATIQUE : redessine seulement sur `_static_dirty` (pose / vente / resize).
func _draw() -> void:
	_draw_ground()
	_draw_zones()
	_draw_arena_floor()
	_draw_props()
	_draw_cast_shadows()
	_draw_arena_walls()
	_draw_wall_sconces()
	_draw_road()
	_draw_zone_details()
	_draw_throne()
	_draw_labels()
	_draw_synergy()
	_draw_grain()
	_draw_vignette()


## ANIME (calque _ArenaFx) : poussiere, faille, brume, chevrons de sens, survol, bannieres.
func _draw_fx(ci: CanvasItem) -> void:
	_draw_key_light(ci)
	_draw_rift(ci)
	_draw_haze(ci)
	_draw_place_dots(ci)
	_draw_path_hint(ci)
	_draw_hover(ci)
	_draw_wall_banners(ci)


## Grain de papier / aquarelle : mouchetis deterministe multiplie sur tout le
## plateau -> "peint" plutot que "rendu".
func _draw_grain() -> void:
	# le grain fin est fait par le post-process (shaders/postfx.gdshader).
	# ici : seulement quelques griffures d'encre deliberees dans l'arene.
	var hall := _zone_rect(BUILD_COL_MIN, BUILD_COL_MAX, WALK_ROW_MIN, WALK_ROW_MAX)
	for i in 10:
		var a := hall.position + Vector2(_hash01(i, 2) * hall.size.x, _hash01(i, 9) * hall.size.y)
		var dir := Vector2.RIGHT.rotated(_hash01(i, 5) * TAU)
		draw_line(a, a + dir * (14.0 + _hash01(i, 1) * 30.0), Color(_INK.r, _INK.g, _INK.b, 0.08), 1.0)


func _zone_rect(col_min: int, col_max: int, row_min: int, row_max: int) -> Rect2:
	return Rect2(Vector2(col_min * CELL, row_min * CELL),
		Vector2((col_max - col_min + 1) * CELL, (row_max - row_min + 1) * CELL))


func _hash01(c: int, r: int) -> float:
	var n := sin(float(c) * 12.9898 + float(r) * 78.233) * 43758.5453
	return n - floorf(n)


## Trait d'encre "a la main" : chaque segment subdivise + jitter perpendiculaire
## deterministe, epaisseur qui varie -> ligne vivante, pas un rectangle CSS.
func _ink_path(pts: PackedVector2Array, base_w: float, sd: int, closed := true) -> void:
	var loop := pts
	if closed:
		loop = _closed(pts)
	var wj := 1.0 + (_hash01(sd, 99) - 0.5) * 0.5   ## epaisseur qui varie par forme
	for i in range(loop.size() - 1):
		var a: Vector2 = loop[i]
		var b: Vector2 = loop[i + 1]
		var nrm := (b - a).orthogonal().normalized()
		var sub := 4
		var seg := PackedVector2Array()
		for s in sub + 1:
			# on saute parfois un point -> trait interrompu, "a la main"
			if s > 0 and s < sub and _hash01(sd + i * 13, s * 5) > 0.86:
				if seg.size() >= 2:
					draw_polyline(seg, _INK, (base_w + 0.5) * wj)
				seg = PackedVector2Array()
				continue
			var t := float(s) / float(sub)
			var wob := (_hash01(sd + i * 7, s * 3) - 0.5) * 2.6
			seg.append(a.lerp(b, t) + nrm * wob)
		if seg.size() >= 2:
			draw_polyline(seg, _INK, (base_w + 0.5) * wj)


func _ink_quad(pts: PackedVector2Array, fill: Color, ink_w := 2.0) -> void:
	draw_colored_polygon(pts, fill)
	_ink_path(pts, ink_w, int(pts[0].x) * 3 + int(pts[0].y))


func _ellipse(c: Vector2, rx: float, ry: float, col: Color, sd: int, ci: CanvasItem = null) -> void:
	var pts := PackedVector2Array()
	var n := 30
	for i in n:
		var ang := i * TAU / n
		var j := 1.0 + (_hash01(sd, i) - 0.5) * 0.12
		pts.append(c + Vector2(cos(ang) * rx, sin(ang) * ry) * j)
	(ci if ci != null else self).draw_colored_polygon(pts, col)


## Fond : quasi-noir partout.  Une lueur froide bleutee tombe du bord haut.
func _draw_ground() -> void:
	var bs := board_size()
	# le plateau se fond dans l'obscurite alentour : halo sombre deborde des bords
	for i in range(10, 0, -1):
		var g := float(i) / 10.0
		draw_rect(Rect2(Vector2(-i * 5.0, -i * 5.0), bs + Vector2(i * 10.0, i * 10.0)),
			Color(0.02, 0.017, 0.015, 0.10 * (1.0 - g)))
	draw_rect(Rect2(Vector2.ZERO, bs), _STONE_DEEP)
	# lavis froid depuis le haut (l'ombre du donjon a une temperature)
	for i in 14:
		var f := float(i) / 14.0
		draw_rect(Rect2(Vector2(0, f * bs.y * 0.6), Vector2(bs.x, bs.y * 0.6 / 14.0 + 1.0)),
			Color(0.16, 0.18, 0.20, 0.045 * (1.0 - f)))


## Poussiere qui flotte dans la lumiere (les nappes de glow = calque additif).
func _draw_key_light(ci: CanvasItem) -> void:
	var hall := _zone_rect(BUILD_COL_MIN, BUILD_COL_MAX, WALK_ROW_MIN, WALK_ROW_MAX)
	var c := hall.get_center()
	for i in 14:
		var ph := fposmod(_t * 0.05 + i * 0.31, 1.0)
		var pp := c + Vector2((_hash01(i, 3) - 0.5) * hall.size.x * 0.7, (_hash01(i, 6) - 0.5) * hall.size.y)
		pp.y -= ph * 12.0
		ci.draw_circle(pp, 0.9, Color(_KEY_WARM.r, _KEY_WARM.g, _KEY_WARM.b, (1.0 - ph) * 0.28 * lit_at(pp)))


## Economie (mine / ferme / garnison) DEPLACEE dans la fenetre FERME -> plus rien
## a dessiner ici.  L'arene de bataille est desormais seule dans cette vue.
func _draw_zones() -> void:
	pass


## Sol de l'arene : grandes dalles taillees irregulieres (contour encre) + paille.
func _draw_arena_floor() -> void:
	var hall := _zone_rect(BUILD_COL_MIN, BUILD_COL_MAX, WALK_ROW_MIN, WALK_ROW_MAX)
	draw_rect(hall, _MORTAR)
	for c in range(BUILD_COL_MIN, BUILD_COL_MAX + 1):
		for r in range(WALK_ROW_MIN, WALK_ROW_MAX + 1):
			_slab(c, r)
	# occlusion : le pourtour interieur du hall s'assombrit
	_inset_shadow(hall, 16.0)
	# paille repandue : plus dense sur les bords, evitant le centre du chemin
	for i in 90:
		var hx := _hash01(i * 2 + 3, 11)
		var hy := _hash01(i * 3 + 7, 5)
		var p := hall.position + Vector2(hx * hall.size.x, hy * hall.size.y)
		var edge := minf(minf(p.x - hall.position.x, hall.end.x - p.x),
			minf(p.y - hall.position.y, hall.end.y - p.y)) / 90.0
		if _hash01(i, 4) > clampf(0.25 + edge, 0.25, 0.85):
			continue
		var ang := _hash01(i, 9) * PI
		var ln := 5.0 + _hash01(i, 1) * 7.0
		var col := _HAY if _hash01(i, 2) > 0.4 else _HAY_DK
		draw_line(p, p + Vector2(cos(ang), sin(ang)) * ln, Color(col.r, col.g, col.b, 0.5), 1.5)


func _slab(c: int, r: int) -> void:
	var o := Vector2(c * CELL, r * CELL)
	var ctr := o + Vector2(CELL * 0.5, CELL * 0.5)
	var h := _hash01(c, r)
	var h2 := _hash01(c * 5 + 2, r * 3 + 8)
	var h3 := _hash01(c * 17 + 4, r * 11 + 6)
	var m := 1.6 + h2 * 1.8                      ## joint fin : sol de dallage continu, pas des blocs flottants
	var jx := (h - 0.5) * 3.0
	var jy := (h2 - 0.5) * 3.0
	var pts := PackedVector2Array([
		o + Vector2(m + jx, m + jy),
		o + Vector2(CELL - m + jy, m - jx * 0.5),
		o + Vector2(CELL - m - jx, CELL - m + jy),
		o + Vector2(m + jy * 0.5, CELL - m - jx)])
	var lit := lit_at(ctr)
	# ombre du joint : legere, la dalle repose dans le mortier
	draw_colored_polygon(_offset(pts, Vector2(1.0, 1.5)), Color(0, 0, 0, 0.24))
	if h2 > 0.985:                               ## dalle arrachee (RARE) -> creux de mortier, jamais noir pur
		draw_colored_polygon(pts, _FLOOR_SHAD.darkened(0.35))
		_ink_path(pts, 1.4, c * 7 + r)
		for k in 3:
			draw_circle(ctr + Vector2((_hash01(c + k, r) - 0.5) * 26.0, (_hash01(c, r + k) - 0.5) * 26.0), 1.5 + _hash01(k, c) * 2.0, _STONE_LO.darkened(0.2))
		return
	# valeur : composition + variation de matiere dalle-a-dalle, MAIS plage bornee
	var fill := _FLOOR_SHAD.lerp(_FLOOR_LIT, clampf(lit * 1.3, 0.12, 1.0))
	var arch := _hash01(c * 23 + 9, r * 19 + 4)
	if arch > 0.86:
		fill = fill.lerp(Color(0.42, 0.38, 0.31), 0.28)                             ## dalle usee, polie
	elif arch < 0.16:
		fill = fill.lerp(Color(0.24, 0.20, 0.15), 0.32)                             ## boue seche brune
	elif arch < 0.30:
		fill = fill.lerp(Color(0.25, 0.29, 0.19), 0.22)                             ## envahie de mousse
	fill = fill.lerp(fill.lightened(0.12), h * h).lerp(fill.darkened(0.16), (1.0 - h3) * (1.0 - h3))
	fill = fill.lerp(_FLOOR_SHAD.darkened(0.2), (1.0 - lit) * (1.0 - lit) * 0.35)   ## jamais _STONE_DEEP
	if lit > 0.05:
		fill = fill.lerp(nearest_light_col(ctr), lit * lit * 0.24)
	draw_colored_polygon(pts, fill)
	# vignette de dalle : chaque pierre a son propre lisere sombre a l'interieur du bord
	var vc := pts[0].lerp(pts[2], 0.5)
	for k in range(1, 4):
		var vv := PackedVector2Array()
		for pp2 in pts:
			vv.append(pp2.lerp(vc, k * 0.06))
		draw_polyline(_closed(vv), Color(0, 0, 0, 0.10 * (1.0 - k / 4.0)), 2.0)
	# ink : present partout, plus epais/sombre dans l'ombre
	var iw := 1.6 + (1.0 - lit) * 1.6
	_ink_path(PackedVector2Array([pts[3], pts[0], pts[1]]), iw * 0.7, c * 7 + r, false)
	_ink_path(PackedVector2Array([pts[1], pts[2], pts[3]]), iw + 1.2, c * 7 + r + 99, false)
	draw_line(pts[3], pts[0], Color(_EDGE_HI.r, _EDGE_HI.g, _EDGE_HI.b, _EDGE_HI.a * (0.3 + lit)), 2.0)
	draw_line(pts[0], pts[1], Color(_EDGE_HI.r, _EDGE_HI.g, _EDGE_HI.b, _EDGE_HI.a * (0.2 + lit * 0.8)), 1.5)
	# fissures : 1 a 3, angles varies
	var ncr := 1 + int(h3 * 2.5)
	for k in ncr:
		var a := ctr + Vector2((_hash01(c * 3 + k, r) - 0.5) * CELL * 0.7, (_hash01(c, r * 3 + k) - 0.5) * CELL * 0.7)
		var dir := Vector2.RIGHT.rotated(_hash01(c + k * 5, r + k * 7) * TAU)
		var l1 := 8.0 + _hash01(k, c + r) * 16.0
		draw_polyline(PackedVector2Array([a, a + dir * l1 * 0.6 + dir.orthogonal() * 3.0, a + dir * l1]),
			Color(_INK.r, _INK.g, _INK.b, 0.6), 1.0)
	# eclats de coin + gravats
	if h3 > 0.7:
		var cn: Vector2 = pts[int(h * 3.99)]
		var into := (ctr - cn).normalized()
		draw_colored_polygon(PackedVector2Array([cn, cn + into.rotated(0.6) * 12.0, cn + into.rotated(-0.6) * 10.0]), _STONE_DEEP)
	# mousse dans les coins bas
	if h2 < 0.2:
		for k in 2:
			draw_circle(o + Vector2(6.0 + k * (CELL - 16.0), CELL - 5.0 - _hash01(k, c) * 4.0), 3.0 + h * 3.0, _MOSS)
	# grime accumule dans le joint bas/droite
	draw_line(pts[3], pts[2], Color(0, 0, 0, 0.28), 4.0)
	draw_line(pts[1], pts[2], Color(0, 0, 0, 0.22), 3.0)
	# touffes d'herbe : SEULEMENT dans les joints des dalles pres d'un mur, et
	#  jamais sur une dalle sombre (ça lisait comme de l'abandon).
	var near_wall := c <= BUILD_COL_MIN or c >= BUILD_COL_MAX or r <= WALK_ROW_MIN or r >= WALK_ROW_MAX
	if h3 < 0.10 and near_wall and lit > 0.15:
		var gp := o + Vector2(m + h * (CELL - 2.0 * m), CELL - m + 1.0)
		var gcol := Color(0.24, 0.30, 0.15).lerp(Color(0.38, 0.42, 0.21), lit)
		for k in 3:
			var sw := (_hash01(c + k, r * 2) - 0.5) * 8.0
			draw_line(gp + Vector2((k - 1) * 2.5, 0), gp + Vector2((k - 1) * 2.5 + sw, -5.0 - _hash01(k, c) * 5.0), gcol, 1.3)


func _offset(pts: PackedVector2Array, d: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + d)
	return out


## Ombres portees : chaque objet projette une ombre longue a l'oppose de la
## lumiere la plus proche -> le plateau cesse d'etre plat.
func _draw_cast_shadows() -> void:
	var casters: Array = []
	for cell in occupied:
		casters.append({"p": cell_to_world(cell), "s": 24.0})
	casters.append({"p": THRONE_ANCHOR + Vector2(-8, 8), "s": 46.0})
	for cst in casters:
		var p: Vector2 = cst["p"]
		var near := Vector2.ZERO
		var bd := 1e9
		for L in light_sources():
			var d: float = p.distance_to(L["p"])
			if d < bd:
				bd = d
				near = L["p"]
		var dir := (p - near)
		if dir.length() < 1.0:
			dir = Vector2(0.3, 1.0)
		dir = dir.normalized()
		var strength: float = clampf(1.0 - bd / 260.0, 0.15, 1.0)
		var sz: float = cst["s"]
		var tip := p + dir * (sz * 2.0 + 28.0)
		var n := dir.orthogonal() * sz * 0.6
		# ombre en 2 passes : large diffuse + noyau net au pied
		draw_colored_polygon(PackedVector2Array([p - n * 0.85, p + n * 0.85, tip + n * 0.4, tip - n * 0.4]),
			Color(0, 0, 0, 0.22 * strength))
		draw_colored_polygon(PackedVector2Array([p - n * 0.6, p + n * 0.6, tip * 0.55 + p * 0.45 + n * 0.3, tip * 0.55 + p * 0.45 - n * 0.3]),
			Color(0, 0, 0, 0.30 * strength))
		draw_circle(p + dir * 3.0, sz * 0.52, Color(0, 0, 0, 0.34 * strength))


## Props de la salle (paille, tonneaux, chandelles, colonne brisee, ossements) :
## deterministes, sur des cases libres hors du chemin -> comble le vide.
func _draw_props() -> void:
	# props FRANCHEMENT dans l'arene (jamais sur un mur ni pres des portes)
	var slots := [
		Vector2i(BUILD_COL_MIN + 1, WALK_ROW_MIN + 1), Vector2i(BUILD_COL_MAX - 2, WALK_ROW_MIN + 1),
		Vector2i(BUILD_COL_MIN + 1, WALK_ROW_MAX - 1), Vector2i(BUILD_COL_MAX - 2, WALK_ROW_MAX - 1),
		Vector2i(BUILD_COL_MIN + 3, WALK_ROW_MAX - 1), Vector2i(BUILD_COL_MIN + 6, WALK_ROW_MIN + 1),
		Vector2i(BUILD_COL_MIN + 1, WALK_ROW_MIN + 4), Vector2i(BUILD_COL_MIN + 5, WALK_ROW_MAX - 1)]
	var idx := 0
	for cell: Vector2i in slots:
		if occupied.has(cell):
			idx += 1
			continue
		var p := cell_to_world(cell) + Vector2((_hash01(idx, 3) - 0.5) * 16.0, (_hash01(idx, 8) - 0.5) * 16.0)
		var lit := lit_at(p)
		draw_circle(p + Vector2(4, 6), 13.0, Color(0, 0, 0, 0.26))   ## contact
		match idx % 4:
			0: _prop_hay(p, lit, idx)
			1: _prop_barrel(p, lit, idx)
			2: _prop_candles(p, idx)
			_: _prop_bones(p, lit, idx)
		idx += 1


func _prop_hay(p: Vector2, lit: float, sd: int) -> void:
	var col := _HAY.darkened((1.0 - lit) * 0.35)
	_ink_quad(PackedVector2Array([p + Vector2(-16, 8), p + Vector2(16, 8), p + Vector2(9, -8), p + Vector2(-11, -6)]), col.darkened(0.15), 1.8)
	for k in 7:
		var a := p + Vector2(-13.0 + k * 4.0, 8.0)
		draw_line(a, a + Vector2((_hash01(sd + k, 2) - 0.5) * 8.0, -12.0 - _hash01(k, sd) * 6.0), Color(col.r, col.g, col.b, 0.85), 1.4)


func _prop_barrel(p: Vector2, lit: float, sd: int) -> void:
	var wood := Color(0.24, 0.17, 0.11).lerp(Color(0.33, 0.24, 0.15), lit)
	_ink_quad(PackedVector2Array([p + Vector2(-9, 12), p + Vector2(9, 12), p + Vector2(11, -12), p + Vector2(-11, -12)]), wood, 2.0)
	draw_line(p + Vector2(-11, -4), p + Vector2(11, -4), Color(0, 0, 0, 0.4), 1.5)
	draw_line(p + Vector2(-11, 5), p + Vector2(11, 5), Color(0, 0, 0, 0.4), 1.5)
	draw_line(p + Vector2(-10, -12), p + Vector2(-8, 12), Color(1, 1, 1, 0.06), 1.5)
	if sd % 2 == 0:
		draw_circle(p + Vector2(0, -12), 3.0, _IRON)


func _prop_candles(p: Vector2, sd: int) -> void:
	for k in 3:
		var cp := p + Vector2(-7.0 + k * 7.0, 4.0 - k * 2.0)
		var ch := 9.0 + _hash01(sd + k, 3) * 6.0
		draw_line(cp, cp + Vector2(0, ch), Color(0.82, 0.78, 0.66), 3.0)
		draw_line(cp, cp + Vector2(0, ch), _INK, 1.0)
		var fl := 0.85 + sin(_t * 8.0 + k + sd) * 0.15
		draw_colored_polygon(PackedVector2Array([cp + Vector2(-1.6, 0), cp + Vector2(1.6, 0), cp + Vector2(0, -5.0 * fl)]), _FIRE_MID)
		draw_circle(cp + Vector2(0, -2.0), 1.1, _FIRE_CORE)


func _prop_bones(p: Vector2, lit: float, sd: int) -> void:
	var bone := Color(0.68, 0.64, 0.54).darkened((1.0 - lit) * 0.4)
	for k in 3:
		var a := p + Vector2(-10.0 + k * 8.0, 6.0 - k * 3.0)
		var b := a + Vector2(12.0, -3.0 + _hash01(sd + k, 5) * 6.0).rotated(_hash01(k, sd) * 0.8)
		draw_line(a, b, _INK, 4.0)
		draw_line(a, b, bone, 2.2)
		draw_circle(a, 2.2, bone)
		draw_circle(b, 2.2, bone)


func _closed(p: PackedVector2Array) -> PackedVector2Array:
	var o := p
	o.append(p[0])
	return o


func _inset_shadow(rc: Rect2, depth: float) -> void:
	var n := 5
	for i in n:
		var f := float(i) / float(n)
		var d := depth * f
		draw_rect(Rect2(rc.position + Vector2(d, d), rc.size - Vector2(d * 2.0, d * 2.0)),
			Color(0, 0, 0, _AO.a * (1.0 - f) * 0.5), false, maxf(1.5, depth / n))


## Enceinte v11 (flux vertical) : 4 murs vus de dessus, tourelles d'angle, 2 portes
## voutees (mur HAUT = faille, mur BAS = roi).  Murs gauche/droite sans porte.
func _draw_arena_walls() -> void:
	var wx0 := BATTLE_COL_MIN * CELL
	var wx1 := (BATTLE_COL_MAX + 1) * CELL
	var top_base := WALK_ROW_MIN * CELL              ## y : le mur haut rencontre le sol de l'arene
	var bot_top := (WALK_ROW_MAX + 1) * CELL         ## y : haut du mur bas
	var in_x0 := (BATTLE_COL_MIN + 1) * CELL
	var in_x1 := BATTLE_COL_MAX * CELL

	# --- 1. OMBRE PORTEE de l'enceinte sur le sol (les 4 cotes) ---
	for i in 14:
		var f := float(i) / 14.0
		var a := 0.30 * (1.0 - f) * (1.0 - f)
		draw_rect(Rect2(Vector2(in_x0, top_base + f * 20.0), Vector2(in_x1 - in_x0, 20.0 / 14.0 + 1.5)), Color(0, 0, 0, a))
		draw_rect(Rect2(Vector2(in_x0, bot_top - 20.0 + f * 20.0), Vector2(in_x1 - in_x0, 20.0 / 14.0 + 1.5)), Color(0, 0, 0, a * 0.7))
		draw_rect(Rect2(Vector2(in_x0 + f * 16.0, top_base), Vector2(16.0 / 14.0 + 1.5, bot_top - top_base)), Color(0, 0, 0, a * 0.8))
		draw_rect(Rect2(Vector2(in_x1 - f * 16.0 - 2.0, top_base), Vector2(16.0 / 14.0 + 1.5, bot_top - top_base)), Color(0, 0, 0, a * 0.8))

	# --- 2. MURS : haut & bas sur les colonnes (sauf la porte), gauche & droite sur les rangees ---
	for c in range(BATTLE_COL_MIN + 1, BATTLE_COL_MAX):
		if c == GATE_COL:
			continue
		_wall_top_block(c * CELL, top_base)
		_wall_bot_block(c * CELL, bot_top)
	for r in range(WALK_ROW_MIN, WALK_ROW_MAX + 1):
		_wall_side_block(Vector2(BATTLE_COL_MIN * CELL, r * CELL), true, false, false)
		_wall_side_block(Vector2(BATTLE_COL_MAX * CELL, r * CELL), false, false, false)
	# 4 tourelles d'angle
	_corner_pier(BATTLE_COL_MIN * CELL, (WALK_ROW_MIN - 1) * CELL, true, true)
	_corner_pier(BATTLE_COL_MAX * CELL, (WALK_ROW_MIN - 1) * CELL, false, true)
	_corner_pier(BATTLE_COL_MIN * CELL, (WALK_ROW_MAX + 1) * CELL, true, false)
	_corner_pier(BATTLE_COL_MAX * CELL, (WALK_ROW_MAX + 1) * CELL, false, false)
	# 2 portes voutees
	_gate_arch(BATTLE_ROW_MIN, true)                 ## mur HAUT : entree (faille)
	_gate_arch(BATTLE_ROW_MAX, false)                ## mur BAS : roi

	# --- 3. ombre franche des murs haut & bas sur le sol ---
	for i in 18:
		var f := float(i) / 18.0
		draw_rect(Rect2(Vector2(wx0, top_base + f * 22.0), Vector2(wx1 - wx0, 22.0 / 18.0 + 1.5)),
			Color(0, 0, 0, 0.30 * (1.0 - f) * (1.0 - f)))
	draw_line(Vector2(wx0, top_base), Vector2(wx1, top_base), Color(0, 0, 0, 0.5), 2.0)
	# contour SILHOUETTE de l'enceinte
	var op := PackedVector2Array([
		Vector2(wx0 + 1, 1), Vector2(wx1 - 1, 1),
		Vector2(wx1 - 1, bot_top + CELL - 1), Vector2(wx0 + 1, bot_top + CELL - 1)])
	_ink_path(op, 4.0, 12345)


# ===== KIT DE MUR UNIFIE v10 (ref "tripleAAA") : chemin de ronde vu de dessus,
# petits merlons reguliers sur les 2 aretes, torches sur l'arete interne.
# Coupe (de l'arene vers l'exterieur) : face interne 12 | dalle 34 | zone merlon ext 12
const WALL_FACE_D    := 12.0    ## courte face interne foreshortened (glimpse vertical)
const WALL_WALK_D    := 34.0    ## dalle du chemin de ronde : LA grande surface
const WALL_MERL_D    := 12.0    ## demi-largeur de la zone de merlons externe
const SIDE_FACE_W    := 42.0    ## (legacy)
const SIDE_ARRIS_W   := 3.0
const SIDE_WALK_W    := 12.0
const SIDE_MERLON_D  := 15.0
const SIDE_OUT_EDGE  := 4.0
const _MERLON_W  := 40.0
const _MERLON_GAP := 24.0
const _MERLON_TALL := 30.0
const _CAP_H  := 20.0
const _PLINTH_H := 14.0

func _target(ci: CanvasItem) -> CanvasItem:
	return ci if ci != null else self

## Rect2 couvrant [xa..xb] en x et une case en y (ordre des x indifferent).
func _xspan(xa: float, xb: float, yy: float) -> Rect2:
	return Rect2(Vector2(minf(xa, xb), yy), Vector2(absf(xa - xb), CELL + 0.6))

## Face en pierre : assises de 18px, appareil en panneresses (running bond), biseau
## par bloc, joints, rebond chaud dans les 20px du bas, liseré froid en haut.
## `dark` : "bottom"|"top" -> quel bord porte l'AO du pied de mur.  `warm` 0..1.
func _stone_face(t: CanvasItem, r: Rect2, sd: int, dark: String, warm := 0.0) -> void:
	if r.size.y < 4.0 or r.size.x < 4.0:
		return
	var nrow := maxi(1, roundi(r.size.y / _COURSE_H))
	for row in nrow:
		var y0 := r.position.y + r.size.y * float(row) / nrow
		var y1 := r.position.y + r.size.y * float(row + 1) / nrow
		var d := float(row) / maxf(1.0, float(nrow - 1))           ## 0 haut -> 1 bas
		if dark == "top":
			d = 1.0 - d
		var col := _K_FACE_HI.lerp(_K_FACE_MID, smoothstep(0.0, 0.45, d)).lerp(_K_FACE_LO, smoothstep(0.55, 1.0, d))
		# appareil : blocs 34..58, joints montants decales
		var off := (23.0 if row % 2 == 1 else 0.0) + (_hash01(sd + row * 7, row) - 0.5) * 10.0
		var bx := r.position.x - 58.0 + off
		while bx < r.end.x:
			var blen := 34.0 + _hash01(sd + int(bx) * 3, row * 5 + 1) * 24.0
			if _hash01(sd + int(bx), row + 9) > 0.83:
				blen = 60.0 + _hash01(sd + int(bx) * 2, row) * 20.0   ## 1/6 gros bloc
			var x0 := maxf(bx, r.position.x)
			var x1 := minf(bx + blen, r.end.x)
			if x1 > x0 + 1.0:
				var bc := col.lerp(col.darkened(0.16), (_hash01(sd + int(bx), row) - 0.5) * 0.6 + 0.3)
				bc = bc.lerp(_K_AMBWARM, 0.06)               ## plancher chaud : aucun pixel jamais gris neutre
				# rebond chaud (bas 20px) puis chaleur de torche
				var dist_up := r.end.y - (y0 + y1) * 0.5
				if dark == "bottom" and dist_up < 20.0:
					bc = bc.lerp(_K_BOUNCE, (1.0 - dist_up / 20.0) * 0.2)
				if warm > 0.02:
					bc = bc.lerp(_K_WARM, warm * (0.6 + 0.4 * (1.0 - d)))
				t.draw_rect(Rect2(Vector2(x0, y0), Vector2(x1 - x0 + 0.6, y1 - y0 + 0.6)), bc)
				# biseau : rehaut haut-gauche, AO bas-droite
				t.draw_line(Vector2(x0, y0 + 0.6), Vector2(x1, y0 + 0.6), Color(bc.lightened(0.16).r, bc.lightened(0.16).g, bc.lightened(0.16).b, 0.8), 1.4)
				t.draw_line(Vector2(x0, y1 - 0.8), Vector2(x1, y1 - 0.8), _K_FACE_LO, 2.0)
				t.draw_line(Vector2(x1, y0), Vector2(x1, y1), _K_MORTAR, 1.8)                 ## joint montant
				# fissure / mousse occasionnelle
				var h := _hash01(sd + int(bx) * 11, row * 13 + 3)
				if h > 0.90:
					t.draw_line(Vector2(x0 + 5, y0 + 2), Vector2((x0 + x1) * 0.5 + 4, y1 - 3), Color(_K_MORTAR.r, _K_MORTAR.g, _K_MORTAR.b, 0.8), 1.0)
				elif h < 0.06 and d > 0.5:
					t.draw_circle(Vector2((x0 + x1) * 0.5, y1 - 3), 4.0 + h * 40.0, Color(0.28, 0.34, 0.20, 0.55))
			bx = bx + blen + 1.0
		# joint de lit + micro-lip clair sur l'arete du dessous
		t.draw_line(Vector2(r.position.x, y1 - 0.5), Vector2(r.end.x, y1 - 0.5), _K_MORTAR, 2.4)
	# liseré froid en haut de la face
	t.draw_line(r.position, Vector2(r.end.x, r.position.y), _K_SKY_RIM, 1.2)


## Merlons le long d'un span HORIZONTAL.  Module 40/24/64 aligne au centre de case.
## Chaque merlon : corps (2 assises) + face de dessus en chanfrein + arete gauche
## claire / droite AO + OMBRE PORTEE dans le creneau a sa droite (sinon "code-barre").
## Le fond de creneau montre le chemin de ronde, JAMAIS du noir.
func _merlon_h(t: CanvasItem, x0: float, x1: float, cap_y: float, sd: int, big_at := -1) -> void:
	var cell0 := int(floorf(x0 / CELL))
	var cell1 := int(ceilf(x1 / CELL))
	var floor_c := _K_CAP_CORE.darkened(0.14)                   ## chemin de ronde vu par le creneau
	for cc in range(cell0, cell1):
		var ctr := cc * CELL + CELL * 0.5
		var mw := _MERLON_W + (6.0 if cc == big_at else 0.0)
		var tall := _MERLON_TALL + (6.0 if cc == big_at else 0.0) + (_hash01(sd + cc, 3) - 0.5) * 3.0
		var m0 := maxf(ctr - mw * 0.5, x0)
		var m1 := minf(ctr + mw * 0.5, x1)
		# --- creneau A GAUCHE de ce merlon : fond clair + ombre portee du merlon precedent ---
		var gL0 := maxf(ctr - CELL * 0.5, x0)
		if m0 > gL0 + 1.0:
			t.draw_rect(Rect2(Vector2(gL0, cap_y - tall), Vector2(m0 - gL0, tall + 1.0)), floor_c)
			t.draw_rect(Rect2(Vector2(gL0, cap_y - tall), Vector2(m0 - gL0, tall + 1.0)), Color(0, 0, 0, 0.30))   ## dans l'ombre
			# ombre PORTEE du merlon de gauche qui tombe vers la droite/bas
			t.draw_colored_polygon(PackedVector2Array([
				Vector2(gL0, cap_y - tall), Vector2(gL0 + 14.0, cap_y - tall),
				Vector2(gL0 + 6.0, cap_y), Vector2(gL0, cap_y)]), Color(0, 0, 0, 0.42))
		if m1 <= m0 + 2.0:
			continue
		# --- corps du merlon (2 assises) ---
		t.draw_rect(Rect2(Vector2(m0, cap_y - tall), Vector2(m1 - m0, tall + 1.0)), _K_FACE_MID.lerp(_K_AMBWARM, 0.06))
		t.draw_line(Vector2(m0, cap_y - tall * 0.5), Vector2(m1, cap_y - tall * 0.5), _K_MORTAR, 1.6)
		# face de dessus en chanfrein (parallelogramme : le merlon a de l'epaisseur)
		t.draw_colored_polygon(PackedVector2Array([
			Vector2(m0, cap_y - tall), Vector2(m1, cap_y - tall),
			Vector2(m1 - 3.0, cap_y - tall + 6.0), Vector2(m0 - 3.0, cap_y - tall + 6.0)]), _K_CAP_LIT)
		t.draw_line(Vector2(m0, cap_y - tall), Vector2(m1, cap_y - tall), _K_SKY_RIM, 1.4)
		# aretes verticales : gauche claire, droite AO
		t.draw_line(Vector2(m0, cap_y - tall), Vector2(m0, cap_y), Color(_K_CAP_LIT.r, _K_CAP_LIT.g, _K_CAP_LIT.b, 0.8), 1.4)
		t.draw_line(Vector2(m1, cap_y - tall), Vector2(m1, cap_y), _K_FACE_LO, 2.2)


## Rangee de merlons le long d'une arete du chemin de ronde (ref "tripleAAA" : petits
## blocs reguliers, 1/case, dessus clair, ombre portee courte sur la dalle).
##   `edge`  : coord de l'arete (y si horiz, x sinon)
##   `horiz` : true = arete horizontale (murs haut/bas), merlons alignes sur x
##   `into`  : +1/-1, direction de l'arete VERS la dalle (l'ombre tombe par la)
func _merlon_strip(t: CanvasItem, a0: float, a1: float, edge: float, horiz: bool, into: float, sd: int, warm := 0.0) -> void:
	var c0 := int(floorf(minf(a0, a1) / CELL))
	var c1 := int(ceilf(maxf(a0, a1) / CELL))
	var half := 15.0
	var body := _K_CAP_CORE.lerp(_K_WARM, warm * 0.35)
	var cap := _K_CAP_LIT.lerp(_K_WARM, warm * 0.4)
	for cc in range(c0, c1):
		var m := cc * CELL + CELL * 0.5 + (_hash01(sd + cc, 2) - 0.5) * 3.0
		if m < minf(a0, a1) - 2.0 or m > maxf(a0, a1) + 2.0:
			continue
		if horiz:
			t.draw_rect(Rect2(Vector2(m - half, edge - 7.5), Vector2(half * 2.0, 15.0)), body)                 ## corps du merlon
			var cap_y := (edge - 7.5) if into > 0 else (edge + 3.5)                                            ## dessus = oppose a la dalle
			t.draw_rect(Rect2(Vector2(m - half, cap_y), Vector2(half * 2.0, 4.0)), cap)
			t.draw_rect(Rect2(Vector2(m - half, edge + (2.0 if into > 0 else -9.0)), Vector2(half * 2.0, 7.0)), Color(0, 0, 0, 0.30))  ## ombre portee
			t.draw_line(Vector2(m - half, edge - 7.5), Vector2(m - half, edge + 7.5), _K_MORTAR, 1.2)
			t.draw_line(Vector2(m + half, edge - 7.5), Vector2(m + half, edge + 7.5), _K_MORTAR, 1.2)
		else:
			t.draw_rect(Rect2(Vector2(edge - 7.5, m - half), Vector2(15.0, half * 2.0)), body)
			var cap_x := (edge - 7.5) if into > 0 else (edge + 3.5)
			t.draw_rect(Rect2(Vector2(cap_x, m - half), Vector2(4.0, half * 2.0)), cap)
			t.draw_rect(Rect2(Vector2(edge + (2.0 if into > 0 else -9.0), m - half), Vector2(7.0, half * 2.0)), Color(0, 0, 0, 0.30))
			t.draw_line(Vector2(edge - 7.5, m - half), Vector2(edge + 7.5, m - half), _K_MORTAR, 1.2)
			t.draw_line(Vector2(edge - 7.5, m + half), Vector2(edge + 7.5, m + half), _K_MORTAR, 1.2)


## Chaleur de torche 0..1 pour un point du mur (base : le lit + attenuation douce).
func _wall_warm(p: Vector2) -> float:
	var w := 0.0
	for L in light_sources():
		if _light_clipped(L, p):
			continue
		var col: Color = L["col"]
		if col.r < col.b or col.g > col.r:                ## pas les sources froides / vertes (faille)
			continue
		var d := p.distance_to(L["p"])
		w = maxf(w, clampf(1.0 - d / (L["r"] * 0.55), 0.0, 1.0))
	return w * w


## MUR HAUT (col 4-14) v10 : face visible (banniere/torche/arche) + dalle + merlons.
const TOP_FACE_H := 60.0
const TOP_WALK_H := 18.0
func _wall_top_block(x: float, base_y: float) -> void:
	var ci := int(x / CELL)
	var face_top := base_y - TOP_FACE_H
	var walk_top := face_top - TOP_WALK_H
	var warm := _wall_warm(Vector2(x + CELL * 0.5, base_y - 30.0))
	# plinthe : sort de 2px au pied de la face
	draw_rect(Rect2(Vector2(x - 2.0, base_y - 10.0), Vector2(CELL + 4.5, 10.0)), _K_FACE_LO.lerp(_K_BOUNCE, 0.18))
	# face en pierre appareillee
	_stone_face(self, Rect2(Vector2(x, face_top), Vector2(CELL + 0.5, base_y - 10.0 - face_top)), ci * 13 + 3, "bottom", warm)
	# pilastre 1 col sur 2 : donne du rythme a la face
	if ci % 2 == 0:
		draw_rect(Rect2(Vector2(x + CELL * 0.5 - 9.0, face_top), Vector2(18.0, base_y - face_top)), _K_FACE_MID.lerp(_K_WARM, warm * 0.45).lightened(0.03))
		draw_line(Vector2(x + CELL * 0.5 - 9.0, face_top), Vector2(x + CELL * 0.5 - 9.0, base_y), Color(_K_CAP_LIT.r, _K_CAP_LIT.g, _K_CAP_LIT.b, 0.5), 1.4)
		draw_line(Vector2(x + CELL * 0.5 + 9.0, face_top), Vector2(x + CELL * 0.5 + 9.0, base_y), _K_FACE_LO, 1.8)
	else:
		var sc := Vector2(x + CELL * 0.5, face_top + (base_y - face_top) * 0.42)   ## meurtriere
		draw_rect(Rect2(sc + Vector2(-2.5, -12.0), Vector2(5.0, 24.0)), _K_MERLON_SH)
	# AO sous le surplomb de la dalle
	draw_rect(Rect2(Vector2(x, face_top), Vector2(CELL + 0.5, 5.0)), Color(0, 0, 0, 0.34))
	# dalle du chemin de ronde
	draw_rect(Rect2(Vector2(x, walk_top), Vector2(CELL + 0.5, TOP_WALK_H)), _K_CAP_CORE.lerp(_K_WARM, warm * 0.18))
	draw_line(Vector2(x, face_top), Vector2(x + CELL, face_top), _K_CAP_LIT, 1.4)
	# merlons sur l'arete externe (haute)
	_merlon_strip(self, x, x + CELL, walk_top, true, 1.0, ci * 3 + 1, warm)


## MUR BAS (col 4-14) v10 : meme kit que les murs lateraux, vu de dessus.
## merlons arene (nord) + dalle + merlons casernes (sud) + courte descente sud.
func _wall_bot_block(x: float, top_y: float) -> void:
	var ci := int(x / CELL)
	var warm := _wall_warm(Vector2(x + CELL * 0.5, top_y + 16.0))
	var walk_top := top_y + WALL_FACE_D
	var walk_bot := walk_top + WALL_WALK_D
	# courte face interne (nord, vers l'arene) : glimpse vertical
	draw_rect(Rect2(Vector2(x, top_y), Vector2(CELL + 0.5, WALL_FACE_D)), _K_FACE_MID.lerp(_K_WARM, warm * 0.4))
	draw_rect(Rect2(Vector2(x, top_y), Vector2(CELL + 0.5, 3.0)), _K_FACE_HI.lerp(_K_WARM, warm * 0.4))
	# dalle du chemin de ronde
	draw_rect(Rect2(Vector2(x, walk_top), Vector2(CELL + 0.5, WALL_WALK_D)), _K_CAP_CORE.lerp(_K_WARM, warm * 0.2))
	draw_line(Vector2(x + CELL * 0.5, walk_top), Vector2(x + CELL * 0.5, walk_bot), _K_MORTAR, 1.3)
	draw_line(Vector2(x, (walk_top + walk_bot) * 0.5), Vector2(x + CELL, (walk_top + walk_bot) * 0.5), _K_MORTAR, 1.3)
	# descente sud (vers les casernes) : courte face en ombre
	draw_rect(Rect2(Vector2(x, walk_bot), Vector2(CELL + 0.5, 12.0)), _K_FACE_LO.lerp(_K_AMBWARM, 0.1))
	# merlons : arete nord (into = +1, dalle en dessous) + arete sud (into = -1)
	_merlon_strip(self, x, x + CELL, top_y, true, 1.0, ci * 3 + 1, warm)
	_merlon_strip(self, x, x + CELL, walk_bot, true, -1.0, ci * 3 + 5, warm * 0.3)
	# AO du mur bas sur le sol de l'arene
	for k in 7:
		var a := 0.20 * (1.0 - k / 7.0) * (1.0 - k / 7.0)
		draw_rect(Rect2(Vector2(x, top_y - 10.0 - k * 2.0), Vector2(CELL + 0.5, 2.0)), Color(0, 0, 0, a))


## MUR LATERAL (col 3 / 15) v10 (ref "tripleAAA") : chemin de ronde vu de dessus,
## petits merlons reguliers sur les DEUX aretes, torches sur l'arete interne.
func _wall_side_block(pos: Vector2, is_left: bool, _corner: bool, is_gate: bool) -> void:
	var ri := int(pos.y / CELL)
	var outw := -1.0 if is_left else 1.0
	var in_x := (pos.x + CELL) if is_left else pos.x               ## arete interne (cote arene)
	var y := pos.y
	var x_face := in_x + outw * WALL_FACE_D                         ## fin de la courte face interne
	var x_walk := in_x + outw * (WALL_FACE_D + WALL_WALK_D)         ## fin de la dalle
	var x_out := x_walk + outw * WALL_MERL_D                        ## arete externe
	var warm := _wall_warm(Vector2(in_x + outw * 10.0, y + CELL * 0.5))
	if is_gate:
		draw_rect(_xspan(in_x + outw * 2.0, x_out + outw * 4.0, y), _K_MERLON_SH)   ## alcove : l'arche se dessine par-dessus
		return
	# --- 1. chute vers le vide (au-dela de l'arete externe) ---
	draw_rect(_xspan(x_out, x_out + outw * 5.0, y), _K_FACE_LO.darkened(0.35))
	# --- 2. dalle du chemin de ronde (grande surface) ---
	var walk := _xspan(x_face, x_walk, y)
	draw_rect(walk, _K_CAP_CORE.lerp(_K_WARM, warm * 0.22))
	draw_line(Vector2(walk.position.x, y + CELL * 0.5), Vector2(walk.end.x, y + CELL * 0.5), _K_MORTAR, 1.4)   ## joint transversal
	if _hash01(ri, 3) > 0.6:
		draw_line(Vector2((walk.position.x + walk.end.x) * 0.5, y + 6.0), Vector2((walk.position.x + walk.end.x) * 0.5 + 5.0, y + CELL - 8.0), _K_MORTAR, 1.0)  ## fissure
	# --- 3. courte face interne (glimpse vertical entre dalle et sol de l'arene) ---
	var fr := _xspan(in_x, x_face, y)
	draw_rect(fr, _K_FACE_MID.lerp(_K_WARM, warm * 0.4))
	draw_rect(Rect2(fr.position, Vector2(fr.size.x, 3.0)), _K_FACE_HI.lerp(_K_WARM, warm * 0.4))
	draw_line(Vector2(fr.position.x, y + CELL - 1.0), Vector2(fr.end.x, y + CELL - 1.0), _K_FACE_LO, 1.6)
	# --- 4. merlons : arete interne (dalle vers l'exterieur) + arete externe ---
	_merlon_strip(self, y, y + CELL, in_x, false, outw, ri * 3 + 1, warm)
	_merlon_strip(self, y, y + CELL, x_out, false, -outw, ri * 3 + 7, warm * 0.4)
	# --- 5. contact au sol de l'arene ---
	draw_line(Vector2(in_x, y), Vector2(in_x, y + CELL), Color(0, 0, 0, 0.5), 2.0)
	for k in 9:
		var a := 0.24 * (1.0 - k / 9.0) * (1.0 - k / 9.0)
		draw_line(Vector2(in_x - outw * (3.0 + k * 2.4), y), Vector2(in_x - outw * (3.0 + k * 2.4), y + CELL),
			Color(_K_WARM_BLK.r, _K_WARM_BLK.g, _K_WARM_BLK.b, a), 1.8)


## TOURELLE D'ANGLE (ref "tripleAAA") : petite tour carree vue de dessus, un peu
## plus grande que la case, merlons sur les 4 cotes, centre en creux, ombre portee.
func _corner_pier(cell_x: float, cell_y: float, is_left: bool, is_top: bool) -> void:
	var ex := 10.0                                            ## debord de la tour
	var tx := cell_x - ex
	var ty := cell_y - ex
	var tw := CELL + ex * 2.0
	var warm := _wall_warm(Vector2(cell_x + CELL * 0.5, cell_y + CELL * 0.5))
	var dx := 1.0 if is_left else -1.0                        ## vers l'arene, en x
	var dy := 1.0 if is_top else -1.0                         ## vers l'arene, en y
	# --- ombre portee sur le sol de l'arene (coin rentrant) ---
	var ic := Vector2(cell_x + (CELL if is_left else 0.0), cell_y + (CELL if is_top else 0.0))
	for k in 9:
		var a := 0.26 * (1.0 - k / 9.0) * (1.0 - k / 9.0)
		draw_colored_polygon(PackedVector2Array([ic, ic + Vector2(dx * (52 - k * 5), 0), ic + Vector2(0, dy * (52 - k * 5))]),
			Color(_K_WARM_BLK.r, _K_WARM_BLK.g, _K_WARM_BLK.b, a))
	# --- corps de la tour + chute exterieure ---
	draw_rect(Rect2(Vector2(tx - 4.0, ty - 4.0), Vector2(tw + 8.0, tw + 8.0)), _K_FACE_LO.darkened(0.25))
	draw_rect(Rect2(Vector2(tx, ty), Vector2(tw, tw)), _K_FACE_MID.lerp(_K_WARM, warm * 0.2))
	# --- dalle du chemin de ronde (grande surface) + joints ---
	var walk := Rect2(Vector2(tx + 13.0, ty + 13.0), Vector2(tw - 26.0, tw - 26.0))
	draw_rect(walk, _K_CAP_CORE.lerp(_K_WARM, warm * 0.22))
	draw_line(Vector2(walk.position.x, walk.get_center().y), Vector2(walk.end.x, walk.get_center().y), _K_MORTAR, 1.3)
	draw_line(Vector2(walk.get_center().x, walk.position.y), Vector2(walk.get_center().x, walk.end.y), _K_MORTAR, 1.3)
	# --- merlons sur les 4 aretes (into pointe vers le centre de la tour) ---
	_merlon_strip(self, tx + 6.0, tx + tw - 6.0, ty, true, 1.0, int(cell_x) + 1, warm)          ## haut
	_merlon_strip(self, tx + 6.0, tx + tw - 6.0, ty + tw, true, -1.0, int(cell_x) + 2, warm)     ## bas
	_merlon_strip(self, ty + 6.0, ty + tw - 6.0, tx, false, 1.0, int(cell_y) + 3, warm)          ## gauche
	_merlon_strip(self, ty + 6.0, ty + tw - 6.0, tx + tw, false, -1.0, int(cell_y) + 4, warm)    ## droite
	# --- arete lumiere haut-gauche / AO bas-droite ---
	draw_line(Vector2(tx, ty), Vector2(tx + tw, ty), Color(_K_CAP_LIT.r, _K_CAP_LIT.g, _K_CAP_LIT.b, 0.5), 1.4)
	draw_line(Vector2(tx, ty), Vector2(tx, ty + tw), Color(_K_CAP_LIT.r, _K_CAP_LIT.g, _K_CAP_LIT.b, 0.4), 1.2)
	draw_line(Vector2(tx + tw, ty), Vector2(tx + tw, ty + tw), _K_FACE_LO, 2.0)
	draw_line(Vector2(tx, ty + tw), Vector2(tx + tw, ty + tw), _K_FACE_LO, 2.0)


## Redessine les MERLONS par-dessus le calque de lumiere additif -> la lueur des
## torches est coupee net a la ligne du parapet (elle reste sur la dalle, pas dans
## le vide).  Plus : le chasme entre rempart et bande eco.
func _draw_wall_crown(ci: CanvasItem) -> void:
	var top_base := WALK_ROW_MIN * CELL
	var bot_top := (WALK_ROW_MAX + 1) * CELL
	# --- mur HAUT : merlons sur l'arete externe (sauf la porte) ---
	for c in range(BATTLE_COL_MIN + 1, BATTLE_COL_MAX):
		if c == GATE_COL:
			continue
		var x := c * CELL
		var w := _wall_warm(Vector2(x + CELL * 0.5, top_base - 30.0))
		_merlon_strip(ci, x, x + CELL, top_base - TOP_FACE_H - TOP_WALK_H, true, 1.0, c * 3 + 1, w)
	# --- mur BAS : merlons sur les 2 aretes (sauf la porte) ---
	for c in range(BATTLE_COL_MIN + 1, BATTLE_COL_MAX):
		if c == GATE_COL:
			continue
		var x := c * CELL
		var w := _wall_warm(Vector2(x + CELL * 0.5, bot_top + 16.0))
		_merlon_strip(ci, x, x + CELL, bot_top, true, 1.0, c * 3 + 1, w)
		_merlon_strip(ci, x, x + CELL, bot_top + WALL_FACE_D + WALL_WALK_D, true, -1.0, c * 3 + 5, w * 0.3)
	# --- murs LATERAUX : merlons sur les 2 aretes (pas de porte) ---
	for r in range(WALK_ROW_MIN, WALK_ROW_MAX + 1):
		for side in 2:
			var is_left := side == 0
			var outw := -1.0 if is_left else 1.0
			var in_x := (BATTLE_COL_MIN + 1) * CELL if is_left else BATTLE_COL_MAX * CELL
			var py := r * CELL
			var x_out := in_x + outw * (WALL_FACE_D + WALL_WALK_D + WALL_MERL_D)
			var w := _wall_warm(Vector2(in_x + outw * 10.0, py + CELL * 0.5))
			_merlon_strip(ci, py, py + CELL, in_x, false, outw, r * 3 + 1, w)
			_merlon_strip(ci, py, py + CELL, x_out, false, -outw, r * 3 + 7, w * 0.4)


## ARCHE DE PORTE v11 : portail voute VU DE FACE dans un mur HORIZONTAL (haut/bas).
## L'arc pointe vers le HAUT.  Ouverture rect + demi-arc, jambages, cle, herse relevee.
## La faille (porte haute) / le trone (porte basse) se logent dans l'ouverture.
func _gate_arch(gate_row: int, is_top: bool) -> void:
	var cx := GATE_COL * CELL + CELL * 0.5                         ## 416
	var sill_y := (float(WALK_ROW_MIN) if is_top else float(WALK_ROW_MAX + 1)) * CELL  ## sol de l'arene au mur
	var hw := 24.0
	var spring_y := sill_y - (34.0 if is_top else 40.0)            ## naissance de l'arc au-dessus du sol
	var crown_y := spring_y - hw
	var toward := 1.0 if is_top else -1.0                          ## direction de l'arene depuis le seuil
	var into := -1.0                                               ## le tunnel recule toujours vers le haut (-y)
	var col := gate_row
	# --- 1. VOID : ouverture rect + demi-disque, noir chaud jamais pur, degrade en fuite ---
	draw_rect(Rect2(Vector2(cx - hw, spring_y), Vector2(hw * 2.0, sill_y - spring_y)), Color(0.052, 0.048, 0.044))
	draw_colored_polygon(_arc_fan(Vector2(cx, spring_y), hw, PI, TAU, 20), Color(0.052, 0.048, 0.044))
	for k in 5:                                                    ## marches qui reculent : plus sombre + decalees vers le fond/haut
		var f := float(k) / 4.0
		var cv := 0.052 - f * 0.030
		draw_rect(Rect2(Vector2(cx - hw + 4.0 + into * f * 3.0, spring_y - f * 6.0), Vector2(hw * 2.0 - 8.0, sill_y - spring_y + f * 4.0)), Color(cv, cv * 0.95, cv * 0.9))
	# --- 2. JAMBAGES : 2 piles de pierres de taille de part et d'autre ---
	for s: float in [-1.0, 1.0]:
		var jx0 := cx + s * hw
		var jx1 := cx + s * (hw + 9.0)
		var by := spring_y - 4.0
		var bi := 0
		while by < sill_y - 1.0:
			draw_rect(Rect2(Vector2(minf(jx0, jx1), by), Vector2(9.0, 10.5)),
				_K_QUOIN.lerp(_K_QUOIN.darkened(0.26), _hash01(col + bi, 3) * 0.5 + 0.12).lerp(_K_AMBWARM, 0.06))
			draw_line(Vector2(minf(jx0, jx1), by), Vector2(maxf(jx0, jx1), by), _K_MORTAR, 1.3)
			by += 10.5
			bi += 1
		draw_line(Vector2(jx0, spring_y), Vector2(jx0, sill_y), Color(0, 0, 0, 0.55), 2.0)          ## arete interne : AO
		draw_line(Vector2(jx1, spring_y - 4.0), Vector2(jx1, sill_y), Color(_K_CAP_LIT.r, _K_CAP_LIT.g, _K_CAP_LIT.b, 0.45), 1.2)
	# --- 3. ANNEAU DE VOUSSOIRS : demi-arc SUPERIEUR (theta PI -> 2PI = ∩) ---
	var A := Vector2(cx, spring_y)
	var r_in := hw
	var r_out := hw + 14.0
	var nv := 9
	for k in nv:
		var g0 := lerpf(PI, TAU, float(k) / nv)
		var g1 := lerpf(PI, TAU, float(k + 1) / nv)
		var mid := (float(k) + 0.5) / nv
		var key := absf(mid - 0.5) < 0.07
		var ro := r_out + (5.0 if key else 0.0)
		var pa0 := A + Vector2(cos(g0), sin(g0)) * r_in
		var pa1 := A + Vector2(cos(g1), sin(g1)) * r_in
		var pb1 := A + Vector2(cos(g1), sin(g1)) * ro
		var pb0 := A + Vector2(cos(g0), sin(g0)) * ro
		var vc := _K_QUOIN.lerp(_K_FACE_MID, 0.10 + absf(mid - 0.5) * 0.6).lerp(_K_AMBWARM, 0.06)
		if key:
			vc = _K_QUOIN.lerp(_K_CAP_LIT, 0.45)
		_ink_quad(PackedVector2Array([pa0, pa1, pb1, pb0]), vc, 1.4)
		draw_line(pa0, pb0, _K_MORTAR, 1.2)
	draw_arc(A, r_out + 1.0, PI, TAU, 28, Color(_K_CAP_LIT.r, _K_CAP_LIT.g, _K_CAP_LIT.b, 0.5), 1.4)  ## extrados eclaire
	draw_arc(A, r_in - 1.0, PI + 0.14, TAU - 0.14, 28, Color(0, 0, 0, 0.45), 3.0)                     ## intrados : AO
	# cle de voute : bloc rehausse + chevron grave
	draw_rect(Rect2(Vector2(cx - 6.0, crown_y - 7.0), Vector2(12.0, 15.0)), _K_QUOIN.lerp(_K_CAP_LIT, 0.4))
	draw_line(Vector2(cx - 4.0, crown_y + 4.0), Vector2(cx, crown_y - 1.0), _K_MORTAR, 1.2)
	draw_line(Vector2(cx, crown_y - 1.0), Vector2(cx + 4.0, crown_y + 4.0), _K_MORTAR, 1.2)
	# assise de decharge au-dessus de la cle (raccorde au mur)
	for bx in 3:
		draw_rect(Rect2(Vector2(cx - 21.0 + bx * 14.0, crown_y - 16.0), Vector2(13.0, 10.0)), _K_FACE_MID.lerp(_K_FACE_LO, 0.3))
	# --- 4. HERSE RELEVEE : barreaux VERTICAUX courts qui pendent sous la cle ---
	for k in 5:
		var bx := cx - hw + 5.0 + k * (hw * 2.0 - 10.0) / 4.0
		var top_b := spring_y - sqrt(maxf(1.0, r_in * r_in - (bx - cx) * (bx - cx))) + 3.0
		draw_line(Vector2(bx, top_b), Vector2(bx, top_b + 12.0), _IRON, 3.0)
		draw_line(Vector2(bx - 1.0, top_b), Vector2(bx - 1.0, top_b + 12.0), _IRON.lightened(0.28), 1.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(bx - 2.5, top_b + 12.0), Vector2(bx + 2.5, top_b + 12.0), Vector2(bx, top_b + 17.0)]), _IRON)
	draw_line(Vector2(cx - hw + 3.0, spring_y - hw * 0.62), Vector2(cx + hw - 3.0, spring_y - hw * 0.62), _IRON, 2.4)  ## traverse
	# --- 5. SEUIL : dalle + ombre sur le sol de l'arene ("on entre ici") ---
	draw_rect(Rect2(Vector2(cx - hw, sill_y - 3.0), Vector2(hw * 2.0, 5.0)), _K_CAP_CORE.lerp(_K_CAP_LIT, 0.3))
	for k in 10:
		var a := 0.30 * (1.0 - k / 10.0) * (1.0 - k / 10.0)
		var sy := sill_y + toward * (2.0 + k * 3.0)
		draw_rect(Rect2(Vector2(cx - hw - k * 1.5, sy), Vector2(hw * 2.0 + k * 3.0, 2.4)), Color(0, 0, 0, a))


## Eventail de triangles couvrant un secteur d'arc (pour remplir un demi-disque).
func _arc_fan(c: Vector2, r: float, a0: float, a1: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(c)
	for i in range(n + 1):
		var g := lerpf(a0, a1, float(i) / n)
		pts.append(c + Vector2(cos(g), sin(g)) * r)
	return pts


## Bannieres cramoisies suspendues au REMPART HAUT, jamais dans le vide.
##   - COURONNE : reservees au tiers DROIT (cote roi / sortie)
##   - EPEES CROISEES : tiers GAUCHE (cote faille / entree)
func _draw_wall_banners(ci: CanvasItem) -> void:
	var top_y := (WALK_ROW_MIN - 1) * CELL + CELL * 0.30
	var bot_y := (WALK_ROW_MAX + 1) * CELL + 6.0
	# mur HAUT (cote faille) : epees croisees, de part et d'autre de la porte
	_banner_at(ci, Vector2((GATE_COL - 2) * CELL + CELL * 0.5, top_y + 2.0), 17.0, 66.0, true, 7)
	_banner_at(ci, Vector2((GATE_COL + 2) * CELL + CELL * 0.5, top_y - 2.0), 15.0, 54.0, true, 11)
	# mur BAS (cote roi) : couronnes, de part et d'autre de la porte
	_banner_at(ci, Vector2((GATE_COL - 2) * CELL + CELL * 0.5, bot_y), 15.0, 52.0, false, 3)
	_banner_at(ci, Vector2((GATE_COL + 2) * CELL + CELL * 0.5, bot_y + 2.0), 17.0, 60.0, false, 0)


func _banner_at(ci: CanvasItem, top: Vector2, hw: float, ln: float, swords: bool, sd: int) -> void:
	var sag := (_hash01(sd, 1) - 0.5) * 8.0
	var base_lean := (_hash01(sd, 2) - 0.5) * 6.0
	var tatter := 3.0 + _hash01(sd, 3) * 6.0
	# oscillation lente : le bas de l'etoffe respire
	var sway := sin(_t * (0.7 + _hash01(sd, 4) * 0.5) + sd * 1.7) * 3.5
	var lean := base_lean + sway
	# ombre portee sur le mur
	ci.draw_colored_polygon(PackedVector2Array([
		top + Vector2(-hw + 5, 3), top + Vector2(hw + 5, 3),
		top + Vector2(hw + lean + 6, ln + sag), top + Vector2(-hw + lean + 6, ln + sag - tatter)]),
		Color(0, 0, 0, 0.22))
	var pts := PackedVector2Array([
		top + Vector2(-hw, 0), top + Vector2(hw, 0),
		top + Vector2(hw + lean, ln + sag - tatter), top + Vector2(hw * 0.3 + lean, ln + sag + tatter),
		top + Vector2(0 + lean, ln + sag - tatter * 0.5),
		top + Vector2(-hw * 0.3 + lean, ln + sag + tatter), top + Vector2(-hw + lean, ln + sag - tatter)])
	ci.draw_colored_polygon(pts, _BANNER)
	ci.draw_polyline(_closed(pts), _INK, 1.6)
	# plis : bande claire d'un cote, pli d'ombre au centre
	ci.draw_colored_polygon(PackedVector2Array([
		top + Vector2(-hw, 1), top + Vector2(-hw * 0.45, 1),
		top + Vector2(-hw * 0.45 + lean, ln + sag - tatter), top + Vector2(-hw + lean, ln + sag - tatter)]),
		Color(_BANNER_LT.r, _BANNER_LT.g, _BANNER_LT.b, 0.5))
	ci.draw_colored_polygon(PackedVector2Array([
		top + Vector2(-hw * 0.15, 2), top + Vector2(hw * 0.15, 2),
		top + Vector2(hw * 0.12 + lean, ln + sag), top + Vector2(-hw * 0.12 + lean, ln + sag)]),
		Color(_BANNER_FOLD.r, _BANNER_FOLD.g, _BANNER_FOLD.b, 0.7))
	ci.draw_line(top + Vector2(-hw - 4, 0), top + Vector2(hw + 4, 0), _IRON, 3.0)
	ci.draw_circle(top + Vector2(-hw - 4, 0), 2.0, _IRON.lightened(0.3))
	ci.draw_circle(top + Vector2(hw + 4, 0), 2.0, _IRON.lightened(0.3))
	var mid := top + Vector2(lean * 0.5, ln * 0.42)
	var em := Color(0.80, 0.77, 0.68)
	if swords:
		for s: float in [-1.0, 1.0]:
			ci.draw_line(mid + Vector2(s * -9, 12), mid + Vector2(s * 9, -12), em, 2.2)
			ci.draw_line(mid + Vector2(s * 5, 14), mid + Vector2(s * 10, 14), em, 2.2)
	else:
		ci.draw_polyline(PackedVector2Array([
			mid + Vector2(-11, 7), mid + Vector2(-11, -4), mid + Vector2(-5, 3), mid + Vector2(0, -7),
			mid + Vector2(5, 3), mid + Vector2(11, -4), mid + Vector2(11, 7), mid + Vector2(-11, 7)]),
			_GOLD_LT, 2.2)


## Torches MURALES : petit brasero de fer sur le mur + halo court, jamais sur le chemin.
func _draw_wall_sconces() -> void:
	# torches sur les 4 murs, en retrait des portes
	var yT := WALK_ROW_MIN * CELL - 12.0
	var yB := (WALK_ROW_MAX + 1) * CELL + 12.0
	for c: int in [GATE_COL - 3, GATE_COL + 3]:
		_sconce(Vector2(c * CELL + CELL * 0.5, yT))
		_sconce(Vector2(c * CELL + CELL * 0.5, yB))
	for r: int in [WALK_ROW_MIN + 2, WALK_ROW_MAX - 2]:
		_sconce(Vector2(BATTLE_COL_MIN * CELL + CELL - 6.0, r * CELL + CELL * 0.5))
		_sconce(Vector2(BATTLE_COL_MAX * CELL + 6.0, r * CELL + CELL * 0.5))


func _sconce(p: Vector2) -> void:
	var fl := 0.85 + sin(_t * 6.0 + p.x * 0.2) * 0.1 + randf() * 0.04
	# platine de fer scellee dans la pierre (on voit qu'elle est FIXEE a la face)
	draw_rect(Rect2(p + Vector2(-4, -1), Vector2(8, 12)), _WALL_FACE_LO)
	draw_rect(Rect2(p + Vector2(-4, -1), Vector2(8, 12)), Color(0, 0, 0, 0.5), false, 1.0)
	draw_circle(p + Vector2(-2, 1), 1.0, _IRON.lightened(0.3))
	draw_circle(p + Vector2(2, 1), 1.0, _IRON.lightened(0.3))
	# bras + vasque
	draw_line(p + Vector2(0, 9), p + Vector2(0, -2), _IRON, 2.5)
	draw_rect(Rect2(p + Vector2(-6, -3), Vector2(12, 4)), _IRON)
	# petite flaque de lumiere chaude posee sur la pierre juste sous la torche
	for k in 3:
		var kf := float(k) / 3.0
		_ellipse(p + Vector2(0, 6.0 + kf * 6.0), 15.0 - kf * 4.0, 8.0 - kf * 2.0,
			Color(1.0, 0.66, 0.30, 0.10 * (1.0 - kf) * fl), int(p.x) + k)
	var fh := 12.0 * fl
	draw_colored_polygon(PackedVector2Array([p + Vector2(-4, -3), p + Vector2(4, -3), p + Vector2(0, -3 - fh)]), _FIRE_LOW)
	draw_colored_polygon(PackedVector2Array([p + Vector2(-2.5, -3), p + Vector2(2.5, -3), p + Vector2(0, -3 - fh * 0.62)]), _FIRE_MID)
	draw_circle(p + Vector2(0, -3 - fh * 0.32), 2.0, _FIRE_CORE)


## Sente d'usure : les pas ont creuse une trace de terre battue DANS le dallage.
## Plus SOMBRE que la pierre, translucide (le sol transparait), bords feutres,
## deux ornieres.  Jamais une bande claire uniforme (ça lisait comme un bug).
func _draw_road() -> void:
	if _trail_pts.size() < 2:
		return
	var npt := _trail_pts.size()
	# normales lissees a chaque sommet
	var nrms := PackedVector2Array()
	for i in npt:
		var dir: Vector2
		if i == 0:
			dir = (_trail_pts[1] - _trail_pts[0]).normalized()
		elif i == npt - 1:
			dir = (_trail_pts[i] - _trail_pts[i - 1]).normalized()
		else:
			dir = ((_trail_pts[i + 1] - _trail_pts[i]).normalized() + (_trail_pts[i] - _trail_pts[i - 1]).normalized()).normalized()
		nrms.append(dir.orthogonal())

	# helper local : bande le long du chemin, largeur/alpha/couleur donnes
	var band := func(w: float, col: Color) -> void:
		var poly := PackedVector2Array()
		for i in npt:
			poly.append(_trail_pts[i] + nrms[i] * w)
		for i in range(npt - 1, -1, -1):
			poly.append(_trail_pts[i] - nrms[i] * w)
		draw_colored_polygon(poly, col)

	var earth := Color(0.115, 0.092, 0.070)
	# 4 bandes concentriques : large+tres faible -> etroite+plus marquee = bord feutre
	band.call(19.0, Color(earth.r, earth.g, earth.b, 0.16))
	band.call(15.0, Color(earth.r, earth.g, earth.b, 0.22))
	band.call(10.5, Color(earth.r, earth.g, earth.b, 0.30))
	band.call(6.0, Color(0.09, 0.072, 0.055, 0.34))
	# creux central (le plus pietine)
	draw_polyline(_trail_pts, Color(0.07, 0.056, 0.044, 0.4), 4.0)
	# deux ornieres
	for sgno: float in [-1.0, 1.0]:
		var rut := PackedVector2Array()
		for i in npt:
			rut.append(_trail_pts[i] + nrms[i] * sgno * 7.0)
		draw_polyline(rut, Color(0.06, 0.048, 0.038, 0.3), 1.6)
	# quelques scuffs sombres irreguliers (pas de galets clairs)
	var d := 0.0
	for i in range(npt - 1):
		var a: Vector2 = _trail_pts[i]
		var b: Vector2 = _trail_pts[i + 1]
		var L := (b - a).length()
		if L < 0.5:
			continue
		var dir := (b - a) / L
		var nrm := dir.orthogonal()
		while d < L:
			var q := a + dir * d + nrm * (_hash01(int((a.x + d) / 13.0), int(a.y / 13.0)) - 0.5) * 22.0
			var hs := _hash01(int(q.x / 9.0) * 7 + 1, int(q.y / 9.0) * 5 + 3)
			draw_circle(q, 2.0 + hs * 3.5, Color(0.06, 0.05, 0.04, 0.22))
			# leger reflet chaud SEULEMENT si bien eclaire (la terre humide luit un peu)
			var pl := lit_at(q)
			if pl > 0.4:
				draw_circle(q, 1.6, Color(0.9, 0.66, 0.36, (pl - 0.4) * 0.18))
			d += 16.0 + hs * 10.0
		d -= L


## Details de zones : galerie de mine (etais + veine + wagonnet) ; champ de ble.
func _draw_zone_details() -> void:
	pass   ## economie deplacee dans la fenetre FERME

## Faille : une DECHIRURE verticale crepitante logee DANS la gueule de l'arche
## (l'arche est dessinee par _gate_arch).  Lueur froide qui deborde vers l'arene.
func _draw_rift(ci: CanvasItem) -> void:
	var pc := RIFT_ANCHOR
	var glow := 0.5 + 0.5 * sin(_t * 1.4)
	var tear_c := Color(0.55, 0.98, 0.80)
	# 1. halo froid : CONTENU dans l'ouverture, deborde juste un peu vers l'est (l'arene)
	for i in range(5, 0, -1):
		_ellipse(pc + Vector2(6.0, 0), (7.0 + i * 4.5), (10.0 + i * 5.0),
			Color(_RIFT_OUTER.r, _RIFT_OUTER.g * 1.1, _RIFT_OUTER.b, (0.030 + i * 0.012 + glow * 0.012)), 90 + i, ci)
	# 2. la dechirure : fente verticale irreguliere qui pulse
	var tw := 4.0 + glow * 2.5
	var lp := PackedVector2Array()
	var rp := PackedVector2Array()
	for s in 9:
		var f := float(s) / 8.0
		var yy := pc.y - 30.0 + f * 60.0
		var w := tw * sin(f * PI) * (1.0 + (_hash01(s, int(_t * 3.0) % 7) - 0.5) * 0.6)
		lp.append(Vector2(pc.x - w, yy))
		rp.append(Vector2(pc.x + w, yy))
	var poly := lp.duplicate()
	for s in range(rp.size() - 1, -1, -1):
		poly.append(rp[s])
	ci.draw_colored_polygon(poly, Color(0.02, 0.06, 0.05, 0.95))
	ci.draw_polyline(lp, Color(tear_c.r, tear_c.g, tear_c.b, 0.7 + glow * 0.3), 1.6)
	ci.draw_polyline(rp, Color(tear_c.r * 0.7, tear_c.g, tear_c.b, 0.6 + glow * 0.3), 1.4)
	# 3. crepitement interne + coeur (jamais blanc pur)
	for k in 4:
		var ph := fposmod(_t * 0.6 + k * 0.25, 1.0)
		var sy := pc.y + 26.0 - ph * 52.0
		ci.draw_line(Vector2(pc.x - 2.0, sy), Vector2(pc.x + 2.0, sy - 3.0), Color(tear_c.r, tear_c.g, tear_c.b, (1.0 - ph) * 0.5), 1.4)
	ci.draw_circle(pc, 2.0 + glow * 1.0, Color(0.66, 0.94, 0.82, 0.55))
	# 4. braises froides qui montent et derivent vers l'est
	for k in 6:
		var ph2 := fposmod(_t * 0.3 + k * 0.4, 1.0)
		var ex := pc + Vector2((_hash01(k, 2) - 0.4) * 20.0 + ph2 * 16.0, 22.0 - ph2 * 46.0)
		ci.draw_circle(ex, (1.0 - ph2) * 1.6, Color(_RIFT_CRACK.r, _RIFT_CRACK.g, _RIFT_CRACK.b, (1.0 - ph2) * 0.35))


## Trone du roi : LOGE dans la porte BASSE, face a l'arene (le ROI regarde monter
## les ennemis).  Perron + tapis cramoisi qui remontent vers le NORD (l'arene).
func _draw_throne() -> void:
	var T := THRONE_ANCHOR                          ## centre de la porte basse
	var pulse := 0.5 + 0.5 * sin(_t * 2.2)
	var floor_y := (WALK_ROW_MAX + 1) * CELL        ## y du sol de l'arene au mur bas

	# 1. perron : marche basse qui avance vers le NORD dans le hall
	var pd := 26.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(T.x - 20.0, floor_y + pd), Vector2(T.x + 20.0, floor_y + pd),
		Vector2(T.x + 20.0, floor_y + pd - 10.0), Vector2(T.x - 20.0, floor_y + pd - 10.0)]),
		_WALL_FACE.lerp(_WALL_FACE_LO, 0.3))                          ## contremarche
	draw_colored_polygon(PackedVector2Array([
		Vector2(T.x - 26.0, floor_y - 4.0), Vector2(T.x + 26.0, floor_y - 4.0),
		Vector2(T.x + 20.0, floor_y + pd - 10.0), Vector2(T.x - 20.0, floor_y + pd - 10.0)]),
		_STONE_HI.lerp(_GOLD_LT, 0.14))                              ## giron eclaire
	draw_line(Vector2(T.x - 26.0, floor_y - 4.0), Vector2(T.x + 26.0, floor_y - 4.0), Color(_EDGE_HI.r, _EDGE_HI.g, _EDGE_HI.b, 0.9), 2.0)
	# tapis cramoisi : remonte vers le nord, s'affine et disparait avant la ligne du mur
	var carpet_end := floor_y - 6.0
	for st in 5:
		var t0 := float(st) / 5.0
		var ya := lerpf(T.y, carpet_end, t0)
		var yb := lerpf(T.y, carpet_end, t0 + 0.22)
		var hwid := lerpf(11.0, 3.0, t0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(T.x - hwid, ya), Vector2(T.x + hwid, ya),
			Vector2(T.x + hwid, yb), Vector2(T.x - hwid, yb)]),
			Color(_BANNER_FOLD.r, _BANNER_FOLD.g, _BANNER_FOLD.b, (1.0 - t0) * (1.0 - t0) * 0.85))

	# 2. TRONE : icone simple.  Le dossier monte vers le SUD (+y), le roi devant, face au nord.
	var seat := Vector2(T.x, T.y - 2.0)
	var bh := 30.0
	var back := PackedVector2Array([
		seat + Vector2(-13, -8), seat + Vector2(-13, bh - 6), seat + Vector2(-9, bh),
		seat + Vector2(9, bh), seat + Vector2(13, bh - 6), seat + Vector2(13, -8)])
	draw_colored_polygon(back, Color(0.275, 0.205, 0.150))
	draw_colored_polygon(PackedVector2Array([                                       ## moitie droite : ombre
		seat + Vector2(2, -8), seat + Vector2(2, bh - 4), seat + Vector2(9, bh), seat + Vector2(13, bh - 6), seat + Vector2(13, -8)]),
		Color(0.165, 0.125, 0.095))
	draw_line(seat + Vector2(-13, bh - 6), seat + Vector2(-9, bh), Color(_GOLD_LT.r, _GOLD_LT.g, _GOLD_LT.b, 0.5), 1.4)
	# fronton d'or au sommet (sud) du dossier
	draw_colored_polygon(PackedVector2Array([seat + Vector2(-9, bh), seat + Vector2(9, bh), seat + Vector2(0, bh + 8.0)]), Color(0.235, 0.185, 0.140))
	draw_line(seat + Vector2(-9, bh), seat + Vector2(0, bh + 8.0), Color(_GOLD_LT.r, _GOLD_LT.g, _GOLD_LT.b, 0.7), 1.6)
	draw_line(seat + Vector2(0, bh + 8.0), seat + Vector2(9, bh), Color(_GOLD.r, _GOLD.g, _GOLD.b, 0.6), 1.4)
	# accotoirs
	for sgna: float in [-1.0, 1.0]:
		draw_rect(Rect2(Vector2(seat.x + sgna * 13.0 - (0.0 if sgna > 0 else 5.0), seat.y - 4.0), Vector2(5.0, 12.0)), Color(0.21, 0.155, 0.115))
	draw_rect(Rect2(seat + Vector2(-9, -4), Vector2(18.0, 8.0)), _BANNER)             ## coussin

	# 3. LE ROI : tete sombre couronnee devant le dossier, face au nord (l'arene)
	var kingp := seat + Vector2(0, 2.0)
	var breath := sin(_t * 1.3) * 0.6
	draw_rect(Rect2(kingp + Vector2(-5, -2 + breath), Vector2(10.0, 9.0)), Color(0.075, 0.055, 0.062))  ## epaules
	draw_circle(kingp + Vector2(0, -6.0 + breath), 4.6, Color(0.085, 0.062, 0.070))                     ## tete
	draw_arc(kingp + Vector2(0, -6.0 + breath), 4.6, PI * 1.1, PI * 1.95, 10, Color(1.0, 0.85, 0.58, 0.8), 1.6)  ## rim chaud (nord)
	draw_colored_polygon(PackedVector2Array([                                       ## couronne (nord de la tete)
		kingp + Vector2(-5, -9 + breath), kingp + Vector2(5, -9 + breath),
		kingp + Vector2(4, -13 + breath), kingp + Vector2(2, -11 + breath),
		kingp + Vector2(0, -15 + breath), kingp + Vector2(-2, -11 + breath), kingp + Vector2(-4, -13 + breath)]),
		_GOLD_LT)

	# 4. 2 petits braseros de part et d'autre, halo chaud minimal
	for sgnb: float in [-1.0, 1.0]:
		var bpz := Vector2(T.x + sgnb * 20.0, T.y + 2.0)
		draw_line(bpz + Vector2(0, 8), bpz + Vector2(0, -1), _IRON, 2.0)
		var flf := 0.82 + sin(_t * 8.0 + sgnb) * 0.18
		draw_colored_polygon(PackedVector2Array([
			bpz + Vector2(-2.2, -1), bpz + Vector2(2.2, -1), bpz + Vector2(0, -8 * flf)]), _FIRE_LOW)
		draw_colored_polygon(PackedVector2Array([
			bpz + Vector2(-1.4, -1), bpz + Vector2(1.4, -1), bpz + Vector2(0, -5 * flf)]), _FIRE_MID)
	for i in range(3, 0, -1):
		_ellipse(seat + Vector2(0, 4), 9.0 + i * 4.0, (6.0 + i * 3.0),
			Color(1.0, 0.76, 0.38, 0.024 + (3 - i) * 0.009 + pulse * 0.007), 40 + i)
	# feedback : PV bas -> le dossier vire au sang
	var frac := clampf(float(GameState.king_hp) / float(maxi(1, GameState.king_max)), 0.0, 1.0)
	if frac < 0.55:
		var dmg := (0.55 - frac) / 0.55
		draw_colored_polygon(back, Color(_BANNER.r, _BANNER.g * 0.4, _BANNER.b * 0.4, dmg * 0.45))


func _draw_labels() -> void:
	pass   ## labels d'economie deplaces dans la fenetre FERME


func _zone_label(pos: Vector2, txt: String) -> void:
	var w := txt.length() * 7.0 + 12.0
	draw_rect(Rect2(pos - Vector2(6, 12), Vector2(w, 16)), Color(0.06, 0.06, 0.05, 0.7))
	draw_rect(Rect2(pos - Vector2(6, 12), Vector2(w, 16)), Color(_INK.r, _INK.g, _INK.b, 0.8), false, 1.0)
	draw_string(ThemeDB.fallback_font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.72, 0.68, 0.58))


## Repere de pose : au centre des cases libres, seulement pendant le placement.
func _draw_place_dots(ci: CanvasItem) -> void:
	if pending_tool == "":
		return
	var cat := Catalog.cat(pending_tool)
	if cat != "tower" and cat != "fighter":
		return
	for c in range(BUILD_COL_MIN, BUILD_COL_MAX + 1):
		for r in range(WALK_ROW_MIN, WALK_ROW_MAX + 1):
			if occupied.has(Vector2i(c, r)):
				continue
			var p := Vector2(c * CELL + CELL * 0.5, r * CELL + CELL * 0.5)
			ci.draw_line(p - Vector2(3, 0), p + Vector2(3, 0), Color(0.85, 0.82, 0.72, 0.3), 1.0)
			ci.draw_line(p - Vector2(0, 3), p + Vector2(0, 3), Color(0.85, 0.82, 0.72, 0.3), 1.0)


## Brume : plans qui reculent (haut = plus brumeux) + halos qui montent.
func _draw_haze(ci: CanvasItem) -> void:
	var bs := board_size()
	# le haut du plateau (mur du fond) recule dans une brume gris-vert froide
	for i in 12:
		var f := float(i) / 12.0
		ci.draw_rect(Rect2(Vector2(0, f * CELL * 3.0), Vector2(bs.x, CELL * 0.35)),
			Color(0.34, 0.40, 0.37, 0.06 * (1.0 - f)))
	# brume tiede qui monte de la faille et du trone
	var rp := RIFT_ANCHOR
	var kp := THRONE_ANCHOR
	for i in 5:
		var ph := fposmod(_t * 0.04 + i * 0.2, 1.0)
		_ellipse(rp + Vector2(6, -ph * 60.0), 30.0 - ph * 10.0, 14.0, Color(_RIFT_OUTER.r, _RIFT_OUTER.g, _RIFT_OUTER.b, (1.0 - ph) * 0.06), 810 + i, ci)
		_ellipse(kp + Vector2(-6, -ph * 60.0), 34.0 - ph * 10.0, 15.0, Color(_GOLD.r, _GOLD.g, _GOLD.b, (1.0 - ph) * 0.045), 820 + i, ci)


## Masquage : la vignette globale est faite par le post-process ; ici on ne
## garde que l'assombrissement des bandes NON JOUABLES du plateau.
func _draw_vignette() -> void:
	var bs := board_size()
	# assombrit tout ce qui entoure l'arene jouable (4 cotes)
	draw_rect(Rect2(Vector2.ZERO, Vector2(bs.x, (WALK_ROW_MIN - 1) * CELL)), Color(0, 0, 0, 0.28))
	draw_rect(Rect2(Vector2(0, (WALK_ROW_MAX + 2) * CELL), Vector2(bs.x, bs.y)), Color(0, 0, 0, 0.30))
	draw_rect(Rect2(Vector2.ZERO, Vector2((BATTLE_COL_MIN) * CELL, bs.y)), Color(0, 0, 0, 0.26))
	draw_rect(Rect2(Vector2((BATTLE_COL_MAX + 1) * CELL, 0), Vector2(bs.x, bs.y)), Color(0, 0, 0, 0.26))


func _refresh_trail() -> void:
	_trail_pts = enemy_path()
	# la sente visuelle relie la faille (haut) au trone (bas)
	if _trail_pts.size() >= 2:
		_trail_pts[0] = RIFT_ANCHOR + Vector2(0, 10)
		_trail_pts[_trail_pts.size() - 1] = THRONE_ANCHOR + Vector2(0, -18)
	_static_dirty = true


func _draw_synergy() -> void:
	for c in occupied:
		var t = occupied[c]
		if not (t is Tower) or t.synergy == 0:
			continue
		var a := cell_to_world(c)
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var o = occupied.get(c + d)
			if o is Tower and o.type_id == t.type_id:
				var col: Color = t.body_color
				draw_line(a, cell_to_world(c + d), Color(col.r, col.g, col.b, 0.5), 3.0)


func _draw_path_hint(ci: CanvasItem) -> void:
	# n'apparait que pendant le placement d'une tour : chevrons discrets qui
	# indiquent le sens de marche (jamais une ligne pointillee facon debug).
	if GameState.finished or pending_tool == "":
		return
	var path := enemy_path()
	if path.size() < 2:
		return
	var march := Color(0.86, 0.66, 0.34, 0.28)
	for i in range(path.size() - 1):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var seg := b - a
		var length := seg.length()
		if length < 0.01:
			continue
		var dir := seg / length
		var nrm := dir.orthogonal()
		var d: float = fmod(_t * 26.0, 46.0)
		while d < length:
			var q := a + dir * d
			ci.draw_polyline(PackedVector2Array([q - dir * 5.0 + nrm * 4.0, q, q - dir * 5.0 - nrm * 4.0]), march, 1.6)
			d += 46.0


func _draw_hover(ci: CanvasItem) -> void:
	if pending_tool == "" or not in_bounds(hover_cell):
		return
	var ok := can_build(pending_tool, hover_cell)
	var origin := Vector2(hover_cell.x * CELL, hover_cell.y * CELL)
	var tint := Color(0.30, 0.90, 0.40, 0.18) if ok else Color(0.90, 0.30, 0.30, 0.14)
	ci.draw_rect(Rect2(origin, Vector2(CELL, CELL)), tint)
	ci.draw_rect(Rect2(origin, Vector2(CELL, CELL)),
		Color(1, 1, 1, 0.25) if ok else Color(0.9, 0.35, 0.35, 0.4), false, 1.5)
	if ok:
		_draw_ghost(ci, hover_cell)


func _draw_ghost(ci: CanvasItem, cell: Vector2i) -> void:
	var c := cell_to_world(cell)
	var col := Catalog.color(pending_tool)
	col.a = 0.45
	match Catalog.cat(pending_tool):
		"tower":
			var rng := Tower.base_range(pending_tool)
			ci.draw_circle(c, rng, Color(col.r, col.g, col.b, 0.06))
			ci.draw_arc(c, rng, 0.0, TAU, 56, Color(col.r, col.g, col.b, 0.4), 1.5)
			ci.draw_rect(Rect2(c - Vector2(27, 27), Vector2(54, 54)), col)
		"fighter":
			var frng := Fighter.base_range(pending_tool)
			ci.draw_circle(c, frng, Color(col.r, col.g, col.b, 0.06))
			ci.draw_arc(c, frng, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.4), 1.5)
			ci.draw_circle(c, 12.0, col)
		_:
			ci.draw_circle(c, 12.0, col)


## Calque additif : nappes de lumiere douces + hotspots quasi-blancs.
class _LightLayer extends Node2D:
	var arena: Node2D
	var _t := 0.0
	var _acc := 0.0
	var _web := OS.has_feature("web")

	func _process(delta: float) -> void:
		_t += delta
		_acc += delta
		if _acc >= (0.05 if _web else 0.0):     ## ~20 fps sur web
			_acc = 0.0
			queue_redraw()

	func _draw() -> void:
		if arena == null:
			return
		var layers := 10 if _web else 26
		for L in arena.light_sources():
			var p: Vector2 = L["p"]
			var col: Color = L["col"]
			var r: float = L["r"]
			var xlo: float = L.get("xmin", -1e9)
			var xhi: float = L.get("xmax", 1e9)
			# semence propre a la source -> chaque foyer a sa taille / son rythme / sa forme
			var s0: float = sin((p.x * 0.113 + p.y * 0.071) * 12.9898) * 43758.5453
			var lseed: float = s0 - floor(s0)
			var size_var: float = 0.82 + lseed * 0.4                 ## 0.82 .. 1.22
			var speed: float = 3.4 + lseed * 3.2
			var fl: float = 0.90 + sin(_t * speed + lseed * 6.28) * 0.06 + randf() * 0.02
			var rr: float = r * size_var
			# falloff doux : N couches fines -> aucun bord de polygone visible
			for i in range(layers, 0, -1):
				var f: float = float(i) / float(layers)
				var a: float = (1.0 - f) * (1.0 - f) * (0.033 * 26.0 / float(layers))
				_blob(p, rr * f * fl, Color(col.r, col.g, col.b, a), 40 + i + int(p.x * 0.1), 0.05 + lseed * 0.04, xlo, xhi)
			# coeur : JAMAIS blanc, jamais sature -> garde la teinte de la source
			_blob(p, 14.0 * size_var * fl, Color(col.r * 0.9 + 0.06, col.g * 0.82 + 0.04, col.b * 0.6, 0.14), 6, 0.10, xlo, xhi)
			_blob(p, (5.0 + lseed * 2.0) * fl, Color(col.r * 0.95 + 0.05, col.g * 0.85, col.b * 0.6 + 0.05, 0.2), 4, 0.08, xlo, xhi)

	func _blob(c: Vector2, rad: float, col: Color, sd: int, rough: float, xlo := -1e9, xhi := 1e9) -> void:
		var pts := PackedVector2Array()
		var n := 30
		for i in n:
			var ang: float = i * TAU / n
			var raw: float = sin(float(sd * 7 + i * 3) * 12.9898) * 43758.5453
			var hh: float = raw - floor(raw)
			var jr: float = 1.0 + (hh - 0.5) * 2.0 * rough
			var vp: Vector2 = c + Vector2(cos(ang), sin(ang)) * rad * jr
			vp.x = clampf(vp.x, xlo, xhi)                            ## clip -> pas de bave sur MINES/CHAMPS
			pts.append(vp)
		draw_colored_polygon(pts, col)


## Redessine la couronne des murs (merlons) par-dessus le calque additif : la lueur
## des torches est coupee net par la maconnerie.  STATIQUE -> ne se redessine qu'a
## la pose (via arena._static_dirty, propage par _sync_layers).
class _CrownLayer extends Node2D:
	var arena: Node2D
	func _draw() -> void:
		if arena != null:
			arena._draw_wall_crown(self)


## Calque des elements ANIMES : faille, brume, chevrons de sens, survol, bannieres
## qui ondulent.  Redraw a ~30 fps (web) / chaque frame (natif).
class _ArenaFx extends Node2D:
	var arena: Node2D
	var _acc := 0.0
	var _dt := 0.033 if OS.has_feature("web") else 0.0
	func _process(d: float) -> void:
		_acc += d
		if _acc >= _dt:
			_acc = 0.0
			queue_redraw()
	func _draw() -> void:
		if arena != null:
			arena._draw_fx(self)
