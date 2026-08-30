extends Node
## Autoload `Audio`. Effets sonores generes proceduralement + musique de fond.

const SR := 22050
const MUSIC_DB := -13.0
const MIN_INTERVAL := {
	"shoot_canon": 0.05, "shoot_gatling": 0.03, "shoot_mortier": 0.10,
	"shoot_givre": 0.06, "kill": 0.03,
}

var _players: Array[AudioStreamPlayer] = []
var _idx := 0
var _fx: Dictionary = {}
var _last_play: Dictionary = {}

var _music: AudioStreamPlayer
var music_on := false   ## coupee par defaut pour le moment (bouton MUSIQUE / touche M)


func _ready() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

	_fx["place_tower"] = _seq([[520.0, 0.09]], "square", 0.30)
	_fx["place_fighter"] = _seq([[300.0, 0.06], [430.0, 0.09]], "square", 0.30)
	_fx["denied"] = _seq([[130.0, 0.14]], "saw", 0.26)
	_fx["sell"] = _seq([[620.0, 0.05], [430.0, 0.05], [860.0, 0.10]], "sine", 0.30)
	_fx["upgrade"] = _seq([[380.0, 0.06], [520.0, 0.06], [700.0, 0.07], [920.0, 0.12]], "square", 0.28)
	_fx["boon"] = _seq([[520.0, 0.06], [660.0, 0.06], [880.0, 0.14]], "sine", 0.34)
	_fx["wave_start"] = _seq([[240.0, 0.10], [360.0, 0.10], [300.0, 0.10], [480.0, 0.18]], "square", 0.30)
	_fx["wave_clear"] = _seq([[520.0, 0.09], [700.0, 0.09], [900.0, 0.16]], "sine", 0.34)
	_fx["kill"] = _seq([[200.0, 0.04], [90.0, 0.06]], "noise", 0.22)
	_fx["leak"] = _seq([[110.0, 0.05], [70.0, 0.30]], "saw", 0.42)
	_fx["champion"] = _seq([[80.0, 0.30], [55.0, 0.35], [70.0, 0.25]], "saw", 0.5)
	_fx["freeze"] = _seq([[1200.0, 0.05], [1500.0, 0.05], [900.0, 0.10]], "sine", 0.22)
	_fx["game_over"] = _seq([[400.0, 0.22], [300.0, 0.24], [200.0, 0.4]], "saw", 0.4)
	_fx["victory"] = _seq([[392.0, 0.14], [523.0, 0.14], [659.0, 0.16], [784.0, 0.32]], "sine", 0.4)

	_fx["shoot_canon"] = _seq([[420.0, 0.05], [260.0, 0.04]], "square", 0.16)
	_fx["shoot_gatling"] = _seq([[820.0, 0.03]], "square", 0.09)
	_fx["shoot_mortier"] = _seq([[150.0, 0.05], [90.0, 0.12]], "saw", 0.24)
	_fx["shoot_givre"] = _seq([[1000.0, 0.04], [1300.0, 0.06]], "sine", 0.12)
	_fx["shoot"] = _fx["shoot_canon"]

	_music = AudioStreamPlayer.new()
	_music.volume_db = -60.0
	add_child(_music)
	var m = load("res://sound/Nodyx_battle_ambiance.mp3")
	if m != null:
		if m is AudioStreamMP3:
			m.loop = true
		_music.stream = m
		_music.play()   # joue mais muet ; toggle_music() la remonte


func toggle_music() -> void:
	music_on = not music_on
	if not is_instance_valid(_music):
		return
	var tw := create_tween()
	tw.tween_property(_music, "volume_db", MUSIC_DB if music_on else -60.0, 0.4)


func play(fx_name: String) -> void:
	if not _fx.has(fx_name) or not is_inside_tree() or _players.is_empty():
		return
	if MIN_INTERVAL.has(fx_name):
		var now := Time.get_ticks_msec() / 1000.0
		if now - float(_last_play.get(fx_name, -1.0)) < float(MIN_INTERVAL[fx_name]):
			return
		_last_play[fx_name] = now
	var p := _players[_idx]
	_idx = (_idx + 1) % _players.size()
	if not p.is_inside_tree():
		return
	p.stream = _fx[fx_name]
	p.pitch_scale = randf_range(0.94, 1.06)
	p.play()


func _wave_sample(kind: String, phase: float) -> float:
	match kind:
		"sine": return sin(phase * TAU)
		"square": return 1.0 if fposmod(phase, 1.0) < 0.5 else -1.0
		"saw": return fposmod(phase, 1.0) * 2.0 - 1.0
		"noise": return randf() * 2.0 - 1.0
	return 0.0


func _seq(notes: Array, kind: String, vol: float) -> AudioStreamWAV:
	var total := 0.0
	for n in notes:
		total += float(n[1])
	var count := maxi(1, int(SR * total))
	var data := PackedByteArray()
	data.resize(count * 2)

	var i := 0
	for n in notes:
		var freq := float(n[0])
		var dur := float(n[1])
		var seg := int(SR * dur)
		for j in seg:
			if i >= count:
				break
			var t := float(j) / SR
			var env := clampf(t / 0.006, 0.0, 1.0) * clampf(1.0 - t / dur, 0.0, 1.0)
			var s := _wave_sample(kind, freq * t)
			data.encode_s16(i * 2, int(clampf(s * env * vol, -1.0, 1.0) * 32767.0))
			i += 1

	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = data
	return w
