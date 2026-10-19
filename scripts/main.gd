extends Node2D
## Runs the simulation on a fixed tick and feeds it local input. The view and
## HUD only read simulation state; input reaches the simulation only as
## commands, the way it would over a network.

@onready var view: WorldView = $WorldView
@onready var hud: Hud = $Hud
@onready var editor: SpellEditor = $Hud/SpellEditor
@onready var picker: ChosenPicker = $Hud/ChosenPicker
@onready var quick: QuickCast = $Hud/QuickCast

var sim: Simulation
var player: WorldObject
var slots: Array = Sandbox.PRESETS.duplicate(true)
var selected := 0  # the slot cast last, highlighted in the HUD
var _accum := 0.0
var _pending_casts := []  # {"ast", "aim"} to send, one per tick, oldest first
var _casting := {}  # a cast waiting on picks: {"ast", "aim", "nouns", "index"}
var _dropping := false  # the picker is choosing a spell to drop
var _pending_drop := 0  # id of a spell to drop with the next tick's command


func _ready() -> void:
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("move_up", [KEY_W, KEY_UP])
	_bind("move_down", [KEY_S, KEY_DOWN])
	quick.cast.connect(func(ast: Dictionary) -> void: _cast(ast, view.get_global_mouse_position(), -1))
	quick.saved.connect(func(slot: int, ast: Dictionary) -> void:
		slots[slot] = ast
		sim.say("Saved to spell %d: %s" % [(slot + 1) % 10, SpellGrammar.to_text(ast)]))
	picker.picked.connect(func(id: int) -> void:
		if _dropping:
			_dropping = false
			_pending_drop = id
		else:
			_on_picked(id))
	picker.cancelled.connect(func() -> void:
		if _dropping:
			_dropping = false
		else:
			_cancel_cast())
	_reset()


func _reset() -> void:
	sim = Simulation.new()
	player = Sandbox.build(sim)
	view.sim = sim
	_accum = 0.0
	_pending_casts.clear()
	_casting = {}
	_dropping = false
	_pending_drop = 0
	picker.hide()
	quick.close()


func _process(delta: float) -> void:
	# The simulation pauses while the editor is open, but not while picking.
	if not editor.visible:
		_accum = minf(_accum + delta, 0.25)
		while _accum >= Simulation.DT:
			_accum -= Simulation.DT
			sim.step({player.controller: _command()})
	view.alpha = _accum / Simulation.DT
	hud.refresh(sim, player, slots, selected, _prompt())
	view.preview = {}
	if quick.visible and quick.input.result.has("ast"):
		var ast: Dictionary = quick.input.result["ast"]
		view.preview = SpellPreview.targets(sim, player, ast, view.get_global_mouse_position())
		view.preview_verb = ast["verb"]
		quick.set_status(SpellPreview.describe(ast, view.preview))
	elif quick.visible:
		quick.set_status("")
	hud.visible_parts(not editor.visible)


func _command() -> Dictionary:
	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	var cmd := {
		"move": Vector2.ZERO if typing else Input.get_vector("move_left", "move_right", "move_up", "move_down"),
		"aim": view.get_global_mouse_position(),
	}
	if not _pending_casts.is_empty():
		var next: Dictionary = _pending_casts.pop_front()
		cmd["cast"] = next["ast"]
		cmd["aim"] = next["aim"]
	if _pending_drop != 0:
		cmd["drop"] = _pending_drop
		_pending_drop = 0
	return cmd


## Casts the selected slot toward `aim`, first having the player pick, one
## after another and while the game runs, what each Chosen, This and There
## in it means: Chosen from a window, This and There by clicking the world.
func _begin_cast(aim: Vector2) -> void:
	_cast(slots[selected], aim, selected)


## Casts `spell` (from slot `slot`, or -1 if typed) toward `aim`, after its picks.
func _cast(spell: Dictionary, aim: Vector2, slot: int) -> void:
	if not _casting.is_empty():
		return
	# The spells of the slots an Alternate uses are copied in now, as they are.
	var ast := SpellGrammar.embed_slots(spell, slots, [slot] if slot >= 0 else [])
	var nouns := SpellGrammar.cast_picks(ast)
	_casting = {"ast": ast, "aim": aim, "nouns": nouns, "index": 0}
	# The first pick can come from where the mouse already is: This is the
	# object under it, There the spot. The rest are asked for.
	if not nouns.is_empty():
		var first: String = nouns[0]["ref"]
		var under := _object_at(aim)
		if first == "there":
			_on_picked(aim)
			return
		if first == "this" and under != null:
			_on_picked(under.id)
			return
	if nouns.is_empty():
		_pending_casts.append({"ast": ast, "aim": aim})
		_casting = {}
		return
	_ask_next()


func _picking() -> String:
	if _casting.is_empty():
		return ""
	return _casting["nouns"][_casting["index"]]["ref"]


func _ask_next() -> void:
	if _picking() == "chosen":
		var nouns: Array = _casting["nouns"]
		picker.ask(SpellGrammar.to_text(_casting["ast"]), _casting["index"] + 1, nouns.size(), sim.inventory(player))


## What the HUD should ask for, if anything.
func _prompt() -> String:
	var what := _picking()
	if what == "" or what == "chosen":
		return ""
	var nouns: Array = _casting["nouns"]
	return "%s\nClick %s for %s (%d of %d) · Esc cancels" % [
		SpellGrammar.to_text(_casting["ast"]), "an object" if what == "this" else "a place",
		what.capitalize(), _casting["index"] + 1, nouns.size()]


## Fills in the current pick ("id" for Chosen and This, "at" for There) and
## moves on to the next, casting once all are picked.
func _on_picked(value: Variant) -> void:
	var noun: Dictionary = _casting["nouns"][_casting["index"]]
	if noun["ref"] == "there":
		noun["at"] = value
	else:
		noun["id"] = value
	_casting["index"] += 1
	if _casting["index"] < _casting["nouns"].size():
		_ask_next()
	else:
		_pending_casts.append({"ast": _casting["ast"], "aim": _casting["aim"]})
		_casting = {}


func _cancel_cast() -> void:
	_casting = {}
	picker.hide()


## The Thing or mana under `at` (spells are picked with Chosen), or null.
func _object_at(at: Vector2) -> WorldObject:
	var best: WorldObject = null
	for o in sim.objects:
		if not o.dead and o.spell == null and not o.has_tag("place") and at.distance_to(o.pos) <= o.radius + 4.0 \
				and (best == null or at.distance_to(o.pos) < at.distance_to(best.pos)):
			best = o
	return best


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return  # typing: Tab completes, Enter submits
	# Handled here, before the editor's controls can take Tab for focus.
	if event.keycode == KEY_TAB and not picker.visible:
		if editor.visible:
			editor.hide()
		else:
			editor.open(slots, selected)
		get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not editor.visible and not picker.visible \
			and _casting.is_empty():
		quick.open()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if editor.visible:
		return
	if _picking() in ["this", "there"]:
		_handle_world_pick(event)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var slot: int = 9 if event.keycode == KEY_0 else event.keycode - KEY_1
		if slot >= 0 and slot < mini(slots.size(), 10):
			# A number key casts its slot toward the mouse right away.
			if _casting.is_empty() and not picker.visible:
				selected = slot
				_begin_cast(view.get_global_mouse_position())
		elif event.keycode == KEY_SPACE and _casting.is_empty() and not picker.visible:
			_dropping = true
			picker.ask_drop(sim.inventory(player))
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R:
			_reset()


## While picking This or There: a click picks, Esc cancels the cast.
func _handle_world_pick(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_cast()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var at := view.get_global_mouse_position()
		if _picking() == "there":
			_on_picked(at)
			return
		var o := _object_at(at)
		if o != null:
			_on_picked(o.id)


static func _bind(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
