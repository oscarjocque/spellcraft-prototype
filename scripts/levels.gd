class_name Levels
extends RefCounted
## The sandbox and six test levels. In 1-3 mana is real but plentiful: the
## player starts with their usual store and refills it from fountains, and
## each level needs more spellcraft than the last. In 4-6 the player starts
## with no mana and no wild crystals appear: what mana there is, and its
## colors, decide which words a solution can use.
##
##   1 Onto the pad   one spell, two picks:    Move (Closest Stone) to There
##   2 Clear the ring  pickers and away from:  Move (All Wood within 3 m of There) away from There
##   3 Firebreak      keep a house alive while fires creep in from all sides:
##                    a live tracker (Hold (All Fire), then Destroy (Target of
##                    Chosen)) does it in two casts; Destroy Fire by hand takes
##                    one every couple of seconds.
##   4 Only green     the pad again, with only green mana: Closest, This and
##                    Me are violet. Move Aimed to There is all green, so line
##                    the stone up between you and the pad first.
##   5 No violet      burn a barricade behind a stone wall: no Destroy. Create
##                    Fire at There takes red and one green word; there is
##                    exactly one green crystal.
##   6 Over the wall  douse three bonfires: too big to Destroy on the little
##                    violet there is, but water puts them out. Red and blue
##                    lie beyond a wall: spend the green and violet pulling
##                    crystals through it (mana passes through stone: Move This
##                    to Me), then Create Water at There, up to 1, for each.
##
## A level's state lives in a dictionary Main keeps: build fills it, step
## advances the level's own events (deterministically, from the simulation's
## tick and dice) and sets "status" and "result" ("", "won" or "lost").

const NAMES := ["Sandbox", "Level 1 · Onto the pad", "Level 2 · Clear the ring", "Level 3 · Firebreak",
	"Level 4 · Only green", "Level 5 · No violet", "Level 6 · Over the wall"]
const GOALS := [
	"Try anything. F2 goes to the levels.",
	"Get a stone onto the gold pad.  Hint: move stone to there, and click the pad.",
	"Get every log out of the gold ring.  Hint: Move … away from …, and All … within 3 m of There.",
	"Keep 2 of the house's 3 logs for 40 s; fires creep in from every side.  Hint: a held All keeps re-reading; Target of Chosen follows it.",
	"Get the stone onto the pad, with only green mana. F1 shows which words are green; Aimed is the first thing toward the mouse.",
	"Burn down the barricade behind the wall. There's no violet mana, so no Destroy.",
	"Put out the three bonfires. Water puts out fire; red and blue mana lie beyond the wall, and mana passes through stone.",
]
## Level 4: where the stone and pad sit (not in line with where you start).
const GREEN_STONE := Vector2(560, 250)
const GREEN_PAD := Vector2(1010, 470)
const WALL_X := 620.0
const BARRICADE := Vector2(920, 360)
const BONFIRES := [Vector2(330, 150), Vector2(420, 600), Vector2(500, 360)]
const PAD := Vector2(980, 360)
const PAD_RADIUS := 46.0
const RING := Vector2(760, 360)
const RING_RADIUS := 130.0
const HOUSE := Vector2(920, 360)
const FIRE_EVERY := 3 * Simulation.TICK_RATE
const FIRE_FROM := 300.0  # how far from the house fires appear
const FIRE_CREEP := 40.0  # pixels per second, toward the house
const HOLD_OUT := 40 * Simulation.TICK_RATE


## Fills `sim` with level `level` and returns the local player.
static func build(level: int, sim: Simulation, state: Dictionary) -> WorldObject:
	state["status"] = ""
	state["result"] = ""
	if level == 0:
		return Sandbox.build(sim)
	var player := sim.spawn(Materials.make_player(Vector2(160, 360), 0))
	match level:
		1:
			sim.spawn(Materials.make("stone", Vector2(520, 300)))
			sim.spawn(Materials.make("stone", Vector2(560, 470)))
			for y in [200, 244, 476, 520]:
				sim.spawn(Materials.make("wood", Vector2(760, y)))
			sim.spawn(Materials.make_fountain("green", Vector2(100, 170)))
			sim.spawn(Materials.make_fountain("violet", Vector2(230, 170)))
		2:
			for p in [Vector2(-22, -22), Vector2(24, -20), Vector2(-20, 24), Vector2(26, 26), Vector2(70, 0)]:
				sim.spawn(Materials.make("wood", RING + p))
			sim.spawn(Materials.make("stone", RING + Vector2(0, -RING_RADIUS - 60)))
			sim.spawn(Materials.make_fountain("green", Vector2(100, 170)))
			sim.spawn(Materials.make_fountain("violet", Vector2(230, 170)))
		3:
			var house: Array[int] = []
			for p in [Vector2(0, -22), Vector2(0, 22), Vector2(38, 0)]:
				house.append(sim.spawn(Materials.make("wood", HOUSE + p)).id)
			state["house"] = house
			state["start"] = sim.tick
			sim.spawn(Materials.make_fountain("violet", Vector2(100, 170)))
			sim.spawn(Materials.make_fountain("blue", Vector2(230, 170)))
			sim.spawn(Materials.make_fountain("red", Vector2(360, 170)))
		4, 5, 6:
			_build_scarce(level, sim, state, player)
	return player


## Levels 4-6: no mana to start with, no wild crystals, and only what's laid
## out (or wells up) to collect.
static func _build_scarce(level: int, sim: Simulation, state: Dictionary, player: WorldObject) -> void:
	sim.wild_mana = false
	for c in SpellGrammar.COLORS:
		player.mana_store[c] = 0.0
	match level:
		4:
			sim.spawn(Materials.make("stone", GREEN_STONE))
			sim.spawn(Materials.make("wood", Vector2(760, 620)))
			for p in [Vector2(240, 210), Vector2(320, 170)]:
				sim.spawn(Materials.make_mana("green", Simulation.MANA_CRYSTAL, p))
		5:
			_wall(sim)
			var logs: Array[int] = []
			for i in 5:
				logs.append(sim.spawn(Materials.make("wood", BARRICADE + Vector2(0, (i - 2) * 44))).id)
			state["logs"] = logs
			for p in [Vector2(240, 200), Vector2(240, 440), Vector2(360, 360)]:
				sim.spawn(Materials.make_mana("red", Simulation.MANA_CRYSTAL, p))
			sim.spawn(Materials.make_mana("green", Simulation.MANA_CRYSTAL, Vector2(110, 160)))
		6:
			_wall(sim)
			var fires: Array[int] = []
			for p in BONFIRES:
				var fire := sim.spawn(Materials.make("fire", p))
				fire.lifetime = -1  # a bonfire burns until put out,
				fire.health = 3000.0  # and Destroy takes 30 s (7.5 violet) to wear one down: water's the way
				fire.max_health = fire.health
				fires.append(fire.id)
			state["fires"] = fires
			sim.spawn(Materials.make_fountain("red", Vector2(950, 220)))
			sim.spawn(Materials.make_fountain("blue", Vector2(950, 500)))
			sim.spawn(Materials.make_mana("green", Simulation.MANA_CRYSTAL, Vector2(260, 240)))
			sim.spawn(Materials.make_mana("violet", Simulation.MANA_CRYSTAL, Vector2(120, 200)))


## A wall of stone from top to bottom, no gaps to walk through.
static func _wall(sim: Simulation) -> void:
	for y in range(20, 720, 40):
		sim.spawn(Materials.make("stone", Vector2(WALL_X, y)))


## The gold areas a level draws: [center, radius].
static func zones(level: int) -> Array:
	match level:
		1:
			return [[PAD, PAD_RADIUS]]
		4:
			return [[GREEN_PAD, PAD_RADIUS]]
		2:
			return [[RING, RING_RADIUS]]
	return []


## Runs the level's events for the tick just stepped and judges it.
static func step(level: int, sim: Simulation, state: Dictionary) -> void:
	if state["result"] != "":
		return
	match level:
		1:
			var on_pad := sim.objects.any(func(o: WorldObject) -> bool:
				return not o.dead and o.material == "stone" and o.pos.distance_to(PAD) <= PAD_RADIUS - 12.0)
			state["status"] = "The pad is empty." if not on_pad else ""
			if on_pad:
				state["result"] = "won"
		2:
			var left := sim.objects.filter(func(o: WorldObject) -> bool:
				return not o.dead and o.material == "wood" and o.pos.distance_to(RING) < RING_RADIUS).size()
			state["status"] = "%d log%s in the ring." % [left, "" if left == 1 else "s"]
			if left == 0:
				state["result"] = "won"
		3:
			_step_firebreak(sim, state)
		4:
			var on_pad := sim.objects.any(func(o: WorldObject) -> bool:
				return not o.dead and o.material == "stone" and o.pos.distance_to(GREEN_PAD) <= PAD_RADIUS - 12.0)
			state["status"] = "The pad is empty." if not on_pad else ""
			if on_pad:
				state["result"] = "won"
		5, 6:
			var ids: Array = state["logs" if level == 5 else "fires"]
			var left := ids.filter(func(id: int) -> bool: return sim.find(id) != null).size()
			state["status"] = ("%d of 5 logs standing." if level == 5 else "%d of 3 bonfires burning.") % left
			if left == 0:
				state["result"] = "won"


static func _step_firebreak(sim: Simulation, state: Dictionary) -> void:
	var elapsed: int = sim.tick - state["start"]
	if elapsed > 0 and elapsed % FIRE_EVERY == 0:
		var at := HOUSE + Vector2.from_angle(sim.rng.randf_range(0.0, TAU)) * FIRE_FROM
		var fire := sim.spawn(Materials.make("fire", at.clamp(Vector2(20, 20), Simulation.ARENA.end - Vector2(20, 20))))
		fire.tags["creeping"] = true
	for o in sim.objects:
		if not o.dead and o.has_tag("creeping"):
			o.force += o.pos.direction_to(HOUSE) * Simulation.DRAG * FIRE_CREEP  # next tick's push
	var standing := 0
	for id in state["house"]:
		if sim.find(id) != null:
			standing += 1
	var left := maxi(0, HOLD_OUT - elapsed) / Simulation.TICK_RATE
	state["status"] = "House: %d of 3 logs standing · %d s to go" % [standing, left]
	if standing < 2:
		state["result"] = "lost"
	elif elapsed >= HOLD_OUT:
		state["result"] = "won"
