class_name Hud
extends CanvasLayer
## Mana storage, spell slots, recent messages and controls.

const MESSAGE_SECONDS := 5

var _top: RichTextLabel
var _bottom: RichTextLabel
var _inventory: RichTextLabel
var _prompt: RichTextLabel
var _tip: RichTextLabel
var _hint: RichTextLabel
var _notices := []  # [text, msec shown]: the player's own doings, e.g. saving
var _hint_done := false


func _ready() -> void:
	_top = _make_label(Vector2(12, 8))
	_bottom = _make_label(Vector2(12, 470))
	_inventory = _make_label(Vector2(860, 8))
	_inventory.size.x = 410
	_prompt = _make_label(Vector2(340, 60))
	_prompt.size.x = 600
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint = _make_label(Vector2(290, 120))
	_hint.size.x = 700
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.text = ("[color=#a7abb3]Press [b]Enter[/b], type [color=#72de8f]move stone to me[/color] and press [b]Enter[/b]; "
			+ "or type [color=#b48cff]destroy[/color] and click a thing.\nNumber keys cast your slots, "
			+ "[b]Tab[/b] opens your spellbook, [b]F1[/b] lists every word.[/color]")
	_tip = _make_label(Vector2.ZERO)
	_tip.size.x = 360


## `prompt` asks the player to pick something for the spell being cast.
func refresh(sim: Simulation, player: WorldObject, slots: Array, selected: int, prompt: String) -> void:
	_show_text(_prompt, prompt)
	var mana := "[b]Mana[/b]  "
	if player.has_tag("infinite_mana"):
		mana += "infinite"
	else:
		for c in SpellGrammar.COLORS:
			var hex: String = WorldView.MANA_COLOR[c].to_html(false)
			mana += "[color=#%s]%s %d/%d[/color]   " % [hex, c, player.mana_store.get(c, 0.0), Simulation.STORE_CAP]
	var spells := 0
	for o in sim.objects:
		if o.spell != null:
			spells += 1
	mana += "\nActive spells: %d    Health: %d" % [spells, player.health]
	_show_text(_top, mana)

	var text := ""
	for i in slots.size():
		var key := "[b]%d[/b]" % ((i + 1) % 10)
		var mark := "[color=#ffd34d]▶[/color] " if i == selected else "   "
		text += "%s%s  %s\n" % [mark, key, SpellText.bbcode(slots[i])]
	for i in sim.messages.size():
		if sim.tick - sim.message_ticks[i] < MESSAGE_SECONDS * Simulation.TICK_RATE:
			text += "[color=#ff8a8a]%s[/color]\n" % sim.messages[i]
	var now := Time.get_ticks_msec()
	_notices = _notices.filter(func(n: Array) -> bool: return now - n[1] < MESSAGE_SECONDS * 1000)
	for n in _notices:
		text += "[color=#ffd34d]%s[/color]\n" % n[0]
	text += "[color=#8a8f98]WASD move · 1–0 cast toward the mouse · Enter type a spell · Tab spellbook · Space drop a spell · F1 words · R reset[/color]"
	_show_text(_bottom, text)
	# Grows up from the bottom as messages come and go.
	_bottom.position.y = _bottom.get_viewport_rect().size.y - _bottom.get_content_height() - 8

	var inv := "[b]Attached spells[/b]  [color=#8a8f98]Chosen picks from these[/color]\n"
	var attached := sim.inventory(player)
	if attached.is_empty():
		inv += "[color=#8a8f98]none[/color]"
	for i in attached.size():
		inv += "%d  %s\n" % [i + 1, SpellText.bbcode(attached[i].spell.ast)]
	_show_text(_inventory, inv)


## Shows `text` under the slots for a few seconds.
func notice(text: String) -> void:
	_notices.append([text, Time.get_ticks_msec()])


## A label's text, set only when it changed (RichTextLabel re-parses on set).
static func _show_text(label: RichTextLabel, text: String) -> void:
	if label.text != text:
		label.text = text


## Shows `bbcode` by the mouse at `at`, or nothing if it's "".
func tooltip(bbcode: String, at: Vector2) -> void:
	_show_text(_tip, bbcode)
	_tip.position = at + Vector2(16, 12)


## Hides the first-run hint (once the player has cast something).
func hide_hint() -> void:
	_hint_done = true
	_hint.visible = false


## Hides the slot list, inventory and hint (under the spellbook, which shows
## the slots).
func visible_parts(shown: bool) -> void:
	_bottom.visible = shown
	_inventory.visible = shown
	_hint.visible = shown and not _hint_done


func _make_label(pos: Vector2) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = pos
	label.size = Vector2(900, 0)
	label.add_theme_font_size_override("normal_font_size", 14)
	label.add_theme_font_size_override("bold_font_size", 14)
	add_child(label)
	return label
