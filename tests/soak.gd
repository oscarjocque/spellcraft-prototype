extends SceneTree
## A long random session through the real game (casting every slot, typing
## spells, picking, dropping, editing in the spellbook), to catch runtime
## errors the unit tests miss. Run it and look for SCRIPT ERROR:
##   godot --path . --script res://tests/soak.gd
var main
var f := 0
var rng := RandomNumberGenerator.new()
const TYPED := ["mo st me", "destroy all fires within 3 of here, up to 2", "create fire at there",
	"move this to there", "mark all moving stones", "closest player", "move stone to target of chosen",
	"create spell [destroy fire]", "alternate 5 chosen", "create wood at aimed", "hold all things within 2 of me",
	"destroy products of chosen", "move all players to farthest stone", "mark random burning thing",
	"de", "mo st", "mvoe stoen to me", "hold", "create fire at there", "move to me",
	"kill the nearest rock", "pull stone", "make a fire", "tag everything within 3 of me",
	"push stone", "move all logs within 3 of there away from there", "move self to there", "destroy self"]
func _initialize():
	rng.seed = 7
	Spellbook.path = "user://soak_spellbook.txt"  # leave the real spellbook alone
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
func _process(_d):
	f += 1
	var aim := Vector2(rng.randf_range(40, 1240), rng.randf_range(40, 680))
	# keep any pick moving along
	if main.flow.picking() in ["this", "there"]:
		var o = main.sim.object_at(aim)
		if main.flow.picking() == "there":
			main._on_picked(aim)
		elif o != null:
			main._on_picked(o.id)
		elif rng.randf() < 0.2:
			main._cancel_cast()
	elif main.picker.visible:
		if rng.randf() < 0.5 and main.picker._entries.size() > 0:
			main.picker._entries[rng.randi_range(0, main.picker._entries.size() - 1)][2].call()
		else:
			main.picker._cancel()
	elif f % 7 == 0:
		var slot := rng.randi_range(0, 9)
		main.selected = slot
		main._begin_cast(aim)
	elif f % 11 == 0:
		var r := SpellParser.parse(TYPED[rng.randi_range(0, TYPED.size() - 1)])
		if r.has("ast"):
			main._cast(r["ast"], aim, -1)
	elif f % 13 == 0 and not main.editor.visible:
		main.quick.open()  # typed into the bar: the world previews it
		main.quick.input.set_text(TYPED[rng.randi_range(0, TYPED.size() - 1)])
	elif f % 13 == 3 and main.quick.visible:
		Input.warp_mouse(aim)
		main.quick.submit()
	elif f % 97 == 0:
		main._dropping = true
		main.picker.ask_drop(main.sim.inventory(main.player))
	elif f % 251 == 0:
		main.editor.open(main.slots, rng.randi_range(0, 9))
	elif f % 251 == 5:
		# click a few random word-menu choices
		for k in 5:
			var chips: SpellChips = main.editor._chips
			var acts := []
			for c in chips.get_children():
				if c is MenuButton:
					_collect(c.get_popup(), acts)
			if not acts.is_empty():
				var a = acts[rng.randi_range(0, acts.size() - 1)]
				a[0].id_pressed.emit(a[1])
	elif f % 251 == 10:
		main.editor.hide()
	if f % 700 == 350:
		main.level = (main.level + 1) % Levels.NAMES.size()  # play the levels too
		main._reset()
	if f % 3 == 0:
		main.player.pos += Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
	if f == 3000:
		print("soak done: tick ", main.sim.tick, " objects ", main.sim.objects.size(), " spells ", main.sim.objects.filter(func(o): return o.spell != null).size())
		quit()
	return false
func _collect(popup: PopupMenu, out: Array) -> void:
	for i in popup.item_count:
		var sub := popup.get_item_submenu_node(i)
		if sub != null:
			_collect(sub, out)
		else:
			out.append([popup, popup.get_item_id(i)])
