class_name WorldView
extends Node2D
## Draws the simulation. It only reads object state, smoothing positions
## between ticks with `alpha`.

const BACKGROUND := Color("1b1e24")
const MATERIAL_COLOR := {
	"fire": Color("ff7a2f"),
	"water": Color("3fa7ff"),
	"wood": Color("9a6b3f"),
	"stone": Color("8a8f98"),
}
const MANA_COLOR := {
	"red": Color("ff4d4d"),
	"blue": Color("4d8dff"),
	"green": Color("4dcc6a"),
	"violet": Color("b36bff"),
}
const VERB_COLOR := {
	"create": Color("ff4d4d"),
	"destroy": Color("b36bff"),
	"move": Color("4dcc6a"),
	"mark": Color("b36bff"),
	"select": Color("e6e6e6"),
	"alternate": Color("ffd34d"),
}
const PLAYER_COLOR := Color("e8e6df")
const DUMMY_COLOR := Color("c9a227")
const BURNING_COLOR := Color("ffb02e")
const FLASH_MSEC := 350

var sim: Simulation
var alpha := 1.0  # 0..1 progress from the last tick to the next
## What a spell being typed would act on (see SpellPreview), and its verb.
var preview := {}
var preview_verb := ""
var zones := []  # a level's goal areas: [center, radius]

var _spell_at := {}  # spell host -> where it's drawn this frame
var _flashes := []  # [position, color, msec started]


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Simulation.ARENA, BACKGROUND)
	for z in zones:
		draw_circle(z[0], z[1], Color(0.95, 0.8, 0.3, 0.08))
		draw_arc(z[0], z[1], 0, TAU, 64, Color("ffd34d"), 2.0)
	if sim == null:
		return
	_place_spells()
	for o in sim.objects:
		if o.spell != null:
			_draw_spell(o)
		elif o.has_tag("mana"):
			_draw_diamond(_p(o), o.radius, MANA_COLOR[o.mana_color])
		elif o.has_tag("fountain"):
			_draw_fountain(o)
		elif o.has_tag("place"):
			_draw_place(o)
		elif o.has_tag("player"):
			_draw_player(o)
		else:
			_draw_material(o)
		if not o.marks.is_empty():
			draw_circle(_p(o) + Vector2(0, -o.radius - 4), 3.0, MANA_COLOR["violet"])
	_draw_preview()
	_draw_flashes()


## A short ring spreading from `at`, e.g. where a spell was just cast.
func flash(at: Vector2, color: Color) -> void:
	_flashes.append([at, color, Time.get_ticks_msec()])


func _draw_flashes() -> void:
	var now := Time.get_ticks_msec()
	_flashes = _flashes.filter(func(f: Array) -> bool: return now - f[2] < FLASH_MSEC)
	for f in _flashes:
		var t: float = (now - f[2]) / float(FLASH_MSEC)
		draw_arc(f[0], 16.0 + 34.0 * t, 0, TAU, 40, Color(f[1], 1.0 - t), 3.0 * (1.0 - t) + 1.0)


## Rings around what the spell being typed would act on (objects, or places
## given as points): pulsing for what the verb acts on, dashed for Move's
## destination.
func _draw_preview() -> void:
	if preview.is_empty():
		return
	var color: Color = VERB_COLOR.get(preview_verb, Color.WHITE)
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 150.0)
	var what: Variant = preview.get("what")
	for o in what if what != null else []:
		if o is Vector2:
			draw_arc(o, 10, 0, TAU, 24, Color(color, pulse), 3.0)
		elif not o.dead:
			draw_arc(_p(o), o.radius + 6, 0, TAU, 32, Color(color, pulse), 3.0)
	var to: Variant = preview.get("to")
	for o in to if to != null else []:
		if o is WorldObject and o.dead:
			continue
		var at: Vector2 = o if o is Vector2 else _p(o)
		var r: float = 10.0 if o is Vector2 else o.radius + 8
		for i in 12:
			var a := TAU * i / 12.0
			draw_arc(at, r, a, a + TAU / 24.0, 4, Color(color, 0.9), 2.5)


func _p(o: WorldObject) -> Vector2:
	return o.prev_pos.lerp(o.pos, alpha)


func _draw_material(o: WorldObject) -> void:
	var p := _p(o)
	var color: Color = MATERIAL_COLOR.get(o.material, Color.WHITE)
	if o.material == "water":
		color.a = 0.6
	draw_circle(p, o.radius, color)
	if o.solid:
		draw_arc(p, o.radius, 0, TAU, 24, color.darkened(0.4), 2.0)
	if o.statuses.has("burning"):
		draw_arc(p, o.radius + 3, 0, TAU, 24, BURNING_COLOR, 2.0)
	_draw_health(o, p)


func _draw_player(o: WorldObject) -> void:
	var p := _p(o)
	draw_circle(p, o.radius, PLAYER_COLOR if o.controller >= 0 else DUMMY_COLOR)
	if o.controller >= 0:
		var aim := get_global_mouse_position()
		draw_line(p, p + p.direction_to(aim) * (o.radius + 8), PLAYER_COLOR, 3.0)
	if o.statuses.has("burning"):
		draw_arc(p, o.radius + 3, 0, TAU, 24, BURNING_COLOR, 2.0)
	_draw_health(o, p)


## A spell is a small diamond in its verb's color, with lines to what it acts
## on: solid to its target, dashed to a Move destination. Hollow while it
## waits for something to act on, faded while it waits for its turn.
func _draw_spell(o: WorldObject) -> void:
	var s := o.spell
	var p: Vector2 = _spell_at.get(o, _p(o))
	var color: Color = VERB_COLOR[s.ast["verb"]]
	if not _spell_at.has(o):  # loose in the world: show how far it draws in mana
		draw_arc(p, Simulation.ABSORB_RADIUS, 0, TAU, 32, Color(color, 0.18), 1.0)
	if s.paused:
		_draw_diamond(p, o.radius, Color(color, 0.35))  # waiting for its turn
		return
	var dest := s.destination()
	var targets := s.targets()
	for target in targets:
		draw_line(p, _p(target), Color(color, 0.5), 1.5)
		if dest != null:
			draw_dashed_line(_p(target), _p(dest), Color(color, 0.5), 1.5, 6.0)
	if targets.is_empty() and s.ast["verb"] != "create":
		_draw_diamond_outline(p, o.radius + 2, color)
	else:
		_draw_diamond(p, o.radius + 2, color)


## The spell drawn at `at` (as placed this frame), or null.
func spell_at(at: Vector2) -> WorldObject:
	var best: WorldObject = null
	var best_d := INF
	for o in sim.objects:
		if o.spell != null and not o.dead:
			var d := at.distance_to(_spell_at.get(o, _p(o)))
			if d <= o.radius + 6.0 and d < best_d:
				best = o
				best_d = d
	return best


## Where each spell is drawn: spells attached to a player in a ring around
## them, in inventory order, numbered for the local player as in the HUD;
## spells an Alternate runs beside it. Others where they are.
func _place_spells() -> void:
	_spell_at.clear()
	var attached := {}  # caster -> their attached spells, oldest first
	for o in sim.objects:
		if o.spell != null and o.spell.anchored and o.spell.parent == null and not o.dead:
			if not attached.has(o.spell.caster):
				attached[o.spell.caster] = []
			attached[o.spell.caster].append(o)
	var font := ThemeDB.fallback_font
	for caster in attached:
		var ring: Array = attached[caster]
		var r: float = caster.radius + 13.0
		for i in ring.size():
			var at := _p(caster) + Vector2.from_angle(-PI / 2 + TAU * i / ring.size()) * r
			_spell_at[ring[i]] = at
			if caster.controller >= 0:
				var label_at := _p(caster) + Vector2.from_angle(-PI / 2 + TAU * i / ring.size()) * (r + 11)
				draw_string(font, label_at + Vector2(-4, 4), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
						Color(PLAYER_COLOR, 0.8))
	for o in sim.objects:
		if o.spell != null and o.spell.parent != null and _spell_at.has(o.spell.parent):
			var side: float = 1.0 if o.spell.parent.spell.ast.get("first", {}).get("ref") == null else -1.0
			_spell_at[o] = _spell_at[o.spell.parent] + Vector2(9.0 * side, 9.0)


## A place made by There: a small cross.
func _draw_place(o: WorldObject) -> void:
	var p := _p(o)
	var c := Color(PLAYER_COLOR, 0.7)
	draw_line(p + Vector2(-6, -6), p + Vector2(6, 6), c, 2.0)
	draw_line(p + Vector2(-6, 6), p + Vector2(6, -6), c, 2.0)


func _draw_diamond(p: Vector2, r: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0),
	]), color)


## A fountain: a stone basin with its mana's color welling in the middle.
func _draw_fountain(o: WorldObject) -> void:
	var p := _p(o)
	var color: Color = MANA_COLOR[o.mana_color]
	draw_circle(p, o.radius, Color("3a3f48"))
	draw_arc(p, o.radius, 0, TAU, 32, Color("5a606b"), 3.0)
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 400.0 + o.id)
	draw_circle(p, o.radius * 0.62, Color(color, 0.35 * pulse))
	_draw_diamond(p, o.radius * 0.45 * pulse, color)


func _draw_diamond_outline(p: Vector2, r: float, color: Color) -> void:
	draw_polyline(PackedVector2Array([
		p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0), p + Vector2(0, -r),
	]), color, 1.5)


func _draw_health(o: WorldObject, p: Vector2) -> void:
	if o.health >= o.max_health:
		return
	var w := o.radius * 2
	var top := p + Vector2(-o.radius, -o.radius - 8)
	draw_rect(Rect2(top, Vector2(w, 4)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(top, Vector2(w * clampf(o.health / o.max_health, 0, 1), 4)), Color("6fdc6f"))
