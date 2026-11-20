extends RefCounted
## Pure evidence freshness / public projection for generic fictional objects.
## Call with server/session-owned evidence and field versions, never client truth.
## Record authenticity, item access and meaning of a specific observation are
## validated by the authority; this helper is not a source of observations.
const Rules = preload("res://src/domain/value_rules.gd")
const SOURCES: Array = ["customer", "visual", "instrument", "record"]
const MAX_DEPENDENCIES: int = 32

static func is_current(dependencies: Variant, current_versions: Variant) -> bool:
	if not dependencies is Dictionary or not current_versions is Dictionary or dependencies.size() > MAX_DEPENDENCIES:
		return false
	for field: Variant in dependencies:
		if not Rules.identifier(field) or not Rules.integer(dependencies[field]):
			return false
		if not current_versions.has(field) or not Rules.integer(current_versions[field]) or current_versions[field] != dependencies[field]:
			return false
	return true

## Whitelist projection. Additional internal properties never enter the result.
## An unauthorized/invalid record returns an empty dictionary, not a hidden label.
## Visibility names are provisional for integration, not a final save schema.
static func public_view(record: Variant, current_versions: Variant, expected_item: Variant) -> Dictionary:
	if not record is Dictionary or record.get("visibility") != "player" or not Rules.identifier(expected_item):
		return {}
	for key: String in ["evidence_id", "item_id", "observation_key"]:
		if not Rules.identifier(record.get(key)):
			return {}
	if record.item_id != expected_item or record.get("source_type") not in SOURCES or not Rules.integer(record.get("observed_at"), 0, 60480):
		return {}
	if not record.has("observed_value") or not record.get("dependent_field_versions") is Dictionary:
		return {}
	var value: Variant = record.observed_value
	# A display-safe scalar is still rendered as plain text by the caller.
	if not (value is bool or Rules.integer(value, -Rules.LIMIT) or (value is String and value.length() <= 128 and value.find("\n") == -1 and value.find("\r") == -1)):
		return {}
	for field: Variant in record.dependent_field_versions:
		if not Rules.identifier(field) or not Rules.integer(record.dependent_field_versions[field]):
			return {}
	if record.dependent_field_versions.size() > MAX_DEPENDENCIES:
		return {}
	var fresh: bool = is_current(record.dependent_field_versions, current_versions)
	return {"evidence_id": record.evidence_id, "item_id": record.item_id, "observation_key": record.observation_key, "observed_value": Rules.normalized(value), "source_type": record.source_type, "observed_at": int(record.observed_at), "current": fresh, "is_claim": record.source_type == "customer"}

## Only current, relevant non-claim evidence may be submitted as a fact.
## Allowed keys must be defined by the actual negotiation/observation contract,
## not chosen by a player. Conflicting facts remain separately recorded.
static func eligible_ground(record: Variant, current_versions: Variant, expected_item: Variant, allowed_keys: Variant) -> bool:
	if not allowed_keys is Array:
		return false
	var view: Dictionary = public_view(record, current_versions, expected_item)
	return not view.is_empty() and view.current and not view.is_claim and view.observation_key in allowed_keys
