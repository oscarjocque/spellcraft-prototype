extends Node2D
## Runs the simulation on a fixed tick and feeds it local input. The view and
## HUD only read simulation state; input reaches the simulation only as
## commands, the way it would over a network.

@onready var view: WorldView = $WorldView
@onready var hud: Hud = $Hud
@onready var editor: SpellEditor = $Hud/SpellEditor
@onready var picker: ChosenPicker = $Hud/ChosenPicker

var sim: Simulation
var player: WorldObject
var slots: Array = Sandbox.PRESETS.duplicate(true)
var selected := 0
var _accum := 0.0
var _pending_cast := {}  # {"ast", "aim"} to send with the next tick's command
var _casting := {}  # a cast waiting on Chosen picks: {"ast", "aim", "nouns", "index"}


func _ready() -> void:
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("move_up", [KEY_W, KEY_UP])
	_bind("move_down", [KEY_S, KEY_DOWN])
	picker.picked.connect(_on_chosen_picked)
	picker.cancelled.connect(func() -> void: _casting = {})
	_reset()


func _reset() -> void:
	sim = Simulation.new()
	player = Sandbox.build(sim)
	view.sim = sim
	_accum = 0.0
	_pending_cast = {}
	_casting = {}
	picker.hide()


func _process(delta: float) -> void:
	# The simulation pauses while the editor or a Chosen pick is open.
	if not editor.visible and not picker.visible:
		_accum = minf(_accum + delta, 0.25)
		while _accum >= Simulation.DT:
			_accum -= Simulation.DT
			sim.step({player.controller: _command()})
	view.alpha = _accum / Simulation.DT
	hud.refresh(sim, player, slots, selected)


func _command() -> Dictionary:
	var cmd := {
		"move": Input.get_vector("move_left", "move_right", "move_up", "move_down"),
		"aim": view.get_global_mouse_position(),
	}
	if not _pending_cast.is_empty():
		cmd["cast"] = _pending_cast["ast"]
		cmd["aim"] = _pending_cast["aim"]
		_pending_cast = {}
	return cmd


## Casts the selected slot toward `aim`, first asking, in a window for each
## Chosen in it, which attached spell that Chosen means.
func _begin_cast(aim: Vector2) -> void:
	var ast: Dictionary = slots[selected].duplicate(true)
	var nouns := SpellGrammar.chosen_nouns(ast)
	if nouns.is_empty():
		_pending_cast = {"ast": ast, "aim": aim}
		return
	_casting = {"ast": ast, "aim": aim, "nouns": nouns, "index": 0}
	_ask_chosen()


func _ask_chosen() -> void:
	var nouns: Array = _casting["nouns"]
	picker.ask(SpellGrammar.to_text(_casting["ast"]), _casting["index"] + 1, nouns.size(), sim.inventory(player))


func _on_chosen_picked(id: int) -> void:
	var nouns: Array = _casting["nouns"]
	nouns[_casting["index"]]["id"] = id
	_casting["index"] += 1
	if _casting["index"] < nouns.size():
		_ask_chosen()
	else:
		_pending_cast = {"ast": _casting["ast"], "aim": _casting["aim"]}
		_casting = {}


func _input(event: InputEvent) -> void:
	# Handled here, before the editor's controls can take Tab for focus.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB \
			and not picker.visible:
		if editor.visible:
			editor.hide()
		else:
			editor.open(slots)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if editor.visible or picker.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode < KEY_1 + slots.size():
			selected = event.keycode - KEY_1
		elif event.keycode == KEY_R:
			_reset()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_begin_cast(view.get_global_mouse_position())


static func _bind(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
