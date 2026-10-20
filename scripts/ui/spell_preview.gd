class_name SpellPreview
extends RefCounted
## What a spell would act on if cast now, worked out without casting it, so
## the world can highlight it while the spell is being typed. The first This
## or There is where the mouse is, as when cast; other picks (Chosen, a later
## This or There), It and relations are only known once cast. Random shows
## every candidate. Reads the simulation; never changes it.


## {"what": what the verb would act on (or where Create would create), "to":
## Move's destination}: each an Array of objects and places (Vector2), or
## null if it can't be known before casting. `aim` is where the mouse is;
## `mouse_picks` false if it isn't over the world (so no This or There).
static func targets(sim: Simulation, caster: WorldObject, ast: Dictionary, aim: Vector2,
		mouse_picks := true) -> Dictionary:
	var picks := SpellGrammar.cast_picks(ast)
	var first: Dictionary = picks[0] if mouse_picks and not picks.is_empty() else {}
	var ctx := {"sim": sim, "caster": caster, "aim": aim, "first": first}
	var limit := SpellGrammar.up_to(ast)
	var out := {"what": null, "to": null}
	match ast.get("verb", ""):
		"destroy", "mark", "move":
			out["what"] = _capped(_noun(ctx, ast["what"]), caster, limit)
			if ast["verb"] == "move":
				out["to"] = _first(_noun(ctx, ast["to"]))
		"select":
			out["what"] = _capped(_noun(ctx, SpellGrammar.held_noun(ast)), caster, limit)
		"create":
			if ast.get("at") is Dictionary:
				out["what"] = _first(_noun(ctx, ast["at"]))
	return out


static func _noun(ctx: Dictionary, noun: Dictionary) -> Variant:
	var sim: Simulation = ctx["sim"]
	var caster: WorldObject = ctx["caster"]
	if noun.has("ref"):
		var first := is_same(noun, ctx["first"])
		match noun["ref"]:
			"me", "here":
				return [caster]
			"aimed":
				var dir := caster.pos.direction_to(ctx["aim"])
				var o := sim.aimed(caster.pos, dir if dir != Vector2.ZERO else Vector2.RIGHT, [caster])
				return [o] if o != null else []
			"this" when first:
				var o := sim.object_at(ctx["aim"])
				return [o] if o != null else null  # nothing under the mouse: it asks
			"there" when first:
				return [ctx["aim"]]
		return null
	var picker := SpellGrammar.picker_of(noun)
	if picker == "":
		return null
	var from := caster.pos
	if noun.get("from") is Dictionary:
		var origin: Variant = _noun(ctx, noun["from"])
		if origin == null or origin.is_empty():
			return origin
		from = origin[0] if origin[0] is Vector2 else origin[0].pos
	var within: float = noun.get("within", 0) * SpellGrammar.PIXELS_PER_METER
	# Random would draw from the simulation's dice: show every candidate.
	return sim.pick("all" if picker == "random" else picker, noun[picker], noun.get("adj", []), from,
			within, caster, [caster], [])


static func _first(found: Variant) -> Variant:
	return null if found == null else found.slice(0, 1)


static func _capped(found: Variant, caster: WorldObject, limit: int) -> Variant:
	if found == null or limit == 0 or found.size() <= limit:
		return found
	var sorted: Array = found.duplicate()
	sorted.sort_custom(func(a: WorldObject, b: WorldObject) -> bool:
		return caster.pos.distance_squared_to(a.pos) < caster.pos.distance_squared_to(b.pos))
	return sorted.slice(0, limit)


## A short note on `found` (from targets) for the player: how much the spell
## would act on right now, or that it would wait. "" when it can't be known
## before casting.
static func describe(ast: Dictionary, found: Dictionary) -> String:
	if not ast.get("verb", "") in ["destroy", "mark", "move", "select"] or found["what"] == null:
		return ""
	var n: int = found["what"].size()
	if n == 0:
		return "nothing to act on right now: it would wait"
	if ast["verb"] == "move" and found["to"] != null and found["to"].is_empty():
		return "nowhere to move to right now: it would wait"
	var note := "acts on %d %s now" % [n, "thing" if n == 1 else "things"]
	if ast["verb"] == "move":
		var weight := 0.0
		for o in found["what"]:
			weight += o.mass
		note += ", weighing %s: mana ×%s while pushing" % [str(snappedf(weight, 0.1)).trim_suffix(".0"),
				str(snappedf(weight / Spell.MOVE_WEIGHT_UNIT, 0.01))]
	return note
