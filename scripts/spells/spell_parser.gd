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
## Parentheses, brackets, commas, "of", "to" in "up to" and in Move, and
## "m" in "3 m" are optional, plurals are fine, a thing on its own is the
## closest one ("move stone to me"), and a noun on its own is a Hold.
## What a verb acts on can be left out to mean This (the thing under the
## mouse), and where Move moves it to to mean There: "destroy" destroys what
## the mouse is on, "move stone" moves the closest stone to the mouse.
## A word one slip from fitting (a letter missing, extra, wrong or swapped)
## is read as the word it nearly is, if nothing reads without that.

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
var _forgiving := false  # read words one slip from fitting as the word
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
## {"error": why not}, with "unfinished": true if it only needs more words.
static func parse(text: String) -> Dictionary:
	var tokens := tokenize(text)
	if tokens.is_empty():
		return {"error": "Type a spell."}
	var strict := SpellParser.new()
	strict._tokens = tokens
	var r := strict._read()
	if r.has("ast"):
		return r
	# Only then forgive slips, so a word typed right is never misread.
	var forgiving := SpellParser.new()
	forgiving._tokens = tokens
	forgiving._forgiving = true
	var f := forgiving._read()
	return f if f.has("ast") else r


func _read() -> Dictionary:
	var invalid := ""
	for r in _spell(0):
		if r[1] == _tokens.size():
			var err := SpellGrammar.validate(r[0], false)
			if err == "":
				return {"ast": r[0]}
			if invalid == "":
				invalid = err
	if invalid != "":
		return {"error": invalid}
	if _furthest >= _tokens.size():
		return {"error": "Unfinished: next could be %s" % _list(_expected), "unfinished": true}
	return {"error": "\"%s\" doesn't fit there; expected %s" % [_tokens[maxi(_furthest, 0)], _list(_expected)]}


## Up to `limit` words that could come next after `text` (completing its last
## word, if it doesn't end in a space), most useful first.
static func suggest(text: String, limit := 5) -> Array[String]:
	var tokens := tokenize(text)
	var partial := ""
	if not tokens.is_empty() and not text.ends_with(" ") and not text.ends_with("(") \
			and not text.ends_with("[") and not text.ends_with(","):
		partial = tokens.pop_back()
	var p := SpellParser.new()
	p._tokens = tokens
	p._spell(0)
	if p._furthest != tokens.size():  # an earlier word slipped?
		p = SpellParser.new()
		p._tokens = tokens
		p._forgiving = true
		p._spell(0)
	var out: Array[String] = []
	if p._furthest != tokens.size():
		return out
	for word in p._expected:
		if word.begins_with(partial) and word != partial and not word in out:
			out.append(word)
	if out.is_empty():  # a slip: offer the words it nearly is
		for word in p._expected:
			if _slip(partial, word) and not word in out:
				out.append(word)
	return out.slice(0, limit)


func _list(words: Array[String]) -> String:
	var shown := words.slice(0, 5)
	return ", ".join(shown) + (", …" if words.size() > 5 else ".")


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
## option it is a prefix of; when forgiving and there are none, every option
## it is one slip from.
func _word(i: int, options: Array) -> Array[String]:
	_note(i, options)
	return _match(i, options)


## As _word, without noting the options as expected there.
func _match(i: int, options: Array) -> Array[String]:
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
	if out.is_empty() and _forgiving:
		for o in options:
			if _slip(token, o):
				out.append(o)
	return out


## Whether `token` is one slip from `word` or from a start of it: one letter
## missing, extra, wrong, or two swapped. Not for words under three letters
## or a wrong first letter, which are too likely to be meant as typed.
static func _slip(token: String, word: String) -> bool:
	if token.length() < 3 or word.length() < 3 or token[0] != word[0]:
		return false
	for n in [token.length() - 1, token.length(), token.length() + 1]:
		if n <= word.length() and _one_apart(token, word.substr(0, n)):
			return true
	return false


static func _one_apart(a: String, b: String) -> bool:
	if a == b or absi(a.length() - b.length()) > 1:
		return false
	var i := 0
	while i < mini(a.length(), b.length()) and a[i] == b[i]:
		i += 1
	if a.length() > b.length():
		return a.substr(i + 1) == b.substr(i)
	if a.length() < b.length():
		return a.substr(i) == b.substr(i + 1)
	if a.substr(i + 1) == b.substr(i + 1):
		return true
	return i + 1 < a.length() and a[i] == b[i + 1] and a[i + 1] == b[i] and a.substr(i + 2) == b.substr(i + 2)


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
				for n in _object(i + 1):
					out.append_array(_adverbs({"verb": verb, "what": n[0]}, n[1]))
			"move":
				for n in _object(i + 1):
					var to := _is(n[1], "to")
					var k: int = n[1] + 1 if to else n[1]
					if not to:
						_note(k, ["to"])
					var dests := _noun(k)
					if not to:
						dests.append([{"ref": "there"}, k])
					for d in dests:
						out.append_array(_adverbs({"verb": "move", "what": n[0], "to": d[0]}, d[1]))
			"hold":
				for n in _object(i + 1):
					out.append_array(_adverbs({"verb": "select", "what": n[0]}, n[1]))
			"alternate":
				for a in _alt_arg(i + 1):
					for b in _alt_arg(a[1]):
						out.append_array(_adverbs({"verb": "alternate", "first": a[0], "second": b[0]}, b[1]))
	# A noun on its own is a Hold.
	for n in _noun(i):
		out.append_array(_adverbs({"verb": "select", "what": n[0]}, n[1]))
	return out


## What a verb acts on: a noun, or This (under the mouse) if it is left out.
func _object(i: int) -> Array:
	var out := _noun(i)
	out.append([{"ref": "this"}, i])
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
	# A thing on its own (with any adjectives) is the closest one. A noun word
	# typed in full comes first; otherwise the closest thing does.
	var full := i < _tokens.size() and (_tokens[i] in NOUN_WORDS
			or _forgiving and NOUN_WORDS.any(func(w: String) -> bool: return _one_apart(_tokens[i], w)))
	var things := _picked("closest", [], i, false)
	if not full:
		out.append_array(things)
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
	if full:
		out.append_array(things)
	# Offer the things too, after the noun words: "destroy fi" suggests fire.
	_note(i, QUALIFIER_WORDS + SpellGrammar.ADJECTIVES)
	return out


## After a picker: adjectives, then the qualifier, then its options.
## `suggest_words` false: don't offer these words as suggestions (for the
## implicit Closest, whose words are offered after Closest itself).
func _picked(picker: String, adj: Array, i: int, suggest_words := true) -> Array:
	var out := []
	var words: Array = QUALIFIER_WORDS + SpellGrammar.ADJECTIVES
	var found := _word(i, words) if suggest_words else _match(i, words)
	for w in found:
		if w in SpellGrammar.ADJECTIVES and not w in adj and not w in QUALIFIER_WORDS:
			out.append_array(_picked(picker, adj + [w], i + 1, suggest_words))
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
