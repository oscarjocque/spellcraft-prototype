class_name Rules
extends RefCounted
## Interaction rules, checked on every contact. They are written against
## properties, never object types ("anything flammable", not "crates"), so a
## new object joins in as soon as it has the right properties.
##
## "Anything moving stops at stone" lives in Simulation._separate, because it
## is part of collision resolution.

const BURN_DAMAGE := 20.0  # health per second while burning
const IMPACT_MOMENTUM := 15000.0  # mass * speed above which a solid hit hurts
const IMPACT_DAMAGE := 0.001  # damage per unit of momentum, per tick of contact


## Applies every rule where `a` acts on `b`. Called once for each order.
static func on_contact(sim: Simulation, a: WorldObject, b: WorldObject) -> void:
	# Fire, or anything burning, sets anything flammable it touches burning.
	if (a.material == "fire" or a.statuses.has("burning")) and b.has_tag("flammable"):
		b.statuses["burning"] = -1

	# Water destroys fire and puts out anything burning.
	if a.material == "water":
		if b.material == "fire":
			b.dead = true
		b.statuses.erase("burning")

	# A fast, heavy solid object damages the solid object it hits.
	if a.solid and b.solid:
		var momentum := a.mass * a.velocity.length()
		if momentum >= IMPACT_MOMENTUM:
			b.health -= momentum * IMPACT_DAMAGE

	# Collectors pick up mana until their storage for that color is full.
	if a.has_tag("collector") and b.has_tag("mana") and not b.dead:
		var have: float = a.mana_store.get(b.mana_color, 0.0)
		var take := minf(b.mana_amount, Simulation.STORE_CAP - have)
		if take > 0.0:
			a.mana_store[b.mana_color] = have + take
			b.mana_amount -= take
			if b.mana_amount <= 0.01:
				b.dead = true
