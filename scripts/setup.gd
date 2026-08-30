extends Control
## Ecran de preparation: choisis 3 specialites parmi 5.

var _chosen: Array = []
var _cards: Dictionary = {}
var _start: Button
var _count: Label
var _mode: int = GameState.Mode.SOLO
var _net_mode := "solo"          ## solo | duel | local | online
var _mode_btns: Dictionary = {}
var _title: Label
var _host_edit: LineEdit
var _code_edit: LineEdit


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
	col.offset_left = -380
	col.offset_right = 380
	col.offset_top = -230
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", Palette.KING)
	col.add_child(_title)

	# --- choix du mode ---
	var modes := HBoxContainer.new()
	modes.alignment = BoxContainer.ALIGNMENT_CENTER
	modes.add_theme_constant_override("separation", 8)
	col.add_child(modes)
	_mode_btns["solo"] = _mode_button(modes, "solo",
		"CAMPAGNE SOLO", "vagues neutres · victoire vague 20 puis sans fin")
	_mode_btns["local"] = _mode_button(modes, "local",
		"COURSE AUX ROIS", "FFA : chacun sa forteresse, envoie des monstres, dernier roi debout · bots en local")
	_mode_btns["online"] = _mode_button(modes, "online",
		"COURSE AUX ROIS — EN LIGNE", "même chose, entre joueurs (salon vocal Nodyx / relais WebSocket)")

	var hostrow := HBoxContainer.new()
	hostrow.alignment = BoxContainer.ALIGNMENT_CENTER
	hostrow.add_theme_constant_override("separation", 8)
	col.add_child(hostrow)
	var hl := Label.new()
	hl.text = "relais"
	hl.add_theme_color_override("font_color", Palette.TEXT_DIM)
	hl.add_theme_font_size_override("font_size", 12)
	hostrow.add_child(hl)
	_host_edit = LineEdit.new()
	var pre_host := Net.cmdline_opt("host")
	_host_edit.text = pre_host if pre_host != "" else "127.0.0.1:9871"
	_host_edit.editable = pre_host == ""       ## impose par le widget/URL sinon
	_host_edit.custom_minimum_size = Vector2(190, 0)
	hostrow.add_child(_host_edit)
	var cl := Label.new()
	cl.text = "  code salon"
	cl.add_theme_color_override("font_color", Palette.TEXT_DIM)
	cl.add_theme_font_size_override("font_size", 12)
	hostrow.add_child(cl)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "vide = nouveau"
	_code_edit.max_length = 8
	_code_edit.custom_minimum_size = Vector2(120, 0)
	hostrow.add_child(_code_edit)

	_count = Label.new()
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.add_theme_font_size_override("font_size", 14)
	_count.add_theme_color_override("font_color", Palette.TEXT_DIM)
	col.add_child(_count)

	for id in Specs.ORDER:
		col.add_child(_make_card(id))

	_set_mode("solo")

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 10)
	col.add_child(pad)

	_start = Button.new()
	_start.text = "COMMENCER"
	_start.focus_mode = Control.FOCUS_NONE
	_start.custom_minimum_size = Vector2(240, 48)
	_start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_start.add_theme_font_size_override("font_size", 20)
	for st in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(6)
		match st:
			"normal": s.bg_color = Color(0.20, 0.42, 0.30)
			"hover": s.bg_color = Color(0.26, 0.55, 0.38)
			"pressed": s.bg_color = Color(0.18, 0.36, 0.26)
			"disabled": s.bg_color = Palette.BTN_OFF
		_start.add_theme_stylebox_override(st, s)
	_start.add_theme_color_override("font_color", Color(0.88, 1.0, 0.9))
	_start.add_theme_color_override("font_disabled_color", Palette.TEXT_DIM.darkened(0.2))
	_start.pressed.connect(_begin)
	col.add_child(_start)

	_refresh()


func _mode_button(parent: Node, mode: String, label: String, hint: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(300, 48)
	b.text = "%s\n%s" % [label, hint]
	b.add_theme_font_size_override("font_size", 12)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for st in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(6)
		s.content_margin_left = 10
		s.content_margin_right = 10
		s.bg_color = Palette.BTN if st == "normal" else Palette.BTN_HOVER
		b.add_theme_stylebox_override(st, s)
	var sel := StyleBoxFlat.new()
	sel.set_corner_radius_all(6)
	sel.bg_color = Palette.KING.darkened(0.55)
	sel.border_color = Palette.KING
	sel.set_border_width_all(2)
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_color_override("font_color", Palette.TEXT)
	b.toggled.connect(func(on: bool):
		if on:
			_set_mode(mode))
	parent.add_child(b)
	return b


func _set_mode(mode: String) -> void:
	_net_mode = mode
	_mode = GameState.Mode.SOLO if mode == "solo" else GameState.Mode.DUEL
	for m in _mode_btns:
		_mode_btns[m].button_pressed = (m == mode)
	_title.text = "PRÉPARE TON DÉFI" if mode != "solo" else "PRÉPARE TA DÉFENSE"
	var online := mode == "online"
	if is_instance_valid(_host_edit):
		_host_edit.get_parent().visible = online
	Audio.play("place_tower")


func _make_card(id: String) -> Button:
	var info: Dictionary = Specs.SPECS[id]
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 56)
	b.toggle_mode = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.text = "  %s   —   %s" % [info["label"], info["desc"]]
	b.add_theme_font_size_override("font_size", 13)
	for st in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(5)
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.border_width_left = 4
		s.border_color = info["color"]
		s.bg_color = Palette.BTN if st == "normal" else Palette.BTN_HOVER
		b.add_theme_stylebox_override(st, s)
	var sel := StyleBoxFlat.new()
	sel.set_corner_radius_all(5)
	sel.content_margin_left = 12
	sel.bg_color = info["color"].darkened(0.55)
	sel.border_color = info["color"]
	sel.set_border_width_all(2)
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_color_override("font_color", Palette.TEXT)
	b.toggled.connect(func(on: bool): _toggle(id, on))
	_cards[id] = b
	return b


func _toggle(id: String, on: bool) -> void:
	if on:
		if _chosen.size() >= 3:
			_cards[id].button_pressed = false
			return
		_chosen.append(id)
	else:
		_chosen.erase(id)
	Audio.play("place_tower")
	_refresh()


func _refresh() -> void:
	_count.text = "Choisis-en %d de plus" % (3 - _chosen.size()) if _chosen.size() < 3 else "Pret."
	_start.disabled = _chosen.size() != 3


func _gen_code() -> String:
	var chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var s := ""
	for _i in 4:
		s += chars[randi() % chars.length()]
	return s


func _begin() -> void:
	GameState.mode = _mode
	Meta.reset()
	Meta.specs = _chosen.duplicate()
	Audio.play("wave_start")
	match _net_mode:
		"local":
			Net.configure("local")
			Net.open({"bots": 1, "difficulty": 1.0})
			get_tree().change_scene_to_file("res://scenes/lobby.tscn")
		"online":
			var code := _code_edit.text.strip_edges().to_upper()
			if code == "":
				code = _gen_code()
			Net.configure("ws")
			Net.open({"host": _host_edit.text.strip_edges(), "room": code,
				"name": Net.cmdline_opt("name") if Net.cmdline_opt("name") != "" else "Toi"})
			get_tree().change_scene_to_file("res://scenes/lobby.tscn")
		_:
			get_tree().change_scene_to_file("res://scenes/main.tscn")
