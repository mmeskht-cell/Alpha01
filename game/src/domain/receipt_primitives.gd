extends RefCounted
## Shared receipt lookup. No dependency on a specific visit or appraisal fixture.
const Rules = preload("res://src/domain/value_rules.gd")

static func matches_receipt(state: Dictionary, id: Variant, kind: String, payload: Dictionary, revision: int) -> bool:
	if not Rules.identifier(id) or revision < 1:
		return false
	var expected: String = Rules.canonical({"action_id": id, "expected_revision": revision - 1, "type": kind, "payload": payload})
	if state.receipts.has(id):
		return state.receipts[id].result.revision == revision and state.receipts[id].fingerprint == expected
	if state.receipt_archive.has(id):
		var row: Array = state.receipt_archive[id]
		return row[1] == revision and row[2] == kind and row[0] == expected.sha256_text()
	return false

static func receipt_revision(state: Dictionary, id: Variant) -> int:
	if not Rules.identifier(id):
		return -1
	if state.receipts.has(id):
		return int(state.receipts[id].result.revision)
	if state.receipt_archive.has(id):
		return int(state.receipt_archive[id][1])
	return -1

static func receipt_type(state: Dictionary, id: String) -> String:
	if state.receipts.has(id):
		return str(JSON.parse_string(state.receipts[id].fingerprint).type)
	return str(state.receipt_archive[id][2]) if state.receipt_archive.has(id) else ""
