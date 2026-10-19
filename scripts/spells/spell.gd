class_name Spell
extends RefCounted
## A cast spell. It lives on its own world object (the host) and performs its
## verb every tick until it reaches its goal, runs out of mana, or is destroyed.
## Create has no goal: it builds one object after another in a line along the
## direction it was cast, sustaining each finished one (fire doesn't burn out),
## until its mana runs out. Create Spell likewise makes a line of spells, one
## every CREATE_SPELL_TICKS, until it has made CREATED_SPELLS of them. Each new
## one goes in the nearest free place on the line, so gaps get refilled; when
## the line is full up to the arena's edge, Create waits for space.
##
## Anchors: every spell a player casts follows them, including a bare selector,
## which they hold until a later spell takes it in with the noun Held. Spells
## created by other spells stay at their own point.
##
## Mana: `mana` is the spell's own fuel and drains every tick. `reserve` is
## earmarked for the spell it creates and is handed over when it does.

const CREATE_TICKS_PER_RADIUS := 1.5  # bigger objects take longer to build
const CREATE_SPACING := 4.0  # gap between objects in a Create line
const CREATE_SPELL_TICKS := Simulation.TICK_RATE  # time between created spells
const CREATED_SPELL_SPACING := 30.0  # distance between spells in a Create Spell line
const DESTROY_RATE := 100.0  # health per second
const MOVE_SPEED := 140.0  # pixels per second

var ast: Dictionary
var caster: WorldObject
var host: WorldObject
var mana := {}  # color -> amount left
var reserve := {}  # color -> amount carried for the spell this one creates
var anchored := true  # follows its caster
var what: WorldObject  # locked at cast; for Create, the object being built
var created: Array[WorldObject] = []  # every object this Create has made
var to: WorldObject  # Move's destination, locked at cast
var current: WorldObject  # a selector spell's pick this tick
var taken_by: WorldObject  # for a held selector: the spell that took it in
var chosen: WorldObject  # the inventory spell the noun Chosen means
# How many times to take "the target of" `what` / `to` to get what this spell
# acts on now: 0 = the object itself; 1 for a followed selector or Target of.
var _what_hops := 0
var _to_hops := 0

var _drain := {}  # color -> mana per tick
var _dir := Vector2.RIGHT  # the direction it was cast in
var _build := 0.0
var _building: WorldObject  # the object Create is growing, or null while it waits
var _build_step := 0.0
var _full_radius := 0.0
var _lifetime := -1  # a created object's full lifetime in ticks, -1 = none
var _material := ""
var _edge := 0.0  # distance from the host to where the Create line starts
var _inner := {}  # for Create Spell: the spell it creates
var _spell_timer := 0


func _init(p_ast: Dictionary, p_caster: WorldObject, p_host: WorldObject, p_mana: Dictionary,
		p_reserve: Dictionary, p_anchored: bool) -> void:
	ast = p_ast
	caster = p_caster
	host = p_host
	mana = p_mana
	reserve = p_reserve
	anchored = p_anchored
	var per_second := SpellGrammar.drain_per_second(ast)
	for c in per_second:
		_drain[c] = per_second[c] / Simulation.TICK_RATE


## A bare selector, cast on its own: it re-chooses every tick.
func is_selector() -> bool:
	return ast["verb"] == "select"


## Runs once at cast. Selectors inside a spell choose now, and the verb keeps
## that choice for its whole life.
func on_cast(sim: Simulation, aim: Vector2) -> void:
	var dir := host.pos.direction_to(aim)
	if dir != Vector2.ZERO:
		_dir = dir
	# Objects are created just outside whatever the spell is anchored to.
	var edge := (caster.radius if anchored else host.radius) + 6.0
	match ast["verb"]:
		"create":
			_edge = edge
			_inner = SpellGrammar.created_spell(ast)
			if not _inner.is_empty():
				_create_spell(sim)
			else:
				_material = ast["what"]["material"]
				_full_radius = Materials.PROPS[_material]["radius"]
				_build_step = 1.0 / (CREATE_TICKS_PER_RADIUS * _full_radius)
				_start_object(sim)
		"destroy":
			var slot := _slot(ast["what"], sim)
			what = slot[0]
			_what_hops = slot[1]
		"move":
			var slot := _slot(ast["what"], sim)
			what = slot[0]
			_what_hops = slot[1]
			slot = _slot(ast["to"], sim)
			to = slot[0]
			_to_hops = slot[1]
		"select":
			current = _closest(sim, ast["qualifier"])
	caster.last_it = host if is_selector() else target()


## Starts building the next object of a Create line in its nearest free
## place, or leaves `_building` null if there is none.
func _start_object(sim: Simulation) -> void:
	_building = null
	var pos := _free_place(_edge + _full_radius, 2.0 * _full_radius + CREATE_SPACING, _full_radius,
			func(at: Vector2) -> bool: return _is_clear(sim, at, _full_radius))
	if pos == Vector2.INF:
		return
	_building = sim.spawn(Materials.make(_material, pos))
	_building.radius = 2.0
	_lifetime = _building.lifetime
	_build = 0.0
	created.append(_building)
	what = _building


## The nearest place on the line, `first` from the host and then every `step`,
## that is inside the arena and passes `free`; Vector2.INF if there is none.
func _free_place(first: float, step: float, radius: float, free: Callable) -> Vector2:
	var arena := Simulation.ARENA.grow(-radius)
	var pos := host.pos + _dir * first
	while arena.has_point(pos):
		if free.call(pos):
			return pos
		pos += _dir * step
	return Vector2.INF


## Nothing physical (not a spell or mana) overlaps a circle of `radius` at `at`.
func _is_clear(sim: Simulation, at: Vector2, radius: float) -> bool:
	for o in sim.objects:
		if not o.dead and o.spell == null and not o.has_tag("mana") \
				and at.distance_to(o.pos) < o.radius + radius:
			return false
	return true


## Starts the next spell of a Create Spell line, just past the last one, paid
## with one share of this spell's reserve. The new spell keeps what it must
## carry for its own created spells as its reserve, and burns the rest as fuel.
func _create_spell(sim: Simulation) -> void:
	var inner_reserve := SpellGrammar.payload(_inner)
	var inner_fuel := SpellGrammar.drain_per_second(_inner)
	for c in inner_fuel:
		inner_fuel[c] *= SpellGrammar.CREATED_SPELL_SECONDS
	# A place is free if none of this spell's living creations sits there.
	var pos := _free_place(_edge + host.radius, CREATED_SPELL_SPACING, host.radius, func(at: Vector2) -> bool:
		return created.all(func(o: WorldObject) -> bool:
			return o.dead or at.distance_to(o.pos) >= CREATED_SPELL_SPACING / 2.0))
	if pos == Vector2.INF:
		return  # no room; try again next tick
	var paid := SpellGrammar.share(_inner)
	for c in paid:
		reserve[c] = maxf(0.0, reserve.get(c, 0.0) - paid[c])
	what = sim.start_spell(_inner, caster, pos, inner_fuel, inner_reserve, pos + _dir * 100.0, false, chosen)
	created.append(what)
	_spell_timer = 0


## Runs every tick. Returns false once the spell has ended.
func tick(sim: Simulation) -> bool:
	if anchored:
		if caster.dead:
			return false
		host.pos = caster.pos
	for c in _drain:
		if mana.get(c, 0.0) < _drain[c]:
			return false
	for c in _drain:
		mana[c] -= _drain[c]

	match ast["verb"]:
		"create":
			if not _inner.is_empty():
				# A created spell starts whole; make the next after a pause.
				if created.size() >= SpellGrammar.CREATED_SPELLS:
					return false
				_spell_timer += 1
				if _spell_timer >= CREATE_SPELL_TICKS:
					_create_spell(sim)
				return true
			if _building == null or _building.dead or _build >= 1.0:
				_start_object(sim)
			if _building != null:
				_build = minf(1.0, _build + _build_step)
				_building.radius = maxf(2.0, _full_radius * _build)
			if _lifetime > 0:
				for o in created:
					o.lifetime = _lifetime  # sustained: none expire while the spell lasts
			return true
		"destroy":
			var subject := target()
			if subject == null:
				return false
			subject.health -= DESTROY_RATE * Simulation.DT
			return subject.health > 0.0
		"move":
			var subject := target()
			var dest := destination()
			if subject == null or dest == null:
				return false
			# A chase after another spell's target keeps going when it arrives or
			# is blocked (it slides around what blocks it); other moves are done.
			if subject.blocked:
				return _to_hops > 0
			if subject.pos.distance_to(dest.pos) - subject.radius - dest.radius <= 2.0:
				return _to_hops > 0
			# Pushes add up, so several Moves on one object combine.
			subject.velocity += subject.pos.direction_to(dest.pos) * MOVE_SPEED
			return true
		"select":
			current = _closest(sim, ast["qualifier"])
			return true
	return false


## What the spell acts on right now, or null if that is gone: a selector's
## pick, the object a Destroy or Move acts on, or a Create's product (the
## newest object in its line, or the spell it created).
func target() -> WorldObject:
	return current if is_selector() else _live(what, _what_hops)


func destination() -> WorldObject:
	return _live(to, _to_hops)


## Follows "the target of" `hops` times from `o`. Spells only refer to older
## spells, so the chain always ends. Destroying a spell in it cuts off every
## spell that goes through it.
static func _live(o: WorldObject, hops: int) -> WorldObject:
	for i in hops:
		if o == null or o.dead or o.spell == null:
			return null
		o = o.spell.target()
	if o == null or o.dead:
		return null
	return o


## Locks a noun at cast: [object, hops]. Target of adds a hop; Held, or "It"
## naming a selector spell, means following whatever that selector picks now.
func _slot(noun: Dictionary, sim: Simulation) -> Array:
	if noun.has("target_of"):
		var inner := _slot(noun["target_of"], sim)
		return [inner[0], inner[1] + 1]
	var o := _resolve(noun, sim)
	var follows: bool = noun.get("ref", "") in ["it", "held"] and o != null and o.spell != null \
			and o.spell.is_selector()
	return [o, 1 if follows else 0]


func _resolve(noun: Dictionary, sim: Simulation) -> WorldObject:
	if noun.has("ref"):
		match noun["ref"]:
			"me":
				return caster
			"held":
				var held := sim.held_selector(caster)
				if held != null:
					held.spell.taken_by = host  # it now belongs to this spell
				return held
			"chosen":
				return chosen if chosen != host else null
		return caster.last_it
	return _closest(sim, noun["closest"])


## Closest is measured from the spell's location and never picks the object
## the spell is anchored to, so a caster never selects themselves.
func _closest(sim: Simulation, qualifier: String) -> WorldObject:
	var exclude := [host, caster] if anchored else [host]
	return sim.closest(host.pos, qualifier, exclude)
