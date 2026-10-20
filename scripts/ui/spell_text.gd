class_name SpellText
extends RefCounted
## Spell text for the UI, each word in the color of the mana it costs.

const WORD_COLOR := {
	"red": Color("ff7d7d"),
	"blue": Color("7db3ff"),
	"green": Color("72de8f"),
	"violet": Color("c79bff"),
}
const FREE_COLOR := Color("a7abb3")  # words that cost nothing, and punctuation


## The color of a word: its mana's, or grey if it is free.
static func color_of(word: String) -> Color:
	if word == "":
		return FREE_COLOR
	return WORD_COLOR[SpellGrammar.BLOCK_COLOR[word]]


## The spell as BBCode, each word colored.
static func bbcode(ast: Dictionary) -> String:
	var out := ""
	var plain := ""
	for seg in SpellGrammar.segments(ast):
		var t: String = seg[0]
		if plain != "" and not plain.ends_with("(") and not plain.ends_with("[") \
				and not t in [")", "]", ",", "."]:
			out += " "
			plain += " "
		out += "[color=#%s]%s[/color]" % [color_of(seg[1]).to_html(false), t]
		plain += t
	return out


## A spell's cost: drain per second and what it carries, by color.
static func cost(ast: Dictionary) -> String:
	var drain := SpellGrammar.drain_per_second(ast)
	var carry := SpellGrammar.payload(ast)
	var parts: Array[String] = []
	for c in SpellGrammar.COLORS:
		if drain.has(c):
			parts.append("[color=#%s]%s %s/s[/color]" % [WORD_COLOR[c].to_html(false), c, snappedf(drain[c], 0.01)])
	var text := " ".join(parts)
	var carried: Array[String] = []
	for c in SpellGrammar.COLORS:
		if carry.has(c):
			carried.append("[color=#%s]%s %d[/color]" % [WORD_COLOR[c].to_html(false), c, carry[c]])
	if not carried.is_empty():
		text += "  ·  carries " + " ".join(carried)
	var holds: Array[String] = []
	var capacity := SpellGrammar.capacity(ast)
	for c in SpellGrammar.COLORS:
		if capacity.has(c):
			holds.append("[color=#%s]%d[/color]" % [WORD_COLOR[c].to_html(false), roundi(capacity[c])])
	text += "  ·  [color=#8a8f98]holds[/color] " + " ".join(holds)
	if ast.get("verb", "") == "move":
		text += "  ·  [color=#8a8f98]for each %d weight pushed[/color]" % Spell.MOVE_WEIGHT_UNIT
	return text
