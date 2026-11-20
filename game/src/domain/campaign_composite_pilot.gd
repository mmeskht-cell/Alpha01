extends RefCounted
## Optional noncanonical electronic-device integration fixture in the real day-one session.
## State under day_one is checked by exact deterministic command replay.
const Rules = preload("res://src/domain/value_rules.gd")
const Customer = preload("res://src/domain/customer_inspection.gd")
const Access = preload("res://src/domain/inspection_access.gd")
const Visits = preload("res://src/domain/visit_primitives.gd")
const DayOne = preload("res://src/domain/day_one.gd")
const Clock = preload("res://src/domain/business_clock.gd")
const OFFER: String = "day_one_composite_offer"
const REQUEST: String = "day_one_composite_request"
const CLOSE: String = "day_one_composite_close"
const DECLINE: String = "day_one_composite_decline"
const ACTIONS: Array = [OFFER, REQUEST, CLOSE, DECLINE]

static func enabled(state: Dictionary) -> bool:
	return state.get("day_one", {}).has("composite_pilot")

static func can_offer(state: Dictionary) -> bool:
	return state.has("day_one") and state.day_one.base != null and not enabled(state) and DayOne.shop(state) and state.game_minutes < 600 and state.campaign.queue.cursor == 3 and state.campaign.queue.active_visit_id == null

static func offer(state: Dictionary, fixture: Dictionary) -> String:
	if not can_offer(state) or fixture.is_empty() or state.wallets.has(Customer.SELLER) or state.inventories.has("customer_grid"):
		return "composite_offer_unavailable"
	for id: String in Customer.IDS:
		if state.items.has(id) or state.tombstones.has(id) or not fixture.items.has(id):
			return "composite_identity"
	state.wallets[Customer.SELLER] = {"VKC": 0, "USD": 0}
	state.inventories["customer_grid"] = {"owner_id": Customer.SELLER, "width": 6, "height": 4, "host_item": ""}
	for id: String in Customer.IDS:
		var item: Dictionary = fixture.items[id].duplicate(true)
		item.owner_id = Customer.SELLER
		item.custodian_id = Customer.SELLER
		item.basis = {"VKC": null, "USD": null}
		if id == Customer.ROOT:
			item.inventory = "customer_grid"
		state.items[id] = item
	var visit: Dictionary = Customer.visit()
	visit.opens = state.game_minutes
	state.visits[Customer.VISIT] = visit
	state.day_one["composite_pilot"] = {"request": null, "close": null, "decline": null}
	return ""

static func live(state: Dictionary) -> bool:
	return enabled(state) and state.day_one.composite_pilot.decline == null and Visits.purchase_open(state, Customer.VISIT, Customer.ROOT, Customer.SELLER, true)

static func eligible(state: Dictionary, id: String) -> bool:
	return live(state) and state.game_minutes < 600 and id in Customer.IDS and Access.root_for(state, id) == Customer.ROOT and Access.stock_access(state, id, Customer.SELLER)

static func extra_access(state: Dictionary, id: String, key: String) -> bool:
	return eligible(state, id) and state.day_one.composite_pilot.request != null and state.day_one.composite_pilot.close == null and Customer.accepted("cooperative") and key in Customer.grant_for(state, id)

static func owned(state: Dictionary, id: String, detached: bool = false) -> bool:
	return enabled(state) and id in Customer.IDS and Access.stock_access(state, id, "player", detached)

static func apply(state: Dictionary, kind: String, p: Dictionary, action_id: String) -> String:
	if not p.is_empty() or not live(state):
		return "composite_visit_unavailable"
	var marker: Dictionary = state.day_one.composite_pilot
	match kind:
		REQUEST:
			if marker.request != null or not eligible(state, Customer.ROOT) or state.game_minutes + 2 * Customer.MINUTES > 600:
				return "composite_request_unavailable"
			state.game_minutes += Customer.MINUTES
			marker.request = action_id
		CLOSE:
			if marker.request == null or marker.close != null or state.game_minutes >= 600:
				return "composite_not_open"
			marker.close = action_id
		DECLINE:
			marker.decline = action_id
		_: return "composite_command"
	return ""

static func view(state: Dictionary) -> Dictionary:
	if not enabled(state):
		return {}
	var marker: Dictionary = state.day_one.composite_pilot
	var current: bool = live(state)
	var purchased: bool = state.visits[Customer.VISIT].scope.completed
	var status: String = "bought" if purchased else ("declined" if marker.decline != null else ("closing" if state.game_minutes >= 600 else ("closed" if marker.close != null else ("open" if marker.request != null else "waiting"))))
	return {"status": status, "ask": Customer.ASK, "visit_id": Customer.VISIT, "item_id": Customer.ROOT, "seller": Customer.SELLER, "buyer": "player", "currency": "VKC", "can_request": current and eligible(state, Customer.ROOT) and marker.request == null and state.game_minutes + 2 * Customer.MINUTES <= 600, "can_close": current and state.game_minutes < 600 and marker.request != null and marker.close == null, "can_buy": current and state.wallets.player.VKC >= Customer.ASK, "can_decline": current}
