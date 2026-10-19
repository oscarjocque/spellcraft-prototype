class_name SpellEditor
extends PanelContainer
## Edits the spell slots. Like Scratch's slots, each picker only offers blocks
## that fit grammatically, so an incomplete spell can't be built. Choosing
## Spell as Create's object opens a nested sentence for the spell to create.
##
## A placeholder for a drag-and-drop block editor.

var slots: Array = []  # shared with Main; edited in place

var _rows: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(760, 0)
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
	_rows = VBoxContainer.new()
	box.add_child(_rows)


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


## One slot: the sentence's pickers, with its word count and cost below.
func _fill_slot(slot: VBoxContainer, i: int) -> void:
	for c in slot.get_children():
		slot.remove_child(c)
		c.queue_free()
	var ast: Dictionary = slots[i]
	var row := HBoxContainer.new()
	slot.add_child(row)
	var label := _text("%d" % (i + 1))
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
	if is_visible_in_tree():
		_recenter.call_deferred()


## The pickers for one sentence. Edits `ast` in place, so the same code edits a
## slot's spell and any spell nested inside it by Create Spell.
func _add_spell(row: HBoxContainer, ast: Dictionary, refresh: Callable) -> void:
	var verbs := ["Create", "Destroy", "Move", "Closest (independent)"]
	var verb := _picker(verbs, SpellGrammar.VERBS.find(ast["verb"]))
	verb.item_selected.connect(func(idx: int) -> void:
		ast.clear()
		ast.merge(_default_for(SpellGrammar.VERBS[idx]))
		refresh.call())
	row.add_child(verb)

	match ast["verb"]:
		"create":
			_add_creation(row, ast["what"], refresh)
		"destroy":
			_add_noun(row, ast["what"], refresh)
		"move":
			_add_noun(row, ast["what"], refresh)
			row.add_child(_text("to"))
			_add_noun(row, ast["to"], refresh)
		"select":
			row.add_child(_word_picker(SpellGrammar.QUALIFIERS, ast, "qualifier", refresh))


## Create's object: a material, or Spell followed by that spell's description.
func _add_creation(row: HBoxContainer, what: Dictionary, refresh: Callable) -> void:
	var kinds: Array = SpellGrammar.MATERIALS + ["spell"]
	var names: Array = kinds.map(func(w: String) -> String: return w.capitalize())
	var kind := _picker(names, kinds.find("spell" if what.has("spell") else what["material"]))
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


## A noun slot: Me, It, or Closest followed by a qualifier.
func _add_noun(row: HBoxContainer, noun: Dictionary, refresh: Callable) -> void:
	var kinds := ["Me", "It", "Closest"]
	var current := 2 if noun.has("closest") else SpellGrammar.REFS.find(noun["ref"])
	var kind := _picker(kinds, current)
	kind.item_selected.connect(func(idx: int) -> void:
		noun.clear()
		if idx == 2:
			noun["closest"] = "fire"
		else:
			noun["ref"] = SpellGrammar.REFS[idx]
		refresh.call())
	row.add_child(kind)
	if noun.has("closest"):
		row.add_child(_word_picker(SpellGrammar.QUALIFIERS, noun, "closest", refresh))


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
	var text := "drains " + ", ".join(drains)
	if not carries.is_empty():
		text += " · carries " + ", ".join(carries) + " for the spell it creates"
	return text


static func _default_for(verb: String) -> Dictionary:
	match verb:
		"create":
			return {"verb": "create", "what": {"material": "wood"}}
		"destroy":
			return {"verb": "destroy", "what": {"closest": "fire"}}
		"move":
			return {"verb": "move", "what": {"closest": "stone"}, "to": {"closest": "player"}}
	return {"verb": "select", "qualifier": "player"}
