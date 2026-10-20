class_name CastFlow
extends RefCounted
## A cast on its way to the simulation. First the player picks, one after
## another and while the game runs, what each This and There in the spell
## means, in reading order, by clicking the world (This: a thing or a spell,
## or an attached spell by its number), except that the first This or There
## is where the mouse already is. Then the spell waits to go out with a
## tick's command, one per tick, oldest first.

var _casting := {}  # waiting on picks: {"ast", "aim", "nouns", "index"}
var _ready_casts := []  # {"ast", "aim"}, picked and waiting to be sent


## Starts casting `ast` (a copy the picks may be written into) toward `aim`,
## with `under` the thing under the mouse, or null. Does nothing while
## another cast is waiting for picks.
func begin(ast: Dictionary, aim: Vector2, under: WorldObject) -> void:
	if busy():
		return
	_casting = {"ast": ast, "aim": aim, "nouns": SpellGrammar.cast_picks(ast), "index": 0}
	match picking():
		"there":
			pick(aim)
		"this" when under != null:
			pick(under.id)
		"":
			_finish()


## Whether a cast is waiting for picks.
func busy() -> bool:
	return not _casting.is_empty()


## What the current pick is for: "this", "there", or "" if none.
func picking() -> String:
	if not busy() or _casting["index"] >= _casting["nouns"].size():
		return ""
	return _casting["nouns"][_casting["index"]]["ref"]


## The spell being picked for, and which pick (1-based) of how many.
func spell() -> Dictionary:
	return _casting.get("ast", {})


func pick_number() -> int:
	return _casting.get("index", 0) + 1


func pick_count() -> int:
	return _casting["nouns"].size() if busy() else 0


## Fills in the current pick (a thing's or spell's id for This, a
## position for There) and moves on to the next, finishing after the last.
func pick(value: Variant) -> void:
	var noun: Dictionary = _casting["nouns"][_casting["index"]]
	noun["at" if noun["ref"] == "there" else "id"] = value
	_casting["index"] += 1
	if picking() == "":
		_finish()


func cancel() -> void:
	_casting = {}


## The oldest cast ready to send, {"ast", "aim"}, taken off the queue; {} if none.
func take() -> Dictionary:
	return _ready_casts.pop_front() if not _ready_casts.is_empty() else {}


func _finish() -> void:
	_ready_casts.append({"ast": _casting["ast"], "aim": _casting["aim"]})
	_casting = {}
