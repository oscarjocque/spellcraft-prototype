class_name Hud
extends CanvasLayer
## Mana storage, spell slots, recent messages and controls.

var _top: RichTextLabel
var _bottom: RichTextLabel
var _inventory: RichTextLabel
var _prompt: RichTextLabel


func _ready() -> void:
	_top = _make_label(Vector2(12, 8))
	_bottom = _make_label(Vector2(12, 470))
	_inventory = _make_label(Vector2(860, 8))
	_inventory.size.x = 410
	_prompt = _make_label(Vector2(340, 60))
	_prompt.size.x = 600
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## `prompt` asks the player to pick something for the spell being cast.
func refresh(sim: Simulation, player: WorldObject, slots: Array, selected: int, prompt: String) -> void:
	_prompt.text = "[b][color=#ffd34d]%s[/color][/b]" % prompt if prompt != "" else ""
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
	_top.text = mana

	var text := ""
	for i in slots.size():
		var key := "[b]%d[/b]" % ((i + 1) % 10)
		var mark := "[color=#ffd34d]▶[/color] " if i == selected else "   "
		text += "%s%s  %s\n" % [mark, key, SpellText.bbcode(slots[i])]
	for m in sim.messages:
		text += "[color=#ff8a8a]%s[/color]\n" % m
	text += "[color=#8a8f98]WASD move · 1–0 cast toward the mouse · Enter type a spell · Tab spellbook · Space drop a spell · F1 words · R reset[/color]"
	_bottom.text = text

	var inv := "[b]Attached spells[/b]  [color=#8a8f98]Chosen picks from these[/color]\n"
	var attached := sim.inventory(player)
	if attached.is_empty():
		inv += "[color=#8a8f98]none[/color]"
	for i in attached.size():
		inv += "%d  %s\n" % [i + 1, SpellText.bbcode(attached[i].spell.ast)]
	_inventory.text = inv


## Hides the slot list and inventory (under the spellbook, which shows them).
func visible_parts(shown: bool) -> void:
	_bottom.visible = shown
	_inventory.visible = shown


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
