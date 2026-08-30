class_name Peon
extends Node2D
## Ouvrier place dans un rail d'economie. `kind` = "peon" (mine -> minerai) ou
## "fermier" (ferme -> nourriture). Produit en continu pendant le COMBAT.

const YIELD_PER_SEC := 0.7

var kind := "peon"            ## "peon" | "fermier"

var _acc := 0.0
var _anim := 0.0
var _life := 0.0
var _pulse := 0.0


func _ready() -> void:
	add_to_group("peons" if kind == "peon" else "fermiers")
	_anim = randf() * TAU


func _group() -> String:
	return "peons" if kind == "peon" else "fermiers"


func _process(delta: float) -> void:
	_anim += delta
	_life += delta
	_pulse = maxf(0.0, _pulse - delta * 3.0)
	# la recolte ne rapporte QUE pendant le combat (pas d'attente infinie en construction)
	var working := GameState.phase == GameState.Phase.COMBAT and not GameState.finished
	modulate.a = 1.0 if working else 0.45
	if not working:
		queue_redraw()
		return
	# rendement decroissant : les premiers ouvriers rapportent plus que les derniers
	var count: int = get_tree().get_nodes_in_group(_group()).size()
	var falloff := 18.0 / (18.0 + float(maxi(0, count - 3)))
	_acc += (YIELD_PER_SEC + Meta.peon_yield_bonus) * falloff * delta
	if _acc >= 1.0:
		var whole := floori(_acc)
		if kind == "fermier":
			GameState.add_nourriture(whole)
		else:
			GameState.add_minerai(whole)
		_acc -= whole
		_pulse = 1.0
		if randf() < 0.18:
			Fx.burst(position, _tint().lightened(0.2), 2, 24.0)
	queue_redraw()


func _tint() -> Color:
	return Color(0.55, 0.80, 0.40) if kind == "fermier" else Palette.PEON


func _draw() -> void:
	var s := clampf(_life * 4.0, 0.0, 1.0)
	s = maxf(0.04, s * (2.0 - s)) * (1.0 + _pulse * 0.10)
	var body := _tint()

	draw_set_transform(Vector2(0, 9.0), 0.0, Vector2(1.1, 0.5) * s)
	draw_circle(Vector2.ZERO, 11.0, Palette.SHADOW)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * s)
	draw_circle(Vector2(0, 1.0), 11.0, body)
	draw_arc(Vector2(0, 1.0), 11.0, 0.0, TAU, 20, body.darkened(0.4), 2.0)

	var swing := sin(_anim * 7.0) * 0.6 - 0.35
	draw_set_transform(Vector2(3.0, -2.0), swing, Vector2.ONE * s)
	if kind == "fermier":
		# faux / outil de moisson
		draw_line(Vector2.ZERO, Vector2(11.0, -9.0), Color(0.60, 0.44, 0.28), 2.5)
		draw_arc(Vector2(11.0, -9.0), 6.0, -1.2, 0.6, 10, Color(0.85, 0.87, 0.92), 2.5)
	else:
		# pioche
		draw_line(Vector2.ZERO, Vector2(10.0, -10.0), Color(0.60, 0.44, 0.28), 2.5)
		draw_line(Vector2(6.0, -13.0), Vector2(13.0, -7.0), Color(0.85, 0.87, 0.92), 3.0)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
