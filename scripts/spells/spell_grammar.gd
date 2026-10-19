class_name SpellGrammar
extends RefCounted
## Spells as data. A spell is a sentence: a verb with its noun slots, or an
## incomplete one: a selector cast on its own, which the caster then holds.
##
##   {"verb": "create", "what": {"material": "wood"}}
##   {"verb": "create", "what": {"spell": SPELL}}     # creates another spell
##   {"verb": "destroy", "what": NOUN}
##   {"verb": "move", "what": NOUN, "to": NOUN}
##   {"verb": "select", "qualifier": "player"}   # a Closest selector on its own
##
## NOUN is {"ref": "me"}, {"ref": "it"}, {"ref": "held"}, {"ref": "chosen"},
## {"closest": QUALIFIER} or {"target_of": NOUN}.
## Held is the selector the caster is holding; the spell takes it over. An
## inline Closest chooses once, when the spell is cast; a held one keeps
## choosing, and the spell follows whatever it picks now.
## Chosen is the spell the caster has chosen in their inventory of attached
## spells. Target of a spell is what that spell acts on right now (a Create's
## product, a selector's pick), re-checked every tick.
## Every block is one word and costs mana of one color. A created spell pays
## its own drain: the spell creating it must carry that mana as a reserve
## (see `payload`).

const VERBS := ["create", "destroy", "move", "select"]
const MATERIALS := ["fire", "water", "wood", "stone"]
const QUALIFIERS := ["fire", "water", "wood", "stone", "spell", "player", "mana"]
const REFS := ["me", "it", "held", "chosen"]
const COLORS := ["red", "blue", "green", "violet"]
const CREATED_SPELL_SECONDS := 60.0  # how long a created spell's mana must last
const CREATED_SPELLS := 3  # how many spells one Create Spell makes

## First sketch from the design doc, to be tuned.
const BLOCK_COLOR := {
	"create": "red", "fire": "red",
	"water": "blue", "mana": "blue",
	"move": "green", "stone": "green", "wood": "green",
	"destroy": "violet", "closest": "violet", "spell": "violet", "player": "violet",
	"me": "violet", "it": "violet", "held": "violet", "chosen": "violet", "target_of": "violet",
}

## Mana per second each block drains while its spell is active.
const DRAIN_PER_BLOCK := 0.2


## Every word of the spell, including the words of any spell it creates.
static func blocks(ast: Dictionary) -> Array[String]:
	var out := own_blocks(ast)
	var inner := created_spell(ast)
	if not inner.is_empty():
		out.append_array(blocks(inner))
	return out


## The words this spell pays for itself, without the spell it creates.
static func own_blocks(ast: Dictionary) -> Array[String]:
	var out: Array[String] = []
	match ast.get("verb", ""):
		"create":
			out.append("create")
			out.append("spell" if ast["what"].has("spell") else ast["what"]["material"])
		"destroy":
			out.append("destroy")
			_noun_blocks(ast["what"], out)
		"move":
			out.append("move")
			_noun_blocks(ast["what"], out)
			_noun_blocks(ast["to"], out)
		"select":
			out.append("closest")
			out.append(ast["qualifier"])
	return out


static func _noun_blocks(noun: Dictionary, out: Array[String]) -> void:
	if noun.has("ref"):
		out.append(noun["ref"])
	elif noun.has("target_of"):
		out.append("target_of")
		_noun_blocks(noun["target_of"], out)
	else:
		out.append("closest")
		out.append(noun["closest"])


## The spell this one creates, or {} if it creates none.
static func created_spell(ast: Dictionary) -> Dictionary:
	if ast.get("verb", "") == "create" and ast["what"] is Dictionary and ast["what"].get("spell") is Dictionary:
		return ast["what"]["spell"]
	return {}


## Mana per second this spell's own blocks drain while it is active.
static func drain_per_second(ast: Dictionary) -> Dictionary:
	var drain := {}
	for b in own_blocks(ast):
		var c: String = BLOCK_COLOR[b]
		drain[c] = drain.get(c, 0.0) + DRAIN_PER_BLOCK
	return drain


## Mana a spell must carry in reserve for the spells it creates: one `share`
## for each of the CREATED_SPELLS it makes.
static func payload(ast: Dictionary) -> Dictionary:
	var inner := created_spell(ast)
	if inner.is_empty():
		return {}
	var need := share(inner)
	for c in need:
		need[c] *= CREATED_SPELLS
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
	var verb: String = ast.get("verb", "")
	match verb:
		"create":
			var what: Variant = ast.get("what")
			if not what is Dictionary:
				return "Create needs a material or a spell."
			if what.has("spell"):
				if not what["spell"] is Dictionary:
					return "Create Spell needs a description of the spell."
				return validate(what["spell"])
			if not what.get("material", "") in MATERIALS:
				return "Create needs a material or a spell."
		"destroy":
			if not _valid_noun(ast.get("what")):
				return "Destroy needs something to destroy."
		"move":
			if not (_valid_noun(ast.get("what")) and _valid_noun(ast.get("to"))):
				return "Move needs something to move and somewhere to move it."
		"select":
			if not ast.get("qualifier", "") in QUALIFIERS:
				return "Closest needs a qualifier."
		_:
			return "Unknown verb: %s" % verb
	return ""


static func _valid_noun(noun: Variant) -> bool:
	if not noun is Dictionary:
		return false
	if noun.has("ref"):
		return noun["ref"] in REFS
	if noun.has("target_of"):
		return _valid_noun(noun["target_of"])
	return noun.get("closest", "") in QUALIFIERS


static func to_text(ast: Dictionary) -> String:
	return _sentence(ast) + "."


static func _sentence(ast: Dictionary) -> String:
	match ast.get("verb", ""):
		"create":
			var inner := created_spell(ast)
			if not inner.is_empty():
				return "Create Spell [%s]" % _sentence(inner)
			return "Create %s" % ast["what"]["material"].capitalize()
		"destroy":
			return "Destroy %s" % _noun_text(ast["what"])
		"move":
			return "Move %s to %s" % [_noun_text(ast["what"]), _noun_text(ast["to"])]
		"select":
			return "Closest %s" % ast["qualifier"].capitalize()
	return "?"


static func _noun_text(noun: Dictionary) -> String:
	if noun.has("ref"):
		return noun["ref"].capitalize()
	if noun.has("target_of"):
		return "(Target of %s)" % _noun_text(noun["target_of"])
	return "(Closest %s)" % noun["closest"].capitalize()
