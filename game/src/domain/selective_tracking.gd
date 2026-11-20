extends RefCounted
## Technical L2 selection contract, not campaign event activation.
## No hidden tier/owner or novel narrative text in public DTOs.
const Rules = preload("res://src/domain/value_rules.gd")
const Registry = preload("res://src/domain/dormant_registry.gd")
const MAX_TRACKED: int = 10
const MAX_AUTHORED: int = 2
const MAX_RECORDS: int = 128
const MAX_REFS: int = 32

static func _ref_exists(full: Dictionary, id: String, ref: String) -> bool:
	if full.knowledge.has(ref):
		return full.knowledge[ref].item_id == id
	for row: Dictionary in full.ledger:
		if row.event_id == ref:
			return id in row.item_ids
	for row: Dictionary in full.object_events:
		if row.event_id == ref:
			return id in row.item_ids
	return false

static func valid(partition: Dictionary, full: Dictionary) -> bool:
	if partition.tracking.size() > MAX_RECORDS:
		return false
	var tracked: int = 0
	var authored: int = 0
	for id: Variant in partition.tracking:
		var row: Variant = partition.tracking[id]
		if not Rules.identifier(id) or Registry.locate(partition, id) == "unknown" or not Rules.keys(row, ["tier", "enabled", "pinned", "refs"]) or row.tier not in ["tracked", "narrative"] or not row.enabled is bool or not row.pinned is bool or not row.refs is Array or row.refs.size() > MAX_REFS or (row.pinned and not row.enabled):
			return false
		var seen: Dictionary = {}
		for ref: Variant in row.refs:
			if not Rules.identifier(ref) or seen.has(ref) or not _ref_exists(full, id, ref):
				return false
			seen[ref] = true
		if row.enabled:
			if Registry.locate(partition, id) == "terminal":
				return false
			tracked += 1
			if row.tier == "narrative":
				authored += 1
	return tracked <= MAX_TRACKED and authored <= MAX_AUTHORED

static func promote(partition: Dictionary, id: String, tier: String, pin: bool, authority: RefCounted) -> Dictionary:
	var full: Dictionary = Registry.materialize(partition, authority)
	if full.is_empty() or not valid(partition, full) or Registry.locate(partition, id) not in ["active", "dormant"] or tier not in ["tracked", "narrative"]:
		return {}
	var result: Dictionary = partition.duplicate(true)
	var old: Dictionary = result.tracking.get(id, {"refs": [], "pinned": false})
	if old.pinned and (not pin or tier != old.tier):
		return {}
	result.tracking[id] = {"tier": tier, "enabled": true, "pinned": pin, "refs": old.refs}
	return result if valid(result, full) else {}

static func retain_reference(partition: Dictionary, id: String, event_id: String, authority: RefCounted) -> Dictionary:
	var full: Dictionary = Registry.materialize(partition, authority)
	if full.is_empty() or not valid(partition, full) or not partition.tracking.has(id) or not partition.tracking[id].enabled or not _ref_exists(full, id, event_id):
		return {}
	var result: Dictionary = partition.duplicate(true)
	if event_id not in result.tracking[id].refs:
		result.tracking[id].refs.append(event_id)
	return result if valid(result, full) else {}

static func suspend(partition: Dictionary, id: String, authority: RefCounted) -> Dictionary:
	var full: Dictionary = Registry.materialize(partition, authority)
	if full.is_empty() or not valid(partition, full) or not partition.tracking.has(id) or partition.tracking[id].pinned:
		return {}
	if not can_suspend(full, id):
		return {}
	var result: Dictionary = partition.duplicate(true)
	result.tracking[id].enabled = false
	return result if valid(result, full) else {}

## Shared with the storage boundary, so direct candidate replacement cannot
## bypass ancestor/visit/service protection. The pin check remains separate.
static func can_suspend(full: Dictionary, id: String) -> bool:
	var row: Dictionary = full.items.get(id, {})
	var root_id: String = str(row.get("parent_id", ""))
	var root: Dictionary = full.items.get(root_id, {})
	for member: Dictionary in [row, root]:
		if not member.is_empty() and (member.protected or member.service_permission or not member.reservation_id.is_empty() or member.status != "stock"):
			return false
	if id == "W001":
		var service: Variant = full.get("day_one", {}).get("service")
		if service is Dictionary and service.status in ["offered", "accepted", "complete"]:
			return false
	for visit: Dictionary in full.visits.values():
		if not visit.scope.completed and int(visit.expires) >= int(full.game_minutes) and (visit.prices.has(id) or id in visit.scope.required_ids or visit.prices.has(root_id) or root_id in visit.scope.required_ids):
			return false
	return true
