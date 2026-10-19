class_name Materials
extends RefCounted
## Property presets for the prototype's materials and object kinds.

const PROPS := {
	"fire": {"radius": 14.0, "solid": false, "mass": 0.1, "health": 10.0, "lifetime_s": 10.0, "tags": ["hot"]},
	"water": {"radius": 18.0, "solid": false, "mass": 1.0, "health": 20.0, "lifetime_s": -1.0, "tags": ["wet"]},
	"wood": {"radius": 22.0, "solid": true, "mass": 30.0, "health": 60.0, "lifetime_s": -1.0, "tags": ["flammable"]},
	"stone": {"radius": 20.0, "solid": true, "mass": 200.0, "health": 150.0, "lifetime_s": -1.0, "tags": []},
}


static func make(material: String, pos: Vector2) -> WorldObject:
	var p: Dictionary = PROPS[material]
	var o := WorldObject.new()
	o.material = material
	o.pos = pos
	o.radius = p["radius"]
	o.solid = p["solid"]
	o.mass = p["mass"]
	o.health = p["health"]
	o.max_health = p["health"]
	if p["lifetime_s"] > 0.0:
		o.lifetime = int(p["lifetime_s"] * Simulation.TICK_RATE)
	for t in p["tags"]:
		o.tags[t] = true
	return o


## A player. With a controller it takes input and collects mana; without
## one it is a training dummy that spells can target.
static func make_player(pos: Vector2, controller := -1) -> WorldObject:
	var o := WorldObject.new()
	o.tags = {"player": true}
	o.pos = pos
	o.home = pos
	o.radius = 16.0
	o.solid = true
	o.mass = 70.0
	o.controller = controller
	if controller >= 0:
		o.tags["collector"] = true
		for c in SpellGrammar.COLORS:
			o.mana_store[c] = Simulation.START_MANA
	return o


static func make_mana(color: String, amount: float, pos: Vector2) -> WorldObject:
	var o := WorldObject.new()
	o.tags = {"mana": true}
	o.pos = pos
	o.radius = 7.0
	o.health = 10.0
	o.max_health = 10.0
	o.mana_color = color
	o.mana_amount = amount
	return o


## A spot in the world, made by There: invisible, weightless, and gone when
## the spell that made it ends.
static func make_place(pos: Vector2) -> WorldObject:
	var o := WorldObject.new()
	o.tags = {"place": true}
	o.pos = pos
	o.radius = 4.0
	o.health = 1.0
	o.max_health = 1.0
	return o


## The world object a cast spell lives on.
static func make_spell_host(pos: Vector2) -> WorldObject:
	var o := WorldObject.new()
	o.tags = {"spell": true}
	o.pos = pos
	o.radius = 6.0
	o.health = 10.0
	o.max_health = 10.0
	return o
