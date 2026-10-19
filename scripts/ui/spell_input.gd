class_name SpellInput
extends VBoxContainer
## Type a spell: a line to type in, up to five suggestions for the next word
## (Tab takes the first, and the rest of it shows faintly after a word being
## typed), and a preview of the spell as understood, or why it isn't one yet.

signal changed(result: Dictionary)  # SpellParser.parse's result, on every edit
signal submitted(ast: Dictionary)  # Enter, on a spell that reads

const HINT_COLOR := Color("8a8f98")

var field: LineEdit
var result := {}  # the latest parse: {"ast"} or {"error"}
## Only preview what the text reads as when that differs from the text itself,
## and leave the cost out (for where the spell is shown with its cost already).
var compact := false

var _hints: HBoxContainer
var _preview: RichTextLabel
var _ghost := ""  # the rest of the word Tab would complete


func _ready() -> void:
	field = LineEdit.new()
	field.placeholder_text = "type a spell, e.g.  move closest stone to me   (short words work: mo cl st to me)"
	field.custom_minimum_size.x = 520
	field.caret_blink = true
	field.text_changed.connect(_on_text_changed)
	field.text_submitted.connect(func(_text: String) -> void: _submit())
	field.gui_input.connect(_on_field_input)
	field.draw.connect(_draw_ghost)
	add_child(field)
	_hints = HBoxContainer.new()
	add_child(_hints)
	_preview = RichTextLabel.new()
	_preview.bbcode_enabled = true
	_preview.fit_content = true
	_preview.scroll_active = false
	_preview.custom_minimum_size.x = 520
	add_child(_preview)
	_on_text_changed("")


## Shows `text` as if typed.
func set_text(text: String) -> void:
	field.text = text
	field.caret_column = text.length()
	_on_text_changed(text)


func _on_text_changed(text: String) -> void:
	result = SpellParser.parse(text) if text.strip_edges() != "" else {}
	if result.has("ast"):
		var reads_as := SpellGrammar.to_text(result["ast"])
		if compact and reads_as.to_lower() == text.strip_edges().to_lower():
			_preview.text = ""
		elif compact:
			_preview.text = "[color=#8a8f98]reads as[/color]  " + SpellText.bbcode(result["ast"])
		else:
			_preview.text = SpellText.bbcode(result["ast"]) + "\n[font_size=12]" + SpellText.cost(result["ast"]) + "[/font_size]"
	elif result.has("error"):
		var color := HINT_COLOR.to_html(false) if result.get("unfinished", false) else "ff8a8a"
		_preview.text = "[color=#%s]%s[/color]" % [color, result["error"]]
	elif not compact:
		_preview.text = "[color=#%s]Tab completes · Enter casts[/color]" % HINT_COLOR.to_html(false)
	else:
		_preview.text = ""
	var words := SpellParser.suggest(text)
	_show_hints(words)
	var partial := text.substr(maxi(text.rfind(" "), maxi(text.rfind("("), text.rfind("["))) + 1)
	_ghost = ""
	if partial != "" and not words.is_empty() and words[0].begins_with(partial.to_lower()):
		_ghost = words[0].substr(partial.length())
	field.queue_redraw()
	changed.emit(result)


func _show_hints(words: Array[String]) -> void:
	for c in _hints.get_children():
		_hints.remove_child(c)
		c.queue_free()
	for i in words.size():
		var b := Button.new()
		b.text = ("Tab: " if i == 0 else "") + words[i]
		b.flat = i > 0
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		var word := words[i]
		b.pressed.connect(func() -> void: _accept(word))
		_hints.add_child(b)


## The rest of the word Tab would complete, faintly, right after the caret.
func _draw_ghost() -> void:
	if _ghost == "" or field.caret_column != field.text.length():
		return
	var font := field.get_theme_font("font")
	var font_size := field.get_theme_font_size("font_size")
	var left := field.get_theme_stylebox("normal").get_margin(SIDE_LEFT)
	var x := left + font.get_string_size(field.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x - field.get_scroll_offset()
	var y := (field.size.y - font.get_height(font_size)) / 2 + font.get_ascent(font_size)
	field.draw_string(font, Vector2(x, y), _ghost, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(HINT_COLOR, 0.8))


## Puts `word` in place of the word being typed (or after the last one).
func _accept(word: String) -> void:
	var text := field.text
	var cut := text.length()
	if not text.ends_with(" "):
		cut = maxi(text.rfind(" "), maxi(text.rfind("("), text.rfind("["))) + 1
	set_text(text.substr(0, cut) + word + " ")
	field.grab_focus()


func _on_field_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_TAB:
		var words := SpellParser.suggest(field.text)
		if not words.is_empty():
			_accept(words[0])
		field.accept_event()
	elif event.keycode == KEY_ESCAPE:
		field.release_focus()


func _submit() -> void:
	if result.has("ast"):
		submitted.emit(result["ast"])
