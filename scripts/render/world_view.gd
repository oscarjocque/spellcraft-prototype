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

var sim: Simulation
var alpha := 1.0  # 0..1 progress from the last tick to the next
## What a spell being typed would act on (see SpellPreview), and its verb.
var preview := {}
var preview_verb := ""


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Simulation.ARENA, BACKGROUND)
	if sim == null:
		return
	for o in sim.objects:
		if o.spell != null:
			_draw_spell(o)
		elif o.has_tag("mana"):
			_draw_diamond(_p(o), o.radius, MANA_COLOR[o.mana_color])
		elif o.has_tag("place"):
			_draw_place(o)
		elif o.has_tag("player"):
			_draw_player(o)
		else:
			_draw_material(o)
		if not o.marks.is_empty():
			draw_circle(_p(o) + Vector2(0, -o.radius - 4), 3.0, MANA_COLOR["violet"])
	_draw_preview()


## Rings around what the spell being typed would act on: pulsing for what
## the verb acts on, dashed for Move's destination.
func _draw_preview() -> void:
	if preview.is_empty():
		return
	var color: Color = VERB_COLOR.get(preview_verb, Color.WHITE)
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 150.0)
	for o in preview.get("what", []):
		if not o.dead:
			draw_arc(_p(o), o.radius + 6, 0, TAU, 32, Color(color, pulse), 3.0)
	for o in preview.get("to", []):
		if o.dead:
			continue
		var r: float = o.radius + 8
		for i in 12:
			var a := TAU * i / 12.0
			draw_arc(_p(o), r, a, a + TAU / 24.0, 4, Color(color, 0.9), 2.5)


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
## on: solid to its target, dashed to a Move destination.
func _draw_spell(o: WorldObject) -> void:
	var s := o.spell
	var p := _p(o)
	var color: Color = VERB_COLOR[s.ast["verb"]]
	var dest := s.destination()
	for target in s.targets():
		draw_line(p, _p(target), Color(color, 0.5), 1.5)
		if dest != null:
			draw_dashed_line(_p(target), _p(dest), Color(color, 0.5), 1.5, 6.0)
	_draw_diamond(p, o.radius + 2, color)


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


func _draw_health(o: WorldObject, p: Vector2) -> void:
	if o.health >= o.max_health:
		return
	var w := o.radius * 2
	var top := p + Vector2(-o.radius, -o.radius - 8)
	draw_rect(Rect2(top, Vector2(w, 4)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(top, Vector2(w * clampf(o.health / o.max_health, 0, 1), 4)), Color("6fdc6f"))
