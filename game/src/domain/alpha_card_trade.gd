extends RefCounted
## B2 bounded, opt-in one-counter appraisal and offers.
## Actual readings are looked up from existing specimen/provenance-bound
## inspection data. The UI never receives unread values or NPC thresholds.
## Negotiation amounts in alpha_b2/cards_pilot_1.json are demo-only terms,
## not a canonical 7-day economy or an automatic per-card price formula.
const Rules = preload("res://src/domain/value_rules.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const Commission = preload("res://src/domain/alpha_commission.gd")
const CONFIG_PATH: String = "res://data/alpha_b2/cards_pilot_1.json"
const MAX_OFFERS: int = 3
const MAX_OBSERVATIONS: int = 8
const ACTIONS: Array = ["alpha_inspect", "alpha_card_toggle", "alpha_price_offer"]

static func config() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not data is Dictionary or not Rules.keys(data, ["version", "profile_id", "specimen_sources", "negotiation_terms"]) or data.version != 1 or data.profile_id != "alpha_b2_cards_pilot_1":
		return {}
	if not data.specimen_sources is Array or not data.negotiation_terms is Dictionary:
		return {}
	return data

static func profile_valid(data: Dictionary, state: Dictionary) -> bool:
	var c: Dictionary = config()
	if c.is_empty() or data.get("appraisal_id") != c.profile_id or not data.has("days"):
		return false
	for id: String in c.negotiation_terms:
		var term: Variant = c.negotiation_terms[id]
		if not state.visits.has(id) or not Rules.keys(term, ["improved_amount", "required_slot"]) or not Rules.integer(term.improved_amount, 1) or not Rules.identifier(term.required_slot):
			return false
		var price: Dictionary = state.visits[id].prices.values()[0]
		var original: int = int(price.VKC) if int(price.VKC) > 0 else int(price.USD)
		var actor_seller: bool = state.visits[id].buyer == "player"
		if (actor_seller and int(term.improved_amount) >= original) or (not actor_seller and int(term.improved_amount) <= original):
			return false
	for src: Variant in c.specimen_sources:
		if not Rules.keys(src, ["def_id", "path"]) or not Rules.identifier(src.def_id) or not src.path is String or not src.path.begins_with("res://data/campaign/gate2/"):
			return false
	return true

static func seed() -> Dictionary:
	return {"visits": {}}

static func _visit_context(state: Dictionary) -> Dictionary:
	var a: Dictionary = state.alpha_shop
	if a.profile.get("content_version") not in ["b2-cards-pilot-1","b2-cards-commission-1","b2-cards-commission-named-1","b2-cards-commission-service-1","b2-cards-commission-service-recovery-2"] or a.phase != "CUSTOMER_ACTIVE" or not state.visits.has(a.active):
		return {}
	if a.has("commissions") and Commission.is_return_visit(a.active, str(a.profile.get("commission_profile_id", ""))):
		return {}
	var visit: Dictionary = state.visits[a.active]
	if visit.scope.completed or visit.prices.size() != 1 or (visit.seller != "player" and not visit.allow_inspection):
		return {}
	var item_id: String = str(visit.prices.keys()[0])
	if not state.items.has(item_id):
		return {}
	if visit.seller == "player" and (item_id not in a.displayed or state.items[item_id].inventory != "storefront_grid"):
		return {}
	return {"visit_id": a.active, "item_id": item_id, "item": state.items[item_id], "visit": visit}

static func _tool_rows(state: Dictionary, item_id: String) -> Array:
	var c: Dictionary = config()
	if c.is_empty() or not state.items.has(item_id):
		return []
	var item: Dictionary = state.items[item_id]
	var options: Array = [{"id":"identity","text_key":"b2.inspect.identity","kind":"fact"}]
	for src: Dictionary in c.specimen_sources:
		if src.def_id != item.def_id:
			continue
		var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(src.path))
		if not document is Dictionary or document.get("version") != 1 or not document.get("profiles") is Dictionary or not document.profiles.has(item.def_id) or not document.get("specimens") is Dictionary:
			continue
		var specimen: Dictionary = document.specimens.get(item_id,{})
		if specimen.get("def_id") != item.def_id or specimen.get("provenance") != item.provenance_id or not specimen.get("readings") is Dictionary:
			continue
		for tool: Variant in document.profiles[item.def_id].get("tools", []):
			if not tool is Dictionary or not Rules.identifier(tool.get("id")) or not specimen.readings.has(tool.id):
				continue
			options.append({"id":tool.id,"text_key":"b2.inspect." + str(tool.id),"kind":"fact"})
	return options

static func _reading(state: Dictionary, item_id: String, slot: String) -> Dictionary:
	var item: Dictionary = state.items[item_id]
	if slot == "identity":
		return {"slot": slot, "value": item.def_id, "kind": "fact", "version": item.field_versions.duplicate(true)}
	for src: Dictionary in config().get("specimen_sources", []):
		if src.def_id != item.def_id:
			continue
		var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(src.path))
		if not document is Dictionary or document.get("version") != 1:
			continue
		var specimen: Dictionary = document.get("specimens",{}).get(item_id,{})
		if specimen.get("def_id") != item.def_id or specimen.get("provenance") != item.provenance_id or not specimen.get("readings") is Dictionary or not specimen.readings.has(slot):
			continue
		for tool: Dictionary in document.profiles[item.def_id].get("tools", []):
			if tool.id == slot:
				return {"slot":slot,"value":Rules.normalized(specimen.readings[slot]),"kind":"fact","version":item.field_versions.duplicate(true)}
	return {}

static func _row(state: Dictionary, context: Dictionary) -> Dictionary:
	var a: Dictionary = state.alpha_shop
	return a.appraisal.visits.get(context.visit_id, {"item_id": context.item_id,"observed":{},"selected":[],"offers":[],"accepted":{}}).duplicate(true)

static func apply(state: Dictionary, command: Dictionary) -> String:
	var context: Dictionary = _visit_context(state)
	if context.is_empty():
		return "alpha_appraisal_context"
	var p: Dictionary = command.payload
	var a: Dictionary = state.alpha_shop
	var row: Dictionary = _row(state,context)
	if not row.accepted.is_empty():
		return "alpha_appraisal_already_accepted"
	match command.type:
		"alpha_inspect":
			if not Rules.keys(p,["slot"]) or not Rules.identifier(p.slot):
				return "alpha_inspect_shape"
			if row.observed.has(p.slot) or row.observed.size() >= MAX_OBSERVATIONS:
				return "alpha_inspect_duplicate"
			var available: bool = false
			for option: Dictionary in _tool_rows(state,context.item_id):
				if option.id == p.slot:
					available = true
			if not available:
				return "alpha_inspect_permission"
			var observed: Dictionary = _reading(state,context.item_id,p.slot)
			if observed.is_empty():
				return "alpha_inspect_unknown"
			row.observed[p.slot] = observed
		"alpha_card_toggle":
			if not Rules.keys(p,["slot","selected"]) or not Rules.identifier(p.slot) or not p.selected is bool or not row.observed.has(p.slot):
				return "alpha_card_shape"
			var included: bool = p.slot in row.selected
			if included == p.selected:
				return "alpha_card_unchanged"
			if p.selected:
				row.selected.append(p.slot)
			else:
				row.selected.erase(p.slot)
		"alpha_price_offer":
			if not Rules.keys(p,["amount"]) or not Rules.integer(p.amount,1) or row.offers.size() >= MAX_OFFERS:
				return "alpha_offer_shape_or_limit"
			for old: Dictionary in row.offers:
				if old.amount == p.amount and old.selected == row.selected:
					return "alpha_offer_duplicate"
			var visit: Dictionary = context.visit
			var base: Dictionary = visit.prices[context.item_id]
			var currency: String = "VKC" if int(base.VKC)>0 and int(base.USD)==0 else ("USD" if int(base.USD)>0 and int(base.VKC)==0 else "")
			if currency.is_empty():
				return "alpha_offer_currency"
			var original: int = int(base[currency])
			var accepted: bool = p.amount == original
			var approved: Dictionary = config().negotiation_terms.get(context.visit_id,{})
			if not approved.is_empty() and p.amount == approved.improved_amount and approved.required_slot in row.selected:
				accepted = true
			# An agreement is not valid if its actual buyer cannot afford it.
			# _transfer separately revalidates the wallet on final settlement.
			if accepted and state.wallets[visit.buyer][currency] < p.amount:
				accepted = false
			var revealed: Array = []
			for slot: String in row.selected:
				if row.observed.has(slot):
					revealed.append(row.observed[slot].duplicate(true))
			var outcome: Dictionary = {
				"action_id": command.action_id, "amount": p.amount, "currency": currency,
				"selected": row.selected.duplicate(), "revealed": revealed,
				"response": "accepted" if accepted else "declined"
			}
			row.offers.append(outcome)
			if accepted:
				row.accepted = {"amount": p.amount,"currency": currency,"action_id":command.action_id}
				# Only the immutable-seed-replayed GameSession candidate may alter
				# these live visit terms; _trade then uses the original transfer,
				# ledger, ownership, basis and wallet guards.
				state.visits[context.visit_id].prices[context.item_id][currency] = p.amount
		_:
			return "alpha_appraisal_action"
	a.appraisal.visits[context.visit_id] = row
	return ""

static func trade_gate(state: Dictionary, payload: Dictionary) -> String:
	var context: Dictionary = _visit_context(state)
	if context.is_empty():
		return "alpha_appraisal_context"
	var row: Dictionary = _row(state,context)
	var accepted: Dictionary = row.accepted
	if accepted.is_empty() or payload.get("amount") != accepted.amount or payload.get("currency") != accepted.currency:
		return "alpha_offer_not_accepted"
	return ""

static func view(state: Dictionary) -> Dictionary:
	var context: Dictionary = _visit_context(state)
	if context.is_empty():
		return {}
	var row: Dictionary = _row(state,context)
	var options: Array = []
	for tool: Dictionary in _tool_rows(state,context.item_id):
		if not row.observed.has(tool.id):
			options.append(tool)
	var cards: Array = []
	var previously_shared: Array = []
	for offer: Dictionary in row.offers:
		for fact: Dictionary in offer.revealed:
			var public_slot: String = str(fact.slot)
			if public_slot not in previously_shared:
				previously_shared.append(public_slot)
	for slot: String in row.observed:
		var observation: Dictionary = row.observed[slot]
		cards.append({"slot":slot,"text_key":"b2.inspect." + slot,"value":str(observation.value),
			"kind":observation.kind,"selected":slot in row.selected,
			"ever_disclosed":slot in previously_shared})
	var history: Array = []
	for offer: Dictionary in row.offers:
		history.append({"amount":offer.amount,"currency":offer.currency,
			"response":offer.response,"public_cards":offer.revealed.duplicate(true)})
	return {"item_id":context.item_id,"def_id":context.item.def_id,"we_buy":context.visit.buyer=="player",
		"tools": options,"cards":cards,"offers":history,
		"accepted":row.accepted.duplicate(true)}
