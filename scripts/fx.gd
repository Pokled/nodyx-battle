extends Node
## Autoload `Fx`. Effets visuels jetables: particules, texte flottant, anneaux,
## eclats, screen-shake. `setup()` est appele par main.gd.

var _root: Node2D = null            ## parent des effets (espace monde = repere arene)
var _shake_target: Node2D = null
var _shake_base := Vector2.ZERO
var _shake := 0.0
var _pops: Array = []               ## anneaux + eclats


func setup(root: Node2D, shake_target: Node2D, shake_base: Vector2) -> void:
	_root = root
	_shake_target = shake_target
	_shake_base = shake_base
	_pops.clear()
	var canvas := FxCanvas.new()
	canvas.z_index = 40
	root.add_child(canvas)


func _process(delta: float) -> void:
	if not is_instance_valid(_shake_target):
		return
	if _shake > 0.05:
		_shake = lerpf(_shake, 0.0, clampf(delta * 12.0, 0.0, 1.0))
		_shake_target.position = _shake_base + Vector2(
			randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	elif _shake_target.position != _shake_base:
		_shake = 0.0
		_shake_target.position = _shake_base


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func ring(pos: Vector2, color: Color, r0 := 6.0, r1 := 30.0, life := 0.33) -> void:
	if not is_instance_valid(_root):
		return
	_pops.append({"kind": "ring", "pos": pos, "age": 0.0, "life": life,
		"color": color, "r0": r0, "r1": r1})


func explosion(pos: Vector2, radius: float, color: Color) -> void:
	if not is_instance_valid(_root):
		return
	# flash central
	_pops.append({"kind": "ring", "pos": pos, "age": 0.0, "life": 0.14,
		"color": Color(1.0, 0.95, 0.75), "r0": radius * 0.7, "r1": 2.0})
	# double onde de choc
	_pops.append({"kind": "ring", "pos": pos, "age": 0.0, "life": 0.36,
		"color": color, "r0": radius * 0.3, "r1": radius})
	_pops.append({"kind": "ring", "pos": pos, "age": -0.06, "life": 0.42,
		"color": color.lightened(0.2), "r0": radius * 0.15, "r1": radius * 1.15})
	# eclats de feu
	for i in 14:
		var ang := randf() * TAU
		_pops.append({"kind": "shard", "pos": pos,
			"vel": Vector2.RIGHT.rotated(ang) * randf_range(radius * 1.5, radius * 4.5),
			"age": 0.0, "life": randf_range(0.25, 0.45),
			"color": color.lerp(Color(1, 0.85, 0.4), randf()),
			"rot": randf() * TAU, "rotv": randf_range(-12.0, 12.0), "size": randf_range(3.0, 7.0)})
	burst(pos, color.lerp(Color(1, 0.7, 0.3), 0.4), 16, radius * 3.0)


func shards(pos: Vector2, color: Color, count := 6) -> void:
	if not is_instance_valid(_root):
		return
	for i in count:
		var ang := randf() * TAU
		_pops.append({"kind": "shard", "pos": pos,
			"vel": Vector2.RIGHT.rotated(ang) * randf_range(45.0, 150.0),
			"age": 0.0, "life": randf_range(0.35, 0.6), "color": color,
			"rot": randf() * TAU, "rotv": randf_range(-9.0, 9.0), "size": randf_range(3.0, 6.0)})


func burst(pos: Vector2, color: Color, amount := 10, speed := 90.0) -> void:
	if not is_instance_valid(_root):
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.5
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 140)
	p.damping_min = 20.0
	p.damping_max = 60.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = color
	_root.add_child(p)
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func strip_anim(pos: Vector2, path: String, frames: int, fps := 24.0, scale := 1.0, color := Color.WHITE) -> void:
	if not is_instance_valid(_root):
		return
	var tex := load(path)
	if tex == null:
		return
	var s := AnimStrip.new()
	s.centered = true
	s.position = pos
	s.scale = Vector2.ONE * scale
	s.modulate = color
	s.z_index = 30
	s.fps = fps
	s.loop = false
	s.set_strip(tex, frames)
	s.finished.connect(s.queue_free)
	_root.add_child(s)
	s.play()


func text(pos: Vector2, s: String, color: Color, size := 15) -> void:
	if not is_instance_valid(_root):
		return
	var l := Label.new()
	l.text = s
	l.position = pos + Vector2(-8, -6)
	l.z_index = 60
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_root.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 26.0, 0.7).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.15)
	tw.tween_callback(l.queue_free)


# --- appele par FxCanvas ---------------------------------------------------

func tick(delta: float) -> void:
	for p in _pops:
		p.age += delta
		if p.kind == "shard":
			p.pos += p.vel * delta
			p.vel = p.vel.lerp(Vector2(0, 90), delta * 2.0)
			p.rot += p.rotv * delta
	if not _pops.is_empty():
		_pops = _pops.filter(func(p): return p.age < p.life)


func render(ci: CanvasItem) -> void:
	for p in _pops:
		var t: float = clampf(p.age / p.life, 0.0, 1.0)
		var a := 1.0 - t
		if p.kind == "ring":
			var r: float = lerpf(p.r0, p.r1, t)
			ci.draw_arc(p.pos, r, 0.0, TAU, 40,
				Color(p.color.r, p.color.g, p.color.b, a * 0.6), 2.5)
		else:
			var pts := PackedVector2Array()
			for i in 3:
				pts.append(p.pos + Vector2.RIGHT.rotated(p.rot + i * TAU / 3.0) * (p.size * (0.4 + a)))
			ci.draw_colored_polygon(pts, Color(p.color.r, p.color.g, p.color.b, a))
