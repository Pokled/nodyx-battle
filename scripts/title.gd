extends Control
## Ecran-titre. Fond shader + titre anime + JOUER.

const HUD_H := 92
const VIEW_H := 668.0

var _t := 0.0
var _title: Label


func _ready() -> void:
	# activite Nodyx : le jeu est embarque dans un salon vocal. Le pont
	# nodyx-activity.js est deja defini a ce stade ; on attend juste que la
	# poignee de main hote ait livre le roster (window.NodyxBattle.__ready),
	# puis on saute directement dans le salon avec le backend "nodyx".
	if OS.has_feature("web"):
		var w = JavaScriptBridge.get_interface("window")
		if w != null and w.NodyxBattle:
			if await _enter_nodyx_activity():
				return
			# l'hote n'a jamais repondu : on retombe sur l'ecran-titre normal.

	# lien de partie directe : ?room=CODE (+ ?host=) -> on saute dans le salon
	if Net.cmdline_opt("room") != "" or Net.cmdline_opt("code") != "":
		GameState.mode = GameState.Mode.DUEL
		Meta.reset()
		Net.configure(Net.cmdline_opt("net") if Net.cmdline_opt("net") != "" else "ws")
		Net.open({})
		get_tree().change_scene_to_file.call_deferred("res://scenes/lobby.tscn")
		return

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

	var dust := CPUParticles2D.new()
	dust.amount = 40
	dust.lifetime = 8.0
	dust.preprocess = 5.0
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(460, 360)
	dust.position = Vector2(416, 334)
	dust.direction = Vector2(1, -0.3)
	dust.spread = 40.0
	dust.gravity = Vector2.ZERO
	dust.initial_velocity_min = 4.0
	dust.initial_velocity_max = 13.0
	dust.scale_amount_min = 1.0
	dust.scale_amount_max = 2.6
	dust.color = Color(1, 1, 1, 0.06)
	add_child(dust)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -280
	box.offset_right = 280
	box.offset_top = -130
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	_title = Label.new()
	_title.text = "NODYX BATTLE"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 64)
	_title.add_theme_color_override("font_color", Palette.KING)
	_title.add_theme_constant_override("outline_size", 8)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	box.add_child(_title)

	var sub := Label.new()
	sub.text = "Tower defense : farme le minerai, construis ton labyrinthe, tiens la ligne."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Palette.TEXT_DIM)
	box.add_child(sub)

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 18)
	box.add_child(pad)

	var play := Button.new()
	play.name = "Jouer"
	play.text = "JOUER"
	play.focus_mode = Control.FOCUS_NONE
	play.mouse_filter = Control.MOUSE_FILTER_STOP
	play.custom_minimum_size = Vector2(220, 52)
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play.add_theme_font_size_override("font_size", 22)
	for st in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(6)
		s.set_border_width_all(2)
		s.border_color = Palette.BORDER_BRONZE
		s.bg_color = Color(0.20, 0.42, 0.30) if st == "normal" else Color(0.26, 0.55, 0.38)
		play.add_theme_stylebox_override(st, s)
	play.add_theme_color_override("font_color", Color(0.88, 1.0, 0.9))
	play.pressed.connect(_start)
	box.add_child(play)

	var hint := Label.new()
	hint.text = "1-7 construire   ·   Espace lancer la vague   ·   clic sur une tour = améliorer / vendre   ·   M musique"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Palette.TEXT_DIM.darkened(0.1))
	box.add_child(hint)

	var credit := Label.new()
	credit.text = "sprites : craftpix.net"
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credit.add_theme_font_size_override("font_size", 10)
	credit.add_theme_color_override("font_color", Palette.TEXT_DIM.darkened(0.3))
	box.add_child(credit)


## Attend la fin de la poignee de main hote (max ~8 s), puis bascule dans le
## salon avec le backend "nodyx". Renvoie false si l'hote n'a jamais repondu.
func _enter_nodyx_activity() -> bool:
	var waited := 0.0
	while waited < 8.0 and not bool(JavaScriptBridge.eval(
			"!!(window.NodyxBattle && window.NodyxBattle.__ready)", true)):
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if not bool(JavaScriptBridge.eval("!!(window.NodyxBattle && window.NodyxBattle.__ready)", true)):
		return false
	# On va a l'ecran de setup : le joueur choisit son mode (solo, contre l'IA,
	# ou course aux rois avec les membres du canal vocal). setup.gd s'adapte.
	GameState.in_nodyx_activity = true
	get_tree().change_scene_to_file.call_deferred("res://scenes/setup.tscn")
	return true


func _process(delta: float) -> void:
	_t += delta
	_title.position.y = sin(_t * 1.5) * 4.0


func _unhandled_input(event: InputEvent) -> void:
	# filet de securite : n'importe quelle touche OU un clic demarre.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER]:
			_start()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_start()


var _starting := false

func _start() -> void:
	if _starting:
		return
	_starting = true
	Audio.play("wave_start")
	get_tree().change_scene_to_file("res://scenes/setup.tscn")
