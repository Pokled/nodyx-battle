class_name TowerPopup
extends Control
## Bulle d'info d'une tour OU d'une unite. Tour : type/niveau, stats, priorite,
## ameliorer, vendre. Unite : type, PV, vendre.

signal upgrade_pressed
signal sell_pressed
signal priority_pressed

const W := 232.0
const H := 152.0

var subject: Node = null   ## Tower ou Fighter
var _below := false
var _rt := 0.0
var _bg: Panel
var _title: Label
var _stats: Label
var _life: Label
var _prio: Button
var _up: Button
var _sell: Button


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(W, H)
	clip_contents = false

	_bg = Panel.new()
	_bg.size = Vector2(W, H)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.PANEL_BG
	sb.set_corner_radius_all(8)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_border_width_all(1)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	_bg.add_theme_stylebox_override("panel", sb)
	add_child(_bg)

	_title = _mk_label(Vector2(12, 7), Palette.TEXT, 14)
	_stats = _mk_label(Vector2(12, 28), Palette.TEXT_DIM, 11)
	_life = _mk_label(Vector2(12, 44), Color(0.62, 0.72, 0.62), 11)
	_prio = _mk_button(Vector2(10, 66), func(): priority_pressed.emit())
	_up = _mk_button(Vector2(10, 94), func(): upgrade_pressed.emit())
	_sell = _mk_button(Vector2(10, 122), func(): sell_pressed.emit())

	GameState.minerai_changed.connect(func(_v): _refresh())
	GameState.phase_changed.connect(func(_p): _refresh())


func _mk_label(pos: Vector2, col: Color, sz: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", sz)
	add_child(l)
	return l


func _mk_button(pos: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.position = pos
	b.size = Vector2(W - 20.0, 22.0)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_disabled_color", Palette.TEXT_DIM.darkened(0.2))
	for st in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(4)
		match st:
			"normal": s.bg_color = Palette.BTN
			"hover": s.bg_color = Palette.BTN_HOVER
			"pressed": s.bg_color = Palette.BTN_HOVER.darkened(0.1)
			"disabled": s.bg_color = Palette.BTN_OFF
		b.add_theme_stylebox_override(st, s)
	add_child(b)
	return b


func _fmt(v: float) -> String:
	if v >= 1000.0:
		return "%.1fk" % (v / 1000.0)
	return "%d" % roundi(v)


func open(s: Node) -> void:
	subject = s
	visible = true
	_refresh()


func close() -> void:
	visible = false
	subject = null


func _refresh() -> void:
	if not is_instance_valid(subject):
		close()
		return
	var build: bool = GameState.phase == GameState.Phase.BUILD and not GameState.finished

	if subject is Tower:
		var t: Tower = subject
		_title.text = "%s : Niveau %d" % [Catalog.label(t.type_id), t.level]
		if t.type_id == "givre":
			_stats.text = "Nova de zone : %d dgts / cible   Rayon %d   Toutes les %.1fs   Ralentit -%d%%" % [
				roundi(t.damage), roundi(t.attack_range), t.attack_cooldown,
				roundi((1.0 - Tower.TYPES["givre"]["slow"]) * 100.0)]
		else:
			_stats.text = "Degats %d   Portee %d   DPS %d" % [
				roundi(t.damage), roundi(t.attack_range), roundi(t.dps())]
		var syn := "  ·  synergie +%d%%" % (t.synergy * 8) if t.synergy > 0 else ""
		_life.text = "Bilan : %s dgts · %d elim. · actif %d%%%s" % [
			_fmt(t.stat_damage), t.stat_kills, roundi(t.uptime() * 100.0), syn]
		_prio.visible = t.type_id != "givre"
		_up.visible = true
		_prio.text = "Cible : %s" % t.priority_label()
		if t.can_upgrade():
			var c := t.upgrade_cost()
			_up.text = "Ameliorer  (%d)" % c
			_up.disabled = not build or GameState.minerai < c
		else:
			_up.text = "Niveau maximum"
			_up.disabled = true
		_sell.text = "Vendre  (+%d)" % t.sell_value()
		_sell.disabled = not build
		_sell.position.y = 122.0
		_bg.size.y = H
	elif subject is Fighter:
		var f: Fighter = subject
		_title.text = Catalog.label(f.type_id)
		_stats.text = "PV %d/%d   Degats %d   Portee %d" % [
			roundi(f.hp), roundi(f.max_hp), roundi(f.damage), roundi(f.attack_range)]
		_life.text = "Unite %s" % ("a distance" if f.ranged else "corps a corps")
		_prio.visible = false
		_up.visible = false
		_sell.text = "Vendre  (+%d)" % f.sell_value()
		_sell.disabled = not build
		_sell.position.y = 62.0
		_bg.size.y = 92.0
	elif subject is Caserne:
		var cs: Caserne = subject
		var lvl := int(Versus.unlocked.get(cs.troop, 1))
		_title.text = "Caserne · %s  (niv %d)" % [Enemy.TYPES.get(cs.troop, {"label": cs.troop})["label"], lvl]
		_stats.text = "Envoi : %d nourriture / unite   ·   puissance x%.2f" % [
			int(Versus.SEND_COST.get(cs.troop, 0)), 1.0 + 0.18 * (lvl - 1)]
		_life.text = "Empile des casernes du meme type pour monter le niveau."
		_prio.visible = false
		_up.visible = false
		_sell.text = "Vendre  (+%d nour.)" % cs.sell_value()
		_sell.disabled = not build
		_sell.position.y = 62.0
		_bg.size.y = 92.0


func _process(delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(subject):
		close()
		return
	_rt += delta
	if _rt > 0.25:
		_rt = 0.0
		_refresh()
	var anchor: Vector2 = subject.global_position
	var vw := get_viewport_rect().size.x
	var x := clampf(anchor.x - W * 0.5, 6.0, vw - W - 6.0)
	var y := anchor.y - H - 24.0
	_below = y < 210.0
	if _below:
		y = anchor.y + 26.0
	position = Vector2(x, floorf(y))
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(subject):
		return
	var tip := clampf(subject.global_position.x - position.x, 16.0, W - 16.0)
	var h_used := H if (subject is Tower) else 92.0
	if _below:
		draw_colored_polygon(PackedVector2Array([
			Vector2(tip - 9, 0), Vector2(tip + 9, 0), Vector2(tip, -12)]), Palette.PANEL_BG)
	else:
		draw_colored_polygon(PackedVector2Array([
			Vector2(tip - 9, h_used), Vector2(tip + 9, h_used), Vector2(tip, h_used + 12)]), Palette.PANEL_BG)
