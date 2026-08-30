class_name Tower
extends Unit
## Tour fixe: mur infranchissable + tourelle qui tire. Type = `type_id`.
## Ameliorable (3 niveaux), revendable, priorite de cible reglable (bulle).

const TYPES := {
	"canon": {
		"levels": [
			{"dmg": 10.0, "rng": 155.0, "cd": 0.60},
			{"dmg": 19.0, "rng": 170.0, "cd": 0.52},
			{"dmg": 34.0, "rng": 192.0, "cd": 0.44},
			{"dmg": 58.0, "rng": 206.0, "cd": 0.40},
			{"dmg": 96.0, "rng": 222.0, "cd": 0.36},
		],
		"up": [55, 120, 260, 540], "pspeed": 340.0, "splash": 0.0, "slow": 1.0, "slow_dur": 0.0,
	},
	"gatling": {
		"levels": [
			{"dmg": 4.0, "rng": 135.0, "cd": 0.15},
			{"dmg": 6.0, "rng": 145.0, "cd": 0.13},
			{"dmg": 10.0, "rng": 160.0, "cd": 0.11},
			{"dmg": 16.0, "rng": 172.0, "cd": 0.10},
			{"dmg": 26.0, "rng": 184.0, "cd": 0.09},
		],
		"up": [60, 135, 285, 580], "pspeed": 520.0, "splash": 0.0, "slow": 1.0, "slow_dur": 0.0,
	},
	"mortier": {
		"levels": [
			{"dmg": 16.0, "rng": 215.0, "cd": 1.7},
			{"dmg": 28.0, "rng": 230.0, "cd": 1.6},
			{"dmg": 46.0, "rng": 250.0, "cd": 1.5},
			{"dmg": 78.0, "rng": 266.0, "cd": 1.4},
			{"dmg": 124.0, "rng": 282.0, "cd": 1.3},
		],
		"up": [95, 195, 410, 820], "pspeed": 240.0, "splash": 58.0, "slow": 1.0, "slow_dur": 0.0,
	},
	# givre = sort de ZONE de proximite (nova de gel) : pas de projectile.
	# rng = rayon de la nova (~1 tuile et un peu plus) ; cd = recharge du sort ;
	# dmg = degats infliges a CHAQUE ennemi dans la zone. Ralentit tout le monde.
	"givre": {
		"levels": [
			{"dmg": 8.0, "rng": 78.0, "cd": 1.5},
			{"dmg": 13.0, "rng": 86.0, "cd": 1.4},
			{"dmg": 20.0, "rng": 96.0, "cd": 1.3},
			{"dmg": 31.0, "rng": 106.0, "cd": 1.15},
			{"dmg": 46.0, "rng": 118.0, "cd": 1.0},
		],
		"up": [70, 150, 310, 630], "pspeed": 300.0, "splash": 0.0, "slow": 0.42, "slow_dur": 1.8,
	},
}

var type_id := "canon"
var level := 1
var invested := 0
var selected := false
var stat_damage := 0.0
var stat_kills := 0
var synergy := 0   ## voisines orthogonales du meme type (0-4) -> +8% degats chacune

var _aim := 0.0
var _muzzle := 0.0
var _tint := Color.WHITE
var _active_t := 0.0
var _combat_t := 0.0

var _is_nova := false        ## givre : attaque de zone au lieu d'un projectile
var _nova_flash := 0.0       ## impulsion visuelle apres un tir de nova (1 -> 0)
var _frost_t := 0.0          ## anim lente du givre au sol


static func base_range(id: String) -> float:
	var t: Dictionary = TYPES[id] if TYPES.has(id) else TYPES["canon"]
	return t["levels"][0]["rng"] + Meta.rng(id)


func configure(id: String) -> void:
	type_id = id if TYPES.has(id) else "canon"
	_tint = Catalog.color(type_id)
	_is_nova = type_id == "givre"


func _ready() -> void:
	team = 0
	target_group = "enemies"
	self_groups = PackedStringArray()
	bobs = false
	target_priority = "first"
	body_color = _tint
	max_hp = 1.0
	radius = 15.0
	_aim = -PI * 0.5    ## au repos : les armes font face au flux ennemi (venant du HAUT)
	_apply_level()
	Meta.changed.connect(_apply_level)
	super._ready()


func _t() -> Dictionary:
	return TYPES[type_id]


func _apply_level() -> void:
	var s: Dictionary = _t()["levels"][level - 1]
	damage = s["dmg"] * Meta.dmg(type_id) * (1.0 + synergy * 0.08)
	attack_range = s["rng"] + Meta.rng(type_id)
	attack_cooldown = s["cd"] * Meta.cd(type_id)


func credit_damage(v: float) -> void:
	stat_damage += v


func credit_kill() -> void:
	stat_kills += 1


func uptime() -> float:
	return _active_t / maxf(0.5, _combat_t)


func can_upgrade() -> bool:
	return level < _t()["levels"].size()


func upgrade_cost() -> int:
	return _t()["up"][level - 1] if can_upgrade() else 0


func sell_value() -> int:
	return int(round(invested * Meta.sell_refund))


func dps() -> float:
	return damage / maxf(0.05, attack_cooldown)


func set_synergy(n: int) -> void:
	if n != synergy:
		synergy = n
		_apply_level()


func cycle_priority() -> void:
	var order := ["first", "near", "strong", "weak"]
	target_priority = order[(order.find(target_priority) + 1) % order.size()]


func priority_label() -> String:
	match target_priority:
		"near": return "le plus proche"
		"strong": return "le plus solide"
		"weak": return "le plus faible"
		_: return "tete de file"


func do_upgrade() -> void:
	if not can_upgrade():
		return
	invested += _t()["up"][level - 1]
	level += 1
	_apply_level()
	_spawn_t = 0.6


func take_damage(_amount: float, _source: Node = null) -> float:
	return 0.0


func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(target):
		_aim = lerp_angle(_aim, (target.global_position - global_position).angle(),
			clampf(delta * 10.0, 0.0, 1.0))
	_muzzle = maxf(0.0, _muzzle - delta * 6.0)
	_nova_flash = maxf(0.0, _nova_flash - delta * 2.2)
	_frost_t += delta
	if GameState.phase == GameState.Phase.COMBAT:
		_combat_t += delta
		if is_instance_valid(target):
			_active_t += delta


func _attack(t: Unit) -> void:
	if _is_nova:
		_nova()
		return
	# vise la cible immediatement pour que le tir parte dans le bon axe
	_aim = (t.global_position - global_position).angle()
	var d: Dictionary = _t()
	var p := Projectile.new()
	p.target = t
	p.source = self
	p.damage = damage
	p.color = _tint.lightened(0.30 + level * 0.05)
	p.speed = d["pspeed"] + level * 30.0
	p.splash = (d["splash"] + Meta.splash_bonus) if d["splash"] > 0.0 else 0.0
	p.slow_factor = maxf(0.1, d["slow"] - Meta.frost_bonus) if d["slow"] < 1.0 else 1.0
	p.slow_dur = d["slow_dur"]
	if type_id == "mortier":
		p.arc = 46.0
	get_parent().add_child(p)
	p.global_position = muzzle()          ## part du BOUT du canon, pas du centre
	_muzzle = 1.0
	Audio.play("shoot_" + type_id)


## Bout du canon (dans le sens de visee).  ~ la longueur du tube dessine (x1.18).
func muzzle() -> Vector2:
	var barrel := 30.0
	match type_id:
		"gatling": barrel = 30.0
		"mortier": barrel = 26.0
		"givre": barrel = 0.0
	return global_position + Vector2.RIGHT.rotated(_aim) * barrel


## Nova de gel : frappe et ralentit tous les ennemis dans le rayon (attack_range).
func _nova() -> void:
	var d: Dictionary = _t()
	var slow_f := maxf(0.08, float(d["slow"]) - Meta.frost_bonus)
	var dur := float(d["slow_dur"])
	var hit := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e.hp <= 0.0:
			continue
		if global_position.distance_to(e.global_position) > attack_range:
			continue
		var dealt: float = e.take_damage(damage, self)
		credit_damage(dealt)
		if e.has_method("apply_slow"):
			e.apply_slow(slow_f, dur)
		hit += 1
	_nova_flash = 1.0
	_muzzle = 1.0
	if hit > 0:
		Audio.play("shoot_givre")
		Fx.ring(position, _tint.lightened(0.45), 5.0, attack_range, 0.30)


func _draw() -> void:
	if _is_nova:
		_draw_frost_zone()
	elif selected:
		var pr := 1.0 + sin(_anim * 4.0) * 0.02
		var rr := attack_range * pr
		# remplissage interieur en degrade doux
		draw_circle(Vector2.ZERO, rr, Color(_tint.r, _tint.g, _tint.b, 0.04))
		draw_circle(Vector2.ZERO, rr * 0.6, Color(_tint.r, _tint.g, _tint.b, 0.03))
		# anneau peint : plusieurs passes, epaisseur qui s'attenue, legere rupture facon craie
		for k in 4:
			var kf := float(k) / 4.0
			draw_arc(Vector2.ZERO, rr - kf * 3.0, 0.0, TAU, 72,
				Color(_tint.r, _tint.g, _tint.b, 0.28 * (1.0 - kf)), (3.0 - kf * 2.0))
		for seg in 24:
			var a0 := seg * TAU / 24.0 + _anim * 0.15
			draw_arc(Vector2.ZERO, rr, a0, a0 + 0.16, 4, Color(_tint.r, _tint.g, _tint.b, 0.45), 1.6)
	if not _is_nova and is_instance_valid(target) and target.hp > 0.0:
		draw_line(Vector2.ZERO, to_local(target.global_position),
			Color(_tint.r, _tint.g, _tint.b, 0.13), 1.0)
	super._draw()
	if _is_nova:
		_draw_cooldown_ring()


## Givre au sol : au repos, empreinte discrete (anneau + givre pres du socle).
## Au survol / selection / decharge de nova : la zone complete s'affiche.
func _draw_frost_zone() -> void:
	var r := attack_range
	var full: float = _nova_flash + (1.0 if selected else 0.0)
	full = clampf(full, 0.0, 1.0)
	# empreinte permanente, tres legere (givre terne au repos)
	draw_circle(Vector2.ZERO, 24.0, Color(0.62, 0.74, 0.78, 0.04 + 0.05 * full))
	for k in 3:
		var kf := float(k) / 3.0
		draw_arc(Vector2.ZERO, r - kf * 2.5, 0.0, TAU, 48,
			Color(0.60, 0.76, 0.80, (0.05 + full * 0.32) * (1.0 - kf)),
			(1.4 + full * 1.6) - kf)
	if full <= 0.01 and _nova_flash <= 0.0:
		return
	var base_a := 0.05 + _nova_flash * 0.24 + full * 0.09
	draw_circle(Vector2.ZERO, r, Color(0.52, 0.80, 1.0, base_a))
	draw_circle(Vector2.ZERO, r * 0.62, Color(0.74, 0.92, 1.0, base_a * 0.7))
	var sd := int(abs(global_position.x) + abs(global_position.y) * 7.0)
	for i in 7:
		var ang := (float((sd + i * 37) % 360)) * PI / 180.0
		var wob := sin(_frost_t * 1.5 + i) * 0.08
		var a := Vector2.RIGHT.rotated(ang + wob) * (r * 0.15)
		var b := Vector2.RIGHT.rotated(ang + wob) * (r * (0.75 + 0.2 * float((sd + i) % 3) / 3.0))
		var mid := (a + b) * 0.5 + Vector2.RIGHT.rotated(ang + PI * 0.5) * (r * 0.12 * sin(float(i)))
		draw_polyline(PackedVector2Array([a, mid, b]),
			Color(0.85, 0.95, 1.0, (0.16 + _nova_flash * 0.4) * maxf(full, _nova_flash)), 1.5)
	for i in 5:
		var fa := _frost_t * 0.4 + i * TAU / 5.0
		var fp := Vector2.RIGHT.rotated(fa) * (r * 0.55)
		for k in 3:
			var da := Vector2.RIGHT.rotated(k * PI / 3.0) * 3.0
			draw_line(fp - da, fp + da, Color(0.9, 0.97, 1.0, (0.3 + _nova_flash * 0.4) * maxf(full, _nova_flash)), 1.2)
	# onde de choc de la nova
	if _nova_flash > 0.0:
		var e := 1.0 - _nova_flash
		draw_arc(Vector2.ZERO, r * (0.4 + e * 0.75), 0.0, TAU, 40,
			Color(0.85, 0.96, 1.0, _nova_flash * 0.8), 2.5)


## Anneau de rechargement (timer circulaire) au-dessus de la tour de givre.
func _draw_cooldown_ring() -> void:
	var c := Vector2(0, -32.0)
	var rr := 9.0
	var frac := 1.0 - clampf(_cd / maxf(0.01, attack_cooldown), 0.0, 1.0)
	draw_circle(c, rr + 1.5, Color(0.04, 0.06, 0.09, 0.7))
	draw_arc(c, rr, 0.0, TAU, 24, Color(0.35, 0.45, 0.55, 0.55), 3.0)
	if frac >= 0.999:
		var pulse := 0.6 + sin(_anim * 5.0) * 0.4
		draw_arc(c, rr, 0.0, TAU, 24, Color(0.7, 0.95, 1.0, pulse), 3.0)
		# petit flocon "pret"
		for k in 3:
			var dd := Vector2.RIGHT.rotated(k * PI / 3.0) * 3.5
			draw_line(c - dd, c + dd, Color(0.9, 0.98, 1.0), 1.4)
	else:
		draw_arc(c, rr, -PI * 0.5, -PI * 0.5 + frac * TAU, 24, Color(0.55, 0.90, 1.0), 3.0)


const _INK := Color(0.072, 0.064, 0.052)   ## encre (accord avec arena.gd)
const _STONE := Color(0.37, 0.39, 0.36)     ## pierre du corps (gris-vert, plus clair que le sol)
const _STONE_LIT := Color(0.56, 0.57, 0.52)
const _STONE_SHD := Color(0.17, 0.18, 0.18)

func _ink_poly(pts: PackedVector2Array, fill: Color, w := 2.4) -> void:
	draw_colored_polygon(pts, fill)
	var o := pts
	o.append(pts[0])
	# trait legerement ondule
	var wob := PackedVector2Array()
	for i in range(o.size() - 1):
		var a: Vector2 = o[i]
		var b: Vector2 = o[i + 1]
		var n := (b - a).orthogonal().normalized()
		for s in 3:
			var t := s / 3.0
			wob.append(a.lerp(b, t) + n * (sin(float(i * 13 + s * 7)) * 1.4))
	wob.append(o[0])
	draw_polyline(wob, _INK, w)


func _draw_body(_col: Color) -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.18, 1.18))   ## emplacements : plus imposants que la grille
	# --- ombre de contact douce + ombre portee : le socle est ANCRE dans le sol ---
	draw_set_transform(Vector2(2, 24), 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, 40.0, Color(0, 0, 0, 0.12))
	draw_circle(Vector2.ZERO, 32.0, Color(0, 0, 0, 0.18))
	draw_circle(Vector2.ZERO, 24.0, Color(0, 0, 0, 0.26))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.18, 1.18))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-22, 20), Vector2(24, 20), Vector2(34, 32), Vector2(-30, 32)]), Color(0, 0, 0, 0.34))
	# --- socle de pierre : trapeze LARGE en bas, etroit en haut, assis dans le dallage ---
	_ink_poly(PackedVector2Array([
		Vector2(-31, 23), Vector2(31, 23), Vector2(23, 4), Vector2(-23, 4)]), _STONE_SHD, 3.0)
	draw_line(Vector2(-23, 4), Vector2(23, 4), _STONE_LIT, 2.4)
	draw_line(Vector2(-31, 23), Vector2(31, 23), Color(0, 0, 0, 0.5), 2.0)
	# bandeau d'accent du type sur le socle -> on distingue les tours d'un coup d'oeil
	var acc := _tint
	draw_rect(Rect2(-23, 4, 46, 3.5), Color(acc.r, acc.g, acc.b, 0.6))
	draw_line(Vector2(-23, 7.5), Vector2(23, 7.5), _INK, 1.2)

	# --- silhouette par TYPE ---
	match type_id:
		"canon":     # blockhaus trapu + gueule epaisse
			_ink_poly(PackedVector2Array([Vector2(-24, 6), Vector2(24, 6), Vector2(20, -18), Vector2(-20, -18)]), _STONE, 2.6)
			draw_colored_polygon(PackedVector2Array([Vector2(-22, 4), Vector2(0, 4), Vector2(-2, -16), Vector2(-20, -16)]), _STONE_LIT)
			var d := Vector2.RIGHT.rotated(_aim)
			_ink_poly(PackedVector2Array([-d.orthogonal() * 6 + d * 4, d.orthogonal() * 6 + d * 4,
				d.orthogonal() * 5 + d * 26, -d.orthogonal() * 5 + d * 26]), _STONE_SHD, 2.2)
			draw_circle(d * 26, 4.0, _INK)
		"gatling":   # tour moyenne, 3 canons qui pointent
			_ink_poly(PackedVector2Array([Vector2(-19, 6), Vector2(19, 6), Vector2(15, -26), Vector2(-15, -26)]), _STONE, 2.6)
			draw_colored_polygon(PackedVector2Array([Vector2(-17, 4), Vector2(-1, 4), Vector2(-3, -24), Vector2(-15, -24)]), _STONE_LIT)
			var g := Vector2.RIGHT.rotated(_aim)
			for o in [-5.0, 0.0, 5.0]:
				draw_line(g.orthogonal() * o + g * 2.0, g.orthogonal() * o + g * (22.0 + level * 2.0), _INK, 3.0)
				draw_line(g.orthogonal() * o + g * 2.0, g.orthogonal() * o + g * (22.0 + level * 2.0), Color(0.5, 0.52, 0.5), 1.4)
		"mortier":   # base lourde + gros tube incline
			_ink_poly(PackedVector2Array([Vector2(-22, 8), Vector2(22, 8), Vector2(18, -12), Vector2(-18, -12)]), _STONE, 2.8)
			draw_colored_polygon(PackedVector2Array([Vector2(-20, 6), Vector2(-2, 6), Vector2(-4, -10), Vector2(-18, -10)]), _STONE_LIT)
			var mv := Vector2(0.55, -1.0).normalized()
			_ink_poly(PackedVector2Array([mv.orthogonal() * 9 - mv * 2, -mv.orthogonal() * 9 - mv * 2,
				-mv.orthogonal() * 11 + mv * 26, mv.orthogonal() * 11 + mv * 26]), _STONE_SHD, 2.6)
			draw_circle(mv * 26, 8.0, _INK)
			draw_circle(mv * 26, 5.5, Color(0.05, 0.05, 0.06))
		"givre":     # eperon de cristal (glace terne, pas un neon)
			_ink_poly(PackedVector2Array([Vector2(-14, 6), Vector2(14, 6), Vector2(9, -14), Vector2(-9, -14)]), _STONE, 2.4)
			_ink_poly(PackedVector2Array([Vector2(-10, -8), Vector2(10, -8), Vector2(5, -34), Vector2(0, -40), Vector2(-5, -32)]),
				Color(0.34, 0.44, 0.48), 2.4)
			draw_line(Vector2(0, -40), Vector2(-4, -12), Color(0.58, 0.70, 0.72, 0.6), 1.6)
			draw_line(Vector2(0, -40), Vector2(5, -14), Color(0.18, 0.26, 0.30, 0.8), 1.4)
			var pr := 0.6 + sin(_frost_t * 1.5) * 0.4
			draw_circle(Vector2(0, -26), 2.2 + pr * 1.4, Color(0.68, 0.82, 0.86, 0.35))
		_:
			_ink_poly(PackedVector2Array([Vector2(-20, 6), Vector2(20, 6), Vector2(16, -22), Vector2(-16, -22)]), _STONE, 2.6)
			draw_rect(Rect2(-16, -30, 8, 10), _STONE)
			draw_rect(Rect2(8, -30, 8, 10), _STONE)

	# --- rim chaud (haut-gauche) + ombre (bas-droite) ---
	draw_line(Vector2(-20, -16), Vector2(16, -18), Color(1.0, 0.84, 0.52, 0.45), 2.0)
	draw_line(Vector2(20, 4), Vector2(-20, 6), Color(0, 0, 0, 0.4), 2.0)
	# --- fanion d'accent du type ---
	draw_line(Vector2(15, -20), Vector2(15, -34), _INK, 2.0)
	_ink_poly(PackedVector2Array([Vector2(15, -34), Vector2(27, -31), Vector2(15, -26)]), acc, 1.4)
	# --- pips de niveau ---
	for i in level:
		draw_circle(Vector2(-13.0 + i * 5.0, 16.0), 2.0, Palette.KING)

	if _muzzle > 0.0:
		var tp := Vector2.RIGHT.rotated(_aim)
		if _is_nova:
			draw_circle(Vector2.ZERO, 16.0 * _muzzle, Color(0.8, 0.95, 1.0, _muzzle * 0.7))
		else:
			draw_circle(tp * (24.0 + level * 2.0), 5.5 * _muzzle, Color(1, 0.95, 0.7, _muzzle))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)   ## reset : le reste (HP, etc.) a l'echelle 1
