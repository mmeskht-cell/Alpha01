extends RefCounted
## Generic active-visit argument deck. Only explicit presentation is public.
## All state changes are made inside the GameSession candidate and replay.
## No hidden truth, customer acceptance, offer counts or price effects.
const Rules = preload("res://src/domain/value_rules.gd")
const Assessment = preload("res://src/domain/visit_appraisal_assessment.gd")
const Observation = preload("res://src/domain/visit_appraisal_observation.gd")
const Receipt = preload("res://src/domain/receipt_primitives.gd")
const CustomerClaims = preload("res://src/domain/visit_customer_claims.gd")
const ACTION: String = "subject_deck_action"
const MAX_EVENTS: int = 48
const MAX_PRESENTED: int = 16

static func blank() -> Dictionary:
	return {"ready":{},"presented":[],"event_count":0}

static func row_for(state: Dictionary,visit_id: String,item_id: String) -> Dictionary:
	var entry: Dictionary = state.get("calendar",{}).get("appraisal_decks",{}).get(visit_id,{})
	return entry.deck.duplicate(true) if entry.get("item_id") == item_id else blank()

static func semantic(argument: Dictionary) -> Array:
	return [argument.slot_id,argument.candidate_id,argument.evidence_ids]

## Derive the entire argument from the current authoritative assessment.
## No client-supplied observations or claimed correctness.
static func candidate(state: Dictionary,visit_id: String,item_id: String,slot_id: String) -> Dictionary:
	var profile: Dictionary = Assessment.catalog(state,visit_id,item_id)
	if profile.is_empty():
		return {}
	var assessed: Dictionary = Assessment.assessment(state,visit_id,item_id)
	if not assessed.selected.has(slot_id) or not Rules.identifier(assessed.source_action):
		return {}
	if Receipt.receipt_revision(state,assessed.source_action) < 1 or Receipt.receipt_type(state,assessed.source_action) not in Assessment.ACTIONS:
		return {}
	var ids: Array = assessed.links.get(slot_id,[]).duplicate()
	var known: Dictionary = {}
	for fact: Dictionary in Observation.view(state,visit_id,item_id):
		if fact.current and not fact.is_claim:
			known[fact.evidence_id] = true
	for id: String in ids:
		if not known.has(id):
			return {}
	var label_key: String = ""
	for slot: Dictionary in profile.slots:
		if slot.id != slot_id:
			continue
		for choice: Dictionary in slot.candidates:
			if choice.id == assessed.selected[slot_id]:
				label_key = choice.label_key
	if label_key.is_empty():
		return {}
	return {"slot_id":slot_id,"candidate_id":assessed.selected[slot_id],"source_action":assessed.source_action,"evidence_ids":ids,"label_key":label_key,"statement_kind":"hypothesis"}

static func observation_argument(state: Dictionary,visit_id: String,item_id: String,ref_id: String) -> Dictionary:
	if Receipt.receipt_revision(state,ref_id)<1 or Receipt.receipt_type(state,ref_id)!="inspect_subject":
		return {}
	for fact: Dictionary in Observation.view(state,visit_id,item_id):
		if fact.evidence_id==ref_id and fact.current and not fact.is_claim:
			return {"slot_id":"observed."+str(fact.observation_key),"candidate_id":ref_id,"source_action":ref_id,"evidence_ids":[ref_id],"label_key":str(fact.observation_key),"statement_kind":"observation","observed_value":fact.observed_value}
	return {}

static func current(state: Dictionary,visit_id: String,item_id: String,argument: Dictionary) -> bool:
	var latest: Dictionary = candidate(state,visit_id,item_id,argument.slot_id)
	return not latest.is_empty() and semantic(latest) == semantic(argument)

static func already_presented(deck: Dictionary,argument: Dictionary) -> bool:
	for e: Dictionary in deck.presented:
		if semantic(e.argument) == semantic(argument):
			return true
	return false

## Latest event for a slot can be a judgment or explicit withdrawal.
static func latest_statement(presented: Array,slot_id: String) -> Dictionary:
	for i: int in range(presented.size()-1,-1,-1):
		var row: Dictionary = presented[i]
		if row.argument.slot_id == slot_id:
			return row
	return {}

static func direct_duplicate(presented: Array,argument: Dictionary) -> bool:
	var row: Dictionary = latest_statement(presented,argument.slot_id)
	return not row.is_empty() and not row.has("withdraws_presentation_id") and semantic(row.argument) == semantic(argument)

## Current public basis, independent of unpublished private edits.
## Historical offers continue to reference the exact earlier statements.
static func public_basis(presented: Array) -> Array:
	var latest: Dictionary = {}
	for row: Dictionary in presented:
		latest[row.argument.slot_id] = row.presentation_id
	var ids: Array = []
	for row: Dictionary in presented:
		if latest[row.argument.slot_id] == row.presentation_id and not row.has("withdraws_presentation_id"):
			ids.append(row.presentation_id)
	return ids

static func apply(state: Dictionary,p: Dictionary,action_id: String) -> String:
	var fields: Array = ["visit_id","item_id","slot_id","op","ref_id"]
	if p.has("claim_id"):
		fields.append("claim_id")
	if not Rules.keys(p,fields) or not Rules.identifier(action_id):
		return "subject_deck_shape"
	if p.has("claim_id") and (p.get("op") not in ["present","present_direct"] or not Rules.identifier(p.claim_id) or not CustomerClaims.enabled(state)):
		return "subject_deck_claim_shape"
	for field: String in ["visit_id","item_id","slot_id","op","ref_id"]:
		if not Rules.identifier(p[field]):
			return "subject_deck_shape"
	var profile: Dictionary = Assessment.catalog(state,p.visit_id,p.item_id)
	if profile.is_empty() or (not Assessment.slot_exists(profile,p.slot_id) and not (p.slot_id.begins_with("observed.") and p.op in ["present_observation","withdraw"])):
		return "subject_deck_permission"
	var deck: Dictionary = row_for(state,p.visit_id,p.item_id)
	if deck.event_count >= MAX_EVENTS:
		return "subject_deck_limit"
	var ready: Dictionary = deck.ready.get(p.slot_id,{})
	match p.op:
		"prepare":
			var argument: Dictionary = candidate(state,p.visit_id,p.item_id,p.slot_id)
			if argument.is_empty() or p.ref_id != argument.source_action:
				return "subject_deck_source"
			if already_presented(deck,argument) or (not ready.is_empty() and semantic(ready.argument) == semantic(argument)):
				return "subject_deck_duplicate"
			deck.ready[p.slot_id] = {"card_id":action_id,"argument":argument}
		"remove":
			if ready.is_empty() or ready.card_id != p.ref_id:
				return "subject_deck_card"
			deck.ready.erase(p.slot_id)
		"withdraw":
			var prior: Dictionary = latest_statement(deck.presented,p.slot_id)
			if prior.is_empty() or prior.has("withdraws_presentation_id") or prior.presentation_id != p.ref_id or deck.presented.size() >= MAX_PRESENTED:
				return "subject_deck_withdrawal"
			# No new observation, assertion, customer beat, price or private edit.
			deck.presented.append({"presentation_id":action_id,"card_id":prior.card_id,"argument":prior.argument.duplicate(true),"current_source_action":prior.current_source_action,"withdraws_presentation_id":prior.presentation_id})
		"present_observation":
			var observed: Dictionary = observation_argument(state,p.visit_id,p.item_id,p.ref_id)
			if observed.is_empty() or observed.slot_id!=p.slot_id or direct_duplicate(deck.presented,observed) or deck.presented.size()>=MAX_PRESENTED:
				return "subject_deck_observation"
			var factual: Dictionary = {"presentation_id":action_id,"card_id":p.ref_id,"argument":observed,"current_source_action":p.ref_id}
			var prior_fact: Dictionary = latest_statement(deck.presented,p.slot_id)
			if not prior_fact.is_empty():
				factual["corrects_presentation_id"]=prior_fact.presentation_id
			# No authored hypothesis response or discount is inferred from a reading.
			deck.presented.append(factual)
		"present", "present_direct":
			var latest: Dictionary = candidate(state,p.visit_id,p.item_id,p.slot_id)
			var argument: Dictionary
			var card_id: String
			if p.op == "present_direct":
				# The current private assessment is the card. No prepare command or
				# client-supplied evidence can create a new public statement.
				if latest.is_empty() or p.ref_id != latest.source_action:
					return "subject_deck_source"
				argument = latest
				card_id = latest.source_action
			else:
				# Keep the historical preparation/presentation journal replayable.
				if ready.is_empty() or ready.card_id != p.ref_id:
					return "subject_deck_card"
				if latest.is_empty() or semantic(latest) != semantic(ready.argument):
					return "subject_deck_stale"
				argument = ready.argument
				card_id = ready.card_id
			if (direct_duplicate(deck.presented,argument) if p.op == "present_direct" else already_presented(deck,argument)) or deck.presented.size() >= MAX_PRESENTED:
				return "subject_deck_duplicate_or_limit"
			var speech: Dictionary = {"presentation_id":action_id,"card_id":card_id,"argument":argument.duplicate(true),"current_source_action":latest.source_action}
			if p.op == "present_direct":
				# A corrected assertion refers to the previous disclosed version;
				# never erase historical statements or mutate an accepted offer.
				for i: int in range(deck.presented.size()-1,-1,-1):
					var previous: Dictionary = deck.presented[i]
					if previous.argument.slot_id == p.slot_id:
						speech["corrects_presentation_id"] = previous.presentation_id
						break
			if p.has("claim_id"):
				var rebuttal: Dictionary = CustomerClaims.rebuttal(p.visit_id,p.item_id,argument,p.claim_id,deck.presented)
				if rebuttal.is_empty():
					return "subject_deck_rebuttal"
				speech["rebuttal"] = rebuttal
			var response: Dictionary = CustomerClaims.respond(state,p.visit_id,p.item_id,argument,action_id,deck.presented)
			if not response.is_empty():
				speech["customer_response"] = response
			deck.presented.append(speech)
			deck.ready.erase(p.slot_id)
		_:
			return "subject_deck_op"
	deck.event_count += 1
	if not state.calendar.has("appraisal_decks"):
		state.calendar["appraisal_decks"] = {}
	state.calendar.appraisal_decks[p.visit_id] = {"item_id":p.item_id,"deck":deck}
	return ""

## Terminal visit keeps only actual spoken records, not unpresented drafts.
## Journal retains commands for exact deterministic restore and idempotence.
static func finish(state: Dictionary,visit_id: String) -> void:
	var entries: Dictionary = state.calendar.get("appraisal_decks",{})
	if not entries.has(visit_id):
		return
	var deck: Dictionary = entries[visit_id].deck
	deck.ready.clear()
	if deck.presented.is_empty():
		entries.erase(visit_id)
	if entries.is_empty():
		state.calendar.erase("appraisal_decks")

static func view(state: Dictionary,visit_id: String,item_id: String) -> Dictionary:
	var profile: Dictionary = Assessment.catalog(state,visit_id,item_id)
	if profile.is_empty():
		return {}
	var deck: Dictionary = row_for(state,visit_id,item_id)
	var ready: Array = []
	var candidates: Array = []
	var direct_ready: Array = []
	for slot: Dictionary in profile.slots:
		var entry: Dictionary = deck.ready.get(slot.id,{})
		var argument: Dictionary = candidate(state,visit_id,item_id,slot.id)
		if not entry.is_empty():
			entry["current"] = current(state,visit_id,item_id,entry.argument)
			if CustomerClaims.enabled(state):
				entry["rebuttal_options"] = CustomerClaims.rebuttal_options(visit_id,item_id,entry.argument,deck.presented) if entry.current else []
			ready.append(entry)
		if not argument.is_empty():
			var spoken: bool = already_presented(deck,argument)
			candidates.append({"argument":argument,"already_presented":spoken,"already_ready":not entry.is_empty() and semantic(entry.argument) == semantic(argument)})
			if not direct_duplicate(deck.presented,argument):
				var correction: bool = false
				for statement: Dictionary in deck.presented:
					if statement.argument.slot_id == slot.id:
						correction = true
				var direct: Dictionary = {"card_id":slot.id,"argument":argument,"current":true,"correction":correction}
				if CustomerClaims.enabled(state):
					direct["rebuttal_options"] = CustomerClaims.rebuttal_options(visit_id,item_id,argument,deck.presented)
				direct_ready.append(direct)
	var observation_ready: Array = []
	for fact: Dictionary in Observation.view(state,visit_id,item_id):
		var observed: Dictionary = observation_argument(state,visit_id,item_id,fact.evidence_id)
		if not observed.is_empty() and not direct_duplicate(deck.presented,observed):
			observation_ready.append(observed)
	return {"ready":ready,"direct_ready":direct_ready,"observation_ready":observation_ready,"presented":deck.presented,"public_basis_ids":public_basis(deck.presented),"candidates":candidates,"remaining_events":MAX_EVENTS-deck.event_count,"remaining_presentations":MAX_PRESENTED-deck.presented.size()}
