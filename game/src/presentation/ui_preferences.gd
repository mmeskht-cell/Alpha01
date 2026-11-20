extends RefCounted
## Versioned local accessibility settings, never part of campaign state.
const MAX_BYTES: int = 8192
const Rules=preload("res://src/domain/value_rules.gd")

static func defaults() -> Dictionary:
	return {"version": 1, "language": "ko", "language_pack": "", "font_size": 16, "sound": true, "motion": true, "levels": {"music": 60, "ambience": 60, "sfx": 80, "ui": 50}}

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high and floorf(float(value)) == float(value)

static func normalize(raw: Variant) -> Dictionary:
	var result: Dictionary = defaults()
	if not raw is Dictionary or not _integer(raw.get("version"), 1, 1):
		return result
	var language: Variant = raw.get("language")
	if language is String and language in ["ko", "en"]:
		result.language = language
	var pack:Variant=raw.get("language_pack","")
	if pack is String and pack.ends_with(".json") and Rules.identifier(pack.trim_suffix(".json")):
		result.language_pack=pack
	var font: Variant = raw.get("font_size")
	if _integer(font, 16, 24) and int(font) in [16, 20, 24]:
		result.font_size = int(font)
	for key: String in ["sound", "motion"]:
		if raw.get(key) is bool:
			result[key] = raw[key]
	var levels: Variant = raw.get("levels")
	if levels is Dictionary:
		for channel: String in result.levels:
			var value: Variant = levels.get(channel)
			if _integer(value, 0, 100):
				result.levels[channel] = int(value)
	return result

static func read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return defaults()
	var parser := JSON.new()
	return normalize(parser.data) if parser.parse(file.get_as_text()) == OK else defaults()

static func write(path: String, value: Dictionary) -> bool:
	var directory: String = ProjectSettings.globalize_path(path.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(directory) != OK and not DirAccess.dir_exists_absolute(directory):
		return false
	var target: String = ProjectSettings.globalize_path(path)
	var temporary: String = target + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(normalize(value)))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		return false
	# Replace only after the complete new file is flushed. Never delete a usable
	# old file as fallback if the OS rejects replacement.
	return DirAccess.rename_absolute(temporary, target) == OK
