class_name BoardDigest
extends RefCounted
## Photo compacte d'un plateau, diffusee ~6 Hz pendant le combat.  Les autres
## clients l'affichent via `GhostBoard`.  Forme :
##   {k,km,o,f,w,ph,
##    tw:[[cx,cy,type_idx,lvl], ...],
##    un:[[id,x,y,hp255,type_idx,team,flags], ...]}
##   flags bit0 = champion, bit1 = from_send

const TYPES := [
	"canon", "gatling", "mortier", "givre", "guerriere", "archere",
	"grognard", "rodeur", "colosse", "soigneur", "spectre", "sorcier",
]


static func type_idx(name: String) -> int:
	var i := TYPES.find(name)
	return i if i >= 0 else 0


static func type_name(idx: int) -> String:
	return TYPES[idx] if idx >= 0 and idx < TYPES.size() else "grognard"


## Capture le plateau reel (arene + GameState).
static func capture(arena: Node2D, gs: Node) -> Dictionary:
	var tw: Array = []
	for cell in arena.occupied:
		var o = arena.occupied[cell]
		if not is_instance_valid(o):
			continue
		if o is Tower:
			tw.append([int(cell.x), int(cell.y), type_idx(o.type_id), int(o.level)])
		elif o is Fighter:
			tw.append([int(cell.x), int(cell.y), type_idx(o.type_id), 1])

	var un: Array = []
	for grp in ["enemies", "blockers"]:
		for u in arena.get_tree().get_nodes_in_group(grp):
			if not is_instance_valid(u) or not (u is Unit) or u.hp <= 0.0:
				continue
			var flags := 0
			if u is Enemy:
				if u.is_champion:
					flags |= 1
				if u.from_send:
					flags |= 2
			un.append([
				int(u.get_instance_id() & 0x7FFFFFFF),
				int(u.position.x), int(u.position.y),
				int(clampf(u.hp / maxf(1.0, u.max_hp), 0.0, 1.0) * 255.0),
				type_idx(u.type_id if "type_id" in u else "grognard"),
				int(u.team), flags,
			])

	return {
		"k": int(gs.king_hp), "km": int(gs.king_max),
		"o": int(gs.minerai), "f": int(gs.nourriture),
		"w": int(gs.wave), "ph": int(gs.phase),
		"tw": tw, "un": un,
	}


static func to_bytes(d: Dictionary) -> PackedByteArray:
	return var_to_bytes(d)


static func from_bytes(b: PackedByteArray) -> Dictionary:
	var v = bytes_to_var(b)
	return v if v is Dictionary else {}
