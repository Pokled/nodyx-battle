class_name NetBackend
extends Node
## Contrat d'un backend de transport pour l'autoload `Net`.  Un backend ne connait
## RIEN au gameplay : il transporte des messages et expose le roster + l'etat
## "parle" du salon.  `Net` l'ajoute comme enfant et re-emet ses signaux.
##
## Canaux logiques :
##   "cmd"  : fiable, ordonne  (build, envois, ready, transitions de manche, king hp)
##   "snap" : non fiable, latest-wins  (BoardDigest binaire)

signal lobby_changed(players: Array)          ## [{id,name,avatar_url,color,is_local,is_bot,ready}]
signal player_joined(p: Dictionary)
signal player_left(id: String)
signal match_started(seed: int, roster: Array)
signal message(from_id: String, channel: String, payload: Dictionary)
signal snapshot(from_id: String, bytes: PackedByteArray)
signal speaking_changed(id: String, on: bool)
signal disconnected(reason: String)
## L'arbitre (host) a change en cours de session : le siege 0 a quitte le
## salon vocal, un autre membre reprend la barriere de manche.
signal host_changed(is_host: bool)
## Un pair (re)demarre et demande l'etat courant du match (arg = son id).
signal sync_requested(from_id: String)

var local_id := ""
var is_host := false
var room := ""


func open(_opts: Dictionary) -> void:
	pass


func close() -> void:
	pass


func set_ready(_on: bool) -> void:
	pass


func start_match(_opts: Dictionary) -> void:
	pass


## `to` vide = broadcast.
func send(_channel: String, _payload: Dictionary, _reliable := true, _to := "") -> void:
	pass


func broadcast_snapshot(_bytes: PackedByteArray) -> void:
	pass
