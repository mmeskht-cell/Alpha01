extends RefCounted
## Common, bounded content contract for fictional inspection tool profiles.
## Immutable legacy specimen values are not a live-state sampler. Never expose
## the private book to presentation. Authority must establish access, then sample.
const Rules = preload("res://src/domain/value_rules.gd")
const Clock = preload("res://src/domain/business_clock.gd")
const Documents = preload("res://src/content/packaged_documents.gd")
const PATH: String = "res://data/campaign/gate1_1/inspection_profiles_v1.json"
static var _legacy: Dictionary = {}

static func valid_reading(kind: String, value: Variant) -> bool:
	match kind:
		"damage_index": return Rules.integer(value, 0, 100)
		"texture": return value in ["pore", "parallel", "cross"]
		"batch_code", "mark": return Rules.identifier(value)
		"side_mark": return value is String and not value.is_empty() and value.length() <= 64 and not value.contains("\n") and not value.contains("\r")
		"function_status": return value in ["serviceable", "partial", "inoperable"]
	return false

static func parse(raw: Variant) -> Dictionary:
	if not Rules.keys(raw, ["version", "profiles", "specimens"]) or raw.version != 1 or not raw.profiles is Dictionary or not raw.specimens is Dictionary:
		return {}
	if raw.profiles.is_empty() or raw.profiles.size() > 128 or raw.specimens.size() > 128:
		return {}
	for def_id: Variant in raw.profiles:
		var p: Variant = raw.profiles[def_id]
		if not Rules.identifier(def_id) or not Rules.keys(p, ["tools"]) or not p.tools is Array or p.tools.is_empty() or p.tools.size() > 32:
			return {}
		var ids: Dictionary = {}
		var evidence_ids: Dictionary = {}
		for row: Variant in p.tools:
			if not Rules.keys(row, ["id", "target", "minutes", "evidence_id", "text_key", "reading_kind"]):
				return {}
			for field: String in ["id", "target", "evidence_id", "text_key", "reading_kind"]:
				if not Rules.identifier(row[field]):
					return {}
			if ids.has(row.id) or evidence_ids.has(row.evidence_id) or not Rules.integer(row.minutes, 1, 60) or row.reading_kind not in ["damage_index", "texture", "batch_code", "mark", "side_mark", "function_status"]:
				return {}
			ids[row.id] = true
			evidence_ids[row.evidence_id] = true
	for id: Variant in raw.specimens:
		var specimen: Variant = raw.specimens[id]
		if not Rules.identifier(id) or not Rules.keys(specimen, ["def_id", "provenance", "readings"]) or not Rules.identifier(specimen.def_id) or not raw.profiles.has(specimen.def_id) or not Rules.identifier(specimen.provenance) or not specimen.readings is Dictionary:
			return {}
		var rows: Array = raw.profiles[specimen.def_id].tools
		if specimen.readings.size() != rows.size():
			return {}
		for row: Dictionary in rows:
			if not valid_reading(row.reading_kind, specimen.readings.get(row.id)):
				return {}
	return Rules.normalized(raw)

static func legacy_book() -> Dictionary:
	if _legacy.is_empty():
		_legacy = parse(Documents.read_object(PATH))
	return _legacy.duplicate(true)

## Definition-based tool selection; result has no specimen or sample values.
static func tools_for(book: Dictionary, def_id: String) -> Dictionary:
	var result: Dictionary = {}
	for row: Dictionary in book.get("profiles", {}).get(def_id, {}).get("tools", []):
		result[row.id] = {"target": row.target, "minutes": row.minutes, "evidence_id": row.evidence_id, "text_key": row.text_key}
	return result

static func legacy_reading(book: Dictionary, item_id: String, def_id: String, provenance: String, tool_id: String) -> Dictionary:
	var s: Dictionary = book.get("specimens", {}).get(item_id, {})
	if s.is_empty() or s.def_id != def_id or s.provenance != provenance:
		return {}
	for tool: Dictionary in book.profiles[def_id].tools:
		if tool.id == tool_id and s.readings.has(tool_id):
			return {"kind": tool.reading_kind, "value": s.readings[tool_id]}
	return {}

## Region-to-observation lookup shared with abstract composite profiles.
static func region_spec(regions: Array, key: String) -> Dictionary:
	for region: Dictionary in regions:
		for tool: String in region.tools:
			if region.tools[tool] == key:
				return {"region_id": region.id, "region_label_key": region.label_key, "tool_key": tool}
	return {}

## A common clock preview, called only with authority-derived duration/access.
static func preview(minute: int, minutes: int, known: bool) -> Dictionary:
	return Clock.inspection_at(minute, minutes, not known)
