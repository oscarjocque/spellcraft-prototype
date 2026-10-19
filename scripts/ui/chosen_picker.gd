class_name ChosenPicker
extends PanelContainer
## The window that asks which attached spell a Chosen in the spell being cast
## means. Main opens it once for each Chosen, in reading order.

signal picked(id: int)  # a spell's id, 0 for nothing
signal cancelled

var _title: Label
var _options: VBoxContainer


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("15171c")
	style.border_color = Color("ffd34d")
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", style)
	custom_minimum_size = Vector2(420, 0)
	var box := VBoxContainer.new()
	add_child(box)
	_title = Label.new()
	box.add_child(_title)
	_options = VBoxContainer.new()
	box.add_child(_options)


## Shows the choice for Chosen `index` (1-based) of `total` in `spell_text`.
func ask(spell_text: String, index: int, total: int, attached: Array[WorldObject]) -> void:
	_title.text = "%s\nChosen %d of %d: which attached spell?" % [spell_text, index, total]
	for c in _options.get_children():
		_options.remove_child(c)
		c.queue_free()
	var n := 1
	for o in attached:
		_add_option("%d  %s" % [n, SpellGrammar.to_text(o.spell.ast)], func() -> void: _pick(o.id))
		n += 1
	if attached.is_empty():
		var none := Label.new()
		none.text = "You have no attached spells."
		none.add_theme_color_override("font_color", Color("a0a4ab"))
		_options.add_child(none)
	_add_option("Nothing (the spell waits)", func() -> void: _pick(0))
	_add_option("Cancel the cast (Esc)", _cancel)
	move_to_front()
	show()
	_recenter.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_cancel()


func _add_option(text: String, on_press: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(on_press)
	_options.add_child(b)


func _pick(id: int) -> void:
	hide()
	picked.emit(id)


func _cancel() -> void:
	hide()
	cancelled.emit()


func _recenter() -> void:
	reset_size()
	position = ((get_viewport_rect().size - size) / 2).max(Vector2.ZERO)
