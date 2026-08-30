class_name HudKit
extends RefCounted
## Boite a outils du HUD (refonte triple-A). StyleBoxFlat + custom-draw only.
## Voir scratchpad/hud_spec_converged.md.

# ============================ POLICE ============================

## Fausse "petite capitale" : to_upper() + espacement inter-glyphe.
static func tracked_font(px: float) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.spacing_glyph = int(round(px))
	return fv


# ============================ PANNEAUX ============================

static func sb_panel(raised := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Palette.PANEL_RAISED if raised else Palette.PANEL
	s.set_corner_radius_all(5)
	s.corner_detail = 6
	s.anti_aliasing = true
	s.set_border_width_all(2)
	s.border_color = Palette.BORDER_BRONZE
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.shadow_size = 12 if raised else 8
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_offset = Vector2(0, 4)
	return s


## Panneau qui borde un cote de l'ecran : bordure + coins seulement sur la face carte.
static func sb_panel_edge(face: int) -> StyleBoxFlat:
	var s := sb_panel(false)
	s.set_border_width_all(0)
	s.set_corner_radius_all(0)
	s.shadow_size = 16
	s.shadow_offset = Vector2.ZERO
	s.border_color = Palette.BORDER_BRONZE
	match face:
		SIDE_RIGHT:
			s.border_width_left = 2
			s.corner_radius_top_left = 6
			s.corner_radius_bottom_left = 6
		SIDE_LEFT:
			s.border_width_right = 2
			s.corner_radius_top_right = 6
			s.corner_radius_bottom_right = 6
		SIDE_TOP:
			s.border_width_bottom = 2
		SIDE_BOTTOM:
			s.border_width_top = 2
			s.corner_radius_top_left = 6
			s.corner_radius_top_right = 6
	return s


## Ajoute le bevel (filet clair haut-gauche / noir bas-droite) + equerres aux 4 coins.
static func add_ornament(host: Control, gold := false, brackets := true, radius := 5.0) -> Control:
	var o := _Ornament.new()
	o.gold = gold
	o.brackets = brackets
	o.radius = radius
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(o)
	return o


class _Ornament extends Control:
	var gold := false
	var brackets := true
	var radius := 5.0
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var r := radius
		draw_line(Vector2(r, 1.0), Vector2(w - r, 1.0), Palette.BEVEL_HI, 1.0)
		draw_line(Vector2(1.0, r), Vector2(1.0, h - r), Color(Palette.BEVEL_HI.r, Palette.BEVEL_HI.g, Palette.BEVEL_HI.b, 0.05), 1.0)
		draw_line(Vector2(r, h - 1.0), Vector2(w - r, h - 1.0), Palette.BEVEL_LO, 1.5)
		draw_line(Vector2(w - 1.0, r), Vector2(w - 1.0, h - r), Color(0, 0, 0, 0.30), 1.0)
		if not brackets:
			return
		var col := Palette.BORDER_GOLD if gold else Palette.BORDER_BRONZE
		var lg := 9.0
		for cx: float in [0.0, w]:
			for cy: float in [0.0, h]:
				var dx := 1.0 if cx == 0.0 else -1.0
				var dy := 1.0 if cy == 0.0 else -1.0
				var o := Vector2(cx + dx * 3.0, cy + dy * 3.0)
				draw_line(o, o + Vector2(dx * lg, 0), col, 2.0)
				draw_line(o, o + Vector2(0, dy * lg), col, 2.0)


# ============================ EN-TETE DE SECTION ============================

static func add_section(parent: Node, title: String, icon_kind := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	if icon_kind != "":
		var ic := HudIcon.new()
		ic.custom_minimum_size = Vector2(15, 15)
		ic.setup(icon_kind, Palette.BORDER_GOLD)
		row.add_child(ic)
	var l := Label.new()
	l.text = title.to_upper()
	l.add_theme_font_override("font", tracked_font(2))
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Palette.TEXT_TITLE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	var rule := _Rule.new()
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.custom_minimum_size = Vector2(0, 14)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rule)
	return row


class _Rule extends Control:
	func _draw() -> void:
		var y := roundf(size.y * 0.5)
		draw_line(Vector2(4, y), Vector2(size.x, y), Color(Palette.BORDER_BRONZE.r, Palette.BORDER_BRONZE.g, Palette.BORDER_BRONZE.b, 0.55), 1.0)
		draw_line(Vector2(4, y + 1), Vector2(size.x, y + 1), Color(0, 0, 0, 0.25), 1.0)


class _VRule extends Control:
	func _draw() -> void:
		var x := roundf(size.x * 0.5)
		draw_line(Vector2(x, 3), Vector2(x, size.y - 3), Color(Palette.BORDER_BRONZE.r, Palette.BORDER_BRONZE.g, Palette.BORDER_BRONZE.b, 0.45), 1.0)


# ============================ CARTES DE CONSTRUCTION ============================

static func sb_card(state: String) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(4)
	s.corner_detail = 6
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.set_border_width_all(1)
	match state:
		"normal":
			s.bg_color = Color(0.123, 0.108, 0.094)
			s.border_color = Palette.BORDER_DIM
		"hover":
			s.bg_color = Color(0.152, 0.133, 0.114)
			s.border_color = Palette.BORDER_BRONZE
		"pressed":
			s.bg_color = Color(0.098, 0.086, 0.075)
			s.border_color = Palette.BORDER_BRONZE
			s.content_margin_top = 9
			s.content_margin_bottom = 7
		"selected":
			s.bg_color = Color(0.170, 0.142, 0.104)
			s.set_border_width_all(2)
			s.border_color = Palette.BORDER_GOLD
			s.shadow_size = 6
			s.shadow_color = Color(Palette.BORDER_GOLD.r, Palette.BORDER_GOLD.g, Palette.BORDER_GOLD.b, 0.20)
			s.shadow_offset = Vector2.ZERO
		"disabled":
			s.bg_color = Color(0.082, 0.073, 0.063)
			s.border_color = Color(0.150, 0.130, 0.110)
	return s


static func sb_well(accent := Color(0, 0, 0, 0), selected := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Palette.WELL
	s.set_corner_radius_all(3)
	s.set_border_width_all(2)
	if selected:
		s.border_color = Palette.BORDER_GOLD
	elif accent.a > 0.0:
		s.border_color = accent.lerp(Palette.BORDER_BRONZE, 0.55)
	else:
		s.border_color = Palette.BORDER_BRONZE
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


# ============================ BOUTONS ============================

static func _states(b: Button, base: Color, hi: Color, deep: Color, rim: Color, font_col: Color) -> void:
	for st in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(4)
		s.corner_detail = 6
		s.content_margin_left = 16
		s.content_margin_right = 16
		s.content_margin_top = 7
		s.content_margin_bottom = 8
		s.set_border_width_all(1)
		s.border_width_bottom = 3
		s.border_color = rim
		match st:
			"normal": s.bg_color = base
			"hover": s.bg_color = hi
			"pressed":
				s.bg_color = deep
				s.border_width_bottom = 1
				s.content_margin_top = 9
				s.content_margin_bottom = 6
			"disabled":
				s.bg_color = Palette.BTN_OFF
				s.border_color = Color(0.20, 0.17, 0.14)
				s.border_width_bottom = 1
		b.add_theme_stylebox_override(st, s)
	b.add_theme_color_override("font_color", font_col)
	b.add_theme_color_override("font_hover_color", font_col)
	b.add_theme_color_override("font_pressed_color", font_col)
	b.add_theme_color_override("font_disabled_color", Palette.TEXT_MUTE)
	b.add_theme_font_size_override("font_size", 14)
	b.focus_mode = Control.FOCUS_NONE


static func btn_primary(b: Button) -> void:
	_states(b, Palette.BTN_GREEN, Palette.BTN_GREEN_HI, Palette.BTN_GREEN_DEEP, Palette.BTN_GREEN_RIM, Color(0.93, 0.97, 0.88))


static func btn_danger(b: Button) -> void:
	_states(b, Palette.BTN_DANGER, Palette.BTN_DANGER_HI, Palette.BTN_DANGER_DEEP, Palette.BTN_DANGER_RIM, Palette.TEXT_TITLE)


static func btn_neutral(b: Button) -> void:
	_states(b, Palette.BTN, Palette.BTN_HOVER, Palette.BTN_PRESS, Palette.BORDER_BRONZE, Palette.TEXT)


static func btn_icon(b: Button) -> void:
	b.custom_minimum_size = Vector2(40, 40)
	b.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(4)
		s.set_border_width_all(2)
		s.border_color = Palette.BORDER_BRONZE
		s.content_margin_left = 6
		s.content_margin_right = 6
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		match st:
			"normal": s.bg_color = Color(0.113, 0.099, 0.086)
			"hover":
				s.bg_color = Color(0.156, 0.137, 0.117)
				s.border_color = Palette.BORDER_GOLD
			"pressed": s.bg_color = Color(0.086, 0.075, 0.065)
			"disabled":
				s.bg_color = Color(0.075, 0.066, 0.057)
				s.border_color = Color(0.20, 0.17, 0.14)
		b.add_theme_stylebox_override(st, s)


static func style_tab(b: Button, active: bool) -> void:
	b.focus_mode = Control.FOCUS_NONE
	var s := StyleBoxFlat.new()
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 0
	s.corner_radius_bottom_right = 0
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	if active:
		s.bg_color = Color(0.231, 0.075, 0.078)
		s.border_width_bottom = 3
		s.border_color = Palette.BORDER_GOLD
	else:
		s.bg_color = Color(0.082, 0.072, 0.063)
		s.border_width_bottom = 1
		s.border_color = Color(0, 0, 0, 0.35)
	for st in ["normal", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, s)
	var hov := s.duplicate()
	if not active:
		hov.bg_color = Color(0.112, 0.098, 0.085)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_color_override("font_color", Palette.TEXT_TITLE if active else Palette.TEXT_DIM)
	b.add_theme_color_override("font_hover_color", Palette.TEXT_TITLE if active else Palette.TEXT)
	b.add_theme_font_override("font", tracked_font(1))
	b.add_theme_font_size_override("font_size", 12)


# ============================ PASTILLES / BARRES ============================

static func sb_pill() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.070, 0.061, 0.052, 0.95)
	s.set_corner_radius_all(13)
	s.set_border_width_all(1)
	s.border_color = Color(0.360, 0.280, 0.160)
	s.content_margin_left = 10
	s.content_margin_right = 14
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


static func sb_pill_group() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.074, 0.064, 0.055)
	s.set_corner_radius_all(8)
	s.set_border_width_all(1)
	s.border_color = Color(0.30, 0.24, 0.14)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func sb_track() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Palette.TRACK_DARK
	s.set_corner_radius_all(3)
	s.set_border_width_all(1)
	s.border_color = Color(0, 0, 0, 0.55)
	return s


static func sb_fill(col: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(3)
	s.border_width_top = 1
	s.border_color = col.lightened(0.30)
	return s
