extends RefCounted
## Detached technical partition of a validated legacy state, not a second authority.
## Full rows retained for exact restoration. Host inventories deferred: fail closed.
const Rules = preload("res://src/domain/value_rules.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const LIMIT: int = 128

static func open_family(state: Dictionary, root: String) -> bool:
	if not state.items.has(root) or not state.items[root].parent_id.is_empty():
		return false
	var ids: Array = Objects.family(state, root)
	for id: String in ids:
		var row: Dictionary = state.items[id]
		if row.owner_id == "player" or row.custodian_id == "player" or row.owner_id != row.custodian_id or row.status != "stock" or row.protected or row.service_permission or not row.reservation_id.is_empty():
			return false
		for grid: Dictionary in state.inventories.values():
			if grid.host_item == id:
				return false
	var item: Dictionary = state.items[root]
	if not state.inventories.has(item.inventory) or not state.inventories[item.inventory].host_item.is_empty():
		return false
	for visit: Dictionary in state.visits.values():
		if not visit.scope.completed and int(visit.expires) >= int(state.game_minutes):
			for id: String in ids:
				if visit.prices.has(id) or id in visit.scope.required_ids:
					return false
	# Explicit day-one service contract remains protected until terminal resolution.
	if "W001" in ids:
		var service: Variant = state.get("day_one", {}).get("service")
		if service is Dictionary and service.status in ["offered", "accepted", "complete"]:
			return false
	return true

static func begin(validated: Dictionary, authority: RefCounted) -> Dictionary:
	if not authority.validate(validated):
		return {}
	return {"state": validated.duplicate(true), "dormant": {}, "tracking": {}}

## Restore original authority shape; ensure exact disjoint ID resolution before
## running authoritative schema/finance/evidence/placement checks.
static func materialize(partition: Dictionary, authority: RefCounted) -> Dictionary:
	if not Rules.keys(partition, ["state", "dormant", "tracking"]) or not partition.state is Dictionary or not partition.dormant is Dictionary or not partition.tracking is Dictionary or not partition.state.get("items") is Dictionary or not partition.state.get("tombstones") is Dictionary or partition.dormant.size() > LIMIT:
		return {}
	var restored: Dictionary = partition.state.duplicate(true)
	for root: Variant in partition.dormant:
		var family: Variant = partition.dormant[root]
		if not Rules.identifier(root) or not family is Dictionary or not family.has(root) or family.is_empty() or family.size() > 9:
			return {}
		for id: Variant in family:
			var row: Variant = family[id]
			if not Rules.identifier(id) or restored.items.has(id) or restored.tombstones.has(id) or not Rules.keys(row, Objects.ITEM_FIELDS) or row.parent_id != ("" if id == root else root):
				return {}
			restored.items[id] = row.duplicate(true)
	if not authority.validate(restored):
		return {}
	for root: String in partition.dormant:
		var family: Dictionary = partition.dormant[root]
		var ids: Array = Objects.family(restored, root)
		if ids.size() != family.size() or not open_family(restored, root):
			return {}
		for id: String in ids:
			if not family.has(id):
				return {}
	return restored

static func sleep_family(partition: Dictionary, root: String, authority: RefCounted) -> Dictionary:
	var full: Dictionary = materialize(partition, authority)
	if full.is_empty() or not partition.state.items.has(root) or not open_family(full, root):
		return {}
	var result: Dictionary = partition.duplicate(true)
	var family: Dictionary = {}
	for id: String in Objects.family(full, root):
		if not result.state.items.has(id):
			return {}
		family[id] = result.state.items[id]
		result.state.items.erase(id)
	result.dormant[root] = family
	return result if materialize(result, authority) == full else {}

## Return same family to its preserved position. Real future placement and
## reentry must be new authority commands, not this reversible storage operation.
static func wake_family(partition: Dictionary, root: String, authority: RefCounted) -> Dictionary:
	var full: Dictionary = materialize(partition, authority)
	if full.is_empty() or not partition.dormant.has(root):
		return {}
	var result: Dictionary = partition.duplicate(true)
	for id: String in result.dormant[root]:
		result.state.items[id] = result.dormant[root][id]
	result.dormant.erase(root)
	return result if materialize(result, authority) == full else {}

static func locate(partition: Dictionary, id: String) -> String:
	if partition.state.items.has(id):
		return "active"
	if partition.state.tombstones.has(id):
		return "terminal"
	for family: Dictionary in partition.dormant.values():
		if family.has(id):
			return "dormant"
	return "unknown"
