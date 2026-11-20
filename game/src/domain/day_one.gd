extends RefCounted
## Day-one continuation policy. No independent mutable state.
const Rules = preload("res://src/domain/value_rules.gd")
const Opening = preload("res://src/domain/gate1_opening.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const WHOLESALE: String = "day1_wholesale"
const RETAIL: String = "visit_g02_buy"
const WHOLESALER: String = "day1_wholesaler"
const ITEM: String = "R001"
const SERVICE: String = "visit_g02_service"
const SERVICE_ITEM: String = "W001"
const RECOVERY: String = "day2_radio_recovery"
const RECOVERY_BUYER: String = "day2_buyer"
const SERVICE_FEE: int = 30
const SERVICE_COST: int = 10
const OVERHEAD: int = 15
const ACTIONS: Array = ["begin_day_one", "day_one_next", "day_one_decline", "day_one_accept_service", "day_one_cancel_service", "day_one_close", "day_one_next_morning", "day_one_deliver_service", "day_one_pay_overhead"]
const RETAIL_PRICE: int = 170
const WHOLESALE_PRICE: int = 135
const Clock = preload("res://src/domain/business_clock.gd")
const CLOSE: int = Clock.BUSINESS_MINUTES

static func marker() -> Dictionary:
	return {"base": null, "commands": [], "service": null, "closing": null, "settlements": [], "news": []}

static func can_begin(state: Dictionary) -> bool:
	return state.phase == "shop" and state.campaign.queue.cursor == 1 and state.campaign.queue.active_visit_id == null and state.campaign.get("negotiation", {}).get("terminal") != null

static func sale_visit(id: String, buyer: String, price: int) -> Dictionary:
	return {"scope": {"visit_id": id, "kind": "ordinary", "purpose": "sale", "completed": false, "required_ids": []}, "seller": "player", "buyer": buyer, "prices": {ITEM: {"VKC": price, "USD": 0}}, "opens": 0, "expires": CLOSE, "allow_inspection": false}

static func begin(state: Dictionary, p: Dictionary) -> String:
	if not p.is_empty() or state.day_one != marker() or not can_begin(state):
		return "day_one_begin"
	var prefix: Dictionary = state.duplicate(true)
	prefix.erase("day_one")
	state.day_one.base = prefix
	state.wallets[WHOLESALER] = {"VKC": WHOLESALE_PRICE, "USD": 0}
	state.inventories["wholesale_grid"] = {"owner_id": WHOLESALER, "width": 4, "height": 3, "host_item": ""}
	state.inventories["player_service"] = {"owner_id": "player", "width": 4, "height": 3, "host_item": ""}
	state.inventories["g02_service_grid"] = {"owner_id": "G02", "width": 4, "height": 3, "host_item": ""}
	state.visits[WHOLESALE] = sale_visit(WHOLESALE, WHOLESALER, WHOLESALE_PRICE)
	return ""

static func owned_radio(state: Dictionary) -> bool:
	var row: Dictionary = state.items.get(ITEM, {})
	return row.get("owner_id") == "player" and row.get("custodian_id") == "player" and row.get("status") == "stock"

static func shop(state: Dictionary) -> bool:
	return state.campaign.day == 1 and state.game_minutes <= CLOSE and Clock.business_at(int(state.game_minutes), state.phase)

static func next(state: Dictionary, p: Dictionary) -> String:
	var queue: Dictionary = state.campaign.queue
	if not p.is_empty() or not shop(state) or state.game_minutes >= CLOSE or queue.active_visit_id != null:
		return "day_one_visit"
	match int(queue.cursor):
		1:
			queue.cursor = 2
			queue.active_visit_id = RETAIL
			state.visits[RETAIL] = sale_visit(RETAIL, "G02", RETAIL_PRICE)
		2:
			if state.items.has(SERVICE_ITEM) or state.day_one.service != null:
				return "service_duplicate"
			queue.cursor = 3
			queue.active_visit_id = SERVICE
			var item: Dictionary = Objects.fresh_item("fictional_gear", "G02", "g02_service_grid", 0, 0, "day1_service_fixture")
			# Abstract condition only, not an operational equipment procedure.
			item.functional = false
			state.items[SERVICE_ITEM] = item
			state.day_one.service = {"status": "offered", "fee": SERVICE_FEE, "direct_cost": SERVICE_COST, "due_minute": 1440}
		_:
			return "day_one_visit"
	return ""

static func decline(state: Dictionary, p: Dictionary) -> String:
	var queue: Dictionary = state.campaign.queue
	if not p.is_empty() or not shop(state) or queue.active_visit_id not in [RETAIL, SERVICE]:
		return "day_one_decline"
	if queue.active_visit_id == SERVICE:
		state.day_one.service.status = "declined"
	queue.active_visit_id = null
	return ""

static func may_sell(state: Dictionary, p: Dictionary) -> bool:
	if not owned_radio(state) or p.get("item_id") != ITEM or p.get("seller") != "player":
		return false
	var id: Variant = p.get("visit_id")
	var active: Variant = state.campaign.queue.active_visit_id
	if id == RECOVERY:
		return state.campaign.day == 2 and state.phase == "shop" and state.game_minutes == 1440 and state.visits.has(RECOVERY) and not state.visits[RECOVERY].scope.completed and (state.day_one.service == null or state.day_one.service.status not in ["accepted", "complete"]) and p.get("inventory") == "day2_buyer_grid"
	if not shop(state):
		return false
	if id == WHOLESALE:
		return active == null and not state.visits[WHOLESALE].scope.completed and p.get("inventory") == "wholesale_grid"
	if id == RETAIL:
		return active == RETAIL and state.items[ITEM].inventory == "player_display" and not state.visits[RETAIL].scope.completed and p.get("inventory") == "g02_grid"
	return false

static func on_sale(state: Dictionary, p: Dictionary) -> void:
	if p.visit_id == RETAIL:
		state.campaign.queue.active_visit_id = null

static func may_move(state: Dictionary, p: Dictionary) -> bool:
	if not (shop(state) or state.phase == "workshop" or state.campaign.day == 2) or not owned_radio(state) or p.get("actor") != "player" or p.get("item_id") != ITEM or p.get("inventory") not in ["player_stock", "player_display"]:
		return false
	if not Rules.keys(p, ["actor", "item_id", "inventory", "x", "y", "rotated"]) or not Rules.integer(p.x, 0, 9) or not Rules.integer(p.y, 0, 9) or not p.rotated is bool:
		return false
	var row: Dictionary = state.items[ITEM]
	return row.inventory != p.get("inventory") or row.x != p.get("x") or row.y != p.get("y") or row.rotated != p.get("rotated")

## Customer custody is not a sale and does not enter the merchandise asset ledger.
static func accept_service(state: Dictionary, p: Dictionary) -> String:
	if not p.is_empty() or not shop(state) or state.campaign.queue.active_visit_id != SERVICE or state.day_one.service.status != "offered" or state.wallets.G02.VKC < SERVICE_FEE:
		return "service_unavailable"
	var item: Dictionary = state.items[SERVICE_ITEM]
	if item.owner_id != "G02" or item.custodian_id != "G02" or item.status != "stock":
		return "service_custody"
	item.custodian_id = "player"
	item.inventory = "player_service"
	item.status = "custody_service"
	item.service_permission = true
	item.version += 1
	state.day_one.service.status = "accepted"
	state.campaign.queue.active_visit_id = null
	return ""

static func may_restore(state: Dictionary, p: Dictionary) -> bool:
	return state.phase == "workshop" and state.game_minutes == CLOSE and state.day_one.service != null and state.day_one.service.status == "accepted" and Rules.keys(p, ["actor", "item_id"]) and p.actor == "player" and p.item_id == SERVICE_ITEM

static func mark_restored(state: Dictionary, id: String) -> void:
	state.day_one.service.status = "complete"
	state.day_one.settlements.append({"id": id, "kind": "service_cost", "minute": state.game_minutes, "amount": SERVICE_COST})

static func return_item(state: Dictionary) -> void:
	var item: Dictionary = state.items[SERVICE_ITEM]
	item.custodian_id = "G02"
	item.inventory = "g02_service_grid"
	item.status = "stock"
	item.service_permission = false
	item.version += 1

static func cancel_service(state: Dictionary, p: Dictionary) -> String:
	if not p.is_empty() or state.day_one.service == null or state.day_one.service.status != "accepted" or not (state.phase == "workshop" or state.campaign.day == 2):
		return "service_cancel"
	return_item(state)
	state.day_one.service.status = "cancelled"
	return ""

static func close_shop(state: Dictionary, p: Dictionary, id: String) -> String:
	if not Rules.keys(p, ["confirm"]) or not p.confirm is bool or not p.confirm or not shop(state) or state.campaign.queue.active_visit_id != null or state.day_one.closing != null:
		return "closing_unavailable"
	var paid: int = mini(OVERHEAD, int(state.wallets.player.VKC))
	state.wallets.player.VKC -= paid
	state.day_one.closing = {"id": id, "paid": paid, "debt": OVERHEAD - paid, "skipped": Opening.QUEUE.slice(int(state.campaign.queue.cursor))}
	state.day_one.settlements.append({"id": id, "kind": "overhead", "minute": CLOSE, "amount": paid})
	state.campaign.queue.cursor = Opening.QUEUE.size()
	state.game_minutes = CLOSE
	state.phase = "workshop"
	return ""

static func next_morning(state: Dictionary, p: Dictionary) -> String:
	if not p.is_empty() or state.phase != "workshop" or state.campaign.day != 1 or state.game_minutes != CLOSE:
		return "morning_unavailable"
	state.game_minutes = 1440
	state.campaign.day = 2
	state.phase = "shop"
	state.day_one.news.append({"id": "day2_sora_market_note", "minute": 1440, "source_key": "dayone.news_source", "text_key": "dayone.news_opening", "confidence": "reported"})
	if owned_radio(state):
		state.wallets[RECOVERY_BUYER] = {"VKC": 130, "USD": 0}
		state.inventories["day2_buyer_grid"] = {"owner_id": RECOVERY_BUYER, "width": 4, "height": 3, "host_item": ""}
		var visit: Dictionary = sale_visit(RECOVERY, RECOVERY_BUYER, 130)
		visit.opens = 1440
		visit.expires = 1440
		state.visits[RECOVERY] = visit
	return ""

static func deliver_service(state: Dictionary, p: Dictionary, id: String) -> String:
	if not p.is_empty() or state.phase != "shop" or state.campaign.day != 2 or state.game_minutes != 1440 or state.day_one.service == null or state.day_one.service.status != "complete" or state.wallets.G02.VKC < SERVICE_FEE:
		return "service_delivery"
	var item: Dictionary = state.items[SERVICE_ITEM]
	if item.owner_id != "G02" or item.custodian_id != "player" or item.status != "custody_service" or not item.restored:
		return "service_delivery"
	return_item(state)
	state.wallets.G02.VKC -= SERVICE_FEE
	state.wallets.player.VKC += SERVICE_FEE
	state.day_one.service.status = "delivered"
	state.day_one.settlements.append({"id": id, "kind": "service_fee", "minute": state.game_minutes, "amount": SERVICE_FEE})
	return ""

static func pay_overhead(state: Dictionary, p: Dictionary, id: String) -> String:
	if not p.is_empty() or state.campaign.day != 2 or state.day_one.closing == null or state.day_one.closing.debt <= 0 or state.wallets.player.VKC < state.day_one.closing.debt:
		return "overhead_unavailable"
	var paid: int = state.day_one.closing.debt
	state.wallets.player.VKC -= paid
	state.day_one.closing.paid += paid
	state.day_one.closing.debt = 0
	state.day_one.settlements.append({"id": id, "kind": "overhead_debt", "minute": state.game_minutes, "amount": paid})
	return ""

static func view(state: Dictionary, defs: Dictionary) -> Dictionary:
	if not state.has("day_one"):
		return {}
	if state.day_one.base == null:
		return {"started": false, "can_begin": can_begin(state)}
	var queue: Dictionary = state.campaign.queue
	var rows: Array = []
	for id: String in state.items:
		var row: Dictionary = state.items[id]
		if row.custodian_id != "player" or not row.parent_id.is_empty():
			continue
		rows.append({"id": id, "name_key": defs[row.def_id].localization_key, "visual_id": row.def_id, "inventory": row.inventory, "x": row.x, "y": row.y, "rotated": row.rotated, "size": Objects.footprint(state, defs, id), "basis": row.basis.duplicate(true), "owned": row.owner_id == "player", "status": row.status})
	var ledger: Array = []
	for entry: Dictionary in state.ledger:
		var margin: Variant = int(entry.amounts.VKC) - int(entry.basis.VKC) if entry.to == "player" and entry.basis.VKC != null else null
		ledger.append({"item_ids": entry.item_ids.duplicate(), "visit_id": entry.visit_id, "direction": "sale" if entry.to == "player" else "purchase", "amounts": entry.amounts.duplicate(true), "basis": entry.basis.duplicate(true), "margin": margin})
	return {"started": true, "phase": state.phase, "minute": state.game_minutes, "active_visit": queue.active_visit_id, "cursor": queue.cursor, "can_next": shop(state) and state.game_minutes < CLOSE and queue.active_visit_id == null and queue.cursor in [1, 2], "can_decline": shop(state) and queue.active_visit_id in [RETAIL, SERVICE], "can_wholesale": shop(state) and owned_radio(state) and queue.active_visit_id == null and not state.visits[WHOLESALE].scope.completed, "can_retail": shop(state) and owned_radio(state) and queue.active_visit_id == RETAIL and state.items[ITEM].inventory == "player_display", "retail_price": RETAIL_PRICE, "wholesale_price": WHOLESALE_PRICE, "wholesale_visit": WHOLESALE, "retail_visit": RETAIL, "wholesaler": WHOLESALER, "stock": rows, "ledger": ledger, "action_count": state.day_one.commands.size(), "day": state.campaign.day, "service": state.day_one.service.duplicate(true) if state.day_one.service != null else null, "closing": state.day_one.closing.duplicate(true) if state.day_one.closing != null else null, "settlements": state.day_one.settlements.duplicate(true), "news": state.day_one.news.duplicate(true), "can_accept_service": shop(state) and queue.active_visit_id == SERVICE and state.wallets.G02.VKC >= SERVICE_FEE, "can_close_shop": shop(state) and queue.active_visit_id == null and state.day_one.closing == null, "can_work": may_restore(state, {"actor": "player", "item_id": SERVICE_ITEM}) and state.wallets.player.VKC >= SERVICE_COST, "can_cancel_service": state.day_one.service != null and state.day_one.service.status == "accepted" and (state.phase == "workshop" or state.campaign.day == 2), "can_morning": state.phase == "workshop", "can_deliver": state.campaign.day == 2 and state.day_one.service != null and state.day_one.service.status == "complete", "can_pay_overhead": state.campaign.day == 2 and state.day_one.closing != null and state.day_one.closing.debt > 0 and state.wallets.player.VKC >= state.day_one.closing.debt, "can_recovery": may_sell(state, {"visit_id": RECOVERY, "item_id": ITEM, "seller": "player", "inventory": "day2_buyer_grid"}), "recovery_visit": RECOVERY, "recovery_buyer": RECOVERY_BUYER, "recovery_price": 130, "closing_cost": OVERHEAD}
