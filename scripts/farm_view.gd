class_name FarmView
extends Node2D
## La FERME : vue plein-ecran (onglet) de l'economie du royaume, 3 zones fortifiees
## empilees.  MINE (peons -> minerai, lueur bleue), CHAMP (fermiers -> ble, lueur verte),
## GARNISON (casernes -> troupes, lueur rouge, mode DUEL).
##
## Rendu en 2 calques : `_static` (sol / remparts / portails / props fixes, redessine
## seulement sur changement d'etat) + `FarmView._draw()` (anime : lueurs, ailes du moulin,
## braises, bannieres, particules, survol).  Meme maconnerie que l'arene (`WallKit`).

const CELL := 64.0
const COLS := 12
const ROWS := 13

const ZONES := [
	{"id": "mine",  "cat": "peon",    "r0": 1, "r1": 3,  "glow": Color(0.36, 0.62, 1.00), "label": "MINE",     "glyph": 0},
	{"id": "champ", "cat": "fermier", "r0": 5, "r1": 7,  "glow": Color(0.46, 0.95, 0.55), "label": "FERME",    "glyph": 1},
	{"id": "garn",  "cat": "caserne", "r0": 9, "r1": 11, "glow": Color(0.95, 0.42, 0.30), "label": "GARNISON", "glyph": 2},
]
const PLAY_COL_MIN := 1
const PLAY_COL_MAX := 10

# -- pierre (rappel WallKit, pour les faces internes) --
const K_WARM     := Color(1.000, 0.600, 0.270)
const K_DEEP     := Color(0.045, 0.045, 0.050)

# -- MINE : roche taillee froide --
const F_ROCK      := Color(0.200, 0.205, 0.225)
const F_ROCK_LO   := Color(0.118, 0.126, 0.148)
const F_ROCK_DEEP := Color(0.090, 0.105, 0.155)
const F_VEIN      := Color(0.42, 0.62, 1.00)
# -- FERME : terre labouree + jachere --
const F_SOIL      := Color(0.300, 0.238, 0.140)
const F_SOIL_LO   := Color(0.176, 0.148, 0.092)
const F_TURF      := Color(0.244, 0.300, 0.140)
const F_TURF_LO   := Color(0.150, 0.196, 0.096)
# -- GARNISON : terre battue + dalles --
const F_DUST      := Color(0.300, 0.250, 0.192)
const F_DUST_LO   := Color(0.180, 0.150, 0.116)
const F_DUST_PALE := Color(0.340, 0.292, 0.240)
const F_FLAG      := Color(0.334, 0.320, 0.298)
# -- bois / chaume / feu / etoffe --
const F_TIMBER    := Color(0.300, 0.222, 0.140)
const F_TIMBER_LO := Color(0.226, 0.166, 0.104)
const F_THATCH    := Color(0.560, 0.446, 0.244)
const F_THATCH_LO := Color(0.404, 0.316, 0.170)
const F_HAY       := Color(0.740, 0.580, 0.300)
const F_HAY_DK    := Color(0.440, 0.350, 0.180)
const F_FIRE_LOW  := Color(0.700, 0.240, 0.090)
const F_FIRE_MID  := Color(0.980, 0.580, 0.220)
const F_BANNER    := Color(0.478, 0.082, 0.094)
const F_IRON      := Color(0.090, 0.085, 0.090)
const F_MORTAR    := Color(0.140, 0.130, 0.120)

var occupied: Dictionary = {}
var pending_tool := "":
	set(v):
		if v == pending_tool:
			return
		pending_tool = v
		_static_dirty = true
var hover_cell := Vector2i(-1, -1):
	set(v):
		if v == hover_cell:
			return
		hover_cell = v
		_static_dirty = true

var _t := 0.0
var _static_dirty := true
var _static: _FarmStatic = null
var _lights: Node2D = null


func _ready() -> void:
	y_sort_enabled = true
	_static = _FarmStatic.new()
	_static.farm = self
	_static.z_index = -1        ## derriere le _draw() dynamique de FarmView
	_static.y_sort_enabled = false
	add_child(_static)
	_lights = _FarmLight.new()
	_lights.farm = self
	_lights.z_index = 2         ## additif, au-dessus de tout
	var lm := CanvasItemMaterial.new()
	lm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_lights.material = lm
	add_child(_lights)


var _redraw_acc := 0.0
var _redraw_dt := 0.04 if OS.has_feature("web") else 0.0   ## ~25 fps de redraw sur web

func _process(delta: float) -> void:
	_t += delta
	_redraw_acc += delta
	if _redraw_acc >= _redraw_dt:
		_redraw_acc = 0.0
		queue_redraw()
	if _static_dirty and is_instance_valid(_static):
		_static_dirty = false
		_static.queue_redraw()


# --- geometrie / API ----------------------------------------------------

func board_size() -> Vector2:
	return Vector2(COLS * CELL, ROWS * CELL)


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * CELL + CELL * 0.5, cell.y * CELL + CELL * 0.5)


func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))


func _zone_rect(z: Dictionary) -> Rect2:
	return Rect2(Vector2(PLAY_COL_MIN * CELL, z["r0"] * CELL),
		Vector2((PLAY_COL_MAX - PLAY_COL_MIN + 1) * CELL, (z["r1"] - z["r0"] + 1) * CELL))


func _zone_of_cell(cell: Vector2i) -> Dictionary:
	for z in ZONES:
		if cell.x >= PLAY_COL_MIN and cell.x <= PLAY_COL_MAX and cell.y >= z["r0"] and cell.y <= z["r1"]:
			return z
	return {}


func _zone_for_cat(cat: String) -> Dictionary:
	for z in ZONES:
		if z["cat"] == cat:
			return z
	return {}


# --- placement --------------------------------------------------------

func can_build(id: String, cell: Vector2i) -> bool:
	if occupied.has(cell):
		return false
	var cat := Catalog.cat(id)
	var z := _zone_of_cell(cell)
	if z.is_empty() or z["cat"] != cat:
		return false
	match cat:
		"peon":
			return get_tree().get_nodes_in_group("peons").size() < Meta.peon_max
		"fermier":
			return get_tree().get_nodes_in_group("fermiers").size() < Meta.peon_max
		"caserne":
			return GameState.mode == GameState.Mode.DUEL
	return false


func place(id: String, cell: Vector2i) -> Node2D:
	var n: Node2D
	match Catalog.cat(id):
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
		_:
			return null
	var is_caserne := n is Caserne
	n.position = cell_to_world(cell)
	add_child(n)
	occupied[cell] = n
	_static_dirty = true
	n.tree_exited.connect(func() -> void:
		if occupied.get(cell) == n:
			occupied.erase(cell)
			_static_dirty = true
			if is_caserne:
				_recompute_casernes())
	if is_caserne:
		_recompute_casernes()
	return n


func _recompute_casernes() -> void:
	var counts: Dictionary = {}
	for c in occupied:
		var o = occupied[c]
		if o is Caserne:
			counts[o.troop] = int(counts.get(o.troop, 0)) + 1
	Versus.unlocked.clear()
	for troop_id in counts:
		Versus.unlocked[troop_id] = counts[troop_id]
	Versus.changed.emit()


# --- lumiere ---------------------------------------------------------

func light_sources() -> Array:
	var out := []
	for zi in ZONES.size():
		var z: Dictionary = ZONES[zi]
		var zr := _zone_rect(z)
		var cy := zr.get_center().y
		var ymin := zr.position.y - 24.0
		var ymax := zr.end.y + 24.0
		# portail magique (bord gauche), clippe a la zone
		out.append({"p": Vector2(zr.position.x + 10.0, cy), "col": z["glow"], "r": 138.0, "ymin": ymin, "ymax": ymax})
		# 2 braseros muraux a gauche
		out.append({"p": Vector2(zr.position.x - TH * 0.5, cy - 62.0), "col": Color(1.0, 0.58, 0.24), "r": 112.0, "ymin": ymin, "ymax": ymax})
		out.append({"p": Vector2(zr.position.x - TH * 0.5, cy + 62.0), "col": Color(1.0, 0.58, 0.24), "r": 112.0, "ymin": ymin, "ymax": ymax})
		# lumiere de travail au prop-hero
		match z["id"]:
			"mine":
				out.append({"p": zr.position + Vector2(zr.size.x - 66.0, 22.0), "col": Color(0.55, 0.66, 0.98), "r": 78.0, "ymin": ymin, "ymax": ymax})
			"champ":
				out.append({"p": zr.position + Vector2(zr.size.x - 74.0, zr.size.y - 46.0), "col": Color(1.0, 0.74, 0.40), "r": 90.0, "ymin": ymin, "ymax": ymax})
			"garn":
				out.append({"p": zr.position + Vector2(52.0, zr.size.y - 40.0), "col": Color(1.0, 0.48, 0.18), "r": 122.0, "ymin": ymin, "ymax": ymax})
	return out


func _clipped(L: Dictionary, p: Vector2) -> bool:
	return (L.has("ymin") and p.y < L["ymin"]) or (L.has("ymax") and p.y > L["ymax"])


func lit_at(p: Vector2) -> float:
	var best := 0.0
	for L in light_sources():
		if _clipped(L, p):
			continue
		var x: float = clampf(1.0 - p.distance_to(L["p"]) / L["r"], 0.0, 1.0)
		best = maxf(best, x * x * (3.0 - 2.0 * x))
	return best


func nearest_light_col(p: Vector2) -> Color:
	var bd := 1e9
	var bc := Color(1.0, 0.62, 0.26)
	for L in light_sources():
		if _clipped(L, p):
			continue
		var d: float = p.distance_to(L["p"])
		if d < bd:
			bd = d
			bc = L["col"]
	return bc


func _wall_warm(p: Vector2) -> float:
	var w := 0.0
	for L in light_sources():
		var col: Color = L["col"]
		if col.b > col.r:
			continue
		if _clipped(L, p):
			continue
		w = maxf(w, clampf(1.0 - p.distance_to(L["p"]) / (L["r"] * 0.55), 0.0, 1.0))
	return w * w


func _hash01(a: int, b: int) -> float:
	return WallKit.hash01(a, b)


func _ellipse(c: Vector2, rx: float, ry: float, col: Color, sd: int) -> void:
	WallKit.ellipse(self, c, rx, ry, col, sd)


# ====================================================================
#  CALQUE STATIQUE
# ====================================================================

func draw_static(ci: CanvasItem) -> void:
	var bs := board_size()
	ci.draw_rect(Rect2(Vector2(-48, -48), bs + Vector2(96, 96)), Palette.BG)
	ci.draw_rect(Rect2(Vector2.ZERO, bs), K_DEEP)
	_draw_global_grade(ci)
	for z in ZONES:
		_zone_floor(ci, z)
		_zone_tint(ci, z)
		_zone_ground_decor(ci, z)
	_draw_ramparts(ci)
	for z in ZONES:
		_zone_props_static(ci, z)
		_zone_gate_masonry(ci, z)
		_zone_vignette(ci, z)
	# reperes de pose
	if pending_tool != "":
		var z := _zone_for_cat(Catalog.cat(pending_tool))
		if not z.is_empty():
			var zr := _zone_rect(z)
			ci.draw_rect(zr, Color(0, 0, 0, 0.12))
			for c in range(PLAY_COL_MIN, PLAY_COL_MAX + 1):
				for r in range(z["r0"], z["r1"] + 1):
					if occupied.has(Vector2i(c, r)):
						continue
					var p := Vector2(c * CELL + CELL * 0.5, r * CELL + CELL * 0.5)
					ci.draw_line(p - Vector2(3, 0), p + Vector2(3, 0), Color(0.95, 0.88, 0.72, 0.4), 1.0)
					ci.draw_line(p - Vector2(0, 3), p + Vector2(0, 3), Color(0.95, 0.88, 0.72, 0.4), 1.0)


func _draw_global_grade(ci: CanvasItem) -> void:
	var bs := board_size()
	for k in 10:
		var f := float(k) / 9.0
		var col: Color
		if f < 0.5:
			col = Color(0.04, 0.05, 0.09, lerpf(0.12, 0.015, f / 0.5))
		else:
			col = Color(0.12, 0.05, 0.02, lerpf(0.015, 0.085, (f - 0.5) / 0.5))
		ci.draw_rect(Rect2(Vector2(0, f * bs.y), Vector2(bs.x, bs.y / 9.0 + 1.0)), col)


func _zone_floor(ci: CanvasItem, z: Dictionary) -> void:
	var zid: String = z["id"]
	var r0: int = z["r0"]
	var r1: int = z["r1"]
	var zr := _zone_rect(z)
	var gc := zr.get_center()
	for c in range(PLAY_COL_MIN, PLAY_COL_MAX + 1):
		for r in range(r0, r1 + 1):
			var o := Vector2(c * CELL, r * CELL)
			var ctr := o + Vector2(CELL * 0.5, CELL * 0.5)
			var h := _hash01(c * 7 + 3, r * 5 + 1)
			var h2 := _hash01(c * 13 + 1, r * 3 + 7)
			var lit := lit_at(ctr)
			match zid:
				"mine":
					_tile_mine(ci, o, ctr, h, h2, lit)
				"champ":
					_tile_champ(ci, o, ctr, c, r, h, h2, lit)
				"garn":
					_tile_garn(ci, o, ctr, c, r, r0, r1, gc, h, h2, lit)


func _tile_mine(ci: CanvasItem, o: Vector2, ctr: Vector2, h: float, h2: float, lit: float) -> void:
	var m := 1.6 + h2 * 1.8
	var jx := (h - 0.5) * 3.0
	var jy := (h2 - 0.5) * 3.0
	var pts := PackedVector2Array([
		o + Vector2(m + jx, m + jy), o + Vector2(CELL - m + jy, m - jx * 0.5),
		o + Vector2(CELL - m - jx, CELL - m + jy), o + Vector2(m + jy * 0.5, CELL - m - jx)])
	var fill := F_ROCK_LO.lerp(F_ROCK, clampf(0.24 + lit * 0.95, 0.10, 1.0)).lerp(F_ROCK_DEEP, h * 0.32)
	if lit > 0.06:
		fill = fill.lerp(nearest_light_col(ctr), lit * lit * 0.20)
	ci.draw_colored_polygon(pts, fill)
	ci.draw_line(pts[2], pts[3], Color(0.05, 0.06, 0.09, 0.5), 1.0)
	ci.draw_line(pts[1], pts[2], Color(0.05, 0.06, 0.09, 0.4), 1.0)
	ci.draw_line(pts[0], pts[1], Color(0.55, 0.70, 1.0, 0.05), 1.0)
	ci.draw_line(pts[0], pts[3], Color(0.55, 0.70, 1.0, 0.045), 1.0)
	if h2 > 0.90:
		ci.draw_line(o + Vector2(8 + h * 34, 6), o + Vector2(20 + h2 * 24, CELL - 6), Color(0.05, 0.06, 0.08, 0.5), 1.0)
	if h < 0.13:
		for k in 3:
			var gp := ctr + Vector2((_hash01(int(o.x) + k, int(o.y)) - 0.5) * 34.0, (_hash01(int(o.x), int(o.y) + k) - 0.5) * 34.0)
			ci.draw_circle(gp, 0.9 + _hash01(k, int(o.x)) * 1.2, Color(F_VEIN.r, F_VEIN.g, F_VEIN.b, 0.55))
	if h2 < 0.12:
		ci.draw_circle(ctr + Vector2(6, 4), 2.4 + h * 2.0, F_ROCK_LO.darkened(0.25))
		ci.draw_circle(ctr + Vector2(-5, -3), 1.8, F_ROCK.darkened(0.1))


func _tile_champ(ci: CanvasItem, o: Vector2, ctr: Vector2, c: int, r: int, h: float, h2: float, lit: float) -> void:
	var bh := _hash01((c >> 1) * 9 + 1, (r >> 1) * 7 + 2)
	var plowed := bh < 0.55
	var base := (F_SOIL_LO.lerp(F_SOIL, clampf(0.30 + lit * 0.85, 0.12, 1.0))) if plowed \
		else (F_TURF_LO.lerp(F_TURF, clampf(0.30 + lit * 0.85, 0.12, 1.0)))
	if lit > 0.06:
		base = base.lerp(nearest_light_col(ctr), lit * lit * 0.12)
	base = base.lerp(base.lightened(0.10), h * h)
	ci.draw_rect(Rect2(o + Vector2(1.5, 1.5), Vector2(CELL - 3.0, CELL - 3.0)), base)
	if plowed:
		for k in 3:
			var ly := o.y + (k + 0.5) * CELL / 3.0 + sin(float(c + k)) * 1.2
			ci.draw_line(Vector2(o.x + 3, ly), Vector2(o.x + CELL - 3, ly), Color(0.13, 0.09, 0.05, 0.42), 1.4)
			ci.draw_line(Vector2(o.x + 3, ly - 1.6), Vector2(o.x + CELL - 3, ly - 1.6), Color(0.50, 0.42, 0.22, 0.12), 1.0)
	elif lit > 0.10:
		for k in 5:
			var gp := o + Vector2(8 + _hash01(int(o.x) + k, r) * 48.0, 20 + _hash01(int(o.y) + k, c) * 34.0)
			ci.draw_line(gp, gp + Vector2((_hash01(k, c) - 0.5) * 3.0, -4.0 - _hash01(k, r) * 4.0), Color(0.32, 0.42, 0.18, 0.8), 1.0)
	ci.draw_rect(Rect2(o + Vector2(1.5, 1.5), Vector2(CELL - 3.0, CELL - 3.0)), Color(0, 0, 0, 0.06 + (1.0 - lit) * 0.055), false, 1.0)
	ci.draw_line(o + Vector2(2, 2), o + Vector2(CELL - 2, 2), Color(0.55, 0.42, 0.20, 0.12), 1.0)
	ci.draw_line(o + Vector2(2, 2), o + Vector2(2, CELL - 2), Color(0.55, 0.42, 0.20, 0.10), 1.0)
	if h2 < 0.15:
		ci.draw_circle(ctr + Vector2(5, 3), 2.0 + h * 1.4, Color(0.18, 0.14, 0.08))


func _tile_garn(ci: CanvasItem, o: Vector2, ctr: Vector2, c: int, r: int, r0: int, r1: int, gc: Vector2, h: float, _h2: float, lit: float) -> void:
	var court := clampf(1.0 - ctr.distance_to(gc) / 220.0, 0.0, 1.0)
	court = court * court * (3.0 - 2.0 * court)
	var base := F_DUST_LO.lerp(F_DUST, clampf(0.30 + lit * 0.85, 0.12, 1.0)).lerp(F_DUST_PALE, court * 0.42)
	if lit > 0.06:
		base = base.lerp(nearest_light_col(ctr), lit * lit * 0.12)
	ci.draw_rect(Rect2(o + Vector2(1.5, 1.5), Vector2(CELL - 3.0, CELL - 3.0)), base)
	var near_wall := c <= PLAY_COL_MIN + 1 or c >= PLAY_COL_MAX - 1 or r == r0 or r == r1
	if near_wall:
		var fc := F_FLAG.lerp(F_FLAG.lerp(F_DUST, 0.4), (1.0 - lit) * 0.5)
		ci.draw_rect(Rect2(o + Vector2(4, 4), Vector2(CELL - 8, CELL - 8)), fc)
		ci.draw_rect(Rect2(o + Vector2(4, 4), Vector2(CELL - 8, CELL - 8)), F_MORTAR, false, 1.4)
	else:
		for k in 3:
			if _hash01(int(o.x) + k * 3, int(o.y) + k) < 0.42:
				var sp := ctr + Vector2((_hash01(k, int(o.x)) - 0.5) * 40.0, (_hash01(int(o.y), k) - 0.5) * 40.0)
				var ang := _hash01(k * 7, int(o.y)) * PI
				ci.draw_line(sp, sp + Vector2(cos(ang), sin(ang)) * (5.0 + h * 6.0), Color(0.10, 0.08, 0.06, 0.30), 1.5)
	ci.draw_line(o + Vector2(2, 2), o + Vector2(CELL - 2, 2), Color(0.80, 0.50, 0.30, 0.10), 1.0)
	ci.draw_line(o + Vector2(2, 2), o + Vector2(2, CELL - 2), Color(0.80, 0.50, 0.30, 0.09), 1.0)
	ci.draw_line(o + Vector2(2, CELL - 2), o + Vector2(CELL - 2, CELL - 2), Color(0, 0, 0, 0.28), 1.0)


func _zone_tint(ci: CanvasItem, z: Dictionary) -> void:
	var zr := _zone_rect(z)
	var tint: Color
	match z["id"]:
		"mine":  tint = Color(0.11, 0.15, 0.28, 0.11)
		"champ": tint = Color(0.24, 0.30, 0.15, 0.055)
		"garn":  tint = Color(0.24, 0.10, 0.06, 0.10)
		_:       tint = Color(0, 0, 0, 0)
	ci.draw_rect(zr, tint)


func _zone_vignette(ci: CanvasItem, z: Dictionary) -> void:
	var zr := _zone_rect(z)
	var deep := Color(0.02, 0.03, 0.06, 0.18) if z["id"] == "mine" else Color(0, 0, 0, 0.15)
	for i in 5:
		var f := float(i) / 5.0
		var d := 15.0 * f
		ci.draw_rect(Rect2(zr.position + Vector2(d, d), zr.size - Vector2(d * 2.0, d * 2.0)),
			Color(deep.r, deep.g, deep.b, deep.a * (1.0 - f) * (1.0 - f)), false, 3.0)


func _zone_ground_decor(ci: CanvasItem, z: Dictionary) -> void:
	if z["id"] != "champ":
		return
	# sillons a l'echelle de la zone (l'oeil suit des lignes productives)
	var zr := _zone_rect(z)
	var nf := 14
	for i in nf:
		var ly := zr.position.y + (i + 0.5) * zr.size.y / nf
		ci.draw_line(Vector2(zr.position.x + 6, ly), Vector2(zr.end.x - 6, ly), Color(0, 0, 0, 0.10), 1.4)
		ci.draw_line(Vector2(zr.position.x + 6, ly - 1.4), Vector2(zr.end.x - 6, ly - 1.4), Color(1.0, 0.88, 0.60, 0.04), 1.0)


# --- remparts ------------------------------------------------------
##  Une enceinte unique autour de l'aire de jeu + 2 murs transversaux dans les
##  gouttieres.  Tours aux 4 coins + 2 jonctions a droite.  Portails a gauche.

const TH := 26.0

func _play_union() -> Rect2:
	return Rect2(PLAY_COL_MIN * CELL, ZONES[0]["r0"] * CELL,
		(PLAY_COL_MAX - PLAY_COL_MIN + 1) * CELL,
		(ZONES[2]["r1"] - ZONES[0]["r0"] + 1) * CELL)


func _gutter_ys() -> Array:
	return [(ZONES[0]["r1"] + 1) * CELL + CELL * 0.5, (ZONES[1]["r1"] + 1) * CELL + CELL * 0.5]


func _draw_ramparts(ci: CanvasItem) -> void:
	var pu := _play_union()
	var wt := _wall_warm(Vector2(pu.get_center().x, pu.position.y - TH))
	# chasme externe
	ci.draw_rect(Rect2(pu.position - Vector2(TH + 6, TH + 6), Vector2(pu.size.x + (TH + 6) * 2, 6)), K_DEEP.darkened(0.3))
	ci.draw_rect(Rect2(Vector2(pu.position.x - TH - 6, pu.end.y + TH), Vector2(pu.size.x + (TH + 6) * 2, 6)), K_DEEP.darkened(0.3))
	# --- 4 dalles de chemin de ronde du perimetre ---
	WallKit.stone_band(ci, Rect2(pu.position - Vector2(TH, TH), Vector2(pu.size.x + TH * 2.0, TH)), 11, wt)
	WallKit.stone_band(ci, Rect2(Vector2(pu.position.x - TH, pu.end.y), Vector2(pu.size.x + TH * 2.0, TH)), 12, wt * 0.5)
	WallKit.stone_band(ci, Rect2(Vector2(pu.end.x, pu.position.y), Vector2(TH, pu.size.y)), 14, wt * 0.6)
	# mur gauche : tronçons entre les 3 portails
	var gates := []
	for z in ZONES:
		gates.append(_zone_rect(z).get_center().y)
	var ys := [pu.position.y]
	for gy in gates:
		ys.append(gy - 40.0)
		ys.append(gy + 40.0)
	ys.append(pu.end.y)
	for i in range(0, ys.size(), 2):
		var a: float = ys[i]
		var b: float = ys[i + 1]
		if b - a > 4.0:
			WallKit.stone_band(ci, Rect2(Vector2(pu.position.x - TH, a), Vector2(TH, b - a)), 20 + i, _wall_warm(Vector2(pu.position.x - TH, (a + b) * 0.5)))
	# --- merlons du perimetre (saut des 3 portails a gauche) ---
	WallKit.merlon_strip(ci, pu.position.x, pu.end.x, pu.position.y - TH, true, 1.0, 30, wt)
	WallKit.merlon_strip(ci, pu.position.x, pu.end.x, pu.end.y + TH, true, -1.0, 31, wt * 0.5)
	WallKit.merlon_strip(ci, pu.position.y, pu.end.y, pu.end.x + TH, false, -1.0, 32, wt * 0.6)
	for i in range(0, ys.size(), 2):
		WallKit.merlon_strip(ci, ys[i], ys[i + 1], pu.position.x - TH, false, 1.0, 33 + i, wt * 0.7)
	# --- murs transversaux dans les gouttieres ---
	for gi in _gutter_ys().size():
		var gy: float = _gutter_ys()[gi]
		var gw := _wall_warm(Vector2(pu.get_center().x, gy))
		WallKit.stone_band(ci, Rect2(Vector2(pu.position.x, gy - 13.0), Vector2(pu.size.x, 26.0)), 50 + gi, gw)
		WallKit.merlon_strip(ci, pu.position.x, pu.end.x, gy - 13.0, true, 1.0, 52 + gi, gw)
		WallKit.merlon_strip(ci, pu.position.x, pu.end.x, gy + 13.0, true, -1.0, 54 + gi, gw)
	# --- tours : 4 coins + 2 jonctions droite ---
	WallKit.corner_tower(ci, pu.position + Vector2(-TH * 0.5, -TH * 0.5), 60, wt, Vector2(1, 1))
	WallKit.corner_tower(ci, Vector2(pu.end.x + TH * 0.5, pu.position.y - TH * 0.5), 64, wt, Vector2(-1, 1))
	WallKit.corner_tower(ci, Vector2(pu.position.x - TH * 0.5, pu.end.y + TH * 0.5), 68, wt * 0.5, Vector2(1, -1))
	WallKit.corner_tower(ci, pu.end + Vector2(TH * 0.5, TH * 0.5), 72, wt * 0.5, Vector2(-1, -1))
	for gi in _gutter_ys().size():
		WallKit.corner_tower(ci, Vector2(pu.end.x + TH * 0.5, _gutter_ys()[gi]), 76 + gi, wt * 0.5, Vector2(-1, 0))
	# --- AO du rempart vers l'interieur, par zone ---
	for z in ZONES:
		var zr := _zone_rect(z)
		for k in 6:
			var aa := 0.18 * (1.0 - k / 6.0) * (1.0 - k / 6.0)
			ci.draw_rect(Rect2(Vector2(zr.position.x, zr.position.y + k * 2.0), Vector2(zr.size.x, 2.0)), Color(0, 0, 0, aa))
			ci.draw_rect(Rect2(Vector2(zr.position.x, zr.end.y - 2.0 - k * 2.0), Vector2(zr.size.x, 2.0)), Color(0, 0, 0, aa))
			ci.draw_rect(Rect2(Vector2(zr.position.x + k * 2.0, zr.position.y), Vector2(2.0, zr.size.y)), Color(0, 0, 0, aa * 0.7))
			ci.draw_rect(Rect2(Vector2(zr.end.x - 2.0 - k * 2.0, zr.position.y), Vector2(2.0, zr.size.y)), Color(0, 0, 0, aa * 0.7))
	# --- bases de braseros le long du mur gauche ---
	for gy in gates:
		WallKit.sconce_base(ci, Vector2(pu.position.x - TH * 0.5, gy - 62.0))
		WallKit.sconce_base(ci, Vector2(pu.position.x - TH * 0.5, gy + 62.0))
	# --- flaveur de mur par zone (l'identite gagne meme la pierre) ---
	for z in ZONES:
		_wall_flavor(ci, z)


## Petits accents qui distinguent la maconnerie de chaque zone.
func _wall_flavor(ci: CanvasItem, z: Dictionary) -> void:
	var zr := _zone_rect(z)
	match z["id"]:
		"mine":
			# givre sur les caps + veines bleues sur la dalle du mur haut
			for i in 7:
				var mx := zr.position.x + 50.0 + i * 88.0
				if mx > zr.end.x - 20.0:
					break
				ci.draw_line(Vector2(mx - 12, zr.position.y - TH - 6), Vector2(mx + 12, zr.position.y - TH - 6), Color(0.72, 0.82, 0.95, 0.16), 1.2)
			for i in 3:
				var vx := zr.position.x + 120.0 + i * 180.0
				ci.draw_line(Vector2(vx, zr.position.y - TH + 3), Vector2(vx + 14, zr.position.y - 3), Color(0.40, 0.60, 1.0, 0.25), 1.4)
		"champ":
			# mousse au pied des merlons + lierre sur la face interne
			for i in 6:
				var mx := zr.position.x + 40.0 + i * 100.0
				if mx > zr.end.x - 20.0:
					break
				WallKit.ellipse(ci, Vector2(mx, zr.position.y + 2.0), 10.0, 4.0, Color(0.24, 0.34, 0.16, 0.5), i + 2)
			for i in 3:
				var ix := zr.position.x + 60.0 + i * 200.0
				ci.draw_polyline(PackedVector2Array([
					Vector2(ix, zr.position.y), Vector2(ix + 4, zr.position.y + 12), Vector2(ix - 2, zr.position.y + 22), Vector2(ix + 3, zr.position.y + 32)]),
					Color(0.26, 0.40, 0.18, 0.6), 1.6)
		"garn":
			# marques de suie sur la dalle du mur + petites bannieres cramoisies
			for i in 5:
				var sx := zr.position.x + 70.0 + i * 110.0
				if sx > zr.end.x - 20.0:
					break
				ci.draw_circle(Vector2(sx, zr.position.y - TH * 0.5), 4.0 + _hash01(i, 4) * 3.0, Color(0, 0, 0, 0.22))


# --- portails ------------------------------------------------------

func _gate_anchor(z: Dictionary) -> Vector2:
	var zr := _zone_rect(z)
	return Vector2(zr.position.x - 13.0, zr.get_center().y)


func _zone_gate_masonry(ci: CanvasItem, z: Dictionary) -> void:
	WallKit.gate_arch_front(ci, _gate_anchor(z), 27.0, 36.0, z["glow"], z["glyph"])


# --- props statiques par zone ------------------------------------

func _zone_props_static(ci: CanvasItem, z: Dictionary) -> void:
	var zr := _zone_rect(z)
	match z["id"]:
		"mine":  _props_mine(ci, zr)
		"champ": _props_champ(ci, zr)
		"garn":  _props_garn(ci, zr)


func _shadow(ci: CanvasItem, c: Vector2, rx: float) -> void:
	WallKit.ellipse(ci, c, rx, rx * 0.42, Color(0, 0, 0, 0.28), int(c.x) + int(c.y))


func _props_mine(ci: CanvasItem, zr: Rect2) -> void:
	# (1) chevalement, coin haut-droite, a cheval sur le mur nord
	var b := zr.position + Vector2(zr.size.x - 62.0, 8.0)
	_shadow(ci, b + Vector2(0, 26), 26.0)
	ci.draw_colored_polygon(PackedVector2Array([b + Vector2(-16, 28), b + Vector2(16, 28), b + Vector2(10, -4), b + Vector2(-10, -4)]), Color(0.03, 0.03, 0.04))
	ci.draw_line(b + Vector2(-15, 28), b + Vector2(-2, -30), F_TIMBER, 4.0)
	ci.draw_line(b + Vector2(15, 28), b + Vector2(2, -30), F_TIMBER, 4.0)
	ci.draw_line(b + Vector2(-2, -30), b + Vector2(2, -30), F_TIMBER, 4.0)
	ci.draw_line(b + Vector2(-11, 8), b + Vector2(11, 8), F_TIMBER_LO, 2.5)
	ci.draw_line(b + Vector2(-11, 8), b + Vector2(2, -30), F_TIMBER_LO, 1.6)
	ci.draw_circle(b + Vector2(0, -22), 5.0, Color(0.16, 0.14, 0.12))
	ci.draw_arc(b + Vector2(0, -22), 5.0, 0, TAU, 12, F_IRON, 1.4)
	ci.draw_line(b + Vector2(0, -18), b + Vector2(0, 20), Color(0.20, 0.18, 0.16), 1.2)
	ci.draw_rect(Rect2(b + Vector2(-18, -12), Vector2(36, 7)), WallKit.K_QUOIN.lerp(K_WARM, 0.05))
	# rails courts vers l'ouest (restent dans la gouttiere du mur haut)
	for s: float in [-4.0, 4.0]:
		ci.draw_line(b + Vector2(s, 24), b + Vector2(s - 70.0, 20.0), Color(0.26, 0.24, 0.22), 2.0)
	var rx := b.x - 6.0
	while rx > b.x - 66.0:
		ci.draw_line(Vector2(rx, b.y + 24.0), Vector2(rx - 3, b.y + 28.0), F_TIMBER_LO, 3.0)
		rx -= 12.0
	# (2) wagonnet sur le rail
	var w := b + Vector2(-42.0, 22.0)
	_shadow(ci, w + Vector2(0, 7), 13.0)
	ci.draw_colored_polygon(PackedVector2Array([w + Vector2(-9, -6), w + Vector2(9, -6), w + Vector2(7, 5), w + Vector2(-7, 5)]), Color(0.24, 0.18, 0.12))
	ci.draw_colored_polygon(PackedVector2Array([w + Vector2(-6, -7), w + Vector2(6, -7), w + Vector2(3, -12), w + Vector2(-3, -11)]), Color(0.30, 0.48, 0.86))
	ci.draw_line(w + Vector2(-2, -12), w + Vector2(2, -10), Color(0.62, 0.80, 1.0), 1.2)
	ci.draw_circle(w + Vector2(-5, 6), 2.6, F_IRON)
	ci.draw_circle(w + Vector2(5, 6), 2.6, F_IRON)
	# (3) filon de cristal, coin bas-gauche
	var f := zr.position + Vector2(30.0, zr.size.y - 24.0)
	for k in 6:
		var hh := 9.0 + _hash01(k, 3) * 16.0
		var fx := f.x + (k - 3) * 6.0
		ci.draw_colored_polygon(PackedVector2Array([Vector2(fx - 4, f.y), Vector2(fx, f.y - hh), Vector2(fx + 4, f.y)]), Color(0.26, 0.44, 0.9))
		ci.draw_line(Vector2(fx, f.y), Vector2(fx, f.y - hh), Color(0.55, 0.75, 1.0, 0.6), 1.0)
	# poutres d'etayage : traversent la galerie pres du mur haut ET du mur bas
	for edge_y: float in [zr.position.y + 3.0, zr.end.y - 6.0]:
		for i in 5:
			var ex := zr.position.x + 60.0 + i * 120.0
			if ex > zr.end.x - 30.0:
				break
			ci.draw_line(Vector2(ex, edge_y), Vector2(ex, edge_y + 24.0), F_TIMBER_LO, 3.0)
			ci.draw_line(Vector2(ex - 8, edge_y + 4.0), Vector2(ex + 8, edge_y + 4.0), F_TIMBER, 2.5)
	# amas de cristaux semes le long des 2 murs lateraux + gravats
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		var cx := (zr.position.x + 18.0) if side < 0 else (zr.end.x - 18.0)
		var cyv := zr.position.y + 30.0 + int(i * 0.5) * 52.0
		if cyv > zr.end.y - 20.0:
			continue
		for k in 3:
			var chh := 6.0 + _hash01(i * 3 + k, 5) * 12.0
			var px := cx + side * (k * 4.0)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(px - 3, cyv), Vector2(px, cyv - chh), Vector2(px + 3, cyv)]), Color(0.26, 0.44, 0.9))
			ci.draw_line(Vector2(px, cyv), Vector2(px, cyv - chh), Color(0.55, 0.75, 1.0, 0.6), 1.0)
	for i in 3:
		var gp := zr.position + Vector2(150.0 + i * 160.0, zr.size.y - 14.0 - _hash01(i, 7) * 8.0)
		ci.draw_circle(gp, 6.0, F_ROCK_LO.darkened(0.2))
		ci.draw_circle(gp + Vector2(-4, -3), 4.0, F_ROCK)
		ci.draw_circle(gp + Vector2(3, -2), 1.2, Color(F_VEIN.r, F_VEIN.g, F_VEIN.b, 0.6))


func _props_champ(ci: CanvasItem, zr: Rect2) -> void:
	# parcelles de ble (semees, alignees grille)
	for pi in 3:
		var pr := Rect2(zr.position + Vector2(zr.size.x * (0.05 + pi * 0.30), zr.size.y * 0.14),
			Vector2(zr.size.x * 0.20, zr.size.y * 0.38))
		ci.draw_rect(pr, Color(0.42, 0.34, 0.16))
		for rr in 5:
			var ly := pr.position.y + (rr + 0.5) * pr.size.y / 5.0
			var x := pr.position.x + 4.0
			while x < pr.end.x - 3.0:
				ci.draw_line(Vector2(x, ly + 3.0), Vector2(x + 1.0, ly - 4.0), Color(0.72, 0.58, 0.26, 0.9), 1.4)
				x += 4.0
		ci.draw_rect(pr, Color(0.30, 0.22, 0.12), false, 1.5)
	# (1) moulin a vent : socle pierre + fut + coiffe (les ailes sont animees)
	var m := zr.position + Vector2(zr.size.x * 0.60, 30.0)
	_shadow(ci, m + Vector2(0, 58), 30.0)
	# socle de pierre
	ci.draw_colored_polygon(PackedVector2Array([m + Vector2(-24, 58), m + Vector2(24, 58), m + Vector2(19, 36), m + Vector2(-19, 36)]), WallKit.K_FACE_MID.lerp(K_WARM, 0.06))
	ci.draw_line(m + Vector2(-21, 47), m + Vector2(21, 47), F_MORTAR, 1.2)
	# fut tronconique bois
	ci.draw_colored_polygon(PackedVector2Array([m + Vector2(-19, 38), m + Vector2(19, 38), m + Vector2(12, -30), m + Vector2(-12, -30)]), Color(0.44, 0.39, 0.31))
	ci.draw_colored_polygon(PackedVector2Array([m + Vector2(3, 38), m + Vector2(19, 38), m + Vector2(12, -30), m + Vector2(2, -30)]), Color(0.31, 0.26, 0.19))
	for k in 4:
		var by := m.y - 20.0 + k * 15.0
		ci.draw_line(Vector2(m.x - 16 + k, by), Vector2(m.x + 16 - k, by), Color(0.30, 0.25, 0.18, 0.7), 1.2)
	ci.draw_rect(Rect2(m + Vector2(-5, 20), Vector2(10, 18)), Color(0.10, 0.09, 0.08))
	ci.draw_rect(Rect2(m + Vector2(-11, -4), Vector2(6, 6)), Color(0.95, 0.72, 0.35))
	# coiffe
	ci.draw_colored_polygon(PackedVector2Array([m + Vector2(-15, -30), m + Vector2(15, -30), m + Vector2(8, -48), m + Vector2(-8, -48)]), F_TIMBER_LO)
	ci.draw_colored_polygon(PackedVector2Array([m + Vector2(-8, -48), m + Vector2(8, -48), m + Vector2(0, -56)]), F_TIMBER_LO.darkened(0.2))
	ci.draw_line(m + Vector2(-15, -30), m + Vector2(0, -56), Color(0.98, 0.86, 0.58, 0.4), 1.2)
	# (2) longere a chaume, coin bas-droite
	var b := zr.position + Vector2(zr.size.x - 78.0, zr.size.y - 52.0)
	_shadow(ci, b + Vector2(0, 24), 30.0)
	ci.draw_rect(Rect2(b + Vector2(-24, -2), Vector2(48, 26)), Color(0.40, 0.33, 0.22))
	for k in 3:
		ci.draw_line(b + Vector2(-16 + k * 16, -2), b + Vector2(-16 + k * 16, 24), F_TIMBER_LO, 2.0)
	ci.draw_line(b + Vector2(-24, -2), b + Vector2(24, 24), Color(0.26, 0.19, 0.12, 0.5), 1.4)
	ci.draw_rect(Rect2(b + Vector2(-5, 10), Vector2(10, 14)), Color(0.12, 0.10, 0.08))
	ci.draw_rect(Rect2(b + Vector2(9, 2), Vector2(8, 8)), Color(1.0, 0.75, 0.40))
	ci.draw_colored_polygon(PackedVector2Array([b + Vector2(-30, -2), b + Vector2(30, -2), b + Vector2(20, -22), b + Vector2(-20, -22)]), F_THATCH)
	for k in 4:
		ci.draw_line(b + Vector2(-28 + k * 2, -2 - k * 5), b + Vector2(28 - k * 2, -2 - k * 5), F_THATCH_LO, 1.4)
	ci.draw_line(b + Vector2(-20, -22), b + Vector2(20, -22), Color(0.70, 0.58, 0.34), 2.0)
	ci.draw_rect(Rect2(b + Vector2(8, -30), Vector2(6, 12)), Color(0.30, 0.26, 0.22))
	# (3) puits + potager, pres du portail
	var wl := zr.position + Vector2(34.0, zr.size.y * 0.5)
	_shadow(ci, wl + Vector2(0, 8), 12.0)
	ci.draw_circle(wl, 9.0, Color(0.40, 0.36, 0.29))
	ci.draw_circle(wl, 5.5, Color(0.06, 0.07, 0.08))
	ci.draw_line(wl + Vector2(-9, 0), wl + Vector2(-9, -16), F_TIMBER, 2.0)
	ci.draw_line(wl + Vector2(9, 0), wl + Vector2(9, -16), F_TIMBER, 2.0)
	ci.draw_colored_polygon(PackedVector2Array([wl + Vector2(-12, -14), wl + Vector2(12, -14), wl + Vector2(0, -22)]), F_TIMBER_LO)
	for gi in 3:
		var gr := Rect2(zr.position + Vector2(18.0, zr.size.y * 0.5 + 24.0 + gi * 14.0), Vector2(30, 10))
		ci.draw_rect(gr, Color(0.22, 0.17, 0.10))
		for sp in 4:
			ci.draw_line(gr.position + Vector2(4 + sp * 7, 8), gr.position + Vector2(4 + sp * 7, 2), Color(0.30, 0.44, 0.18), 1.4)
	# meules de foin semees
	for i in 2:
		var hp := zr.position + Vector2(zr.size.x * (0.30 + i * 0.16), zr.size.y - 22.0)
		_shadow(ci, hp + Vector2(0, 4), 12.0)
		WallKit.ellipse(ci, hp, 12.0, 9.0, F_HAY, i * 5 + 1)
		ci.draw_arc(hp, 11.0, PI, TAU, 10, F_HAY_DK, 1.4)


func _props_garn(ci: CanvasItem, zr: Rect2) -> void:
	# (1) baraquement, haut-droite
	var b := zr.position + Vector2(zr.size.x - 74.0, 40.0)
	_shadow(ci, b + Vector2(0, 24), 34.0)
	ci.draw_rect(Rect2(b + Vector2(-30, -4), Vector2(60, 30)), Color(0.33, 0.31, 0.29))
	for k in 4:
		ci.draw_line(b + Vector2(-28, -4 + k * 8), b + Vector2(28, -4 + k * 8), F_MORTAR, 1.2)
	ci.draw_colored_polygon(PackedVector2Array([b + Vector2(-34, -4), b + Vector2(34, -4), b + Vector2(26, -20), b + Vector2(-26, -20)]), Color(0.22, 0.20, 0.19))
	ci.draw_line(b + Vector2(-26, -20), b + Vector2(26, -20), Color(0.34, 0.32, 0.30), 1.6)
	ci.draw_rect(Rect2(b + Vector2(-6, 8), Vector2(12, 18)), Color(0.09, 0.08, 0.08))
	ci.draw_colored_polygon(WallKit.arc_fan(b + Vector2(0, 8), 6.0, PI, TAU, 8), Color(0.09, 0.08, 0.08))
	ci.draw_rect(Rect2(b + Vector2(-22, 2), Vector2(6, 8)), Color(1.0, 0.55, 0.22, 0.5))
	# (2) aire d'entrainement, gouttiere sud
	var trn := zr.position + Vector2(zr.size.x * 0.30, zr.size.y - 20.0)
	for i in 3:
		var pp := trn + Vector2(i * 26.0, 0)
		ci.draw_line(pp + Vector2(0, 12), pp + Vector2(0, -16), F_TIMBER, 3.0)
		ci.draw_line(pp + Vector2(-7, -8), pp + Vector2(7, -8), F_TIMBER, 3.0)
		ci.draw_circle(pp + Vector2(0, -18), 4.0, Color(0.48, 0.38, 0.24))
	# cible
	var tg := trn + Vector2(-70.0, -4.0)
	ci.draw_circle(tg, 8.0, F_HAY)
	ci.draw_circle(tg, 5.0, Color(0.6, 0.15, 0.12))
	ci.draw_circle(tg, 2.0, Color(0.90, 0.80, 0.35))
	ci.draw_line(tg + Vector2(-5, 8), tg + Vector2(-8, 16), F_TIMBER_LO, 2.0)
	ci.draw_line(tg + Vector2(5, 8), tg + Vector2(8, 16), F_TIMBER_LO, 2.0)
	# ratelier d'armes
	var rk := zr.position + Vector2(zr.size.x - 40.0, zr.size.y - 26.0)
	ci.draw_line(rk + Vector2(-12, 0), rk + Vector2(12, 0), F_TIMBER, 2.5)
	for k in 5:
		ci.draw_line(rk + Vector2(-10 + k * 5, 2), rk + Vector2(-14 + k * 5, -22), Color(0.5, 0.42, 0.3), 1.6)
		ci.draw_polygon(PackedVector2Array([rk + Vector2(-14 + k * 5, -22), rk + Vector2(-16 + k * 5, -26), rk + Vector2(-12 + k * 5, -26)]), PackedColorArray([F_IRON]))
	# (3) forge, coin bas-gauche pres du portail
	var fg := zr.position + Vector2(46.0, zr.size.y - 34.0)
	_shadow(ci, fg + Vector2(0, 10), 16.0)
	ci.draw_rect(Rect2(fg + Vector2(-14, -2), Vector2(28, 16)), Color(0.24, 0.21, 0.19))
	for k in 3:
		ci.draw_line(fg + Vector2(-13, -2 + k * 5), fg + Vector2(13, -2 + k * 5), F_MORTAR, 1.0)
	ci.draw_colored_polygon(PackedVector2Array([fg + Vector2(-10, -2), fg + Vector2(10, -2), fg + Vector2(5, -18), fg + Vector2(-5, -18)]), F_IRON)
	ci.draw_colored_polygon(PackedVector2Array([fg + Vector2(2, 14), fg + Vector2(14, 14), fg + Vector2(14, 22), fg + Vector2(-2, 22)]), Color(0.12, 0.11, 0.12))
	ci.draw_line(fg + Vector2(16, 12), fg + Vector2(22, 6), Color(0.30, 0.26, 0.22), 2.0)
	# tas de boucliers
	var sh := zr.position + Vector2(zr.size.x * 0.5, zr.size.y - 18.0)
	for i in 3:
		WallKit.ellipse(ci, sh + Vector2(i * 6 - 6, -i * 3), 8.0, 8.0, Color(0.35, 0.16, 0.13), i + 1)
		ci.draw_circle(sh + Vector2(i * 6 - 6, -i * 3), 2.0, F_IRON)
	# bannieres rouges de mur (semees)
	for i in 2:
		var bp := zr.position + Vector2(zr.size.x * (0.18 + i * 0.5), 6.0)
		ci.draw_line(bp, bp + Vector2(0, -2), F_IRON, 2.0)
		ci.draw_colored_polygon(PackedVector2Array([bp, bp + Vector2(14, 0), bp + Vector2(14, 22), bp + Vector2(7, 18), bp + Vector2(0, 22)]), F_BANNER)


# ====================================================================
#  CALQUE DYNAMIQUE
# ====================================================================

func _draw() -> void:
	for z in ZONES:
		_zone_props_anim(z)
	# flammes des braseros muraux
	for z in ZONES:
		var cy: float = _zone_rect(z).get_center().y
		WallKit.sconce_flame(self, Vector2(_zone_rect(z).position.x - TH * 0.5, cy - 62.0), _t)
		WallKit.sconce_flame(self, Vector2(_zone_rect(z).position.x - TH * 0.5, cy + 62.0), _t)
	for zi in ZONES.size():
		var z2: Dictionary = ZONES[zi]
		WallKit.gate_glow(self, _gate_anchor(z2), 27.0, 36.0, z2["glow"], _t, zi)
		_zone_sign(z2, zi)
		_zone_particles(z2, zi)
	_draw_hover()


func _zone_props_anim(z: Dictionary) -> void:
	var zr := _zone_rect(z)
	match z["id"]:
		"mine":
			var f := zr.position + Vector2(30.0, zr.size.y - 24.0)
			var tw := 0.10 + 0.09 * sin(_t * 1.8)
			_ellipse(f, 30.0, 20.0, Color(F_VEIN.r, F_VEIN.g, F_VEIN.b, tw), 41)
			for k in 8:
				var gp := zr.position + Vector2(20 + _hash01(k, 1) * (zr.size.x - 40), 16 + _hash01(k, 2) * (zr.size.y - 32))
				var edge: bool = gp.x < zr.position.x + 60 or gp.x > zr.end.x - 60 or gp.y < zr.position.y + 40 or gp.y > zr.end.y - 40
				if not edge:
					continue
				var s := 0.5 + 0.5 * sin(_t * 2.2 + k * 1.7)
				draw_circle(gp, 1.0 + s * 1.0, Color(F_VEIN.r, F_VEIN.g, F_VEIN.b, 0.25 + s * 0.35))
		"champ":
			var m := zr.position + Vector2(zr.size.x * 0.60, 30.0)
			var hub := m + Vector2(0, -37)
			var a := _t * 0.8
			for k in 4:
				var ang := a + k * PI * 0.5
				var dir := Vector2(cos(ang), sin(ang))
				var orth := Vector2(-dir.y, dir.x)
				var tip := hub + dir * 30.0
				draw_line(hub, tip, F_TIMBER_LO, 3.5)
				draw_colored_polygon(PackedVector2Array([hub + dir * 5.0 + orth * 2.0, tip + orth * 2.0, tip + orth * 7.0, hub + dir * 5.0 + orth * 4.0]),
					Color(0.82, 0.76, 0.58, 0.92))
				draw_polyline(PackedVector2Array([hub + dir * 5.0 + orth * 2.0, tip + orth * 2.0]), Color(0.30, 0.24, 0.16), 1.0)
			draw_circle(hub, 3.5, F_IRON)
			# fumee de la cheminee de la longere
			var ch := zr.position + Vector2(zr.size.x - 78.0 + 8.0, zr.size.y - 52.0 - 30.0)
			for k in 3:
				var ph := fposmod(_t * 0.3 + k * 0.34, 1.0)
				draw_circle(ch + Vector2(sin(_t + k) * 4.0, -ph * 22.0), 2.0 + ph * 3.0, Color(0.6, 0.58, 0.55, (1.0 - ph) * 0.22))
		"garn":
			var fg := zr.position + Vector2(46.0, zr.size.y - 34.0)
			var gl := 0.6 + 0.4 * sin(_t * 7.0)
			_ellipse(fg + Vector2(0, 6), 11.0, 5.0, Color(1.0, 0.42, 0.12, 0.30 + gl * 0.18), 61)
			for k in 3:
				draw_circle(fg + Vector2((k - 1) * 4.0, 5.0), 1.6, Color(1.0, 0.6 + gl * 0.2, 0.25))
			for k in 3:
				var ph := fposmod(_t * 0.7 + k * 0.4, 1.0)
				draw_circle(fg + Vector2((_hash01(k, 3) - 0.4) * 10.0 + ph * 6.0, 2.0 - ph * 24.0), (1.0 - ph) * 1.4, Color(1.0, 0.55, 0.2, (1.0 - ph) * 0.5))


## Enseigne : plaque de bronze montee sur le mur au-dessus de la zone + petit
## fanion de couleur.  Taux de production live.
func _zone_sign(z: Dictionary, zi: int) -> void:
	var zr := _zone_rect(z)
	var glow: Color = z["glow"]
	var f := ThemeDB.fallback_font
	var pw := 154.0
	var ph := 22.0
	var p := Vector2(zr.position.x + 10.0, zr.position.y - TH - 1.0)
	draw_rect(Rect2(p, Vector2(pw, ph)), Color(0.11, 0.097, 0.083, 0.97))
	draw_rect(Rect2(p, Vector2(pw, ph)), Color(0.451, 0.333, 0.180), false, 2.0)
	draw_line(p + Vector2(2, 1.5), p + Vector2(pw - 2, 1.5), Color(1, 0.98, 0.92, 0.10), 1.0)
	draw_rect(Rect2(p, Vector2(4.0, ph)), glow)
	draw_circle(p + Vector2(pw - 7, 6), 1.6, Color(0.55, 0.45, 0.26))
	draw_circle(p + Vector2(pw - 7, ph - 6), 1.6, Color(0.55, 0.45, 0.26))
	draw_string(f, p + Vector2(12, ph * 0.5 + 4.5), String(z["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.TEXT_TITLE)
	var nm := f.get_string_size(String(z["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(f, p + Vector2(12 + nm + 8, ph * 0.5 + 4.5), _zone_rate(z), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, glow.lightened(0.25))
	# fanion de couleur qui pend du coin droit de la plaque
	var cloth := Color(0.16, 0.22, 0.42) if z["id"] == "mine" else (Color(0.18, 0.28, 0.12) if z["id"] == "champ" else F_BANNER)
	WallKit.banner_cloth(self, p + Vector2(pw - 20.0, ph - 2.0), 9.0, 20.0, cloth, -1, _t, zi + 5)


func _zone_rate(z: Dictionary) -> String:
	var grp := "peons" if z["cat"] == "peon" else "fermiers" if z["cat"] == "fermier" else "casernes"
	var n: int = get_tree().get_nodes_in_group(grp).size()
	if z["cat"] == "caserne":
		return "%d caserne%s" % [n, "s" if n > 1 else ""]
	if n == 0:
		return "0 ouvrier"
	var yv := 0.7 + Meta.peon_yield_bonus
	var r := n * yv * (18.0 / (18.0 + float(maxi(0, n - 3))))
	return "+%.1f / s" % r


func _zone_particles(z: Dictionary, zi: int) -> void:
	var zr := _zone_rect(z)
	match z["id"]:
		"mine":
			for i in 9:
				var ph := fposmod(_t * 0.05 + i * 0.317, 1.0)
				var px := zr.position.x + 40.0 + _hash01(i, zi) * (zr.size.x - 80.0)
				var py := zr.position.y + 20.0 + ph * (zr.size.y - 40.0)
				draw_circle(Vector2(px + sin(_t + i) * 3.0, py), 0.8, Color(0.62, 0.68, 0.82, (1.0 - ph) * 0.22))
		"champ":
			for i in 9:
				var ph := fposmod(_t * 0.06 + i * 0.29, 1.0)
				var px := zr.position.x + 30.0 + _hash01(i, zi + 1) * (zr.size.x - 60.0) + sin(_t * 0.8 + i) * 8.0
				var py := zr.end.y - 20.0 - ph * (zr.size.y - 40.0)
				draw_circle(Vector2(px, py), 1.0, Color(0.86, 0.76, 0.40, (1.0 - ph) * 0.28))
		"garn":
			for i in 8:
				var ph := fposmod(_t * 0.08 + i * 0.31, 1.0)
				var px := zr.position.x + 46.0 + sin(_t * 1.4 + i) * 10.0
				var py := zr.end.y - 30.0 - ph * 60.0
				draw_circle(Vector2(px, py), (1.0 - ph) * 1.5, Color(1.0, 0.52, 0.18, (1.0 - ph) * 0.4))


func _draw_hover() -> void:
	if pending_tool == "" or hover_cell.x < 0:
		return
	var ok := can_build(pending_tool, hover_cell)
	var o := Vector2(hover_cell.x * CELL, hover_cell.y * CELL)
	draw_rect(Rect2(o, Vector2(CELL, CELL)), Color(0.30, 0.90, 0.40, 0.16) if ok else Color(0.90, 0.30, 0.30, 0.12))
	draw_rect(Rect2(o, Vector2(CELL, CELL)), Color(1, 1, 1, 0.25) if ok else Color(0.9, 0.35, 0.35, 0.4), false, 1.5)


# ====================================================================
#  CLASSES INTERNES
# ====================================================================

## Calque statique : sol / remparts / portails / props fixes.  Redessine seulement
## quand `farm._static_dirty` est arme (pose, retrait, changement d'outil / de survol).
class _FarmStatic extends Node2D:
	var farm: FarmView
	func _draw() -> void:
		if farm != null:
			farm.draw_static(self)


## Calque additif : nappes de lumiere douces (clippees par zone).
class _FarmLight extends Node2D:
	var farm: FarmView
	var _acc := 0.0
	var _web := OS.has_feature("web")
	func _process(d: float) -> void:
		_acc += d
		if _acc >= (0.05 if _web else 0.0):
			_acc = 0.0
			queue_redraw()
	func _draw() -> void:
		if farm == null:
			return
		for L in farm.light_sources():
			var p: Vector2 = L["p"]
			var col: Color = L["col"]
			var r: float = L["r"]
			var ymin: float = L.get("ymin", -1e9)
			var ymax: float = L.get("ymax", 1e9)
			for i in range(6, 0, -1):
				var f := float(i) / 6.0
				var rr := r * f
				var pts := PackedVector2Array()
				for k in 20:
					var a := k * TAU / 20.0
					var pt := p + Vector2(cos(a) * rr, sin(a) * rr * 1.1)
					pt.y = clampf(pt.y, ymin, ymax)
					pts.append(pt)
				draw_colored_polygon(pts, Color(col.r, col.g, col.b, (1.0 - f) * (1.0 - f) * 0.055))
