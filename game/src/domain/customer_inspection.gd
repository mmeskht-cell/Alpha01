extends RefCounted
## Independent composite customer fixture. Permission is a view, never a physical mutation.
const Rules = preload("res://src/domain/value_rules.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const Visits = preload("res://src/domain/visit_primitives.gd")
const Access = preload("res://src/domain/inspection_access.gd")
const Items = preload("res://src/domain/item_primitives.gd")
const Receipts = preload("res://src/domain/receipt_primitives.gd")
const Documents = preload("res://src/content/packaged_documents.gd")

const VISIT: String = "fixture_customer_visit"
const ROOT: String = "D001"
const SELLER: String = "fixture_customer"
const IDS: Array = ["D001", "D001_A", "D001_B", "D001_C"]
const ASK: int = 80
const CLOSE: int = 600
const MINUTES: int = 5
const ACTIONS: Array = ["request_open_inspection", "close_inspection", "decline_component_visit", "finish_component_visit"]
const POLICY_PATH: String = "res://data/campaign/component_preview/customer_inspection_policy.json"
static var _policy_cache: Dictionary = {}

static func _policy_source() -> Dictionary:
	if not _policy_cache.is_empty():
		return _policy_cache
	var raw: Variant = Documents.read_object(POLICY_PATH)
	if not Rules.keys(raw, ["version", "policies", "grants_by_definition"]) or raw.version != 1 or not raw.policies is Dictionary or raw.policies.is_empty() or not raw.grants_by_definition is Dictionary:
		return {}
	for id: Variant in raw.policies:
		var row: Variant = raw.policies[id]
		if not Rules.identifier(id) or not Rules.keys(row, ["trust", "urgency", "allow_partial"]) or not Rules.integer(row.trust, 0, 100) or not Rules.integer(row.urgency, 0, 100) or not row.allow_partial is bool:
			return {}
	for def_id: Variant in raw.grants_by_definition:
		var keys: Variant = raw.grants_by_definition[def_id]
		if not Rules.identifier(def_id) or not keys is Array or keys.is_empty():
			return {}
		var seen: Dictionary = {}
		for key: Variant in keys:
			if not Rules.identifier(key) or not key.begins_with("component_") or key == "component_function" or seen.has(key):
				return {}
			seen[key] = true
	_policy_cache = Rules.normalized(raw)
	return _policy_cache

static func has_policy(id: String) -> bool:
	return _policy_source().get("policies", {}).has(id)

static func grant_for(state: Dictionary, id: String) -> Array:
	if id not in IDS or id == ROOT or not state.items.has(id):
		return []
	return _policy_source().get("grants_by_definition", {}).get(state.items[id].def_id, []).duplicate()

static func visit() -> Dictionary:
	return {"scope": {"visit_id": VISIT, "kind": "ordinary", "purpose": "purchase", "completed": false, "required_ids": []}, "seller": SELLER, "buyer": "player", "prices": {ROOT: {"VKC": ASK, "USD": 0}}, "opens": 0, "expires": CLOSE, "allow_inspection": true}

static func seed(state: Dictionary, policy: String) -> Dictionary:
	if state.is_empty() or not has_policy(policy):
		return {}
	state.phase = "shop"
	state.game_minutes = 0
	state.wallets[SELLER] = {"VKC": 0, "USD": 0}
	state.inventories["customer_grid"] = {"owner_id": SELLER, "width": 6, "height": 4, "host_item": ""}
	for id: String in IDS:
		var item: Dictionary = state.items[id]
		item.owner_id = SELLER
		item.custodian_id = SELLER
		item.basis = {"VKC": null, "USD": null}
	state.items[ROOT].inventory = "customer_grid"
	state.visits[VISIT] = visit()
	state["customer_inspection"] = {"policy": policy, "request": null, "close": null, "decline": null, "evening": null, "waits": {}}
	return state

static func enabled(state: Dictionary) -> bool:
	return state.has("customer_inspection")

static func accepted(policy: String) -> bool:
	var p: Dictionary = _policy_source().get("policies", {}).get(policy, {})
	return not p.is_empty() and p.allow_partial and int(p.trust) >= int(p.urgency)

static func bought(state: Dictionary) -> bool:
	return state.visits[VISIT].scope.completed

static func live_visit(state: Dictionary) -> bool:
	return enabled(state) and state.customer_inspection.decline == null and Visits.purchase_open(state, VISIT, ROOT, SELLER, true)

static func active(state: Dictionary) -> bool:
	return live_visit(state) and state.game_minutes < CLOSE

static func open_access(state: Dictionary) -> bool:
	return active(state) and state.customer_inspection.request != null and accepted(state.customer_inspection.policy) and state.customer_inspection.close == null

static func eligible(state: Dictionary, id: String) -> bool:
	if not active(state) or id not in IDS or not state.items.has(id) or not state.items.has(ROOT):
		return false
	return Access.root_for(state, id) == ROOT and Access.stock_access(state, id, SELLER)

static func extra_access(state: Dictionary, id: String, key: String) -> bool:
	return eligible(state, id) and open_access(state) and key in grant_for(state, id)

static func may_trade(state: Dictionary, p: Dictionary) -> bool:
	return live_visit(state) and p.get("visit_id") == VISIT and p.get("item_id") == ROOT

static func apply(state: Dictionary, kind: String, payload: Dictionary, id: String) -> String:
	if not enabled(state) or not payload.is_empty():
		return "inspection_visit_permission"
	var c: Dictionary = state.customer_inspection
	match kind:
		"request_open_inspection":
			if not active(state) or not eligible(state, ROOT) or c.request != null or state.game_minutes + 2 * MINUTES > CLOSE:
				return "inspection_request_unavailable"
			state.game_minutes += MINUTES
			c.request = id
		"close_inspection":
			if not open_access(state):
				return "inspection_not_open"
			c.close = id
		"decline_component_visit":
			if not live_visit(state):
				return "inspection_visit_closed"
			c.decline = id
		"finish_component_visit":
			if state.phase != "shop" or c.evening != null or (live_visit(state) and state.game_minutes < CLOSE):
				return "inspection_visit_still_active"
			c.evening = id
			state.game_minutes = CLOSE
			state.phase = "workshop"
		_:
			return "inspection_command"
	return ""

static func command_gate(state: Dictionary, kind: String, p: Dictionary) -> String:
	if not enabled(state):
		return "inspection_mode_required" if kind in ACTIONS else ""
	if kind in ACTIONS:
		return ""
	if state.phase == "shop":
		match kind:
			"trade": return "" if may_trade(state, p) else "inspection_visit_closed"
			"observe", "record_component_hypothesis": return ""
			"advance_time":
				if Rules.keys(p, ["minutes"]) and Rules.integer(p.minutes, 1, 240) and live_visit(state) and state.game_minutes + int(p.minutes) <= CLOSE:
					return ""
				return "inspection_time"
		return "inspection_physical_change_forbidden"
	if state.phase == "workshop" and kind in ["observe", "record_component_hypothesis", "detach", "attach", "restore_item", "move"]:
		return ""
	return "inspection_command_unavailable"

static func valid(state: Dictionary, policy: String) -> bool:
	var c: Variant = state.get("customer_inspection")
	if not c is Dictionary:
		return false
	var fields: Array = ["policy", "request", "close", "decline", "evening"]
	if c.has("waits"):
		fields.append("waits")
	if not Rules.keys(c, fields) or c.policy != policy or not has_policy(policy) or state.has("campaign") or not state.visits.has(VISIT) or state.visits.size() != 1:
		return false
	var expected: Dictionary = visit()
	expected.scope.completed = bought(state)
	if state.visits[VISIT] != expected or state.game_minutes > CLOSE:
		return false
	var links: Dictionary = {}
	for pair: Array in [["request", ACTIONS[0]], ["close", ACTIONS[1]], ["decline", ACTIONS[2]], ["evening", ACTIONS[3]]]:
		var action: Variant = c[pair[0]]
		if action == null:
			continue
		if not Rules.identifier(action) or links.has(action) or not Receipts.matches_receipt(state, action, pair[1], {}, Receipts.receipt_revision(state, action)):
			return false
		links[action] = true
	for index: int in range(2):
		var table: Dictionary = state.receipts if index == 0 else state.receipt_archive
		for action: String in table:
			var kind: String = str(JSON.parse_string(table[action].fingerprint).type) if index == 0 else str(table[action][2])
			if kind in ACTIONS and not links.has(action):
				return false
	var req: int = Receipts.receipt_revision(state, c.request)
	var closed: int = Receipts.receipt_revision(state, c.close)
	var declined: int = Receipts.receipt_revision(state, c.decline)
	var evening: int = Receipts.receipt_revision(state, c.evening)
	if (closed > 0 and (req < 1 or closed <= req or not accepted(policy))) or (state.phase == "workshop") != (evening > 0) or (evening > 0 and state.game_minutes != CLOSE):
		return false
	var purchase: int = -1
	if bought(state):
		if state.ledger.size() != 1 or state.ledger[0].visit_id != VISIT or state.ledger[0].root_ids != [ROOT] or state.ledger[0].item_ids.size() != IDS.size():
			return false
		for id: String in IDS:
			if id not in state.ledger[0].item_ids:
				return false
		purchase = int(state.ledger[0].revision)
		if declined > 0:
			return false
	elif not state.ledger.is_empty():
		return false
	var terminal: int = maxi(purchase, declined)
	if terminal > 0 and (req >= terminal or closed >= terminal):
		return false
	if evening > 0 and (terminal >= evening or req >= evening or closed >= evening):
		return false
	if state.phase == "shop" or not bought(state):
		for id: String in IDS:
			if not state.items.has(id):
				return false
			var part: Dictionary = state.items[id]
			var owner: String = "player" if bought(state) else SELLER
			if part.owner_id != owner or part.custodian_id != owner or part.parent_id != ("" if id == ROOT else ROOT) or part.field_versions.composition != 0 or part.field_versions.functional != 0 or part.field_versions.restored != 0:
				return false
	return timeline_valid(state)

## For retained observations/hypotheses: distinguish the shop window from owned evening.
static func historical_access(state: Dictionary, id: String, key: String, revision: int, exposed: bool, observed_at: int = -1) -> bool:
	if not enabled(state):
		return true
	var c: Dictionary = state.customer_inspection
	var evening: int = Receipts.receipt_revision(state, c.evening)
	if evening > 0 and revision > evening:
		return id not in IDS or bought(state)
	if id not in IDS or revision < 1:
		return false
	var terminal: int = Receipts.receipt_revision(state, c.decline)
	if bought(state):
		terminal = int(state.ledger[0].revision)
	if (terminal > 0 and revision >= terminal) or (observed_at >= 0 and (observed_at < MINUTES or observed_at > CLOSE)):
		return false
	if id == ROOT or exposed:
		return true
	var req: int = Receipts.receipt_revision(state, c.request)
	var closed: int = Receipts.receipt_revision(state, c.close)
	return accepted(c.policy) and req > 0 and revision > req and (closed < 1 or revision < closed) and (key in grant_for(state, id) or (key.is_empty() and not grant_for(state, id).is_empty()))

static func view(state: Dictionary) -> Dictionary:
	if not enabled(state):
		return {}
	var c: Dictionary = state.customer_inspection
	var status: String = "waiting"
	if bought(state): status = "bought"
	elif c.decline != null: status = "declined"
	elif state.phase == "workshop": status = "expired"
	elif state.game_minutes >= CLOSE: status = "closing"
	elif open_access(state): status = "open"
	elif c.close != null: status = "closed"
	elif c.request != null and not accepted(c.policy): status = "refused"
	return {"status": status, "policy": c.policy, "ask": ASK, "visit_id": VISIT, "item_id": ROOT, "seller": SELLER, "buyer": "player", "currency": "VKC", "close_minute": CLOSE, "can_request": active(state) and c.request == null and state.game_minutes + 2 * MINUTES <= CLOSE, "can_close": open_access(state), "can_buy": live_visit(state), "can_decline": live_visit(state), "can_finish": state.phase == "shop" and (not live_visit(state) or state.game_minutes >= CLOSE), "request_minutes": MINUTES, "inspection_minutes": MINUTES}

## The shop clock is reconstructed from the receipt order. New waits store the
## small payload; legacy preview archives recover only the finite 1..240 domain.
static func wait_minutes(state: Dictionary, id: String, revision: int) -> int:
	var c: Dictionary = state.customer_inspection
	if c.has("waits"):
		var waits: Variant = c.waits
		if not waits is Dictionary or not Rules.integer(waits.get(id), 1, 240):
			return -1
		var amount: int = int(waits[id])
		return amount if Receipts.matches_receipt(state, id, "advance_time", {"minutes": amount}, revision) else -1
	if state.receipts.has(id):
		var cmd: Dictionary = JSON.parse_string(state.receipts[id].fingerprint)
		var amount: Variant = cmd.payload.get("minutes")
		return int(amount) if Rules.keys(cmd.payload, ["minutes"]) and Rules.integer(amount, 1, 240) else -1
	for amount: int in range(1, 241):
		if Receipts.matches_receipt(state, id, "advance_time", {"minutes": amount}, revision):
			return amount
	return -1

static func timeline_valid(state: Dictionary) -> bool:
	var c: Dictionary = state.customer_inspection
	if c.has("waits") and not c.waits is Dictionary:
		return false
	var rows: Array = []
	for id: String in state.receipts:
		var command: Dictionary = JSON.parse_string(state.receipts[id].fingerprint)
		rows.append({"id": id, "rev": int(state.receipts[id].result.revision), "kind": command.type})
	for id: String in state.receipt_archive:
		var receipt: Array = state.receipt_archive[id]
		rows.append({"id": id, "rev": int(receipt[1]), "kind": receipt[2]})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.rev < b.rev)
	var minute: int = 0
	var ended: bool = false
	var evening: bool = false
	var waited: Dictionary = {}
	for row: Dictionary in rows:
		var id: String = row.id
		var kind: String = row.kind
		if evening:
			if kind not in ["observe", "record_component_hypothesis", "detach", "attach", "restore_item", "move"]:
				return false
			if kind == "observe" and state.knowledge.has(id):
				var fact: Variant = state.knowledge[id]
				if not fact is Dictionary or fact.get("observed_at") != CLOSE:
					return false
			continue
		match kind:
			"advance_time":
				var amount: int = wait_minutes(state, id, row.rev)
				if ended or minute >= CLOSE or amount < 1:
					return false
				minute += amount
				waited[id] = amount
			"request_open_inspection":
				if ended or minute + 2 * MINUTES > CLOSE:
					return false
				minute += MINUTES
			"observe":
				if ended or minute + MINUTES > CLOSE:
					return false
				minute += MINUTES
				if state.knowledge.has(id):
					var fact: Variant = state.knowledge[id]
					if not fact is Dictionary or fact.get("observed_at") != minute:
						return false
				elif not state.receipt_archive.has(id) or state.receipt_archive[id].size() != 4:
					return false
			"record_component_hypothesis", "close_inspection":
				if ended or minute >= CLOSE:
					return false
			"trade":
				if ended or state.ledger.size() != 1 or state.ledger[0].event_id != id or state.ledger[0].game_minutes != minute:
					return false
				ended = true
			"decline_component_visit":
				if ended:
					return false
				ended = true
			"finish_component_visit":
				if not ended and minute != CLOSE:
					return false
				minute = CLOSE
				evening = true
			_:
				return false
		if minute > CLOSE:
			return false
	return minute == state.game_minutes and (not c.has("waits") or c.waits == waited)

## Post-history validation: this fixed preview allows only one purchase and
## abstract repairs, so its cash, cost basis and repair flags can be reconciled.
static func economy_valid(state: Dictionary, defs: Dictionary) -> bool:
	if not enabled(state):
		return true
	if state.items.size() != 5 or not state.items.has("D002") or not state.tombstones.is_empty() or state.wallets.size() != 2 or not state.wallets.has("player") or not state.wallets.has(SELLER):
		return false
	var weights: Dictionary = {}
	for id: String in IDS:
		if not state.items.has(id):
			return false
		weights[id] = defs[state.items[id].def_id].weight
	var allocated: Dictionary = Items.allocate_cost(ASK, weights) if bought(state) else {}
	var expenses: Dictionary = {}
	var repair_revision: Dictionary = {}
	var cash: int = 100 - (ASK if bought(state) else 0)
	var evening: int = Receipts.receipt_revision(state, state.customer_inspection.evening)
	for event: Dictionary in state.object_events:
		if evening < 1 or event.revision <= evening:
			return false
		if event.type != "restore_item":
			if event.type not in ["detach", "attach"] or event.expenses != {"VKC": 0, "USD": 0}:
				return false
			continue
		if event.item_ids.size() != 1:
			return false
		var id: String = event.item_ids[0]
		if repair_revision.has(id) or id not in ["D001_B", "D001_C"] or not bought(state) or event.expenses != defs[state.items[id].def_id].restore_cost or event.expenses.USD != 0:
			return false
		repair_revision[id] = event.revision
		expenses[id] = int(event.expenses.VKC)
		cash -= int(event.expenses.VKC)
	for id: String in IDS + ["D002"]:
		var item: Dictionary = state.items[id]
		var player_owned: bool = id == "D002" or bought(state)
		var owner: String = "player" if player_owned else SELLER
		if item.owner_id != owner or item.custodian_id != owner:
			return false
		var repaired: bool = repair_revision.has(id)
		if item.restored != repaired or item.field_versions.functional != int(repaired) or item.field_versions.restored != int(repaired):
			return false
		if id in ["D001_B", "D001_C"] and item.functional != repaired:
			return false
		if id == "D001_A" and not item.functional:
			return false
		# Legacy shells had a false functional flag; both values denote passive
		# structures with no independently tested function.
		var cost: Variant = (20 if id == "D002" else int(allocated.get(id, 0))) + int(expenses.get(id, 0)) if player_owned else null
		if item.basis != {"VKC": cost, "USD": 0 if player_owned else null}:
			return false
	return cash >= 0 and state.wallets.player == {"VKC": cash, "USD": 0} and state.wallets[SELLER] == {"VKC": ASK if bought(state) else 0, "USD": 0}
