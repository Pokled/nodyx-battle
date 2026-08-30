extends Node
## Avatars Nodyx des joueurs, decodes en texture.
##
## L'hote (ActivitySurface) resout chaque avatar Nodyx en PNG 64x64 base64 et le
## pose dans le roster (`avatar_png`). Ici on decode, on met en cache par id, et
## on previent le HUD quand une nouvelle image arrive (elle peut arriver apres le
## debut de partie, en member_update).

signal changed(id: String)
signal local_ready()   ## le profil Nodyx du joueur local est disponible

var _tex: Dictionary = {}   ## id -> ImageTexture
var _seen: Dictionary = {}  ## id -> hash du base64 deja decode (evite de refaire)

## Profil Nodyx du joueur local, disponible meme hors partie (solo, contre l'IA).
var local_id := ""
var local_name := ""
var local_tex: ImageTexture = null


func _ready() -> void:
	Net.lobby_changed.connect(_ingest)
	Net.match_started.connect(func(_s, _r): _ingest(Net.roster))
	_ingest(Net.players)
	if OS.has_feature("web"):
		var w = JavaScriptBridge.get_interface("window")
		if w != null and w.NodyxBattle:
			_poll_local(0)


## L'hote resout l'avatar apres coup : on rescrute meJson() quelques secondes.
func _poll_local(tries: int) -> void:
	var raw := String(JavaScriptBridge.eval("window.NodyxBattle && window.NodyxBattle.meJson ? window.NodyxBattle.meJson() : ''", true))
	var learned := false
	if raw != "":
		var v = JSON.parse_string(raw)
		if v is Dictionary:
			if local_id == "" and String(v.get("id", "")) != "":
				local_id = String(v.get("id", "")); learned = true
			if local_name == "" and String(v.get("name", "")) != "":
				local_name = String(v.get("name", "")); learned = true
			var b64 := String(v.get("avatar_png", ""))
			if b64 != "" and local_tex == null:
				local_tex = _decode(b64)
				learned = learned or local_tex != null
	if learned:
		local_ready.emit()
	if local_tex == null and tries < 20:
		await get_tree().create_timer(0.4).timeout
		_poll_local(tries + 1)


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
