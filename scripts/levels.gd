class_name Levels
extends RefCounted
## The sandbox and three test levels, each needing more spellcraft than the
## last. In the levels mana is real: the player starts with their usual store
## and refills it from fountains.
##
##   1 Onto the pad   one spell, two picks:    Move (Closest Stone) to There
##   2 Clear the ring  pickers and away from:  Move (All Wood within 3 m of There) away from There
##   3 Firebreak      keep a house alive while fires creep in from all sides:
##                    a live tracker (Hold (All Fire), then Destroy (Target of
##                    Chosen)) does it in two casts; Destroy Fire by hand takes
##                    one every couple of seconds.
##
## A level's state lives in a dictionary Main keeps: build fills it, step
## advances the level's own events (deterministically, from the simulation's
## tick and dice) and sets "status" and "result" ("", "won" or "lost").

const NAMES := ["Sandbox", "Level 1 · Onto the pad", "Level 2 · Clear the ring", "Level 3 · Firebreak"]
const GOALS := [
	"Try anything. F2 goes to the levels.",
	"Get a stone onto the gold pad.  Hint: move stone to there, and click the pad.",
	"Get every log out of the gold ring.  Hint: Move … away from …, and All … within 3 m of There.",
	"Keep 2 of the house's 3 logs for 40 s; fires creep in from every side.  Hint: a held All keeps re-reading; Target of Chosen follows it.",
]
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
	return player


## The gold areas a level draws: [center, radius].
static func zones(level: int) -> Array:
	match level:
		1:
			return [[PAD, PAD_RADIUS]]
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
