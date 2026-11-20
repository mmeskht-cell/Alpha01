extends RefCounted
## P1: latest committed card dialogue; no truth, discounts, claims or relation effects.
## The slot is bound to the existing hypothesis receipt (including archived receipts).
const SLOTS: Array = ["model_id", "appearance_id", "material_id", "batch_id"]

static func single_change(before: Dictionary, after: Dictionary, slot: Variant) -> bool:
	if slot not in SLOTS or before.get(slot) == after.get(slot):
		return false
	for field: String in SLOTS:
		if field != slot and before.get(field) != after.get(field):
			return false
	return true

static func project(record: Dictionary, catalog: Dictionary) -> Dictionary:
	var slot: Variant = record.get("card_slot")
	if slot not in SLOTS:
		return {}
	var value: Variant = record.get(slot)
	var group: String = {"model_id":"model_candidates","appearance_id":"appearance_candidates","material_id":"material_candidates","batch_id":"batch_candidates"}[slot]
	var key: String = "ui.unconfirmed"
	if value != null:
		for candidate: Dictionary in catalog.get(group, []):
			if candidate.id == value:
				key = candidate.get("name_key", candidate.get("label_key",""))
				break
	return {"action_id":record.hypothesis_action_id,"slot":slot,"label_key":key,"speaker_key":"appraisal.card_clear" if value == null else "appraisal.card_" + str(slot),"response_key":"appraisal.customer_clear" if value == null else "appraisal.customer_" + str(slot)}
