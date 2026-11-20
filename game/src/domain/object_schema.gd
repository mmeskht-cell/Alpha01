extends RefCounted
## Stateless schema/projection helpers. The only registry remains GameSession._state.
const Rules = preload("res://src/domain/value_rules.gd")
const Grid = preload("res://src/domain/grid_primitives.gd")
const Relations = preload("res://src/domain/object_relation_primitives.gd")
const Items = preload("res://src/domain/item_primitives.gd")
const Evidence = preload("res://src/domain/evidence_primitives.gd")
const ITEM_FIELDS: Array = ["def_id", "owner_id", "custodian_id", "status", "inventory", "x", "y", "rotated", "version", "parent_id", "basis", "protected", "reservation_id", "provenance_id", "functional", "restored", "field_versions", "hidden_economy", "service_permission"]
const DEFINITION_FIELDS: Array = ["def_id", "category", "localization_key", "render_key", "width", "height", "kind", "weight", "tag", "required_tags", "footprints", "inside", "recombine", "restorable", "observation_minutes", "restore_cost"]

static func definition(raw: Dictionary) -> Dictionary:
	var d: Dictionary = raw.duplicate(true)
	if Rules.keys(raw, ["def_id", "category", "localization_key", "render_key", "width", "height"]):
		d.merge({"kind": "atomic", "weight": 1, "tag": "generic", "required_tags": [], "footprints": {}, "inside": {}, "recombine": false, "restorable": false, "observation_minutes": 0, "restore_cost": {"VKC": 0, "USD": 0}})
	if not Rules.keys(d, DEFINITION_FIELDS):
		return {}
	for field: String in ["def_id", "category", "localization_key", "render_key", "tag"]:
		if not Rules.identifier(d[field]):
			return {}
	if d.kind not in ["atomic", "composite"] or not Rules.integer(d.weight, 1, 10000) or not Rules.integer(d.width, 1, 8) or not Rules.integer(d.height, 1, 8):
		return {}
	if not d.recombine is bool or not d.restorable is bool or not Rules.integer(d.observation_minutes, 0, 60) or not money(d.restore_cost, false):
		return {}
	if not d.required_tags is Array or d.required_tags.size() > 8 or not d.footprints is Dictionary or not d.inside is Dictionary:
		return {}
	var tags: Dictionary = {}
	for tag: Variant in d.required_tags:
		if not Rules.identifier(tag) or tags.has(tag):
			return {}
		tags[tag] = true
	if d.kind == "atomic" and (not tags.is_empty() or not d.footprints.is_empty() or d.recombine):
		return {}
	if d.kind == "composite":
		if tags.is_empty() or not d.inside.is_empty() or d.footprints.size() != tags.size() + 1:
			return {}
		for count: int in range(tags.size() + 1):
			var size: Variant = d.footprints.get(str(count))
			if not size is Array or size.size() != 2 or not Rules.integer(size[0], 1, 8) or not Rules.integer(size[1], 1, 8):
				return {}
	if not d.inside.is_empty() and (not Rules.keys(d.inside, ["width", "height"]) or not Rules.integer(d.inside.width, 1, 10) or not Rules.integer(d.inside.height, 1, 10)):
		return {}
	return Rules.normalized(d)

static func money(value: Variant, unknown_allowed: bool = true) -> bool:
	if not Rules.keys(value, ["VKC", "USD"]):
		return false
	for currency: String in ["VKC", "USD"]:
		if value[currency] == null and unknown_allowed:
			continue
		if not Rules.integer(value[currency]):
			return false
	return true

static func fresh_item(def_id: String, owner: String, inventory: String, x: int, y: int, source: String) -> Dictionary:
	return {"def_id": def_id, "owner_id": owner, "custodian_id": owner, "status": "stock", "inventory": inventory, "x": x, "y": y, "rotated": false, "version": 0, "parent_id": "", "basis": {"VKC": null, "USD": null}, "protected": false, "reservation_id": "", "provenance_id": source, "functional": true, "restored": false, "field_versions": {"functional": 0, "restored": 0, "composition": 0}, "hidden_economy": 0, "service_permission": false}

static func prepare_initial(raw: Dictionary) -> Dictionary:
	var state: Dictionary = raw.duplicate(true)
	if state.has("object_schema"):
		return state
	# Bootstrap compatibility is restricted to a fresh fixture, never an old save migration.
	if state.get("revision") != 0 or not state.get("items") is Dictionary or not state.get("inventories") is Dictionary:
		return state
	state.merge({"object_schema": 3, "tombstones": {}, "object_events": [], "visits": {}, "phase": "shop", "knowledge": {}, "receipt_archive": {}}, false)
	for id: String in state.items:
		var old: Variant = state.items[id]
		if not Rules.keys(old, ITEM_FIELDS.slice(0, 9)):
			return raw.duplicate(true)
		var item: Dictionary = fresh_item(old.def_id, old.owner_id, old.inventory, int(old.x), int(old.y), "bootstrap_" + id)
		item.merge(old, true)
		state.items[id] = item
	for inv: String in state.inventories:
		if not state.inventories[inv] is Dictionary:
			return raw.duplicate(true)
		state.inventories[inv]["host_item"] = ""
	return state

static func nodes(state: Dictionary, defs: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: String in state.items:
		var item: Dictionary = state.items[id]
		result[id] = {"kind": defs[item.def_id].kind, "parent_id": item.parent_id, "container_id": state.inventories[item.inventory].host_item if item.parent_id.is_empty() else "", "owner_id": item.owner_id, "custodian_id": item.custodian_id, "container_capable": not defs[item.def_id].inside.is_empty(), "locked": item.protected or not item.reservation_id.is_empty() or item.status != "stock"}
	return result

static func family(state: Dictionary, root: String) -> Array:
	var ids: Array = [root]
	for id: String in state.items:
		if state.items[id].parent_id == root:
			ids.append(id)
	ids.sort()
	return ids

static func basis(state: Dictionary, ids: Array) -> Dictionary:
	var map: Dictionary = {}
	for id: String in ids:
		map[id] = state.items[id].basis
	return Items.sum_basis(map, ids)

static func complete(state: Dictionary, defs: Dictionary, id: String) -> bool:
	return family(state, id).size() - 1 == defs[state.items[id].def_id].required_tags.size()

static func footprint(state: Dictionary, defs: Dictionary, id: String) -> Array:
	var d: Dictionary = defs[state.items[id].def_id]
	return [d.width, d.height] if d.kind == "atomic" else d.footprints[str(family(state, id).size() - 1)]

## Root inventories are public to their custodian; hosted grids also require
## authority over the host, independently of the incoming item's permissions.
static func destination_accessible(state: Dictionary, inventory: Variant, owner: String, custodian: String) -> bool:
	if not Rules.identifier(inventory) or not state.inventories.has(inventory):
		return false
	var grid: Dictionary = state.inventories[inventory]
	if grid.owner_id != custodian:
		return false
	if grid.host_item.is_empty():
		return true
	var host: Dictionary = state.items.get(grid.host_item, {})
	return not host.is_empty() and host.owner_id == owner and host.custodian_id == custodian and host.status == "stock" and not host.protected and host.reservation_id.is_empty()

static func grids_valid(state: Dictionary, defs: Dictionary) -> bool:
	for inv: String in state.inventories:
		var placements: Array = []
		for id: String in state.items:
			var item: Dictionary = state.items[id]
			if not item.parent_id.is_empty() or item.inventory != inv:
				continue
			var size: Array = footprint(state, defs, id)
			placements.append({"item_id": id, "x": item.x, "y": item.y, "rotated": item.rotated, "width": size[0], "height": size[1]})
		if not Grid.validate(state.inventories[inv].width, state.inventories[inv].height, placements).ok:
			return false
	return true

static func validate(state: Dictionary, defs: Dictionary) -> bool:
	return validation_error(state,defs).is_empty()

## Same validation conditions, named failure for fixture diagnostics.
static func validation_error(state: Dictionary, defs: Dictionary) -> String:
	if state.object_schema != 3 or state.phase not in ["shop", "workshop"] or not state.tombstones is Dictionary or not state.object_events is Array or not state.visits is Dictionary or not state.knowledge is Dictionary:
		return "state_shape"
	var hosts: Dictionary = {}
	for inv: Variant in state.inventories:
		var grid: Variant = state.inventories[inv]
		if not Rules.identifier(inv) or not Rules.keys(grid, ["owner_id", "width", "height", "host_item"]) or not Rules.identifier(grid.owner_id) or not state.wallets.has(grid.owner_id) or not grid.host_item is String:
			return "inventory_shape" + ':' + str(inv)
		if not Rules.integer(grid.width, 1, 10) or not Rules.integer(grid.height, 1, 10):
			return "inventory_dimensions" + ':' + str(inv)
		if not grid.host_item.is_empty():
			if not state.items.has(grid.host_item) or hosts.has(grid.host_item):
				return "inventory_host" + ':' + str(inv)
			hosts[grid.host_item] = inv
	for id: Variant in state.items:
		var item: Variant = state.items[id]
		if not Rules.identifier(id):
			return "item_id_type_or_format:" + str(id) + ":type=" + str(typeof(id))
		if state.tombstones.has(id):
			return "item_tombstone_conflict:" + str(id)
		if not Rules.keys(item, ITEM_FIELDS):
			return "item_fields:" + str(id)
		for key: String in ["def_id", "owner_id", "custodian_id", "provenance_id"]:
			if not Rules.identifier(item[key]):
				return "item_identity" + ':' + str(id)
		if not defs.has(item.def_id) or not state.wallets.has(item.owner_id) or not state.wallets.has(item.custodian_id):
			return "item_definition_or_owner" + ':' + str(id)
		if item.status not in ["stock", "reserved", "custody_service", "custody_pawn"] or not item.parent_id is String or not item.inventory is String or not item.reservation_id is String:
			return "item_status_or_location" + ':' + str(id)
		if not item.reservation_id.is_empty() and not Rules.identifier(item.reservation_id):
			return "reservation_id" + ':' + str(id)
		if item.status == "reserved" and item.reservation_id.is_empty():
			return "reservation_missing" + ':' + str(id)
		if item.owner_id != item.custodian_id and item.status not in ["custody_service", "custody_pawn"]:
			return "custody_status" + ':' + str(id)
		for field: String in ["protected", "functional", "restored", "service_permission", "rotated"]:
			if not item[field] is bool:
				return "item_flags" + ':' + str(id)
		if not Rules.integer(item.version) or not Rules.integer(item.hidden_economy) or not money(item.basis) or not Rules.keys(item.field_versions, ["functional", "restored", "composition"]):
			return "item_version_basis_or_fields" + ':' + str(id)
		for version: Variant in item.field_versions.values():
			if not Rules.integer(version, 0, int(item.version)):
				return "field_version" + ':' + str(id)
		if item.parent_id.is_empty():
			if not state.inventories.has(item.inventory) or state.inventories[item.inventory].owner_id != item.custodian_id or not Rules.integer(item.x, 0, 9) or not Rules.integer(item.y, 0, 9):
				return "root_placement" + ':' + str(id)
		else:
			if not Rules.identifier(item.parent_id) or not state.items.has(item.parent_id) or item.inventory != "" or item.x != -1 or item.y != -1 or item.rotated:
				return "child_placement" + ':' + str(id)
		var def: Dictionary = defs[item.def_id]
		if not def.inside.is_empty():
			if not hosts.has(id):
				return "host_missing" + ':' + str(id)
			var grid: Dictionary = state.inventories[hosts[id]]
			if grid.width != def.inside.width or grid.height != def.inside.height or grid.owner_id != item.custodian_id:
				return "host_dimensions" + ':' + str(id)
		elif hosts.has(id):
			return "unexpected_host" + ':' + str(id)
	var projection: Dictionary = nodes(state, defs)
	if not Relations.validate(projection).ok:
		return "relations"
	for id: String in state.items:
		var item: Dictionary = state.items[id]
		if not item.parent_id.is_empty():
			var parent: Dictionary = state.items[item.parent_id]
			if item.status != parent.status:
				return "child_status" + ':' + str(id)
		var seen: Dictionary = {}
		for child: String in family(state, id):
			if child == id:
				continue
			var tag: String = defs[state.items[child].def_id].tag
			if tag not in defs[item.def_id].required_tags or seen.has(tag):
				return "child_tag" + ':' + str(id)
			seen[tag] = true
	if not grids_valid(state, defs):
		return "grid_placement"
	for id: Variant in state.tombstones:
		var tomb: Variant = state.tombstones[id]
		if not Rules.identifier(id) or state.items.has(id) or not Rules.keys(tomb, ["def_id", "owner_id", "custodian_id", "basis", "provenance_id", "event_id", "revision"]):
			return "tombstone_shape" + ':' + str(id)
		if not defs.has(tomb.def_id) or not state.wallets.has(tomb.owner_id) or not state.wallets.has(tomb.custodian_id) or not Rules.identifier(tomb.provenance_id) or not Rules.identifier(tomb.event_id) or not Rules.integer(tomb.revision, 1, int(state.revision)) or not money(tomb.basis):
			return "tombstone_fields" + ':' + str(id)
	return ""
