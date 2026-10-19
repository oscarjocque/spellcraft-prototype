extends SceneTree
## Headless checks for the prototype's spells and rules.
##   godot --headless --path . --script res://tests/test_spells.gd

var _failures := 0


func _init() -> void:
	for t in [
		"test_barrier", "test_extinguish_releases_mana", "test_boulder_throw",
		"test_fire_burns_wood", "test_water_destroys_fire", "test_stone_blocks_movement",
		"test_dispel", "test_live_tracker", "test_destroying_selector_cuts_off_spell",
		"test_not_enough_mana", "test_closest_never_picks_caster", "test_deterministic",
		"test_payload", "test_create_spell_pays_from_reserve", "test_nested_create_spell",
		"test_create_spell_needs_its_payload", "test_created_spell_stays_put",
		"test_spell_absorbs_mana", "test_invalid_created_spell",
	]:
		call(t)
	print("FAILED: %d" % _failures if _failures else "All tests passed.")
	quit(1 if _failures else 0)


func check(cond: bool, what: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + what)


func world() -> Array:
	var sim := Simulation.new()
	var player := sim.spawn(Materials.make_player(Vector2(200, 360), 0))
	return [sim, player]


func run(sim: Simulation, ticks: int) -> void:
	for i in ticks:
		sim.step()


func count(sim: Simulation, qualifier: String) -> int:
	return sim.objects.filter(func(o: WorldObject) -> bool: return o.matches(qualifier)).size()


func test_barrier() -> void:
	var w := world()
	var sim: Simulation = w[0]
	sim.cast(w[1], {"verb": "create", "what": {"material": "wood"}}, Vector2(400, 360))
	run(sim, 30)
	var wood := sim.closest(Vector2(400, 360), "wood", [])
	check(wood != null and is_equal_approx(wood.radius, 22.0), "Create Wood builds a full-size wood object")
	check(wood.pos.x > 200, "Create places the object toward the aim")
	check(count(sim, "spell") == 0, "Create ends once the object is complete")


func test_extinguish_releases_mana() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	sim.spawn(Materials.make("fire", Vector2(500, 200)))
	sim.cast(p, {"verb": "destroy", "what": {"closest": "fire"}}, Vector2.ZERO)
	var violet_after_cast: float = p.mana_store["violet"]
	run(sim, 5)
	check(count(sim, "fire") == 0, "Destroy (Closest Fire) removes the fire")
	check(count(sim, "spell") == 0, "Destroy ends when the target is gone")
	# The spell sits on its caster, so released mana lands on them and is collected.
	check(p.mana_store["violet"] > violet_after_cast, "Leftover mana is released and collected")


func test_boulder_throw() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var stone := sim.spawn(Materials.make("stone", Vector2(400, 360)))
	var dummy := sim.spawn(Materials.make_player(Vector2(800, 360)))
	sim.cast(w[1], {"verb": "move", "what": {"closest": "stone"}, "to": {"closest": "player"}}, Vector2.ZERO)
	run(sim, 80)
	check(stone.pos.distance_to(dummy.pos) < stone.radius + dummy.radius + 4, "Stone reaches the dummy")
	check(dummy.health < dummy.max_health, "A fast stone damages what it hits")
	check(count(sim, "spell") == 0, "Move ends on arrival")


func test_fire_burns_wood() -> void:
	var sim := Simulation.new()
	sim.spawn(Materials.make("fire", Vector2(300, 300)))
	var wood := sim.spawn(Materials.make("wood", Vector2(330, 300)))
	run(sim, 2)
	check(wood.statuses.has("burning"), "Fire touching wood sets it burning")
	run(sim, 4 * Simulation.TICK_RATE)
	check(wood.dead and count(sim, "wood") == 0, "Burning wood is destroyed")


func test_water_destroys_fire() -> void:
	var sim := Simulation.new()
	sim.spawn(Materials.make("fire", Vector2(300, 300)))
	sim.spawn(Materials.make("water", Vector2(320, 300)))
	run(sim, 1)
	check(count(sim, "fire") == 0, "Water destroys fire")
	check(count(sim, "water") == 1, "Water survives")


func test_stone_blocks_movement() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var wood := sim.spawn(Materials.make("wood", Vector2(700, 360)))
	sim.spawn(Materials.make("stone", Vector2(450, 360)))
	sim.cast(w[1], {"verb": "move", "what": {"closest": "wood"}, "to": {"ref": "me"}}, Vector2.ZERO)
	run(sim, 80)
	check(wood.pos.x > 470, "Stone stops the moving wood")
	check(count(sim, "spell") == 0, "A blocked Move ends")


func test_dispel() -> void:
	var w := world()
	var sim: Simulation = w[0]
	sim.spawn(Materials.make_player(Vector2(900, 360)))  # dummy, does not collect
	sim.cast(w[1], {"verb": "select", "qualifier": "player"}, Vector2(900, 300))
	run(sim, 2)
	check(count(sim, "spell") == 1, "Independent selector stays active")
	var mana_before := count(sim, "mana")
	sim.cast(w[1], {"verb": "destroy", "what": {"closest": "spell"}}, Vector2.ZERO)
	run(sim, 4)
	check(count(sim, "spell") == 0, "Dispel destroys the spell and then ends")
	check(count(sim, "mana") > mana_before, "Dispelled spell releases its mana")


func test_live_tracker() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var stone := sim.spawn(Materials.make("stone", Vector2(300, 600)))
	var a := sim.spawn(Materials.make_player(Vector2(900, 150)))
	var b := sim.spawn(Materials.make_player(Vector2(900, 650)))
	var selector := sim.cast(p, {"verb": "select", "qualifier": "player"}, Vector2(900, 100))
	sim.cast(p, {"verb": "move", "what": {"closest": "stone"}, "to": {"ref": "it"}}, Vector2.ZERO)
	run(sim, 10)
	check(selector.spell.current == a, "Selector picks the player nearest to it")
	var heading_a := stone.pos.direction_to(a.pos)
	check((stone.pos - stone.prev_pos).normalized().dot(heading_a) > 0.95, "Stone chases the selector's pick")
	selector.pos = Vector2(900, 700)  # the selector is moved; its pick changes
	run(sim, 2)
	check(selector.spell.current == b, "Independent selector re-chooses every tick")
	check((stone.pos - stone.prev_pos).normalized().dot(stone.pos.direction_to(b.pos)) > 0.95, "Stone follows the new pick")


func test_destroying_selector_cuts_off_spell() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	sim.spawn(Materials.make("stone", Vector2(300, 600)))
	sim.spawn(Materials.make_player(Vector2(900, 150)))
	var selector := sim.cast(p, {"verb": "select", "qualifier": "player"}, Vector2(900, 100))
	var mover := sim.cast(p, {"verb": "move", "what": {"closest": "stone"}, "to": {"ref": "it"}}, Vector2.ZERO)
	run(sim, 3)
	selector.health = 0
	run(sim, 3)
	check(mover.dead, "A spell relying on a destroyed selector ends")


func test_not_enough_mana() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	p.mana_store["green"] = 0.0
	var host := sim.cast(p, {"verb": "move", "what": {"closest": "stone"}, "to": {"ref": "me"}}, Vector2.ZERO)
	check(host == null, "Casting without the needed color fails")
	check(sim.messages.size() == 1, "The failure is reported")


func test_closest_never_picks_caster() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var other := sim.spawn(Materials.make_player(Vector2(1000, 360)))
	var host := sim.cast(p, {"verb": "destroy", "what": {"closest": "player"}}, Vector2.ZERO)
	check(host.spell.what == other, "Closest Player cast by a player finds someone else")


const FIRE_WARDEN := {"verb": "create", "what": {"spell": {"verb": "destroy", "what": {"closest": "fire"}}}}


func test_payload() -> void:
	# The warden must carry 5 s of Destroy (Closest Fire): destroy + closest
	# (violet) and fire (red).
	check(SpellGrammar.payload(FIRE_WARDEN) == {"violet": 10.0, "red": 5.0}, "Payload covers the created spell")
	check(SpellGrammar.drain_per_second(FIRE_WARDEN) == {"red": 1.0, "violet": 1.0}, "Creator drains only its own words")
	check(SpellGrammar.blocks(FIRE_WARDEN).size() == 5, "Words include the created spell's")
	check(SpellGrammar.to_text(FIRE_WARDEN) == "Create Spell [Destroy (Closest Fire)].", "Created spell reads inside brackets")


func test_create_spell_pays_from_reserve() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	sim.spawn(Materials.make("fire", Vector2(600, 200)))
	var parent := sim.cast(p, FIRE_WARDEN, Vector2(400, 360))
	# Storage pays the reserve (violet 10, red 5) and then up to 10 fuel per color.
	check(is_equal_approx(p.mana_store["violet"], 10.0), "Caster pays the created spell's mana up front")
	check(is_equal_approx(p.mana_store["red"], 15.0), "Caster pays the created spell's red mana up front")
	var child: WorldObject = parent.spell.what
	check(child != null and child.spell != null, "Create Spell puts a spell into the world")
	check(child.spell.mana == {"violet": 10.0, "red": 5.0}, "The created spell's mana comes from the creator's reserve")
	check(parent.spell.reserve.is_empty(), "The reserve is handed over")
	check(not child.spell.anchored and child.pos.x > p.pos.x, "The created spell sits in front of the caster")
	check(p.last_it == child, "It refers to the created spell")
	run(sim, 10)
	check(count(sim, "fire") == 0, "The created spell does its job")


func test_nested_create_spell() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var ast := {"verb": "create", "what": {"spell": {"verb": "create", "what": {"spell": {"verb": "create", "what": {"material": "fire"}}}}}}
	check(SpellGrammar.payload(ast) == {"red": 15.0, "violet": 5.0}, "Payload includes the created spell's own payload")
	var outer := sim.cast(p, ast, Vector2(600, 360))
	var middle: WorldObject = outer.spell.what
	check(middle.spell.mana == {"red": 5.0, "violet": 5.0}, "Middle spell keeps its fuel")
	check(middle.spell.reserve.is_empty(), "Middle spell hands its reserve on when it creates")
	var inner: WorldObject = middle.spell.what
	check(inner != null and inner.spell.mana == {"red": 10.0}, "Innermost spell is paid from the middle reserve")
	run(sim, 20)
	check(count(sim, "fire") == 1, "The innermost spell creates its fire")


func test_create_spell_needs_its_payload() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	p.mana_store["violet"] = 10.0  # 1 for the creator's drain + 10 reserve needed
	check(sim.cast(p, FIRE_WARDEN, Vector2(400, 360)) == null, "Cast fails without the created spell's mana")
	check(is_equal_approx(p.mana_store["violet"], 10.0), "A failed cast takes nothing")


func test_created_spell_stays_put() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var parent := sim.cast(p, {"verb": "create", "what": {"spell": {"verb": "select", "qualifier": "player"}}}, Vector2(400, 360))
	var child: WorldObject = parent.spell.what
	var at := child.pos
	for i in 20:
		sim.step({0: {"move": Vector2.DOWN}})
	check(p.pos.y > 400 and child.pos == at, "A created spell stays where it was made")
	check(child.spell.current == p, "A created spell is not anchored to the caster, so it can select them")


func test_spell_absorbs_mana() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	sim.spawn(Materials.make_player(Vector2(900, 360)))
	var host := sim.cast(p, {"verb": "select", "qualifier": "player"}, Vector2(900, 300))
	var crystal := sim.spawn(Materials.make_mana("blue", 5.0, Vector2(903, 300)))
	var target := sim.spawn(Materials.make_mana("red", 5.0, Vector2(600, 600)))
	run(sim, 1)
	check(crystal.dead, "Mana touching a spell is absorbed")
	check(is_equal_approx(host.spell.mana.get("blue", 0.0), 5.0), "Absorbed mana joins the spell's fuel")
	check(sim.closest(Vector2(600, 600), "mana", []) == target, "Mana is a qualifier spells can select")


func test_invalid_created_spell() -> void:
	check(SpellGrammar.validate({"verb": "create", "what": {"spell": {"verb": "move", "what": {"ref": "me"}}}}) != "",
		"Create Spell rejects an incomplete spell description")
	check(SpellGrammar.validate({"verb": "create", "what": {"spell": "fireball"}}) != "",
		"Create Spell needs the spell as a description")
	var long_spell := {"verb": "create", "what": {"spell": {"verb": "create", "what": {"spell":
		{"verb": "move", "what": {"closest": "stone"}, "to": {"closest": "player"}}}}}}
	check(SpellGrammar.validate(long_spell) == "", "Spells have no word limit")


func test_deterministic() -> void:
	check(_replay() == _replay(), "Same inputs give the same world")


func _replay() -> String:
	var sim := Simulation.new(42)
	var player := Sandbox.build(sim)
	for i in 400:
		var cmd := {"move": Vector2(cos(i * 0.05), sin(i * 0.03)), "aim": Vector2(640, 360)}
		if i % 40 == 0:
			cmd["cast"] = Sandbox.PRESETS[(i / 40) % Sandbox.PRESETS.size()]
		sim.step({player.controller: cmd})
	var state := ""
	for o in sim.objects:
		state += "%d %s %s %.3f|" % [o.id, o.material, o.pos, o.health]
	return state
