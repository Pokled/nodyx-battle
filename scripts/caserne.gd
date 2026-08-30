class_name Caserne
extends Node2D
## Batiment de la GARNISON (mode DUEL). Debloque l'envoi de `troop` chez l'adversaire.
## Empiler plusieurs casernes du meme type monte le niveau d'envoi.

var troop := "grognard"
var invested := 0
var selected := false

var _t := 0.0
var _tint := Color.WHITE


func configure(id: String) -> void:
	troop = Catalog.troop_of(id)
	if troop == "":
		troop = "grognard"
	_tint = Catalog.color(id)


func _ready() -> void:
	add_to_group("casernes")
	z_index = 1
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	# ombre
	draw_set_transform(Vector2(0, 16), 0.0, Vector2(1.2, 0.45))
	draw_circle(Vector2.ZERO, 20.0, Palette.SHADOW)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# tente / baraquement
	var w := 24.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(-w, 14), Vector2(w, 14), Vector2(w, -4), Vector2(0, -20), Vector2(-w, -4)]),
		Color(0.34, 0.30, 0.24))
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -20), Vector2(w + 3, -2), Vector2(w - 4, -2)]), _tint.darkened(0.2))
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -20), Vector2(-w - 3, -2), Vector2(-w + 4, -2)]), _tint.darkened(0.35))
	# entree
	draw_colored_polygon(PackedVector2Array([
		Vector2(-6, 14), Vector2(6, 14), Vector2(5, -2), Vector2(-5, -2)]), Color(0.12, 0.10, 0.08))
	# fanion du type
	var fx := 10.0 + sin(_t * 3.0) * 2.0
	draw_line(Vector2(0, -20), Vector2(0, -34), Color(0.5, 0.45, 0.4), 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -34), Vector2(fx, -30), Vector2(0, -26)]), _tint)

	if selected:
		draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 28, Color(_tint.r, _tint.g, _tint.b, 0.6), 2.0)


func sell_value() -> int:
	return int(round(invested * 0.7))
