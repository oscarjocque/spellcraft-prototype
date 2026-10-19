class_name SpellParser
extends RefCounted
## Reads a spell typed as a sentence into spell data, and suggests what can
## come next, so a spell can be typed about as fast as it can be thought:
##
##   move closest stone to me          mo cl st to me
##   destroy all fires within 3 of there, up to 2
##   create spell [destroy closest fire]      alternate 5 6
##
## Any word can be cut to a prefix that fits where it stands ("mo" is Move
## at the start, Mine after Closest); when a prefix fits several words, the
## most common reading wins, and the canonical text shows which was meant.
## Parentheses, brackets, commas, "of", "to" in "up to" and "m" in "3 m"
## are optional, plurals are fine, and a noun on its own is a Hold.

const VERB_WORDS := ["move", "create", "destroy", "mark", "hold", "alternate"]
## Noun words, most useful first: the order suggestions and ambiguous
## prefixes go by.
const NOUN_WORDS := ["closest", "me", "this", "there", "all", "here", "aimed", "chosen", "it",
		"farthest", "random", "target", "caster", "maker", "products"]
const KINDS := ["fire", "water", "wood", "stone", "spell"]
const QUALIFIER_WORDS := ["stone", "fire", "player", "thing", "wood", "water", "spell", "mana"]
const SLOT_KEYS := [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]  # slot numbers as on the keys
const RELATION_WORDS := {"target": "target_of", "caster": "caster_of", "maker": "maker_of",
		"products": "products_of"}

var _tokens: Array[String] = []
var _furthest := -1  # the furthest token position the parse reached
var _expected: Array[String] = []  # words that would fit there


## Splits typed text into lowercase words, numbers and brackets.
static func tokenize(text: String) -> Array[String]:
	var spaced := text.to_lower()
	for mark in ["(", ")", "[", "]", ","]:
		spaced = spaced.replace(mark, " %s " % mark)
	spaced = spaced.replace(".", " ")
	var out: Array[String] = []
	for word in spaced.split(" ", false):
		# "3m" is "3 m"
		var split := word.length() > 1 and word[0].is_valid_int() and not word.is_valid_int()
		if split:
			var i := 0
			while i < word.length() and word[i].is_valid_int():
				i += 1
			out.append(word.substr(0, i))
			out.append(word.substr(i))
		else:
			out.append(word)
	return out


## Parses `text`: {"ast": spell} if it reads as a grammatical spell, else
## {"error": why not}.
static func parse(text: String) -> Dictionary:
	var p := SpellParser.new()
	p._tokens = tokenize(text)
	if p._tokens.is_empty():
		return {"error": "Type a spell."}
	var invalid := ""
	for r in p._spell(0):
		if r[1] == p._tokens.size():
			var err := SpellGrammar.validate(r[0], false)
			if err == "":
				return {"ast": r[0]}
			if invalid == "":
				invalid = err
	if invalid != "":
		return {"error": invalid}
	if p._furthest >= p._tokens.size():
		return {"error": "Unfinished: next could be %s." % p._list(p._expected)}
	return {"error": "\"%s\" doesn't fit there; expected %s." % [p._tokens[maxi(p._furthest, 0)], p._list(p._expected)]}


## Up to `limit` words that could come next after `text` (completing its last
## word, if it doesn't end in a space), most useful first.
static func suggest(text: String, limit := 5) -> Array[String]:
	var p := SpellParser.new()
	p._tokens = tokenize(text)
	var partial := ""
	if not p._tokens.is_empty() and not text.ends_with(" ") and not text.ends_with("(") \
			and not text.ends_with("[") and not text.ends_with(","):
		partial = p._tokens.pop_back()
	p._spell(0)
	var out: Array[String] = []
	if p._furthest != p._tokens.size():
		return out
	for word in p._expected:
		if word.begins_with(partial) and word != partial and not word in out:
			out.append(word)
			if out.size() == limit:
				break
	return out


func _list(words: Array[String]) -> String:
	var shown := words.slice(0, 5)
	return ", ".join(shown) + (", …" if words.size() > 5 else "")


## Notes that `options` would fit at token `i` (for errors and suggestions).
func _note(i: int, options: Array) -> void:
	if i > _furthest:
		_furthest = i
		_expected.clear()
	if i == _furthest:
		for o in options:
			if not o in _expected:
				_expected.append(o)


## The options token `i` can be: itself if it is one, its singular, or every
## option it is a prefix of.
func _word(i: int, options: Array) -> Array[String]:
	_note(i, options)
	var out: Array[String] = []
	if i >= _tokens.size():
		return out
	var token := _tokens[i]
	for form in [token, token.trim_suffix("s"), token.trim_suffix("es")]:
		if form in options:
			out.append(form)
			return out
	for o in options:
		if o.begins_with(token):
			out.append(o)
	return out


func _is(i: int, token: String) -> bool:
	return i < _tokens.size() and _tokens[i] == token


## Token `i` as one of the numbers in `values`, or [] if it isn't.
func _number(i: int, values: Array) -> Array[int]:
	_note(i, values.map(func(v: int) -> String: return str(v)))
	var out: Array[int] = []
	if i < _tokens.size() and _tokens[i].is_valid_int() and _tokens[i].to_int() in values:
		out.append(_tokens[i].to_int())
	return out


# Each rule returns every way it can read the tokens from `i`, as
# [result, next token] pairs.

func _spell(i: int) -> Array:
	var out := []
	for verb in _word(i, VERB_WORDS):
		match verb:
			"create":
				for w in _creation(i + 1):
					var ast := {"verb": "create", "what": w[0]}
					out.append_array(_create_at(ast, w[1]))
			"destroy", "mark":
				for n in _noun(i + 1):
					out.append_array(_adverbs({"verb": verb, "what": n[0]}, n[1]))
			"move":
				for n in _noun(i + 1):
					for to in _word(n[1], ["to"]):
						for d in _noun(n[1] + 1):
							out.append_array(_adverbs({"verb": "move", "what": n[0], "to": d[0]}, d[1]))
			"hold":
				for n in _noun(i + 1):
					out.append_array(_adverbs({"verb": "select", "what": n[0]}, n[1]))
			"alternate":
				for a in _alt_arg(i + 1):
					for b in _alt_arg(a[1]):
						out.append_array(_adverbs({"verb": "alternate", "first": a[0], "second": b[0]}, b[1]))
	# A noun on its own is a Hold.
	for n in _noun(i):
		out.append_array(_adverbs({"verb": "select", "what": n[0]}, n[1]))
	return out


func _creation(i: int) -> Array:
	var out := []
	for kind in _word(i, KINDS):
		if kind != "spell":
			out.append([{"material": kind}, i + 1])
			continue
		var start := i + 1
		var bracketed := _is(start, "[")
		for s in _spell(start + 1 if bracketed else start):
			if not bracketed:
				out.append([{"spell": s[0]}, s[1]])
			elif _is(s[1], "]"):
				out.append([{"spell": s[0]}, s[1] + 1])
	return out


func _create_at(ast: Dictionary, i: int) -> Array:
	var out := _adverbs(ast, i)
	for w in _word(i, ["at"]):
		for n in _noun(i + 1):
			var with := ast.duplicate(true)
			with["at"] = n[0]
			out.append_array(_adverbs(with, n[1]))
	return out


## The spell as it is, or with ", up to N" after it.
func _adverbs(ast: Dictionary, i: int) -> Array:
	var out := [[ast, i]]
	var k := i + 1 if _is(i, ",") else i
	for w in _word(k, ["up"]):
		var j := k + 1
		if _is(j, "to"):
			j += 1
		for n in _number(j, SpellGrammar.UP_TO):
			var with := ast.duplicate(true)
			with["adverbs"] = {"up_to": n}
			out.append([with, j + 1])
	return out


func _alt_arg(i: int) -> Array:
	var out := []
	var bracketed := _is(i, "[")
	var k := i + 1 if bracketed else i
	var args := []
	for w in _word(k, ["spell", "chosen"]):
		if w == "chosen":
			args.append([{"ref": "chosen"}, k + 1])
		else:
			for n in _number(k + 1, SLOT_KEYS):
				args.append([{"slot": (n + 9) % 10}, k + 2])
	for n in _number(k, SLOT_KEYS):
		args.append([{"slot": (n + 9) % 10}, k + 1])
	for a in args:
		if not bracketed:
			out.append(a)
		elif _is(a[1], "]"):
			out.append([a[0], a[1] + 1])
	return out


func _noun(i: int) -> Array:
	var out := []
	if _is(i, "("):
		for n in _noun(i + 1):
			if _is(n[1], ")"):
				out.append([n[0], n[1] + 1])
		return out
	for w in _word(i, NOUN_WORDS):
		if w in SpellGrammar.REFS:
			out.append([{"ref": w}, i + 1])
		elif w in SpellGrammar.PICKERS:
			out.append_array(_picked(w, [], i + 1))
		else:
			var k := i + 1
			if _is(k, "of"):
				k += 1
			for n in _noun(k):
				out.append([{RELATION_WORDS[w]: n[0]}, n[1]])
	return out


## After a picker: adjectives, then the qualifier, then its options.
func _picked(picker: String, adj: Array, i: int) -> Array:
	var out := []
	for w in _word(i, SpellGrammar.ADJECTIVES + QUALIFIER_WORDS):
		if w in SpellGrammar.ADJECTIVES and not w in adj and not w in QUALIFIER_WORDS:
			out.append_array(_picked(picker, adj + [w], i + 1))
		elif w in QUALIFIER_WORDS:
			var noun := {picker: w}
			if not adj.is_empty():
				noun["adj"] = adj
			out.append_array(_picker_options(noun, i + 1))
	return out


## A picker noun as it is, "within N m (of X)", or "to X".
func _picker_options(noun: Dictionary, i: int) -> Array:
	var out := [[noun, i]]
	for w in _word(i, ["within", "to"]):
		if w == "to":
			for n in _noun(i + 1):
				var with := noun.duplicate(true)
				with["from"] = n[0]
				out.append([with, n[1]])
			continue
		for d in _number(i + 1, SpellGrammar.DISTANCES):
			var within := noun.duplicate(true)
			within["within"] = d
			var k := i + 2
			if _is(k, "m"):
				k += 1
			out.append([within, k])
			for of in _word(k, ["of"]):
				for n in _noun(k + 1):
					var with := within.duplicate(true)
					with["from"] = n[0]
					out.append([with, n[1]])
	return out
