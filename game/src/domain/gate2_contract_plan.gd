extends RefCounted
## Gate2-A0 content preflight only. This is not a mutable economy, a receipt,
## a stock reservation, or a grant of medication. No game state is written.
const Rules = preload("res://src/domain/value_rules.gd")
const Clock = preload("res://src/domain/business_clock.gd")
const Opening = preload("res://src/domain/gate1_opening.gd")
const PLAN_PATH: String = "res://data/campaign/gate2_a/rad1_plan.json"
const EFFECT_MINUTES: int = 4320
const USD_SWITCH: int = 21 * 1440

static func fail(code: String) -> Dictionary:
	return {"ok": false, "error": code}

static func load_candidate() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLAN_PATH))
	var checked: Dictionary = audit(parsed)
	if not checked.ok:
		return checked
	return {"ok": true, "plan": Rules.normalized(parsed), "summary": checked.summary}

static func audit(raw: Variant) -> Dictionary:
	if not Rules.keys(raw, ["version", "kind", "initial_effect_until", "initial_doses", "duration", "contracts"]):
		return fail("plan_shape")
	var p: Dictionary = Rules.normalized(raw)
	if p.version != 1 or p.kind != "gate2a_candidate" or p.initial_effect_until != 2880 or p.initial_doses != 1 or p.duration != EFFECT_MINUTES:
		return fail("initial_terms")
	if not p.contracts is Array or p.contracts.size() != 7:
		return fail("contract_count")
	var seen: Dictionary = {}
	var totals: Dictionary = {"VKC": 0, "USD": 0}
	var next_use: int = int(p.initial_effect_until) + EFFECT_MINUTES
	var count: int = 0
	var previous_offer: int = -1
	for c: Variant in p.contracts:
		if not Rules.keys(c, ["id", "offer_minute", "currency", "tranches"]):
			return fail("contract_shape")
		if not Rules.identifier(c.id) or seen.has(c.id) or not Rules.integer(c.offer_minute, 0, Clock.CAMPAIGN_END - 1):
			return fail("contract_identity")
		if int(c.offer_minute) <= previous_offer:
			return fail("offer_order")
		previous_offer = int(c.offer_minute)
		seen[c.id] = true
		if c.currency != ("USD" if c.offer_minute >= USD_SWITCH else "VKC"):
			return fail("currency_epoch")
		if not c.tranches is Array or c.tranches.is_empty() or c.tranches.size() > 3:
			return fail("tranche_count")
		for t: Variant in c.tranches:
			if not Rules.keys(t, ["id", "amount", "due_minute", "delivery_minute", "use_minute"]):
				return fail("tranche_shape")
			if not Rules.identifier(t.id) or seen.has(t.id) or not Rules.integer(t.amount, 1, 100000):
				return fail("tranche_identity_or_price")
			seen[t.id] = true
			if not Rules.integer(t.due_minute, int(c.offer_minute), Clock.CAMPAIGN_END - 1) or not Rules.integer(t.delivery_minute, int(t.due_minute), Clock.CAMPAIGN_END - 1) or not Rules.integer(t.use_minute, int(t.delivery_minute), Clock.CAMPAIGN_END - 1):
				return fail("tranche_time")
			if int(t.due_minute) % Clock.DAY_MINUTES != Clock.BUSINESS_MINUTES or int(t.delivery_minute) % Clock.DAY_MINUTES != Clock.BUSINESS_MINUTES:
				return fail("close_boundary")
			if t.use_minute != next_use or t.delivery_minute >= next_use:
				return fail("coverage_gap_or_overlap")
			if count == 0 and (c.offer_minute != 0 or c.currency != Opening.TERMS.currency or t.amount != Opening.TERMS.amount or t.due_minute != Opening.TERMS.due_minute or t.delivery_minute != Opening.TERMS.delivery_minute or c.tranches.size() != 1):
				return fail("first_contract_changed")
			totals[c.currency] += int(t.amount)
			count += 1
			next_use += EFFECT_MINUTES
	if count != 13 or next_use < Clock.CAMPAIGN_END or next_use - EFFECT_MINUTES >= Clock.CAMPAIGN_END:
		return fail("coverage_count")
	return {"ok": true, "summary": {"contracts": p.contracts.size(), "additional_doses": count, "totals": totals, "effect_until": next_use, "effect_remaining_at_end": next_use - Clock.CAMPAIGN_END}}
