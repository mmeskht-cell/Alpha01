extends RefCounted
## JSON-safe integer and shape checks shared by content, commands and saves.
const LIMIT: int = 1000000000

static func integer(value: Variant, minimum: int = 0, maximum: int = LIMIT) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

static func keys(value: Variant, required: Array) -> bool:
	if not value is Dictionary or value.size() != required.size():
		return false
	for key: String in required:
		if not value.has(key):
			return false
	return true

static func identifier(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 64:
		return false
	for character: String in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.":
			return false
	return true

static func normalized(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and integer(value, -LIMIT):
		return int(value)
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[key] = normalized(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry: Variant in value:
			result.append(normalized(entry))
		return result
	return value

static func canonical(value: Variant) -> String:
	return JSON.stringify(normalized(value), "", true)
