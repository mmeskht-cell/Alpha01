extends RefCounted
## Shared schema3 record factory and receipt binding for server-sampled observations.
## Call only after the authority has checked item access and sampled actual state.
## This helper neither decides permission nor samples item truth.
const Rules = preload("res://src/domain/value_rules.gd")
const Evidence = preload("res://src/domain/evidence_primitives.gd")
const Receipt = preload("res://src/domain/receipt_primitives.gd")
const FIELDS: Array = ["evidence_id", "item_id", "observer_id", "visibility", "observation_key", "source_type", "observed_at", "observed_value", "dependent_field_versions"]

static func capture(id: String, item_id: String, key: String, source: String, minute: int, value: Variant, dependencies: Dictionary) -> Dictionary:
	var record: Dictionary = {"evidence_id": id, "item_id": item_id, "observer_id": "player", "visibility": "player", "observation_key": key, "source_type": source, "observed_at": minute, "observed_value": value, "dependent_field_versions": dependencies.duplicate(true)}
	if source not in ["instrument", "record"] or Evidence.public_view(record, dependencies, item_id).is_empty():
		return {}
	return record

## Both retained full requests and compacted fingerprints bind exactly the
## same item, actor and observation key. Values/versions require caller validation.
static func bound(state: Dictionary, id: Variant, record: Variant, source: String) -> bool:
	if not Rules.identifier(id) or not Rules.keys(record, FIELDS) or record.evidence_id != id or record.observer_id != "player" or record.visibility != "player" or record.source_type != source:
		return false
	if source not in ["instrument", "record"] or not Rules.integer(record.observed_at, 0, int(state.game_minutes)) or not Rules.identifier(record.item_id) or not Rules.identifier(record.observation_key):
		return false
	if Evidence.public_view(record, record.dependent_field_versions, record.item_id).is_empty():
		return false
	var p:Dictionary={"actor":"player","item_id":record.item_id,"key":record.observation_key}
	var revision:int=Receipt.receipt_revision(state,id)
	if Receipt.matches_receipt(state,id,"observe",p,revision):
		return true
	if source!="record" or not state.has("calendar"):
		return false
	p["owned_review"]=true
	return Receipt.matches_receipt(state,id,"observe",p,revision)
