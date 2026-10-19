extends Node2D
## Runs the simulation on a fixed tick and feeds it local input. The view and
## HUD only read simulation state; input reaches the simulation only as
## commands, the way it would over a network.

@onready var view: WorldView = $WorldView
@onready var hud: Hud = $Hud
@onready var editor: SpellEditor = $Hud/SpellEditor
@onready var picker: ChosenPicker = $Hud/ChosenPicker
@onready var quick: QuickCast = $Hud/QuickCast
@onready var words: WordSheet = $Hud/WordSheet

var sim: Simulation
var player: WorldObject
var slots: Array = Spellbook.load_slots()  # saved when changed
var selected := 0  # the slot cast last, highlighted in the HUD
var flow := CastFlow.new()  # casts being picked for, and ready to send
var _accum := 0.0
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
		Spellbook.save_slots(slots)
		hud.notice("Saved to spell %d: %s" % [(slot + 1) % 10, SpellGrammar.to_text(ast)]))
	editor.visibility_changed.connect(func() -> void:
		if not editor.visible:
			Spellbook.save_slots(slots))
	editor.reset_requested.connect(func() -> void:
		slots.clear()
		slots.append_array(Sandbox.PRESETS.duplicate(true))
		editor.open(slots, selected))
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
	flow = CastFlow.new()
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
	view.preview = {}
	var mouse := view.get_global_mouse_position()
	var hovered := hud.slot_at(get_viewport().get_mouse_position(), slots.size()) \
			if not (quick.visible or editor.visible or flow.busy()) else -1
	hud.refresh(sim, player, slots, selected, _prompt(), hovered)
	if hovered >= 0:
		var ast := SpellGrammar.embed_slots(slots[hovered], slots, [hovered])
		view.preview = SpellPreview.targets(sim, player, ast, mouse, false)
		view.preview_verb = ast["verb"]
	elif quick.visible and quick.input.result.has("ast"):
		var ast: Dictionary = quick.input.result["ast"]
		view.preview = SpellPreview.targets(sim, player, ast, mouse)
		view.preview_verb = ast["verb"]
		quick.set_status(SpellPreview.describe(ast, view.preview))
	elif quick.visible:
		quick.set_status("")
	hud.visible_parts(not editor.visible)
	var tip := ""
	if not editor.visible and hovered < 0:  # a hovered slot's line says what to do itself
		var under := sim.object_at(mouse)
		var spell := view.spell_at(mouse) if under == null else null
		tip = _describe(under) if under != null else _describe_spell(spell) if spell != null else ""
	var what := flow.picking()
	if what in ["this", "there"]:  # where the eyes are: by the mouse
		tip = "[color=#ffd34d][b]%s?[/b] click %s · Esc cancels[/color]\n%s" % [what.capitalize(),
				"a place" if what == "there" else "a thing", tip]
	hud.tooltip(tip, mouse)


func _command() -> Dictionary:
	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	var cmd := {
		"move": Vector2.ZERO if typing else Input.get_vector("move_left", "move_right", "move_up", "move_down"),
		"aim": view.get_global_mouse_position(),
	}
	var next := flow.take()
	if not next.is_empty():
		cmd["cast"] = next["ast"]
		cmd["aim"] = next["aim"]
		view.flash(player.pos, WorldView.VERB_COLOR.get(next["ast"]["verb"], Color.WHITE))
	if _pending_drop != 0:
		cmd["drop"] = _pending_drop
		_pending_drop = 0
	return cmd


## Casts the selected slot toward `aim` (see CastFlow for the picks).
func _begin_cast(aim: Vector2) -> void:
	_cast(slots[selected], aim, selected)


## Casts `spell` (from slot `slot`, or -1 if typed) toward `aim`, after its picks.
func _cast(spell: Dictionary, aim: Vector2, slot: int) -> void:
	if flow.busy():
		return
	hud.hide_hint()
	# The spells of the slots an Alternate uses are copied in now, as they are.
	flow.begin(SpellGrammar.embed_slots(spell, slots, [slot] if slot >= 0 else []), aim, sim.object_at(aim))
	_ask_chosen()


## Opens the window for a Chosen, if that's the pick to make.
func _ask_chosen() -> void:
	if flow.picking() == "chosen":
		picker.ask(flow.spell(), flow.pick_number(), flow.pick_count(), sim.inventory(player))


func _on_picked(value: Variant) -> void:
	flow.pick(value)
	_ask_chosen()


func _cancel_cast() -> void:
	flow.cancel()
	picker.hide()


## What the HUD should ask for, if anything.
func _prompt() -> String:
	var what := flow.picking()
	if what == "" or what == "chosen":
		return ""
	return "%s\n[b][color=#ffd34d]Click %s for %s (%d of %d)[/color][/b] [color=#8a8f98]· Esc cancels[/color]" % [
		SpellText.bbcode(flow.spell()), "a thing" if what == "this" else "a place",
		what.capitalize(), flow.pick_number(), flow.pick_count()]


## The words that describe `o` from the player's side, colored by mana.
func _describe(o: WorldObject) -> String:
	var words: Array[String] = []
	var kind: String = "player" if o.has_tag("player") else "mana" if o.has_tag("mana") else o.material
	if o == player:
		kind = "me"
	words.append("[color=#%s]%s[/color]" % [SpellText.color_of(kind).to_html(false), kind.capitalize()])
	for adj in SpellGrammar.ADJECTIVES:
		if o != player and sim.has_adjective(o, adj, player):
			words.append("[color=#%s]%s[/color]" % [SpellText.color_of(adj).to_html(false), adj])
	var text := " · ".join(words)
	if o.health < o.max_health:
		text += "  [color=#8a8f98]%d/%d[/color]" % [o.health, o.max_health]
	return "[font_size=13]%s[/font_size]" % text


## The words for hovering spell `o`: what it says, how it's doing, its mana.
func _describe_spell(o: WorldObject) -> String:
	var s := o.spell
	var n := s.targets().size()
	var doing := "acting on %d" % n if n > 0 else "waiting: nothing to act on"
	if s.paused:
		doing = "waiting for its turn"
	elif s.ast["verb"] == "create":
		doing = "made %d" % s.created.size()
	var mana: Array[String] = []
	for c in SpellGrammar.COLORS:
		if s.mana.get(c, 0.0) > 0.0:
			mana.append("[color=#%s]%d %s[/color]" % [SpellText.WORD_COLOR[c].to_html(false), ceili(s.mana[c]), c])
	var fuel := "paid by its Alternate" if s.paid_by_parent else "mana left " + " ".join(mana)
	var number := sim.inventory(player).find(o)
	return "[font_size=13]%s%s\n[color=#8a8f98]%s · %s[/color][/font_size]" % [
		"[b]%d[/b]  " % (number + 1) if number >= 0 else "", SpellText.bbcode(s.ast), doing, fuel]


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_F1:
		words.toggle()  # even while typing
		get_viewport().set_input_as_handled()
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return  # typing: Tab completes, Enter submits
	# Handled here, before the editor's controls can take Tab for focus.
	if event.keycode == KEY_ESCAPE and editor.visible:
		editor.hide()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_TAB and not picker.visible:
		if editor.visible:
			editor.hide()
		else:
			editor.open(slots, selected)
		get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not editor.visible and not picker.visible \
			and not flow.busy():
		quick.open()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if editor.visible:
		return
	if flow.picking() in ["this", "there"]:
		_handle_world_pick(event)
		return
	var clicked: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if picker.visible and clicked:
		var spell := view.spell_at(view.get_global_mouse_position())
		if spell != null:
			picker.choose(spell.id)  # an attached spell, clicked by the player
		get_viewport().set_input_as_handled()
		return
	var slot_clicked := hud.slot_at(get_viewport().get_mouse_position(), slots.size()) if clicked else -1
	if slot_clicked >= 0 and not quick.visible and not flow.busy():
		selected = slot_clicked
		editor.open(slots, slot_clicked)  # a click on a slot's line edits it
		get_viewport().set_input_as_handled()
		return
	if quick.visible and clicked:
		quick.submit()  # cast what's typed where clicked: This is what's there
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var slot: int = 9 if event.keycode == KEY_0 else event.keycode - KEY_1
		if slot >= 0 and slot < mini(slots.size(), 10):
			# A number key casts its slot toward the mouse right away.
			if not flow.busy() and not picker.visible:
				selected = slot
				_begin_cast(view.get_global_mouse_position())
		elif event.keycode == KEY_SPACE and not flow.busy() and not picker.visible:
			_dropping = true
			picker.ask_drop(sim.inventory(player))
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R:
			_reset()


## While picking This or There: a click picks, Esc or a right click cancels
## the cast.
func _handle_world_pick(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE \
			or event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_cast()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var at := view.get_global_mouse_position()
		if flow.picking() == "there":
			_on_picked(at)
			return
		var o := sim.object_at(at)
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
