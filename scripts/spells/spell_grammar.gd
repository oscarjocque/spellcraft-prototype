class_name SpellGrammar
extends RefCounted
## Spells as data. A spell is a sentence: a verb with its noun slots, or an
## incomplete one, a noun on its own, which the caster then holds.
##
##   {"verb": "create", "what": {"material": "wood"}, "at": NOUN?}
##   {"verb": "create", "what": {"spell": SPELL}, "at": NOUN?}   # creates spells
##   {"verb": "destroy", "what": NOUN}
##   {"verb": "move", "what": NOUN, "to": NOUN}
##   {"verb": "mark", "what": NOUN}
##   {"verb": "select", "what": NOUN}   # Hold: a noun on its own, re-read every tick
##   {"verb": "alternate", "first": ARG, "second": ARG}
##     ARG is {"slot": N}, one of the caster's spell slots (0-based), which is
##     copied in as "spell" when casting (see embed_slots); or {"ref":
##     "chosen"}, an attached spell, picked when casting, that it takes over.
##
## Any spell may also have adverbs: {"adverbs": {ADVERB: VALUE}}. So far:
##   "up_to": N   at most N: created, spells created, destroyed, moved,
##                marked, held, or turns of an Alternate
##
## NOUN is one of:
##   {"ref": REF}                 Me, Here, It, Chosen, This, There, Aimed
##   {PICKER: QUALIFIER, "adj": [ADJECTIVE...]?, "within": METERS?, "from": NOUN?}
##                                e.g. (Closest Moving Stone within 3 m of There)
##   {RELATION: NOUN}             (Target of X), (Caster of X), ...
##
## Here is the spell's own location (the caster's, for a spell they cast).
## It is what the other spell of an Alternate acted on in its last turn (and
## nothing outside an Alternate). Chosen, This and There are picked by the caster for each use when casting,
## and the pick is stored in the noun: "id" for Chosen and This, "at" for There.
## A picker inside a spell chooses once, when the spell is cast; a held one
## keeps choosing. Relations are re-read every tick, so (Target of Chosen),
## with a held noun chosen, follows whatever it holds now.
## Every word costs mana of one color. A created spell pays its own drain:
## the spell creating it must carry that mana as a reserve (see `payload`).

const VERBS := ["create", "destroy", "move", "mark", "select", "alternate"]
const MATERIALS := ["fire", "water", "wood", "stone"]
const QUALIFIERS := ["thing", "fire", "water", "wood", "stone", "spell", "player", "mana"]
const REFS := ["me", "here", "it", "chosen", "this", "there", "aimed"]
## Refs the caster picks when casting.
const PICKED_REFS := ["chosen", "this", "there"]
const PICKERS := ["closest", "farthest", "random", "all"]
const ADJECTIVES := ["moving", "burning", "mine", "theirs", "marked"]
const RELATIONS := ["target_of", "caster_of", "maker_of", "products_of"]
const DISTANCES := [1, 2, 3, 5]  # meters, for "within"
const PIXELS_PER_METER := 40.0
const COLORS := ["red", "blue", "green", "violet"]
const CREATED_SPELL_SECONDS := 60.0  # how long a created spell's mana must last
const CREATED_SPELLS := 3  # how many spells one Create Spell makes, unless "up to"
const ADVERBS := ["up_to"]
const UP_TO := [1, 2, 3, 4, 5, 10]

## First sketch from the design doc, to be tuned.
const BLOCK_COLOR := {
	"create": "red", "fire": "red", "burning": "red", "at": "red",
	"water": "blue", "mana": "blue", "up_to": "blue",
	"move": "green", "stone": "green", "wood": "green", "moving": "green",
	"there": "green", "here": "green", "aimed": "green", "within": "green", "from": "green",
	"destroy": "violet", "mark": "violet", "alternate": "violet", "it": "violet", "spell": "violet", "player": "violet", "thing": "violet",
	"closest": "violet", "farthest": "violet", "random": "violet", "all": "violet",
	"me": "violet", "chosen": "violet", "this": "violet",
	"mine": "violet", "theirs": "violet", "marked": "violet",
	"target_of": "violet", "caster_of": "violet", "maker_of": "violet", "products_of": "violet",
}

## Mana per second each block drains while its spell is active.
const DRAIN_PER_BLOCK := 0.2


## The noun a held spell holds. (Older spells wrote {"qualifier": Q}.)
static func held_noun(ast: Dictionary) -> Dictionary:
	if ast.get("what") is Dictionary:
		return ast["what"]
	return {"closest": ast.get("qualifier", "")}


## A spell's "up to" limit, or 0 for none.
static func up_to(ast: Dictionary) -> int:
	return ast.get("adverbs", {}).get("up_to", 0)


## How many spells a Create Spell makes.
static func spells_created(ast: Dictionary) -> int:
	return up_to(ast) if up_to(ast) > 0 else CREATED_SPELLS


## The picker word of a selector noun, or "" if the noun isn't a selector.
static func picker_of(noun: Dictionary) -> String:
	for p in PICKERS:
		if noun.has(p):
			return p
	return ""


## The relation word of a relation noun, or "".
static func relation_of(noun: Dictionary) -> String:
	for r in RELATIONS:
		if noun.has(r):
			return r
	return ""


## Every word of the spell, including the words of any spell it creates.
static func blocks(ast: Dictionary) -> Array[String]:
	if ast.get("verb", "") == "alternate":
		var all: Array[String] = ["alternate"]
		for arg in [ast["first"], ast["second"]]:
			var sub := arg_spell(arg)
			if not sub.is_empty():
				all.append_array(blocks(sub))
			elif arg.has("ref"):
				all.append(arg["ref"])
		for adverb in ast.get("adverbs", {}):
			all.append(adverb)
		return all
	var out := own_blocks(ast)
	var inner := created_spell(ast)
	if not inner.is_empty():
		out.append_array(blocks(inner))
	return out


## The spells an Alternate runs from its slots (not the attached spells it
## takes over), or [].
static func inner_spells(ast: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if ast.get("verb", "") == "alternate":
		for arg in [ast["first"], ast["second"]]:
			var sub := arg_spell(arg)
			if not sub.is_empty():
				out.append(sub)
	return out


## The spell an Alternate's argument runs, once its slot is copied in; {} if
## none (an attached spell, or a slot not yet copied in).
static func arg_spell(arg: Dictionary) -> Dictionary:
	if arg.get("spell") is Dictionary:
		return arg["spell"]
	return {}


## A copy of `ast` with the spells of every Alternate slot it uses copied in
## from `slots`. A slot that leads back to a slot already being copied (in
## `visiting`) is left out, so validate rejects it.
static func embed_slots(ast: Dictionary, slots: Array, visiting: Array = []) -> Dictionary:
	var copy := ast.duplicate(true)
	_embed(copy, slots, visiting)
	return copy


static func _embed(ast: Dictionary, slots: Array, visiting: Array) -> void:
	if ast.get("verb", "") == "alternate":
		for key in ["first", "second"]:
			var arg: Dictionary = ast[key]
			if arg.has("slot"):
				arg.erase("spell")
				var n: int = arg["slot"]
				if n >= 0 and n < slots.size() and not n in visiting:
					arg["spell"] = slots[n].duplicate(true)
					_embed(arg["spell"], slots, visiting + [n])
	var inner := created_spell(ast)
	if not inner.is_empty():
		_embed(inner, slots, visiting)


## The words this spell pays for itself, without the spell it creates.
static func own_blocks(ast: Dictionary) -> Array[String]:
	var out: Array[String] = []
	match ast.get("verb", ""):
		"create":
			out.append("create")
			out.append("spell" if ast["what"].has("spell") else ast["what"]["material"])
			if ast.get("at") is Dictionary:
				out.append("at")
				_noun_blocks(ast["at"], out)
		"destroy", "mark":
			out.append(ast["verb"])
			_noun_blocks(ast["what"], out)
		"move":
			out.append("move")
			_noun_blocks(ast["what"], out)
			_noun_blocks(ast["to"], out)
		"select":
			_noun_blocks(held_noun(ast), out)
		"alternate":
			# It runs both spells, so it pays for both.
			out.append("alternate")
			for arg in [ast["first"], ast["second"]]:
				var sub := arg_spell(arg)
				if not sub.is_empty():
					out.append_array(own_blocks(sub))
				elif arg.has("ref"):
					out.append(arg["ref"])
	for adverb in ast.get("adverbs", {}):
		out.append(adverb)
	return out


static func _noun_blocks(noun: Dictionary, out: Array[String]) -> void:
	if noun.has("ref"):
		out.append(noun["ref"])
		return
	var rel := relation_of(noun)
	if rel != "":
		out.append(rel)
		_noun_blocks(noun[rel], out)
		return
	var picker := picker_of(noun)
	out.append(picker)
	for a in noun.get("adj", []):
		out.append(a)
	out.append(noun[picker])
	if noun.has("within"):
		out.append("within")
	if noun.get("from") is Dictionary:
		out.append("from")
		_noun_blocks(noun["from"], out)


## The spell this one creates, or {} if it creates none.
static func created_spell(ast: Dictionary) -> Dictionary:
	if ast.get("verb", "") == "create" and ast["what"] is Dictionary and ast["what"].get("spell") is Dictionary:
		return ast["what"]["spell"]
	return {}


## Mana per second this spell's own blocks drain while it is active (acting on
## one target; acting on several costs this much per target).
static func drain_per_second(ast: Dictionary) -> Dictionary:
	var drain := {}
	for b in own_blocks(ast):
		var c: String = BLOCK_COLOR[b]
		drain[c] = drain.get(c, 0.0) + DRAIN_PER_BLOCK
	return drain


## Mana a spell must carry in reserve for the spells it creates: one `share`
## for each spell it makes.
static func payload(ast: Dictionary) -> Dictionary:
	var need := {}
	# An Alternate carries one turn's worth for each of its spells.
	for sub in inner_spells(ast):
		var p := payload(sub)
		for c in p:
			need[c] = need.get(c, 0.0) + p[c]
	var inner := created_spell(ast)
	if inner.is_empty():
		return need
	var one := share(inner)
	for c in one:
		need[c] = need.get(c, 0.0) + one[c] * spells_created(ast)
	return need


## What one created spell is given: enough to run it for
## CREATED_SPELL_SECONDS, plus what it must carry for its own created spells.
static func share(inner: Dictionary) -> Dictionary:
	var need := payload(inner)
	var drain := drain_per_second(inner)
	for c in drain:
		need[c] = need.get(c, 0.0) + drain[c] * CREATED_SPELL_SECONDS
	return need


## Returns "" if the spell is grammatical, else why not.
static func validate(ast: Dictionary) -> String:
	var adverbs: Variant = ast.get("adverbs", {})
	if not adverbs is Dictionary or not adverbs.keys().all(func(a: Variant) -> bool: return a in ADVERBS):
		return "Unknown adverb."
	if adverbs.has("up_to") and not adverbs["up_to"] in UP_TO:
		return "Up to needs a number."
	var verb: String = ast.get("verb", "")
	match verb:
		"create":
			var what: Variant = ast.get("what")
			if not what is Dictionary:
				return "Create needs a material or a spell."
			if ast.has("at") and not _valid_noun(ast["at"]):
				return "Create at needs somewhere to create."
			if what.has("spell"):
				if not what["spell"] is Dictionary:
					return "Create Spell needs a description of the spell."
				return validate(what["spell"])
			if not what.get("material", "") in MATERIALS:
				return "Create needs a material or a spell."
		"destroy", "mark":
			if not _valid_noun(ast.get("what")):
				return "%s needs something to act on." % verb.capitalize()
		"move":
			if not (_valid_noun(ast.get("what")) and _valid_noun(ast.get("to"))):
				return "Move needs something to move and somewhere to move it."
		"select":
			if not _valid_noun(held_noun(ast)):
				return "Hold needs something to hold."
		"alternate":
			for key in ["first", "second"]:
				var arg: Variant = ast.get(key)
				if not arg is Dictionary:
					return "Alternate needs two spells."
				if arg.get("ref", "") == "chosen":
					continue
				if not arg.has("slot") or not arg["slot"] is int or arg["slot"] < 0 or arg["slot"] > 9:
					return "Alternate takes a spell slot or an attached spell."
				if not arg.get("spell") is Dictionary:
					return "Alternate's spell %d is empty or leads back to itself." % ((arg["slot"] + 1) % 10)
				var err := validate(arg["spell"])
				if err != "":
					return err
		_:
			return "Unknown verb: %s" % verb
	return ""


static func _valid_noun(noun: Variant) -> bool:
	if not noun is Dictionary:
		return false
	if noun.has("ref"):
		return noun["ref"] in REFS
	var rel := relation_of(noun)
	if rel != "":
		return _valid_noun(noun[rel])
	var picker := picker_of(noun)
	if picker == "" or not noun[picker] in QUALIFIERS:
		return false
	if not noun.get("adj", []).all(func(a: Variant) -> bool: return a in ADJECTIVES):
		return false
	if noun.has("within") and not noun["within"] in DISTANCES:
		return false
	return not noun.has("from") or _valid_noun(noun["from"])


## Every noun the caster picks when casting (Chosen, This, There), including
## those in the spells it creates, in reading order: the order they're asked.
static func cast_picks(ast: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match ast.get("verb", ""):
		"create":
			if ast.get("at") is Dictionary:
				_picks_in(ast["at"], out)
		"select":
			_picks_in(held_noun(ast), out)
		"alternate":
			for arg in [ast["first"], ast["second"]]:
				if arg.get("ref", "") == "chosen":
					out.append(arg)
				elif not arg_spell(arg).is_empty():
					out.append_array(cast_picks(arg_spell(arg)))
		_:
			for key in ["what", "to"]:
				if ast.get(key) is Dictionary:
					_picks_in(ast[key], out)
	var inner := created_spell(ast)
	if not inner.is_empty():
		out.append_array(cast_picks(inner))
	return out


static func _picks_in(noun: Dictionary, out: Array[Dictionary]) -> void:
	if noun.get("ref", "") in PICKED_REFS:
		out.append(noun)
	var rel := relation_of(noun)
	if rel != "":
		_picks_in(noun[rel], out)
	elif noun.get("from") is Dictionary:
		_picks_in(noun["from"], out)


static func to_text(ast: Dictionary) -> String:
	return _sentence(ast) + "."


static func _sentence(ast: Dictionary) -> String:
	var text := _clause(ast)
	if up_to(ast) > 0:
		text += ", up to %d" % up_to(ast)
	return text


static func _clause(ast: Dictionary) -> String:
	match ast.get("verb", ""):
		"create":
			var inner := created_spell(ast)
			var text := "Create Spell [%s]" % _sentence(inner) if not inner.is_empty() \
					else "Create %s" % ast["what"]["material"].capitalize()
			if ast.get("at") is Dictionary:
				text += " at %s" % noun_text(ast["at"])
			return text
		"destroy", "mark":
			return "%s %s" % [ast["verb"].capitalize(), noun_text(ast["what"])]
		"move":
			return "Move %s to %s" % [noun_text(ast["what"]), noun_text(ast["to"])]
		"select":
			return "Hold %s" % noun_text(held_noun(ast))
		"alternate":
			return "Alternate %s %s" % [_arg_text(ast["first"]), _arg_text(ast["second"])]
	return "?"


static func noun_text(noun: Dictionary) -> String:
	if noun.has("ref"):
		return noun["ref"].capitalize()
	var rel := relation_of(noun)
	if rel != "":
		return "(%s %s)" % [rel.capitalize().replace(" Of", " of"), noun_text(noun[rel])]
	var picker := picker_of(noun)
	var words: Array[String] = [picker.capitalize()]
	for a in noun.get("adj", []):
		words.append(a.capitalize())
	words.append(noun[picker].capitalize())
	if noun.has("within"):
		words.append("within %d m" % noun["within"])
		if noun.get("from") is Dictionary:
			words.append("of " + noun_text(noun["from"]))
	elif noun.get("from") is Dictionary:
		words.append("to " + noun_text(noun["from"]))
	return "(%s)" % " ".join(words)


## An Alternate's argument: the spell copied in, else its slot, else Chosen.
static func _arg_text(arg: Dictionary) -> String:
	if not arg_spell(arg).is_empty():
		return "[%s]" % _sentence(arg_spell(arg))
	if arg.has("slot"):
		return "[spell %d]" % ((arg["slot"] + 1) % 10)
	return "[Chosen]"
