extends Node
## Avatars Nodyx des joueurs, decodes en texture.
##
## L'hote (ActivitySurface) resout chaque avatar Nodyx en PNG 64x64 base64 et le
## pose dans le roster (`avatar_png`). Ici on decode, on met en cache par id, et
## on previent le HUD quand une nouvelle image arrive (elle peut arriver apres le
## debut de partie, en member_update).

signal changed(id: String)

var _tex: Dictionary = {}   ## id -> ImageTexture
var _seen: Dictionary = {}  ## id -> hash du base64 deja decode (evite de refaire)


func _ready() -> void:
	Net.lobby_changed.connect(_ingest)
	Net.match_started.connect(func(_s, _r): _ingest(Net.roster))
	_ingest(Net.players)


func _ingest(players: Array) -> void:
	for p in players:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var id := String(p.get("id", ""))
		var b64 := String(p.get("avatar_png", ""))
		if id == "" or b64 == "":
			continue
		var h := b64.hash()
		if _seen.get(id, 0) == h:
			continue
		_seen[id] = h
		var tex := _decode(b64)
		if tex != null:
			_tex[id] = tex
			changed.emit(id)


func _decode(b64: String) -> ImageTexture:
	var raw := Marshalls.base64_to_raw(b64)
	if raw.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(raw) != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	_circle_mask(img)
	return ImageTexture.create_from_image(img)


## Rend l'image circulaire (alpha a 0 hors du disque, bord adouci) une fois pour
## toutes, pour que le HUD n'ait qu'a poser la texture.
func _circle_mask(img: Image) -> void:
	var w := mini(img.get_width(), img.get_height())
	var c := w * 0.5
	var rad := c - 1.0
	for y in img.get_height():
		for x in img.get_width():
			var d := Vector2(x + 0.5 - c, y + 0.5 - c).length()
			if d <= rad - 1.5:
				continue
			var col := img.get_pixel(x, y)
			col.a *= 0.0 if d > rad else clampf((rad - d) / 1.5, 0.0, 1.0)
			img.set_pixel(x, y, col)


## Texture de l'avatar, ou null (l'appelant dessine alors une pastille a initiale).
func tex(id: String) -> ImageTexture:
	return _tex.get(id, null)


func has(id: String) -> bool:
	return _tex.has(id)
