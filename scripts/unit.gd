class_name Unit
extends Node2D
## Base commune a tout ce qui se bat: tours, guerriers, ennemis.
## Cible automatiquement l'unite la plus proche du groupe `target_group` a portee.

@export var max_hp := 100.0
@export var damage := 10.0
@export var attack_range := 120.0
@export var attack_cooldown := 1.0
@export var body_color := Color.WHITE
@export var radius := 14.0

## A regler par les sous-classes AVANT super._ready().
var target_group := "enemies"
var self_groups: PackedStringArray = PackedStringArray()
var bobs := true
var target_priority := "first"   ## first | near | strong | weak

var team := 0
var hp := 0.0
var target: Unit = null
var show_damage_text := false
var rig: SpriteRig = null
var hp_offset := 0.0

var _cd := 0.0
var _anim := 0.0
var _bob_seed := 0.0
var _spawn_t := 0.0
var _flash := 0.0
var _lunge := Vector2.ZERO
var _dmg_accum := 0.0
var _dmg_cd := 0.0

signal died(unit: Unit)


func _ready() -> void:
	hp = max_hp
	add_to_group("units")
	for g in self_groups:
		add_to_group(g)
	_cd = randf() * attack_cooldown
	_bob_seed = randf() * TAU
	_setup_rig()


## Les sous-classes peuvent creer un `rig` (SpriteRig) ici pour remplacer le rendu procedural.
func _setup_rig() -> void:
	pass


func _process(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	if not _valid_target(target):
		target = _acquire_target()
	if _valid_target(target) and _cd <= 0.0:
		_attack(target)
		_cd = attack_cooldown

	_anim += delta
	_spawn_t = minf(1.0, _spawn_t + delta * 5.0)
	_flash = maxf(0.0, _flash - delta * 4.0)
	_lunge = _lunge.lerp(Vector2.ZERO, clampf(delta * 9.0, 0.0, 1.0))

	if show_damage_text:
		_dmg_cd = maxf(0.0, _dmg_cd - delta)
		if _dmg_cd <= 0.0 and _dmg_accum >= 1.0:
			var big := _dmg_accum >= maxf(38.0, max_hp * 0.22)
			Fx.text(position + Vector2(0, -radius - hp_offset - 4.0), str(roundi(_dmg_accum)),
				Palette.GOLD_TEXT if big else Color(1, 1, 1, 0.85), 20 if big else 13)
			if big:
				Fx.shake(1.5)
			_dmg_accum = 0.0
			_dmg_cd = 0.28

	if rig != null:
		rig.set_flash(_flash)
		rig.position = _lunge
		rig.scale = Vector2.ONE * _spawn_scale()

	queue_redraw()


func _valid_target(t) -> bool:
	return is_instance_valid(t) and t is Unit and t.hp > 0.0 \
		and global_position.distance_to(t.global_position) <= attack_range


func _acquire_target() -> Unit:
	var best: Unit = null
	var best_score := -INF
	for u in get_tree().get_nodes_in_group(target_group):
		if not (u is Unit) or not is_instance_valid(u) or u.hp <= 0.0:
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d > attack_range:
			continue
		var score := _target_score(u, d)
		if score > best_score:
			best_score = score
			best = u
	return best


func _target_score(u: Unit, d: float) -> float:
	match target_priority:
		"near": return -d
		"strong": return u.hp
		"weak": return -u.hp
		_:
			# "first": le plus avance sur le chemin (sinon le plus proche)
			if u.has_method("progress"):
				return u.progress() * 1000.0 - d
			return -d


## Point d'ou partent les projectiles / effets (centre visible de l'entite).
func muzzle() -> Vector2:
	return global_position


func _attack(t: Unit) -> void:
	t.take_damage(damage)
	_lunge = (t.global_position - global_position).normalized() * 5.0


func take_damage(amount: float, _source: Node = null) -> float:
	if hp <= 0.0:
		return 0.0
	var dealt := minf(hp, amount)
	hp = maxf(0.0, hp - amount)
	_flash = 1.0
	_dmg_accum += amount
	if hp <= 0.0:
		died.emit(self)
		_on_death()
	return dealt


func _on_death() -> void:
	queue_free()


# --- rendu -------------------------------------------------------------------

func _spawn_scale() -> float:
	var e := clampf(_spawn_t, 0.0, 1.0)
	return maxf(0.04, e * (2.0 - e))   # ease-out, jamais 0 (matrice singuliere)


func _draw() -> void:
	var s := _spawn_scale()

	# ombre de contact douce : 3 anneaux -> l'unite est POSEE au sol
	draw_set_transform(Vector2(1.5, radius * 0.78), 0.0, Vector2(1.25, 0.44) * s)
	draw_circle(Vector2.ZERO, radius * 1.15, Color(0, 0, 0, 0.14))
	draw_circle(Vector2.ZERO, radius * 0.85, Color(0, 0, 0, 0.20))
	draw_circle(Vector2.ZERO, radius * 0.55, Color(0, 0, 0, 0.26))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if rig == null:
		var bob := (sin(_anim * 5.0 + _bob_seed) * 1.6) if bobs else 0.0
		draw_set_transform(_lunge + Vector2(0, bob), 0.0, Vector2.ONE * s)
		_draw_body(body_color.lerp(Color(1, 1, 1), _flash * 0.75))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if rig != null or s > 0.98:
		_draw_hp()


func _draw_body(col: Color) -> void:
	draw_circle(Vector2.ZERO, radius, col)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 28, col.darkened(0.45), 2.0)


func _draw_hp() -> void:
	if hp >= max_hp or hp <= 0.0:
		return
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	var w := (radius + hp_offset * 0.35) * 2.2
	var p := Vector2(-w * 0.5, -radius - hp_offset - 8.0)
	draw_rect(Rect2(p, Vector2(w, 4.0)), Palette.HP_BG)
	var col := Palette.HP_GOOD if frac > 0.35 else Palette.HP_LOW
	draw_rect(Rect2(p, Vector2(w * frac, 4.0)), col)
