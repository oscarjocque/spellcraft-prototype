class_name CastFlow
extends RefCounted
## A cast on its way to the simulation. First the player picks, one after
## another and while the game runs, what each This and There in the spell
## means, in reading order, by clicking the world (This: a thing or a spell,
## or an attached spell by its number), except that the first This or There
## is where the mouse already is. Then the spell waits to go out with a
## tick's command, one per tick, oldest first.
##
## While a This is being picked, casting another spell picks that spell: the
## cast waiting on the This is set aside, the new spell gets its own picks,
## and once it's in the world (see `fed`) its id is the This, and the cast
## set aside carries on. This can nest.

var _casting := {}  # waiting on picks: {"ast", "aim", "nouns", "index", "feeds"?}
var _set_aside := []  # casts waiting for a spell being cast to be their This, innermost last
var _ready_casts := []  # {"ast", "aim", "feeds"?}, picked and waiting to be sent
var _feeding := false  # a spell meant as a This has been sent; waiting for its id


## Starts casting `ast` (a copy the picks may be written into) toward `aim`,
## with `under` the thing under the mouse, or null. While another cast waits
## for a This, this spell will be it; while another waits for anything else,
## it does nothing.
func begin(ast: Dictionary, aim: Vector2, under: WorldObject) -> void:
	if not can_begin():
		return
	var feeds := picking() == "this"
	if feeds:
		_set_aside.append(_casting)
	_casting = {"ast": ast, "aim": aim, "nouns": SpellGrammar.cast_picks(ast), "index": 0, "feeds": feeds}
	match picking():
		"there":
			pick(aim)
		"this" when under != null:
			pick(under.id)
		"":
			_finish()


## Whether a cast is waiting for picks (or for a spell cast as its This).
func busy() -> bool:
	return not _casting.is_empty() or not _set_aside.is_empty()


## Whether a spell can be cast now: nothing is waiting, or a This is, which
## the spell will then be.
func can_begin() -> bool:
	return not _feeding and (not busy() or picking() == "this")


## What the current pick is for: "this", "there", or "" if none.
func picking() -> String:
	if _casting.is_empty() or _casting["index"] >= _casting["nouns"].size():
		return ""
	return _casting["nouns"][_casting["index"]]["ref"]


## The spell being picked for, and which pick (1-based) of how many.
func spell() -> Dictionary:
	return _casting.get("ast", {})


func pick_number() -> int:
	return _casting.get("index", 0) + 1


func pick_count() -> int:
	return _casting["nouns"].size() if not _casting.is_empty() else 0


## Fills in the current pick (a thing's or spell's id for This, a
## position for There) and moves on to the next, finishing after the last.
func pick(value: Variant) -> void:
	var noun: Dictionary = _casting["nouns"][_casting["index"]]
	noun["at" if noun["ref"] == "there" else "id"] = value
	_casting["index"] += 1
	if picking() == "":
		_finish()


## Cancels the cast being picked for; one set aside for it carries on, still
## wanting its This.
func cancel() -> void:
	_casting = _set_aside.pop_back() if not _set_aside.is_empty() else {}


## The oldest cast ready to send, {"ast", "aim", "feeds"}, taken off the
## queue; {} if none. One that "feeds" is meant as a This: tell `fed` what
## became of it.
func take() -> Dictionary:
	var next: Dictionary = _ready_casts.pop_front() if not _ready_casts.is_empty() else {}
	if next.get("feeds", false):
		_feeding = true
	return next


## The spell sent as a This is in the world as `id` (0 if it couldn't be
## cast): the cast set aside for it takes it and carries on, or, without
## it, still asks for its This.
func fed(id: int) -> void:
	_feeding = false
	if _set_aside.is_empty():
		return
	_casting = _set_aside.pop_back()
	if id != 0:
		pick(id)


func _finish() -> void:
	_ready_casts.append({"ast": _casting["ast"], "aim": _casting["aim"], "feeds": _casting.get("feeds", false)})
	_casting = {}
