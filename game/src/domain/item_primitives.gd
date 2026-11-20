extends RefCounted
## Pure generic item helpers. Not connected to GameSession until Gate 0-C.
const Rules = preload("res://src/domain/value_rules.gd")

## Allocate one currency's nonnegative integer cost among existing item IDs.
## An empty result means invalid input. No state or inventory is mutated.
## The sum of weights is capped at Rules.LIMIT to keep 64-bit products safe.
static func allocate_cost(total: Variant, weights: Variant) -> Dictionary:
	if not Rules.integer(total) or not weights is Dictionary or weights.is_empty():
		return {}
	var ids: Array = weights.keys()
	var weight_sum: int = 0
	for item_id: Variant in ids:
		if not Rules.identifier(item_id) or not Rules.integer(weights[item_id], 1):
			return {}
		weight_sum += int(weights[item_id])
		if weight_sum > Rules.LIMIT:
			return {}
	ids.sort()
	var result: Dictionary = {}
	var allocated: int = 0
	for item_id: String in ids:
		@warning_ignore("integer_division")
		var share: int = (int(total) * int(weights[item_id])) / weight_sum
		result[item_id] = share
		allocated += share
	var remainder: int = int(total) - allocated
	for index: int in range(remainder):
		result[ids[index]] += 1
	return result

## Presentation helper; input MUST be a known-observation DTO, not item truth.
## Missing evidence is unknown. Nonfunctional/incomplete evidence takes priority.
## For atomic items, the caller may provide complete=true by definition.
static func quality_from_observations(known: Dictionary) -> String:
	var functional: Variant = known.get("functional")
	var complete: Variant = known.get("complete")
	var restored: Variant = known.get("restored")
	if (functional is bool and functional == false) or (complete is bool and complete == false):
		return "inoperable"
	if not functional is bool or not complete is bool or not restored is bool:
		return "unknown"
	return "refurbished" if restored else "serviceable"

## Sum individually allocated basis for an explicitly validated family.
## Unknown historical basis is null, never silently zero. No FX conversion.
## Caller supplies exactly the active IDs in the transaction/disposal preview.
static func sum_basis(basis_by_id: Variant, item_ids: Variant) -> Dictionary:
	if not basis_by_id is Dictionary or not item_ids is Array or item_ids.is_empty() or item_ids.size() > 128:
		return {"ok": false, "error": "basis_shape"}
	var sums: Dictionary = {"VKC": 0, "USD": 0}
	var known: Dictionary = {"VKC": true, "USD": true}
	var seen: Dictionary = {}
	for item_id: Variant in item_ids:
		if not Rules.identifier(item_id) or seen.has(item_id) or not basis_by_id.has(item_id):
			return {"ok": false, "error": "basis_id"}
		seen[item_id] = true
		var record: Variant = basis_by_id[item_id]
		if not Rules.keys(record, ["VKC", "USD"]):
			return {"ok": false, "error": "basis_currency"}
		for currency: String in ["VKC", "USD"]:
			if record[currency] == null:
				known[currency] = false
				continue
			if not Rules.integer(record[currency]):
				return {"ok": false, "error": "basis_amount"}
			sums[currency] += int(record[currency])
			if sums[currency] > Rules.LIMIT:
				return {"ok": false, "error": "basis_limit"}
	for currency: String in ["VKC", "USD"]:
		if not known[currency]:
			sums[currency] = null
	return {"ok": true, "basis": sums}
