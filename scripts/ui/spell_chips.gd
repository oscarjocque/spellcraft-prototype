class_name SpellChips
extends HFlowContainer
## A spell as a row of word chips, each in its mana's color. Clicking a word
## opens a menu of at most five choices (longer lists are split into
## submenus) to change it; "+" chips add optional parts, and optional parts
## can be removed from their own menu. Edits change the spell in place.

signal edited

## The noun kinds, grouped so that no menu has more than five entries.
const NOUN_GROUPS := [
	["You", ["me", "here"]],
	["Pick", ["closest", "farthest", "random", "all"]],
	["Point", ["this", "there", "aimed"]],
	["Spell", ["chosen", "it"]],
	["Of", ["target_of", "caster_of", "maker_of", "products_of"]],
]

var _spell := {}


## Shows `ast` (edited in place from now on).
func show_spell(ast: Dictionary) -> void:
	_spell = ast
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_add_spell(ast)


func _changed() -> void:
	show_spell.call_deferred(_spell)  # not during the menu's own signal
	edited.emit()


# --- Building chips ----------------------------------------------------------

## A word chip: a button in `word`'s mana color that opens `items`, a menu of
## [label, action] and [label, sub-items] entries. The entry for the word as
## it is now is ticked, and so is the submenu it's in.
func _chip(text: String, word: String, items: Array) -> MenuButton:
	var chip := MenuButton.new()
	chip.text = text
	chip.flat = true
	chip.focus_mode = Control.FOCUS_NONE
	var color := SpellText.color_of(word)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		chip.add_theme_color_override(state, color.lightened(0.25) if state == "font_hover_color" else color)
	chip.add_theme_stylebox_override("normal", _chip_style(color, 0.10))
	chip.add_theme_stylebox_override("hover", _chip_style(color, 0.22))
	chip.add_theme_stylebox_override("pressed", _chip_style(color, 0.30))
	_fill_menu(chip.get_popup(), items, text)
	add_child(chip)
	return chip


static func _chip_style(color: Color, alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, alpha)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style


## Fills `popup` with `items`; returns whether one of them is `current`.
func _fill_menu(popup: PopupMenu, items: Array, current: String) -> bool:
	assert(items.size() <= 5, "a menu has at most five entries")
	var actions := []
	var found := false
	for item in items:
		var here := false
		if item[1] is Callable:
			popup.add_item(item[0], actions.size())
			actions.append(item[1])
			var label: String = item[0].to_lower()
			here = label == current.to_lower() or current.to_lower().ends_with(" " + label)  # "up to 2"
		else:
			var sub := PopupMenu.new()
			here = _fill_menu(sub, item[1], current)
			popup.add_submenu_node_item(item[0], sub, -1)
		if here:
			popup.set_item_as_radio_checkable(popup.item_count - 1, true)
			popup.set_item_checked(popup.item_count - 1, true)
			found = true
	popup.id_pressed.connect(func(id: int) -> void:
		actions[id].call()
		_changed())
	return found


## Plain text between chips: punctuation and free words.
func _text(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", SpellText.FREE_COLOR)
	add_child(label)


## A "+" chip offering optional parts, if there are any to add.
func _plus(items: Array) -> void:
	if not items.is_empty():
		_chip("+", "", items)


# --- Spells ------------------------------------------------------------------

func _add_spell(ast: Dictionary) -> void:
	var verb: String = ast["verb"]
	_chip("Hold" if verb == "select" else verb.capitalize(), "" if verb == "select" else verb,
			_verb_items(ast))
	var plus := []
	match verb:
		"create":
			_add_creation(ast)
			if ast.get("at") is Dictionary:
				_chip("at", "at", [["Remove", func() -> void: ast.erase("at")]])
				_add_noun(ast["at"])
			else:
				plus.append(["at …", func() -> void: ast["at"] = {"ref": "aimed"}])
		"destroy", "mark":
			_add_noun(ast["what"])
		"move":
			_add_noun(ast["what"])
			_text("to")
			_add_noun(ast["to"])
		"select":
			if not ast.get("what") is Dictionary:
				ast["what"] = SpellGrammar.held_noun(ast)
				ast.erase("qualifier")
			_add_noun(ast["what"])
		"alternate":
			for key in ["first", "second"]:
				_add_alternate_arg(ast[key])
	var limit := SpellGrammar.up_to(ast)
	if limit > 0:
		_text(",")
		_chip("up to %d" % limit, "up_to", _number_items(SpellGrammar.UP_TO, "%d",
				func(n: int) -> void: ast["adverbs"] = {"up_to": n},
				func() -> void: ast.erase("adverbs")))
	else:
		plus.append(["up to ▸", _number_items(SpellGrammar.UP_TO, "%d",
				func(n: int) -> void: ast["adverbs"] = {"up_to": n})])
	_plus(plus)


func _verb_items(ast: Dictionary) -> Array:
	var items := []
	for verb in ["create", "destroy", "move", "mark"]:
		items.append([verb.capitalize(), _set_verb.bind(ast, verb)])
	items.append(["More ▸", [["Hold", _set_verb.bind(ast, "select")],
			["Alternate", _set_verb.bind(ast, "alternate")]]])
	return items


## Changes the verb, keeping what the old one acted on where the new one has
## a place for it, and its adverbs.
static func _set_verb(ast: Dictionary, verb: String) -> void:
	var noun: Variant = ast.get("what")
	if not noun is Dictionary or noun.has("material") or noun.has("spell"):
		noun = {"closest": "stone"}
	var adverbs: Variant = ast.get("adverbs")
	ast.clear()
	match verb:
		"create":
			ast.merge({"verb": "create", "what": {"material": "wood"}})
		"move":
			ast.merge({"verb": "move", "what": noun, "to": {"ref": "me"}})
		"alternate":
			ast.merge({"verb": "alternate", "first": {"slot": 4}, "second": {"slot": 5}})
		_:
			ast.merge({"verb": verb, "what": noun})
	if adverbs is Dictionary:
		ast["adverbs"] = adverbs


func _add_creation(ast: Dictionary) -> void:
	var what: Dictionary = ast["what"]
	var kind: String = "spell" if what.has("spell") else what["material"]
	var items := []
	for k in SpellGrammar.MATERIALS + ["spell"]:
		items.append([k.capitalize(), func() -> void:
			what.clear()
			if k == "spell":
				what["spell"] = {"verb": "destroy", "what": {"closest": "fire"}}
			else:
				what["material"] = k])
	_chip(kind.capitalize(), kind, items)
	if what.has("spell"):
		_text("[")
		_add_spell(what["spell"])
		_text("]")


func _add_alternate_arg(arg: Dictionary) -> void:
	var set_slot := func(n: int) -> void:
		arg.clear()
		arg["slot"] = (n + 9) % 10
	var label := "Chosen" if arg.has("ref") else "spell %d" % ((arg.get("slot", 0) + 1) % 10)
	_text("[")
	_chip(label, "chosen" if arg.has("ref") else "", [
		["Chosen (an attached spell)", func() -> void:
			arg.clear()
			arg["ref"] = "chosen"],
		["Spell 1–5 ▸", _number_items([1, 2, 3, 4, 5], "spell %d", set_slot)],
		["Spell 6–0 ▸", _number_items([6, 7, 8, 9, 0], "spell %d", set_slot)],
	])
	_text("]")


## Menu entries for `numbers` (labelled with `format`) calling `pick` with
## the number, plus a Remove entry if `remove` is given.
static func _number_items(numbers: Array, format: String, pick: Callable, remove := Callable()) -> Array:
	var items := []
	for n in numbers:
		var label: String = format % n
		items.append([label.capitalize() if n is String else label, pick.bind(n)])
	if remove.is_valid():
		items.append(["Remove", remove])
	return items


# --- Nouns -------------------------------------------------------------------

func _add_noun(noun: Dictionary) -> void:
	if noun.has("ref"):
		_chip(noun["ref"].capitalize(), noun["ref"], _kind_items(noun))
		return
	_text("(")
	var rel := SpellGrammar.relation_of(noun)
	if rel != "":
		_chip(rel.capitalize().replace(" Of", " of"), rel, _kind_items(noun))
		_add_noun(noun[rel])
	else:
		_add_picker(noun)
	_text(")")


## The noun-kind menu: five groups of kinds.
func _kind_items(noun: Dictionary) -> Array:
	var items := []
	for group in NOUN_GROUPS:
		var sub := []
		for kind in group[1]:
			sub.append([kind.capitalize().replace(" Of", " of"), _set_kind.bind(noun, kind)])
		items.append([group[0] + " ▸", sub])
	return items


## Makes `noun` a `kind` noun: a picker keeps its qualifier and options when
## switching pickers; a relation wraps the noun as it was.
static func _set_kind(noun: Dictionary, kind: String) -> void:
	var old := noun.duplicate(true)
	var picker := SpellGrammar.picker_of(old)
	noun.clear()
	if kind in SpellGrammar.REFS:
		noun["ref"] = kind
	elif kind in SpellGrammar.PICKERS:
		if picker != "":
			noun.merge(old)
			noun.erase(picker)
			noun[kind] = old[picker]
		else:
			noun[kind] = "stone"
	else:
		var rel := SpellGrammar.relation_of(old)
		noun[kind] = old[rel] if rel != "" else old


func _add_picker(noun: Dictionary) -> void:
	var picker := SpellGrammar.picker_of(noun)
	_chip(picker.capitalize(), picker, _kind_items(noun))
	var adj: Array = noun.get("adj", [])
	for a in adj:
		var items := [["Remove", func() -> void:
			adj.erase(a)
			if adj.is_empty():
				noun.erase("adj")]]
		for other in SpellGrammar.ADJECTIVES:
			if not other in adj:
				items.append([other.capitalize(), func() -> void: adj[adj.find(a)] = other])
		_chip(a.capitalize(), a, items)
	var set_qualifier := func(q: String) -> void: noun[picker] = q
	_chip(noun[picker].capitalize(), noun[picker], [
		["Thing", set_qualifier.bind("thing")],
		["Player", set_qualifier.bind("player")],
		["Spell", set_qualifier.bind("spell")],
		["Mana", set_qualifier.bind("mana")],
		["Material ▸", _number_items(SpellGrammar.MATERIALS, "%s", set_qualifier)],
	])
	if noun.has("within"):
		_chip("within %d m" % noun["within"], "within", _number_items(SpellGrammar.DISTANCES, "%d m",
				func(d: int) -> void: noun["within"] = d, func() -> void: noun.erase("within")))
	if noun.get("from") is Dictionary:
		_chip("of" if noun.has("within") else "to", "from", [["Remove", func() -> void: noun.erase("from")]])
		_add_noun(noun["from"])
	var plus := []
	var missing := SpellGrammar.ADJECTIVES.filter(func(a: String) -> bool: return not a in adj)
	if not missing.is_empty():
		var add_adj := func(a: String) -> void:
			adj.append(a)
			noun["adj"] = adj
		plus.append(["adjective ▸", _number_items(missing, "%s", add_adj)])
	if not noun.has("within"):
		plus.append(["within ▸", _number_items(SpellGrammar.DISTANCES, "%d m",
				func(d: int) -> void: noun["within"] = d)])
	if not noun.get("from") is Dictionary:
		plus.append(["measured from …", func() -> void: noun["from"] = {"ref": "there"}])
	_plus(plus)
