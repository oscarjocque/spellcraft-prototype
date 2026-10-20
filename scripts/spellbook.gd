class_name Spellbook
extends RefCounted
## The player's ten spell slots, and the spells they typed lately, kept on
## disk between plays.

const TYPED_KEPT := 50

static var path := "user://spellbook.txt"  # tools can point it elsewhere


## The saved slots, or the presets for any slot missing or no longer a spell
## (all of them, if nothing is saved).
static func load_slots(from := "") -> Array:
	var file_path := from if from != "" else path
	var slots: Array = Sandbox.PRESETS.duplicate(true)
	if not FileAccess.file_exists(file_path):
		return slots
	# Chosen was merged into This: older spellbooks say "chosen".
	var saved: Variant = str_to_var(FileAccess.get_file_as_string(file_path).replace('"chosen"', '"this"'))
	if not saved is Array:
		return slots
	for i in mini(saved.size(), slots.size()):
		if saved[i] is Dictionary and SpellGrammar.validate(saved[i], false) == "":
			slots[i] = saved[i]
	return slots


static func save_slots(slots: Array, to := "") -> void:
	var file := FileAccess.open(to if to != "" else path, FileAccess.WRITE)
	if file != null:
		file.store_string(var_to_str(slots))


## The spells typed lately, oldest first, as typed.
static func load_typed() -> Array[String]:
	var out: Array[String] = []
	if FileAccess.file_exists(_typed_path()):
		for line in FileAccess.get_file_as_string(_typed_path()).split("\n", false):
			out.append(line)
	return out


static func save_typed(typed: Array[String]) -> void:
	var file := FileAccess.open(_typed_path(), FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(typed.slice(-TYPED_KEPT)))


static func _typed_path() -> String:
	return path.get_basename() + "_typed.txt"
