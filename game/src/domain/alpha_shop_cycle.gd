extends RefCounted
## Opt-in B1 date/phase authority. Does not mint funds, items, time or contracts.
const Rules = preload("res://src/domain/value_rules.gd")
const Contract = preload("res://src/domain/alpha_dated_contract.gd")
const Cards = preload("res://src/domain/alpha_card_trade.gd")
const Commission = preload("res://src/domain/alpha_commission.gd")
const ServiceCustody = preload("res://src/domain/alpha_service_custody.gd")
const B3Interest = preload("res://src/domain/alpha_b3_market_interest.gd")
const B3Fx = preload("res://src/domain/alpha_b3_fx.gd")
const B3Currency = preload("res://src/domain/alpha_b3_currency_terms.gd")
const Salvage = preload("res://src/domain/alpha_b3_outbound.gd")
const B3Random = preload("res://src/domain/alpha_b3_visit_randomizer.gd")
const Story = preload("res://src/domain/alpha_story_projection.gd")
const Grid = preload("res://src/domain/grid_primitives.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const ACTIONS: Array = ["alpha_open", "alpha_next_customer", "alpha_ack_entry", "alpha_finish_customer", "alpha_ack_exit", "alpha_close", "alpha_settle", "alpha_next_day", "alpha_prepare_day", "alpha_exchange_contact", "alpha_display", "alpha_withdraw_display", "alpha_trade", "alpha_contract_accept", "alpha_contract_decline", "alpha_contract_pay", "alpha_contract_extend", "alpha_inspect", "alpha_card_toggle", "alpha_price_offer", "alpha_hypothesis", "alpha_statement_retract", "alpha_statement_reaffirm", "alpha_claim_challenge", "alpha_commission_accept", "alpha_commission_decline", "alpha_commission_reserve", "alpha_commission_cancel", "alpha_commission_deliver", "alpha_service_accept", "alpha_service_decline", "alpha_service_repair", "alpha_service_deliver", "alpha_service_return_unpaid", "alpha_fx_trade", "alpha_salvage_dispatch", "alpha_salvage_cancel","week_pledge","week_redeem","week_extend","spatial_move","spatial_restore_item","spatial_attach","spatial_detach"]
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
	if profile is Dictionary and profile.get("content_version") in B3Interest.VERSIONS:
		keys.append("market_interest")
	if profile is Dictionary and profile.get("content_version")==B3Fx.VERSION:
		keys.append("fx_profile")
	if profile is Dictionary and profile.has("visit_random"):
		keys.append("visit_random")
	if profile is Dictionary and profile.has("spatial_opening"):
		if profile.spatial_opening != 1 or not profile.has("week_proposal"):
			return false
		keys.append("spatial_opening")
	if profile is Dictionary and profile.has("week_proposal"):
		if profile.week_proposal != "first_week_proposal_1" or profile.get("market_extension") != B3Interest.M7_MARKER:
			return false
		keys.append("week_proposal")
	if profile is Dictionary and profile.has("market_extension"):
		keys.append("market_extension")
	if not Rules.keys(profile, keys) or profile.id != "alpha_b1_v1" or not Rules.identifier(profile.content_version):
		return false
	# This bounded addon is only valid in its independent seeded campaign.
	# Legacy M1–M5 profiles remain byte-for-byte compatible.
	if profile.has("market_extension") and (profile.market_extension != B3Interest.M7_MARKER or not profile.has("visit_random") or str(profile.content_version) != B3Fx.VERSION):
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
	if profile.get("content_version") in B3Interest.VERSIONS and not B3Interest.profile_valid(profile,state):
		return false
	if profile.get("content_version")==B3Fx.VERSION and not B3Fx.profile_valid(profile,state):
		return false
	if profile.has("visit_random"):
		var policy: Variant = profile.visit_random
		if str(profile.content_version) != B3Fx.VERSION or not Rules.keys(policy, ["version", "seed", "locked_ids"]):
			return false
		if int(policy.version) != 1 or not Rules.integer(policy.seed, 1, Rules.LIMIT) or not policy.locked_ids is Array or policy.locked_ids != ["alpha_marcus_intro", "alpha_ian_hygiene_offer_d1", "hygiene_buy", "hygiene_sale"]:
			return false
		# Mandatory events and their original supply chain must remain
		# present on their authored day. A protected story sale without
		# its real D5 item acquisition would be an empty promise.
		var authored: Dictionary = {}
		for day_index: int in range(profile.days.size()):
			for row: Dictionary in profile.days[day_index]:
				if row.id in policy.locked_ids:
					authored[row.id] = {"day": day_index + 1, "actor": str(row.actor_id)}
		if authored != {
			"alpha_marcus_intro": {"day": 1, "actor": "marcus"},
			"alpha_ian_hygiene_offer_d1": {"day": 1, "actor": "ian"},
			"hygiene_buy": {"day": 5, "actor": "G05"},
			"hygiene_sale": {"day": 5, "actor": "ian"}
		}:
			return false
		var purchase: Dictionary = state.visits.get("hygiene_buy", {})
		var resale: Dictionary = state.visits.get("hygiene_sale", {})
		if purchase.is_empty() or resale.is_empty() or not purchase.prices.has("HY05") or not resale.prices.has("HY05"):
			return false
		if str(purchase.seller) != "G05" or str(purchase.buyer) != "player" or str(resale.seller) != "player" or str(resale.buyer) != "ian":
			return false
		if str(profile.get("story_rules", {}).get("clinic_supply_confirmed", {}).get("source_id", "")) != "hygiene_sale":
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
	if profile.has("week_proposal"):
		next.alpha_shop["week_pawn"] = {"status":"available","due":4,"events":[]}
	if profile.content_version in ["b2-preview-1", "b2-preview-2", "b2-cards-pilot-1", "b2-cards-commission-1", "b2-cards-commission-named-1", "b2-cards-commission-service-1", "b2-cards-commission-service-recovery-2", "b2-cards-commission-service-multi-3", B3Interest.CONTENT_VERSION, B3Interest.CONTENT_VERSION_M2, B3Fx.VERSION]:
		next.alpha_shop["displayed"] = []
	if profile.has("contracts"):
		next.alpha_shop["contracts"] = Contract.seed(profile)
	if profile.has("appraisal_id"):
		next.alpha_shop["appraisal"] = Cards.seed()
	if profile.has("commission_profile_id"):
		next.alpha_shop["commissions"] = Commission.seed(str(profile.commission_profile_id))
	if profile.has("service_profile_id"):
		next.alpha_shop["services"] = ServiceCustody.seed(str(profile.service_profile_id))
	if profile.get("content_version")==B3Fx.VERSION:
		next.alpha_shop["fx"] = B3Fx.seed()
	if profile.has("visit_random"):
		next.alpha_shop["random_visits"] = {"version":1, "day":0, "plan":[], "target":0, "shortfall":0}
	return Rules.normalized(next)

## Each replayed opening freezes an eligible nonstory visitor plan. Existing
## authored rows remain the only identities; committed returns cannot be dropped.
static func _admissible(state: Dictionary, visit_id: String) -> bool:
	var a: Dictionary = state.alpha_shop
	if visit_id == "tool_buy" and a.get("outbound", {}).get("tool_search", {}).get("status") == "empty":
		return false
	if a.has("week_pawn") and state.visits.has(visit_id) and visit_id not in a.profile.visit_random.locked_ids:
		var visit: Dictionary = state.visits[visit_id]
		# Appointments/service visits may trade an encumbered object under their
		# own authority. Ordinary merchandise has to have a real free root.
		if visit_id not in ["visit_g01","watch_a","tool_buy"] and visit.scope.kind == "ordinary" and visit.prices.size() == 1 and not Commission.is_return_visit(visit_id,str(a.profile.commission_profile_id)) and not ServiceCustody.is_return_visit(visit_id,str(a.profile.service_profile_id)):
			var id: String = str(visit.prices.keys()[0])
			var item: Dictionary = state.items[id]
			if visit.scope.completed or item.status != "stock" or item.protected or not item.reservation_id.is_empty() or not item.parent_id.is_empty():
				return false
			if visit.seller == "player":
				if item.owner_id != "player" or item.custodian_id != "player" or id not in a.displayed:
					# At opening a later same-day shelf sale can follow a real
					# funded supply. At the door require actual display.
					if a.phase != "DAY_PREP" or not _same_day_supply(state,id):
						return false
				for currency: String in ["VKC","USD"]:
					if state.wallets[visit.buyer][currency] < visit.prices[id][currency]:
						return false
			elif item.owner_id != visit.seller or item.custodian_id != visit.seller:
				return false
	return (not a.has("commissions") or Commission.scheduled(state, visit_id)) and (not a.has("services") or ServiceCustody.scheduled(state, visit_id)) and B3Interest.eligible(state, visit_id)

static func _same_day_supply(state: Dictionary, item_id: String) -> bool:
	var a: Dictionary = state.alpha_shop
	var item: Dictionary = state.items[item_id]
	for slot: Dictionary in a.profile.days[int(a.day)-1]:
		var supply: Dictionary = state.visits.get(slot.id,{})
		if supply.get("buyer") != "player" or supply.seller != item.owner_id or supply.seller != item.custodian_id or not supply.prices.has(item_id) or supply.scope.completed:
			continue
		var price: Dictionary = supply.prices[item_id]
		if state.wallets.player.VKC >= price.VKC and state.wallets.player.USD >= price.USD:
			return true
	return false

static func _planned_rows(a: Dictionary) -> Array:
	var source: Array = a.profile.days[int(a.day) - 1]
	if not a.has("random_visits"):
		return source
	if int(a.random_visits.day) != int(a.day):
		return []
	var selected: Array = []
	for visit_id: String in a.random_visits.plan:
		for row: Dictionary in source:
			if row.id == visit_id:
				selected.append(row)
				break
	return selected

static func _draw_day(state: Dictionary) -> String:
	var a: Dictionary = state.alpha_shop
	var rows: Array = a.profile.days[int(a.day) - 1]
	if a.has("week_pawn"):
		for slot: Dictionary in rows:
			if slot.id != "week_tool_buy_d7":
				continue
			# G01's optional NEW quote changes only if G01 took VKC at an
			# earlier sale and the shop resold the radio out of local stock.
			var received_vkc: bool = false
			var local_outflow: bool = false
			for sale: Dictionary in state.ledger:
				received_vkc = received_vkc or (sale.to == "G01" and int(sale.amounts.VKC) > 0)
				local_outflow = local_outflow or (sale.to == "player" and "R001" in sale.root_ids)
			if received_vkc and local_outflow and state.items.TL04.owner_id == "G01" and state.items.TL04.custodian_id == "G01":
				state.visits[slot.id].prices["TL04"] = {"VKC":0,"USD":1}
	var availability: Dictionary = {}
	var locked: Array = []
	for row: Dictionary in rows:
		var id: String = str(row.id)
		var admitted: bool = _admissible(state, id)
		availability[id] = admitted
		var commission_return: bool = a.has("commissions") and Commission.is_return_visit(id, str(a.profile.commission_profile_id))
		# A story-linked return is NOT an unconditional story event:
		# it is mandatory ONLY after the player actually accepted that order.
		# An unaccepted order cannot force an impossible counter appointment.
		var mandatory: bool = id in a.profile.visit_random.locked_ids and (admitted or not commission_return)
		if commission_return and admitted:
			mandatory = true
		if a.has("services") and ServiceCustody.is_return_visit(id, str(a.profile.service_profile_id)) and admitted:
			mandatory = true
		for request: Dictionary in a.get("outbound", {}).values():
			if admitted and request.status == "goods_offered" and request.visit_id == id:
				mandatory = true
		if a.profile.has("spatial_opening") and a.day == 1 and id == "visit_g01":
			mandatory = true
		if mandatory:
			locked.append(id)
	var result: Dictionary = B3Random.plan(rows, availability, locked, int(a.profile.visit_random.seed), int(a.day))
	if not bool(result.get("ok", false)):
		return str(result.get("error", "b3_random_schedule"))
	var ids: Array = []
	for visit: Dictionary in result.visits:
		ids.append(str(visit.id))
	a.random_visits.day = int(a.day)
	if a.profile.has("spatial_opening") and a.day == 1:
		for opening_id: String in ["visit_g01", "alpha_marcus_intro"]:
			if opening_id in ids:
				ids.erase(opening_id)
				ids.push_front(opening_id)
	a.random_visits.plan = ids
	a.random_visits.target = int(result.target)
	a.random_visits.shortfall = int(result.shortfall)
	return ""

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
		public_slots.append(str(revealed.slot))
	var standing: Dictionary = Cards.public_history(notes)
	# Historical knowledge persists even after explicit retraction. Only
	# statements actually submitted at this visitor's counter are projected.
	return {"amount": int(offer.amount), "currency": str(offer.currency),
		"response": str(offer.response), "disclosed_count": public_slots.size(),
		"public_slots": public_slots, "known_slots": standing.known_slots,
		"active_slots": standing.active_slots, "withdrawn_slots": standing.withdrawn_slots}

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
	# A challenge is spoken only after a direct opt-in command. Private
	# observations or possible claim inconsistencies are not NPC knowledge.
	var current_notes: Dictionary = a.get("appraisal",{}).get("visits",{}).get(str(current.id),{})
	var challenges: Array = current_notes.get("claim_challenges",[]).duplicate(true)
	return {"current_offer": _last_public_offer(a, str(current.id)),
		"current_challenges":challenges,
		"current_outcome": str(a.outcomes.get(current.id, "")), "prior": prior}

## B2 candidate only: every physical shelf item must be an owned free root
## located in the actual, non-custody inventory. Never infer listing from price.
static func display_gate(state: Dictionary, p: Dictionary, withdraw: bool = false) -> String:
	var a: Dictionary = state.alpha_shop
	if a.profile.content_version not in ["b2-preview-1", "b2-preview-2", "b2-cards-pilot-1", "b2-cards-commission-1", "b2-cards-commission-named-1", "b2-cards-commission-service-1", "b2-cards-commission-service-recovery-2", "b2-cards-commission-service-multi-3", B3Interest.CONTENT_VERSION, B3Interest.CONTENT_VERSION_M2, B3Fx.VERSION] or not Rules.keys(p, ["item_id", "x", "y", "rotated"]):
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

## Source-only shelf placement preview: reveal every free owned item, never
## an NPC's private property. The existing GameSession move, geometry,
## ownership, reservation and replay gates remain the sole authority.
## A physical placement is recomputed from current contents on each refresh.
static func shelf_options(state: Dictionary, defs: Dictionary) -> Dictionary:
	var options: Dictionary = {"display": [], "withdraw": []}
	if not state.has("alpha_shop") or not state.alpha_shop.has("displayed") or state.alpha_shop.phase not in ["OPEN_IDLE","EVENING_WORK"]:
		return options
	var ids: Array = state.items.keys()
	ids.sort()
	for item_id: String in ids:
		var item: Dictionary = state.items[item_id]
		if item.owner_id != "player" or item.custodian_id != "player" or item.status != "stock" or item.protected or not item.reservation_id.is_empty() or not item.parent_id.is_empty():
			continue
		var outgoing: bool = item.inventory == "storefront_grid" and item_id in state.alpha_shop.displayed
		var incoming: bool = item.inventory == "player_stock" and item_id not in state.alpha_shop.displayed
		if not (outgoing or incoming):
			continue
		var target: String = "player_stock" if outgoing else "storefront_grid"
		if not state.inventories.has(target):
			continue
		var target_grid: Dictionary = state.inventories[target]
		var placements: Array = []
		for other_id: String in state.items:
			var other: Dictionary = state.items[other_id]
			if other_id == item_id or other.inventory != target or not other.parent_id.is_empty():
				continue
			var footprint: Array = Objects.footprint(state,defs,other_id)
			placements.append({"item_id":other_id,"x":other.x,"y":other.y,"rotated":other.rotated,"width":footprint[0],"height":footprint[1]})
		var size: Array = Objects.footprint(state,defs,item_id)
		var fit: Dictionary = Grid.first_fit(target_grid.width,target_grid.height,placements,{"item_id":item_id,"width":size[0],"height":size[1],"rotated":item.rotated})
		if fit.get("ok",false):
			var option: Dictionary = {"item_id":item_id,"def_id":item.def_id,"x":fit.x,"y":fit.y,"rotated":fit.rotated}
			options["withdraw" if outgoing else "display"].append(option)
	return options

static func after_display(state: Dictionary, item_id: String, withdraw: bool = false) -> void:
	if withdraw:
		state.alpha_shop.displayed.erase(item_id)
	else:
		state.alpha_shop.displayed.append(item_id)

static func trade_gate(state: Dictionary, p: Dictionary) -> String:
	var a: Dictionary = state.alpha_shop
	var row: Dictionary = active_row(a)
	if a.profile.content_version not in ["b2-preview-1", "b2-preview-2", "b2-cards-pilot-1", "b2-cards-commission-1", "b2-cards-commission-named-1", "b2-cards-commission-service-1", "b2-cards-commission-service-recovery-2", "b2-cards-commission-service-multi-3", B3Interest.CONTENT_VERSION, B3Interest.CONTENT_VERSION_M2, B3Fx.VERSION] or a.phase != "CUSTOMER_ACTIVE" or row.is_empty():
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
	for request: Dictionary in a.get("outbound", {}).values():
		if request.status == "goods_offered" and request.visit_id == a.active and request.item_id == p.item_id:
			request.status = "received"
	if p.item_id in a.displayed:
		a.displayed.erase(p.item_id)
	a.phase = "CUSTOMER_EXIT"

static func apply(state: Dictionary, command: Dictionary) -> String:
	var a: Dictionary = state.alpha_shop
	var p: Dictionary = command.payload
	var kind: String = command.type
	if kind not in ACTIONS:
		return "alpha_command_unavailable"
	if kind in ["alpha_salvage_dispatch", "alpha_salvage_cancel"]:
		if a.profile.get("market_extension") != B3Interest.M7_MARKER or not Rules.keys(p, ["request_id"]) or not Rules.identifier(p.request_id):
			return "salvage_request"
		var terms: Dictionary = Salvage.catalog(a).get(p.request_id, {})
		if terms.is_empty() or not can_contact(a, terms.actor_id):
			return "salvage_no_agreement"
		return Salvage.apply(state, str(p.request_id), terms, command)
	if kind in Contract.ACTIONS:
		return Contract.apply(state, command) if a.has("contracts") else "alpha_contract_unavailable"
	if kind in Cards.ACTIONS:
		return Cards.apply(state, command) if a.has("appraisal") else "alpha_appraisal_unavailable"
	if kind in Commission.ACTIONS:
		return Commission.apply(state, command) if a.has("commissions") else "alpha_commission_unavailable"
	if kind in ServiceCustody.ACTIONS:
		return ServiceCustody.apply(state, command) if a.has("services") else "alpha_service_unavailable"
	if kind=="alpha_fx_trade":
		return B3Fx.apply(state,command) if a.has("fx") else "alpha_fx_unavailable"
	if kind != "alpha_exchange_contact" and not p.is_empty():
		return "alpha_payload"
	match kind:
		"alpha_open":
			if a.phase != "DAY_PREP":
				return "alpha_phase"
			if a.has("random_visits"):
				var planning_error: String = _draw_day(state)
				if not planning_error.is_empty():
					return planning_error
			a.phase = "OPEN_IDLE"
		"alpha_next_customer":
			if a.phase != "OPEN_IDLE":
				return "alpha_no_next_customer"
			var offered: Array = _planned_rows(a)
			var cursor: int = int(a.cursor)
			while cursor < offered.size() and not _admissible(state, str(offered[cursor].id)):
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
			for request: Dictionary in a.get("outbound", {}).values():
				if request.status == "goods_offered" and request.visit_id == a.active:
					request.status = "declined"
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
			if a.has("commissions") and not Commission.pending_pickup(state).is_empty():
				return "alpha_commission_pickup_pending"
			var remaining_rows: Array = _planned_rows(a)
			for i: int in range(int(a.cursor), remaining_rows.size()):
				var row: Dictionary = remaining_rows[i]
				if _admissible(state, str(row.id)):
					a.outcomes[row.id] = "unserved"
			for request: Dictionary in a.get("outbound", {}).values():
				if request.status == "goods_offered":
					request.status = "missed"
			a.cursor = remaining_rows.size()
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
			if a.has("random_visits"):
				a.random_visits.day = 0
				a.random_visits.plan = []
				a.random_visits.target = 0
				a.random_visits.shortfall = 0
			a.phase = "DAY_PREP"
			Salvage.morning(state)
	return ""

static func view(state: Dictionary) -> Dictionary:
	if not state.has("alpha_shop"):
		return {}
	var a: Dictionary = state.alpha_shop
	var row: Dictionary = active_row(a)
	var contacts: Array = []
	var pending_visits: int = 0
	var today_rows: Array = _planned_rows(a)
	for i: int in range(int(a.cursor), today_rows.size()):
		var candidate: Dictionary = today_rows[i]
		if _admissible(state, str(candidate.id)):
			pending_visits += 1
	var contract_view: Dictionary = Contract.view(state)
	for actor: String in a.contacts:
		contacts.append({"actor_id": actor, "contact_id": a.contacts[actor].contact_id, "acquired_day": int(a.contacts[actor].acquired_day), "callable": can_contact(a, actor)})
	contacts.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.actor_id < y.actor_id)
	var result: Dictionary = {
		"day": a.day, "phase": a.phase, "active": row,
		"remaining": pending_visits,
		"contacts": contacts, "contact_exchanged": not row.is_empty() and a.contacts.has(row.actor_id),
		"can_exchange": a.phase == "CUSTOMER_ACTIVE" and not row.is_empty() and row.contact_offer and not a.contacts.has(row.actor_id),
		"settled": int(a.day) in a.settled_days,
		"pickup_pending": Commission.pending_pickup(state) if a.has("commissions") else "",
		"displayed_items": a.get("displayed", []).duplicate(),
		"appraisal": Cards.view(state) if a.has("appraisal") else {},
		"npc_context": npc_context(state),
		"commissions": Commission.view(state) if a.has("commissions") else {"entries":[]},
		"services": ServiceCustody.view(state) if a.has("services") else {"entries":[]},
		"fx": B3Fx.view(state) if a.has("fx") else {},
		"contracts": contract_view.contracts, "news": contract_view.news,
		"story": Story.view(state)
	}
	if a.profile.content_version == B3Fx.VERSION:
		result["currency_terms"] = B3Currency.view(state)
	if a.has("random_visits"):
		# Daily target is internal planning metadata, not guaranteed attendance.
		result["random_visits"] = {"planned": a.random_visits.plan.size() if int(a.random_visits.day) == int(a.day) else 0,
			"seeded": int(a.random_visits.day) == int(a.day)}
	if a.profile.get("market_extension") == B3Interest.M7_MARKER:
		var arrived: int = 0
		var eligible_now: int = 0
		var protected_now: int = 0
		var shortages: Dictionary = {}
		var source: Array = a.profile.days[int(a.day) - 1]
		for candidate: Dictionary in source:
			var id: String = str(candidate.id)
			if a.active == id or str(a.outcomes.get(id, "")) not in ["", "unserved"]:
				arrived += 1
			var reason: String = B3Interest.interest_status(state, id)
			if reason not in ["ordinary", "eligible"]:
				shortages[reason] = int(shortages.get(reason, 0)) + 1
			if _admissible(state, id):
				eligible_now += 1
				if id in a.profile.visit_random.locked_ids or Commission.is_return_visit(id, str(a.profile.get("commission_profile_id", ""))) or ServiceCustody.is_return_visit(id, str(a.profile.get("service_profile_id", ""))):
					protected_now += 1
		if a.phase == "EVENING_WORK":
			var options: Array = []
			for id: String in Salvage.catalog(a):
				var terms: Dictionary = Salvage.catalog(a)[id]
				if not can_contact(a, terms.actor_id):
					continue
				var request: Dictionary = a.get("outbound", {}).get(id, {})
				if request.is_empty() and a.day == terms.offer_day:
					options.append({"id":id, "actor":terms.actor_id, "label":terms.public_terms_key,
						"command":"alpha_salvage_dispatch"})
				elif request.get("status") in ["dispatched","delayed"] and terms.has("cancel_refund"):
					options.append({"id":id, "actor":terms.actor_id, "label":terms.public_cancel_key,
						"command":"alpha_salvage_cancel"})
			result["outbound_options"] = options
		if a.phase in ["CLOSE_SETTLE", "EVENING_WORK", "COMPLETE"]:
			var flow: Dictionary = {"bought":0, "sold":0, "VKC":0, "USD":0}
			for entry: Dictionary in state.ledger:
				if int(entry.game_minutes / 1440) + 1 != int(a.day):
					continue
				var buying: bool = entry.from == "player"
				if not buying and entry.to != "player":
					continue
				var side: String = "bought" if buying else "sold"
				flow[side] += entry.root_ids.size()
				for currency: String in ["VKC", "USD"]:
					flow[currency] += int(entry.amounts[currency]) * (-1 if buying else 1)
			result["local_trade_flow"] = flow
		var trade: Dictionary = result.get("currency_terms", {}).get("trade", {})
		var offer: Dictionary = result.npc_context.get("current_offer", {})
		if trade.get("direction") == "pay" and not offer.is_empty() and offer.response == "accepted" and offer.currency == trade.currency:
			result.currency_terms["can_pay_public_offer"] = int(state.wallets.player[offer.currency]) >= int(offer.amount)
		result["attendance"] = {"source": source.size(), "eligible_now": eligible_now, "interest_shortages_now": shortages,
			"protected_now": protected_now, "target": int(a.random_visits.target),
			"planned": today_rows.size(), "arrived": arrived}
	return result
