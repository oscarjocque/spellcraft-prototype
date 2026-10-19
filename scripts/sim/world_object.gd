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
var home := Vector2.ZERO  # where a defeated player respawns
var radius := 16.0

# Physics
var velocity := Vector2.ZERO  # reset every tick; input and Move set it
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
var last_it: WorldObject = null  # what "It" means in this caster's next spell


func has_tag(tag: String) -> bool:
	return tags.has(tag)


## Qualifiers match a material ("stone") or a tag ("player", "spell").
func matches(qualifier: String) -> bool:
	return material == qualifier or tags.has(qualifier)


func touches(other: WorldObject) -> bool:
	return pos.distance_to(other.pos) <= radius + other.radius + 0.5
