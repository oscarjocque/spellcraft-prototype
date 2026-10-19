class_name SpellEditor
extends PanelContainer
## Edits the spell slots. Like Scratch's slots, each picker only offers blocks
## that fit grammatically, so an incomplete spell can't be built.
##
## A placeholder for a drag-and-drop block editor.

var slots: Array = []  # shared with Main; edited in place

var _rows: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(760, 0)
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
		c.queue_free()
	for i in slots.size():
		var row := HBoxContainer.new()
		_rows.add_child(row)
		_fill_row(row, i)
	show()
	position = (get_viewport_rect().size - get_combined_minimum_size()) / 2


func _fill_row(row: HBoxContainer, i: int) -> void:
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()
	var ast: Dictionary = slots[i]
	var label := Label.new()
	label.text = "%d" % (i + 1)
	label.custom_minimum_size.x = 20
	row.add_child(label)

	var verbs := ["Create", "Destroy", "Move", "Closest (independent)"]
	var verb := _picker(verbs, SpellGrammar.VERBS.find(ast["verb"]))
	verb.item_selected.connect(func(idx: int) -> void:
		slots[i] = _default_for(SpellGrammar.VERBS[idx])
		_fill_row(row, i))
	row.add_child(verb)

	match ast["verb"]:
		"create":
			var what: Dictionary = ast["what"]
			row.add_child(_word_picker(SpellGrammar.MATERIALS, what, "material", row, i))
		"destroy":
			_add_noun(row, ast["what"], i)
		"move":
			_add_noun(row, ast["what"], i)
			var to := Label.new()
			to.text = "to"
			row.add_child(to)
			_add_noun(row, ast["to"], i)
		"select":
			row.add_child(_word_picker(SpellGrammar.QUALIFIERS, ast, "qualifier", row, i))

	var summary := Label.new()
	var words := SpellGrammar.blocks(ast).size()
	summary.text = "  %d/%d words · %s" % [words, SpellGrammar.SLOT_LIMIT, _cost_text(ast)]
	row.add_child(summary)


## A noun slot: Me, It, or Closest followed by a qualifier.
func _add_noun(row: HBoxContainer, noun: Dictionary, i: int) -> void:
	var kinds := ["Me", "It", "Closest"]
	var current := 2 if noun.has("closest") else SpellGrammar.REFS.find(noun["ref"])
	var kind := _picker(kinds, current)
	kind.item_selected.connect(func(idx: int) -> void:
		noun.clear()
		if idx == 2:
			noun["closest"] = "fire"
		else:
			noun["ref"] = SpellGrammar.REFS[idx]
		_fill_row(row, i))
	row.add_child(kind)
	if noun.has("closest"):
		row.add_child(_word_picker(SpellGrammar.QUALIFIERS, noun, "closest", row, i))


func _word_picker(words: Array, target: Dictionary, key: String, row: HBoxContainer, i: int) -> OptionButton:
	var names: Array = words.map(func(w: String) -> String: return w.capitalize())
	var picker := _picker(names, words.find(target[key]))
	picker.item_selected.connect(func(idx: int) -> void:
		target[key] = words[idx]
		_fill_row(row, i))
	return picker


func _picker(items: Array, selected: int) -> OptionButton:
	var b := OptionButton.new()
	for item in items:
		b.add_item(item)
	b.select(selected)
	return b


func _cost_text(ast: Dictionary) -> String:
	var parts: Array[String] = []
	var drain := SpellGrammar.drain_per_second(ast)
	for c in SpellGrammar.COLORS:
		if drain.has(c):
			parts.append("%s %d/s" % [c, drain[c]])
	return ", ".join(parts)


static func _default_for(verb: String) -> Dictionary:
	match verb:
		"create":
			return {"verb": "create", "what": {"material": "wood"}}
		"destroy":
			return {"verb": "destroy", "what": {"closest": "fire"}}
		"move":
			return {"verb": "move", "what": {"closest": "stone"}, "to": {"closest": "player"}}
	return {"verb": "select", "qualifier": "player"}
