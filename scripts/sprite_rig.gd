class_name SpriteRig
extends Node2D
## Gere le sprite anime d'un personnage (idle / walk / attack / die) + orientation + flash.

signal die_finished

const FRAME_H := 150.0   ## hauteur des bandes generees par le pipeline d'assets

var base_facing := 1     ## +1 = l'art regarde a droite, -1 = a gauche

var _sprite: AnimStrip
var _strips: Dictionary = {}
var _state := ""
var _dead := false


func _ready() -> void:
	_sprite = AnimStrip.new()
	_sprite.centered = true
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/flash.gdshader")
	_sprite.material = mat
	add_child(_sprite)


func add_state(state: String, path: String, frames: int, fps: float, loop: bool) -> void:
	var tex := load(path)
	if tex != null:
		_strips[state] = {"tex": tex, "n": frames, "fps": fps, "loop": loop}


func has_art() -> bool:
	return not _strips.is_empty()


func configure(height_px: float, anchor: Vector2, facing: int) -> void:
	base_facing = facing
	_sprite.offset = anchor
	_sprite.scale = Vector2.ONE * (height_px / FRAME_H)


func set_flash(v: float) -> void:
	_sprite.material.set_shader_parameter("flash", v)


func set_tint(c: Color) -> void:
	_sprite.self_modulate = c


func face(dir: float) -> void:
	if absf(dir) > 0.05:
		_sprite.flip_h = signf(dir) != float(base_facing)


func play(state: String) -> void:
	if _dead or state == _state or not _strips.has(state):
		return
	_state = state
	var s: Dictionary = _strips[state]
	_sprite.set_strip(s["tex"], s["n"])
	_sprite.fps = s["fps"]
	_sprite.loop = s["loop"]
	_sprite.play()


func play_die() -> void:
	if _dead:
		return
	_dead = true
	if _strips.has("die"):
		var s: Dictionary = _strips["die"]
		_sprite.set_strip(s["tex"], s["n"])
		_sprite.fps = s["fps"]
		_sprite.loop = false
		_sprite.finished.connect(func(): die_finished.emit(), CONNECT_ONE_SHOT)
		_sprite.play()
	else:
		die_finished.emit.call_deferred()
