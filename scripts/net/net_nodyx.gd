class_name NetNodyx
extends NetBackend
## Backend `nodyx` : le jeu tourne comme ACTIVITE dans un salon vocal Nodyx.  Les
## membres du salon SONT le roster ; la voix reste 100 % Nodyx ; l'hote de la page
## relaie nos messages/snapshots dans la room `voice:<channelId>` via le socket
## deja authentifie de l'utilisateur (l'activite n'a ni socket ni token propre).
##
## Contrat cote page (implemente par `widget/nodyx-battle/nodyx-activity.js`,
## charge dans le <head> de l'export web AVANT index.js) :
##   window.NodyxBattle = {
##     me()            -> {id, name, avatar}
##     isHost()        -> bool
##     onLobby(fn)     fn([{id,name,avatar_url,color,is_bot,ready}])
##     onSpeaking(fn)  fn(id, bool)
##     onMessage(fn)   fn(fromId, channel, payloadJson)
##     onSnapshot(fn)  fn(fromId, base64)
##     onMatchStart(fn) fn(seed, rosterJson)
##     ready(bool)     setReady
##     start(seed)     host lance
##     send(channel, payloadJson, reliable, toId)
##     sendSnapshot(base64)
##   }
##
## ECRIT MAIS INERTE tant qu'aucune instance Nodyx n'est branchee : si
## `window.NodyxBattle` est absent, `open()` emet `disconnected` et l'appelant
## retombe sur `local`.

var _js: JavaScriptObject = null
var _cbs: Array = []   ## garde les callbacks vivants


func open(_opts: Dictionary) -> void:
	if not OS.has_feature("web"):
		disconnected.emit("backend nodyx : export web requis")
		return
	var win := JavaScriptBridge.get_interface("window")
	if win == null or not win.NodyxBattle:
		disconnected.emit("pont Nodyx absent (window.NodyxBattle)")
		return
	_js = win.NodyxBattle
	var me = _js.me()
	local_id = String(me.id) if me else ""
	is_host = bool(_js.isHost())
	_bind("onLobby", _on_lobby)
	_bind("onSpeaking", _on_speaking)
	_bind("onMessage", _on_message)
	_bind("onSnapshot", _on_snapshot)
	_bind("onMatchStart", _on_match_start)


func _bind(hook: String, fn: Callable) -> void:
	var cb := JavaScriptBridge.create_callback(fn)
	_cbs.append(cb)
	_js.call(hook, cb)


func close() -> void:
	_js = null
	_cbs.clear()


func set_ready(on: bool) -> void:
	if _js: _js.ready(on)


func start_match(opts: Dictionary) -> void:
	if _js: _js.start(int(opts.get("seed", randi())))


func send(channel: String, payload: Dictionary, reliable := true, to := "") -> void:
	if _js: _js.send(channel, JSON.stringify(payload), reliable, to)


func broadcast_snapshot(bytes: PackedByteArray) -> void:
	if _js: _js.sendSnapshot(Marshalls.raw_to_base64(bytes))


# --- callbacks JS -> Godot ----------------------------------------

func _on_lobby(args: Array) -> void:
	var v = JSON.parse_string(String(args[0])) if args.size() > 0 else []
	# Le host (siege 0) peut changer si quelqu'un quitte le salon : on le
	# reevalue a chaque mise a jour du roster.
	if _js: is_host = bool(_js.isHost())
	lobby_changed.emit(v if v is Array else [])


func _on_speaking(args: Array) -> void:
	if args.size() >= 2:
		speaking_changed.emit(String(args[0]), bool(args[1]))


func _on_message(args: Array) -> void:
	if args.size() >= 3:
		var p = JSON.parse_string(String(args[2]))
		message.emit(String(args[0]), String(args[1]), p if p is Dictionary else {})


func _on_snapshot(args: Array) -> void:
	if args.size() >= 2:
		snapshot.emit(String(args[0]), Marshalls.base64_to_raw(String(args[1])))


func _on_match_start(args: Array) -> void:
	if args.size() >= 2:
		var r = JSON.parse_string(String(args[1]))
		match_started.emit(int(args[0]), r if r is Array else [])
