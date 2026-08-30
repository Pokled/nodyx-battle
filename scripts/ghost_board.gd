class_name GhostBoard
extends Node2D
## Rendu "fantome" d'un plateau adverse a partir d'un BoardDigest.  Aucune
## simulation : decor d'arene reel + glyphes de tours + points d'unites interpoles.
## Sert dans le carrousel de spectate (miniature) et en plein ecran.

var _arena: Node2D = null
var _digest: Dictionary = {}
var _units: Dictionary = {}          ## id -> {pos, target, type_idx, hp, team, flags}
var _tint := Color(1, 1, 1)
var label := ""


func _ready() -> void:
	_arena = preload("res://scenes/arena.tscn").instantiate()
	_arena.z_index = -2
	_arena.set_process_input(false)
	add_child(_arena)


func board_size() -> Vector2:
	return _arena.board_size() if _arena != null else Vector2(832, 832)


func set_tint(c: Color) -> void:
	_tint = c


func apply_digest(d: Dictionary) -> void:
	_digest = d
	var seen := {}
	for u in d.get("un", []):
		var id := int(u[0])
		seen[id] = true
		var tgt := Vector2(float(u[1]), float(u[2]))
		if _units.has(id):
			_units[id]["target"] = tgt
			_units[id]["hp"] = float(u[3]) / 255.0
		else:
			_units[id] = {"pos": tgt, "target": tgt, "type_idx": int(u[4]),
				"hp": float(u[3]) / 255.0, "team": int(u[5]), "flags": int(u[6])}
	for id in _units.keys():
		if not seen.has(id):
			_units.erase(id)
	queue_redraw()


func _process(delta: float) -> void:
	var k := clampf(delta * 10.0, 0.0, 1.0)
	for id in _units:
		_units[id]["pos"] = _units[id]["pos"].lerp(_units[id]["target"], k)
	queue_redraw()


func _draw() -> void:
	if _digest.is_empty():
		return
	# tours
	for t in _digest.get("tw", []):
		var cell := Vector2i(int(t[0]), int(t[1]))
		var wp: Vector2 = _arena.cell_to_world(cell)
		var col: Color = Catalog.color(BoardDigest.type_name(int(t[2])))
		var lvl := int(t[3])
		draw_rect(Rect2(wp - Vector2(13, 13), Vector2(26, 26)), Color(0.10, 0.09, 0.08, 0.9))
		draw_rect(Rect2(wp - Vector2(13, 13), Vector2(26, 26)), col.darkened(0.2), false, 2.0)
		draw_circle(wp, 6.0 + lvl, col)
	# unites
	for id in _units:
		var u: Dictionary = _units[id]
		var tn := BoardDigest.type_name(int(u["type_idx"]))
		var col: Color = Enemy.TYPE_COLOR.get(tn, Color(0.8, 0.3, 0.25)) if int(u["team"]) == 1 \
			else Color(0.40, 0.80, 0.45)
		if int(u["flags"]) & 2:
			col = col.lerp(Color(1.0, 0.5, 0.3), 0.5)
		var r := 5.0 + (4.0 if int(u["flags"]) & 1 else 0.0)
		draw_circle(u["pos"], r + 1.5, Color(0, 0, 0, 0.35))
		draw_circle(u["pos"], r, col)
		if float(u["hp"]) < 1.0:
			draw_rect(Rect2(u["pos"] + Vector2(-r, -r - 4), Vector2(r * 2.0 * float(u["hp"]), 2.0)),
				Color(0.9, 0.85, 0.4))
