class_name AnimStrip
extends Sprite2D
## Joue une bande horizontale de N frames (hframes). Boucle ou one-shot.

signal finished

var fps := 12.0
var loop := true

var _n := 1
var _acc := 0.0
var _playing := false


func set_strip(tex: Texture2D, n: int) -> void:
	texture = tex
	vframes = 1
	hframes = maxi(1, n)
	_n = maxi(1, n)
	frame = 0


func play() -> void:
	frame = 0
	_acc = 0.0
	_playing = true


func _process(delta: float) -> void:
	if not _playing or _n <= 1:
		return
	_acc += delta * fps
	while _acc >= 1.0:
		_acc -= 1.0
		if frame + 1 >= _n:
			if loop:
				frame = 0
			else:
				_playing = false
				finished.emit()
				return
		else:
			frame += 1
