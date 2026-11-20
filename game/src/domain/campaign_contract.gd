extends RefCounted
## A1c3: ordinary dated external supply obligations, not personal inventory.
## All changes on GameSession candidate. No health, consumption, or recurring charge.
const Rules = preload("res://src/domain/value_rules.gd")
const Clock = preload("res://src/domain/business_clock.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const ACTIONS: Array = ["calendar_accept_contract", "calendar_decline_contract", "calendar_extend_contract", "calendar_pay_contract"]

static func seed(s: Dictionary, profile: Dictionary) -> Dictionary:
	var configured: Variant = profile.get("contracts")
	var facts: Variant = profile.get("story_rules")
	if not configured is Dictionary or configured.size() > 128 or not facts is Dictionary or facts.size() > 128:
		return {}
	var limit: int = profile.day_ids.size()
	var result: Dictionary = {"rows": {}, "supplies": {}, "settlements": [], "facts": {}}
	for id: Variant in configured:
		var t: Variant = configured[id]
		if not Rules.identifier(id) or not Rules.keys(t, ["supplier", "supply_id", "offer_day", "due_day", "delivery_day", "extension_day", "price", "label_key"]):
			return {}
		if not Rules.identifier(t.supplier) or t.supplier == "player" or not s.wallets.has(t.supplier) or not Rules.identifier(t.supply_id) or result.supplies.has(t.supply_id) or s.items.has(t.supply_id) or s.tombstones.has(t.supply_id) or not Rules.identifier(t.label_key):
			return {}
		if not Rules.integer(t.offer_day, 1, limit) or not Rules.integer(t.due_day, int(t.offer_day), limit) or not Rules.integer(t.delivery_day, int(t.due_day), limit) or not Rules.integer(t.extension_day, 0, limit):
			return {}
		if t.extension_day != 0 and (t.extension_day <= t.due_day or t.extension_day > t.delivery_day):
			return {}
		if not Objects.money(t.price, false) or (t.price.VKC == 0 and t.price.USD == 0):
			return {}
		result.rows[id] = {"status":"offered", "due_day":t.due_day, "extended":false, "accept_action":"", "pay_action":"", "delivery_action":"", "end_action":""}
		result.supplies[t.supply_id] = {"contract":id, "supplier":t.supplier, "status":"available"}
	for id: Variant in facts:
		var f: Variant = facts[id]
		if not Rules.identifier(id) or not Rules.keys(f, ["day", "source", "source_id", "outcome", "text_key"]) or not Rules.integer(f.day, 1, limit) or not Rules.identifier(f.source_id) or not Rules.identifier(f.text_key):
			return {}
		if f.source == "contract":
			if not configured.has(f.source_id) or f.outcome not in ["delivered", "defaulted", "declined", "missed"] or f.day <= configured[f.source_id].offer_day:
				return {}
		elif f.source == "trade":
			if not s.visits.has(f.source_id) or f.outcome != "traded" or (int(f.day) - 1) * Clock.DAY_MINUTES <= int(s.visits[f.source_id].expires):
				return {}
		else:
			return {}
	return result

static func day(s: Dictionary) -> int:
	return Clock.day_index(int(s.game_minutes))

static func terms(s: Dictionary, id: String) -> Dictionary:
	return s.calendar.profile.contracts[id]

static func record(s: Dictionary, id: String, action: String, kind: String, minute: int, amount: Dictionary) -> void:
	s.calendar.contracts.settlements.append({"contract_id":id, "action_id":action, "kind":kind, "minute":minute, "amount":amount.duplicate(true), "supply_id":terms(s,id).supply_id})

static func can_pay(s: Dictionary, t: Dictionary) -> bool:
	for currency: String in ["VKC","USD"]:
		if s.wallets.player[currency] < t.price[currency] or not Rules.integer(s.wallets[t.supplier][currency] + t.price[currency]):
			return false
	return true

static func pay(s: Dictionary, id: String, action: String) -> bool:
	var t: Dictionary = terms(s,id)
	var row: Dictionary = s.calendar.contracts.rows[id]
	var supply: Dictionary = s.calendar.contracts.supplies[t.supply_id]
	if row.status != "reserved" or supply.status != "reserved" or not can_pay(s,t):
		return false
	for currency: String in ["VKC","USD"]:
		s.wallets.player[currency] -= t.price[currency]
		s.wallets[t.supplier][currency] += t.price[currency]
	row.status = "paid"
	row.pay_action = action
	supply.status = "paid"
	record(s,id,action,"payment",int(s.game_minutes),t.price)
	return true

static func apply(s: Dictionary, kind: String, p: Dictionary, action: String) -> String:
	if not s.calendar.has("contracts") or not Clock.business_at(int(s.game_minutes),s.phase) or not Rules.keys(p,["contract_id"]) or not Rules.identifier(p.contract_id) or not s.calendar.contracts.rows.has(p.contract_id):
		return "contract_permission"
	var id: String = p.contract_id
	var t: Dictionary = terms(s,id)
	var row: Dictionary = s.calendar.contracts.rows[id]
	var supply: Dictionary = s.calendar.contracts.supplies[t.supply_id]
	match kind:
		"calendar_accept_contract", "calendar_decline_contract":
			if row.status != "offered" or day(s) != t.offer_day or supply.status != "available" or not Clock.business_at(int(s.game_minutes),s.phase,false):
				return "contract_offer"
			if kind == "calendar_accept_contract":
				row.status = "reserved"
				row.accept_action = action
				supply.status = "reserved"
			else:
				row.status = "declined"
				row.end_action = action
		"calendar_extend_contract":
			if row.status != "reserved" or row.extended or t.extension_day == 0 or day(s) != row.due_day:
				return "contract_extension"
			row.due_day = t.extension_day
			row.extended = true
		"calendar_pay_contract":
			if row.status != "reserved" or day(s) > row.due_day or not pay(s,id,action):
				return "contract_payment"
		_:
			return "contract_command"
	return ""

## Legacy empty close payload is retained for deterministic historical replay.
## Explicit close choices are checked against exactly the due reserved contracts.
static func due_ids(s:Dictionary)->Array:
	var ids:Array=[]
	for id:String in s.calendar.get("contracts",{}).get("rows",{}):
		var row:Dictionary=s.calendar.contracts.rows[id]
		if row.status=="reserved" and row.due_day==day(s):
			ids.append(id)
	ids.sort()
	return ids

static func close_choices_valid(s:Dictionary,choices:Variant)->bool:
	if not choices is Dictionary:
		return false
	var ids:Array=due_ids(s)
	if choices.size()!=ids.size():
		return false
	var available:Dictionary=s.wallets.player.duplicate()
	available.VKC=maxi(0,int(available.VKC)-15)
	for id:String in ids:
		if not choices.has(id) or choices[id] not in ["pay","default"]:
			return false
		if choices[id]=="pay":
			for currency:String in ["VKC","USD"]:
				available[currency]-=terms(s,id).price[currency]
				if available[currency]<0:
					return false
	return true

static func close(s: Dictionary, action: String, choices:Dictionary={},explicit:bool=false) -> String:
	if not s.calendar.has("contracts"):
		return ""
	var ids: Array = s.calendar.contracts.rows.keys()
	ids.sort()
	for id: String in ids:
		var t: Dictionary = terms(s,id)
		var row: Dictionary = s.calendar.contracts.rows[id]
		var supply: Dictionary = s.calendar.contracts.supplies[t.supply_id]
		if row.status == "offered" and day(s) == t.offer_day:
			row.status = "missed"
			row.end_action = action
		if row.status == "reserved" and day(s) == row.due_day:
			var settled:bool=false
			if not explicit or choices.get(id)=="pay":
				settled=pay(s,id,action)
				if explicit and not settled:
					return "contract_payment"
			if not settled:
				row.status = "defaulted"
				row.end_action = action
				supply.status = "available"
		if row.status == "paid" and day(s) == t.delivery_day and supply.status == "paid":
			row.status = "delivered"
			row.delivery_action = action
			supply.status = "delivered"
			record(s,id,action,"delivery",int(s.game_minutes),{"VKC":0,"USD":0})
	return ""

## Authored facts are derived from real outcomes; never a UI assertion.
## One-shot day gate; no D8/D43 publication beyond the selected profile.
static func morning(s: Dictionary, action: String) -> void:
	if not s.calendar.has("contracts"):
		return
	var rules: Dictionary = s.calendar.profile.story_rules
	for id: String in rules:
		var f: Dictionary = rules[id]
		if f.day != day(s) or s.calendar.contracts.facts.has(id):
			continue
		var cause: String = ""
		if f.source == "contract":
			var row: Dictionary = s.calendar.contracts.rows[f.source_id]
			if row.status == f.outcome:
				cause = row.delivery_action if row.status == "delivered" else row.end_action
		else:
			for e: Dictionary in s.ledger:
				if e.visit_id == f.source_id:
					cause = e.event_id
					break
		if not cause.is_empty():
			s.calendar.contracts.facts[id] = {"id":id,"day":f.day,"text_key":f.text_key,"source":f.source,"source_id":f.source_id,"cause_action":cause,"reveal_action":action}

static func view(s: Dictionary) -> Dictionary:
	var result: Dictionary = {"contracts":{}, "settlements":[], "facts":{}}
	if not s.calendar.has("contracts"):
		return result
	for id: String in s.calendar.contracts.rows:
		var t: Dictionary = terms(s,id)
		if day(s) < t.offer_day:
			continue
		var row: Dictionary = s.calendar.contracts.rows[id]
		result.contracts[id] = {"supplier":t.supplier,"label_key":t.label_key,"price":t.price.duplicate(true),"due_day":row.due_day,"delivery_day":t.delivery_day,"status":row.status,"extended":row.extended,"can_extend":row.status == "reserved" and day(s) == row.due_day and t.extension_day != 0 and not row.extended and Clock.business_at(int(s.game_minutes),s.phase)}
	result.settlements = s.calendar.contracts.settlements.duplicate(true)
	result.facts = s.calendar.contracts.facts.duplicate(true)
	return result
