extends RefCounted
## Compact only nonfinancial component facts/hypotheses after a successful candidate edit.
## A superseded receipt retains its original request hash, revision, type and direct
## link to the surviving record. No chain traversal, no replay of the old action.
const Receipt = preload("res://src/domain/receipt_primitives.gd")
const Rules = preload("res://src/domain/value_rules.gd")
const Component = preload("res://src/domain/component_appraisal.gd")
const Customer = preload("res://src/domain/customer_inspection.gd")

static func compact(state: Dictionary, observation_keys: Array) -> void:
	if state.has("campaign"):
		return
	var latest: Dictionary = {}
	var redirects: Dictionary = {}
	for id: String in state.knowledge:
		var record: Dictionary = state.knowledge[id]
		if record.observation_key not in observation_keys:
			continue
		var slot: String = record.item_id + ":" + record.observation_key
		if not latest.has(slot) or Receipt.receipt_revision(state, id) > Receipt.receipt_revision(state, latest[slot]):
			latest[slot] = id
	for id: String in state.knowledge.keys():
		var record: Dictionary = state.knowledge[id]
		if record.observation_key not in observation_keys:
			continue
		var survivor: String = latest[record.item_id + ":" + record.observation_key]
		if id != survivor:
			_retire(state, id, survivor, "observe", record.item_id + ":" + record.observation_key)
			redirects[id] = survivor
			state.knowledge.erase(id)
	var hypotheses: Dictionary = state.get("component_hypotheses", {})
	latest.clear()
	for id: String in hypotheses:
		var item_id: String = hypotheses[id].item_id
		if not latest.has(item_id) or Receipt.receipt_revision(state, id) > Receipt.receipt_revision(state, latest[item_id]):
			latest[item_id] = id
	for id: String in hypotheses.keys():
		var survivor: String = latest[hypotheses[id].item_id]
		if id != survivor:
			_retire(state, id, survivor, "record_component_hypothesis", hypotheses[id].item_id)
			redirects[id] = survivor
			hypotheses.erase(id)

	if not redirects.is_empty():
		for old: String in state.receipt_archive:
			var row: Array = state.receipt_archive[old]
			if row.size() == 4 and redirects.has(row[3][0]):
				row[3][0] = redirects[row[3][0]]

static func _retire(state: Dictionary, id: String, survivor: String, kind: String, slot: String) -> void:
	var revision: int = Receipt.receipt_revision(state, id)
	var digest: String
	if state.receipts.has(id):
		digest = state.receipts[id].fingerprint.sha256_text()
		state.receipts.erase(id)
	else:
		digest = state.receipt_archive[id][0]
	state.receipt_archive[id] = [digest, revision, kind, [survivor, slot]]

static func valid_link(state: Dictionary, id: String, observation_keys: Array) -> bool:
	var row: Array = state.receipt_archive[id]
	if row.size() != 4 or state.has("campaign") or row[2] not in ["observe", "record_component_hypothesis"] or not row[3] is Array or row[3].size() != 2 or not row[3][0] is String or not row[3][1] is String or row[3][0] == id:
		return false
	var target: String = row[3][0]
	var slot: String = row[3][1]
	if not state.receipts.has(target) and not state.receipt_archive.has(target):
		return false
	if Receipt.receipt_revision(state, target) <= int(row[1]):
		return false
	if state.receipt_archive.has(target) and state.receipt_archive[target].size() != 3:
		return false
	if row[2] == "observe":
		if state.knowledge.has(id) or not state.knowledge.has(target) or not state.knowledge[target] is Dictionary:
			return false
		var fact: Dictionary = state.knowledge[target]
		if not Rules.identifier(fact.get("item_id")) or fact.get("observation_key") not in observation_keys or slot != fact.item_id + ":" + fact.observation_key or not Receipt.matches_receipt(state, id, "observe", {"actor": "player", "item_id": fact.item_id, "key": fact.observation_key}, int(row[1])):
			return false
		var item: Dictionary = state.items.get(fact.item_id, state.tombstones.get(fact.item_id, {}))
		return Customer.historical_access(state, fact.item_id, fact.observation_key, int(row[1]), not Component.observation_spec(item, fact.observation_key, true).is_empty())
	var records: Variant = state.get("component_hypotheses", {})
	if not records is Dictionary or records.has(id) or not records.has(target) or not records[target] is Dictionary or records[target].get("item_id") != slot or not Rules.identifier(slot):
		return false
	var item: Dictionary = state.items.get(slot, state.tombstones.get(slot, {}))
	return Customer.historical_access(state, slot, "", int(row[1]), not Component.regions(item, true).is_empty())
