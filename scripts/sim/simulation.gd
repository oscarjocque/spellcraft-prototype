class_name Simulation
extends RefCounted
## The one engine that updates every world object on a fixed tick, in the same
## order every time. It never draws: views read object state after each tick.
##
## It is deterministic (same seed and inputs give the same result) and takes
## player input as plain command dictionaries, so it can later run on a server
## that clients only send input to.

const TICK_RATE := 20
const DT := 1.0 / TICK_RATE
const ARENA := Rect2(0, 0, 1280, 720)

const PLAYER_SPEED := 160.0  # pixels per second
const START_MANA := 30.0  # per color
const STORE_CAP := 30.0  # storage limit per color
const INFUSE_CAP := 10.0  # most mana of each color one cast takes from storage
const MANA_CRYSTAL := 5.0  # mana in a naturally spawned crystal
const MANA_SPAWN_TICKS := 3 * TICK_RATE
const MAX_CRYSTALS := 12

var tick := 0
var objects: Array[WorldObject] = []
var messages: Array[String] = []  # recent messages for the HUD
var rng := RandomNumberGenerator.new()
var _next_id := 1


func _init(seed_value := 1) -> void:
	rng.seed = seed_value


func spawn(o: WorldObject) -> WorldObject:
	o.id = _next_id
	_next_id += 1
	o.prev_pos = o.pos
	objects.append(o)
	return o


func say(text: String) -> void:
	messages.append(text)
	if messages.size() > 5:
		messages.pop_front()


## Advances the world by one tick. `commands` maps a controller slot to
## {"move": Vector2, "aim": Vector2, "cast": spell} ("cast" is optional).
func step(commands: Dictionary = {}) -> void:
	tick += 1
	for o in objects:
		o.prev_pos = o.pos
		o.velocity = Vector2.ZERO

	# Behaviors run on a snapshot, so whatever they spawn starts next tick.
	var snapshot := objects.duplicate()
	for o in snapshot:
		if not o.dead and o.controller >= 0:
			_control(o, commands.get(o.controller, {}))
	for o in snapshot:
		if not o.dead and o.spell != null and not o.spell.tick(self):
			o.dead = true

	_integrate()
	_contacts()
	_update_states()
	_cleanup()
	_spawn_mana()


## Nearest live object matching `qualifier`, measured from `from`.
func closest(from: Vector2, qualifier: String, exclude: Array) -> WorldObject:
	var best: WorldObject = null
	var best_d := INF
	for o in objects:
		if o.dead or o in exclude or not o.matches(qualifier):
			continue
		var d := from.distance_squared_to(o.pos)
		if d < best_d:
			best = o
			best_d = d
	return best


## Validates a spell as the server would, infuses mana, and casts it. A spell
## that creates another spell also takes, as a reserve, all the mana that
## spell will need.
func cast(caster: WorldObject, ast: Dictionary, aim: Vector2) -> WorldObject:
	var err := SpellGrammar.validate(ast)
	if err != "":
		say(err)
		return null
	var drain := SpellGrammar.drain_per_second(ast)
	var reserve := SpellGrammar.payload(ast)
	var fuel := {}
	if caster.has_tag("infinite_mana"):
		# Spells still get their usual mana; storage just never runs out.
		for c in drain:
			fuel[c] = INFUSE_CAP
	else:
		for c in SpellGrammar.COLORS:
			var need: float = drain.get(c, 0.0) + reserve.get(c, 0.0)
			if caster.mana_store.get(c, 0.0) < need:
				say("Not enough %s mana for: %s" % [c, SpellGrammar.to_text(ast)])
				return null
		for c in reserve:
			caster.mana_store[c] -= reserve[c]
		for c in drain:
			var amount := minf(caster.mana_store[c], INFUSE_CAP)
			caster.mana_store[c] -= amount
			fuel[c] = amount

	# An independent selector is placed at the aim; other spells follow the caster.
	var independent: bool = ast["verb"] == "select"
	return start_spell(ast, caster, aim if independent else caster.pos, fuel, reserve, aim, not independent)


## Puts a spell into the world. Its mana is already paid: by a caster's
## storage, or by the reserve of the spell that created it.
func start_spell(ast: Dictionary, caster: WorldObject, pos: Vector2, fuel: Dictionary,
		reserve: Dictionary, aim: Vector2, anchored: bool) -> WorldObject:
	var host := spawn(Materials.make_spell_host(pos))
	host.spell = Spell.new(ast, caster, host, fuel, reserve, anchored)
	host.spell.on_cast(self, aim)
	return host


func _control(o: WorldObject, cmd: Dictionary) -> void:
	var move: Vector2 = cmd.get("move", Vector2.ZERO)
	o.velocity = move.limit_length(1.0) * PLAYER_SPEED
	if cmd.has("cast"):
		cast(o, cmd["cast"], cmd.get("aim", o.pos))


func _integrate() -> void:
	for o in objects:
		o.blocked = false
		if o.velocity != Vector2.ZERO:
			o.pos += o.velocity * DT
	var n := objects.size()
	for i in n:
		var a := objects[i]
		if a.dead or not a.solid:
			continue
		for j in range(i + 1, n):
			var b := objects[j]
			if not b.dead and b.solid:
				_separate(a, b)
	for o in objects:
		o.pos = o.pos.clamp(ARENA.position + Vector2.ONE * o.radius, ARENA.end - Vector2.ONE * o.radius)


## Pushes two overlapping solid objects apart. Stone that is not itself moving
## is immovable, and anything moving into it stops dead.
func _separate(a: WorldObject, b: WorldObject) -> void:
	var delta := b.pos - a.pos
	var dist := delta.length()
	var overlap := a.radius + b.radius - dist
	if overlap <= 0.0:
		return
	var normal := delta / dist if dist > 0.001 else Vector2.RIGHT
	var a_moving := a.velocity != Vector2.ZERO
	var b_moving := b.velocity != Vector2.ZERO
	if b.material == "stone" and not b_moving:
		a.pos -= normal * overlap
		a.blocked = a_moving
		return
	if a.material == "stone" and not a_moving:
		b.pos += normal * overlap
		b.blocked = b_moving
		return
	var share := b.mass / (a.mass + b.mass)
	a.pos -= normal * overlap * share
	b.pos += normal * overlap * (1.0 - share)


func _contacts() -> void:
	var n := objects.size()
	for i in n:
		var a := objects[i]
		for j in range(i + 1, n):
			var b := objects[j]
			if a.dead or b.dead or not a.touches(b):
				continue
			Rules.on_contact(self, a, b)
			Rules.on_contact(self, b, a)


func _update_states() -> void:
	for o in objects:
		if o.dead:
			continue
		if o.statuses.has("burning"):
			o.health -= Rules.BURN_DAMAGE * DT
		for s in o.statuses.keys():
			if o.statuses[s] > 0:
				o.statuses[s] -= 1
				if o.statuses[s] == 0:
					o.statuses.erase(s)
		if o.lifetime > 0:
			o.lifetime -= 1
			if o.lifetime == 0:
				o.dead = true
		if o.health <= 0.0:
			_defeat(o)


## Players respawn at home; everything else is destroyed.
func _defeat(o: WorldObject) -> void:
	if not o.has_tag("player"):
		o.dead = true
		return
	say("A player was defeated and respawns.")
	o.pos = o.home
	o.prev_pos = o.home
	o.health = o.max_health
	o.statuses.clear()


func _cleanup() -> void:
	var alive: Array[WorldObject] = []
	var released: Array[WorldObject] = []
	for o in objects:
		if not o.dead:
			alive.append(o)
		elif o.spell != null:
			released.append_array(_release(o))
	objects = alive
	for m in released:
		spawn(m)


## A spell that ends with mana left, fuel or reserve, drops it into the world.
func _release(host: WorldObject) -> Array[WorldObject]:
	var out: Array[WorldObject] = []
	var i := 0
	for c in SpellGrammar.COLORS:
		var amount: float = host.spell.mana.get(c, 0.0) + host.spell.reserve.get(c, 0.0)
		if amount >= 0.5:
			var offset := Vector2(10, 0).rotated(i * TAU / SpellGrammar.COLORS.size())
			out.append(Materials.make_mana(c, amount, host.pos + offset))
		i += 1
	return out


func _spawn_mana() -> void:
	if tick % MANA_SPAWN_TICKS != 0:
		return
	var count := 0
	for o in objects:
		if o.has_tag("mana"):
			count += 1
	if count >= MAX_CRYSTALS:
		return
	var color: String = SpellGrammar.COLORS[rng.randi_range(0, SpellGrammar.COLORS.size() - 1)]
	var area := ARENA.grow(-40)
	var pos := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
	spawn(Materials.make_mana(color, MANA_CRYSTAL, pos))
