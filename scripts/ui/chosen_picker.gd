class_name ChosenPicker
extends PanelContainer
## The window that asks the player to pick one of their attached spells: for
## a Chosen in the spell being cast (once for each, in reading order), or a
## spell to drop. The game keeps running meanwhile.
##
## Spells keep the numbers they have in the HUD's list of attached spells,
## and their number key picks them; 0 picks Nothing where that's allowed.
## At most five entries show at a time, with "More" for the rest. Esc cancels.

signal picked(id: int)  # a spell's id, 0 for nothing
signal cancelled

const PAGE := 5

var _title: Label
var _options: VBoxContainer
var _entries := []  # [key, bbcode, action]
var _page := 0


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.96)
	style.border_color = Color("ffd34d")
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", style)
	custom_minimum_size = Vector2(480, 0)
	var box := VBoxContainer.new()
	add_child(box)
	_title = Label.new()
	box.add_child(_title)
	_options = VBoxContainer.new()
	box.add_child(_options)
	var hint := Label.new()
	hint.text = "number keys pick   ·   Esc cancels"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color("8a8f98"))
	box.add_child(hint)


## Shows the choice for Chosen `index` (1-based) of `total` in `spell_text`.
func ask(spell_text: String, index: int, total: int, attached: Array[WorldObject]) -> void:
	_open("%s\nChosen %d of %d: which attached spell?" % [spell_text, index, total], attached, true)


## Shows the choice of an attached spell to drop.
func ask_drop(attached: Array[WorldObject]) -> void:
	_open("Drop which spell? It stays where it is and stops following you.", attached, false)


func _open(title: String, attached: Array[WorldObject], nothing: bool) -> void:
	_title.text = title
	_entries.clear()
	for i in attached.size():
		var o := attached[i]
		_entries.append([i + 1, SpellText.bbcode(o.spell.ast), _pick.bind(o.id)])
	if nothing:
		_entries.append([0, "[color=#a7abb3]Nothing (the spell waits)[/color]", _pick.bind(0)])
	_page = 0
	_show_page()
	move_to_front()
	show()
	_recenter.call_deferred()


func _show_page() -> void:
	for c in _options.get_children():
		_options.remove_child(c)
		c.queue_free()
	if _entries.is_empty():
		var none := Label.new()
		none.text = "You have no attached spells."
		none.add_theme_color_override("font_color", Color("a7abb3"))
		_options.add_child(none)
		return
	var paged := _entries.size() > PAGE
	var per_page := PAGE - 1 if paged else PAGE
	var start := _page * per_page
	for e in _entries.slice(start, start + per_page):
		_add_option("[b]%d[/b]   %s" % [e[0], e[1]], e[2])
	if paged:
		var pages := ceili(float(_entries.size()) / per_page)
		_add_option("[color=#a7abb3]More ▸   (page %d of %d)[/color]" % [_page + 1, pages], func() -> void:
			_page = (_page + 1) % pages
			_show_page())


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: int = event.keycode
	if key == KEY_ESCAPE:
		_cancel()
	elif key >= KEY_0 and key <= KEY_9:
		for e in _entries:
			if e[0] == key - KEY_0:
				e[2].call()
				break
	else:
		return
	get_viewport().set_input_as_handled()


func _add_option(bbcode: String, on_press: Callable) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(456, 32)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 10
	label.offset_top = 5
	label.text = bbcode
	b.add_child(label)
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
