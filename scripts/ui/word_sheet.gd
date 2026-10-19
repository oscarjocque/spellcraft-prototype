class_name WordSheet
extends PanelContainer
## F1: every word a spell can use, grouped, each in the color of the mana it
## costs, with typed examples. A crib sheet for thinking in spells.

const GROUPS := [
	["Verbs", ["create", "destroy", "move", "mark", "", "alternate"],
		"Hold (a noun on its own) is free · leave out what a verb acts on: This · where Move goes: There"],
	["Things", ["thing", "fire", "water", "wood", "stone", "spell", "player", "mana"],
		"a thing on its own means the closest one"],
	["Pickers", ["closest", "farthest", "random", "all"], ""],
	["Adjectives", ["moving", "burning", "mine", "theirs", "marked"], "go before the thing"],
	["Nouns", ["me", "here", "aimed", "this", "there", "chosen", "it"],
		"This and There come from the mouse, Chosen from your attached spells, It only inside Alternate"],
	["Of", ["target_of", "caster_of", "maker_of", "products_of"], "followed by a noun"],
	["Extras", ["within", "from", "at", "up_to"], "within 3 m (of …)  ·  to …  ·  Create … at …  ·  …, up to 2"],
]
const EXAMPLES := [
	"mo st", "de", "destroy all fires within 3 of here", "create fire at there",
	"move this to there", "mark all moving stones, up to 2", "closest player",
	"move stone to target of chosen", "create spell [destroy fire]", "alternate 5 6", "mvoe stoen to me",
]

var _text: RichTextLabel


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11)
	style.border_color = Color("2c3038")
	style.set_border_width_all(1)
	style.set_content_margin_all(14)
	style.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", style)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size.x = 760
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text)
	_text.text = _build()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func toggle() -> void:
	visible = not visible
	if visible:
		move_to_front()
		reset_size()
		position = Vector2((get_viewport_rect().size.x - size.x) / 2, 40)


static func _build() -> String:
	var grey := SpellText.FREE_COLOR.to_html(false)
	var out := "[b]Words[/b]   [color=#%s]colored by the mana they cost · F1 closes[/color]\n\n" % grey
	for group in GROUPS:
		var words: Array[String] = []
		for w in group[1]:
			if w == "":
				words.append("[color=#%s]hold[/color]" % grey)
			else:
				var label: String = {"within": "within N m", "from": "to / of", "up_to": "up to N"}.get(w,
						w.replace("_", " "))
				words.append("[color=#%s]%s[/color]" % [SpellText.color_of(w).to_html(false), label])
		out += "[b]%s[/b]   %s" % [group[0], "   ".join(words)]
		if group[2] != "":
			out += "   [color=#%s][font_size=12]%s[/font_size][/color]" % [grey, group[2]]
		out += "\n"
	out += "\n[b]Type it[/b]   [color=#%s]Enter, then for example:[/color]\n" % grey
	for e in EXAMPLES:
		var r := SpellParser.parse(e)
		var reads: String = SpellText.bbcode(r["ast"]) if r.has("ast") else ""
		out += "   [code]%s[/code]   [color=#%s]→[/color]   %s\n" % [e, grey, reads]
	out += "\n[color=#%s]Words can be cut short (mo = move, st = stone), and a slip of one letter is forgiven. Tab takes a suggestion.[/color]" % grey
	return out
