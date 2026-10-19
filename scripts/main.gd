extends Node2D
## Runs the simulation on a fixed tick and feeds it local input. The view and
## HUD only read simulation state; input reaches the simulation only as
## commands, the way it would over a network.

@onready var view: WorldView = $WorldView
@onready var hud: Hud = $Hud
@onready var editor: SpellEditor = $Hud/SpellEditor

var sim: Simulation
var player: WorldObject
var slots: Array = Sandbox.PRESETS.duplicate(true)
var selected := 0
var _accum := 0.0
var _pending_cast := {}


func _ready() -> void:
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("move_up", [KEY_W, KEY_UP])
	_bind("move_down", [KEY_S, KEY_DOWN])
	_reset()


func _reset() -> void:
	sim = Simulation.new()
	player = Sandbox.build(sim)
	view.sim = sim
	_accum = 0.0
	_pending_cast = {}


func _process(delta: float) -> void:
	if not editor.visible:
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
		cmd["cast"] = _pending_cast
		_pending_cast = {}
	return cmd


func _input(event: InputEvent) -> void:
	# Handled here, before the editor's controls can take Tab for focus.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		if editor.visible:
			editor.hide()
		else:
			editor.open(slots)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if editor.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode < KEY_1 + slots.size():
			selected = event.keycode - KEY_1
		elif event.keycode == KEY_R:
			_reset()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pending_cast = slots[selected].duplicate(true)


static func _bind(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
