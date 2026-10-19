class_name Spell
extends RefCounted
## A cast spell. It lives on its own world object (the host) and performs its
## verb every tick until it reaches its goal, runs out of mana, or is destroyed.
##
## Anchors: verb spells follow their caster; an independent selector stays at
## the point it was cast and re-chooses every tick.

const CREATE_TICKS_PER_RADIUS := 0.4  # bigger objects take longer to build
const DESTROY_RATE := 100.0  # health per second
const MOVE_SPEED := 140.0  # pixels per second

var ast: Dictionary
var caster: WorldObject
var host: WorldObject
var mana := {}  # color -> amount left
var what: WorldObject  # locked at cast
var to: WorldObject  # Move's destination, locked at cast
var current: WorldObject  # an independent selector's pick this tick
var _what_follows := false  # `what` is a selector this spell follows
var _to_follows := false

var _drain := {}  # color -> mana per tick
var _build := 0.0
var _build_step := 0.0
var _full_radius := 0.0


func _init(p_ast: Dictionary, p_caster: WorldObject, p_host: WorldObject, p_mana: Dictionary) -> void:
	ast = p_ast
	caster = p_caster
	host = p_host
	mana = p_mana
	var per_second := SpellGrammar.drain_per_second(ast)
	for c in per_second:
		_drain[c] = per_second[c] / Simulation.TICK_RATE


func is_independent() -> bool:
	return ast["verb"] == "select"


## Runs once at cast. Selectors inside a spell choose now, and the verb keeps
## that choice for its whole life.
func on_cast(sim: Simulation, aim: Vector2) -> void:
	match ast["verb"]:
		"create":
			var dir := caster.pos.direction_to(aim)
			if dir == Vector2.ZERO:
				dir = Vector2.RIGHT
			var material: String = ast["what"]["material"]
			_full_radius = Materials.PROPS[material]["radius"]
			var pos := caster.pos + dir * (caster.radius + _full_radius + 6.0)
			what = sim.spawn(Materials.make(material, pos))
			what.radius = 2.0
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
			host.pos = aim
			current = sim.closest(host.pos, ast["qualifier"], [host])
	caster.last_it = host if is_independent() else what


## Runs every tick. Returns false once the spell has ended.
func tick(sim: Simulation) -> bool:
	if not is_independent():
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
			if what == null or what.dead:
				return false
			_build = minf(1.0, _build + _build_step)
			what.radius = maxf(2.0, _full_radius * _build)
			return _build < 1.0
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
	return sim.closest(host.pos, noun["closest"], [host, caster])
