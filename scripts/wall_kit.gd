class_name WallKit
extends RefCounted
## Kit de rempart top-down PARTAGEABLE (arene + ferme).  100 % statique, sans etat.
## REGLE Godot 4.7 : chaque methode prend `ci: CanvasItem` en 1er param et n'appelle
## QUE `ci.draw_*`.  Les valeurs de pierre sont copiees a l'identique d'arena.gd (kit v11)
## pour que les deux mondes montrent la meme maconnerie.  Migration d'arena.gd -> WallKit
## en lot separe (wrappers minces).

# --- pierre (valeurs EXACTES d'arena.gd) ---
const K_CAP_LIT  := Color(0.640, 0.618, 0.575)
const K_CAP_CORE := Color(0.492, 0.474, 0.442)
const K_FACE_HI  := Color(0.470, 0.440, 0.400)
const K_FACE_MID := Color(0.360, 0.334, 0.300)
const K_FACE_LO  := Color(0.225, 0.208, 0.188)
const K_MORTAR   := Color(0.140, 0.130, 0.120)
const K_QUOIN    := Color(0.530, 0.500, 0.452)
const K_MERLON_SH:= Color(0.115, 0.107, 0.100)
const K_SKY_RIM  := Color(0.460, 0.520, 0.575, 0.42)
const K_WARM     := Color(1.000, 0.600, 0.270)
const K_AMBWARM  := Color(0.550, 0.380, 0.240)
const K_BOUNCE   := Color(0.470, 0.330, 0.190)
const K_INK      := Color(0.048, 0.046, 0.044)
const K_WARM_BLK := Color(0.050, 0.040, 0.035)
const IRON       := Color(0.090, 0.085, 0.090)
const FIRE_CORE  := Color(1.000, 0.957, 0.847)
const FIRE_MID   := Color(0.980, 0.580, 0.220)
const FIRE_LOW   := Color(0.700, 0.240, 0.090)
const CELL       := 64.0


static func hash01(a: int, b: int) -> float:
	var n := sin(float(a) * 12.9898 + float(b) * 78.233) * 43758.5453
	return n - floorf(n)


static func _closed(p: PackedVector2Array) -> PackedVector2Array:
	var o := p.duplicate()
	o.append(p[0])
	return o


## Trait d'encre "a la main" : segments subdivises + jitter perpendiculaire deterministe.
static func ink_path(ci: CanvasItem, pts: PackedVector2Array, base_w: float, sd: int, closed := true) -> void:
	var loop := pts
	if closed:
		loop = _closed(pts)
	for i in range(loop.size() - 1):
		var a: Vector2 = loop[i]
		var b: Vector2 = loop[i + 1]
		var nrm := (b - a).orthogonal().normalized()
		var seg := PackedVector2Array()
		for s in 5:
			var f := float(s) / 4.0
			var j := (hash01(sd + i * 7, s * 13) - 0.5) * 1.6
			seg.append(a.lerp(b, f) + nrm * j)
		var w: float = base_w * (0.8 + hash01(sd + i, 3) * 0.5)
		ci.draw_polyline(seg, K_INK, w)


static func ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, sd: int) -> void:
	var pts := PackedVector2Array()
	for i in 26:
		var ang := i * TAU / 26.0
		var j := 1.0 + (hash01(sd, i) - 0.5) * 0.14
		pts.append(c + Vector2(cos(ang) * rx, sin(ang) * ry) * j)
	ci.draw_colored_polygon(pts, col)


static func arc_fan(c: Vector2, r: float, a0: float, a1: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(c)
	for i in range(n + 1):
		var g := lerpf(a0, a1, float(i) / n)
		pts.append(c + Vector2(cos(g), sin(g)) * r)
	return pts


## Dalle de chemin de ronde vue de dessus : grande surface + joints + liseré.
##   `warm` 0..1 : chaleur de torche.  `sd` : graine.
static func stone_band(ci: CanvasItem, r: Rect2, sd: int, warm := 0.0) -> void:
	if r.size.x < 2.0 or r.size.y < 2.0:
		return
	var horiz := r.size.x >= r.size.y
	ci.draw_rect(r, K_CAP_CORE.lerp(K_WARM, warm * 0.20))
	# jitter de valeur par tronçon
	var step := 56.0
	if horiz:
		var x := r.position.x
		var bi := 0
		while x < r.end.x:
			var w: float = minf(step, r.end.x - x)
			var v: float = (hash01(sd + bi, 5) - 0.5) * 0.10
			ci.draw_rect(Rect2(Vector2(x, r.position.y), Vector2(w, r.size.y)), Color(0, 0, 0, absf(v)) if v > 0.0 else Color(1, 1, 1, absf(v) * 0.4))
			ci.draw_line(Vector2(x, r.position.y + 1.0), Vector2(x, r.end.y - 1.0), K_MORTAR, 1.3)
			x += step
			bi += 1
	else:
		var y := r.position.y
		var bj := 0
		while y < r.end.y:
			var h: float = minf(step, r.end.y - y)
			var v2: float = (hash01(sd + bj, 9) - 0.5) * 0.10
			ci.draw_rect(Rect2(Vector2(r.position.x, y), Vector2(r.size.x, h)), Color(0, 0, 0, absf(v2)) if v2 > 0.0 else Color(1, 1, 1, absf(v2) * 0.4))
			ci.draw_line(Vector2(r.position.x + 1.0, y), Vector2(r.end.x - 1.0, y), K_MORTAR, 1.3)
			y += step
			bj += 1
	ci.draw_rect(r, K_FACE_LO, false, 1.4)
	# liseré froid sur l'arete haute
	ci.draw_line(r.position, Vector2(r.end.x, r.position.y), K_SKY_RIM, 1.2)


## Rangee de merlons le long d'une arete.  Copie conforme d'arena._merlon_strip.
##   `edge`  : coord de l'arete (y si horiz, x sinon)
##   `horiz` : true = arete horizontale, merlons alignes sur x
##   `into`  : +1/-1, direction de l'arete VERS la dalle (l'ombre tombe par la)
static func merlon_strip(ci: CanvasItem, a0: float, a1: float, edge: float, horiz: bool, into: float, sd: int, warm := 0.0) -> void:
	var c0 := int(floorf(minf(a0, a1) / CELL))
	var c1 := int(ceilf(maxf(a0, a1) / CELL))
	var half := 15.0
	var body := K_CAP_CORE.lerp(K_WARM, warm * 0.35)
	var cap := K_CAP_LIT.lerp(K_WARM, warm * 0.4)
	for cc in range(c0, c1):
		var m := cc * CELL + CELL * 0.5 + (hash01(sd + cc, 2) - 0.5) * 3.0
		if m < minf(a0, a1) - 2.0 or m > maxf(a0, a1) + 2.0:
			continue
		if horiz:
			ci.draw_rect(Rect2(Vector2(m - half, edge - 7.5), Vector2(half * 2.0, 15.0)), body)
			var cap_y := (edge - 7.5) if into > 0 else (edge + 3.5)
			ci.draw_rect(Rect2(Vector2(m - half, cap_y), Vector2(half * 2.0, 4.0)), cap)
			ci.draw_rect(Rect2(Vector2(m - half, edge + (2.0 if into > 0 else -9.0)), Vector2(half * 2.0, 7.0)), Color(0, 0, 0, 0.30))
			ci.draw_line(Vector2(m - half, edge - 7.5), Vector2(m - half, edge + 7.5), K_MORTAR, 1.2)
			ci.draw_line(Vector2(m + half, edge - 7.5), Vector2(m + half, edge + 7.5), K_MORTAR, 1.2)
		else:
			ci.draw_rect(Rect2(Vector2(edge - 7.5, m - half), Vector2(15.0, half * 2.0)), body)
			var cap_x := (edge - 7.5) if into > 0 else (edge + 3.5)
			ci.draw_rect(Rect2(Vector2(cap_x, m - half), Vector2(4.0, half * 2.0)), cap)
			ci.draw_rect(Rect2(Vector2(edge + (2.0 if into > 0 else -9.0), m - half), Vector2(7.0, half * 2.0)), Color(0, 0, 0, 0.30))
			ci.draw_line(Vector2(edge - 7.5, m - half), Vector2(edge + 7.5, m - half), K_MORTAR, 1.2)
			ci.draw_line(Vector2(edge - 7.5, m + half), Vector2(edge + 7.5, m + half), K_MORTAR, 1.2)


## Tourelle d'angle vue de dessus : corps + dalle + merlons 4 cotes + ombre portee
## vers l'interieur (dir = vecteur normalise vers le centre de la zone).
static func corner_tower(ci: CanvasItem, ctr: Vector2, sd: int, warm: float, dir: Vector2) -> void:
	var tw := CELL + 20.0
	var tx := ctr.x - tw * 0.5
	var ty := ctr.y - tw * 0.5
	# ombre portee vers l'interieur
	for k in 8:
		var a := 0.24 * (1.0 - k / 8.0) * (1.0 - k / 8.0)
		var o := dir * (10.0 + k * 6.0)
		ci.draw_colored_polygon(PackedVector2Array([
			ctr, ctr + Vector2(o.x, 0) + Vector2(0, dir.y * 6.0), ctr + Vector2(0, o.y) + Vector2(dir.x * 6.0, 0)]),
			Color(K_WARM_BLK.r, K_WARM_BLK.g, K_WARM_BLK.b, a))
	ci.draw_rect(Rect2(Vector2(tx - 4.0, ty - 4.0), Vector2(tw + 8.0, tw + 8.0)), K_FACE_LO.darkened(0.25))
	ci.draw_rect(Rect2(Vector2(tx, ty), Vector2(tw, tw)), K_FACE_MID.lerp(K_WARM, warm * 0.2))
	var walk := Rect2(Vector2(tx + 13.0, ty + 13.0), Vector2(tw - 26.0, tw - 26.0))
	ci.draw_rect(walk, K_CAP_CORE.lerp(K_WARM, warm * 0.22))
	ci.draw_line(Vector2(walk.position.x, walk.get_center().y), Vector2(walk.end.x, walk.get_center().y), K_MORTAR, 1.3)
	ci.draw_line(Vector2(walk.get_center().x, walk.position.y), Vector2(walk.get_center().x, walk.end.y), K_MORTAR, 1.3)
	merlon_strip(ci, tx + 6.0, tx + tw - 6.0, ty, true, 1.0, sd + 1, warm)
	merlon_strip(ci, tx + 6.0, tx + tw - 6.0, ty + tw, true, -1.0, sd + 2, warm)
	merlon_strip(ci, ty + 6.0, ty + tw - 6.0, tx, false, 1.0, sd + 3, warm)
	merlon_strip(ci, ty + 6.0, ty + tw - 6.0, tx + tw, false, -1.0, sd + 4, warm)
	ci.draw_line(Vector2(tx, ty), Vector2(tx + tw, ty), Color(K_CAP_LIT.r, K_CAP_LIT.g, K_CAP_LIT.b, 0.5), 1.4)
	ci.draw_line(Vector2(tx, ty), Vector2(tx, ty + tw), Color(K_CAP_LIT.r, K_CAP_LIT.g, K_CAP_LIT.b, 0.4), 1.2)
	ci.draw_line(Vector2(tx + tw, ty), Vector2(tx + tw, ty + tw), K_FACE_LO, 2.0)
	ci.draw_line(Vector2(tx, ty + tw), Vector2(tx + tw, ty + tw), K_FACE_LO, 2.0)


## PORTAIL VU DE FACE : arche ∩ encastree dans un mur vertical, ouverture pointant
## vers le HAUT, lueur magique `glow` qui deborde vers l'EST (la zone).  Statique
## (maçonnerie) ; le halo anime est fait par `gate_glow`.
## `A` = centre de l'ouverture.  Retourne le point d'accroche de l'enseigne (linteau).
static func gate_arch_front(ci: CanvasItem, A: Vector2, hw: float, hh: float, glow: Color, glyph: int) -> Vector2:
	var spring := Vector2(A.x, A.y - hh)          ## naissance de l'arc
	var crown_y := spring.y - hw
	var sill_y := A.y + hh
	var void_c := Color(0.050, 0.046, 0.044)
	# --- 1. VOID + tunnel fuyant (vers l'ouest / le haut) ---
	ci.draw_rect(Rect2(Vector2(A.x - hw, spring.y), Vector2(hw * 2.0, sill_y - spring.y)), void_c)
	ci.draw_colored_polygon(arc_fan(spring, hw, PI, TAU, 18), void_c)
	for k in 5:
		var f := float(k) / 4.0
		var cv := 0.050 - f * 0.030
		ci.draw_rect(Rect2(Vector2(A.x - hw + 4.0 - f * 4.0, spring.y - f * 5.0), Vector2(hw * 2.0 - 8.0, sill_y - spring.y + f * 3.0)), Color(cv, cv * 0.95, cv * 0.9))
	# --- 2. JAMBAGES ---
	for s: float in [-1.0, 1.0]:
		var jx := A.x + s * hw
		var by := spring.y - 2.0
		var bi := 0
		while by < sill_y - 1.0:
			ci.draw_rect(Rect2(Vector2(jx if s > 0 else jx - 9.0, by), Vector2(9.0, 10.5)),
				K_QUOIN.lerp(K_QUOIN.darkened(0.26), hash01(glyph + bi, 3) * 0.5 + 0.12).lerp(K_AMBWARM, 0.06))
			ci.draw_line(Vector2(jx - 9.0 if s > 0 else jx, by), Vector2(jx if s > 0 else jx + 9.0, by), K_MORTAR, 1.2)
			by += 10.5
			bi += 1
		ci.draw_line(Vector2(jx, spring.y), Vector2(jx, sill_y), Color(0, 0, 0, 0.55), 2.0)
		ci.draw_line(Vector2(jx + s * 9.0, spring.y - 2.0), Vector2(jx + s * 9.0, sill_y), Color(K_CAP_LIT.r, K_CAP_LIT.g, K_CAP_LIT.b, 0.45), 1.2)
	# --- 3. ANNEAU DE VOUSSOIRS ---
	var r_in := hw
	var r_out := hw + 14.0
	var nv := 9
	for k in nv:
		var g0 := lerpf(PI, TAU, float(k) / nv)
		var g1 := lerpf(PI, TAU, float(k + 1) / nv)
		var mid := (float(k) + 0.5) / nv
		var key: bool = absf(mid - 0.5) < 0.07
		var ro := r_out + (5.0 if key else 0.0)
		var pa0 := spring + Vector2(cos(g0), sin(g0)) * r_in
		var pa1 := spring + Vector2(cos(g1), sin(g1)) * r_in
		var pb1 := spring + Vector2(cos(g1), sin(g1)) * ro
		var pb0 := spring + Vector2(cos(g0), sin(g0)) * ro
		var vc := K_QUOIN.lerp(K_FACE_MID, 0.10 + absf(mid - 0.5) * 0.6).lerp(K_AMBWARM, 0.06)
		if key:
			vc = K_QUOIN.lerp(K_CAP_LIT, 0.45)
		ci.draw_colored_polygon(PackedVector2Array([pa0, pa1, pb1, pb0]), vc)
		ci.draw_line(pa0, pb0, K_MORTAR, 1.2)
	ci.draw_arc(spring, r_out + 1.0, PI, TAU, 26, Color(K_CAP_LIT.r, K_CAP_LIT.g, K_CAP_LIT.b, 0.5), 1.4)
	ci.draw_arc(spring, r_in - 1.0, PI + 0.14, TAU - 0.14, 26, Color(0, 0, 0, 0.45), 3.0)
	ci.draw_arc(spring, r_in + 1.5, PI, TAU, 26, Color(glow.r, glow.g, glow.b, 0.45), 1.6)   ## l'intrados capte la magie
	# --- 4. CLE + glyphe grave ---
	ci.draw_rect(Rect2(Vector2(A.x - 7.0, crown_y - 8.0), Vector2(14.0, 16.0)), K_QUOIN.lerp(K_CAP_LIT, 0.4))
	_glyph(ci, glyph, Vector2(A.x, crown_y), glow)
	for bx in 3:
		ci.draw_rect(Rect2(Vector2(A.x - 22.0 + bx * 15.0, crown_y - 17.0), Vector2(13.0, 10.0)), K_FACE_MID.lerp(K_FACE_LO, 0.3))
	# --- 5. HERSE RELEVEE ---
	for k in 5:
		var bx2 := A.x - hw + 5.0 + k * (hw * 2.0 - 10.0) / 4.0
		var top_b := spring.y - sqrt(maxf(1.0, r_in * r_in - (bx2 - A.x) * (bx2 - A.x))) + 3.0
		ci.draw_line(Vector2(bx2, top_b), Vector2(bx2, top_b + 12.0), IRON, 3.0)
		ci.draw_line(Vector2(bx2 - 1.0, top_b), Vector2(bx2 - 1.0, top_b + 12.0), IRON.lightened(0.28), 1.0)
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(bx2 - 2.5, top_b + 12.0), Vector2(bx2 + 2.5, top_b + 12.0), Vector2(bx2, top_b + 17.0)]), IRON)
	ci.draw_line(Vector2(A.x - hw + 3.0, spring.y - hw * 0.62), Vector2(A.x + hw - 3.0, spring.y - hw * 0.62), IRON, 2.4)
	# --- 6. SEUIL + ombre vers l'est ---
	ci.draw_rect(Rect2(Vector2(A.x - hw, sill_y - 3.0), Vector2(hw * 2.0, 5.0)), K_CAP_CORE.lerp(K_CAP_LIT, 0.3))
	for k in 9:
		var a := 0.28 * (1.0 - k / 9.0) * (1.0 - k / 9.0)
		ci.draw_rect(Rect2(Vector2(A.x + hw + k * 5.0, A.y - hh - 4.0 + k * 2.0), Vector2(4.0, hh * 2.0 + 8.0 - k * 4.0)), Color(0, 0, 0, a))
	return Vector2(A.x, crown_y - 12.0)


## Glyphe de ministere grave dans la cle : 0 pic / 1 gerbe / 2 epees croisees.
static func _glyph(ci: CanvasItem, kind: int, c: Vector2, tint: Color) -> void:
	var g := Color(tint.r, tint.g, tint.b, 0.85)
	match kind:
		0:   ## pic
			ci.draw_line(c + Vector2(-5, 3), c + Vector2(0, -4), K_MORTAR, 1.6)
			ci.draw_line(c + Vector2(0, -4), c + Vector2(5, 3), K_MORTAR, 1.6)
			ci.draw_line(c + Vector2(0, -4), c + Vector2(0, 5), g, 1.4)
		1:   ## gerbe
			for a: float in [-0.5, 0.0, 0.5]:
				ci.draw_line(c + Vector2(0, 5), c + Vector2(sin(a) * 6.0, -5), g, 1.4)
		2:   ## epees croisees
			ci.draw_line(c + Vector2(-5, 5), c + Vector2(5, -5), g, 1.5)
			ci.draw_line(c + Vector2(5, 5), c + Vector2(-5, -5), g, 1.5)


## Halo magique anime qui deborde de l'ouverture vers l'est.  A appeler chaque frame.
static func gate_glow(ci: CanvasItem, A: Vector2, hw: float, hh: float, glow: Color, t: float, sd: int) -> void:
	var pulse := 0.5 + 0.5 * sin(t * 1.5 + sd)
	var c := Vector2(A.x + 14.0, A.y - 2.0)
	for i in range(6, 0, -1):
		ellipse(ci, c, 8.0 + i * 6.0, 12.0 + i * 6.0,
			Color(glow.r, glow.g, glow.b, 0.028 + i * 0.009 + pulse * 0.010), sd * 10 + i)
	ci.draw_circle(Vector2(A.x + 4.0, A.y), 3.0 + pulse * 1.2, Color(glow.r, glow.g, glow.b, 0.7))
	# motes qui montent dans l'arche
	for k in 4:
		var ph := fposmod(t * 0.4 + k * 0.31, 1.0)
		var mp := Vector2(A.x + (hash01(k, sd) - 0.4) * hw, A.y + hh * 0.6 - ph * hh * 1.6)
		ci.draw_circle(mp, (1.0 - ph) * 1.4, Color(glow.r, glow.g, glow.b, (1.0 - ph) * 0.55))
	# filet de lumiere sur le seuil, vers l'est
	ci.draw_line(Vector2(A.x, A.y), Vector2(A.x + 40.0, A.y), Color(glow.r, glow.g, glow.b, 0.16 + pulse * 0.06), 3.0)


## Platine de fer scellee (statique).
static func sconce_base(ci: CanvasItem, p: Vector2) -> void:
	ci.draw_rect(Rect2(p + Vector2(-4, -1), Vector2(8, 12)), K_FACE_LO)
	ci.draw_rect(Rect2(p + Vector2(-4, -1), Vector2(8, 12)), Color(0, 0, 0, 0.5), false, 1.0)
	ci.draw_line(p + Vector2(0, 9), p + Vector2(0, -2), IRON, 2.5)
	ci.draw_rect(Rect2(p + Vector2(-6, -3), Vector2(12, 4)), IRON)


## Flamme + flaque chaude (dynamique).
static func sconce_flame(ci: CanvasItem, p: Vector2, t: float) -> void:
	var fl := 0.85 + sin(t * 6.0 + p.x * 0.2) * 0.12
	for k in 3:
		var kf := float(k) / 3.0
		ellipse(ci, p + Vector2(0, 6.0 + kf * 6.0), 15.0 - kf * 4.0, 8.0 - kf * 2.0,
			Color(1.0, 0.66, 0.30, 0.10 * (1.0 - kf) * fl), int(p.x) + k)
	var fh := 12.0 * fl
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-4, -3), p + Vector2(4, -3), p + Vector2(0, -3 - fh)]), FIRE_LOW)
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-2.5, -3), p + Vector2(2.5, -3), p + Vector2(0, -3 - fh * 0.62)]), FIRE_MID)
	ci.draw_circle(p + Vector2(0, -3 - fh * 0.32), 2.0, FIRE_CORE)


## Etoffe de banniere suspendue (port d'arena._banner_at, couleur parametrable).
##   `top` : point d'accroche (haut de l'etoffe).  `hw` demi-largeur, `ln` longueur.
##   `emblem` : -1 aucun / 0 epees / 1 couronne.
static func banner_cloth(ci: CanvasItem, top: Vector2, hw: float, ln: float, col: Color, emblem: int, t: float, sd: int) -> void:
	var sag := (hash01(sd, 1) - 0.5) * 6.0
	var tatter := 3.0 + hash01(sd, 3) * 5.0
	var sway := sin(t * (0.7 + hash01(sd, 4) * 0.5) + sd * 1.7) * 3.0
	var lean := (hash01(sd, 2) - 0.5) * 5.0 + sway
	var fold := col.darkened(0.42)
	var lt := col.lightened(0.22)
	ci.draw_colored_polygon(PackedVector2Array([
		top + Vector2(-hw + 4, 3), top + Vector2(hw + 4, 3),
		top + Vector2(hw + lean + 5, ln + sag), top + Vector2(-hw + lean + 5, ln + sag - tatter)]),
		Color(0, 0, 0, 0.22))
	var pts := PackedVector2Array([
		top + Vector2(-hw, 0), top + Vector2(hw, 0),
		top + Vector2(hw + lean, ln + sag - tatter), top + Vector2(hw * 0.3 + lean, ln + sag + tatter),
		top + Vector2(lean, ln + sag - tatter * 0.5),
		top + Vector2(-hw * 0.3 + lean, ln + sag + tatter), top + Vector2(-hw + lean, ln + sag - tatter)])
	ci.draw_colored_polygon(pts, col)
	ci.draw_polyline(_closed(pts), K_INK, 1.6)
	ci.draw_colored_polygon(PackedVector2Array([
		top + Vector2(-hw, 1), top + Vector2(-hw * 0.45, 1),
		top + Vector2(-hw * 0.45 + lean, ln + sag - tatter), top + Vector2(-hw + lean, ln + sag - tatter)]),
		Color(lt.r, lt.g, lt.b, 0.5))
	ci.draw_colored_polygon(PackedVector2Array([
		top + Vector2(-hw * 0.15, 2), top + Vector2(hw * 0.15, 2),
		top + Vector2(hw * 0.12 + lean, ln + sag), top + Vector2(-hw * 0.12 + lean, ln + sag)]),
		Color(fold.r, fold.g, fold.b, 0.7))
	ci.draw_line(top + Vector2(-hw - 4, 0), top + Vector2(hw + 4, 0), IRON, 3.0)
	ci.draw_circle(top + Vector2(-hw - 4, 0), 2.0, IRON.lightened(0.3))
	ci.draw_circle(top + Vector2(hw + 4, 0), 2.0, IRON.lightened(0.3))
	if emblem >= 0:
		var mid := top + Vector2(lean * 0.5, ln * 0.42)
		var em := Color(0.80, 0.77, 0.68)
		if emblem == 0:
			for s: float in [-1.0, 1.0]:
				ci.draw_line(mid + Vector2(s * -8, 10), mid + Vector2(s * 8, -10), em, 2.0)
				ci.draw_line(mid + Vector2(s * 4, 12), mid + Vector2(s * 9, 12), em, 2.0)
		else:
			ci.draw_polyline(PackedVector2Array([
				mid + Vector2(-10, 6), mid + Vector2(-10, -4), mid + Vector2(-4, 2), mid + Vector2(0, -6),
				mid + Vector2(4, 2), mid + Vector2(10, -4), mid + Vector2(10, 6), mid + Vector2(-10, 6)]),
				Color(0.98, 0.86, 0.58), 2.0)


## Cadre d'ombre interne (AO d'assise) : n rects concentriques degressifs.
static func inset_shadow(ci: CanvasItem, rc: Rect2, depth: float) -> void:
	for i in 6:
		var f := float(i) / 6.0
		var d := depth * f
		ci.draw_rect(Rect2(rc.position + Vector2(d, d), rc.size - Vector2(d * 2.0, d * 2.0)),
			Color(0, 0, 0, 0.22 * (1.0 - f) * (1.0 - f)), false, maxf(1.5, depth / 6.0))
