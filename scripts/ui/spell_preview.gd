class_name SpellPreview
extends RefCounted
## What a spell would act on if cast now, worked out without casting it, so
## the world can highlight it while the spell is being typed. Nouns that are
## only known once cast (Chosen, This, There, It, relations) show nothing.
## Random shows every candidate. Reads the simulation; never changes it.


## {"what": objects the verb would act on (or Create at), "to": Move's
## destination}.
static func targets(sim: Simulation, caster: WorldObject, ast: Dictionary, aim: Vector2) -> Dictionary:
	var dir := caster.pos.direction_to(aim)
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var limit := SpellGrammar.up_to(ast)
	var out := {"what": [], "to": []}
	match ast.get("verb", ""):
		"destroy", "mark", "move":
			out["what"] = _capped(_noun(sim, caster, ast["what"], dir), caster, limit)
			if ast["verb"] == "move":
				out["to"] = _noun(sim, caster, ast["to"], dir).slice(0, 1)
		"select":
			out["what"] = _capped(_noun(sim, caster, SpellGrammar.held_noun(ast), dir), caster, limit)
		"create":
			if ast.get("at") is Dictionary:
				out["what"] = _noun(sim, caster, ast["at"], dir).slice(0, 1)
	return out


static func _noun(sim: Simulation, caster: WorldObject, noun: Dictionary, dir: Vector2) -> Array:
	if noun.has("ref"):
		match noun["ref"]:
			"me", "here":
				return [caster]
			"aimed":
				var o := sim.aimed(caster.pos, dir, [caster])
				return [o] if o != null else []
		return []
	var picker := SpellGrammar.picker_of(noun)
	if picker == "":
		return []
	var from := caster.pos
	if noun.get("from") is Dictionary:
		var origin := _noun(sim, caster, noun["from"], dir)
		if origin.is_empty():
			return []
		from = origin[0].pos
	var within: float = noun.get("within", 0) * SpellGrammar.PIXELS_PER_METER
	# Random would draw from the simulation's dice: show every candidate.
	return sim.pick("all" if picker == "random" else picker, noun[picker], noun.get("adj", []), from,
			within, caster, [caster], [])


static func _capped(objs: Array, caster: WorldObject, limit: int) -> Array:
	if limit == 0 or objs.size() <= limit:
		return objs
	var sorted := objs.duplicate()
	sorted.sort_custom(func(a: WorldObject, b: WorldObject) -> bool:
		return caster.pos.distance_squared_to(a.pos) < caster.pos.distance_squared_to(b.pos))
	return sorted.slice(0, limit)


## A short note on `found` (from targets) for the player: how much the spell
## would act on right now, or that it would wait. "" when it can't be known
## before casting.
static func describe(ast: Dictionary, found: Dictionary) -> String:
	var noun: Variant = null
	match ast.get("verb", ""):
		"destroy", "mark", "move":
			noun = ast["what"]
		"select":
			noun = SpellGrammar.held_noun(ast)
	if not noun is Dictionary or not _knowable(noun):
		return ""
	var n: int = found["what"].size()
	if n == 0:
		return "nothing to act on right now: it would wait"
	if ast["verb"] == "move" and _knowable(ast["to"]) and found["to"].is_empty():
		return "nowhere to move to right now: it would wait"
	return "acts on %d %s now" % [n, "thing" if n == 1 else "things"]


## Whether a noun can be worked out before casting.
static func _knowable(noun: Dictionary) -> bool:
	if noun.has("ref"):
		return noun["ref"] in ["me", "here", "aimed"]
	if SpellGrammar.picker_of(noun) == "":
		return false
	return not noun.get("from") is Dictionary or _knowable(noun["from"])
