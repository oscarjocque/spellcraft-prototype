class_name Spell
extends RefCounted
## A cast spell. It lives on its own world object (the host) and performs its
## verb every tick until it reaches its goal, runs out of mana, or is destroyed.
## Create has no goal once its object is built: it keeps sustaining the object
## (fire doesn't burn out) until its mana runs out or the object is destroyed.
##
## Anchors: verb spells a player casts follow their caster. Independent
## selectors, and spells created by other spells, stay at their own point.
##
## Mana: `mana` is the spell's own fuel and drains every tick. `reserve` is
## earmarked for the spell it creates and is handed over when it does.

const CREATE_TICKS_PER_RADIUS := 0.4  # bigger objects take longer to build
const DESTROY_RATE := 100.0  # health per second
const MOVE_SPEED := 140.0  # pixels per second

var ast: Dictionary
var caster: WorldObject
var host: WorldObject
var mana := {}  # color -> amount left
var reserve := {}  # color -> amount carried for the spell this one creates
var anchored := true  # follows its caster
var what: WorldObject  # locked at cast
var to: WorldObject  # Move's destination, locked at cast
var current: WorldObject  # an independent selector's pick this tick
var _what_follows := false  # `what` is a selector this spell follows
var _to_follows := false

var _drain := {}  # color -> mana per tick
var _dir := Vector2.RIGHT  # the direction it was cast in
var _build := 0.0
var _build_step := 0.0
var _full_radius := 0.0
var _lifetime := -1  # the created object's full lifetime in ticks, -1 = none


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


func is_independent() -> bool:
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
			var inner := SpellGrammar.created_spell(ast)
			if not inner.is_empty():
				what = _create_spell(sim, inner, host.pos + _dir * (edge + host.radius))
			else:
				var material: String = ast["what"]["material"]
				_full_radius = Materials.PROPS[material]["radius"]
				what = sim.spawn(Materials.make(material, host.pos + _dir * (edge + _full_radius)))
				what.radius = 2.0
				_lifetime = what.lifetime
				_build_step = 1.0 / (CREATE_TICKS_PER_RADIUS * _full_radius)
		"destroy":
			what = _resolve(ast["what"], sim)
			_what_follows = _follows(ast["what"], what)
		"move":
			what = _resolve(ast["what"], sim)
			to = _resolve(ast["to"], sim)
			_what_follows = _follows(ast["what"], what)
			_to_follows = _follows(ast["to"], to)
		"select":
			current = sim.closest(host.pos, ast["qualifier"], [host])
	caster.last_it = host if is_independent() else what


## Starts `inner` at `pos`, paid entirely from this spell's reserve. The new
## spell keeps what it must carry for its own created spell as its reserve,
## and burns the rest as fuel.
func _create_spell(sim: Simulation, inner: Dictionary, pos: Vector2) -> WorldObject:
	var inner_reserve := SpellGrammar.payload(inner)
	var inner_fuel := {}
	for c in reserve:
		inner_fuel[c] = reserve[c] - inner_reserve.get(c, 0.0)
	reserve = {}
	return sim.start_spell(inner, caster, pos, inner_fuel, inner_reserve, pos + _dir * 100.0, false)


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
			if what == null or what.dead or what.spell != null:
				return false  # a created spell starts whole, so Create is done
			if _build < 1.0:
				_build = minf(1.0, _build + _build_step)
				what.radius = maxf(2.0, _full_radius * _build)
			elif _lifetime > 0:
				what.lifetime = _lifetime  # sustained: it can't expire while the spell lasts
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
			if subject == null or dest == null or subject.blocked:
				return false
			if subject.pos.distance_to(dest.pos) - subject.radius - dest.radius <= 2.0:
				return false
			subject.velocity = subject.pos.direction_to(dest.pos) * MOVE_SPEED
			return true
		"select":
			current = sim.closest(host.pos, ast["qualifier"], [host])
			return true
	return false


## What the spell acts on right now, or null if that is gone.
func target() -> WorldObject:
	return current if is_independent() else _live(what, _what_follows)


func destination() -> WorldObject:
	return _live(to, _to_follows)


## A followed selector stands for whatever it picks now, so destroying the
## selector cuts off every spell that follows it.
static func _live(o: WorldObject, follows: bool) -> WorldObject:
	if follows and o != null and not o.dead:
		o = o.spell.current
	if o == null or o.dead:
		return null
	return o


## "It" naming an independent selector means: follow whatever it picks.
static func _follows(noun: Dictionary, o: WorldObject) -> bool:
	return noun.get("ref", "") == "it" and o != null and o.spell != null and o.spell.is_independent()


func _resolve(noun: Dictionary, sim: Simulation) -> WorldObject:
	if noun.has("ref"):
		return caster if noun["ref"] == "me" else caster.last_it
	# Closest is measured from the spell's location and never picks the object
	# the spell is anchored to, so a caster never selects themselves.
	var exclude := [host, caster] if anchored else [host]
	return sim.closest(host.pos, noun["closest"], exclude)
