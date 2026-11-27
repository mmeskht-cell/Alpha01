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
const CLAIMS_PATH: String = "res://data/alpha_b2/customer_claims_1.json"
const SURFACE_CHOICES := {"material":["unknown","metal","plastic","paper","fabric","glass"],"exterior":["unknown","minimal","moderate","severe"]}
const F3Trial = preload("res://src/domain/b3_f3_composite_trial.gd")
const SurfaceProfiles = preload("res://src/domain/appraisal_surface_profiles.gd")
const IntegratedCatalog = preload("res://src/domain/b3_integrated_catalog.gd")
const F3Receipt = preload("res://src/domain/receipt_primitives.gd")
const MAX_OFFERS: int = 3
const MAX_OBSERVATIONS: int = 8
const ACTIONS: Array = ["alpha_inspect", "alpha_card_toggle", "alpha_price_offer", "alpha_hypothesis", "alpha_statement_retract", "alpha_statement_reaffirm", "alpha_claim_challenge","alpha_composite_consent"]

static func config() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not data is Dictionary or not Rules.keys(data, ["version", "profile_id", "specimen_sources", "negotiation_terms"]) or data.version != 1 or data.profile_id != "alpha_b2_cards_pilot_1":
		return {}
	if not data.specimen_sources is Array or not data.negotiation_terms is Dictionary:
		return {}
	return data

## Claims are authored as customer self-report, never verified item facts.
## A customer cannot supply an unscripted claim in the command payload.
static func _claims() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CLAIMS_PATH))
	if not Rules.keys(data,["version","claims"]) or data.version != 1 or not data.claims is Array or data.claims.size() > 12:
		return {}
	var seen: Dictionary = {}
	for entry: Variant in data.claims:
		var required: Array = ["visit_id","actor_id","item_id","text_key"]
		if entry.has("asserted_slot") or entry.has("asserted_value"):
			required.append_array(["asserted_slot","asserted_value"])
		if not Rules.keys(entry,required):
			return {}
		if entry.has("asserted_slot") and (not Rules.identifier(entry.asserted_slot) or entry.asserted_value not in ["serviceable","inoperable"]):
			return {}
		for key: String in ["visit_id","actor_id","item_id","text_key"]:
			if not Rules.identifier(entry[key]):
				return {}
		if seen.has(entry.visit_id):
			return {}
		seen[entry.visit_id] = true
	return data

static func profile_valid(data: Dictionary, state: Dictionary) -> bool:
	var c: Dictionary = config()
	var claims: Dictionary = _claims()
	if c.is_empty() or claims.is_empty() or data.get("appraisal_id") != c.profile_id or not data.has("days"):
		return false
	for statement: Dictionary in claims.claims:
		var visit: Dictionary = state.visits.get(statement.visit_id,{})
		if visit.is_empty() or visit.seller != statement.actor_id or not visit.prices.has(statement.item_id):
			return false
		if not state.items.has(statement.item_id) or state.items[statement.item_id].owner_id != statement.actor_id:
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
		if not Rules.keys(src, ["def_id", "path"]) or not Rules.identifier(src.def_id) or not src.path is String or not (src.path.begins_with("res://data/campaign/gate2/") or src.path == "res://data/alpha_b2/inspection_live_stock_1.json"):
			return false
	return true

static func seed() -> Dictionary:
	return {"visits": {}}

static func _visit_context(state: Dictionary) -> Dictionary:
	var a: Dictionary = state.alpha_shop
	if a.profile.get("content_version") not in ["b2-cards-pilot-1","b2-cards-commission-1","b2-cards-commission-named-1","b2-cards-commission-service-1","b2-cards-commission-service-recovery-2", "b2-cards-commission-service-multi-3", "b3-finite-market-m1", "b3-finite-market-m2", "b3-finite-market-fx-m3"] or a.phase != "CUSTOMER_ACTIVE" or not state.visits.has(a.active):
		return {}
	if a.has("commissions") and Commission.is_return_visit(a.active, str(a.profile.get("commission_profile_id", ""))):
		return {}
	var visit: Dictionary = state.visits[a.active]
	if visit.scope.completed or visit.prices.size() != 1 or (visit.seller != "player" and not visit.allow_inspection and not (a.profile.has("spatial_opening") and visit.scope.kind=="ordinary")):
		return {}
	var item_id: String = str(visit.prices.keys()[0])
	if not state.items.has(item_id):
		return {}
	if visit.seller == "player" and (item_id not in a.displayed or state.items[item_id].inventory != "storefront_grid"):
		return {}
	return {"visit_id": a.active, "item_id": item_id, "item": state.items[item_id], "visit": visit}

## Item-sourced tools are authored for a specific definition+provenance.
## A field read is permitted only after the matching inspect action; no
## uninspected truth crosses to the UI or to the counterparty. No generic
## property-path access, reflection or client-supplied slot->field mapping.
static func _inspected_value(item: Dictionary, reading: Variant) -> Variant:
	if reading is Dictionary:
		if not Rules.keys(reading, ["source_field"]) or reading.source_field != "functional":
			return null
		return "serviceable" if item.functional else "inoperable"
	if reading is String or reading is int or reading is float or reading is bool:
		return Rules.normalized(reading)
	return null

static func _tool_rows(state: Dictionary, item_id: String) -> Array:
	var active: Dictionary = state.visits.get(state.alpha_shop.active,{})
	if active.get("seller") != "player" and not active.get("allow_inspection",false):
		return []
	var c: Dictionary = config()
	if c.is_empty() or not state.items.has(item_id):
		return []
	var item: Dictionary = state.items[item_id]
	var options: Array = [{"id":"identity","text_key":"b2.inspect.identity","kind":"fact"}]
	var catalog_item := IntegratedCatalog.specimen(state.alpha_shop.profile,item_id,item)
	if catalog_item.get("functional",false):
		options.append({"id":"function_detail","text_key":"b2.inspect.function_detail","kind":"fact"})
	if F3Trial.enabled(state.alpha_shop.profile) and item.def_id==F3Trial.MODEL:
		options.append({"id":"function_detail","text_key":"b2.inspect.function_detail","kind":"fact"})
		var consent:Dictionary=state.alpha_shop.appraisal.visits.get(state.alpha_shop.active,{}).get("composite_consent",{})
		if consent.get("granted",false):
			for slot:String in ["f3_part_a","f3_part_b"]:
				options.append({"id":slot,"text_key":"b2.inspect."+slot,"kind":"fact"})
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
			if _inspected_value(item, specimen.readings[tool.id]) == null:
				continue
			options.append({"id":tool.id,"text_key":"b2.inspect." + str(tool.id),"kind":"fact"})
	var authored := SurfaceProfiles.authored_readings(state.alpha_shop.profile,item_id,item)
	for slot: String in authored:
		if not options.any(func(option:Dictionary)->bool:return option.id==slot):
			options.append({"id":slot,"text_key":"b2.inspect."+slot,"kind":"fact","surface_side":authored[slot].side})
	return options

static func _reading(state: Dictionary, item_id: String, slot: String) -> Dictionary:
	var item: Dictionary = state.items[item_id]
	if slot == "identity":
		return {"slot": slot, "value": item.def_id, "kind": "fact", "version": item.field_versions.duplicate(true)}
	if slot=="function_detail" and IntegratedCatalog.specimen(state.alpha_shop.profile,item_id,item).get("functional",false):
		return {"slot":slot,"value":_inspected_value(item,{"source_field":"functional"}),"kind":"fact","version":item.field_versions.duplicate(true)}
	if F3Trial.enabled(state.alpha_shop.profile) and item.def_id==F3Trial.MODEL and slot=="function_detail":
		return {"slot":slot,"value":F3Trial.signal_value(state,item_id),"kind":"fact","version":item.field_versions.duplicate(true)}
	if F3Trial.enabled(state.alpha_shop.profile) and item.def_id==F3Trial.MODEL and slot in ["f3_part_a","f3_part_b"]:
		return {"slot":slot,"value":F3Trial.part_signal(state,item_id,slot),"kind":"fact","version":item.field_versions.duplicate(true)}
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
				var inspected: Variant = _inspected_value(item,specimen.readings[slot])
				if inspected == null:
					return {}
				return {"slot":slot,"value":inspected,"kind":"fact","version":item.field_versions.duplicate(true)}
	var authored := SurfaceProfiles.authored_readings(state.alpha_shop.profile,item_id,item)
	if authored.has(slot):
		return {"slot":slot,"value":authored[slot].value,"kind":"fact","version":item.field_versions.duplicate(true)}
	return {}

static func _row(state: Dictionary, context: Dictionary) -> Dictionary:
	var a: Dictionary = state.alpha_shop
	return a.appraisal.visits.get(context.visit_id, {"item_id": context.item_id,"observed":{},"selected":[],"offers":[],"accepted":{}}).duplicate(true)

## Reconstruct the current public standing from immutable proposal facts and
## explicit subsequent statements. "Heard before" never means "still endorsed".
## offer_count is the bounded causal ordering key; no clocks or new save root.
static func public_history(row: Dictionary) -> Dictionary:
	var ever: Array = []
	var active: Array = []
	var actions: Array = row.get("statements",[])
	var offers: Array = row.get("offers",[])
	for i: int in range(offers.size()):
		for fact: Dictionary in offers[i].revealed:
			var slot: String = str(fact.slot)
			if slot not in ever:
				ever.append(slot)
			if slot not in active:
				active.append(slot)
		for record: Dictionary in actions:
			if int(record.after_offer) != i + 1:
				continue
			var slot: String = str(record.slot)
			if record.kind == "withdraw":
				active.erase(slot)
			elif record.kind == "reaffirm" and slot in ever and slot not in active:
				active.append(slot)
	var withdrawn: Array = []
	for slot: String in ever:
		if slot not in active:
			withdrawn.append(slot)
	return {"known_slots":ever,"active_slots":active,"withdrawn_slots":withdrawn}

## Direction is descriptive: the same source-backed item evidence has the
## opposite bargaining implication when the shop buys vs sells. This never
## changes a price, creates an offer, or calculates a hidden NPC threshold.
static func _value_signal(slot: String, value: Variant) -> String:
	if slot in ["function_detail","condition_detail"]:
		if value == "serviceable":
			return "positive"
		if value == "inoperable":
			return "negative"
	if slot in ["wear_detail","display_damage_detail"] and (value is int or value is float):
		return "negative" if float(value) > 0.0 else "neutral"
	return "unknown"

static func _claim_discrepancy(row: Dictionary, statement: Dictionary) -> String:
	if not statement.has("asserted_slot"):
		return "not_testable"
	var slot: String = str(statement.asserted_slot)
	if not row.observed.has(slot):
		return "unverified"
	var observed: Dictionary = row.observed[slot]
	return "consistent" if observed.value == statement.asserted_value else "conflict"

static func _source_offer_action(row: Dictionary, slot: String) -> String:
	var result: String = ""
	for offer: Dictionary in row.get("offers",[]):
		for fact: Dictionary in offer.revealed:
			if str(fact.slot) == slot:
				result = str(offer.action_id)
	return result

static func _catalog_counteroffer(state: Dictionary,context: Dictionary,row: Dictionary,basis: int,offered: int) -> bool:
	if IntegratedCatalog.visit_item(state.alpha_shop.profile,context.visit_id).is_empty() or not row.accepted.is_empty():
		return false
	var item: Dictionary = context.item
	var function_fact: Dictionary = row.observed.get("function_detail",{})
	var function_current: bool = "function_detail" in row.selected and function_fact.get("version")==item.field_versions
	var wear_fact: Dictionary = row.observed.get("wear_detail",{})
	var damaged: bool = "wear_detail" in row.selected and SurfaceProfiles.current_fact("wear_detail",wear_fact,item) and int(wear_fact.get("value",0))>=30
	var margin := clampi(roundi(basis*0.10),1,3)
	if context.visit.buyer=="player":
		return basis>offered and basis-offered<=margin and (damaged or (function_current and function_fact.get("value")=="inoperable"))
	return offered>basis and offered-basis<=margin and function_current and function_fact.get("value")=="serviceable"

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
		"alpha_composite_consent":
			if not p.is_empty() or not F3Trial.enabled(a.profile) or context.item.def_id!=F3Trial.MODEL or context.visit.seller=="player" or not context.visit.allow_inspection or row.has("composite_consent"):
				return "alpha_inspect_permission"
			# Authored customer response, read-only access for this visit only.
			row["composite_consent"]={"granted":context.visit_id==F3Trial.BUY,"action_id":command.action_id}
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
		"alpha_hypothesis":
			# Explicitly provisional and private. Never put guesses inside
			# row.observed, selected fact cards, NPC DTO or customer receipts.
			if not Rules.keys(p,["slot","judgment"]) or not Rules.identifier(p.slot) or not p.judgment is String:
				return "alpha_hypothesis_shape"
			var guess_allowed: bool = SURFACE_CHOICES.has(p.slot) and p.judgment in SURFACE_CHOICES[p.slot]
			for option: Dictionary in _tool_rows(state,context.item_id):
				if option.id == p.slot and p.slot in ["function_detail","condition_detail"] and p.judgment in ["serviceable","inoperable","unknown"]:
					guess_allowed = true
			if not guess_allowed:
				return "alpha_hypothesis_slot"
			var hypotheses: Dictionary = row.get("hypotheses",{})
			if str(hypotheses.get(p.slot,"unknown")) == p.judgment:
				return "alpha_hypothesis_unchanged"
			if p.judgment == "unknown":
				hypotheses.erase(p.slot)
			else:
				hypotheses[p.slot] = p.judgment
			if hypotheses.is_empty():
				row.erase("hypotheses")
			else:
				row["hypotheses"] = hypotheses
		"alpha_statement_retract", "alpha_statement_reaffirm":
			if not Rules.keys(p,["slot"]) or not Rules.identifier(p.slot) or not row.observed.has(p.slot):
				return "alpha_statement_shape"
			var public: Dictionary = public_history(row)
			var currently_public: bool = p.slot in public.active_slots
			var has_been_public: bool = p.slot in public.known_slots
			if not has_been_public or (command.type == "alpha_statement_retract" and not currently_public) or (command.type == "alpha_statement_reaffirm" and currently_public):
				return "alpha_statement_status"
			var source_offer: String = _source_offer_action(row,p.slot)
			if source_offer.is_empty():
				return "alpha_statement_origin"
			var statement_actions: Array = row.get("statements",[])
			if statement_actions.size() >= 8:
				return "alpha_statement_limit"
			statement_actions.append({"action_id":command.action_id,
				"kind":"withdraw" if command.type == "alpha_statement_retract" else "reaffirm",
				"slot":p.slot,"source_offer_action_id":source_offer,
				"after_offer":row.offers.size()})
			row["statements"] = statement_actions
			if command.type == "alpha_statement_retract":
				# Withdrawing a statement never erases what the customer heard,
				# and it must not silently re-publish on the next price offer.
				row.selected.erase(p.slot)
		"alpha_claim_challenge":
			# A contradiction is not proof of intentional dishonesty. Only
			# explicitly inspected, same-item, same-visit evidence can be
			# raised with the speaking customer. No automatic trust penalty.
			if not Rules.keys(p,["claim_key"]) or not Rules.identifier(p.claim_key):
				return "alpha_claim_shape"
			var claim: Dictionary = {}
			for authored: Dictionary in _claims().get("claims",[]):
				if authored.visit_id == p.claim_key and authored.visit_id == context.visit_id and authored.actor_id == context.visit.seller and authored.item_id == context.item_id:
					claim = authored
			if claim.is_empty() or _claim_discrepancy(row,claim) != "conflict":
				return "alpha_claim_unverified"
			if row.get("claim_challenges",[]).size() > 0:
				return "alpha_claim_duplicate"
			var checked: Dictionary = row.observed[claim.asserted_slot]
			row["claim_challenges"] = [{"action_id":command.action_id,"claim_key":p.claim_key,
				"item_id":context.item_id,"slot":claim.asserted_slot,
				"seller_statement":claim.asserted_value,"verified_reading":checked.value,
				"evidence_kind":checked.kind}]
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
			if _catalog_counteroffer(state,context,row,original,int(p.amount)):
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
			var assessment := {}
			for slot: String in SURFACE_CHOICES:
				if row.get("hypotheses",{}).has(slot): assessment[slot] = row.hypotheses[slot]
			if not assessment.is_empty():
				outcome["private_assessment"] = assessment
				var known_slots: Array = row.observed.keys()
				known_slots.sort()
				outcome["observed_slots"] = known_slots
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

## Only evidence already disclosed in a previous visit is historical testimony.
## A proposal can exist without a completed transfer.
static func prior_disclosures(state: Dictionary,item_id: String,current_visit: String) -> Array:
	var records: Array = []
	# JSON canonicalization sorts dictionary keys. For the new composite
	# profile, actual receipt revisions, not visit-key insertion order,
	# define the chronological sequence of historical proposals.
	var ordered:bool=F3Trial.enabled(state.alpha_shop.profile) and item_id==F3Trial.ROOT
	var visits: Dictionary = state.get("alpha_shop",{}).get("appraisal",{}).get("visits",{})
	for visit_id: String in visits:
		var row: Dictionary = visits[visit_id]
		if visit_id==current_visit or row.get("item_id")!=item_id: continue
		for offer: Dictionary in row.get("offers",[]):
			var facts: Array = []
			for observation: Dictionary in offer.get("revealed",[]):
				var fact:Dictionary={"slot":observation.slot,"value":observation.value}
				if ordered:
					fact["current"]=F3Trial.observation_current(state,item_id,observation)
				facts.append(fact)
			var record:Dictionary={"amount":offer.amount,"currency":offer.currency,"response":offer.response,"facts":facts,"assessment":offer.get("private_assessment",{}).duplicate(),"observed_slots":offer.get("observed_slots",[]).duplicate()}
			if ordered:
				var rev:int=F3Receipt.receipt_revision(state,offer.get("action_id",""))
				var journal:Array=state.alpha_shop.commands
				if rev<1 or rev>journal.size(): continue
				var cmd:Dictionary=journal[rev-1]
				if cmd.type!="alpha_price_offer" or cmd.action_id!=offer.action_id or cmd.payload.get("amount")!=offer.amount or not F3Receipt.matches_receipt(state,cmd.action_id,cmd.type,cmd.payload,rev): continue
				record["revision"]=rev
			records.append(record)
	if ordered:
		records.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.revision)<int(b.revision))
	return records

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
	var tools: Array = _tool_rows(state,context.item_id)
	var surface_facts: Dictionary = {}
	var options: Array = []
	for tool: Dictionary in tools:
		if not row.observed.has(tool.id):
			options.append(tool)
		elif row.item_id==context.item_id and SurfaceProfiles.current_fact(tool.id,row.observed[tool.id],context.item):
			surface_facts[tool.id] = row.observed[tool.id]
	var cards: Array = []
	var public: Dictionary = public_history(row)
	for slot: String in row.observed:
		var observation: Dictionary = row.observed[slot]
		var value_signal: String = _value_signal(slot, observation.value)
		var helps_shop: bool = (value_signal == "negative" and context.visit.buyer=="player") or (value_signal == "positive" and context.visit.seller=="player")
		var effect: String = "unknown" if value_signal in ["unknown","neutral"] else ("helps" if helps_shop else "hurts")
		var card := {"slot":slot,"text_key":"b2.inspect." + slot,"value":str(observation.value),
			"kind":observation.kind,"selected":slot in row.selected,
			"value_signal":value_signal,"shop_effect":effect,
			"ever_disclosed":slot in public.known_slots,
			"public_active":slot in public.active_slots}
		if slot in SurfaceProfiles.SLOTS:
			card["surface_current"] = surface_facts.has(slot)
			for tool: Dictionary in tools:
				if tool.id==slot and tool.has("surface_side"):
					card["surface_side"] = tool.surface_side
					break
		cards.append(card)
	var history: Array = []
	for offer: Dictionary in row.offers:
		history.append({"amount":offer.amount,"currency":offer.currency,
			"response":offer.response,"public_cards":offer.revealed.duplicate(true)})
	var hypotheses: Array = []
	for tool: Dictionary in tools:
		if str(tool.id) in ["function_detail","condition_detail"]:
			hypotheses.append({"slot":str(tool.id),"kind":"hypothesis",
				"judgment":str(row.get("hypotheses",{}).get(tool.id,"unknown"))})
	var claims: Array = []
	for statement: Dictionary in _claims().get("claims",[]):
		if statement.visit_id == context.visit_id and statement.actor_id == context.visit.seller and statement.item_id == context.item_id:
			var discrepancy: String = _claim_discrepancy(row,statement)
			var challenged: bool = false
			for event: Dictionary in row.get("claim_challenges",[]):
				if event.claim_key == statement.visit_id:
					challenged = true
			claims.append({"kind":"customer_claim","claim_key":str(statement.visit_id),
				"text_key":str(statement.text_key),"check_status":discrepancy,
				"can_challenge":discrepancy=="conflict" and not challenged,
				"challenged":challenged})
	var terms: Dictionary = context.visit.prices[context.item_id]
	var currency := "VKC" if int(terms.VKC)>0 else "USD"
	var result:Dictionary={"offer_currency":currency,"item_id":context.item_id,"def_id":context.item.def_id,"we_buy":context.visit.buyer=="player",
		"surface_seed":("%s/%s"%[state.alpha_shop.profile.get("visit_random",{}).get("seed",0),context.item_id]).sha256_text().left(8).hex_to_int(),
		"surface_judgments":row.get("hypotheses",{}).duplicate(),
		"surface_profiles":SurfaceProfiles.project(context.item_id,context.item,surface_facts,state.alpha_shop.profile),
		"tools": options,"cards":cards,"offers":history,"hypotheses":hypotheses,
		"customer_claims":claims,"statements":row.get("statements",[]).duplicate(true),
		"claim_challenges":row.get("claim_challenges",[]).duplicate(true),
		"commitments":[],"public_standing":public,
		"accepted":row.accepted.duplicate(true)}
	if F3Trial.enabled(state.alpha_shop.profile) and context.item.def_id==F3Trial.MODEL and context.visit.seller!="player":
		result["composite_access"]="not_requested" if not row.has("composite_consent") else ("granted" if row.composite_consent.granted else "denied")
	return result
