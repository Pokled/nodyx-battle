extends Control
## Salon d'avant-match.  En Nodyx : c'est la liste des membres du salon vocal.
## En local : 1 humain + bots.  Le host lance ; tout le monde bascule en match.

var _list: VBoxContainer
var _ready_btn: Button
var _start_btn: Button
var _hint: Label
var _local_ready := false


func _ready() -> void:
	RenderingServer.set_default_clear_color(Palette.BG)
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/background.gdshader")
	mat.set_shader_parameter("farm_edge", 1.0)
	mat.set_shader_parameter("top_edge", 0.0)
	bg.material = mat
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.offset_left = -300
	col.offset_right = 300
	col.offset_top = -240
	col.add_theme_constant_override("separation", 12)
	add_child(col)

	var title := Label.new()
	title.text = "SALON  —  COURSE AUX ROIS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Palette.KING)
	col.add_child(title)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Palette.TEXT_DIM)
	col.add_child(_hint)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudKit.sb_panel(true))
	panel.custom_minimum_size = Vector2(560, 0)
	col.add_child(panel)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	panel.add_child(_list)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)

	var back := Button.new()
	back.text = "  RETOUR  "
	HudKit.btn_neutral(back)
	back.pressed.connect(func():
		Net.leave()
		get_tree().change_scene_to_file("res://scenes/setup.tscn"))
	row.add_child(back)

	_ready_btn = Button.new()
	_ready_btn.text = "JE SUIS PRÊT"
	HudKit.btn_primary(_ready_btn)
	_ready_btn.pressed.connect(_toggle_ready)
	row.add_child(_ready_btn)

	_start_btn = Button.new()
	_start_btn.text = "LANCER LA PARTIE"
	HudKit.btn_primary(_start_btn)
	_start_btn.pressed.connect(func(): Net.start_match({}))
	row.add_child(_start_btn)

	Net.lobby_changed.connect(func(_p): _refresh())
	Net.match_started.connect(_on_match_started)
	_refresh()


func _toggle_ready() -> void:
	_local_ready = not _local_ready
	Net.set_ready(_local_ready)
	_ready_btn.text = "PRÊT ✓" if _local_ready else "JE SUIS PRÊT"


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var n := Net.players.size()
	var rm := Net.room()
	if rm != "" and rm != "PUBLIC":
		_hint.text = "SALON  %s   ·   %d joueur%s   —   partage le code à ton ami" % [rm, n, "s" if n > 1 else ""]
	else:
		_hint.text = "%d joueur%s dans le salon" % [n, "s" if n > 1 else ""]
	for p in Net.players:
		var h := PanelContainer.new()
		h.add_theme_stylebox_override("panel", HudKit.sb_well(p.get("color", Color.WHITE), false))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		h.add_child(hb)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.color = p.get("color", Color.WHITE)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(dot)
		var nm := Label.new()
		nm.text = String(p.get("name", "?")) + ("  (toi)" if p.get("is_local", false) else ("  · bot" if p.get("is_bot", false) else ""))
		nm.add_theme_font_size_override("font_size", 15)
		nm.add_theme_color_override("font_color", Palette.TEXT)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(nm)
		var rl := Label.new()
		rl.text = "PRÊT" if p.get("ready", false) else "…"
		rl.add_theme_font_size_override("font_size", 13)
		rl.add_theme_color_override("font_color", Palette.ACCENT_GREEN_LIT if p.get("ready", false) else Palette.TEXT_MUTE)
		hb.add_child(rl)
		_list.add_child(h)
	_start_btn.visible = true
	_start_btn.disabled = n < 2


func _on_match_started(_seed: int, _roster: Array) -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
