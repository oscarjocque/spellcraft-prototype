class_name Spellbook
extends RefCounted
## The player's ten spell slots, kept on disk between plays.

const PATH := "user://spellbook.txt"


## The saved slots, or the presets for any slot missing or no longer a spell
## (all of them, if nothing is saved).
static func load_slots(path := PATH) -> Array:
	var slots: Array = Sandbox.PRESETS.duplicate(true)
	if not FileAccess.file_exists(path):
		return slots
	var saved: Variant = str_to_var(FileAccess.get_file_as_string(path))
	if not saved is Array:
		return slots
	for i in mini(saved.size(), slots.size()):
		if saved[i] is Dictionary and SpellGrammar.validate(saved[i], false) == "":
			slots[i] = saved[i]
	return slots


static func save_slots(slots: Array, path := PATH) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(var_to_str(slots))
