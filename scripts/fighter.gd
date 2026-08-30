class_name Fighter
extends Unit
## Unite embauchee. Type = `type_id`. Fixe, dans le groupe "blockers"
## (les ennemis s'arretent pour la combattre).

const TYPES := {
	"guerriere": {
		"art": "warrior", "h": 76.0, "hp_off": 26.0,
		"hp": 135.0, "dmg": 15.0, "rng": 90.0, "cd": 0.8, "ranged": false,
	},
	"archere": {
		"art": "elf", "h": 74.0, "hp_off": 25.0,
		"hp": 58.0, "dmg": 12.0, "rng": 250.0, "cd": 0.82, "ranged": true,
	},
}

var type_id := "guerriere"
var ranged := false
var invested := 0
var selected := false

var _dying := false


func configure(id: String) -> void:
	type_id = id if TYPES.has(id) else "guerriere"


func sell_value() -> int:
	return int(round(invested * Meta.sell_refund * 0.85))


static func base_range(id: String) -> float:
	var t: Dictionary = TYPES[id] if TYPES.has(id) else TYPES["guerriere"]
	return t["rng"] + Meta.rng(id)


func _ready() -> void:
	team = 0
	target_group = "enemies"
	self_groups = PackedStringArray(["blockers"])
	target_priority = "first"
	var t: Dictionary = TYPES.get(type_id, TYPES["guerriere"])
	ranged = t["ranged"]
	body_color = Catalog.color(type_id)
	max_hp = t["hp"] + Meta.fighter_hp_bonus
	damage = t["dmg"] * Meta.dmg(type_id)
	attack_range = t["rng"] + Meta.rng(type_id)
	attack_cooldown = t["cd"]
	radius = 13.0
	super._ready()


func _setup_rig() -> void:
	var t: Dictionary = TYPES.get(type_id, TYPES["guerriere"])
	var art: String = t["art"]
	var r := SpriteRig.new()
	r.add_state("idle", "res://art/%s_idle.png" % art, 10, 9.0, true)
	r.add_state("attack", "res://art/%s_attack.png" % art, 10, 13.0, true)
	r.add_state("die", "res://art/%s_die.png" % art, 10, 12.0, false)
	if r.has_art():
		add_child(r)
		r.configure(t["h"], Vector2(0.0, -8.0), 1)
		r.face(-1.0)
		rig = r
		hp_offset = t["hp_off"]
		r.play("idle")
	else:
		r.queue_free()


func _process(delta: float) -> void:
	if _dying:
		return
	super._process(delta)
	if Meta.fighter_regen > 0.0 and hp > 0.0 and hp < max_hp:
		hp = minf(max_hp, hp + Meta.fighter_regen * delta)
	if rig:
		if _valid_target(target):
			rig.play("attack")
			rig.face(target.global_position.x - global_position.x)
		else:
			rig.play("idle")


## point de tir en GLOBAL (utilise par projectile.gd qui travaille en global).
func muzzle() -> Vector2:
	return global_position + Vector2(0, -hp_offset * 0.85)

## meme point en LOCAL arene (pour les effets Fx qui vivent dans l'espace arene).
func _muzzle_local() -> Vector2:
	return position + Vector2(0, -hp_offset * 0.85)


func _attack(t: Unit) -> void:
	if ranged:
		var m := muzzle()
		var p := Projectile.new()
		p.target = t
		p.damage = damage
		p.color = Catalog.color(type_id).lightened(0.2)
		p.speed = 460.0
		get_parent().add_child(p)
		p.global_position = m + (t.muzzle() - m).normalized() * 6.0
		Audio.play("shoot_gatling")
	else:
		super._attack(t)
		var tl: Vector2 = t.position + Vector2(0, -t.radius * 0.6)
		Fx.strip_anim((_muzzle_local() + tl) * 0.5, "res://art/fx_slash.png", 12, 34.0, 0.7)


func _on_death() -> void:
	if _dying:
		return
	_dying = true
	Fx.burst(position, body_color, 10, 90.0)
	if rig:
		rig.die_finished.connect(_finish_death, CONNECT_ONE_SHOT)
		rig.play_die()
	else:
		_finish_death()


func _finish_death() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)


func _draw() -> void:
	if selected:
		var pr := 1.0 + sin(_anim * 4.0) * 0.02
		draw_arc(Vector2.ZERO, attack_range * pr, 0.0, TAU, 48,
			Color(body_color.r, body_color.g, body_color.b, 0.5), 1.5)
	super._draw()


func _draw_body(col: Color) -> void:
	draw_circle(Vector2.ZERO, radius, col)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, col.darkened(0.45), 2.0)
	if is_instance_valid(target):
		var f := to_local(target.global_position).normalized()
		draw_line(f * 6.0, f * (radius + 9.0), Color(0.85, 0.9, 0.95), 3.0)
