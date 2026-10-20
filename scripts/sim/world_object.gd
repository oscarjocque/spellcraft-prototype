class_name WorldObject
extends RefCounted
## Everything in the world is a WorldObject. Players, obstacles, spells and
## mana differ only in which properties they carry, so every verb and every
## rule works on all of them alike.

var id := 0
var tags := {}  # tag name -> true

# Transform. Prototype 1 uses circles only.
var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO  # position before this tick, for render smoothing
var moved := Vector2.ZERO  # how far it moved last tick
var home := Vector2.ZERO  # where a defeated player respawns
var radius := 16.0

# Physics
var velocity := Vector2.ZERO  # kept from tick to tick: forces speed it up, drag slows it
var force := Vector2.ZERO  # pushes on it this tick (Move); reset every tick
var walk := Vector2.ZERO  # a player's own walking this tick, on top of its velocity
var mass := 1.0
var solid := false
var blocked := false  # stone stopped this object during the last tick

# Material and state
var material := ""
var health := 100.0
var max_health := 100.0
var statuses := {}  # status name -> ticks left, -1 = until removed
var lifetime := -1  # ticks left, -1 = until destroyed
var dead := false

# Mana: a crystal carries one color; a collector stores several.
var mana_color := ""
var mana_amount := 0.0
var mana_store := {}  # color -> amount

# Behavior
var controller := -1  # input slot of a player-controlled object
var spell: Spell = null  # set on spell objects
var maker: WorldObject = null  # the spell that created this, if one did
var bound_to: WorldObject = null  # this ends when that does
var marks := {}  # caster id -> true, for the adjective Marked


func has_tag(tag: String) -> bool:
	return tags.has(tag)


## Qualifiers match a material ("stone") or a tag ("player", "spell"). A
## Thing is any physical object: not a spell, mana or a place.
func matches(qualifier: String) -> bool:
	if qualifier == "thing":
		return spell == null and not tags.has("mana") and not tags.has("place")
	return material == qualifier or tags.has(qualifier)


## How it is moving this tick: its velocity plus any walking.
func motion() -> Vector2:
	return velocity + walk


func is_moving() -> bool:
	return velocity != Vector2.ZERO or force != Vector2.ZERO or walk != Vector2.ZERO


func touches(other: WorldObject) -> bool:
	return pos.distance_to(other.pos) <= radius + other.radius + 0.5
