class_name SpellEditor
extends PanelContainer
## The spellbook: the ten spell slots on the left, the chosen one on the
## right. A spell is edited by typing it (as in the quick-cast bar) or by
## clicking its words; either way the slot changes as soon as it reads as a
## spell. Number keys choose a slot while nothing is being typed.

signal reset_requested  # the player asked for the preset spells back

var slots: Array = []  # shared with Main; edited in place

var _rows: VBoxContainer
var _title: Label
var _input: SpellInput
var _chips: SpellChips
var _summary: RichTextLabel
var _selected := 0


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("15171c")
	style.border_color = Color("2c3038")
	style.set_border_width_all(1)
	style.set_content_margin_all(14)
	style.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", style)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	add_child(page)
	var header := Label.new()
	header.text = "Spellbook   ·   1–0 choose a spell   ·   type it, or click its words   ·   Tab close (the game is paused)"
	header.add_theme_color_override("font_color", Color("8a8f98"))
	page.add_child(header)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	page.add_child(body)

	_rows = VBoxContainer.new()
	_rows.custom_minimum_size.x = 420
	_rows.add_theme_constant_override("separation", 2)
	body.add_child(_rows)

	var detail := VBoxContainer.new()
	detail.custom_minimum_size = Vector2(620, 0)
	detail.add_theme_constant_override("separation", 12)
	body.add_child(detail)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	detail.add_child(_title)
	_input = SpellInput.new()
	_input.compact = true
	detail.add_child(_input)
	_input.field.select_all_on_focus = true  # typing replaces the spell
	_input.field.focus_exited.connect(func() -> void:
		# Leaving half a spell behind puts the slot's text back.
		if not _input.result.has("ast"):
			_input.set_text(SpellGrammar.to_text(slots[_selected])))
	_input.changed.connect(_on_typed)
	_input.submitted.connect(func(_ast: Dictionary) -> void: _input.field.release_focus())
	_chips = SpellChips.new()
	_chips.custom_minimum_size.x = 620
	detail.add_child(_chips)
	_chips.edited.connect(_on_clicked_edit)
	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.fit_content = true
	_summary.scroll_active = false
	_summary.custom_minimum_size.x = 620
	detail.add_child(_summary)
	var tip := Label.new()
	tip.text = "Click a word to change it; + adds optional parts. Colors show which mana each word costs."
	tip.add_theme_font_size_override("font_size", 12)
	tip.add_theme_color_override("font_color", Color("8a8f98"))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD
	tip.custom_minimum_size.x = 620
	detail.add_child(tip)
	var reset := Button.new()
	reset.text = "Reset all ten to the presets"
	reset.flat = true
	reset.focus_mode = Control.FOCUS_NONE
	reset.add_theme_font_size_override("font_size", 12)
	reset.add_theme_color_override("font_color", Color("8a8f98"))
	reset.size_flags_horizontal = Control.SIZE_SHRINK_END
	reset.pressed.connect(func() -> void: reset_requested.emit())
	detail.add_child(reset)


func open(p_slots: Array, slot := 0) -> void:
	slots = p_slots
	_build_rows()
	_select(slot)
	move_to_front()  # above the HUD's labels
	show()
	_recenter.call_deferred()


## Containers grow but never shrink on their own, so fit to the content again.
func _recenter() -> void:
	reset_size()
	position = ((get_viewport_rect().size - size) / 2).max(Vector2.ZERO)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: int = event.keycode
	if key >= KEY_0 and key <= KEY_9:
		_select(9 if key == KEY_0 else key - KEY_1)
		get_viewport().set_input_as_handled()
	elif key == KEY_ENTER or key == KEY_KP_ENTER:
		_input.field.grab_focus()
		get_viewport().set_input_as_handled()


func _build_rows() -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var group := ButtonGroup.new()
	for i in slots.size():
		var row := Button.new()
		row.toggle_mode = true
		row.button_group = group
		row.focus_mode = Control.FOCUS_NONE
		row.custom_minimum_size = Vector2(420, 34)
		row.pressed.connect(_select.bind(i))
		var label := RichTextLabel.new()
		label.bbcode_enabled = true
		label.scroll_active = false
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.offset_left = 10
		label.offset_top = 6
		row.add_child(label)
		_rows.add_child(row)
	_refresh_rows()


func _refresh_rows() -> void:
	for i in _rows.get_child_count():
		var row: Button = _rows.get_child(i)
		row.set_pressed_no_signal(i == _selected)
		var label: RichTextLabel = row.get_child(0)
		label.text = "[b]%d[/b]   %s" % [(i + 1) % 10, SpellText.bbcode(slots[i])]


func _select(i: int) -> void:
	if i < 0 or i >= slots.size():
		return
	_selected = i
	_title.text = "Spell %d   (press %d in the game to cast it)" % [(i + 1) % 10, (i + 1) % 10]
	_show_selected(true)


## Shows the selected slot's spell; `retype` also puts its text in the box.
func _show_selected(retype: bool) -> void:
	var ast: Dictionary = slots[_selected]
	if retype:
		_input.set_text(SpellGrammar.to_text(ast))
	_chips.show_spell(ast)
	_refresh_rows()
	var full := SpellGrammar.embed_slots(ast, slots, [_selected])  # as it would be cast
	var err := SpellGrammar.validate(full)
	if err != "":
		_summary.text = "[color=#ff8a8a]%s[/color]" % err
	else:
		_summary.text = "[color=#8a8f98]%d words · costs[/color]  %s" % [SpellGrammar.blocks(full).size(), SpellText.cost(full)]


## Typing: once the text reads as a spell, it becomes the slot's spell.
func _on_typed(result: Dictionary) -> void:
	if not visible or not result.has("ast") or result["ast"] == slots[_selected]:
		return
	var ast: Dictionary = slots[_selected]
	ast.clear()
	ast.merge(result["ast"])
	_show_selected(false)


## Clicking words changed the spell: show it as text too.
func _on_clicked_edit() -> void:
	_show_selected(true)
