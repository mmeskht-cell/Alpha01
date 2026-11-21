extends RefCounted
## Alpha B1 date-only contract authority; terms are copied from the canonical
## finite demo contract, never inferred from the visitor's dialogue or UI.
## Financial movements use the same candidate GameSession, with a dedicated
## contract settlement trail like campaign_contract.gd. No phantom item mint.
const Rules = preload("res://src/domain/value_rules.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const ACTIONS: Array = ["alpha_contract_accept", "alpha_contract_decline", "alpha_contract_pay", "alpha_contract_extend"]

static func profile_valid(profile: Dictionary, source: Dictionary) -> bool:
	if not profile.get("contracts") is Dictionary or not profile.get("story_rules") is Dictionary:
		return false
	if profile.contracts.is_empty() or profile.contracts.size() > 128 or profile.story_rules.size() > 128:
		return false
	var supplies: Dictionary = {}
	for id: String in profile.contracts:
		var t: Variant = profile.contracts[id]
		if not Rules.identifier(id) or not Rules.keys(t, ["supplier", "supply_id", "offer_day", "due_day", "delivery_day", "extension_day", "price", "label_key"]):
			return false
		if not Rules.identifier(t.supplier) or not source.wallets.has(t.supplier) or t.supplier == "player" or not Rules.identifier(t.supply_id) or supplies.has(t.supply_id) or source.items.has(t.supply_id) or source.tombstones.has(t.supply_id) or not Rules.identifier(t.label_key):
			return false
		if not Rules.integer(t.offer_day, 1, profile.days.size()) or not Rules.integer(t.due_day, int(t.offer_day), profile.days.size()) or not Rules.integer(t.delivery_day, int(t.due_day), profile.days.size()) or not Rules.integer(t.extension_day, 0, profile.days.size()):
			return false
		if int(t.extension_day) != 0 and (int(t.extension_day) <= int(t.due_day) or int(t.extension_day) > int(t.delivery_day)):
			return false
		if not Objects.money(t.price, false) or int(t.price.VKC) + int(t.price.USD) <= 0:
			return false
		var supplier_offered: bool = false
		for row: Dictionary in profile.days[int(t.offer_day) - 1]:
			if row.actor_id == t.supplier and row.kind == "named":
				supplier_offered = true
		if not supplier_offered:
			return false
		supplies[t.supply_id] = true
	for id: String in profile.story_rules:
		var rule: Variant = profile.story_rules[id]
		if not Rules.identifier(id) or not Rules.keys(rule, ["day", "source", "source_id", "outcome", "text_key"]) or not Rules.integer(rule.day, 1, profile.days.size()) or not Rules.identifier(rule.source_id) or not Rules.identifier(rule.text_key):
			return false
		if rule.source == "contract":
			if not profile.contracts.has(rule.source_id) or rule.outcome not in ["delivered", "defaulted", "declined", "missed"] or rule.day <= profile.contracts[rule.source_id].offer_day:
				return false
		elif rule.source == "trade":
			if rule.outcome != "traded" or not source.visits.has(rule.source_id) or int(rule.day) <= int(source.visits[rule.source_id].expires / 1440) + 1:
				return false
		else:
			return false
	return true

static func seed(profile: Dictionary) -> Dictionary:
	var rows: Dictionary = {}
	var supplies: Dictionary = {}
	for id: String in profile.contracts:
		var t: Dictionary = profile.contracts[id]
		rows[id] = {"status": "unoffered", "due_day": t.due_day, "extended": false, "offer_action": "", "accept_action": "", "pay_action": "", "delivery_action": "", "end_action": ""}
		supplies[t.supply_id] = {"contract": id, "supplier": t.supplier, "status": "available"}
	return {"rows": rows, "supplies": supplies, "settlements": [], "facts": {}}

static func at_counter(a: Dictionary, actor: String) -> bool:
	if a.phase != "CUSTOMER_ACTIVE" or a.active.is_empty():
		return false
	for row: Dictionary in a.profile.days[int(a.day) - 1]:
		if row.id == a.active and row.actor_id == actor:
			return true
	return false

static func on_entry(s: Dictionary, action: String) -> void:
	var a: Dictionary = s.alpha_shop
	for id: String in a.profile.contracts:
		var t: Dictionary = a.profile.contracts[id]
		var row: Dictionary = a.contracts.rows[id]
		if row.status == "unoffered" and a.day == t.offer_day and at_counter(a, t.supplier):
			row.status = "offered"
			row.offer_action = action

static func on_visit_end(s: Dictionary, action: String) -> void:
	var a: Dictionary = s.alpha_shop
	for id: String in a.profile.contracts:
		var t: Dictionary = a.profile.contracts[id]
		var row: Dictionary = a.contracts.rows[id]
		if row.status == "offered" and at_counter(a, t.supplier):
			row.status = "missed"
			row.end_action = action

static func on_close(s: Dictionary, action: String) -> void:
	var a: Dictionary = s.alpha_shop
	for id: String in a.profile.contracts:
		var t: Dictionary = a.profile.contracts[id]
		var row: Dictionary = a.contracts.rows[id]
		if a.day == t.offer_day and row.status in ["unoffered", "offered"]:
			row.status = "missed"
			row.end_action = action

static func funded(s: Dictionary, t: Dictionary) -> bool:
	for currency: String in ["VKC", "USD"]:
		if s.wallets.player[currency] < t.price[currency] or not Rules.integer(s.wallets[t.supplier][currency] + t.price[currency]):
			return false
	return true

static func apply(s: Dictionary, command: Dictionary) -> String:
	var a: Dictionary = s.alpha_shop
	var p: Dictionary = command.payload
	if not Rules.keys(p, ["contract_id"]) or not Rules.identifier(p.contract_id) or not a.profile.contracts.has(p.contract_id):
		return "alpha_contract_shape"
	var id: String = p.contract_id
	var t: Dictionary = a.profile.contracts[id]
	var row: Dictionary = a.contracts.rows[id]
	var supply: Dictionary = a.contracts.supplies[t.supply_id]
	match command.type:
		"alpha_contract_accept", "alpha_contract_decline":
			if row.status != "offered" or a.day != t.offer_day or not at_counter(a, t.supplier) or supply.status != "available":
				return "alpha_contract_offer"
			if command.type == "alpha_contract_accept":
				row.status = "reserved"
				row.accept_action = command.action_id
				supply.status = "reserved"
			else:
				row.status = "declined"
				row.end_action = command.action_id
		"alpha_contract_extend":
			if a.phase != "CLOSE_SETTLE" or row.status != "reserved" or row.extended or a.day != row.due_day or t.extension_day == 0:
				return "alpha_contract_extension"
			row.due_day = t.extension_day
			row.extended = true
		"alpha_contract_pay":
			if a.phase != "CLOSE_SETTLE" or row.status != "reserved" or a.day > row.due_day or supply.status != "reserved" or not funded(s, t):
				return "alpha_contract_payment"
			for currency: String in ["VKC", "USD"]:
				s.wallets.player[currency] -= t.price[currency]
				s.wallets[t.supplier][currency] += t.price[currency]
			row.status = "paid"
			row.pay_action = command.action_id
			supply.status = "paid"
			a.contracts.settlements.append({"contract_id": id, "action_id": command.action_id, "kind": "payment", "day": a.day, "amount": t.price.duplicate(true), "supply_id": t.supply_id})
		_:
			return "alpha_contract_command"
	return ""

static func on_settle(s: Dictionary, action: String) -> void:
	var a: Dictionary = s.alpha_shop
	for id: String in a.profile.contracts:
		var t: Dictionary = a.profile.contracts[id]
		var row: Dictionary = a.contracts.rows[id]
		var supply: Dictionary = a.contracts.supplies[t.supply_id]
		if row.status == "reserved" and row.due_day == a.day:
			row.status = "defaulted"
			row.end_action = action
			supply.status = "available"
		if row.status == "paid" and t.delivery_day == a.day and supply.status == "paid":
			row.status = "delivered"
			row.delivery_action = action
			supply.status = "delivered"
			a.contracts.settlements.append({"contract_id": id, "action_id": action, "kind": "delivery", "day": a.day, "amount": {"VKC": 0, "USD": 0}, "supply_id": t.supply_id})

static func on_morning(s: Dictionary, action: String) -> void:
	var a: Dictionary = s.alpha_shop
	for id: String in a.profile.story_rules:
		var rule: Dictionary = a.profile.story_rules[id]
		if rule.day != a.day or a.contracts.facts.has(id):
			continue
		var cause: String = ""
		if rule.source == "contract":
			var row: Dictionary = a.contracts.rows[rule.source_id]
			if row.status == rule.outcome:
				cause = row.delivery_action if row.status == "delivered" else row.end_action
		else:
			for e: Dictionary in s.ledger:
				if e.visit_id == rule.source_id:
					cause = e.event_id
					break
		if not cause.is_empty():
			a.contracts.facts[id] = {"id": id, "day": rule.day, "text_key": rule.text_key, "source": rule.source, "source_id": rule.source_id, "cause_action": cause, "reveal_action": action}

static func view(s: Dictionary) -> Dictionary:
	var a: Dictionary = s.alpha_shop
	var result: Dictionary = {"contracts": {}, "news": []}
	if not a.has("contracts"):
		return result
	for id: String in a.profile.contracts:
		var t: Dictionary = a.profile.contracts[id]
		var row: Dictionary = a.contracts.rows[id]
		if row.status == "unoffered":
			continue
		result.contracts[id] = {
			"supplier": t.supplier, "price": t.price.duplicate(true),
			"due_day": row.due_day, "delivery_day": t.delivery_day,
			"status": row.status, "extended": row.extended,
			"can_accept": row.status == "offered" and at_counter(a, t.supplier),
			"can_pay": a.phase == "CLOSE_SETTLE" and row.status == "reserved" and a.day <= row.due_day and funded(s, t),
			"can_extend": a.phase == "CLOSE_SETTLE" and row.status == "reserved" and a.day == row.due_day and not row.extended and t.extension_day != 0
		}
	for id: String in a.contracts.facts:
		result.news.append(a.contracts.facts[id].duplicate(true))
	return result
