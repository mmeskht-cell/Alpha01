extends RefCounted
## Fictional medicine accounting; no medical advice. Only a GameSession candidate
## can change these rows. Contract schedule and finite seller stock are seed-bound.
const Rules = preload("res://src/domain/value_rules.gd")
const Plan = preload("res://src/domain/gate2_contract_plan.gd")
const ACTIONS: Array = ["rad_reserve", "rad_decline", "rad_extend", "rad_pay", "rad_use", "rad_auto"]
const DURATION: int = 4320

static func seed(state: Dictionary, profile: Dictionary) -> Dictionary:
	if not profile.has("medicine"):
		return {}
	var config: Variant = profile.medicine
	if not Rules.keys(config, ["extension_ids", "stock_ids"]) or not config.extension_ids is Array or not config.stock_ids is Array or not state.wallets.has("marcus"):
		return {}
	var loaded: Dictionary = Plan.load_candidate()
	if not loaded.ok:
		return {}
	var contracts: Dictionary = {}
	var stocks: Dictionary = {}
	var seen: Dictionary = {}
	for id: Variant in config.stock_ids:
		if not Rules.identifier(id) or seen.has(id):
			return {}
		seen[id] = true
	var end: int = profile.day_ids.size() * 1440
	for offer: Dictionary in loaded.plan.contracts:
		var rows: Array = []
		for t: Dictionary in offer.tranches:
			if t.delivery_minute >= end:
				continue
			if not seen.has(t.id):
				return {}
			stocks[t.id] = {"owner": "marcus", "status": "available"}
			rows.append({"id": t.id, "amount": t.amount, "due": t.due_minute, "original_due": t.due_minute, "delivery": t.delivery_minute, "status": "offered", "extended": false})
		if not rows.is_empty():
			contracts[offer.id] = {"offer": offer.offer_minute, "currency": offer.currency, "tranches": rows}
	if stocks.size() != seen.size():
		return {}
	for id: Variant in config.extension_ids:
		if id != "RAD01" or not stocks.has(id) or config.extension_ids.count(id) != 1:
			return {}
	stocks["INITIAL"] = {"owner": "player", "status": "personal"}
	return {"contracts": contracts, "stock": stocks, "effect_until": 2880, "auto": false, "events": []}

static func record(m: Dictionary, kind: String, id: String, minute: int, action: String) -> void:
	m.events.append({"kind": kind, "id": id, "minute": minute, "action": action})

static func use(s: Dictionary, id: String, action: String) -> String:
	var m: Dictionary = s.calendar.medicine
	if not m.stock.has(id) or m.stock[id] != {"owner": "player", "status": "personal"}:
		return "rad_not_owned"
	m.stock[id].status = "consumed"
	m.effect_until = int(s.game_minutes) + DURATION
	record(m, "use", id, int(s.game_minutes), action)
	return ""

static func pay(s: Dictionary, offer: Dictionary, t: Dictionary, action: String, minute: int) -> String:
	if t.status != "reserved" or minute > int(t.due):
		return "rad_payment_status"
	var currency: String = offer.currency
	if s.wallets.player[currency] < t.amount or not Rules.integer(s.wallets.marcus[currency] + t.amount):
		return "rad_funds"
	s.wallets.player[currency] -= t.amount
	s.wallets.marcus[currency] += t.amount
	t.status = "paid"
	record(s.calendar.medicine, "paid", t.id, minute, action)
	return ""

static func deliver(s: Dictionary, t: Dictionary, action: String, minute: int) -> void:
	var m: Dictionary = s.calendar.medicine
	t.status = "delivered"
	m.stock[t.id] = {"owner": "player", "status": "personal"}
	record(m, "delivered", t.id, minute, action)

## Closing is the actual deadline; fixed shop overhead was already charged.
## Only an explicitly reserved tranche is eligible for automatic due payment.
## No early involuntary payment. Workshop time doesn't advance.
static func close(s: Dictionary, action: String) -> void:
	var m: Dictionary = s.calendar.medicine
	var now: int = int(s.game_minutes)
	for offer: Dictionary in m.contracts.values():
		for t: Dictionary in offer.tranches:
			if t.status == "reserved" and t.due == now:
				if not pay(s, offer, t, action, now).is_empty():
					t.status = "missed"
					m.stock[t.id].status = "available"
					record(m, "missed", t.id, now, action)
			elif t.status == "offered" and t.due == now:
				t.status = "expired"
				record(m, "expired", t.id, now, action)
			if t.status == "paid" and t.delivery == now:
				deliver(s, t, action, now)

static func morning(s: Dictionary, action: String) -> void:
	var m: Dictionary = s.calendar.medicine
	if m.auto and m.effect_until <= s.game_minutes:
		var ids: Array = m.stock.keys()
		ids.sort()
		for id: String in ids:
			if m.stock[id] == {"owner": "player", "status": "personal"}:
				use(s, id, action)
				break

static func apply(s: Dictionary, kind: String, p: Dictionary, action: String) -> String:
	if not s.calendar.has("medicine") or s.phase != "shop":
		return "rad_unavailable"
	var m: Dictionary = s.calendar.medicine
	if kind == "rad_auto":
		if not Rules.keys(p, ["enabled"]) or not p.enabled is bool:
			return "rad_payload"
		m.auto = p.enabled
		return ""
	if kind == "rad_use":
		if not Rules.keys(p, ["id"]) or not Rules.identifier(p.id):
			return "rad_payload"
		return use(s, p.id, action)
	if not Rules.keys(p, ["contract", "tranche"]) or not Rules.identifier(p.contract) or not Rules.identifier(p.tranche) or not m.contracts.has(p.contract):
		return "rad_payload"
	var offer: Dictionary = m.contracts[p.contract]
	var now: int = int(s.game_minutes)
	if now < offer.offer:
		return "rad_not_offered"
	for t: Dictionary in offer.tranches:
		if t.id != p.tranche:
			continue
		if now > t.due:
			return "rad_deadline"
		match kind:
			"rad_reserve":
				if t.status != "offered" or m.stock[t.id].status != "available":
					return "rad_reservation"
				t.status = "reserved"
				m.stock[t.id].status = "reserved"
				record(m, "reserved", t.id, now, action)
			"rad_decline":
				if t.status not in ["offered", "reserved"]:
					return "rad_decline"
				t.status = "declined"
				m.stock[t.id].status = "available"
				record(m, "declined", t.id, now, action)
			"rad_extend":
				if t.status != "reserved" or t.extended or t.id not in s.calendar.profile.medicine.extension_ids or now < t.original_due - 600 or t.delivery <= t.due:
					return "rad_extension"
				t.extended = true
				t.due = t.delivery
				record(m, "extended", t.id, now, action)
			"rad_pay":
				return pay(s, offer, t, action, now)
			_:
				return "rad_command"
		return ""
	return "rad_tranche"

static func view(s: Dictionary) -> Dictionary:
	if not s.calendar.has("medicine"):
		return {}
	var m: Dictionary = s.calendar.medicine
	var doses: Array = []
	for id: String in m.stock:
		if m.stock[id] == {"owner": "player", "status": "personal"}:
			doses.append(id)
	var offers: Dictionary = {}
	for id: String in m.contracts:
		if m.contracts[id].offer <= s.game_minutes:
			offers[id] = m.contracts[id].duplicate(true)
	return {"personal_ids": doses, "effect_until": m.effect_until, "remaining_minutes": maxi(0, int(m.effect_until) - int(s.game_minutes)), "suppressed": m.effect_until > s.game_minutes, "auto": m.auto, "contracts": offers}
