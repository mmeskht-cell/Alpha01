extends RefCounted
## Opt-in generic campaign state boundary. Lifecycle commands are world-only.
## Fixed initial actor/catalog set; bounded explicit world creation. No scheduler.
const Rules = preload("res://src/domain/value_rules.gd")
const Directory = preload("res://src/domain/campaign_identity_directory.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const Receipt = preload("res://src/domain/receipt_primitives.gd")
const Items = preload("res://src/domain/item_primitives.gd")
const ACTIONS: Array = ["world_sleep_family", "world_wake_family", "world_spawn_stock", "world_open_visit"]
const BIRTH: String = "world_spawn_stock"
const VISIT: String = "world_open_visit"
const MAX_DYNAMIC: int = 128

static func partition(state: Dictionary) -> Dictionary:
	return {"state": state, "dormant": state.lifecycle.dormant, "tracking": {}}

static func read_history(state: Dictionary) -> Dictionary:
	# History-only lookup; never passed to geometry/command permission.
	var view: Dictionary = state.duplicate()
	view.items = state.items.duplicate()
	for family: Dictionary in state.lifecycle.dormant.values():
		view.items.merge(family)
	return view

static func apply(state: Dictionary, defs: Dictionary, command: Dictionary) -> Dictionary:
	var p: Dictionary = command.payload
	if command.type in [BIRTH, VISIT]:
		return _create(state, defs, command)
	var moving: Dictionary = {}
	var next: Dictionary = {}
	if command.type == ACTIONS[0]:
		if not Rules.keys(p, ["root_id"]) or not Rules.identifier(p.root_id):
			return {}
		next = Directory.sleep_candidate(partition(state), defs, p.root_id)
		if not next.is_empty():
			moving = next.dormant[p.root_id]
	elif command.type == ACTIONS[1]:
		if not Rules.keys(p, ["root_id", "inventory", "x", "y", "rotated"]) or not Rules.identifier(p.root_id) or not Rules.identifier(p.inventory) or not Rules.integer(p.x, 0, 9) or not Rules.integer(p.y, 0, 9) or not p.rotated is bool:
			return {}
		moving = state.lifecycle.dormant.get(p.root_id, {})
		next = Directory.wake_candidate(partition(state), defs, p.root_id, p.inventory, int(p.x), int(p.y), p.rotated)
	if next.is_empty():
		return {}
	var ids: Array = moving.keys()
	ids.sort()
	var result: Dictionary = next.state
	result.lifecycle.dormant = next.dormant
	result.lifecycle.events.append({"command": Rules.normalized(command), "revision": state.revision + 1, "item_ids": ids})
	return result


## Technical creation boundary. Explicit internal proposals only, no content
## scheduler, price generation, player access, new actors or story activation.
static func _birth_row(state: Dictionary, defs: Dictionary, command: Dictionary) -> Dictionary:
	var p: Dictionary = command.payload
	if not Rules.keys(p, ["item_id", "def_id", "owner", "inventory", "x", "y", "rotated", "functional"]) or not Rules.identifier(p.item_id) or not Rules.identifier(p.def_id) or not Rules.identifier(p.owner) or p.owner == "player" or not Rules.identifier(p.inventory) or not Rules.integer(p.x, 0, 9) or not Rules.integer(p.y, 0, 9) or not p.rotated is bool or not p.functional is bool:
		return {}
	if not defs.has(p.def_id) or defs[p.def_id].kind != "atomic" or not defs[p.def_id].inside.is_empty() or not state.wallets.has(p.owner):
		return {}
	var grid: Dictionary = state.inventories.get(p.inventory, {})
	if grid.is_empty() or grid.owner_id != p.owner or not grid.host_item.is_empty():
		return {}
	var row: Dictionary = Objects.fresh_item(p.def_id, p.owner, p.inventory, int(p.x), int(p.y), command.action_id.sha256_text())
	row.rotated = p.rotated
	row.functional = p.functional
	return row

static func _visit_row(state: Dictionary, command: Dictionary) -> Dictionary:
	var p: Dictionary = command.payload
	if not Rules.keys(p, ["visit_id", "item_id", "seller", "buyer", "price", "opens", "expires", "allow_inspection"]) or not Rules.identifier(p.visit_id) or not Rules.identifier(p.item_id) or not Rules.identifier(p.seller) or not Rules.identifier(p.buyer) or p.seller == p.buyer or "player" not in [p.seller, p.buyer] or not state.wallets.has(p.seller) or not state.wallets.has(p.buyer) or not Objects.money(p.price, false) or not Rules.integer(p.opens, 0, 60480) or not Rules.integer(p.expires, int(p.opens), 60480) or not p.allow_inspection is bool:
		return {}
	if p.price.VKC + p.price.USD <= 0 or (p.price.VKC > 0 and p.price.USD > 0):
		return {}
	return {"scope": {"visit_id": p.visit_id, "kind": "ordinary", "purpose": "purchase" if p.buyer == "player" else "sale", "completed": false, "required_ids": []}, "seller": p.seller, "buyer": p.buyer, "prices": {p.item_id: p.price.duplicate(true)}, "opens": p.opens, "expires": p.expires, "allow_inspection": p.allow_inspection}

static func _create(state: Dictionary, defs: Dictionary, command: Dictionary) -> Dictionary:
	var p: Dictionary = command.payload
	var count: int = 0
	for event: Dictionary in state.lifecycle.events:
		if event.command.type in [BIRTH, VISIT]:
			count += 1
	if count >= MAX_DYNAMIC:
		return {}
	var next: Dictionary = state.duplicate(true)
	if command.type == BIRTH:
		var row: Dictionary = _birth_row(state, defs, command)
		if row.is_empty() or read_history(state).items.has(p.item_id) or state.tombstones.has(p.item_id):
			return {}
		next.items[p.item_id] = row
	else:
		var visit: Dictionary = _visit_row(state, command)
		if visit.is_empty() or state.visits.has(p.visit_id) or not state.items.has(p.item_id) or int(p.opens) < int(state.game_minutes):
			return {}
		var item: Dictionary = state.items[p.item_id]
		if item.owner_id != p.seller or item.custodian_id != p.seller or not item.parent_id.is_empty() or item.status != "stock" or item.protected or not item.reservation_id.is_empty():
			return {}
		next.visits[p.visit_id] = visit
	next.lifecycle.events.append({"command": Rules.normalized(command), "revision": state.revision + 1, "item_ids": [p.item_id]})
	return next if Directory.audit(partition(next), defs).ok else {}

## Derive trusted creation rows from exact immutable command receipts. Those
## rows are introduced at their own revisions by the chronological audit.
static func _expanded_seed(state: Dictionary, defs: Dictionary, seed: Dictionary) -> Dictionary:
	var expanded: Dictionary = read_history(seed).duplicate(true)
	var count: int = 0
	var prior: int = 0
	for event: Variant in state.lifecycle.events:
		if not Rules.keys(event, ["command", "revision", "item_ids"]) or not Rules.keys(event.command, ["type", "action_id", "expected_revision", "payload"]) or not Rules.integer(event.revision, prior + 1, int(state.revision)) or not Rules.identifier(event.command.action_id) or not event.command.payload is Dictionary or event.command.expected_revision != event.revision - 1:
			return {}
		prior = int(event.revision)
		if event.command.type not in [BIRTH, VISIT]:
			continue
		count += 1
		if count > MAX_DYNAMIC or not Receipt.matches_receipt(state, event.command.action_id, event.command.type, event.command.payload, prior):
			return {}
		var p: Dictionary = event.command.payload
		if event.command.type == BIRTH:
			var row: Dictionary = _birth_row(seed, defs, event.command)
			if row.is_empty() or expanded.items.has(p.item_id):
				return {}
			expanded.items[p.item_id] = row
		else:
			var visit: Dictionary = _visit_row(seed, event.command)
			if visit.is_empty() or expanded.visits.has(p.visit_id) or not expanded.items.has(p.item_id):
				return {}
			expanded.visits[p.visit_id] = visit
		if event.item_ids != [p.item_id]:
			return {}
	return expanded

static func audit(state: Dictionary, defs: Dictionary, seed: Dictionary) -> bool:
	if not Rules.keys(state.get("lifecycle"), ["version", "seed_hash", "dormant", "events", "waits"]) or state.lifecycle.version != 2 or not state.lifecycle.waits is Dictionary or state.lifecycle.seed_hash != seed.lifecycle.seed_hash or not state.lifecycle.events is Array or not state.lifecycle.dormant is Dictionary:
		return false
	var report: Dictionary = Directory.audit(partition(state), defs)
	if state.phase != seed.phase or int(state.game_minutes) < int(seed.game_minutes) or not report.ok:
		return false
	var history: Dictionary = read_history(state)
	var seed_history: Dictionary = _expanded_seed(state, defs, seed)
	if seed_history.is_empty():
		return false
	if report.index.size() != seed_history.items.size() or state.wallets.keys().size() != seed.wallets.keys().size() or state.visits.size() != seed_history.visits.size() or state.inventories.size() > seed.inventories.size():
		return false
	var states: Dictionary = {}
	var ownership: Dictionary = {}
	for id: String in seed_history.items:
		if not report.index.has(id):
			return false
		var old: Dictionary = seed_history.items[id]
		var row: Dictionary = history.items.get(id, state.tombstones.get(id, {}))
		if row.get("def_id") != old.def_id or row.get("provenance_id") != old.provenance_id:
			return false
		if history.items.has(id) and row.hidden_economy != old.hidden_economy:
			return false
		states[id] = "active" if seed.items.has(id) else ("dormant" if _seed_dormant(seed, id) else "unborn")
		ownership[id] = old.owner_id
	for id: String in seed_history.visits:
		if not state.visits.has(id):
			return false
		var actual: Dictionary = state.visits[id].duplicate(true)
		actual.scope.completed = false
		if Rules.canonical(actual) != Rules.canonical(seed_history.visits[id]):
			return false
	var seen: Dictionary = {}
	var previous: int = 0
	for event: Variant in state.lifecycle.events:
		if not Rules.keys(event, ["command", "revision", "item_ids"]) or not Rules.keys(event.command, ["action_id", "expected_revision", "type", "payload"]) or not Rules.integer(event.revision, previous + 1, int(state.revision)) or event.command.type not in ACTIONS or not event.command.payload is Dictionary or event.command.expected_revision != event.revision - 1:
			return false
		var p: Dictionary = event.command.payload
		if event.command.type in [BIRTH, VISIT]:
			if seen.has(event.command.action_id) or (event.command.type == BIRTH and states.get(p.item_id) != "unborn"):
				return false
			if event.command.type == BIRTH:
				states[p.item_id] = "active"
			seen[event.command.action_id] = true
			previous = event.revision
			continue
		var fields: Array = ["root_id"] if event.command.type == ACTIONS[0] else ["root_id", "inventory", "x", "y", "rotated"]
		if not Rules.keys(p, fields) or not Rules.identifier(p.root_id) or not event.item_ids is Array or event.item_ids.is_empty() or event.item_ids.size() > 9 or p.root_id not in event.item_ids or seen.has(event.command.action_id) or not Receipt.matches_receipt(state, event.command.action_id, event.command.type, p, int(event.revision)):
			return false
		if event.command.type == ACTIONS[1] and (not Rules.identifier(p.inventory) or not Rules.integer(p.x, 0, 9) or not Rules.integer(p.y, 0, 9) or not p.rotated is bool):
			return false
		var members: Dictionary = {}
		var sleeping: bool = event.command.type == ACTIONS[0]
		for id: Variant in event.item_ids:
			if not Rules.identifier(id) or members.has(id) or states.get(id) != ("active" if sleeping else "dormant"):
				return false
			members[id] = true
			states[id] = "dormant" if sleeping else "active"
		seen[event.command.action_id] = true
		previous = event.revision
	for table: Dictionary in [state.receipts, state.receipt_archive]:
		for id: String in table:
			if (Receipt.receipt_type(state, id) in ACTIONS) != seen.has(id):
				return false
	for id: String in report.index:
		if states[id] != ("active" if report.index[id] == "terminal" else report.index[id]):
			return false
	# Independently reconcile all known transfers and restoration expenses in
	# revision order, including nonnegative running balances and owner chain.
	var book: Dictionary = seed.wallets.duplicate(true)
	var posts: Array = []
	for row: Dictionary in state.ledger:
		posts.append({"revision": row.revision, "kind": "trade", "row": row})
	for row: Dictionary in state.object_events:
		if row.type == "restore_item":
			posts.append({"revision": row.revision, "kind": "expense", "row": row})
	posts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.revision < b.revision)
	var last: int = 0
	for posting: Dictionary in posts:
		if posting.revision <= last:
			return false
		last = posting.revision
		var row: Dictionary = posting.row
		var payer: String = row.from if posting.kind == "trade" else "player"
		var values: Dictionary = row.amounts if posting.kind == "trade" else row.expenses
		if not book.has(payer) or not Objects.money(values, false):
			return false
		if posting.kind == "trade":
			if not book.has(row.to):
				return false
			for id: String in row.item_ids:
				if ownership.get(id) != row.to:
					return false
				ownership[id] = row.from
		else:
			if row.item_ids.size() != 1 or not history.items.has(row.item_ids[0]) and not state.tombstones.has(row.item_ids[0]):
				return false
			var item: Dictionary = history.items.get(row.item_ids[0], state.tombstones.get(row.item_ids[0], {}))
			if values != defs[item.def_id].restore_cost:
				return false
		for currency: String in ["VKC", "USD"]:
			book[payer][currency] -= values[currency]
			if book[payer][currency] < 0:
				return false
			if posting.kind == "trade":
				book[row.to][currency] += values[currency]
	for id: String in ownership:
		if history.items.get(id, state.tombstones.get(id, {})).owner_id != ownership[id]:
			return false
	return Rules.canonical(book) == Rules.canonical(state.wallets) and _audit_history(state, defs, seed, seed_history, history)

## Chronological reconstruction of the fields that have explicit domain events.
## Not a replacement for full command replay: movement, clock, custody policy and
## archived composition placement payloads are not independently reconstructed.
static func _family(rows: Dictionary, root: String) -> Array:
	if not rows.has(root) or not rows[root].parent_id.is_empty():
		return []
	var ids: Array = [root]
	for id: String in rows:
		if rows[id].parent_id == root:
			ids.append(id)
	ids.sort()
	return ids

static func _audit_history(state: Dictionary, defs: Dictionary, original: Dictionary, seed: Dictionary, final: Dictionary) -> bool:
	var rows: Dictionary = read_history(original).items.duplicate(true)
	var visits: Dictionary = original.visits.duplicate(true)
	var locations: Dictionary = {}
	var births: Dictionary = {}
	for id: String in rows:
		locations[id] = "active" if not _seed_dormant(seed, id) else "dormant"
	# read_history includes the original lifecycle partition unchanged.
	var transitions: Array = []
	var minute: int = int(original.game_minutes)
	for table: Dictionary in [state.receipts, state.receipt_archive]:
		for id: String in table:
			var kind: String = Receipt.receipt_type(state, id)
			if kind == "advance_time":
				var duration: Variant = state.lifecycle.waits.get(id)
				var revision: int = Receipt.receipt_revision(state, id)
				if not Rules.integer(duration, 1, 240) or not Receipt.matches_receipt(state, id, kind, {"minutes": duration}, revision):
					return false
				transitions.append({"revision": revision, "kind": "wait", "row": {"minutes": duration}})
			elif state.lifecycle.waits.has(id):
				return false
	for id: String in state.lifecycle.waits:
		if Receipt.receipt_type(state, id) != "advance_time":
			return false
	for id: String in state.knowledge:
		transitions.append({"revision": Receipt.receipt_revision(state, id), "kind": "observe", "row": state.knowledge[id]})
	for event: Dictionary in state.lifecycle.events:
		transitions.append({"revision": event.revision, "kind": "life", "row": event})
	for event: Dictionary in state.object_events:
		transitions.append({"revision": event.revision, "kind": "object", "row": event})
	for entry: Dictionary in state.ledger:
		transitions.append({"revision": entry.revision, "kind": "ledger", "row": entry})
	transitions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.revision < b.revision)
	var last: int = 0
	for transition: Dictionary in transitions:
		if transition.revision <= last:
			return false
		last = transition.revision
		var e: Dictionary = transition.row
		if transition.kind == "wait":
			minute += int(e.minutes)
			continue
		if transition.kind == "observe":
			var id: String = e.item_id
			if locations.get(id) != "active" or not rows.has(id):
				return false
			var row: Dictionary = rows[id]
			var root: String = id if row.parent_id.is_empty() else row.parent_id
			var observed_field: String = "composition" if e.observation_key == "complete" else e.observation_key
			var value: bool = _family(rows, id).size() - 1 == defs[row.def_id].required_tags.size() if observed_field == "composition" and row.parent_id.is_empty() else (defs[row.def_id].required_tags.is_empty() if observed_field == "composition" else row[observed_field])
			var end: int = minute + int(defs[row.def_id].observation_minutes)
			if e.observed_at != end or e.observed_value != value or Rules.canonical(e.dependent_field_versions) != Rules.canonical({observed_field: row.field_versions[observed_field]}):
				return false
			if row.custodian_id != "player":
				var permitted: bool = false
				for v: Dictionary in visits.values():
					if not v.scope.completed and v.buyer == "player" and v.seller == row.owner_id and v.allow_inspection and v.prices.has(root) and int(v.opens) <= minute and int(v.expires) >= end:
						permitted = true
				if not permitted:
					return false
			minute = end
			continue
		if transition.kind == "life":
			if e.command.type == BIRTH:
				var id: String = e.command.payload.item_id
				if locations.has(id):
					return false
				rows[id] = seed.items[id].duplicate(true)
				births[id] = int(e.revision)
				locations[id] = "active"
				continue
			if e.command.type == VISIT:
				var p: Dictionary = e.command.payload
				if locations.get(p.item_id) != "active" or not rows[p.item_id].parent_id.is_empty() or rows[p.item_id].owner_id != p.seller or visits.has(p.visit_id) or int(p.opens) < minute:
					return false
				visits[p.visit_id] = seed.visits[p.visit_id].duplicate(true)
				continue
			var expected: Array = _family(rows, e.command.payload.root_id)
			if expected.is_empty() or expected != e.item_ids:
				return false
			var sleeping: bool = e.command.type == ACTIONS[0]
			for id: String in expected:
				if locations.get(id) != ("active" if sleeping else "dormant"):
					return false
				locations[id] = "dormant" if sleeping else "active"
			continue
		if transition.kind == "ledger":
			if not visits.has(e.visit_id) or visits[e.visit_id].scope.completed or e.game_minutes != minute or int(visits[e.visit_id].opens) > minute or int(visits[e.visit_id].expires) < minute:
				return false
			visits[e.visit_id].scope.completed = true
			var all_ids: Array = []
			var old_basis: Dictionary = {"VKC": 0, "USD": 0}
			for root: String in e.root_ids:
				var ids: Array = _family(rows, root)
				if ids.is_empty():
					return false
				var bases: Dictionary = {}
				var weights: Dictionary = {}
				for id: String in ids:
					if locations.get(id) != "active" or id in all_ids or rows[id].owner_id != e.to:
						return false
					all_ids.append(id)
					bases[id] = rows[id].basis
					weights[id] = defs[rows[id].def_id].weight
				var subtotal: Dictionary = Items.sum_basis(bases, ids)
				if not subtotal.ok:
					return false
				for currency: String in old_basis:
					old_basis[currency] = null if old_basis[currency] == null or subtotal.basis[currency] == null else old_basis[currency] + subtotal.basis[currency]
					if e.from == "player":
						var allocated: Dictionary = Items.allocate_cost(state.visits[e.visit_id].prices[root][currency], weights)
						if allocated.is_empty():
							return false
						for id: String in ids:
							rows[id].basis[currency] = allocated[id]
				for id: String in ids:
					rows[id].owner_id = e.from
					rows[id].custodian_id = e.from
			all_ids.sort()
			if all_ids != e.item_ids or Rules.canonical(old_basis) != Rules.canonical(e.basis):
				return false
			continue
		for id: String in e.item_ids:
			if not rows.has(id) or locations.get(id) != "active":
				return false
		match e.type:
			"attach", "detach":
				if e.item_ids.size() != 2 or e.basis != {"VKC": 0, "USD": 0} or e.expenses != {"VKC": 0, "USD": 0}:
					return false
				var root: String = e.item_ids[0]
				var child: String = e.item_ids[1]
				var d: Dictionary = defs[rows[root].def_id]
				var cd: Dictionary = defs[rows[child].def_id]
				if root == child or not rows[root].parent_id.is_empty() or d.kind != "composite" or not d.recombine or cd.kind != "atomic" or cd.tag not in d.required_tags or rows[root].owner_id != "player" or rows[child].owner_id != "player":
					return false
				if state.receipts.has(e.event_id):
					var payload: Dictionary = JSON.parse_string(state.receipts[e.event_id].fingerprint).payload
					if payload.get("root_id") != root or payload.get("child_id") != child or payload.get("actor") != "player":
						return false
				if e.type == "attach" and not Receipt.matches_receipt(state, e.event_id, e.type, {"actor": "player", "root_id": root, "child_id": child}, int(e.revision)):
					return false
				if e.type == "detach":
					if rows[child].parent_id != root:
						return false
					rows[child].parent_id = ""
				else:
					if not rows[child].parent_id.is_empty() or not cd.inside.is_empty():
						return false
					for id: String in _family(rows, root):
						if id != root and defs[rows[id].def_id].tag == cd.tag:
							return false
					rows[child].parent_id = root
				rows[root].field_versions.composition += 1
			"restore_item":
				if e.item_ids.size() != 1 or e.basis != {"VKC": 0, "USD": 0}:
					return false
				var id: String = e.item_ids[0]
				var row: Dictionary = rows[id]
				var d: Dictionary = defs[row.def_id]
				var service: bool = row.status == "custody_service" and row.custodian_id == "player" and row.service_permission
				if not row.parent_id.is_empty() or row.functional or not d.restorable or _family(rows, id).size() - 1 != d.required_tags.size() or (row.owner_id != "player" and not service) or not Receipt.matches_receipt(state, e.event_id, e.type, {"actor": "player", "item_id": id}, int(e.revision)):
					return false
				for currency: String in row.basis:
					if not service and row.basis[currency] != null:
						row.basis[currency] += d.restore_cost[currency]
				row.functional = true
				row.restored = true
				row.field_versions.functional += 1
				row.field_versions.restored += 1
			"discard":
				var roots: Array = []
				var bases: Dictionary = {}
				for id: String in e.item_ids:
					if rows[id].owner_id != "player":
						return false
					if rows[id].parent_id.is_empty():
						roots.append(id)
					bases[id] = rows[id].basis
				if roots.size() != 1 or _family(rows, roots[0]) != e.item_ids or not Receipt.matches_receipt(state, e.event_id, e.type, {"actor": "player", "item_id": roots[0], "confirmed_ids": e.item_ids}, int(e.revision)):
					return false
				var total: Dictionary = Items.sum_basis(bases, e.item_ids)
				if not total.ok or Rules.canonical(total.basis) != Rules.canonical(e.basis):
					return false
				for id: String in e.item_ids:
					var tomb: Dictionary = state.tombstones.get(id, {})
					if Rules.canonical(tomb.get("basis")) != Rules.canonical(rows[id].basis) or tomb.get("custodian_id") != rows[id].custodian_id:
						return false
					locations[id] = "terminal"
					rows.erase(id)
			_: return false
	if minute != int(state.game_minutes):
		return false
	for id: String in seed.items:
		if locations[id] == "terminal":
			if not state.tombstones.has(id):
				return false
			continue
		if not final.items.has(id):
			return false
		for field: String in ["parent_id", "basis", "functional", "restored", "field_versions", "owner_id", "custodian_id", "protected", "reservation_id", "status", "service_permission"]:
			if Rules.canonical(rows[id][field]) != Rules.canonical(final.items[id][field]):
				return false
	for id: String in state.knowledge:
		if Receipt.receipt_revision(state, id) <= int(births.get(state.knowledge[id].item_id, 0)):
			return false
	return true

static func _seed_dormant(seed: Dictionary, id: String) -> bool:
	for family: Dictionary in seed.lifecycle.dormant.values():
		if family.has(id):
			return true
	return false
