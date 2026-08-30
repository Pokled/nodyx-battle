class_name WaveCard
extends PanelContainer
## Petite carte d'apercu d'un groupe d'ennemis de la prochaine vague.

func setup(tid: String, count: int, is_champ: bool) -> void:
	var col: Color = Color(0.85, 0.30, 0.30) if is_champ else Enemy.TYPE_COLOR.get(tid, Color.WHITE)
	var label: String = "CHAMPION" if is_champ else Enemy.TYPES.get(tid, {"label": tid})["label"]
	var traits: Array = ["BOSS"] if is_champ else Enemy.TYPE_TRAITS.get(tid, [])

	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "%s x%d\n%s" % [label, count, ", ".join(PackedStringArray(traits)) if traits.size() else "ennemi de base"]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.PANEL_BG
	sb.set_corner_radius_all(5)
	sb.border_color = col
	sb.border_width_top = 3
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 4
	add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 5)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	var dot := _EnemyDot.new()
	dot.color = col
	dot.is_champ = is_champ
	head.add_child(dot)
	var name_lbl := _lbl("%d x %s" % [count, label], col.lightened(0.25), 13)
	head.add_child(name_lbl)

	if traits.size() > 0:
		v.add_child(_lbl(" · ".join(PackedStringArray(traits)),
			Color(1.0, 0.55, 0.4) if is_champ else Palette.TEXT_DIM, 10))


func _lbl(text: String, col: Color, sz: int) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", sz)
	return l


class _EnemyDot extends Control:
	var color := Color.WHITE
	var is_champ := false

	func _init() -> void:
		custom_minimum_size = Vector2(16, 18)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := 7.0 if is_champ else 6.0
		draw_circle(c, r, color)
		draw_arc(c, r, 0.0, TAU, 16, color.darkened(0.4), 1.5)
		# petites cornes
		draw_line(c + Vector2(-r * 0.7, -r * 0.5), c + Vector2(-r * 1.3, -r * 1.2), color.darkened(0.2), 2.0)
		draw_line(c + Vector2(r * 0.7, -r * 0.5), c + Vector2(r * 1.3, -r * 1.2), color.darkened(0.2), 2.0)
		if is_champ:
			draw_arc(c, r + 3.0, 0.0, TAU, 16, Color(1, 0.3, 0.3, 0.7), 1.5)
