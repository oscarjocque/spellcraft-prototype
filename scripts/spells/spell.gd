class_name Spell
extends RefCounted
## A cast spell. It lives on its own world object (the host) and performs its
## verb every tick until it reaches its goal, runs out of mana, or is destroyed.
## A spell with nothing to act on waits, looking again every tick.
## Create has no goal: it builds one object after another, sustaining each
## finished one (fire doesn't burn out), until its mana runs out. Create Spell
## likewise makes spells, one every CREATE_SPELL_TICKS, until it has made
## them (CREATED_SPELLS, or its "up to"). Each new one goes in the free spot closest to where
## Create aims (see _create_spot), so they gather there and gaps get refilled;
## with no free spot within reach, Create waits.
##
## Anchors: every spell a player casts follows them, including a held noun
## (Hold), which other spells can use through This. Spells created by other
## spells stay at their own point.
##
## Alternate runs its two spells attached to itself, one at a time: a spell
## from a slot is cast fresh each turn (and paid for by the Alternate); an
## attached spell it took over keeps its own mana and is paused between its
## turns. It switches when the running one is done, or after ALTERNATE_TICKS,
## skipping a side that has nothing left to run. Each spell's It is what the
## other acted on in its turn.
##
## Mana: `mana` is the spell's own fuel and drains every tick, once more for
## each extra target it acts on. `reserve` is earmarked for the spells it
## creates and is handed over as it does. An Alternate pays for its spells.

const CREATE_TICKS_PER_RADIUS := 1.5  # bigger objects take longer to build
const CREATE_SEARCH_RINGS := 6  # how far Create looks for a free spot, in rings
const CREATE_SPELL_TICKS := Simulation.TICK_RATE  # time between created spells
const CREATED_SPELL_SPACING := 30.0  # distance between spells a Create Spell makes
const DESTROY_RATE := 100.0  # health per second
const MOVE_SPEED := 140.0  # pixels per second: how fast a Move gets things going, against drag
const MOVE_FORCE := Simulation.DRAG * MOVE_SPEED
## While Move pushes, its drain is scaled by the weight it pushes, in units
## of this much (a player): a stone costs about three times as much, fire
## next to nothing. While it has nothing to push it drains as usual.
const MOVE_WEIGHT_UNIT := 70.0
const ALTERNATE_TICKS := 3 * Simulation.TICK_RATE  # longest turn in an Alternate
const AWAY_DISTANCE := 5.0 * SpellGrammar.PIXELS_PER_METER  # Move ... away from X: this far from X
const REST_SLACK := 8.0  # pixels off its goal before a Move pushes a resting object again

var ast: Dictionary
var caster: WorldObject
var host: WorldObject
var mana := {}  # color -> amount left
var reserve := {}  # color -> amount carried for the spells this one creates
var fuel_limit := {}  # color -> the most fuel it holds (see SpellGrammar.capacity)
var anchored := true  # follows its caster (through `parent`, if it has one)
var parent: WorldObject  # the Alternate running this spell
var paid_by_parent := false  # a spell an Alternate cast from a slot
var paused := false  # an attached spell an Alternate took over, between its turns
var it: Array[WorldObject] = []  # what the noun It means
var what: WorldObject  # for Create: its newest product
var created: Array[WorldObject] = []  # every object or spell this Create has made
var current: Array[WorldObject] = []  # for Hold: what it holds this tick

# Nouns locked at cast (see _bind): what the verb acts on, Move's destination,
# Create's "at".
var _what := {}
var _to := {}
var _at := {}
var _at_pos := Vector2.INF  # where Create's "at" was last seen
var _from_bindings: Array = []  # [noun, binding] pairs for pickers' "to"/"of" nouns
var _resting := {}  # Move: objects at their goal, not being pushed

var _drain := {}  # color -> mana per tick
var _limit := 0  # its "up to", 0 for none
var _count := 0  # how many it has destroyed, marked, or turns it has run
var _dir := Vector2.RIGHT  # the direction it was cast in
var _build := 0.0
var _building: WorldObject  # the object Create is growing, or null while it waits
var _build_step := 0.0
var _full_radius := 0.0
var _lifetime := -1  # a created object's full lifetime in ticks, -1 = none
var _material := ""
var _edge := 0.0  # distance from the host to where Create aims, without "at"
var _inner := {}  # for Create Spell: the spell it creates
var _spell_timer := 0
var _sub: WorldObject  # Alternate: the spell running now
var _turn := 0  # Alternate: 0 = first spell, 1 = second
var _turn_ticks := 0
var _last := [[], []]  # Alternate: what each spell last acted on
var _taken: Array = [null, null]  # Alternate: the attached spells it took over


func _init(p_ast: Dictionary, p_caster: WorldObject, p_host: WorldObject, p_mana: Dictionary,
		p_reserve: Dictionary, p_anchored: bool) -> void:
	ast = p_ast
	caster = p_caster
	host = p_host
	mana = p_mana
	reserve = p_reserve
	anchored = p_anchored
	_limit = SpellGrammar.up_to(ast)
	var per_second := SpellGrammar.drain_per_second(ast)
	for c in per_second:
		_drain[c] = per_second[c] / Simulation.TICK_RATE
	fuel_limit = SpellGrammar.fuel_limit(ast)


## Runs once at cast. Pickers inside a spell choose now, and the verb keeps
## that choice for its whole life.
func on_cast(sim: Simulation, aim: Vector2) -> void:
	var dir := host.pos.direction_to(aim)
	if dir != Vector2.ZERO:
		_dir = dir
	# Objects are created just outside whatever the spell is anchored to.
	_edge = (caster.radius if anchored else host.radius) + 6.0
	match ast["verb"]:
		"create":
			if ast.get("at") is Dictionary:
				_at = _bind(ast["at"], sim)
			_inner = SpellGrammar.created_spell(ast)
			if not _inner.is_empty():
				_create_spell(sim)
			else:
				_material = ast["what"]["material"]
				_full_radius = Materials.PROPS[_material]["radius"]
				_build_step = 1.0 / (CREATE_TICKS_PER_RADIUS * _full_radius)
				_start_object(sim)
		"destroy", "mark":
			_what = _bind(ast["what"], sim)
		"move":
			_what = _bind(ast["what"], sim)
			_to = _bind(ast["to"], sim)
		"select":
			var noun := SpellGrammar.held_noun(ast)
			if SpellGrammar.picker_of(noun) == "":
				_what = _bind(noun, sim)
			current = _hold(sim)
		"alternate":
			for i in 2:
				var arg: Dictionary = ast["first" if i == 0 else "second"]
				if arg.get("ref", "") == "this":
					_taken[i] = _take(sim, arg.get("id", 0))
			_turn = 1  # so the first turn tried is the first spell's
			_next_turn(sim)


## Runs every tick. Returns false once the spell has ended.
func tick(sim: Simulation) -> bool:
	if anchored:
		if caster.dead:
			return false
		host.pos = parent.pos if parent != null else caster.pos
	if ast["verb"] != "move" and not _pay(1):  # Move pays by the weight it pushes
		return false

	match ast["verb"]:
		"create":
			return _tick_create(sim)
		"destroy":
			var subjects: Variant = _subjects(sim)
			if subjects == null:
				return false
			if not _pay(subjects.size() - 1):
				return false
			for s in subjects:
				var was_alive: bool = s.health > 0.0
				s.health -= DESTROY_RATE * Simulation.DT
				if was_alive and s.health <= 0.0:
					_count += 1
			# Once what it locked onto is gone, _subjects ends it.
			return _limit == 0 or _count < _limit
		"mark":
			var subjects: Variant = _subjects(sim)
			if subjects == null:
				return false
			if not _pay(subjects.size() - 1):
				return false
			for s in subjects:
				if not s.marks.has(caster.id):
					s.marks[caster.id] = true
					_count += 1
			if _limit > 0 and _count >= _limit:
				return false
			# Done once it has marked something, unless it follows a spell's
			# target, in which case it marks each new one.
			return subjects.is_empty() or not _what["chain"].is_empty()
		"move":
			return _tick_move(sim)
		"select":
			current = _hold(sim)
			return true
		"alternate":
			return _tick_alternate(sim)
	return false


## Takes `times` ticks' worth of drain; false if the mana isn't there. A spell
## an Alternate cast from a slot is paid for by the Alternate.
func _pay(times: float) -> bool:
	if times <= 0 or paid_by_parent:
		return true
	for c in _drain:
		if mana.get(c, 0.0) < _drain[c] * times:
			return false
	for c in _drain:
		mana[c] -= _drain[c] * times
	return true


## What Destroy or Mark acts on now; [] while it waits; null when it's over:
## everything it locked onto is gone (its goal), or a spell it follows is.
func _subjects(sim: Simulation) -> Variant:
	match _state(_what):
		"lost":
			return null
		"unbound":
			_what = _bind(ast["what"], sim)
	return _capped(_eval(_what))


## With "up to N", only the N nearest of `objs`.
func _capped(objs: Array[WorldObject]) -> Array[WorldObject]:
	if _limit == 0 or objs.size() <= _limit:
		return objs
	var sorted := objs.duplicate()
	sorted.sort_custom(func(a: WorldObject, b: WorldObject) -> bool:
		return host.pos.distance_squared_to(a.pos) < host.pos.distance_squared_to(b.pos))
	return sorted.slice(0, _limit)


func _tick_move(sim: Simulation) -> bool:
	# A spell it follows being destroyed cuts it off, and so does losing what
	# a This named (that pick can't come back); other objects it moves or
	# moves to being destroyed just send it looking for others.
	for k in ["what", "to"]:
		var b: Dictionary = _what if k == "what" else _to
		if _state(b) == "lost" and (not b["chain"].is_empty() or ast[k].get("ref", "") == "this"):
			return false
	if _state(_what) != "ok":
		_what = _bind(ast["what"], sim)
	if _state(_to) != "ok":
		_to = _bind(ast["to"], sim)
	var subjects := _capped(_eval(_what))
	var dests := _eval(_to)
	if subjects.is_empty() or dests.is_empty():
		return _pay(1)  # nothing to move, or nowhere to move it, yet: wait
	# It doesn't end when things get there: it stops pushing what's at its
	# goal, and pushes it again once it's knocked (or its goal moves) more
	# than REST_SLACK off. Something in the way is pushed against, so it
	# slides around it where it can.
	var away: bool = ast.get("away", false)
	var pushes := []  # [object, direction]
	var weight := 0.0
	for s in subjects:
		var dest := _nearest(dests, s)
		if dest == null or s.has_tag("fixed"):
			continue
		var dir := s.pos.direction_to(dest.pos)
		var gap := s.pos.distance_to(dest.pos) - s.radius - dest.radius
		var slack := REST_SLACK if _resting.has(s) else 0.0
		var at_goal := false
		if away:
			# Away from X: until it's AWAY_DISTANCE from X, letting go in time
			# to coast the rest of the way.
			dir = -dir if dir != Vector2.ZERO else Vector2.RIGHT
			var coast_away := maxf(s.velocity.dot(dir), 0.0) * s.mass / Simulation.DRAG
			at_goal = gap + coast_away >= AWAY_DISTANCE - slack
		else:
			# Arrived means touching, so the last push always makes contact:
			# what it moves rams into something solid at speed. Toward
			# something that isn't solid (a place, fire) it stops pushing in
			# time to coast to a stop there instead of past it.
			var coast := 0.0 if dest.solid else maxf(s.velocity.dot(dir), 0.0) * s.mass / Simulation.DRAG
			at_goal = gap <= maxf(coast, 0.5) + slack
		if at_goal:
			_resting[s] = true
			continue
		_resting.erase(s)
		if s == host:
			anchored = false  # a spell moving itself leaves its caster to go
		pushes.append([s, dir])
		weight += s.mass
	if not _pay(weight / MOVE_WEIGHT_UNIT if not pushes.is_empty() else 1.0):
		return false
	for p in pushes:
		# A push, so several Moves on one object combine, and heavy things
		# take longer to get going.
		p[0].force += p[1] * MOVE_FORCE
	return true  # until its mana runs out


func _tick_create(sim: Simulation) -> bool:
	if not _inner.is_empty():
		# A created spell starts whole; make the next after a pause.
		if created.size() >= SpellGrammar.spells_created(ast):
			return false
		_spell_timer += 1
		if _spell_timer >= CREATE_SPELL_TICKS:
			_create_spell(sim)
		return true
	var room := _limit == 0 or created.size() < _limit
	if room and (_building == null or _building.dead or _build >= 1.0):
		_start_object(sim)
	if _building != null and not _building.dead:
		_build = minf(1.0, _build + _build_step)
		_building.radius = maxf(2.0, _full_radius * _build)
	if _lifetime > 0:
		for o in created:
			o.lifetime = _lifetime  # sustained: none expire while the spell lasts
	elif not room and _build >= 1.0:
		return false  # made all it may, and none of it needs sustaining
	return true


func _tick_alternate(sim: Simulation) -> bool:
	_turn_ticks += 1
	if _sub != null and not _sub.dead:
		_last[_turn] = _sub.spell.targets()
		if _turn_ticks < ALTERNATE_TICKS:
			return true
		if _taken[_turn] == _sub:
			_sub.spell.paused = true  # an attached spell waits for its next turn
		else:
			_sub.dead = true
	# The turn is over: unless that was the last of its "up to" turns, the
	# other spell goes, its It what this one acted on.
	if _limit > 0 and _count >= _limit:
		return false
	return _next_turn(sim)


## Starts the other side's turn, or this side's again if the other has
## nothing to run; false if neither has.
func _next_turn(sim: Simulation) -> bool:
	for side in [1 - _turn, _turn]:
		var arg: Dictionary = ast["first" if side == 0 else "second"]
		var taken: WorldObject = _taken[side]
		if taken != null and not taken.dead:
			_turn = side
			_sub = taken
			_sub.spell.paused = false
			_sub.spell.it = _alive(_last[1 - side])
		elif not SpellGrammar.arg_spell(arg).is_empty():
			_turn = side
			_start_turn(sim)
		else:
			continue
		_turn_ticks = 0
		_count += 1
		return true
	return false


## Takes over one of the caster's attached spells: it now follows this
## spell, leaves their inventory, waits paused for its turns, and ends with
## this spell. Returns it, or null if `id` isn't one of their attached spells.
func _take(sim: Simulation, id: int) -> WorldObject:
	for o in sim.inventory(caster):
		if o.id == id and o != host:
			o.spell.parent = host
			o.spell.paused = true
			o.bound_to = host
			return o
	return null


## Casts the spell from the slot whose turn it is, attached to this one,
## which pays for it. A spell it creates is paid from this one's reserve
## while that lasts.
func _start_turn(sim: Simulation) -> void:
	var sub := SpellGrammar.arg_spell(ast["first" if _turn == 0 else "second"])
	var sub_reserve := SpellGrammar.payload(sub)
	for c in sub_reserve:
		var take := minf(sub_reserve[c], reserve.get(c, 0.0))
		reserve[c] = reserve.get(c, 0.0) - take
		sub_reserve[c] = take
	var it_now: Array[WorldObject] = _alive(_last[1 - _turn])
	_sub = sim.start_spell(sub, caster, host.pos, {}, sub_reserve, host.pos + _dir * 100.0, anchored,
			host, host, it_now)
	_sub.bound_to = host  # it ends with this spell
	_sub.spell.paid_by_parent = true


## What the spell acts on right now: a held noun's value, Create's newest
## product, what a Destroy, Move or Mark acts on, or what an Alternate's
## running spell acts on.
func targets() -> Array[WorldObject]:
	match ast["verb"]:
		"alternate":
			if _sub != null and not _sub.dead:
				return _sub.spell.targets()
			var none: Array[WorldObject] = []
			return none
		"select":
			return _alive(current)
		"create":
			var out: Array[WorldObject] = []
			if what != null and not what.dead:
				out.append(what)
			return out
	return _capped(_eval(_what))


## The first target, or null.
func target() -> WorldObject:
	var t := targets()
	return t[0] if not t.is_empty() else null


## Move's (first) destination, or null.
func destination() -> WorldObject:
	var d := _eval(_to)
	return d[0] if not d.is_empty() else null


# --- Nouns -----------------------------------------------------------------

## Locks a noun: `roots` are the objects it names now, and `chain` the
## relations (Target of, Caster of, ...) applied to them live, every tick.
func _bind(noun: Dictionary, sim: Simulation) -> Dictionary:
	var rel := SpellGrammar.relation_of(noun)
	if rel != "":
		var inner := _bind(noun[rel], sim)
		inner["chain"].append(rel)
		return inner
	var roots: Array[WorldObject] = []
	var chain: Array[String] = []
	if noun.get("ref", "") == "it":
		roots = _alive(it)
	elif noun.has("ref"):
		var o := _resolve_ref(noun, sim)
		if o != null:
			roots.append(o)
	else:
		roots = _pick(noun, sim, [])
	return {"roots": roots, "chain": chain}


## "unbound": the noun named nothing; "lost": everything it named is gone;
## "ok" otherwise.
static func _state(b: Dictionary) -> String:
	if b.is_empty() or b["roots"].is_empty():
		return "unbound"
	if b["roots"].all(func(o: WorldObject) -> bool: return o.dead):
		return "lost"
	return "ok"


## What a locked noun means now.
static func _eval(b: Dictionary) -> Array[WorldObject]:
	if b.is_empty():
		return []
	var objs := _alive(b["roots"])
	for rel in b["chain"]:
		var next: Array[WorldObject] = []
		for o in objs:
			match rel:
				"target_of":
					if o.spell != null:
						next.append_array(o.spell.targets())
				"caster_of":
					if o.spell != null:
						next.append(o.spell.caster)
				"maker_of":
					if o.maker != null:
						next.append(o.maker)
				"products_of":
					if o.spell != null:
						next.append_array(o.spell.created)
		objs = []
		for o in _alive(next):
			if not o in objs:
				objs.append(o)
	return objs


static func _alive(objs: Array) -> Array[WorldObject]:
	var out: Array[WorldObject] = []
	for o in objs:
		if o != null and not o.dead:
			out.append(o)
	return out


static func _nearest(objs: Array[WorldObject], to: WorldObject) -> WorldObject:
	var best: WorldObject = null
	for o in objs:
		if o != to and (best == null or to.pos.distance_squared_to(o.pos) < to.pos.distance_squared_to(best.pos)):
			best = o
	return best


func _resolve_ref(noun: Dictionary, sim: Simulation) -> WorldObject:
	match noun["ref"]:
		"me":
			return caster
		"here", "self":
			return host  # the spell's own world object: where it is, and itself
		"this":
			# Any object or spell, in the world or attached to anyone, but not
			# this spell itself (that's Self).
			var o := sim.find(noun.get("id", 0))
			if o != null and o != host:
				return o
		"there":
			var at: Variant = noun.get("at")
			if at is Vector2 and Simulation.ARENA.has_point(at):
				var place := sim.spawn(Materials.make_place(at))
				place.bound_to = host  # it lasts as long as this spell
				place.maker = host
				return place
		"aimed":
			return sim.aimed(host.pos, _dir, [host, caster, parent])
	return null


## Runs a picker noun now. The distance is measured from its "to"/"of" noun if
## it has one, else from the spell; a spell attached to its caster never picks
## the caster. `keep` lets Random stick with an earlier pick that still fits.
func _pick(noun: Dictionary, sim: Simulation, keep: Array) -> Array[WorldObject]:
	var picker := SpellGrammar.picker_of(noun)
	var from := host.pos
	if noun.get("from") is Dictionary:
		var origin := _eval(_from_binding(noun, sim))
		if origin.is_empty():
			return []
		from = origin[0].pos
	var within: float = noun.get("within", 0) * SpellGrammar.PIXELS_PER_METER
	var exclude := [host, caster, parent] if anchored else [host]
	return sim.pick(picker, noun[picker], noun.get("adj", []), from, within, caster, exclude, keep)


## The locked "to"/"of" noun of a picker, bound the first time it is needed.
func _from_binding(noun: Dictionary, sim: Simulation) -> Dictionary:
	for pair in _from_bindings:
		if is_same(pair[0], noun):
			if _state(pair[1]) == "unbound":
				pair[1] = _bind(noun["from"], sim)
			return pair[1]
	var b := _bind(noun["from"], sim)
	_from_bindings.append([noun, b])
	return b


## A held noun's value now: a picker picks again; anything else is re-read.
func _hold(sim: Simulation) -> Array[WorldObject]:
	var noun := SpellGrammar.held_noun(ast)
	if SpellGrammar.picker_of(noun) != "":
		return _capped(_pick(noun, sim, current))
	if _state(_what) == "unbound":
		_what = _bind(noun, sim)
	return _capped(_eval(_what))


# --- Create ------------------------------------------------------------------

## Where Create aims. Without "at": just outside the spell's anchor, in the
## cast direction. With "at": right in front of what it's at (on the caster's
## side, touching it), or on it if that's a place or a spell. If what it's at
## is destroyed, Create keeps aiming where it was; until the noun names
## anything, there's nowhere yet.
func _create_spot(sim: Simulation, radius: float) -> Vector2:
	if not ast.get("at") is Dictionary:
		return host.pos + _dir * (_edge + radius)
	if _state(_at) == "unbound":
		_at = _bind(ast["at"], sim)
	var at := _eval(_at)
	if not at.is_empty():
		var t := at[0]
		_at_pos = t.pos - _dir * (t.radius + radius) if t.matches("thing") else t.pos
	return _at_pos


## Starts building the next object in the free spot closest to where Create
## aims, or leaves `_building` null if there is none.
func _start_object(sim: Simulation) -> void:
	_building = null
	var spot := _create_spot(sim, _full_radius)
	if spot == Vector2.INF:
		return
	var pos := _closest_free(spot, _full_radius, _full_radius,
			func(p: Vector2) -> bool: return _is_clear(sim, p, _full_radius))
	if pos == Vector2.INF:
		return
	_building = sim.spawn(Materials.make(_material, pos))
	_building.radius = 2.0
	_building.maker = host
	_lifetime = _building.lifetime
	_build = 0.0
	created.append(_building)
	what = _building


## The spot closest to `center` that is inside the arena and passes `free`,
## trying `center` and then rings `step` apart, up to CREATE_SEARCH_RINGS;
## within a ring, the side facing the caster first. Vector2.INF if none.
func _closest_free(center: Vector2, step: float, radius: float, free: Callable) -> Vector2:
	var arena := Simulation.ARENA.grow(-radius)
	if arena.has_point(center) and free.call(center):
		return center
	var facing := (-_dir).angle()
	for ring in range(1, CREATE_SEARCH_RINGS + 1):
		var r := ring * step
		var n := maxi(6, ceili(TAU * r / step))
		for i in n:
			# Alternate either side of the caster-facing direction.
			var angle := facing + ((i + 1) / 2) * (TAU / n) * (1 if i % 2 == 1 else -1)
			var pos := center + Vector2.from_angle(angle) * r
			if arena.has_point(pos) and free.call(pos):
				return pos
	return Vector2.INF


## No physical object (a Thing) overlaps a circle of `radius` at `at`. What
## isn't solid (fire, water) only keeps clear of its own kind: fire made on a
## log is on it, and sets it burning.
func _is_clear(sim: Simulation, at: Vector2, radius: float) -> bool:
	var solid: bool = Materials.PROPS.get(_material, {}).get("solid", true)
	for o in sim.objects:
		if o.dead or not o.matches("thing") or (not solid and o.material != _material):
			continue
		if at.distance_to(o.pos) < o.radius + radius:
			return false
	return true


## Starts the next spell of a Create Spell in the free spot closest to where
## it aims, paid with one share of this spell's reserve. The new spell keeps what it
## must carry for its own created spells as its reserve, and burns the rest.
func _create_spell(sim: Simulation) -> void:
	var spot := _create_spot(sim, host.radius)
	if spot == Vector2.INF:
		return
	# A spot is free if none of this spell's living creations sits there.
	var pos := _closest_free(spot, CREATED_SPELL_SPACING, host.radius, func(at: Vector2) -> bool:
		return created.all(func(o: WorldObject) -> bool:
			return o.dead or at.distance_to(o.pos) >= CREATED_SPELL_SPACING / 2.0))
	if pos == Vector2.INF:
		return  # no room; try again next tick
	var inner_reserve := SpellGrammar.payload(_inner)
	var inner_fuel := SpellGrammar.fuel_limit(_inner)  # created full
	var paid := SpellGrammar.share(_inner)
	for c in paid:
		reserve[c] = maxf(0.0, reserve.get(c, 0.0) - paid[c])
	what = sim.start_spell(_inner, caster, pos, inner_fuel, inner_reserve, pos + _dir * 100.0, false, host)
	created.append(what)
	_spell_timer = 0
