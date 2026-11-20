extends RefCounted
## Links are references to observations, not truth or verification of a candidate.
const Slots = preload("res://src/domain/appraisal_card_dialogue.gd")
static func valid(record: Dictionary, links: Variant) -> bool:
	if not links is Dictionary or links.size() > Slots.SLOTS.size():
		return false
	for slot: Variant in links:
		if slot not in Slots.SLOTS or record.get(slot) == null or not links[slot] is Array or links[slot].is_empty() or links[slot].size() > record.evidence.size():
			return false
		var previous: String = ""
		for id: Variant in links[slot]:
			if not id is String or not record.evidence.has(id) or (not previous.is_empty() and id <= previous):
				return false
			previous = id
	return true

static func placement_valid(before: Dictionary, after: Dictionary, links: Variant, slot: Variant) -> bool:
	if slot not in Slots.SLOTS:
		return false
	var expected: Dictionary = before.get("card_links", {}).duplicate(true)
	if after.get(slot) == null:
		expected.erase(slot)
	var candidate: Dictionary = after.duplicate(true)
	candidate["evidence"] = before.evidence
	return valid(candidate, links) and links == expected

static func edit_valid(record: Dictionary, links: Variant, slot: Variant) -> bool:
	if slot not in Slots.SLOTS or record.get(slot) == null or not valid(record, links):
		return false
	var before: Dictionary = record.get("card_links", {})
	for field: String in Slots.SLOTS:
		if field != slot and before.get(field, []) != links.get(field, []):
			return false
	var old: Array = before.get(slot, [])
	var next: Array = links.get(slot, [])
	var changes: int = 0
	for id: String in old:
		if id not in next:
			changes += 1
	for id: String in next:
		if id not in old:
			changes += 1
	return changes == 1
