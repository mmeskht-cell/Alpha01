extends RefCounted
## General lifecycle identity boundary for the next campaign domain.
## Separate active geometry from dormant historical location. Does not
## authorize a trade, create an event, or replace full campaign validation.
const Rules = preload("res://src/domain/value_rules.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const Relations = preload("res://src/domain/object_relation_primitives.gd")
const Registry = preload("res://src/domain/dormant_registry.gd")
const Tracking = preload("res://src/domain/selective_tracking.gd")

static func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code}

static func _refs(ids: Variant, index: Dictionary, active_only: bool = false) -> bool:
	if not ids is Array or ids.is_empty() or ids.size() > 128:
		return false
	var seen: Dictionary = {}
	for id: Variant in ids:
		if not Rules.identifier(id) or not index.has(id) or seen.has(id) or (active_only and index[id] != "active"):
			return false
		seen[id] = true
	return true

## defs and non-object domain shape come from the trusted content/authority.
## Dormant roots do NOT reserve active grid cells. Old inventory and position
## are historical; reentry must supply a new validated placement.
static func audit(partition: Variant, defs: Dictionary) -> Dictionary:
	if not Rules.keys(partition, ["state", "dormant", "tracking"]) or not partition.state is Dictionary or not partition.dormant is Dictionary or not partition.tracking is Dictionary or partition.dormant.size() > Registry.LIMIT:
		return _error("partition_shape")
	var state: Dictionary = partition.state
	for key: String in ["items", "tombstones", "inventories", "wallets", "visits", "knowledge"]:
		if not state.get(key) is Dictionary:
			return _error("state_shape")
	for key: String in ["ledger", "object_events"]:
		if not state.get(key) is Array:
			return _error("state_shape")
	if not Rules.integer(state.get("revision")) or not Rules.integer(state.get("game_minutes"), 0, 60480) or state.get("object_schema") != 3 or state.get("phase") not in ["shop", "workshop"]:
		return _error("state_shape")
	if state.items.size() > Relations.MAX_ACTIVE or not Objects.validate(state, defs):
		return _error("active_geometry")
	var index: Dictionary = {}
	for id: String in state.items:
		index[id] = "active"
	for id: String in state.tombstones:
		index[id] = "terminal"
	var dormant_count: int = 0
	for root: Variant in partition.dormant:
		var family: Variant = partition.dormant[root]
		if not Rules.identifier(root) or not family is Dictionary or not family.has(root) or family.size() > 9:
			return _error("family_shape")
		for id: Variant in family:
			var row: Variant = family[id]
			if not Rules.identifier(id) or index.has(id) or not Rules.keys(row, Objects.ITEM_FIELDS) or row.parent_id != ("" if id == root else root):
				return _error("identity_collision")
			index[id] = "dormant"
			dormant_count += 1
		var item: Dictionary = family[root]
		if not Rules.identifier(item.inventory) or not state.inventories.has(item.inventory) or not state.inventories[item.inventory].host_item.is_empty():
			return _error("dormant_host")
		# Only this historical family is passed to the object validator.
		# No other active/dormant family's footprint is inserted.
		var local: Dictionary = {"object_schema": 3, "phase": state.phase, "revision": state.revision, "game_minutes": state.game_minutes, "items": family, "inventories": {item.inventory: state.inventories[item.inventory]}, "wallets": state.wallets, "tombstones": {}, "object_events": [], "visits": {}, "knowledge": {}}
		if not Objects.validate(local, defs):
			return _error("dormant_geometry")
		for id: String in family:
			var row: Dictionary = family[id]
			if row.owner_id == "player" or row.custodian_id == "player" or row.owner_id != row.custodian_id or row.status != "stock" or row.protected or row.service_permission or not row.reservation_id.is_empty():
				return _error("dormant_permission")
		if "W001" in family:
			var service: Variant = state.get("day_one", {}).get("service")
			if service is Dictionary and service.status in ["offered", "accepted", "complete"]:
				return _error("dormant_service")
	for visit: Variant in state.visits.values():
		if not visit is Dictionary or not visit.get("scope") is Dictionary or not visit.get("prices") is Dictionary or not visit.scope.get("required_ids") is Array or not visit.scope.get("completed") is bool or not Rules.integer(visit.get("expires"), 0, 60480):
			return _error("visit_shape")
		var pending: bool = not visit.scope.completed and int(visit.expires) >= int(state.game_minutes)
		if not _refs(visit.prices.keys(), index) or (not visit.scope.required_ids.is_empty() and not _refs(visit.scope.required_ids, index)):
			return _error("visit_reference")
		if pending:
			# Authored conditional ordinary resale inquiries are not reservations.
			# A disposed player-owned item may keep its historical inquiry ID,
			# but the queue must never admit that inquiry or treat it as a sale.
			# All other pending refs still require active identities.
			var calendar:Dictionary=state.get("calendar",{})
			var queue:Dictionary=calendar.get("queue",{})
			var conditional:bool=calendar.get("profile",{}).get("content_version") in ["demo7-integrated-1","demo7-integrated-2","demo7-integrated-3"] and not queue.is_empty() and queue.get("active")!=visit.scope.get("visit_id") and visit.scope.get("kind")=="ordinary" and visit.scope.get("purpose")=="sale" and visit.get("seller")=="player" and visit.scope.required_ids.is_empty()
			for item_id:String in visit.prices:
				if index[item_id]=="active":
					continue
				if not conditional or index[item_id]!="terminal" or state.tombstones[item_id].owner_id!="player" or state.tombstones[item_id].custodian_id!="player":
					return _error("visit_reference")
			if not visit.scope.required_ids.is_empty() and not _refs(visit.scope.required_ids,index,true):
				return _error("visit_reference")
	for row: Variant in state.ledger:
		if not row is Dictionary or not _refs(row.get("item_ids"), index) or not _refs(row.get("root_ids"), index):
			return _error("ledger_reference")
	for row: Variant in state.object_events:
		if not row is Dictionary or not _refs(row.get("item_ids"), index):
			return _error("event_reference")
	for row: Variant in state.knowledge.values():
		if not row is Dictionary or not _refs([row.get("item_id")], index):
			return _error("knowledge_reference")
	for row: Variant in state.get("component_hypotheses", {}).values():
		if not row is Dictionary or not _refs([row.get("item_id")], index):
			return _error("hypothesis_reference")
	if not Tracking.valid(partition, state):
		return _error("tracking_reference")
	return {"ok": true, "active_count": state.items.size(), "dormant_count": dormant_count, "terminal_count": state.tombstones.size(), "index": index}

## Detached candidate only. A future campaign authority must commit the
## lifecycle event and advance revision. Reentry is never an ownership change.
static func wake_candidate(partition: Dictionary, defs: Dictionary, root: String, inventory: String, x: int, y: int, rotated: bool) -> Dictionary:
	var before: Dictionary = audit(partition, defs)
	if not before.ok or not partition.dormant.has(root):
		return {}
	var family: Dictionary = partition.dormant[root]
	if before.active_count + family.size() > Relations.MAX_ACTIVE or not partition.state.inventories.has(inventory):
		return {}
	var item: Dictionary = family[root]
	if partition.state.inventories[inventory].owner_id != item.custodian_id or not partition.state.inventories[inventory].host_item.is_empty():
		return {}
	var next: Dictionary = partition.duplicate(true)
	for id: String in family:
		next.state.items[id] = family[id].duplicate(true)
	var row: Dictionary = next.state.items[root]
	row.inventory = inventory
	row.x = x
	row.y = y
	row.rotated = rotated
	row.version += 1
	next.dormant.erase(root)
	return next if audit(next, defs).ok else {}

static func sleep_candidate(partition: Dictionary, defs: Dictionary, root: String) -> Dictionary:
	if not audit(partition, defs).ok or not Registry.open_family(partition.state, root):
		return {}
	var next: Dictionary = partition.duplicate(true)
	var family: Dictionary = {}
	for id: String in Objects.family(next.state, root):
		family[id] = next.state.items[id]
		next.state.items.erase(id)
	next.dormant[root] = family
	return next if audit(next, defs).ok else {}
