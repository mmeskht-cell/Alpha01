extends RefCounted
## Stateless first-day fixture rules. All mutable data lives in GameSession's candidate.
## First counter authority rules. Transfers are executed by GameSession.
const Rules = preload("res://src/domain/value_rules.gd")
const Appraisal = preload("res://src/domain/gate1_appraisal.gd")
const Receipt = preload("res://src/domain/receipt_primitives.gd")
const Negotiation = preload("res://src/domain/gate1_negotiation.gd")
const Deck = preload("res://src/domain/negotiation_deck.gd")
const ACTIONS: Array = ["accept_rad1_contract", "next_visit", "inspect_radio", "record_hypothesis", "deck_action", "make_offer", "confirm_purchase", "decline_visit"]
const QUEUE: Array = ["visit_g01", "visit_g02_buy", "visit_g02_service"]
const TERMS: Dictionary = {"id": "rad1_first", "supplier": "marcus", "currency": "VKC", "amount": 300, "quantity": 1, "due_minute": 4920, "delivery_minute": 6360, "external_supply": 1, "prepayment_on_acceptance": 0}

static func seed(scenario: Dictionary) -> Dictionary:
	var initial: Variant = scenario.get("initial_state")
	var start: Variant = scenario.get("campaign_initial")
	if not initial is Dictionary or not start is Dictionary or not start.get("contract") is Dictionary or not start.get("customer_queue") is Dictionary:
		return {}
	var terms: Dictionary = Rules.normalized(start.contract)
	if terms.get("initial_status") != "offered" or start.get("phase") != "business":
		return {}
	terms.erase("initial_status")
	var state: Dictionary = Rules.normalized(initial)
	state["campaign"] = {"id": "gate1_1", "day": start.get("day"), "personal_rad1_doses": start.get("personal_rad1_doses"), "rad1_effect_until_minute": start.get("rad1_effect_until_minute"), "contract": terms, "contract_status": "offered", "reserved_supply": 0, "queue": Rules.normalized(start.customer_queue)}
	if state.campaign.contract != TERMS or state.campaign.queue != {"ordered_visit_ids": QUEUE, "cursor": 0, "active_visit_id": null}:
		return {}
	return Rules.normalized(state)

static func first_visit() -> Dictionary:
	return {"scope": {"visit_id": "visit_g01", "kind": "ordinary", "purpose": "purchase", "completed": false, "required_ids": []}, "seller": "G01", "buyer": "player", "prices": {"R001": {"VKC": 125, "USD": 0}}, "opens": 0, "expires": 600, "allow_inspection": false}

static func apply(state: Dictionary, command_type: String, payload: Dictionary, action_id: String) -> String:
	if command_type in Appraisal.ACTIONS:
		return Appraisal.apply(state, command_type, payload, action_id)
	if command_type == "deck_action":
		return Deck.apply(state,payload,action_id)
	if command_type == "make_offer":
		return Negotiation.offer(state, payload, action_id)
	if command_type == "decline_visit":
		return Negotiation.decline(state, payload, action_id)
	if not payload.is_empty():
		return "opening_payload"
	var campaign: Dictionary = state.campaign
	match command_type:
		"accept_rad1_contract":
			if campaign.contract_status != "offered" or campaign.reserved_supply != 0:
				return "contract_already_reserved"
			campaign["contract_status"] = "reserved"
			campaign["reserved_supply"] = 1
		"next_visit":
			if campaign.queue.cursor != 0 or campaign.queue.active_visit_id != null:
				return "visit_unavailable"
			campaign.queue["cursor"] = 1
			campaign.queue["active_visit_id"] = "visit_g01"
			state.visits["visit_g01"] = first_visit()
		_:
			return "opening_command_unavailable"
	return ""

## Explicit narrow invariant until inspection/negotiation/purchase are integrated.
static func valid(state: Dictionary) -> bool:
	var c: Variant = state.get("campaign")
	var keys: Array = ["id", "day", "personal_rad1_doses", "rad1_effect_until_minute", "contract", "contract_status", "reserved_supply", "queue"]
	if c is Dictionary:
		for optional: String in ["appraisal", "negotiation", "deck_events"]:
			if c.has(optional):
				keys.append(optional)
	if not Rules.keys(c, keys):
		return false
	if c.id != "gate1_1" or not Rules.integer(c.day, 1, 1) or not Rules.integer(c.personal_rad1_doses, 1, 1) or not Rules.integer(c.rad1_effect_until_minute, 2880, 2880) or c.contract != TERMS:
		return false
	if c.contract_status not in ["offered", "reserved"] or not Rules.integer(c.reserved_supply, 0, 1) or c.reserved_supply != (1 if c.contract_status == "reserved" else 0):
		return false
	if not Rules.keys(c.queue, ["ordered_visit_ids", "cursor", "active_visit_id"]) or c.queue.ordered_visit_ids != QUEUE or not Rules.integer(c.queue.cursor, 0, 1):
		return false
	var admitted: bool = c.queue.cursor == 1
	var n: Variant = c.get("negotiation", Negotiation.empty())
	if not Rules.keys(n, ["offers", "terminal"]) or not n.offers is Array:
		return false
	var terminal: Variant = n.terminal
	if terminal != null and (not Rules.keys(terminal, ["kind", "action_id"]) or terminal.kind not in ["purchased", "declined"]):
		return false
	var bought: bool = terminal != null and terminal.kind == "purchased"
	if c.queue.active_visit_id != ("visit_g01" if admitted and terminal == null else null):
		return false
	var price: int = 0
	var expected_visit: Dictionary = first_visit()
	if bought:
		if not admitted or n.offers.is_empty() or not n.offers.back() is Dictionary or not Rules.integer(n.offers.back().get("amount"), 1, 180):
			return false
		price = int(n.offers.back().amount)
		expected_visit.prices.R001["VKC"] = price
		expected_visit.scope["completed"] = true
	if state.visits != ({"visit_g01": expected_visit} if admitted else {}):
		return false
	if state.phase != "shop" or state.ledger.size() != (1 if bought else 0) or not state.knowledge.is_empty() or not state.object_events.is_empty() or not state.tombstones.is_empty():
		return false
	if state.wallets != {"player": {"VKC": 180 - price, "USD": 0}, "G01": {"VKC": price, "USD": 0}, "G02": {"VKC": 200, "USD": 0}}:
		return false
	if state.items.size() != 1 or not state.items.has("R001"):
		return false
	var radio: Dictionary = state.items.R001
	var owner: String = "player" if bought else "G01"
	if radio.def_id != "portable_radio" or radio.owner_id != owner or radio.custodian_id != owner or radio.inventory != ("player_stock" if bought else "g01_grid") or radio.version != (1 if bought else 0):
		return false
	if not radio.functional or radio.restored or radio.field_versions.functional != 0 or radio.field_versions.restored != 0:
		return false
	if bought and radio.basis != {"VKC": price, "USD": 0}:
		return false
	var expected_grids: Dictionary = {
		"player_stock": {"owner_id": "player", "width": 10, "height": 6, "host_item": ""},
		"player_display": {"owner_id": "player", "width": 6, "height": 3, "host_item": ""},
		"g01_grid": {"owner_id": "G01", "width": 4, "height": 3, "host_item": ""},
		"g02_grid": {"owner_id": "G02", "width": 4, "height": 3, "host_item": ""}
	}
	if state.inventories != expected_grids or radio.status != "stock" or radio.protected or not radio.reservation_id.is_empty() or not radio.parent_id.is_empty() or radio.service_permission or radio.provenance_id != "bootstrap_R001" or radio.field_versions.composition != 0 or radio.hidden_economy != 0:
		return false
	if not bought and (radio.basis != {"VKC": null, "USD": null} or radio.x != 0 or radio.y != 0 or radio.rotated):
		return false
	var commands: Dictionary = {}
	for id: String in state.receipts:
		var command: Variant = JSON.parse_string(state.receipts[id].fingerprint)
		if not command is Dictionary or command.type not in ACTIONS:
			return false
		if not commands.has(command.type):
			commands[command.type] = []
		commands[command.type].append(id)
	for id: String in state.receipt_archive:
		var kind: String = state.receipt_archive[id][2]
		if kind not in ACTIONS:
			return false
		if not commands.has(kind):
			commands[kind] = []
		commands[kind].append(id)
	var reserve_ids: Array = commands.get("accept_rad1_contract", [])
	var admit_ids: Array = commands.get("next_visit", [])
	if reserve_ids.size() != int(c.reserved_supply) or admit_ids.size() != int(c.queue.cursor):
		return false
	for id: String in reserve_ids:
		if not Receipt.matches_receipt(state, id, "accept_rad1_contract", {}, Receipt.receipt_revision(state, id)):
			return false
	var admission_revision: int = 0
	if admitted:
		admission_revision = Receipt.receipt_revision(state, admit_ids[0])
		if not Receipt.matches_receipt(state, admit_ids[0], "next_visit", {}, admission_revision):
			return false
	return Appraisal.valid(state, admitted, admission_revision, commands) and Deck.valid(state, admitted, admission_revision, commands) and Negotiation.valid(state, admitted, admission_revision, commands)

## Only public player-facing values. No NPC wallet, hidden function, or full snapshot.
static func view(state: Dictionary) -> Dictionary:
	var c: Dictionary = state.campaign
	var contract: Dictionary = {"id": c.contract.id, "supplier": c.contract.supplier, "amount": c.contract.amount, "currency": c.contract.currency, "quantity": c.contract.quantity, "due_minute": c.contract.due_minute, "delivery_minute": c.contract.delivery_minute, "status": c.contract_status}
	var appraisal: Dictionary = Appraisal.view(state)
	var function_key: String = "day1.radio.unknown"
	if appraisal.get("function_status") == "serviceable":
		function_key = "day1.radio.function_serviceable"
	elif appraisal.get("function_status") == "inoperable":
		function_key = "day1.radio.function_inoperable"
	var customer: Variant = null
	if c.queue.active_visit_id == "visit_g01":
		customer = {"visit_id": "visit_g01", "actor_id": "G01", "item_id": "R001", "ask": state.visits.visit_g01.prices.R001.VKC, "currency": "VKC", "dialogue_key": "day1.g01.offer", "visible_key": "day1.radio.visible_shape", "function_key": function_key}
	return {"revision": state.revision, "minute": state.game_minutes, "day": c.day, "wallet": state.wallets.player.duplicate(true), "personal_rad1_doses": c.personal_rad1_doses, "rad1_effect_until_minute": c.rad1_effect_until_minute, "contract": contract, "customer": customer, "remaining_visits": c.queue.ordered_visit_ids.size() - int(c.queue.cursor), "can_call_next": c.queue.cursor == 0, "appraisal": appraisal, "acquired_appraisal": Appraisal.acquired_view(state), "negotiation": Negotiation.view(state), "negotiation_deck": Deck.view(state)}
