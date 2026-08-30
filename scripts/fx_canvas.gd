class_name FxCanvas
extends Node2D
## Rend les "pops" (anneaux, eclats) geres par l'autoload Fx. Un seul noeud pour tout.

func _process(delta: float) -> void:
	Fx.tick(delta)
	queue_redraw()


func _draw() -> void:
	Fx.render(self)
