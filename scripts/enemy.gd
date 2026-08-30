class_name Enemy
extends Unit
## Ennemi. Type (TYPES) + modificateurs (blinde / rapide / regen / champion).

const TYPES := {
	"grognard": {
		"label": "Grognard", "art": "troll", "h": 78.0, "hp_off": 27.0, "radius": 12.0,
		"hp": 40.0, "speed": 66.0, "dmg": 5.0, "bounty": 4, "leak": 2, "cd": 1.0, "walk_fps": 12.0,
	},
	"rodeur": {
		"label": "Rodeur", "art": "troll2", "h": 70.0, "hp_off": 24.0, "radius": 10.0,
		"hp": 24.0, "speed": 122.0, "dmg": 3.0, "bounty": 4, "leak": 1, "cd": 0.8, "walk_fps": 20.0,
	},
	"colosse": {
		"label": "Colosse", "art": "troll3", "h": 102.0, "hp_off": 40.0, "radius": 16.0,
		"hp": 165.0, "speed": 40.0, "dmg": 13.0, "bounty": 13, "leak": 4, "cd": 1.5, "walk_fps": 9.0,
	},
	"soigneur": {
		"label": "Soigneur", "art": "troll2", "h": 76.0, "hp_off": 26.0, "radius": 12.0,
		"hp": 55.0, "speed": 52.0, "dmg": 2.0, "bounty": 10, "leak": 2, "cd": 1.0, "walk_fps": 13.0,
		"heal": 9.0, "heal_radius": 90.0,
	},
	# fantome : traverse le mur de renforts (comme le mod spectre), rapide et fragile,
	# mais fait mal s'il atteint le roi.
	"spectre": {
		"label": "Spectre", "art": "wraith", "h": 62.0, "hp_off": 22.0, "radius": 10.0,
		"hp": 26.0, "speed": 108.0, "dmg": 4.0, "bounty": 6, "leak": 3, "cd": 0.9, "walk_fps": 14.0,
	},
	# devin : caster a distance qui harcele TES renforts hors de leur portee.
	# lent, gros bounty -> cible prioritaire pour tes tours.
	"sorcier": {
		"label": "Sorcier", "art": "seer", "h": 66.0, "hp_off": 24.0, "radius": 11.0,
		"hp": 60.0, "speed": 46.0, "dmg": 6.0, "bounty": 15, "leak": 2, "cd": 1.7, "walk_fps": 12.0,
		"ranged": 118.0,
	},
}

const MOD_LABEL := {
	"blinde": "Blinde", "rapide": "Rapide", "regen": "Regenerant",
	"spectre": "Spectre", "champion": "CHAMPION",
}

static var heal_tally := 0.0   ## PV soignes ce round (lu/remis a zero par WaveManager)

const TYPE_TRAITS := {
	"grognard": [],
	"rodeur": ["rapide", "fragile"],
	"colosse": ["gros PV", "frappe fort", "lent"],
	"soigneur": ["soigne les allies"],
	"spectre": ["traverse tes renforts", "rapide", "fragile"],
	"sorcier": ["tir a distance", "harcele tes renforts"],
}
const TYPE_COLOR := {
	"grognard": Color(0.55, 0.75, 0.35),
	"rodeur": Color(0.72, 0.76, 0.82),
	"colosse": Color(0.72, 0.48, 0.30),
	"soigneur": Color(0.45, 0.90, 0.50),
	"spectre": Color(0.64, 0.46, 0.88),
	"sorcier": Color(0.88, 0.74, 0.36),
}

@export var move_speed := 66.0
@export var bounty := 4
@export var leak_damage := 2

var type_id := "grognard"
var mods: PackedStringArray = PackedStringArray()
var is_champion := false
var armor := 0.0
var from_send := false    ## DUEL : envoye par l'adversaire (le tuer rapporte de la nourriture)

var _path: PackedVector2Array
var _wp := 0
var _jitter := Vector2.ZERO
var _face := 0.0
var _dying := false
var _slow_factor := 1.0
var _slow_time := 0.0
var _since_hit := 99.0
var _rig_scale := 1.0
var _last_source: Node = null
var _champ_emit := 0.0
var _champ_roar := 4.0
var _heal := 0.0
var _heal_radius := 0.0
var _heal_pulse := 0.0
var _ranged := 0.0        ## sorcier : portee de tir sur les renforts (0 = melee)
var _cast_fx := 0.0

signal gone(leaked: bool)


func configure(id: String, wave: int, wave_mods: PackedStringArray = PackedStringArray()) -> void:
	type_id = id
	mods = wave_mods
	var t: Dictionary = TYPES.get(id, TYPES["grognard"])
	var w := float(wave - 1)
	# lineaire jusqu'a la vague ~13, puis quadratique. Apres la vague 20 (mode sans
	# fin) une 2e rampe quadratique s'ajoute -> pas de plafond, tout finit deborde.
	var ramp := maxf(0.0, w - 12.0)
	var endl := maxf(0.0, w - 20.0)
	var hp_mul := 1.0 + w * 0.11 + ramp * ramp * 0.013 + endl * endl * 0.015
	var dmg_mul := 1.0 + w * 0.05 + ramp * 0.03 + endl * 0.02
	max_hp = t["hp"] * hp_mul
	move_speed = t["speed"] + w * 1.0 + endl * 2.5
	damage = t["dmg"] * dmg_mul
	bounty = int(round(t["bounty"] + w * 0.45))
	leak_damage = t["leak"] + int(w / 5.0)
	attack_cooldown = t["cd"]
	radius = t["radius"]
	_heal = float(t.get("heal", 0.0)) * (1.0 + w * 0.08)
	_heal_radius = float(t.get("heal_radius", 0.0))
	_ranged = float(t.get("ranged", 0.0))

	if "blinde" in mods:
		armor = 3.0 + float(wave) * 0.35
		max_hp *= 1.15
	if "rapide" in mods:
		move_speed *= 1.6
	if "spectre" in mods:
		move_speed *= 1.2
		max_hp *= 0.9
	if "champion" in mods:
		is_champion = true
		max_hp *= 8.0
		radius *= 1.4
		leak_damage = 30
		bounty = int(bounty * 6)
		move_speed *= 0.85
		_rig_scale = 1.55
		show_damage_text = false


func _ready() -> void:
	team = 1
	var phantom := type_id == "spectre" or "spectre" in mods
	target_group = "none" if phantom else "blockers"
	self_groups = PackedStringArray(["enemies"])
	target_priority = "near"
	body_color = Palette.ENEMY
	attack_range = _ranged if _ranged > 0.0 else 46.0
	show_damage_text = show_damage_text and not is_champion
	# decalage lateral persistant -> les ennemis occupent la largeur du couloir
	_jitter = Vector2(randf_range(-8.0, 8.0), randf_range(-17.0, 17.0))
	if is_champion:
		_jitter = Vector2.ZERO
	if phantom:
		modulate.a = 0.62
	super._ready()


func _setup_rig() -> void:
	var t: Dictionary = TYPES.get(type_id, TYPES["grognard"])
	var art: String = t["art"]
	var r := SpriteRig.new()
	r.add_state("walk", "res://art/%s_walk.png" % art, 10, t["walk_fps"], true)
	r.add_state("attack", "res://art/%s_attack.png" % art, 10, 12.0, true)
	r.add_state("die", "res://art/%s_die.png" % art, 10, 14.0, false)
	if r.has_art():
		add_child(r)
		r.configure(t["h"] * _rig_scale, Vector2(0, -8.0), 1)
		r.face(1.0)
		r.set_tint(_mod_tint())
		rig = r
		hp_offset = t["hp_off"] * _rig_scale
		r.play("walk")
	else:
		r.queue_free()


func _mod_tint() -> Color:
	if type_id == "soigneur":
		return Color(0.60, 1.0, 0.65)
	if type_id == "spectre":
		return Color(0.82, 0.66, 1.0)
	if type_id == "sorcier":
		return Color(1.0, 0.92, 0.62)
	if "spectre" in mods:
		return Color(0.80, 0.70, 1.0)
	if "regen" in mods:
		return Color(0.75, 1.0, 0.75)
	if "rapide" in mods:
		return Color(0.75, 0.95, 1.0)
	if "blinde" in mods:
		return Color(0.72, 0.74, 0.80)
	return Color.WHITE


func set_path(p: PackedVector2Array) -> void:
	_path = p
	_wp = 0


func muzzle() -> Vector2:
	return global_position + Vector2(0, -hp_offset * 0.6)


func progress() -> float:
	return float(_wp)


func path_fraction() -> float:
	return clampf(float(_wp) / maxf(1.0, float(_path.size())), 0.0, 1.0)


func apply_slow(factor: float, dur: float) -> void:
	if _dying:
		return
	if Meta.freeze:
		if _slow_factor > 0.05:
			Audio.play("freeze")
		_slow_factor = 0.0
		_slow_time = maxf(_slow_time, 0.5)
		Fx.ring(position, Color(0.6, 0.85, 1.0), 4.0, radius + 8.0, 0.35)
	else:
		_slow_factor = minf(_slow_factor, factor)
		_slow_time = maxf(_slow_time, dur)


func take_damage(amount: float, source: Node = null) -> float:
	if _dying:
		return 0.0
	_since_hit = 0.0
	if source != null:
		_last_source = source
	var eff := amount
	if _slow_time > 0.0 and Meta.slow_vuln > 0.0:
		eff *= 1.0 + Meta.slow_vuln
	if armor > 0.0:
		eff = maxf(eff * 0.15, eff - armor)
	return super.take_damage(eff, source)


func _process(delta: float) -> void:
	if _dying:
		return
	super._process(delta)
	_since_hit += delta
	_cast_fx = maxf(0.0, _cast_fx - delta * 2.5)

	if _slow_time > 0.0:
		_slow_time -= delta
		if _slow_time <= 0.0:
			_slow_factor = 1.0
	if "regen" in mods and _since_hit > 1.6 and hp < max_hp:
		hp = minf(max_hp, hp + max_hp * 0.05 * delta)

	if is_champion:
		if _since_hit > 2.0 and hp < max_hp:
			var r: float = max_hp * 0.035 * delta
			hp = minf(max_hp, hp + r)
			heal_tally += r
		_champ_roar -= delta
		if _champ_roar <= 0.0:
			_champ_roar = 5.5
			Audio.play("champion")
			Fx.shake(7.0)
			Fx.ring(position, Palette.SPAWN, 10.0, radius * 4.0, 0.5)
			var burst: float = minf(max_hp - hp, max_hp * 0.06)
			hp += burst
			heal_tally += burst

	if _heal > 0.0:
		_heal_pulse += delta
		var amt := _heal * delta
		for other in get_tree().get_nodes_in_group("enemies"):
			if other == self or not is_instance_valid(other) or other._dying:
				continue
			if other.hp < other.max_hp and position.distance_to(other.position) <= _heal_radius:
				var g: float = minf(other.max_hp - other.hp, amt)
				other.hp += g
				heal_tally += g

	if rig:
		var tint := Color(0.6, 0.8, 1.0) if _slow_time > 0.0 else _mod_tint()
		if _cast_fx > 0.0:
			tint = tint.lerp(Color(1.0, 0.95, 0.7), _cast_fx * 0.7)
		rig.set_tint(tint)

	if is_champion:
		_champ_emit -= delta
		if _champ_emit <= 0.0:
			_champ_emit = 0.12
			GameState.champion.emit(hp, max_hp, true)

	var engaged := _valid_target(target)
	if engaged:
		var d: Vector2 = target.global_position - global_position
		if d.length() > 1.0:
			_face = d.angle()
		if rig:
			rig.play("attack")
			rig.face(d.x)

	# separation : les ennuis groupes s'ecartent pour remplir le couloir
	position += _separation() * delta

	if engaged:
		return

	if _path.is_empty() or _wp >= _path.size():
		_leak()
		return
	var last := _wp >= _path.size() - 1
	var dest: Vector2 = _path[_wp] + (Vector2.ZERO if last else _jitter)
	var step: Vector2 = dest - position
	if step.length() > 1.0:
		_face = step.angle()
	if rig:
		rig.play("walk")
		rig.face(step.x)
	position = position.move_toward(dest, move_speed * _slow_factor * delta)
	if position.distance_to(dest) < 5.0:
		_wp += 1


func _separation() -> Vector2:
	var push := Vector2.ZERO
	var n := 0
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not is_instance_valid(other):
			continue
		var to: Vector2 = position - other.position
		var dl := to.length()
		if dl < 24.0 and dl > 0.5:
			push += to / dl * (24.0 - dl)
			n += 1
		if n >= 6:
			break
	return push.limit_length(38.0)


func _attack(t: Unit) -> void:
	if _slow_factor <= 0.05:   # gele : ne frappe pas
		return
	if _ranged > 0.0:
		_cast_bolt(t)
		return
	super._attack(t)


func _cast_bolt(t: Unit) -> void:
	var m := muzzle()
	var p := Projectile.new()
	p.target = t
	p.source = self
	p.damage = damage
	p.color = Color(0.95, 0.82, 0.42)
	p.speed = 320.0
	get_parent().add_child(p)
	p.global_position = m + (t.muzzle() - m).normalized() * 6.0
	_cast_fx = 1.0
	Fx.ring(position + Vector2(0, -hp_offset * 0.6), p.color, 3.0, 15.0, 0.22)
	Audio.play("shoot_givre")


func _leak() -> void:
	if hp <= 0.0 or _dying:
		return
	_dying = true
	hp = 0.0
	remove_from_group("enemies")
	gone.emit(true)
	if is_champion:
		GameState.champion.emit(0.0, max_hp, false)
	Audio.play("leak")
	Fx.text(position, "-%d PV" % leak_damage, Palette.DANGER_TEXT)
	Fx.ring(position, Palette.KING, 8.0, 44.0, 0.4)
	Fx.burst(position, Palette.KING, 8, 80.0)
	Fx.shake(6.0 if not is_champion else 16.0)
	GameState.take_king_damage(leak_damage)
	queue_free()


func _on_death() -> void:
	if _dying:
		return
	_dying = true
	remove_from_group("enemies")
	gone.emit(false)
	if is_champion:
		GameState.champion.emit(0.0, max_hp, false)
	if is_instance_valid(_last_source) and _last_source.has_method("credit_kill"):
		_last_source.credit_kill()
	Audio.play("kill")
	Fx.text(position, "+%d" % bounty, Palette.GOLD_TEXT, 17 if is_champion else 15)
	Fx.ring(position, Palette.ENEMY, 6.0, 26.0 * _rig_scale, 0.30)
	Fx.burst(position, Palette.ENEMY, 8 if not is_champion else 24, 105.0)
	if is_champion:
		Fx.shake(10.0)
	GameState.add_minerai(bounty)

	if rig:
		rig.die_finished.connect(_finish_death, CONNECT_ONE_SHOT)
		rig.play_die()
	else:
		Fx.shards(position, Palette.ENEMY, 7)
		_finish_death()


func _finish_death() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)


func _draw() -> void:
	super._draw()
	if armor > 0.0 and hp > 0.0 and not _dying:
		draw_arc(Vector2.ZERO, radius + 3.0, -2.4, -0.7, 8, Color(0.7, 0.8, 0.95, 0.7), 2.0)
	if _heal > 0.0 and not _dying:
		var pr := _heal_radius * (0.55 + 0.06 * sin(_heal_pulse * 4.0))
		draw_arc(Vector2.ZERO, pr, 0.0, TAU, 40, Color(0.4, 0.95, 0.5, 0.18), 2.0)
		var c := Vector2(0, -radius - 6.0)
		draw_line(c + Vector2(-3, 0), c + Vector2(3, 0), Color(0.5, 1.0, 0.6), 2.0)
		draw_line(c + Vector2(0, -3), c + Vector2(0, 3), Color(0.5, 1.0, 0.6), 2.0)


func _draw_body(col: Color) -> void:
	draw_circle(Vector2.ZERO, radius, col)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, col.darkened(0.5), 2.0)
	var f := Vector2.RIGHT.rotated(_face)
	var perp := f.orthogonal()
	draw_circle(f * 2.5 + perp * 4.0, 2.2, Color(0.05, 0.05, 0.05))
	draw_circle(f * 2.5 - perp * 4.0, 2.2, Color(0.05, 0.05, 0.05))
