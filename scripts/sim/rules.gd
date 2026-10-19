class_name Rules
extends RefCounted
## Interaction rules, checked on every contact. They are written against
## properties, never object types ("anything flammable", not "crates"), so a
## new object joins in as soon as it has the right properties.
##
## "Anything moving stops at stone" lives in Simulation._separate, because it
## is part of collision resolution.

const BURN_DAMAGE := 20.0  # health per second while burning
const IMPACT_MOMENTUM := 15000.0  # mass * closing speed above which a solid hit hurts
const IMPACT_DAMAGE := 0.001  # damage per unit of that momentum, once per hit


## When two solid objects come into contact: each takes damage from the
## other's mass times the speed at which they closed on each other, if that
## is high enough. A heavy stone thrown at a player hurts them (and a little
## itself); a player walking into a wall doesn't. Things already touching, or
## moving apart, don't hit.
static func on_impact(a: WorldObject, b: WorldObject) -> void:
	var normal := a.pos.direction_to(b.pos)
	var closing := (a.velocity - b.velocity).dot(normal)
	if closing <= 0.0:
		return
	if a.mass * closing >= IMPACT_MOMENTUM:
		b.health -= a.mass * closing * IMPACT_DAMAGE
	if b.mass * closing >= IMPACT_MOMENTUM:
		a.health -= b.mass * closing * IMPACT_DAMAGE


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

	# A spell absorbs any mana it touches into its own fuel.
	if a.spell != null and b.has_tag("mana") and not b.dead:
		a.spell.mana[b.mana_color] = a.spell.mana.get(b.mana_color, 0.0) + b.mana_amount
		b.mana_amount = 0.0
		b.dead = true

	# Collectors pick up mana until their storage for that color is full.
	if a.has_tag("collector") and b.has_tag("mana") and not b.dead:
		if a.has_tag("infinite_mana"):
			b.dead = true  # storage that never runs out takes it all
			return
		var have: float = a.mana_store.get(b.mana_color, 0.0)
		var take := minf(b.mana_amount, Simulation.STORE_CAP - have)
		if take > 0.0:
			a.mana_store[b.mana_color] = have + take
			b.mana_amount -= take
			if b.mana_amount <= 0.01:
				b.dead = true
