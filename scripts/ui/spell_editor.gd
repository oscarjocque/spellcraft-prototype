class_name SpellEditor
extends PanelContainer
## Edits the spell slots. Like Scratch's slots, each picker only offers blocks
## that fit grammatically, so an incomplete spell can't be built. Choosing
## Spell as Create's object opens a nested sentence for the spell to create,
## and nouns that take another noun (Target of, "to", "at") open one too.
##
## A placeholder for a drag-and-drop block editor.

## Noun kinds offered, in the noun picker's order.
const NOUN_KINDS := ["me", "it", "chosen", "this", "there", "aimed",
		"closest", "farthest", "random", "all",
		"target_of", "caster_of", "maker_of", "products_of"]

var slots: Array = []  # shared with Main; edited in place

var _rows: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("15171c")
	style.set_content_margin_all(12)
	style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "Spell editor (simulation paused, Tab to close)"
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1120, 620)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)


func open(p_slots: Array) -> void:
	slots = p_slots
	for c in _rows.get_children():
		_rows.remove_child(c)  # detach now; queue_free alone leaves it laid out this frame
		c.queue_free()
	for i in slots.size():
		var slot := VBoxContainer.new()
		_rows.add_child(slot)
		_fill_slot(slot, i)
	move_to_front()  # above the HUD's labels
	show()
	_recenter.call_deferred()


## Containers grow but never shrink on their own, so fit to the content again.
func _recenter() -> void:
	reset_size()
	position = ((get_viewport_rect().size - size) / 2).max(Vector2.ZERO)


## One slot: the sentence's pickers (wrapping onto more lines as needed), with
## its word count and cost below.
func _fill_slot(slot: VBoxContainer, i: int) -> void:
	for c in slot.get_children():
		slot.remove_child(c)
		c.queue_free()
	var ast: Dictionary = slots[i]
	var row := HFlowContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.add_child(row)
	var label := _text("%d" % ((i + 1) % 10))
	label.custom_minimum_size.x = 20
	row.add_child(label)
	_add_spell(row, ast, func() -> void: _fill_slot(slot, i))

	var err := SpellGrammar.validate(ast)
	var summary := _text("      " + err)
	if err != "":
		summary.add_theme_color_override("font_color", Color("ff8a8a"))
	else:
		summary.text = "      %d words · %s" % [SpellGrammar.blocks(ast).size(), _cost_text(ast)]
		summary.add_theme_color_override("font_color", Color("a0a4ab"))
	summary.add_theme_font_size_override("font_size", 12)
	slot.add_child(summary)


## The pickers for one sentence. Edits `ast` in place, so the same code edits a
## slot's spell and any spell nested inside it by Create Spell.
func _add_spell(row: Container, ast: Dictionary, refresh: Callable) -> void:
	if ast["verb"] == "select" and not ast.has("what"):
		ast["what"] = SpellGrammar.held_noun(ast)  # older form
		ast.erase("qualifier")
	var verbs := ["Create", "Destroy", "Move", "Mark", "Hold", "Alternate"]
	var verb := _picker(verbs, SpellGrammar.VERBS.find(ast["verb"]))
	verb.item_selected.connect(func(idx: int) -> void:
		ast.clear()
		ast.merge(_default_for(SpellGrammar.VERBS[idx]))
		refresh.call())
	row.add_child(verb)

	match ast["verb"]:
		"create":
			_add_creation(row, ast, refresh)
		"destroy", "mark", "select":
			_add_noun(row, ast["what"], refresh)
		"move":
			_add_noun(row, ast["what"], refresh)
			row.add_child(_text("to"))
			_add_noun(row, ast["to"], refresh)
		"alternate":
			for key in ["first", "second"]:
				row.add_child(_text("["))
				_add_spell(row, ast[key], refresh)
				row.add_child(_text("]"))


## Create's object (a material, or Spell followed by that spell's
## description), then optionally "at" a noun.
func _add_creation(row: Container, ast: Dictionary, refresh: Callable) -> void:
	var what: Dictionary = ast["what"]
	var kinds: Array = SpellGrammar.MATERIALS + ["spell"]
	var kind := _picker(kinds.map(func(w: String) -> String: return w.capitalize()),
			kinds.find("spell" if what.has("spell") else what["material"]))
	kind.item_selected.connect(func(idx: int) -> void:
		what.clear()
		if kinds[idx] == "spell":
			what["spell"] = _default_for("create")
		else:
			what["material"] = kinds[idx]
		refresh.call())
	row.add_child(kind)
	if what.has("spell"):
		row.add_child(_text("["))
		_add_spell(row, what["spell"], refresh)
		row.add_child(_text("]"))
	_add_optional_noun(row, ast, "at", ["in front of me", "at"], refresh)


## A noun slot: a ref, a picker with its options, or a relation and its noun.
func _add_noun(row: Container, noun: Dictionary, refresh: Callable) -> void:
	var current: String = noun["ref"] if noun.has("ref") else SpellGrammar.picker_of(noun)
	if current == "":
		current = SpellGrammar.relation_of(noun)
	var names: Array = NOUN_KINDS.map(func(k: String) -> String: return k.capitalize().replace(" Of", " of"))
	var kind := _picker(names, NOUN_KINDS.find(current))
	kind.item_selected.connect(func(idx: int) -> void:
		var picked: String = NOUN_KINDS[idx]
		var qualifier: String = noun.get(SpellGrammar.picker_of(noun), "stone")
		noun.clear()
		if picked in SpellGrammar.REFS:
			noun["ref"] = picked
		elif picked in SpellGrammar.PICKERS:
			noun[picked] = qualifier
		else:
			noun[picked] = {"ref": "chosen"}
		refresh.call())
	row.add_child(kind)

	var picker := SpellGrammar.picker_of(noun)
	var rel := SpellGrammar.relation_of(noun)
	if rel != "":
		_add_noun(row, noun[rel], refresh)
	elif picker != "":
		_add_adjectives(row, noun, refresh)
		row.add_child(_word_picker(SpellGrammar.QUALIFIERS, noun, picker, refresh))
		var within := ["anywhere"] + SpellGrammar.DISTANCES.map(func(d: int) -> String: return "within %d m" % d)
		var w := _picker(within, SpellGrammar.DISTANCES.find(noun.get("within", 0)) + 1)
		w.item_selected.connect(func(idx: int) -> void:
			if idx == 0:
				noun.erase("within")
			else:
				noun["within"] = SpellGrammar.DISTANCES[idx - 1]
			refresh.call())
		row.add_child(w)
		var measured := ["of the spell", "of"] if noun.has("within") else ["near the spell", "to"]
		_add_optional_noun(row, noun, "from", measured, refresh)


## A toggle between leaving `key` out (labels[0]) and a noun after labels[1].
func _add_optional_noun(row: Container, owner: Dictionary, key: String, labels: Array, refresh: Callable) -> void:
	var has := owner.get(key) is Dictionary
	var toggle := _picker([labels[0], labels[1] + " …"], 1 if has else 0)
	toggle.item_selected.connect(func(idx: int) -> void:
		if idx == 0:
			owner.erase(key)
		else:
			owner[key] = {"ref": "there"}
		refresh.call())
	row.add_child(toggle)
	if has:
		_add_noun(row, owner[key], refresh)


## A menu of adjectives to tick on and off.
func _add_adjectives(row: Container, noun: Dictionary, refresh: Callable) -> void:
	var adj: Array = noun.get("adj", [])
	var menu := MenuButton.new()
	menu.flat = false
	menu.text = " ".join(adj.map(func(a: String) -> String: return a.capitalize())) if not adj.is_empty() else "+ adjective"
	var popup := menu.get_popup()
	for i in SpellGrammar.ADJECTIVES.size():
		popup.add_check_item(SpellGrammar.ADJECTIVES[i].capitalize(), i)
		popup.set_item_checked(i, SpellGrammar.ADJECTIVES[i] in adj)
	popup.id_pressed.connect(func(id: int) -> void:
		var a: String = SpellGrammar.ADJECTIVES[id]
		if a in adj:
			adj.erase(a)
		else:
			adj.append(a)
		if adj.is_empty():
			noun.erase("adj")
		else:
			noun["adj"] = adj
		refresh.call())
	row.add_child(menu)


func _word_picker(words: Array, target: Dictionary, key: String, refresh: Callable) -> OptionButton:
	var names: Array = words.map(func(w: String) -> String: return w.capitalize())
	var picker := _picker(names, words.find(target[key]))
	picker.item_selected.connect(func(idx: int) -> void:
		target[key] = words[idx]
		refresh.call())
	return picker


func _picker(items: Array, selected: int) -> OptionButton:
	var b := OptionButton.new()
	for item in items:
		b.add_item(item)
	b.select(selected)
	return b


func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _cost_text(ast: Dictionary) -> String:
	var drain := SpellGrammar.drain_per_second(ast)
	var carry := SpellGrammar.payload(ast)
	var drains: Array[String] = []
	var carries: Array[String] = []
	for c in SpellGrammar.COLORS:
		if drain.has(c):
			drains.append("%s %s/s" % [c, snappedf(drain[c], 0.01)])
		if carry.has(c):
			carries.append("%s %d" % [c, carry[c]])
	var text := "drains " + ", ".join(drains) + " per target"
	if not carries.is_empty():
		text += " · carries " + ", ".join(carries) + " for the spells it creates"
	return text


static func _default_for(verb: String) -> Dictionary:
	match verb:
		"create":
			return {"verb": "create", "what": {"material": "wood"}}
		"destroy":
			return {"verb": "destroy", "what": {"closest": "fire"}}
		"move":
			return {"verb": "move", "what": {"closest": "stone"}, "to": {"closest": "player"}}
		"mark":
			return {"verb": "mark", "what": {"ref": "this"}}
		"alternate":
			return Sandbox.JUGGLE.duplicate(true)
	return {"verb": "select", "what": {"closest": "player"}}
