extends RefCounted
## Opt-in B1 date/phase authority. Does not mint funds, items, time or contracts.
const Rules = preload("res://src/domain/value_rules.gd")
const Contract = preload("res://src/domain/alpha_dated_contract.gd")
const Cards = preload("res://src/domain/alpha_card_trade.gd")
const Commission = preload("res://src/domain/alpha_commission.gd")
const ServiceCustody = preload("res://src/domain/alpha_service_custody.gd")
const ACTIONS: Array = ["alpha_open", "alpha_next_customer", "alpha_ack_entry", "alpha_finish_customer", "alpha_ack_exit", "alpha_close", "alpha_settle", "alpha_next_day", "alpha_prepare_day", "alpha_exchange_contact", "alpha_display", "alpha_withdraw_display", "alpha_trade", "alpha_contract_accept", "alpha_contract_decline", "alpha_contract_pay", "alpha_contract_extend", "alpha_inspect", "alpha_card_toggle", "alpha_price_offer", "alpha_commission_accept", "alpha_commission_decline", "alpha_commission_reserve", "alpha_commission_cancel", "alpha_commission_deliver", "alpha_service_accept", "alpha_service_decline", "alpha_service_repair", "alpha_service_deliver", "alpha_service_return_unpaid"]
const PHASES: Array = ["DAY_PREP", "OPEN_IDLE", "CUSTOMER_ENTER", "CUSTOMER_ACTIVE", "CUSTOMER_EXIT", "CLOSE_SETTLE", "EVENING_WORK", "NEXT_DAY", "COMPLETE"]

static func profile_valid(profile: Variant, state: Dictionary) -> bool:
	var keys: Array = ["id", "content_version", "days", "unavailable_actors"]
	if profile is Dictionary and profile.has("contracts"):
		keys.append_array(["contracts", "story_rules"])
	if profile is Dictionary and profile.has("appraisal_id"):
		keys.append("appraisal_id")
	if profile is Dictionary and profile.has("commission_profile_id"):
		keys.append("commission_profile_id")
	if profile is Dictionary and profile.has("service_profile_id"):
		keys.append("service_profile_id")
	if not Rules.keys(profile, keys) or profile.id != "alpha_b1_v1" or not Rules.identifier(profile.content_version):
		return false
	if not profile.days is Array or profile.days.is_empty() or profile.days.size() > 42 or not profile.unavailable_actors is Array:
		return false
	var visits: Dictionary = {}
	for actor: Variant in profile.unavailable_actors:
		if not Rules.identifier(actor) or not state.wallets.has(actor):
			return false
	for day_index: int in range(profile.days.size()):
		var day: Variant = profile.days[day_index]
		if not day is Array or day.size() > 10:
			return false
		var today: Dictionary = {}
		for row: Variant in day:
			if not Rules.keys(row, ["id", "actor_id", "kind", "purpose_key", "contact_offer"]):
				return false
			if not Rules.identifier(row.id) or not Rules.identifier(row.actor_id) or not state.wallets.has(row.actor_id) or row.actor_id == "player":
				return false
			if row.kind not in ["regular", "named"] or not Rules.identifier(row.purpose_key) or not row.contact_offer is bool:
				return false
			if visits.has(row.id) or today.has(row.actor_id) or row.actor_id in profile.unavailable_actors:
				return false
			# An authored counter identity may not impersonate a different
			# transaction actor or smuggle a visit into another date.
			if state.visits.has(row.id):
				var transaction: Dictionary = state.visits[row.id]
				var real_actor: String = str(transaction.seller if transaction.buyer == "player" else transaction.buyer)
				if real_actor != row.actor_id or int(transaction.opens) != day_index * 1440:
					return false
			elif not ((row.kind == "named" and row.id.begins_with("alpha_")) or (profile.has("service_profile_id") and ServiceCustody.is_return_visit(str(row.id), str(profile.service_profile_id)))):
				return false
			visits[row.id] = true
			today[row.actor_id] = true
	if profile.has("contracts") and not Contract.profile_valid(profile, state):
		return false
	if profile.has("appraisal_id") and not Cards.profile_valid(profile, state):
		return false
	if profile.has("commission_profile_id") and not Commission.profile_valid(profile, state):
		return false
	if profile.has("service_profile_id") and not ServiceCustody.profile_valid(profile, state):
		return false
	return true

static func seed(state: Dictionary, profile: Dictionary) -> Dictionary:
	if not profile_valid(profile, state) or state.has("alpha_shop") or int(state.revision) != 0:
		return {}
	var next: Dictionary = state.duplicate(true)
	next["alpha_shop"] = {
		"version": 1, "profile": profile.duplicate(true),
		"binding": Rules.canonical(profile).sha256_text(),
		"day": 1, "phase": "DAY_PREP", "cursor": 0, "active": "",
		"outcomes": {}, "settled_days": [], "contacts": {}, "commands": []
	}
	if profile.content_version in ["b2-preview-1", "b2-preview-2", "b2-cards-pilot-1", "b2-cards-commission-1", "b2-cards-commission-named-1", "b2-cards-commission-service-1", "b2-cards-commission-service-recovery-2"]:
		next.alpha_shop["displayed"] = []
	if profile.has("contracts"):
		next.alpha_shop["contracts"] = Contract.seed(profile)
	if profile.has("appraisal_id"):
		next.alpha_shop["appraisal"] = Cards.seed()
	if profile.has("commission_profile_id"):
		next.alpha_shop["commissions"] = Commission.seed(str(profile.commission_profile_id))
	if profile.has("service_profile_id"):
		next.alpha_shop["services"] = ServiceCustody.seed(str(profile.service_profile_id))
	return Rules.normalized(next)

static func active_row(a: Dictionary) -> Dictionary:
	if a.active == "":
		return {}
	for row: Dictionary in a.profile.days[int(a.day) - 1]:
		if row.id == a.active:
			return row.duplicate(true)
	return {}

static func can_contact(a: Dictionary, actor: String) -> bool:
	return a.phase == "EVENING_WORK" and a.contacts.has(actor) and a.contacts[actor].status == "available" and actor not in a.profile.unavailable_actors

## A customer's conversation can only refer to actions actually addressed to
## that same actor. This projection is read-only; it does not persist a second
## NPC memory or expose the player's unshared private appraisal observations.
static func _last_public_offer(a: Dictionary, visit_id: String) -> Dictionary:
	if not a.has("appraisal"):
		return {}
	var notes: Dictionary = a.appraisal.visits.get(visit_id, {})
	var offers: Array = notes.get("offers", [])
	if offers.is_empty():
		return {}
	var offer: Dictionary = offers[offers.size() - 1]
	var public_slots: Array = []
	for revealed: Dictionary in offer.revealed:
		# Only public, already spoken facts. No private observation values or
		# agreement rules cross the customer-facing DTO boundary.
		public_slots.append(str(revealed.slot))
	return {"amount": int(offer.amount), "currency": str(offer.currency),
		"response": str(offer.response), "disclosed_count": public_slots.size(), "public_slots": public_slots}

static func npc_context(state: Dictionary) -> Dictionary:
	if not state.has("alpha_shop"):
		return {}
	var a: Dictionary = state.alpha_shop
	var current: Dictionary = active_row(a)
	if current.is_empty():
		return {}
	var prior: Dictionary = {}
	for day: Array in a.profile.days:
		for visit: Dictionary in day:
			if visit.actor_id != current.actor_id or visit.id == current.id:
				continue
			var outcome: String = str(a.outcomes.get(visit.id, ""))
			if outcome.is_empty() or outcome == "unserved":
				continue
			var offer: Dictionary = _last_public_offer(a, str(visit.id))
			if not offer.is_empty() or outcome in ["traded", "commission_delivered", "service_delivered"]:
				prior = {"outcome": outcome, "offer": offer}
	return {"current_offer": _last_public_offer(a, str(current.id)),
		"current_outcome": str(a.outcomes.get(current.id, "")), "prior": prior}

## B2 candidate only: every physical shelf item must be an owned free root
## located in the actual, non-custody inventory. Never infer listing from price.
static func display_gate(state: Dictionary, p: Dictionary, withdraw: bool = false) -> String:
	var a: Dictionary = state.alpha_shop
	if a.profile.content_version not in ["b2-preview-1", "b2-preview-2", "b2-cards-pilot-1", "b2-cards-commission-1", "b2-cards-commission-named-1", "b2-cards-commission-service-1", "b2-cards-commission-service-recovery-2"] or not Rules.keys(p, ["item_id", "x", "y", "rotated"]):
		return "alpha_b2_display_shape"
	if a.phase not in ["OPEN_IDLE", "EVENING_WORK"] or not Rules.identifier(p.item_id):
		return "alpha_display_phase"
	if not state.items.has(p.item_id) or not state.inventories.has("storefront_grid"):
		return "alpha_display_item"
	var item: Dictionary = state.items[p.item_id]
	var listed: bool = p.item_id in a.displayed
	if item.owner_id != "player" or item.custodian_id != "player" or item.status != "stock" or item.protected or not item.reservation_id.is_empty() or not item.parent_id.is_empty():
		return "alpha_display_ownership"
	if not p.rotated is bool or not Rules.integer(p.x, 0, 9) or not Rules.integer(p.y, 0, 5):
		return "alpha_display_coordinates"
	if withdraw:
		return "" if listed and item.inventory == "storefront_grid" else "alpha_not_displayed"
	return "" if not listed and item.inventory == "player_stock" else "alpha_already_displayed"

static func after_display(state: Dictionary, item_id: String, withdraw: bool = false) -> void:
	if withdraw:
		state.alpha_shop.displayed.erase(item_id)
	else:
		state.alpha_shop.displayed.append(item_id)

static func trade_gate(state: Dictionary, p: Dictionary) -> String:
	var a: Dictionary = state.alpha_shop
	var row: Dictionary = active_row(a)
	if a.profile.content_version not in ["b2-preview-1", "b2-preview-2", "b2-cards-pilot-1", "b2-cards-commission-1", "b2-cards-commission-named-1", "b2-cards-commission-service-1", "b2-cards-commission-service-recovery-2"] or a.phase != "CUSTOMER_ACTIVE" or row.is_empty():
		return "alpha_trade_phase"
	if not Rules.keys(p, ["visit_id", "item_id", "seller", "buyer", "currency", "amount", "inventory", "x", "y", "rotated"]) or p.visit_id != row.id or not state.visits.has(row.id):
		return "alpha_trade_visit"
	if a.has("commissions") and Commission.is_return_visit(p.visit_id, str(a.profile.get("commission_profile_id", ""))):
		return "alpha_commission_delivery_only"
	var visit: Dictionary = state.visits[row.id]
	if visit.scope.completed or not visit.prices.has(p.item_id) or not state.items.has(p.item_id):
		return "alpha_trade_item"
	if visit.seller != p.seller or visit.buyer != p.buyer or row.actor_id not in [p.seller, p.buyer]:
		return "alpha_trade_actor"
	var item: Dictionary = state.items[p.item_id]
	if visit.seller == "player":
		if visit.buyer != row.actor_id or p.item_id not in a.displayed or item.inventory != "storefront_grid" or p.inventory != row.actor_id + "_grid":
			return "alpha_trade_not_displayed"
	elif visit.seller != row.actor_id or visit.buyer != "player" or item.inventory == "storefront_grid" or p.inventory != "player_stock":
		return "alpha_trade_purchase_terms"
	return ""

static func after_trade(state: Dictionary, p: Dictionary) -> void:
	var a: Dictionary = state.alpha_shop
	a.outcomes[a.active] = "traded"
	if p.item_id in a.displayed:
		a.displayed.erase(p.item_id)
	a.phase = "CUSTOMER_EXIT"

static func apply(state: Dictionary, command: Dictionary) -> String:
	var a: Dictionary = state.alpha_shop
	var p: Dictionary = command.payload
	var kind: String = command.type
	if kind not in ACTIONS:
		return "alpha_command_unavailable"
	if kind in Contract.ACTIONS:
		return Contract.apply(state, command) if a.has("contracts") else "alpha_contract_unavailable"
	if kind in Cards.ACTIONS:
		return Cards.apply(state, command) if a.has("appraisal") else "alpha_appraisal_unavailable"
	if kind in Commission.ACTIONS:
		return Commission.apply(state, command) if a.has("commissions") else "alpha_commission_unavailable"
	if kind in ServiceCustody.ACTIONS:
		return ServiceCustody.apply(state, command) if a.has("services") else "alpha_service_unavailable"
	if kind != "alpha_exchange_contact" and not p.is_empty():
		return "alpha_payload"
	match kind:
		"alpha_open":
			if a.phase != "DAY_PREP":
				return "alpha_phase"
			a.phase = "OPEN_IDLE"
		"alpha_next_customer":
			if a.phase != "OPEN_IDLE":
				return "alpha_no_next_customer"
			var offered: Array = a.profile.days[int(a.day) - 1]
			var cursor: int = int(a.cursor)
			while cursor < offered.size() and ((a.has("commissions") and not Commission.scheduled(state, str(offered[cursor].id))) or (a.has("services") and not ServiceCustody.scheduled(state, str(offered[cursor].id)))):
				cursor += 1
			if cursor >= offered.size():
				return "alpha_no_next_customer"
			var row: Dictionary = offered[cursor]
			a.active = row.id
			a.cursor = cursor + 1
			a.phase = "CUSTOMER_ENTER"
		"alpha_ack_entry":
			if a.phase != "CUSTOMER_ENTER":
				return "alpha_phase"
			a.phase = "CUSTOMER_ACTIVE"
			if a.has("contracts"):
				Contract.on_entry(state, command.action_id)
			if a.has("commissions"):
				Commission.on_entry(state, command.action_id)
			if a.has("services"):
				ServiceCustody.on_entry(state, command.action_id)
		"alpha_exchange_contact":
			var row: Dictionary = active_row(a)
			if a.phase != "CUSTOMER_ACTIVE" or not Rules.keys(p, ["actor_id", "accepted"]):
				return "alpha_contact_context"
			if row.is_empty() or p.actor_id != row.actor_id or not row.contact_offer or p.accepted != true:
				return "alpha_contact_consent"
			if a.contacts.has(row.actor_id) or row.actor_id in a.profile.unavailable_actors:
				return "alpha_contact_duplicate_or_unavailable"
			a.contacts[row.actor_id] = {
				"contact_id": "contact_" + row.actor_id, "actor_id": row.actor_id,
				"exchange_event_id": command.action_id, "acquired_day": a.day,
				"channel": "counter", "status": "available"
			}
		"alpha_finish_customer":
			if a.phase != "CUSTOMER_ACTIVE":
				return "alpha_phase"
			if a.has("contracts"):
				Contract.on_visit_end(state, command.action_id)
			if a.has("commissions"):
				Commission.on_leave(state, command.action_id)
			if a.has("services"):
				ServiceCustody.on_leave(state, command.action_id)
			a.outcomes[a.active] = "departed"
			a.phase = "CUSTOMER_EXIT"
		"alpha_ack_exit":
			if a.phase != "CUSTOMER_EXIT":
				return "alpha_phase"
			a.active = ""
			a.phase = "OPEN_IDLE"
		"alpha_close":
			if a.phase != "OPEN_IDLE":
				return "alpha_customer_active"
			for i: int in range(int(a.cursor), a.profile.days[int(a.day) - 1].size()):
				var row: Dictionary = a.profile.days[int(a.day) - 1][i]
				if (not a.has("commissions") or Commission.scheduled(state, row.id)) and (not a.has("services") or ServiceCustody.scheduled(state, row.id)):
					a.outcomes[row.id] = "unserved"
			a.cursor = a.profile.days[int(a.day) - 1].size()
			if a.has("contracts"):
				Contract.on_close(state, command.action_id)
			if a.has("commissions"):
				Commission.on_close(state, command.action_id)
			if a.has("services"):
				ServiceCustody.on_close(state, command.action_id)
			a.phase = "CLOSE_SETTLE"
		"alpha_settle":
			if a.phase != "CLOSE_SETTLE" or int(a.day) in a.settled_days:
				return "alpha_duplicate_settlement"
			# Only explicit contract payments move actual money. Closing once
			# resolves due obligations, never invents automatic profit or fees.
			if a.has("contracts"):
				Contract.on_settle(state, command.action_id)
			if a.has("commissions"):
				Commission.on_settle(state, command.action_id)
			if a.has("services"):
				ServiceCustody.on_settle(state, command.action_id)
			a.settled_days.append(a.day)
			a.phase = "EVENING_WORK"
		"alpha_next_day":
			if a.phase != "EVENING_WORK" or int(a.day) not in a.settled_days:
				return "alpha_phase"
			a.phase = "COMPLETE" if int(a.day) == a.profile.days.size() else "NEXT_DAY"
		"alpha_prepare_day":
			if a.phase != "NEXT_DAY":
				return "alpha_phase"
			a.day += 1
			# Internal legacy day-index bridge only. No player-visible clock,
			# inspection minutes, action points or time-consuming actions.
			state.game_minutes = (int(a.day) - 1) * 1440
			if a.has("contracts"):
				Contract.on_morning(state, command.action_id)
			a.cursor = 0
			a.phase = "DAY_PREP"
	return ""

static func view(state: Dictionary) -> Dictionary:
	if not state.has("alpha_shop"):
		return {}
	var a: Dictionary = state.alpha_shop
	var row: Dictionary = active_row(a)
	var contacts: Array = []
	var pending_visits: int = 0
	for i: int in range(int(a.cursor), a.profile.days[int(a.day) - 1].size()):
		var candidate: Dictionary = a.profile.days[int(a.day) - 1][i]
		if (not a.has("commissions") or Commission.scheduled(state, candidate.id)) and (not a.has("services") or ServiceCustody.scheduled(state, candidate.id)):
			pending_visits += 1
	var contract_view: Dictionary = Contract.view(state)
	for actor: String in a.contacts:
		contacts.append({"actor_id": actor, "contact_id": a.contacts[actor].contact_id, "acquired_day": int(a.contacts[actor].acquired_day), "callable": can_contact(a, actor)})
	contacts.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.actor_id < y.actor_id)
	return {
		"day": a.day, "phase": a.phase, "active": row,
		"remaining": pending_visits,
		"contacts": contacts, "contact_exchanged": not row.is_empty() and a.contacts.has(row.actor_id),
		"can_exchange": a.phase == "CUSTOMER_ACTIVE" and not row.is_empty() and row.contact_offer and not a.contacts.has(row.actor_id),
		"settled": int(a.day) in a.settled_days,
		"displayed_items": a.get("displayed", []).duplicate(),
		"appraisal": Cards.view(state) if a.has("appraisal") else {},
		"npc_context": npc_context(state),
		"commissions": Commission.view(state) if a.has("commissions") else {"entries":[]},
		"services": ServiceCustody.view(state) if a.has("services") else {"entries":[]},
		"contracts": contract_view.contracts, "news": contract_view.news
	}
