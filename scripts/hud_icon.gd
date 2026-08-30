class_name HudIcon
extends Control
## Icone vectorielle du HUD.  Tout est dessine a la main (pas d'asset image).
## Boite ~20x20 : c = size*0.5, demi-etendue ~9.

var kind := "gem"
var color := Color.WHITE


func _init() -> void:
	custom_minimum_size = Vector2(20, 20)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(k: String, c: Color) -> void:
	kind = k
	color = c
	queue_redraw()


func _draw() -> void:
	HudIcon.paint(self, kind, size * 0.5, color)


## Dessine l'icone `k` centree sur `c` dans le CanvasItem `ci`, teinte `col`.
static func paint(ci: CanvasItem, k: String, c: Vector2, col: Color) -> void:
	var dk := col.darkened(0.35)
	match k:
		"gem":
			var p := PackedVector2Array([c + Vector2(0, -7), c + Vector2(6, -1), c + Vector2(0, 8), c + Vector2(-6, -1)])
			ci.draw_colored_polygon(p, col)
			var o := p; o.append(p[0])
			ci.draw_polyline(o, col.lightened(0.35), 1.0)
		"coin":
			ci.draw_circle(c, 8.0, col)
			ci.draw_arc(c, 8.0, 0, TAU, 20, dk, 1.5)
			ci.draw_arc(c, 4.6, 0, TAU, 16, Color(dk.r, dk.g, dk.b, 0.8), 1.3)
			ci.draw_arc(c + Vector2(-1, -1), 6.2, PI * 0.95, PI * 1.55, 8, Color(1, 0.96, 0.82, 0.55), 1.4)
		"crown":
			var b := c + Vector2(0, 3)
			ci.draw_colored_polygon(PackedVector2Array([
				b + Vector2(-7, 3), b + Vector2(7, 3), b + Vector2(6, -4),
				b + Vector2(2, 0), b + Vector2(0, -6), b + Vector2(-2, 0), b + Vector2(-6, -4)]), col)
			ci.draw_circle(b + Vector2(-3.5, 1.5), 1.0, Palette.ACCENT_RED)
			ci.draw_circle(b + Vector2(0, 1.0), 1.1, Palette.ACCENT_BLUE)
			ci.draw_circle(b + Vector2(3.5, 1.5), 1.0, Palette.ACCENT_RED)
		"heart":
			ci.draw_circle(c + Vector2(-3.2, -2.4), 3.7, col)
			ci.draw_circle(c + Vector2(3.2, -2.4), 3.7, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-6.6, -0.6), c + Vector2(6.6, -0.6), c + Vector2(0, 7.8)]), col)
		"shield":
			var p := PackedVector2Array([c + Vector2(-7, -7), c + Vector2(7, -7), c + Vector2(7, 1.5), c + Vector2(0, 8.5), c + Vector2(-7, 1.5)])
			ci.draw_colored_polygon(p, col.darkened(0.15))
			var o := p; o.append(p[0])
			ci.draw_polyline(o, col.lightened(0.20), 1.6)
			ci.draw_line(c + Vector2(0, -6), c + Vector2(0, 7), Color(0, 0, 0, 0.22), 1.0)
		"skull":
			var bone := Color(0.85, 0.82, 0.74)
			var ink := Color(0.09, 0.07, 0.06)
			ci.draw_circle(c + Vector2(0, -1.5), 6.4, bone)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-4, 3), c + Vector2(4, 3), c + Vector2(2.6, 7.8), c + Vector2(-2.6, 7.8)]), bone)
			ci.draw_circle(c + Vector2(-2.6, -1.4), 1.8, ink)
			ci.draw_circle(c + Vector2(2.6, -1.4), 1.8, ink)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, 0.6), c + Vector2(1.1, 2.8), c + Vector2(-1.1, 2.8)]), ink)
		"wave":
			ci.draw_arc(c + Vector2(0, 3), 7.0, PI, TAU, 14, col, 2.0)
			ci.draw_arc(c + Vector2(0, 3), 3.5, PI, TAU, 10, col, 2.0)
		"phase":
			ci.draw_arc(c, 6.5, -PI / 2.0, PI, 18, col, 2.0)
			ci.draw_circle(c + Vector2(0, -6.5), 1.8, col)
		"hourglass":
			ci.draw_line(c + Vector2(-6, -8), c + Vector2(6, -8), col, 2.0)
			ci.draw_line(c + Vector2(-6, 8), c + Vector2(6, 8), col, 2.0)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-5.4, -7.2), c + Vector2(5.4, -7.2), c]), Color(col.r, col.g, col.b, 0.4))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-5.4, 7.2), c + Vector2(5.4, 7.2), c]), Color(col.r, col.g, col.b, 0.4))
			ci.draw_circle(c + Vector2(0, 2.5), 1.4, col.lightened(0.3))
		"food", "wheat":
			ci.draw_line(c + Vector2(0, 9), c + Vector2(0, -8), col, 2.0)
			for i in 4:
				var yy := -7.0 + i * 4.0
				for s: float in [-1.0, 1.0]:
					var g := c + Vector2(s * 3.4, yy + 1.0)
					ci.draw_colored_polygon(PackedVector2Array([g + Vector2(0, -2.4), g + Vector2(s * 2.2, 0), g + Vector2(0, 2.4), g + Vector2(-s * 0.5, 0)]), col)
		"ore", "pick":
			if k == "ore":
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(4, -1), c + Vector2(0, 8), c + Vector2(-4, -1)]), col)
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-5, 0.5), c + Vector2(-2.6, 3.4), c + Vector2(-4.2, 7), c + Vector2(-7, 3.4)]), col.darkened(0.18))
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(5, 1.5), c + Vector2(7, 4.4), c + Vector2(5, 8), c + Vector2(3, 4.4)]), col.darkened(0.18))
				ci.draw_line(c + Vector2(0, -9), c + Vector2(0, 8), Color(1, 1, 1, 0.28), 1.0)
			else:
				ci.draw_line(c + Vector2(0, 9), c + Vector2(0, -5), Palette.BORDER_BRONZE, 2.0)
				ci.draw_arc(c + Vector2(0, -5), 7.0, PI * 1.15, PI * 1.85, 10, Color(0.55, 0.56, 0.6), 2.4)
		"sword":
			ci.draw_line(c + Vector2(-5, 7), c + Vector2(5, -6.5), Color(0.78, 0.80, 0.84), 2.6)
			ci.draw_line(c + Vector2(4, -8), c + Vector2(7, -5), Color(0.78, 0.80, 0.84), 2.6)
			ci.draw_line(c + Vector2(-7, 2), c + Vector2(-1, -4), Palette.BORDER_BRONZE, 3.0)
			ci.draw_circle(c + Vector2(-6.4, 6.4), 1.8, Palette.BORDER_BRONZE)
		"swords":
			for s: float in [-1.0, 1.0]:
				ci.draw_line(c + Vector2(s * -5, 7), c + Vector2(s * 5, -6.5), Color(0.78, 0.80, 0.84), 2.2)
				ci.draw_line(c + Vector2(s * -7, 2), c + Vector2(s * -1, -4), Palette.BORDER_BRONZE, 2.6)
		"arrow", "bow":
			if k == "bow":
				ci.draw_arc(c + Vector2(1, 0), 8.0, PI * 0.55, PI * 1.45, 16, Palette.BORDER_BRONZE, 2.2)
				ci.draw_line(c + Vector2(-3, -6), c + Vector2(-3, 6), Palette.TEXT_DIM, 1.0)
			ci.draw_line(c + Vector2(-8, 8), c + Vector2(6, -6), col, 2.2)
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -6), c + Vector2(6, -6), c + Vector2(6, 0)]), col, 2.2)
		"cannon":
			ci.draw_circle(c + Vector2(-3, 3), 4.5, Color(0.20, 0.19, 0.18))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-2, 1), c + Vector2(7, -5), c + Vector2(9, -2), c + Vector2(0, 4)]), Color(0.30, 0.29, 0.28))
			ci.draw_arc(c + Vector2(-3, 3), 4.5, 0, TAU, 12, Palette.BORDER_BRONZE, 1.5)
		"keep", "caserne":
			ci.draw_rect(Rect2(c + Vector2(-5, -2), Vector2(10, 9)), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-7, -2), c + Vector2(0, -8), c + Vector2(7, -2)]), col.darkened(0.2))
			ci.draw_rect(Rect2(c + Vector2(-1.5, 2), Vector2(3, 5)), Palette.INK)
		"frost", "crystal":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(4, -1), c + Vector2(0, 8), c + Vector2(-4, -1)]), Palette.ACCENT_BLUE)
			ci.draw_line(c + Vector2(0, -9), c + Vector2(0, 8), Color(1, 1, 1, 0.4), 1.0)
			ci.draw_line(c + Vector2(-4, -1), c + Vector2(4, -1), Palette.ACCENT_BLUE.darkened(0.3), 1.0)
		"spark", "sorts":
			for i in 6:
				var d := Vector2.RIGHT.rotated(i * TAU / 6.0)
				ci.draw_line(c + d * 3.0, c + d * 8.0, Palette.ACCENT_BLUE, 2.0)
			ci.draw_circle(c, 2.5, Palette.ACCENT_BLUE.lightened(0.3))
		"gear":
			ci.draw_arc(c, 6.0, 0, TAU, 24, col, 2.4)
			for i in 8:
				var d := Vector2.RIGHT.rotated(i * TAU / 8.0)
				ci.draw_line(c + d * 5.4, c + d * 9.0, col, 2.2)
			ci.draw_circle(c, 2.4, Color(0, 0, 0, 0.40))
		"pause":
			ci.draw_rect(Rect2(c + Vector2(-5.0, -6), Vector2(3.4, 12)), col)
			ci.draw_rect(Rect2(c + Vector2(1.6, -6), Vector2(3.4, 12)), col)
		"upgrade":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-6, 1), c + Vector2(0, -6), c + Vector2(6, 1)]), col, 2.6)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-6, 7), c + Vector2(0, 0), c + Vector2(6, 7)]), col, 2.6)
		"trash":
			ci.draw_line(c + Vector2(-7, -4), c + Vector2(7, -4), col, 2.0)
			ci.draw_rect(Rect2(c + Vector2(-2.6, -6.6), Vector2(5.2, 2.4)), col)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-5.4, -4), c + Vector2(-4.4, 8), c + Vector2(4.4, 8), c + Vector2(5.4, -4)]), col, 2.0)
			for x: float in [-2.4, 0.0, 2.4]:
				ci.draw_line(c + Vector2(x, -1), c + Vector2(x, 5.5), col, 1.2)
		"chevron":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-2, -6), c + Vector2(4, 0), c + Vector2(-2, 6)]), col, 2.4)
		"helmet", "troops":
			ci.draw_arc(c + Vector2(0, 1), 6.0, PI, TAU, 14, col, 3.0)
			ci.draw_line(c + Vector2(-7, 1), c + Vector2(7, 1), col, 2.0)
			ci.draw_line(c + Vector2(0, -5), c + Vector2(0, -8), Palette.ACCENT_RED, 2.0)
		"portal":
			ci.draw_line(c + Vector2(0, -6), c + Vector2(0, 6), Palette.ACCENT_GREEN_LIT, 3.0)
			ci.draw_arc(c, 6.0, PI * 1.35, PI * 1.65, 6, Palette.ACCENT_GREEN, 2.0)
		_:
			ci.draw_circle(c, 4.0, col)
