class_name QuickCast
extends PanelContainer
## The quick-cast bar: Enter opens it, type a spell, Enter casts it toward the
## mouse (or click where to cast it). Ctrl+1–0 saves it to that slot instead,
## Up/Down go through spells typed before, Esc closes.

signal cast(ast: Dictionary)
signal saved(slot: int, ast: Dictionary)

var input: SpellInput
var _status: Label
var _history: Array[String] = []
var _history_at := 0


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.94)
	style.border_color = Color("ffd34d")
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "Enter or click: cast  ·  Shift keeps it open  ·  Ctrl+1–0 save  ·  ↑↓ earlier  ·  Esc close"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color("8a8f98"))
	box.add_child(title)
	input = SpellInput.new()
	box.add_child(input)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color("ffb02e"))
	box.add_child(_status)
	input.submitted.connect(_on_submitted)
	input.field.gui_input.connect(_on_key)
	minimum_size_changed.connect(_place)  # stays in the corner as it grows
	hide()


## A note under the preview, e.g. what the spell would act on now.
func set_status(text: String) -> void:
	_status.text = text
	_status.visible = text != ""


func open() -> void:
	input.set_text("")
	_history_at = _history.size()
	show()
	move_to_front()
	_place()
	input.field.grab_focus()


func close() -> void:
	hide()
	input.field.release_focus()


## Bottom right, clear of the slot list on the left.
func _place() -> void:
	reset_size()
	position = get_viewport_rect().size - size - Vector2(12, 12)


func _remember(text: String) -> void:
	_history.erase(text)
	_history.append(text)


## Casts what's typed, if it reads as a spell (a click on the world).
func submit() -> void:
	if input.result.has("ast"):
		_cast_typed(input.result["ast"], true)


func _on_submitted(ast: Dictionary) -> void:
	_cast_typed(ast, false)


## Shift keeps the bar open: after Enter, empty for the next spell; after a
## click, with the same spell, to click it onto more things.
func _cast_typed(ast: Dictionary, clicked: bool) -> void:
	_remember(input.field.text.strip_edges())
	if Input.is_key_pressed(KEY_SHIFT):
		if not clicked:
			input.set_text("")
		input.field.grab_focus.call_deferred()
	else:
		close()
	cast.emit(ast)


func _on_key(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var key: int = event.keycode
	if key == KEY_ESCAPE:
		close()
	elif key == KEY_UP or key == KEY_DOWN:
		if _history.is_empty():
			return
		_history_at = clampi(_history_at + (-1 if key == KEY_UP else 1), 0, _history.size())
		input.set_text(_history[_history_at] if _history_at < _history.size() else "")
	elif event.ctrl_pressed and key >= KEY_0 and key <= KEY_9:
		if input.result.has("ast"):
			_remember(input.field.text.strip_edges())
			saved.emit(9 if key == KEY_0 else key - KEY_1, input.result["ast"])
			close()
	else:
		return
	input.field.accept_event()
