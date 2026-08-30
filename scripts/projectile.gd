class_name Projectile
extends Node2D
## Tir de tour. File vers sa cible, applique les degats (+ zone / ralentissement) a l'arrivee.

var target: Node2D = null
var source: Node = null
var speed := 340.0
var damage := 0.0
var color := Color.WHITE
var splash := 0.0
var slow_factor := 1.0
var slow_dur := 0.0
var arc := 0.0            ## hauteur de la parabole (0 = tir tendu)

var _trail: PackedVector2Array = PackedVector2Array()
var _total := -1.0
var _lob := 0.0


func _aim_point() -> Vector2:
	return target.muzzle() if target.has_method("muzzle") else target.global_position


func _process(delta: float) -> void:
	if not is_instance_valid(target) or not (target is Unit) or target.hp <= 0.0:
		_impact(false)
		return
	var to: Vector2 = _aim_point() - global_position
	if _total < 0.0:
		_total = maxf(1.0, to.length())
	if arc > 0.0:
		var prog := clampf(1.0 - to.length() / _total, 0.0, 1.0)
		_lob = -sin(prog * PI) * arc
	var step := speed * delta
	if to.length() <= step:
		global_position = _aim_point()
		_hit(target)
		_impact(true)
		return
	global_position += to.normalized() * step
	_trail.append(global_position + Vector2(0, _lob))
	if _trail.size() > 7:
		_trail.remove_at(0)
	queue_redraw()


func _hit(u) -> void:
	if is_instance_valid(u) and u is Unit and u.hp > 0.0:
		var dealt: float = u.take_damage(damage, source)
		if is_instance_valid(source) and source.has_method("credit_damage"):
			source.credit_damage(dealt)
		if slow_factor < 1.0 and u.has_method("apply_slow"):
			u.apply_slow(slow_factor, slow_dur)


func _impact(hit: bool) -> void:
	if splash > 0.0:
		Fx.explosion(position, splash, Color(0.95, 0.45, 0.2))
		Fx.shake(2.5)
		for u in get_tree().get_nodes_in_group("enemies"):
			if u == target or not (u is Unit) or not is_instance_valid(u):
				continue
			if global_position.distance_to(u.global_position) <= splash:
				_hit(u)
	elif hit:
		Fx.ring(position, color, 3.0, 16.0, 0.20)
		Fx.burst(position, color, 4, 55.0)
	else:
		Fx.ring(position, color, 3.0, 14.0, 0.18)
	queue_free()


func _draw() -> void:
	for i in range(_trail.size() - 1):
		var a := to_local(_trail[i])
		var b := to_local(_trail[i + 1])
		var k := float(i) / maxf(1.0, float(_trail.size()))
		draw_line(a, b, Color(color.r, color.g, color.b, k * 0.45), 2.5)
	var r := 3.0 + (2.5 if splash > 0.0 else 0.0)
	if arc > 0.0:
		draw_circle(Vector2(0, 3), r * 0.7, Color(0, 0, 0, 0.25))   # ombre au sol
	var c := Vector2(0, _lob)
	draw_circle(c, r + 5.0, Color(color.r, color.g, color.b, 0.18))
	draw_circle(c, r + 2.0, Color(color.r, color.g, color.b, 0.35))
	draw_circle(c, r, color)
	draw_circle(c + Vector2(-1, -1), 1.4, Color(1, 1, 1, 0.9))
