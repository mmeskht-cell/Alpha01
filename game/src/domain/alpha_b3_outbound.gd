extends RefCounted
## First-week offers are authored agreements. A caller can submit only their ID.
## Populate only with signed actor, days, currency, advance, cancellation refund
## and dated external evidence. Goods remain with their owner until counter trade.
const Rules = preload("res://src/domain/value_rules.gd")
const CATALOG: Dictionary = {}
const WEEK_CATALOG = {"tool_search":{"actor_id":"G01","currency":"VKC","offer_day":1,
	"advance":10,"cancel_refund":10,"public_terms_key":"week.dispatch","public_cancel_key":"week.cancel",
	"events":{"3":{"status":"delayed"},"4":{"status":"goods_offered","visit_id":"tool_buy","item_id":"TL04"}}}}

static func catalog(a: Dictionary) -> Dictionary:
	return WEEK_CATALOG if a.profile.get("week_proposal") == "first_week_proposal_1" else CATALOG

static func apply(state: Dictionary, id: String, terms: Dictionary, command: Dictionary) -> String:
	var a: Dictionary = state.alpha_shop
	var rows: Dictionary = a.get("outbound", {})
	var actor: String = terms.actor_id
	var currency: String = terms.currency
	if currency not in ["VKC", "USD"] or not state.wallets.has(actor) or actor == "player":
		return "salvage_terms"
	var payer: String = "player"
	var receiver: String = actor
	var amount: int
	var status: String
	if command.type == "alpha_salvage_dispatch":
		if rows.has(id) or a.day != terms.offer_day or rows.size() >= 128:
			return "salvage_unavailable"
		for other: Dictionary in rows.values():
			if other.actor_id == actor and other.status in ["dispatched", "delayed", "unreachable", "goods_offered"]:
				return "salvage_busy"
		if not Rules.integer(terms.advance, 1, Rules.LIMIT):
			return "salvage_terms"
		amount = terms.advance
		status = "dispatched"
	else:
		if not rows.has(id) or rows[id].status not in ["dispatched", "delayed"] or not terms.has("cancel_refund") or not Rules.integer(terms.cancel_refund, 0, terms.advance):
			return "salvage_cancel_terms"
		payer = actor
		receiver = "player"
		amount = terms.cancel_refund
		status = "cancelled"
	if state.wallets[payer][currency] < amount or not Rules.integer(int(state.wallets[receiver][currency]) + amount):
		return "salvage_funds"
	state.wallets[payer][currency] -= amount
	state.wallets[receiver][currency] += amount
	if not rows.has(id):
		rows[id] = {"actor_id": actor, "payments": []}
	rows[id].status = status
	rows[id].payments.append({"action_id": command.action_id, "from": payer, "to": receiver,
		"currency": currency, "amount": amount, "day": a.day})
	a.outbound = rows
	return ""

static func morning(state: Dictionary) -> void:
	var a: Dictionary = state.alpha_shop
	for id: String in a.get("outbound", {}):
		var row: Dictionary = a.outbound[id]
		var policies: Dictionary = catalog(a)
		if not policies.has(id):
			continue
		if row.status not in ["dispatched", "delayed", "unreachable"]:
			continue
		var evidence: Dictionary = policies[id].events.get(str(a.day), {})
		if evidence.get("status") == "goods_offered" and int(state.wallets[row.actor_id].VKC) < 60:
			evidence = {"status":"empty"}
		apply_evidence(state, row, evidence)
		if evidence.get("status") == "goods_offered" and row.status != "goods_offered":
			row.status = "empty"

static func apply_evidence(state: Dictionary, row: Dictionary, evidence: Dictionary) -> void:
	if row.status not in ["dispatched", "delayed", "unreachable"]:
		return
	if evidence.is_empty():
		return
	if evidence.status in ["empty", "delayed", "unreachable"]:
		row.status = evidence.status
	elif evidence.status == "goods_offered":
		var visit: Dictionary = state.visits.get(evidence.visit_id, {})
		var item: Dictionary = state.items.get(evidence.item_id, {})
		var scheduled: bool = false
		var a: Dictionary = state.alpha_shop
		for slot: Dictionary in a.profile.days[int(a.day) - 1]:
			if slot.id == evidence.visit_id and slot.actor_id == row.actor_id:
				scheduled = true
				break
		if scheduled and visit.get("seller") == row.actor_id and visit.buyer == "player" and not visit.scope.completed and visit.prices.has(evidence.item_id) and item.get("owner_id") == row.actor_id and item.custodian_id == row.actor_id and item.status == "stock" and not item.protected and item.reservation_id.is_empty() and item.parent_id.is_empty():
			row.status = "goods_offered"
			row.visit_id = evidence.visit_id
			row.item_id = evidence.item_id
