class_name SpellGrammar
extends RefCounted
## Spells as data. A spell is a sentence: a verb with its noun slots, or a
## selector cast on its own as an independent spell.
##
##   {"verb": "create", "what": {"material": "wood"}}
##   {"verb": "destroy", "what": NOUN}
##   {"verb": "move", "what": NOUN, "to": NOUN}
##   {"verb": "select", "qualifier": "player"}   # independent Closest selector
##
## NOUN is {"ref": "me"}, {"ref": "it"} or {"closest": QUALIFIER}.
## Every block is one word and costs mana of one color.

const VERBS := ["create", "destroy", "move", "select"]
const MATERIALS := ["fire", "water", "wood", "stone"]
const QUALIFIERS := ["fire", "water", "wood", "stone", "spell", "player"]
const REFS := ["me", "it"]
const COLORS := ["red", "blue", "green", "violet"]
const SLOT_LIMIT := 6  # words per spell; grows with progression later

## First sketch from the design doc, to be tuned.
const BLOCK_COLOR := {
	"create": "red", "fire": "red",
	"water": "blue",
	"move": "green", "stone": "green", "wood": "green",
	"destroy": "violet", "closest": "violet", "spell": "violet", "player": "violet",
	"me": "violet", "it": "violet",
}

## Mana per second each block drains while its spell is active.
const DRAIN_PER_BLOCK := 1.0


static func blocks(ast: Dictionary) -> Array[String]:
	var out: Array[String] = []
	match ast.get("verb", ""):
		"create":
			out.append("create")
			out.append(ast["what"]["material"])
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
	else:
		out.append("closest")
		out.append(noun["closest"])


static func drain_per_second(ast: Dictionary) -> Dictionary:
	var drain := {}
	for b in blocks(ast):
		var c: String = BLOCK_COLOR[b]
		drain[c] = drain.get(c, 0.0) + DRAIN_PER_BLOCK
	return drain


## Returns "" if the spell is grammatical and fits the slot limit, else why not.
static func validate(ast: Dictionary) -> String:
	var verb: String = ast.get("verb", "")
	match verb:
		"create":
			if not (ast.get("what") is Dictionary and ast["what"].get("material", "") in MATERIALS):
				return "Create needs a material."
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
	var words := blocks(ast).size()
	if words > SLOT_LIMIT:
		return "Spell has %d words; the limit is %d." % [words, SLOT_LIMIT]
	return ""


static func _valid_noun(noun: Variant) -> bool:
	if not noun is Dictionary:
		return false
	if noun.has("ref"):
		return noun["ref"] in REFS
	return noun.get("closest", "") in QUALIFIERS


static func to_text(ast: Dictionary) -> String:
	match ast.get("verb", ""):
		"create":
			return "Create %s." % ast["what"]["material"].capitalize()
		"destroy":
			return "Destroy %s." % _noun_text(ast["what"])
		"move":
			return "Move %s to %s." % [_noun_text(ast["what"]), _noun_text(ast["to"])]
		"select":
			return "Closest %s (independent)." % ast["qualifier"].capitalize()
	return "?"


static func _noun_text(noun: Dictionary) -> String:
	if noun.has("ref"):
		return noun["ref"].capitalize()
	return "(Closest %s)" % noun["closest"].capitalize()
