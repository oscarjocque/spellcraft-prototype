class_name Sandbox
extends RefCounted
## The prototype's test arena: a player, a training dummy, some of every
## material to try spells on, and a fountain of each mana color.

const PRESETS := [
	{"verb": "create", "what": {"material": "fire"}},
	# Juggle: pull the nearest stone in (slot 5), throw it (slot 6), and again.
	{"verb": "alternate", "first": {"slot": 4}, "second": {"slot": 5}},
	{"verb": "create", "what": {"material": "wood"}},  # Barrier
	{"verb": "destroy", "what": {"closest": "fire"}},  # Extinguish
	{"verb": "move", "what": {"closest": "stone"}, "to": {"ref": "me"}},  # Pull
	{"verb": "move", "what": {"closest": "stone"}, "to": {"closest": "player"}},  # Boulder throw
	{"verb": "select", "what": {"closest": "player"}},  # Live tracker, part 1: hold a selector
	{"verb": "move", "what": {"closest": "stone"}, "to": {"target_of": {"ref": "this"}}},  # Live tracker, part 2
	{"verb": "create", "what": {"spell": {"verb": "destroy", "what": {"closest": "fire"}}}},  # Fire warden
	{"verb": "move", "what": {"ref": "this"}, "to": {"ref": "there"}},  # Telekinesis
]


## Fills `sim` with the arena and returns the local player.
static func build(sim: Simulation) -> WorldObject:
	var player := sim.spawn(Materials.make_player(Vector2(220, 360), 0))
	player.tags["infinite_mana"] = true  # for now, while spells are being explored
	sim.spawn(Materials.make_player(Vector2(1060, 360)))  # training dummy

	for p in [Vector2(480, 180), Vector2(470, 560), Vector2(780, 250), Vector2(820, 520)]:
		sim.spawn(Materials.make("stone", p))
	for y in range(270, 460, 44):
		sim.spawn(Materials.make("wood", Vector2(900, y)))
	sim.spawn(Materials.make("wood", Vector2(640, 620)))
	sim.spawn(Materials.make("wood", Vector2(684, 620)))
	sim.spawn(Materials.make("water", Vector2(330, 600)))

	var x := 420
	for c in SpellGrammar.COLORS:
		sim.spawn(Materials.make_fountain(c, Vector2(x, 90)))
		x += 140
	var i := 0
	for c in SpellGrammar.COLORS:
		sim.spawn(Materials.make_mana(c, Simulation.MANA_CRYSTAL, Vector2(140 + i * 40, 120)))
		i += 1
	return player
