extends RefCounted
const Objects = preload("res://src/domain/object_schema.gd")
const Rules = preload("res://src/domain/value_rules.gd")

static func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 65536:
		return {"ok": false, "error": "catalog_io"}
	return parse(file.get_as_text())

static func parse(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "error": "catalog_json"}
	var raw: Variant = json.data
	if not Rules.keys(raw, ["content_version", "definitions"]) or raw.content_version != "0.1.0":
		return {"ok": false, "error": "catalog_version"}
	if not raw.definitions is Array or raw.definitions.is_empty() or raw.definitions.size() > 64:
		return {"ok": false, "error": "catalog_definitions"}
	var definitions: Dictionary = {}
	for entry: Variant in raw.definitions:
		if not entry is Dictionary:
			return {"ok": false, "error": "catalog_shape"}
		var definition: Dictionary = Objects.definition(entry)
		if definition.is_empty():
			return {"ok": false, "error": "catalog_definition"}
		if definitions.has(definition.def_id):
			return {"ok": false, "error": "catalog_duplicate"}
		definitions[definition.def_id] = definition
	return {"ok": true, "content_version": raw.content_version, "definitions": definitions}
