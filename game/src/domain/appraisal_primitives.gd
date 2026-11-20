extends RefCounted
## Pure reference arithmetic and business inspection-time preview.
## Only public catalog values selected by the player are inputs to reference arithmetic.
## No actual item truth, customer price floor, or mutable state belongs here.
const Rules = preload("res://src/domain/value_rules.gd")
const Clock = preload("res://src/domain/business_clock.gd")
const CLOSE_MINUTE: int = Clock.BUSINESS_MINUTES
const MAX_PERCENT: int = 500

## Pure ID lookup over public candidate tables.
static func selected_value(entries: Array, id: Variant, field: String) -> Variant:
	for entry: Dictionary in entries:
		if entry.id == id:
			return entry.get(field)
	return null

static func reference_preview(base_reference: Variant, selected_percent: Variant) -> Dictionary:
	if base_reference == null:
		return {"ok": true, "base_reference": null, "estimate": null, "partial": true}
	if not Rules.integer(base_reference):
		return {"ok": false, "error": "reference_base"}
	if selected_percent == null:
		return {"ok": true, "base_reference": int(base_reference), "estimate": null, "partial": true}
	if not Rules.integer(selected_percent, 0, MAX_PERCENT):
		return {"ok": false, "error": "reference_modifier"}
	# Nearest whole currency unit, integer half-up; fixture 200 * 80% = 160.
	@warning_ignore("integer_division")
	var result: int = (int(base_reference) * int(selected_percent) + 50) / 100
	if not Rules.integer(result):
		return {"ok": false, "error": "reference_limit"}
	return {"ok": true, "base_reference": int(base_reference), "estimate": result, "partial": true}

## Business only, uses prior validated evidence knowledge; not an authority for actual inspection.
## Already-known information may be reviewed free, including at closing.
## Actual novel observations must be committed atomically by the session.
static func inspection_preview(minute_of_day: Variant, duration: Variant, new_evidence: Variant) -> Dictionary:
	# Compatibility wrapper retains the first-day fixture boundary.
	if not Rules.integer(minute_of_day, 0, CLOSE_MINUTE):
		return {"ok": false, "error": "inspection_shape"}
	return Clock.inspection_at(minute_of_day, duration, new_evidence)
