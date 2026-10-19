extends SceneTree
## Headless checks for the prototype's spells and rules.
##   godot --headless --path . --script res://tests/test_spells.gd

var _failures := 0
var _ran := false


func _process(_delta: float) -> bool:
	# On the first frame, once the tree is up, so UI nodes get their _ready.
	if not _ran:
		_ran = true
		_run()
	return false


## Every test_ function, in the order they're written.
func _run() -> void:
	var tests: Array[String] = []
	for m in get_script().get_script_method_list():
		if m["name"].begins_with("test_") and not m["name"] in tests:
			tests.append(m["name"])
	for t in tests:
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


## Mana amounts are sums of 0.2s, so compare them approximately.
func same(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in b:
		if not (a.has(k) and is_equal_approx(a[k], b[k])):
			return false
	return true


func run(sim: Simulation, ticks: int) -> void:
	for i in ticks:
		sim.step()


func count(sim: Simulation, qualifier: String) -> int:
	return sim.objects.filter(func(o: WorldObject) -> bool: return o.matches(qualifier)).size()


func test_barrier() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var host := sim.cast(w[1], {"verb": "create", "what": {"material": "wood"}}, Vector2(400, 360))
	run(sim, 2 * Simulation.TICK_RATE)
	var wood: WorldObject = host.spell.created[0]
	check(wood != null and is_equal_approx(wood.radius, 22.0), "Create Wood builds a full-size wood object")
	check(wood.pos.x > 200, "Create places the object toward the aim")
	check(count(sim, "spell") == 1, "Create keeps going once the object is complete")


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
	check(count(sim, "spell") == 1, "Held selector stays active")
	var p: WorldObject = w[1]
	sim.cast(p, {"verb": "destroy", "what": {"closest": "spell"}}, Vector2.ZERO)
	var violet: float = p.mana_store["violet"]
	run(sim, 4)
	check(count(sim, "spell") == 0, "Dispel destroys the spell and then ends")
	# The held selector sat on its caster, so its released mana lands on them.
	check(p.mana_store["violet"] > violet, "Dispelled spell releases its mana")


func test_held_selector_tracks() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var stone := sim.spawn(Materials.make("stone", Vector2(500, 360)))
	var a := sim.spawn(Materials.make_player(Vector2(900, 150)))
	var b := sim.spawn(Materials.make_player(Vector2(900, 650)))
	var selector := sim.cast(p, {"verb": "select", "qualifier": "player"}, Vector2(900, 100))
	check(selector.spell.anchored and selector.pos == p.pos, "A bare selector stays attached to its caster")
	var mover := sim.cast(p, with_chosen({"verb": "move", "what": {"closest": "stone"}, "to": {"target_of": {"ref": "chosen"}}}, [selector.id]), Vector2.ZERO)
	run(sim, 10)
	check(selector.spell.target() == a, "Held selector picks the player nearest its caster, never the caster")
	check(heading(stone).dot(stone.pos.direction_to(a.pos)) > 0.95, "Stone chases the held selector's pick")

	p.pos = Vector2(200, 650)  # the caster walks; the held selector goes with them
	run(sim, 2)
	check(selector.pos.distance_to(p.pos) < 1.0, "Held selector follows its caster")
	check(selector.spell.target() == b, "Held selector re-chooses every tick")
	check(heading(stone).dot(stone.pos.direction_to(b.pos)) > 0.95, "Stone follows the new pick")

	run(sim, 8 * Simulation.TICK_RATE)
	check(not mover.dead, "Chasing a held selector's pick doesn't end on arrival")
	b.pos = Vector2(650, 650)  # still nearer the caster than a is
	run(sim, 3 * Simulation.TICK_RATE)
	check(stone.pos.distance_to(b.pos) < stone.radius + b.radius + 4, "Stone keeps tracking its target")
	selector.health = 0
	run(sim, 2)
	check(mover.dead, "Destroying the held selector cuts off the spell following it")


func test_tracking_gets_around_stone() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var stone := sim.spawn(Materials.make("stone", Vector2(400, 360)))
	sim.spawn(Materials.make("stone", Vector2(600, 362)))  # in the way
	var target := sim.spawn(Materials.make_player(Vector2(900, 360)))
	var selector := sim.cast(p, {"verb": "select", "qualifier": "player"}, Vector2.ZERO)
	var mover := sim.cast(p, with_chosen({"verb": "move", "what": {"closest": "stone"}, "to": {"target_of": {"ref": "chosen"}}}, [selector.id]), Vector2.ZERO)
	run(sim, 6 * Simulation.TICK_RATE)
	check(not mover.dead, "A chase doesn't end when stone blocks it")
	check(stone.pos.distance_to(target.pos) < stone.radius + target.radius + 4, "It slides around the stone and reaches its target")


func test_held_noun_is_shared() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	sim.spawn(Materials.make("stone", Vector2(500, 360)))
	sim.spawn(Materials.make("stone", Vector2(500, 500)))
	var dummy := sim.spawn(Materials.make_player(Vector2(900, 360)))
	var selector := sim.cast(p, {"verb": "select", "what": {"closest": "player"}}, Vector2.ZERO)
	check(SpellGrammar.to_text(selector.spell.ast) == "Hold (Closest Player).", "A held noun reads as Hold")
	var first := sim.cast(p, with_chosen({"verb": "move", "what": {"closest": "stone"}, "to": {"target_of": {"ref": "chosen"}}}, [selector.id]), Vector2.ZERO)
	var second := sim.cast(p, with_chosen({"verb": "move", "what": {"closest": "stone"}, "to": {"target_of": {"ref": "chosen"}}}, [selector.id]), Vector2.ZERO)
	check(first.spell.destination() == dummy and second.spell.destination() == dummy,
		"Several spells can follow one held selector through Chosen")
	check(selector in sim.inventory(p), "Using a held noun doesn't take it out of the inventory")


func heading(o: WorldObject) -> Vector2:
	return (o.pos - o.prev_pos).normalized()


func test_destroying_selector_cuts_off_spell() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	sim.spawn(Materials.make("stone", Vector2(300, 600)))
	sim.spawn(Materials.make_player(Vector2(900, 150)))
	var selector := sim.cast(p, {"verb": "select", "qualifier": "player"}, Vector2(900, 100))
	var mover := sim.cast(p, with_chosen({"verb": "move", "what": {"closest": "stone"}, "to": {"target_of": {"ref": "chosen"}}}, [selector.id]), Vector2.ZERO)
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
	check(host.spell.target() == other, "Closest Player cast by a player finds someone else")


const FIRE_WARDEN := {"verb": "create", "what": {"spell": {"verb": "destroy", "what": {"closest": "fire"}}}}


func test_payload() -> void:
	# Each of the warden's 3 spells gets 60 s of Destroy (Closest Fire) at
	# 0.2/s per word: destroy + closest (violet) and fire (red).
	check(same(SpellGrammar.share(FIRE_WARDEN["what"]["spell"]), {"violet": 24.0, "red": 12.0}), "A share runs one created spell")
	check(same(SpellGrammar.payload(FIRE_WARDEN), {"violet": 72.0, "red": 36.0}), "Payload covers every created spell")
	check(same(SpellGrammar.drain_per_second(FIRE_WARDEN), {"red": 0.2, "violet": 0.2}), "Creator drains only its own words")
	check(SpellGrammar.blocks(FIRE_WARDEN).size() == 5, "Words include the created spell's")
	check(SpellGrammar.to_text(FIRE_WARDEN) == "Create Spell [Destroy (Closest Fire)].", "Created spell reads inside brackets")


func test_create_spell_pays_from_reserve() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	for c in SpellGrammar.COLORS:
		p.mana_store[c] = 200.0
	sim.spawn(Materials.make("fire", Vector2(600, 200)))
	var parent := sim.cast(p, FIRE_WARDEN, Vector2(400, 360))
	# Storage pays the reserve (violet 72, red 36) and then up to 10 fuel per color.
	check(is_equal_approx(p.mana_store["violet"], 118.0), "Caster pays the created spells' mana up front")
	check(is_equal_approx(p.mana_store["red"], 154.0), "Caster pays the created spells' red mana up front")
	var child: WorldObject = parent.spell.what
	check(child != null and child.spell != null, "Create Spell puts a spell into the world")
	check(same(child.spell.mana, {"violet": 24.0, "red": 12.0}), "The created spell's mana comes from the creator's reserve")
	check(same(parent.spell.reserve, {"violet": 48.0, "red": 24.0}), "One share of the reserve is handed over")
	check(not child.spell.anchored and child.pos.x > p.pos.x, "The created spell sits in front of the caster")
	run(sim, 10)
	check(count(sim, "fire") == 0, "The created spell does its job")


func test_nested_create_spell() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var ast := {"verb": "create", "what": {"spell": {"verb": "create", "what": {"spell": {"verb": "create", "what": {"material": "fire"}}}}}}
	# Middle share: 60 s of create + spell (red 12, violet 12) + its own payload
	# of 3 x 60 s of Create Fire (red 72). Outer payload: 3 middle shares.
	check(same(SpellGrammar.payload(ast), {"red": 252.0, "violet": 36.0}), "Payload includes the created spells' own payloads")
	for c in SpellGrammar.COLORS:
		p.mana_store[c] = 1000.0
	var outer := sim.cast(p, ast, Vector2(600, 360))
	var middle: WorldObject = outer.spell.what
	check(same(middle.spell.mana, {"red": 12.0, "violet": 12.0}), "Middle spell keeps its fuel")
	check(same(middle.spell.reserve, {"red": 48.0}), "Middle spell hands one share on when it creates")
	var inner: WorldObject = middle.spell.what
	check(inner != null and same(inner.spell.mana, {"red": 24.0}), "Innermost spell is paid from the middle reserve")
	run(sim, 20)
	check(count(sim, "fire") >= 1, "The innermost spell creates fire")


func test_create_spell_needs_its_payload() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	p.mana_store["violet"] = 10.0  # 0.2 for the creator's drain + 24 reserve needed
	check(sim.cast(p, FIRE_WARDEN, Vector2(400, 360)) == null, "Cast fails without the created spell's mana")
	check(is_equal_approx(p.mana_store["violet"], 10.0), "A failed cast takes nothing")


func test_created_spell_stays_put() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var parent := sim.cast(p, {"verb": "create", "what": {"spell": {"verb": "select", "qualifier": "player"}}}, Vector2(400, 360))
	var child: WorldObject = parent.spell.what
	var at := child.pos
	for i in 20:
		sim.step({0: {"move": Vector2.DOWN}})
	check(p.pos.y > 400 and child.pos == at, "A created spell stays where it was made")
	check(child.spell.target() == p, "A created spell is not anchored to the caster, so it can select them")


func test_spell_absorbs_mana() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	# A caster that doesn't collect mana, so only the spell can take it.
	var caster := sim.spawn(Materials.make_player(Vector2(900, 300)))
	caster.tags["infinite_mana"] = true
	var host := sim.cast(caster, {"verb": "select", "qualifier": "player"}, Vector2.ZERO)
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


func test_infinite_mana() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	p.tags["infinite_mana"] = true
	for c in SpellGrammar.COLORS:
		p.mana_store[c] = 0.0
	var host := sim.cast(p, FIRE_WARDEN, Vector2(400, 360))
	check(host != null, "Infinite mana casts with empty storage")
	check(p.mana_store["violet"] == 0.0, "Infinite mana takes nothing from storage")
	var child: WorldObject = host.spell.what
	check(same(child.spell.mana, {"violet": 24.0, "red": 12.0}), "Spells still get their usual mana and reserve")


func test_create_sustains_its_objects() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var host := sim.cast(p, {"verb": "create", "what": {"material": "fire"}}, Vector2(400, 360))
	var first: WorldObject = host.spell.created[0]
	run(sim, 15 * Simulation.TICK_RATE)  # past fire's 10 s lifetime
	check(not first.dead and not host.dead, "Fire doesn't burn out while its Create spell lasts")
	sim.cast(p, {"verb": "destroy", "what": {"ref": "this", "id": first.id}}, Vector2.ZERO)
	run(sim, 4)
	check(first.dead and not host.dead, "Create keeps going when one of its objects is destroyed")


func test_create_keeps_creating() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var host := sim.cast(p, {"verb": "create", "what": {"material": "wood"}}, Vector2(1000, 360))
	run(sim, 5 * Simulation.TICK_RATE)
	var made := host.spell.created
	check(made.size() >= 3, "Create builds one object after another")
	var spot := made[0].pos
	check(spot.x > p.pos.x and is_equal_approx(spot.y, 360.0), "The first goes right in front of the caster, toward the aim")
	check(made.all(func(o: WorldObject) -> bool: return o.pos.distance_to(spot) < 4.0 * 22.0 + 1.0),
		"The rest gather in the closest free spots around it, not in a line")
	check(is_equal_approx(made[0].radius, 22.0), "Earlier objects are complete")
	run(sim, 50 * Simulation.TICK_RATE)  # 10 red and 10 green at 0.2/s each last 50 s
	check(host.dead, "Create ends when its mana runs out")
	var count_at_end := count(sim, "wood")
	run(sim, Simulation.TICK_RATE)
	check(count(sim, "wood") == count_at_end, "Its objects stay after it ends")


func test_spells_last_longer() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var host := sim.cast(w[1], {"verb": "select", "qualifier": "player"}, Vector2(600, 360))
	run(sim, 20 * Simulation.TICK_RATE)
	check(not host.dead, "A 2-word spell with 10 mana runs for 20 s")
	run(sim, 6 * Simulation.TICK_RATE)
	check(host.dead, "...and ends when its mana runs out, at 25 s")


const DESTROY_CHOSEN := {"verb": "destroy", "what": {"ref": "chosen"}}


## A copy of `ast` with the Chosen picks filled in, as the pick windows do.
func with_chosen(ast: Dictionary, ids: Array) -> Dictionary:
	var copy := ast.duplicate(true)
	var nouns := SpellGrammar.cast_picks(copy)
	for i in nouns.size():
		nouns[i]["id"] = ids[i]
	return copy


func spell_world() -> Array:
	var w := world()
	w[1].tags["infinite_mana"] = true
	return w


## Builds `n` full objects with a Create Wood cast from `p` toward +x.
func wood_pile(sim: Simulation, p: WorldObject, n: int) -> WorldObject:
	var maker := sim.cast(p, {"verb": "create", "what": {"material": "wood"}}, p.pos + Vector2(100, 0))
	var ticks := ceili(Spell.CREATE_TICKS_PER_RADIUS * 22.0)
	run(sim, n * ticks + 1)
	return maker


func test_create_refills_gaps() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var maker := wood_pile(sim, p, 3)
	var first: WorldObject = maker.spell.created[0]
	var first_at := first.pos
	first.dead = true
	run(sim, ceili(Spell.CREATE_TICKS_PER_RADIUS * 22.0) + 2)
	var newest: WorldObject = maker.spell.created.back()
	check(newest.pos.distance_to(first_at) < 0.5, "The closest spot, once free again, is filled first")


func test_create_skips_obstacles() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	# The spot Create aims at (x = 200 + 22 + 22 = 244) is taken by stone.
	var stone := sim.spawn(Materials.make("stone", Vector2(244, 360)))
	var maker := wood_pile(sim, p, 1)
	var first: WorldObject = maker.spell.created[0]
	check(first.pos.distance_to(stone.pos) >= stone.radius + 22.0 - 0.01, "Create doesn't build on something else")
	check(first.pos.distance_to(Vector2(244, 360)) <= 2.0 * 22.0 + stone.radius, "...but in the closest free spot")


func test_create_waits_for_space() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	# Something huge covers every spot within reach.
	var blocker := sim.spawn(Materials.make("water", Vector2(600, 360)))  # not solid: pushes nobody
	blocker.radius = 400.0
	p.pos = Vector2(600, 360)
	var maker := wood_pile(sim, p, 2)
	check(maker.spell.created.is_empty() and not maker.dead, "With no free spot within reach, Create waits")
	blocker.dead = true
	run(sim, 2)
	check(maker.spell.created.size() == 1, "...and builds once there is space")


func test_create_spell_refills_gaps() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var maker := sim.cast(p, {"verb": "create", "what": {"spell": {"verb": "select", "qualifier": "player"}}}, Vector2(800, 360))
	var first: WorldObject = maker.spell.created[0]
	var first_at := first.pos
	first.health = 0
	run(sim, Spell.CREATE_SPELL_TICKS + 1)
	check(maker.spell.created[1].pos.distance_to(first_at) < 0.5, "A Create Spell refills the closest spot too")


func test_create_spell_makes_several() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var ast := {"verb": "create", "what": {"spell": {"verb": "select", "qualifier": "player"}}}
	var maker := sim.cast(p, ast, Vector2(800, 360))
	check(maker.spell.created.size() == 1, "The first spell is created at once")
	run(sim, Simulation.TICK_RATE)
	check(maker.spell.created.size() == 2, "The next follows a second later")
	run(sim, Simulation.TICK_RATE + 1)
	var made := maker.spell.created
	check(made.size() == SpellGrammar.CREATED_SPELLS and maker.dead, "It ends once it has made all of them")
	check(made[0].pos.distance_to(made[1].pos) >= Spell.CREATED_SPELL_SPACING / 2.0
		and made[1].pos.distance_to(made[2].pos) >= Spell.CREATED_SPELL_SPACING / 2.0
		and made.all(func(o: WorldObject) -> bool: return o.pos.distance_to(made[0].pos) <= Spell.CREATED_SPELL_SPACING + 0.1),
		"They take separate spots, close together")
	for o in made:
		check(not o.dead and o.spell.mana["violet"] > 23.0, "Each created spell got a full share")
	check(maker.spell.reserve.values().all(func(v: float) -> bool: return v < 0.001), "The whole reserve went to them")


func test_moves_combine() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var stone := sim.spawn(Materials.make("stone", Vector2(640, 360)))
	sim.spawn(Materials.make("wood", Vector2(640, 100)))
	sim.spawn(Materials.make("water", Vector2(1000, 360)))
	sim.cast(p, {"verb": "move", "what": {"closest": "stone"}, "to": {"closest": "wood"}}, Vector2.ZERO)
	sim.cast(p, {"verb": "move", "what": {"closest": "stone"}, "to": {"closest": "water"}}, Vector2.ZERO)
	run(sim, 1)
	var step := stone.pos - stone.prev_pos
	check(step.x > 0 and step.y < 0, "Two Moves on one object combine their directions")
	check(step.length() > Spell.MOVE_SPEED * Simulation.DT * 1.3, "...and their speeds add up")
	sim.cast(p, {"verb": "move", "what": {"ref": "me"}, "to": {"closest": "water"}}, Vector2.ZERO)
	sim.step({0: {"move": Vector2.UP}})
	check(p.pos.x > p.prev_pos.x and p.pos.y < p.prev_pos.y, "A Move on a player adds to their walking")


func test_inventory() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var selector := sim.cast(p, {"verb": "select", "qualifier": "player"}, Vector2.ZERO)
	var fire := sim.cast(p, {"verb": "create", "what": {"material": "fire"}}, Vector2(400, 360))
	var warden := sim.cast(p, FIRE_WARDEN, Vector2(400, 360))
	var created: WorldObject = warden.spell.what
	check(sim.inventory(p) == [selector, fire, warden], "Inventory lists the spells attached to the caster, oldest first")
	check(not created in sim.inventory(p), "A spell created by a spell isn't attached, so isn't in the inventory")


func test_chosen_noun() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var selector := sim.cast(p, {"verb": "select", "qualifier": "player"}, Vector2.ZERO)
	var fire := sim.cast(p, {"verb": "create", "what": {"material": "fire"}}, Vector2(400, 360))
	sim.cast(p, with_chosen(DESTROY_CHOSEN, [selector.id]), Vector2.ZERO)
	run(sim, 4)
	check(selector.dead and not fire.dead, "Destroy Chosen destroys the chosen spell, and only it")
	check(SpellGrammar.to_text(DESTROY_CHOSEN) == "Destroy Chosen.", "Chosen reads as a noun")

	var dummy := sim.spawn(Materials.make_player(Vector2(900, 360)))
	var stray := sim.cast(p, with_chosen(DESTROY_CHOSEN, [dummy.id]), Vector2.ZERO)
	run(sim, 5)
	check(stray.spell.target() == null and dummy.health == dummy.max_health,
		"Chosen only accepts a spell in the caster's inventory")
	var nothing := sim.cast(p, with_chosen(DESTROY_CHOSEN, [0]), Vector2.ZERO)
	run(sim, 5)
	check(not nothing.dead and nothing.spell.target() == null, "With nothing chosen, the spell waits")


func test_each_chosen_is_picked_separately() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var stone := sim.spawn(Materials.make("stone", Vector2(500, 600)))
	var pull := sim.cast(p, {"verb": "move", "what": {"closest": "stone"}, "to": {"ref": "me"}}, Vector2.ZERO)
	var fire := sim.cast(p, {"verb": "create", "what": {"material": "fire"}}, Vector2(400, 360))
	var ast := {"verb": "move", "what": {"target_of": {"ref": "chosen"}}, "to": {"target_of": {"ref": "chosen"}}}
	check(SpellGrammar.cast_picks(ast).size() == 2, "Each Chosen in a spell is picked separately")
	var both := sim.cast(p, with_chosen(ast, [pull.id, fire.id]), Vector2.ZERO)
	check(both.spell.target() == stone and both.spell.destination() == fire.spell.what,
		"Each Chosen means the spell picked for it")
	var nested := {"verb": "create", "what": {"spell": DESTROY_CHOSEN}}
	check(SpellGrammar.cast_picks(nested).size() == 1, "A created spell's Chosen is picked when casting its creator")


func test_target_of_selector() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var stone := sim.spawn(Materials.make("stone", Vector2(500, 360)))
	var a := sim.spawn(Materials.make_player(Vector2(900, 150)))
	var b := sim.spawn(Materials.make_player(Vector2(900, 650)))
	var selector := sim.cast(p, {"verb": "select", "qualifier": "player"}, Vector2.ZERO)
	var ast := {"verb": "move", "what": {"closest": "stone"}, "to": {"target_of": {"ref": "chosen"}}}
	check(SpellGrammar.to_text(ast) == "Move (Closest Stone) to (Target of Chosen).", "Target of reads as a noun")
	var mover := sim.cast(p, with_chosen(ast, [selector.id]), Vector2.ZERO)
	run(sim, 4)
	check(mover.spell.destination() == a and heading(stone).dot(stone.pos.direction_to(a.pos)) > 0.95,
		"Target of a selector is its pick")
	p.pos = Vector2(200, 650)
	run(sim, 2)
	check(mover.spell.destination() == b, "Target of is re-checked every tick")
	check(selector in sim.inventory(p), "Target of only looks; the selector stays in the inventory")


func test_target_of_move() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var stone := sim.spawn(Materials.make("stone", Vector2(700, 360)))
	var pull := sim.cast(p, {"verb": "move", "what": {"closest": "stone"}, "to": {"ref": "me"}}, Vector2.ZERO)
	sim.cast(p, with_chosen({"verb": "destroy", "what": {"target_of": {"ref": "chosen"}}}, [pull.id]), Vector2.ZERO)
	run(sim, 2 * Simulation.TICK_RATE)
	check(stone.dead, "Target of a Move is the object it moves")


func test_target_of_create() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var stone := sim.spawn(Materials.make("stone", Vector2(700, 600)))
	var maker := sim.cast(p, {"verb": "create", "what": {"material": "wood"}}, Vector2(400, 360))
	var first: WorldObject = maker.spell.created[0]
	var ast := {"verb": "move", "what": {"closest": "stone"}, "to": {"target_of": {"ref": "chosen"}}}
	var mover := sim.cast(p, with_chosen(ast, [maker.id]), Vector2.ZERO)
	check(mover.spell.destination() == first, "Target of a Create is its product")
	run(sim, 3 * Simulation.TICK_RATE)
	check(maker.spell.created.size() > 1 and mover.spell.destination() == maker.spell.created.back(),
		"...its newest product, as it keeps creating")
	var warden := sim.cast(p, FIRE_WARDEN, Vector2(400, 360))
	var look := sim.cast(p, with_chosen({"verb": "destroy", "what": {"target_of": {"ref": "chosen"}}}, [warden.id]), Vector2.ZERO)
	var made: WorldObject = warden.spell.what
	check(made.spell != null and look.spell.target() == made, "Target of a Create Spell is the spell it made")


func test_target_of_nests() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var dummy := sim.spawn(Materials.make_player(Vector2(900, 360)))
	var selector := sim.cast(p, {"verb": "select", "qualifier": "player"}, Vector2.ZERO)
	var aimer := sim.cast(p, with_chosen({"verb": "destroy", "what": {"target_of": {"ref": "chosen"}}}, [selector.id]), Vector2.ZERO)
	check(aimer.spell.target() == dummy, "Target of a held selector is its pick")
	var ast := {"verb": "destroy", "what": {"target_of": {"target_of": {"ref": "chosen"}}}}
	check(SpellGrammar.validate(ast) == "", "Target of nests")
	var outer := sim.cast(p, with_chosen(ast, [aimer.id]), Vector2.ZERO)
	check(outer.spell.target() == null, "Target of (Target of a Destroy) is the target's own target: none here")
	var via_selector := sim.cast(p, with_chosen({"verb": "destroy", "what": {"target_of": {"ref": "chosen"}}}, [aimer.id]), Vector2.ZERO)
	check(via_selector.spell.target() == dummy, "Target of a spell following a selector is that selector's pick")


func test_target_of_non_spell() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	sim.spawn(Materials.make("fire", Vector2(500, 360)))
	var host := sim.cast(p, {"verb": "destroy", "what": {"target_of": {"closest": "fire"}}}, Vector2.ZERO)
	run(sim, 5)
	check(not host.dead and count(sim, "fire") == 1, "Target of something that isn't a spell is nothing: the spell waits")


func test_spells_wait_for_a_target() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var host := sim.cast(p, {"verb": "destroy", "what": {"closest": "fire"}}, Vector2.ZERO)
	run(sim, Simulation.TICK_RATE)
	check(not host.dead, "With nothing to destroy, Destroy waits")
	var fire := sim.spawn(Materials.make("fire", Vector2(600, 200)))
	run(sim, 4)
	check(fire.dead and host.dead, "...then destroys what turns up, and ends")

	var dummy := sim.spawn(Materials.make_player(Vector2(900, 360)))
	var pull := sim.cast(p, {"verb": "move", "what": {"closest": "stone"}, "to": {"ref": "me"}}, Vector2.ZERO)
	run(sim, 5)
	check(not pull.dead, "With nothing to move, Move waits")
	var stone := sim.spawn(Materials.make("stone", Vector2(600, 360)))
	run(sim, 2)
	check(heading(stone).dot(stone.pos.direction_to(p.pos)) > 0.95, "...then moves what turns up")
	stone.dead = true
	var next := sim.spawn(Materials.make("stone", Vector2(600, 600)))
	run(sim, 3)
	check(not pull.dead and heading(next).dot(next.pos.direction_to(p.pos)) > 0.95,
		"If what it moves is destroyed, Move looks for another")
	check(dummy.health == dummy.max_health, "(nothing else was touched)")


func test_destroy_follows_selector_to_next_pick() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	sim.spawn(Materials.make("fire", Vector2(300, 360)))
	sim.spawn(Materials.make("fire", Vector2(400, 360)))
	var selector := sim.cast(p, {"verb": "select", "qualifier": "fire"}, Vector2.ZERO)
	var turret := sim.cast(p, with_chosen({"verb": "destroy", "what": {"target_of": {"ref": "chosen"}}}, [selector.id]), Vector2.ZERO)
	run(sim, 10)
	check(count(sim, "fire") == 0 and not turret.dead, "Destroy (Target of Chosen) destroys one pick after another, then waits")


func test_this_and_there() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var wood := sim.spawn(Materials.make("wood", Vector2(500, 200)))
	var ast := {"verb": "move", "what": {"ref": "this"}, "to": {"ref": "there"}}
	var picks := SpellGrammar.cast_picks(ast)
	check(picks.size() == 2 and picks[0]["ref"] == "this" and picks[1]["ref"] == "there", "This and There are picked in reading order")
	picks[0]["id"] = wood.id
	picks[1]["at"] = Vector2(500, 600)
	var host := sim.cast(p, ast, Vector2.ZERO)
	var place := host.spell.destination()
	check(place != null and place.has_tag("place") and place.pos == Vector2(500, 600), "There becomes a place in the world")
	check(not place.matches("thing"), "A place isn't a Thing")
	run(sim, 4 * Simulation.TICK_RATE)
	check(wood.pos.distance_to(Vector2(500, 600)) < wood.radius + 8.0, "This moves to There")
	run(sim, 2)
	check(host.dead and place.dead, "A place ends with the spell that made it")


func test_aimed() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var near := sim.spawn(Materials.make("wood", Vector2(400, 360)))
	sim.spawn(Materials.make("wood", Vector2(700, 360)))
	sim.spawn(Materials.make("wood", Vector2(400, 200)))
	var host := sim.cast(p, {"verb": "destroy", "what": {"ref": "aimed"}}, Vector2(1000, 360))
	check(host.spell.target() == near, "Aimed is the first Thing along the aim")


func test_pickers() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var near := sim.spawn(Materials.make("wood", Vector2(300, 360)))
	var far := sim.spawn(Materials.make("wood", Vector2(1000, 360)))
	sim.spawn(Materials.make("wood", Vector2(600, 360)))
	var farthest := sim.cast(p, {"verb": "mark", "what": {"farthest": "wood"}}, Vector2.ZERO)
	check(farthest.spell.target() == far, "Farthest picks the farthest")
	var all := sim.cast(p, {"verb": "mark", "what": {"all": "wood"}}, Vector2.ZERO)
	check(all.spell.targets().size() == 3, "All picks every match")
	var near_one := sim.cast(p, {"verb": "mark", "what": {"all": "wood", "within": 3}}, Vector2.ZERO)
	check(near_one.spell.targets() == [near], "Within limits the distance")
	var rand := sim.cast(p, {"verb": "select", "what": {"random": "wood"}}, Vector2.ZERO)
	var first := rand.spell.target()
	run(sim, 5)
	check(first != null and rand.spell.target() == first, "A held Random sticks with its pick while it fits")
	var to := sim.cast(p, {"verb": "mark", "what": {"closest": "wood", "from": {"ref": "this", "id": far.id}}}, Vector2.ZERO)
	check(to.spell.target() == far, "Closest ... to X measures from X")
	check(SpellGrammar.to_text({"verb": "mark", "what": {"all": "fire", "within": 3, "from": {"ref": "there"}}})
		== "Mark (All Fire within 3 m of There).", "Pickers read as words")


func test_all_costs_per_target() -> void:
	var w := world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	for i in 3:
		sim.spawn(Materials.make("stone", Vector2(600, 200 + i * 150)))
	var one := sim.cast(p, {"verb": "destroy", "what": {"closest": "stone"}}, Vector2.ZERO)
	var three := sim.cast(p, {"verb": "destroy", "what": {"all": "stone"}}, Vector2.ZERO)
	var before_one: float = one.spell.mana["violet"]
	var before_three: float = three.spell.mana["violet"]
	run(sim, 1)
	check(is_equal_approx((before_three - three.spell.mana["violet"]), 3.0 * (before_one - one.spell.mana["violet"])),
		"Acting on three targets drains three times as much")


func test_adjectives() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var still := sim.spawn(Materials.make("stone", Vector2(400, 360)))
	var rolling := sim.spawn(Materials.make("stone", Vector2(700, 200)))
	sim.cast(p, {"verb": "move", "what": {"farthest": "stone"}, "to": {"ref": "me"}}, Vector2.ZERO)
	run(sim, 3)
	var moving := sim.cast(p, {"verb": "mark", "what": {"closest": "stone", "adj": ["moving"]}}, Vector2.ZERO)
	check(moving.spell.target() == rolling, "Moving picks what is moving")
	run(sim, 1)
	check(still.marks.is_empty() and rolling.marks.has(p.id), "Mark marks its target")
	var marked := sim.cast(p, {"verb": "destroy", "what": {"all": "thing", "adj": ["marked"]}}, Vector2.ZERO)
	check(marked.spell.targets() == [rolling], "Marked picks what the caster marked")
	var wall := sim.cast(p, {"verb": "create", "what": {"material": "wood"}}, Vector2(200, 100))
	var dummy := sim.spawn(Materials.make_player(Vector2(1000, 600)))
	var mine := sim.cast(p, {"verb": "mark", "what": {"all": "thing", "adj": ["mine"]}}, Vector2.ZERO)
	check(mine.spell.targets() == [wall.spell.what], "Mine picks what the caster's spells made")
	var theirs := sim.cast(p, {"verb": "mark", "what": {"all": "player", "adj": ["theirs"]}}, Vector2.ZERO)
	check(theirs.spell.targets() == [dummy], "Theirs picks what is someone else's")
	still.statuses["burning"] = -1
	var burning := sim.cast(p, {"verb": "mark", "what": {"all": "thing", "adj": ["burning"]}}, Vector2.ZERO)
	check(burning.spell.targets() == [still], "Burning picks what burns")


func test_relations() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var wall := sim.cast(p, {"verb": "create", "what": {"material": "wood"}}, Vector2(600, 360))
	run(sim, 3 * Simulation.TICK_RATE)
	var ask := func(noun: Dictionary) -> Array[WorldObject]:
		return sim.cast(p, with_chosen({"verb": "mark", "what": noun}, [wall.id]), Vector2.ZERO).spell.targets()
	check(ask.call({"products_of": {"ref": "chosen"}}) == wall.spell.created, "Products of is everything a Create made")
	check(ask.call({"caster_of": {"ref": "chosen"}}) == [p], "Caster of is who cast the spell")
	var first: WorldObject = wall.spell.created[0]
	var maker := sim.cast(p, {"verb": "destroy", "what": {"maker_of": {"ref": "this", "id": first.id}}}, Vector2.ZERO)
	check(maker.spell.target() == wall, "Maker of is the spell that made it")
	run(sim, 3)
	check(wall.dead and not first.dead, "Destroying the maker leaves what it made")


func test_create_at() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var ast := {"verb": "create", "what": {"material": "fire"}, "at": {"ref": "there", "at": Vector2(900, 200)}}
	check(SpellGrammar.to_text(ast) == "Create Fire at There.", "Create at reads as words")
	var host := sim.cast(p, ast, Vector2(900, 200))
	check(host.spell.what.pos.distance_to(Vector2(900, 200)) < 1.0, "Create at starts its line there")


func test_create_at_aimed_goes_in_front() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var wood := sim.spawn(Materials.make("wood", Vector2(600, 360)))
	var host := sim.cast(p, {"verb": "create", "what": {"material": "fire"}, "at": {"ref": "aimed"}}, Vector2(1000, 360))
	var first: WorldObject = host.spell.what
	check(first.pos.x < wood.pos.x and is_equal_approx(first.pos.distance_to(wood.pos), wood.radius + 14.0),
		"Create at a Thing puts the first object right in front of it, touching it")
	run(sim, 4 * Simulation.TICK_RATE)
	check(wood.dead, "...so fire created at wood sets it burning")
	var made := host.spell.created
	var reach := Spell.CREATE_SEARCH_RINGS * 14.0 + 0.1
	var near := func(o: WorldObject) -> bool: return o.pos.distance_to(first.pos) <= reach
	check(made.size() > 1 and made.all(near), "The rest gather in the closest free spots around it")


## The Juggle as casting sends it: slots copied in, the second using It.
const JUGGLE := {"verb": "alternate",
	"first": {"slot": 4, "spell": {"verb": "move", "what": {"closest": "stone"}, "to": {"ref": "me"}}},
	"second": {"slot": 5, "spell": {"verb": "move", "what": {"ref": "it"}, "to": {"closest": "player"}}}}


func test_alternate() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var stone := sim.spawn(Materials.make("stone", Vector2(450, 360)))
	var dummy := sim.spawn(Materials.make_player(Vector2(1000, 360)))
	check(SpellGrammar.to_text(JUGGLE)
		== "Alternate [Move (Closest Stone) to Me] [Move It to (Closest Player)].", "Alternate reads as words")
	check(SpellGrammar.blocks(JUGGLE).size() == 9, "Its words are its own plus both spells'")
	var alt := sim.cast(p, JUGGLE, Vector2.ZERO)
	var pull: WorldObject = alt.spell._sub
	check(pull != null and pull.spell.parent == alt and not pull in sim.inventory(p),
		"The first spell runs attached to the Alternate, not in the inventory")
	check(pull.spell.it.is_empty(), "On its first turn It means nothing yet")
	run(sim, 3 * Simulation.TICK_RATE)
	var throw: WorldObject = alt.spell._sub
	check(pull.dead and throw != pull and throw.spell.ast == JUGGLE["second"]["spell"],
		"When the first is done, the second takes its turn")
	check(throw.spell.it == [stone], "The second spell's It is what the first acted on")
	run(sim, 2)
	check(heading(stone).dot(stone.pos.direction_to(dummy.pos)) > 0.9, "...so it throws the pulled stone")
	run(sim, 3 * Simulation.TICK_RATE)
	check(alt.spell._sub.spell.ast == JUGGLE["first"]["spell"], "Then the first goes again")
	check(alt.spell._sub.spell.it == [stone], "...with its own It: what the second acted on")
	alt.health = 0
	run(sim, 2)
	check(alt.spell._sub.dead, "The spells end with their Alternate")


func test_alternate_turns_are_capped() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var ast := {"verb": "alternate", "first": {"slot": 0, "spell": {"verb": "create", "what": {"material": "fire"}}},
			"second": {"slot": 1, "spell": {"verb": "create", "what": {"material": "water"}}}}
	var alt := sim.cast(p, ast, Vector2(600, 360))
	run(sim, Spell.ALTERNATE_TICKS + 1)
	check(alt.spell._sub.spell.ast == ast["second"]["spell"], "A spell that never finishes still hands over after its turn")


func test_alternate_slots() -> void:
	var slots := [
		{"verb": "move", "what": {"closest": "stone"}, "to": {"ref": "me"}},
		{"verb": "alternate", "first": {"slot": 0}, "second": {"slot": 2}},
		{"verb": "alternate", "first": {"slot": 1}, "second": {"slot": 0}},
	]
	var full := SpellGrammar.embed_slots(slots[1], slots, [1])
	check(full["first"]["spell"] == slots[0], "A slot's spell is copied in when casting")
	check(SpellGrammar.to_text(slots[1]) == "Alternate [spell 1] [spell 3].", "Before that it reads as slot numbers")
	check(SpellGrammar.validate(full) != "", "A slot that leads back to the Alternate itself is rejected")
	check(SpellGrammar.validate(SpellGrammar.embed_slots(slots[0], slots, [0])) == "", "(an ordinary slot is fine)")
	var preset := SpellGrammar.embed_slots(Sandbox.PRESETS[1], Sandbox.PRESETS, [1])
	check(SpellGrammar.to_text(preset)
		== "Alternate [Move (Closest Stone) to Me] [Move (Closest Stone) to (Closest Player)].", "The Juggle preset uses slots 5 and 6")


func test_alternate_takes_attached_spell() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var held := sim.cast(p, {"verb": "select", "what": {"closest": "player"}}, Vector2.ZERO)
	var mana_before: float = held.spell.mana["violet"]
	var ast := {"verb": "alternate", "first": {"ref": "chosen", "id": held.id},
			"second": {"slot": 0, "spell": {"verb": "create", "what": {"material": "fire"}}}}
	check(SpellGrammar.to_text(ast) == "Alternate [Chosen] [Create Fire].", "Chosen reads as an argument")
	check(SpellGrammar.cast_picks(ast).size() == 1, "The attached spell is picked when casting")
	var alt := sim.cast(p, ast, Vector2(600, 360))
	check(held.spell.parent == alt and not held in sim.inventory(p), "It takes the attached spell over")
	check(alt.spell._sub == held and not held.spell.paused, "...and runs it on its turn")
	run(sim, Spell.ALTERNATE_TICKS + 1)
	check(held.spell.paused and not held.dead, "Between its turns it waits, paused")
	var paused_mana: float = held.spell.mana["violet"]
	run(sim, 10)
	check(held.spell.mana["violet"] == paused_mana, "...using no mana")
	check(paused_mana < mana_before, "On its turns it pays its own way")
	run(sim, Spell.ALTERNATE_TICKS)
	check(alt.spell._sub == held and not held.spell.paused, "Then it gets its turn again")
	held.health = 0
	run(sim, Spell.ALTERNATE_TICKS + 2)
	check(not alt.dead and alt.spell._sub.spell.ast["verb"] == "create", "If it ends, the Alternate runs the other side")
	alt.health = 0
	run(sim, 2)
	check(alt.spell._sub.dead, "The spells end with their Alternate")


func test_up_to() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var ast := {"verb": "destroy", "what": {"all": "fire"}, "adverbs": {"up_to": 2}}
	check(SpellGrammar.to_text(ast) == "Destroy (All Fire), up to 2.", "Up to reads as words")
	check(SpellGrammar.blocks(ast).size() == 4, "Up to is a word")
	for x in [300, 500, 700, 900]:
		sim.spawn(Materials.make("fire", Vector2(x, 200)))
	var host := sim.cast(p, ast, Vector2.ZERO)
	check(host.spell.targets().size() == 2, "Up to 2 acts on the 2 nearest at a time")
	run(sim, 10)
	check(count(sim, "fire") == 2 and host.dead, "...and ends once it has destroyed 2")

	var wood := sim.cast(p, {"verb": "create", "what": {"material": "wood"}, "adverbs": {"up_to": 3}}, Vector2(600, 600))
	run(sim, 10 * Simulation.TICK_RATE)
	check(wood.spell.created.size() == 3 and not wood.dead, "Create up to 3 makes 3, then only sustains them")

	var warden := {"verb": "create", "what": {"spell": {"verb": "select", "what": {"closest": "player"}}}, "adverbs": {"up_to": 5}}
	check(SpellGrammar.spells_created(warden) == 5, "Create Spell up to 5 makes 5 spells")
	check(same(SpellGrammar.payload(warden), {"violet": 5 * 0.4 * 60.0}), "...and carries mana for 5")

	sim.spawn(Materials.make("stone", Vector2(400, 300)))
	sim.spawn(Materials.make("stone", Vector2(400, 420)))
	var pull := sim.cast(p, {"verb": "move", "what": {"all": "stone"}, "to": {"ref": "me"}, "adverbs": {"up_to": 1}}, Vector2.ZERO)
	check(pull.spell.targets().size() == 1, "Move up to 1 moves one")

	var marks := sim.cast(p, {"verb": "mark", "what": {"all": "wood"}, "adverbs": {"up_to": 2}}, Vector2.ZERO)
	run(sim, 1)
	check(sim.objects.filter(func(o: WorldObject) -> bool: return o.marks.has(p.id)).size() == 2 and marks.dead,
		"Mark up to 2 marks two")

	var turns := sim.cast(p, JUGGLE.merged({"adverbs": {"up_to": 2}}), Vector2.ZERO)
	run(sim, 2 * Spell.ALTERNATE_TICKS + 2)
	check(turns.dead, "Alternate up to 2 runs two turns, then ends")
	check(SpellGrammar.validate({"verb": "mark", "what": {"ref": "me"}, "adverbs": {"up_to": 7}}) != "", "Up to takes a listed number")


func test_here() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var stone := sim.spawn(Materials.make("stone", Vector2(600, 360)))
	var pull := sim.cast(p, {"verb": "move", "what": {"closest": "stone"}, "to": {"ref": "here"}}, Vector2.ZERO)
	check(pull.spell.destination() == pull, "Here is the spell's own location")
	run(sim, 3)
	check(heading(stone).dot(stone.pos.direction_to(p.pos)) > 0.95, "...which, for a spell you cast, is where you are")
	var maker := sim.cast(p, {"verb": "create", "what": {"spell": {"verb": "create", "what": {"material": "fire"}, "at": {"ref": "here"}}}}, Vector2(400, 600))
	var made: WorldObject = maker.spell.what
	# Right at it, or in the nearest free spot (its spot overlaps the caster).
	check(made.spell.what.pos.distance_to(made.pos) <= 14.01, "A created spell's Here is where it sits")


func test_drop() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var held := sim.cast(p, {"verb": "select", "what": {"closest": "player"}}, Vector2.ZERO)
	var other := sim.spawn(Materials.make_player(Vector2(900, 360)))
	sim.step({0: {"drop": held.id}})
	check(not held in sim.inventory(p) and not held.spell.anchored, "Dropping a spell detaches it")
	var at := held.pos
	sim.step({0: {"move": Vector2.DOWN}})
	sim.step({0: {"move": Vector2.DOWN}})
	check(held.pos == at and p.pos != at, "A dropped spell stays where it was dropped")
	check(held.spell.target() == p, "...and, no longer attached to its caster, can pick them")
	var other_spell := sim.cast(p, {"verb": "select", "what": {"closest": "fire"}}, Vector2.ZERO)
	sim.step({0: {"drop": other.id}})
	check(other_spell in sim.inventory(p), "Dropping something that isn't an attached spell does nothing")


## Throws a stone at a fresh dummy `gap` px away; returns the damage done.
func throw_damage(gap: float) -> float:
	var w := spell_world()
	var sim: Simulation = w[0]
	var dummy := sim.spawn(Materials.make_player(Vector2(400 + gap, 300)))
	sim.spawn(Materials.make("stone", Vector2(400, 300)))
	sim.cast(w[1], {"verb": "move", "what": {"closest": "stone"}, "to": {"ref": "this", "id": dummy.id}}, Vector2.ZERO)
	run(sim, 80)
	return dummy.max_health - dummy.health


func test_impact_damage_is_consistent() -> void:
	var damage := []
	for gap in [300, 302, 304, 306, 308, 310, 312]:
		damage.append(throw_damage(gap))
	check(damage.all(func(d: float) -> bool: return is_equal_approx(d, damage[0])) and damage[0] > 0.0,
		"A thrown stone always hits for the same damage, wherever it starts (got %s)" % str(damage))


func test_impact_once_per_hit() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var dummy := sim.spawn(Materials.make_player(Vector2(700, 300)))
	sim.spawn(Materials.make("stone", Vector2(400, 300)))
	var sel := sim.cast(p, {"verb": "select", "what": {"closest": "player"}}, Vector2.ZERO)
	sim.cast(p, with_chosen({"verb": "move", "what": {"closest": "stone"}, "to": {"target_of": {"ref": "chosen"}}}, [sel.id]), Vector2.ZERO)
	run(sim, 3 * Simulation.TICK_RATE)
	var after_hit := dummy.health
	check(after_hit < dummy.max_health, "A chasing stone hits its target")
	run(sim, 2 * Simulation.TICK_RATE)
	check(dummy.health == after_hit, "...once: pressing against it doesn't keep hurting")
	dummy.pos = Vector2(1000, 300)  # it gets away; the stone catches up and hits again
	run(sim, 4 * Simulation.TICK_RATE)
	check(dummy.health < after_hit, "Catching up after a gap is a new hit")


func test_impact_hurts_both_and_spares_walkers() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var thrown := sim.spawn(Materials.make("stone", Vector2(400, 300)))
	var still := sim.spawn(Materials.make("stone", Vector2(700, 300)))
	sim.cast(p, {"verb": "move", "what": {"ref": "this", "id": thrown.id}, "to": {"ref": "this", "id": still.id}}, Vector2.ZERO)
	run(sim, 60)
	check(thrown.health < thrown.max_health and still.health < still.max_health, "Stone hitting stone damages both")
	var wall := sim.spawn(Materials.make("wood", Vector2(p.pos.x + 60, p.pos.y)))
	for i in 20:
		sim.step({0: {"move": Vector2.RIGHT}})
	check(wall.health == wall.max_health and p.health == p.max_health, "Walking into a wall hurts nothing")


func test_parse_round_trip() -> void:
	var spells: Array = Sandbox.PRESETS.duplicate(true)
	spells.append_array([
		{"verb": "destroy", "what": {"all": "fire", "within": 3, "from": {"ref": "there"}}, "adverbs": {"up_to": 2}},
		{"verb": "move", "what": {"closest": "stone", "adj": ["moving", "mine"], "from": {"ref": "this"}}, "to": {"ref": "here"}},
		{"verb": "mark", "what": {"caster_of": {"target_of": {"ref": "chosen"}}}},
		{"verb": "create", "what": {"spell": {"verb": "create", "what": {"material": "fire"}, "at": {"ref": "here"}}}, "adverbs": {"up_to": 5}},
		{"verb": "create", "what": {"material": "water"}, "at": {"farthest": "player", "within": 5}},
		{"verb": "alternate", "first": {"ref": "chosen"}, "second": {"slot": 9}},
		{"verb": "select", "what": {"random": "thing", "adj": ["burning"]}},
		{"verb": "destroy", "what": {"products_of": {"maker_of": {"ref": "aimed"}}}},
	])
	for ast in spells:
		var text := SpellGrammar.to_text(ast)
		var back := SpellParser.parse(text)
		check(back.get("ast") == ast, "\"%s\" reads back as the same spell (got %s)" % [text, back])


func test_parse_typed() -> void:
	var cases := {
		"move closest stone to me": "Move (Closest Stone) to Me.",
		"mo cl st to me": "Move (Closest Stone) to Me.",
		"destroy all fires within 3 of there, up to 2": "Destroy (All Fire within 3 m of There), up to 2.",
		"d all fire within 3m up 2": "Destroy (All Fire within 3 m), up to 2.",
		"move closest stone to closest player to me": "Move (Closest Stone) to (Closest Player to Me).",
		"create spell destroy closest fire": "Create Spell [Destroy (Closest Fire)].",
		"create fire at aimed": "Create Fire at Aimed.",
		"closest player": "Hold (Closest Player).",
		"alternate 5 6": "Alternate [spell 5] [spell 6].",
		"alt chosen 0": "Alternate [Chosen] [spell 0].",
		"move closest stone to target of chosen": "Move (Closest Stone) to (Target of Chosen).",
		"mark all moving mine things": "Mark (All Moving Mine Thing).",
		"MOVE This to THERE.": "Move This to There.",
		"move stone to me": "Move (Closest Stone) to Me.",
		"move stone me": "Move (Closest Stone) to Me.",
		"destroy fire": "Destroy (Closest Fire).",
		"mark moving stones": "Mark (Closest Moving Stone).",
		"move stone to player": "Move (Closest Stone) to (Closest Player).",
		"move all stones within 2 of me to there": "Move (All Stone within 2 m of Me) to There.",
		# What a verb acts on defaults to This, where Move moves it to There.
		"destroy": "Destroy This.",
		"mark, up to 2": "Mark This, up to 2.",
		"move": "Move This to There.",
		"move stone": "Move (Closest Stone) to There.",
		"move to me": "Move This to Me.",
		"hold": "Hold This.",
		# Slips are forgiven when nothing reads without them.
		"mvoe stoen to me": "Move (Closest Stone) to Me.",
		"destory fier": "Destroy (Closest Fire).",
		"craete wod": "Create Wood.",
		"move ths to there": "Move This to There.",
		"mark all movng stones": "Mark (All Moving Stone).",
		# Everyday words, and a, an, the.
		"make a fire": "Create Fire.",
		"kill the nearest rock": "Destroy (Closest Stone).",
		"pull stone": "Move (Closest Stone) to Me.",
		"bring the furthest player": "Move (Farthest Player) to Me.",
		"grab every rock": "Hold (All Stone).",
		"tag everything within 3 of me": "Mark (All Thing within 3 m of Me).",
		"put the rock there": "Move (Closest Stone) to There.",
	}
	for typed in cases:
		var r := SpellParser.parse(typed)
		var got: String = SpellGrammar.to_text(r["ast"]) if r.has("ast") else "error: " + r["error"]
		check(got == cases[typed], "\"%s\" reads as %s (got %s)" % [typed, cases[typed], got])
	check(SpellParser.parse("move all").has("error"), "An unfinished spell is an error")
	check("stone" in SpellParser.parse("move all").get("error", ""), "...saying what could come next")
	check(SpellParser.parse("move banana to me").has("error"), "Words that don't fit are an error")
	check(SpellParser.parse("alternate 2 2").has("ast"), "Slots aren't checked until casting (they're copied in then)")


func test_suggest() -> void:
	check(SpellParser.suggest("").slice(0, 3) == ["move", "create", "destroy"], "An empty line suggests verbs first")
	check(SpellParser.suggest("move closest st") == ["stone"], "A partial word suggests what it could be")
	check(SpellParser.suggest("move closest stone ").slice(0, 2) == ["within", "to"], "After a picker: its options, then Move's to")
	check(SpellParser.suggest("destroy closest fire ").has("up"), "A finished spell suggests adverbs")
	check(SpellParser.suggest("create ") == ["fire", "water", "wood", "stone", "spell"], "Create suggests what to create")
	check(SpellParser.suggest("move banana ").is_empty(), "Nothing fits after a mistake")
	check(SpellParser.suggest("move closest ").slice(0, 2) == ["stone", "fire"], "After a picker: things before adjectives")
	check(SpellParser.suggest("destroy fier") == ["fire"], "A slip suggests the word it nearly is")
	check(SpellParser.suggest("destroy wa") == ["water"], "A thing on its own is suggested too")
	check(SpellParser.suggest("destory wa") == ["water"], "A slip earlier on still gets suggestions")
	check(not SpellParser._slip("me", "mine") and not SpellParser._slip("tone", "stone"),
			"Short words and wrong first letters aren't slips")
	for text in ["", "m", "move ", "move closest ", "destroy all fire within "]:
		check(SpellParser.suggest(text).size() <= 5, "Never more than five suggestions")


## Every [popup, id] a SpellChips row offers, menus and submenus, in order.
func chip_actions(chips: SpellChips) -> Array:
	var out := []
	for c in chips.get_children():
		if c is MenuButton:
			_menu_actions(c.get_popup(), out)
	return out


func _menu_actions(popup: PopupMenu, out: Array) -> void:
	check(popup.item_count <= 5, "A word's menu has at most five entries")
	for i in popup.item_count:
		var sub := popup.get_item_submenu_node(i)
		if sub != null:
			_menu_actions(sub, out)
		else:
			out.append([popup, popup.get_item_id(i)])


func test_chip_menus() -> void:
	var spells: Array = Sandbox.PRESETS.duplicate(true)
	spells.append_array([
		{"verb": "destroy", "what": {"all": "fire", "adj": ["moving"], "within": 3, "from": {"ref": "there"}}, "adverbs": {"up_to": 2}},
		{"verb": "create", "what": {"material": "water"}, "at": {"caster_of": {"ref": "chosen"}}},
		{"verb": "alternate", "first": {"ref": "chosen"}, "second": {"slot": 9}},
		{"verb": "mark", "what": {"random": "mana", "adj": ["mine", "theirs", "marked", "burning"]}},
	])
	var tried := 0
	for spell in spells:
		var count := 0
		var chips := SpellChips.new()
		root.add_child(chips)
		chips.show_spell(spell.duplicate(true))
		count = chip_actions(chips).size()
		chips.free()
		for k in count:
			# Each choice, on a fresh copy: the spell must stay a spell.
			var copy: Dictionary = spell.duplicate(true)
			var fresh := SpellChips.new()
			root.add_child(fresh)
			fresh.show_spell(copy)
			var action: Array = chip_actions(fresh)[k]
			action[0].id_pressed.emit(action[1])
			var err := SpellGrammar.validate(copy, false)
			check(err == "", "Choosing from a word's menu keeps \"%s\" a spell (got %s: %s)" % [
				SpellGrammar.to_text(spell), SpellGrammar.to_text(copy), err])
			fresh.free()
			tried += 1
	check(tried > 200, "(tried %d menu choices)" % tried)


func test_preview() -> void:
	var w := spell_world()
	var sim: Simulation = w[0]
	var p: WorldObject = w[1]
	var near := sim.spawn(Materials.make("stone", Vector2(300, 360)))
	sim.spawn(Materials.make("stone", Vector2(900, 360)))
	var dummy := sim.spawn(Materials.make_player(Vector2(600, 600)))
	var ast: Dictionary = SpellParser.parse("move all stones within 3 of me to closest player")["ast"]
	var before := sim.objects.size()
	var found := SpellPreview.targets(sim, p, ast, Vector2(600, 360))
	check(found["what"] == [near] and found["to"] == [dummy], "The preview finds what the spell would act on")
	check(sim.objects.size() == before and sim.tick == 0, "...without casting anything")
	check(SpellPreview.describe(ast, found) == "acts on 1 thing now", "It says how much")
	var none: Dictionary = SpellParser.parse("destroy closest fire")["ast"]
	check(SpellPreview.describe(none, SpellPreview.targets(sim, p, none, Vector2.ZERO)).contains("wait"),
		"...or that the spell would wait")
	var picked: Dictionary = SpellParser.parse("destroy this")["ast"]
	check(SpellPreview.describe(picked, SpellPreview.targets(sim, p, picked, Vector2.ZERO)) == "",
		"...and nothing when it can't know before casting (nothing is under the mouse for This)")
	check(SpellPreview.targets(sim, p, picked, near.pos)["what"] == [near], "The first This is under the mouse")
	var there: Dictionary = SpellParser.parse("move stone to there")["ast"]
	check(SpellPreview.targets(sim, p, there, Vector2(50, 60))["to"] == [Vector2(50, 60)],
		"The first There is the mouse")
	var second: Dictionary = SpellParser.parse("move this to there")["ast"]
	check(SpellPreview.targets(sim, p, second, near.pos)["to"] == null, "A second pick isn't known")
	var chosen: Dictionary = SpellParser.parse("move chosen to there")["ast"]
	check(SpellPreview.targets(sim, p, chosen, near.pos)["to"] == null, "...even after a Chosen")


func test_spellbook_saves() -> void:
	var path := "user://test_spellbook.txt"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(Spellbook.load_slots(path) == Sandbox.PRESETS, "With nothing saved, the slots are the presets")
	var slots: Array = Sandbox.PRESETS.duplicate(true)
	slots[2] = SpellParser.parse("destroy all fires within 3 of there, up to 2")["ast"]
	slots[4] = {"verb": "nonsense"}
	Spellbook.save_slots(slots, path)
	var loaded := Spellbook.load_slots(path)
	check(loaded[2] == slots[2], "A saved spell comes back exactly")
	check(loaded[4] == Sandbox.PRESETS[4], "A slot that isn't a spell falls back to its preset")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_deterministic() -> void:
	check(_replay() == _replay(), "Same inputs give the same world")


func _replay() -> String:
	var sim := Simulation.new(42)
	var player := Sandbox.build(sim)
	for i in 400:
		var cmd := {"move": Vector2(cos(i * 0.05), sin(i * 0.03)), "aim": Vector2(640, 360)}
		if i % 40 == 0:
			var n: int = (i / 40) % Sandbox.PRESETS.size()
			cmd["cast"] = SpellGrammar.embed_slots(Sandbox.PRESETS[n], Sandbox.PRESETS, [n])
		sim.step({player.controller: cmd})
	var state := ""
	for o in sim.objects:
		state += "%d %s %s %.3f|" % [o.id, o.material, o.pos, o.health]
	return state


func test_quick_cast_keys() -> void:
	var quick := QuickCast.new()
	root.add_child(quick)
	var cast := []
	quick.cast.connect(func(ast: Dictionary) -> void: cast.append(ast))
	quick.open()
	quick.input.set_text("de")
	quick.submit()
	check(cast == [{"verb": "destroy", "what": {"ref": "this"}}] and not quick.visible,
		"A click casts what's typed and closes the bar")
	quick.open()
	check(quick.input.field.placeholder_text.contains("de"), "The empty bar offers the last spell")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	quick._on_key(enter)
	check(cast.size() == 2 and cast[1] == cast[0], "Enter on the empty bar casts the last spell again")
	quick.free()


func test_cast_flow() -> void:
	var w := world()
	var stone := (w[0] as Simulation).spawn(Materials.make("stone", Vector2(300, 300)))
	var flow := CastFlow.new()
	flow.begin(SpellParser.parse("create fire")["ast"], Vector2(1, 2), null)
	check(not flow.busy() and flow.take() == {"ast": {"verb": "create", "what": {"material": "fire"}}, "aim": Vector2(1, 2)},
		"A spell with nothing to pick is ready at once")
	check(flow.take().is_empty(), "...once")
	flow.begin(SpellParser.parse("move this to there")["ast"], Vector2(300, 300), stone)
	check(flow.picking() == "there" and flow.pick_number() == 2 and flow.pick_count() == 2,
		"The first This is the thing under the mouse; There is asked for next")
	flow.begin(SpellParser.parse("destroy fire")["ast"], Vector2.ZERO, null)
	check(flow.spell()["verb"] == "move", "A second cast waits until the first is picked")
	flow.pick(Vector2(5, 6))
	var sent := flow.take()
	check(sent["ast"]["what"] == {"ref": "this", "id": stone.id} and sent["ast"]["to"] == {"ref": "there", "at": Vector2(5, 6)},
		"The picks are written into the spell sent")
	flow.begin(SpellParser.parse("move chosen to there")["ast"], Vector2(7, 8), null)
	check(flow.picking() == "chosen", "A first Chosen is asked for (only This and There come from the mouse)")
	flow.cancel()
	check(not flow.busy() and flow.take().is_empty(), "Cancelling sends nothing")
	flow.begin(SpellParser.parse("destroy this")["ast"], Vector2.ZERO, null)
	check(flow.picking() == "this", "With nothing under the mouse, This is asked for")


func test_every_script_compiles() -> void:
	var dirs := ["res://scripts"]
	while not dirs.is_empty():
		var dir: String = dirs.pop_back()
		for sub in DirAccess.get_directories_at(dir):
			dirs.append(dir.path_join(sub))
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".gd"):
				var script: GDScript = load(dir.path_join(file))
				check(script != null and script.can_instantiate(), "%s compiles" % file)


func test_parser_fuzz() -> void:
	var words: Array = SpellParser.VERB_WORDS + SpellParser.NOUN_WORDS + SpellParser.QUALIFIER_WORDS \
			+ SpellGrammar.ADJECTIVES + SpellParser.SYNONYMS.keys() + SpellParser.FILLERS \
			+ ["to", "of", "at", "within", "up", "3", "2", "5", ",", "(", ")", "[", "]", "mo", "st", "cl", "fier"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var read := 0
	var bad := []
	for n in 400:
		var text := ""
		for k in rng.randi_range(1, 7):
			text += words[rng.randi_range(0, words.size() - 1)] + " "
		var r := SpellParser.parse(text)
		SpellParser.suggest(text.strip_edges())
		if not r.has("ast"):
			continue
		read += 1
		var back := SpellParser.parse(SpellGrammar.to_text(r["ast"]))
		if SpellGrammar.validate(r["ast"], false) != "" or back.get("ast") != r["ast"]:
			bad.append(text)
	check(read > 15, "Random words sometimes read as spells (%d of 400)" % read)
	check(bad.is_empty(), "Every spell read from random words is valid and reads back the same: %s" % [bad.slice(0, 3)])
