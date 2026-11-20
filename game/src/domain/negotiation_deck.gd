extends RefCounted
## Bounded, receipt-bound records within one R001 visit. No random draw or price effects.
const Appraisal = preload("res://src/domain/gate1_appraisal.gd")
const Receipt = preload("res://src/domain/receipt_primitives.gd")
const Rules = preload("res://src/domain/value_rules.gd")
const Slots = preload("res://src/domain/appraisal_card_dialogue.gd")
const MAX_EVENTS: int = 48
const MAX_PRESENTED: int = 16

static func semantic(argument: Dictionary) -> Array:
	var p: Dictionary = argument.source_payload
	return [argument.slot,p.get(argument.slot),p.get("card_links",{}).get(argument.slot,[])]

static func payload_shape(p: Variant) -> bool:
	return Rules.keys(p,["op","slot","argument"]) or (Rules.keys(p,["op","slot","argument","current_argument"]) and p.op == "present")

static func latest_source(state: Dictionary, before: int) -> String:
	var best: int = 0
	var found: String = ""
	for table: Dictionary in [state.receipts,state.receipt_archive]:
		for id: String in table:
			var rev: int = Receipt.receipt_revision(state,id)
			if rev > best and rev < before and Receipt.receipt_type(state,id) == "record_hypothesis":
				best = rev
				found = id
	return found

static func historical_current(state: Dictionary, p: Dictionary, rev: int) -> bool:
	var last: String = latest_source(state,rev)
	if p.has("current_argument"):
		return Appraisal.argument_valid(state,p.current_argument,rev,false) and p.current_argument.source_action == last and semantic(p.argument) == semantic(p.current_argument)
	if last == p.argument.source_action:
		return true
	# Old v1 records had no current proof. Check full recent receipt where recoverable;
	# preserve prior archived v1 records whose payload was compacted before v2.
	if state.receipts.has(last):
		var command: Variant = JSON.parse_string(state.receipts[last].fingerprint)
		if not command is Dictionary or not command.get("payload") is Dictionary:
			return false
		var proof: Dictionary = {"slot":p.slot,"source_action":last,"source_payload":command.payload}
		return Appraisal.argument_valid(state,proof,rev,false) and semantic(proof) == semantic(p.argument)
	return not last.is_empty() and state.receipt_archive.has(last)

static func replay(state: Dictionary, events: Array, admission: int, terminal: int, hypotheses: Array) -> Dictionary:
	if events.size() > MAX_EVENTS:
		return {}
	var ready: Dictionary = {}
	var spoken: Array = []
	var used: Array = []
	var prior: int = admission
	for e: Variant in events:
		if not Rules.keys(e,["action_id","payload"]) or not Rules.identifier(e.action_id) or not payload_shape(e.payload):
			return {}
		var rev: int = Receipt.receipt_revision(state,e.action_id)
		var p: Dictionary = e.payload
		if rev <= prior or (terminal > 0 and rev >= terminal) or not Receipt.matches_receipt(state,e.action_id,"deck_action",p,rev) or p.slot not in Slots.SLOTS:
			return {}
		prior = rev
		match p.op:
			"prepare":
				if not Appraisal.argument_valid(state,p.argument,rev,false) or p.argument.slot != p.slot:
					return {}
				# Prepared snapshots originate from the latest committed assessment at preparation.
				var source: int = Receipt.receipt_revision(state,p.argument.source_action)
				for h: String in hypotheses:
					var h_rev: int = Receipt.receipt_revision(state,h)
					if h_rev > source and h_rev < rev:
						return {}
				if semantic(p.argument) in used or (ready.has(p.slot) and semantic(ready[p.slot]) == semantic(p.argument)):
					return {}
				ready[p.slot] = p.argument
			"remove":
				if p.argument != null or not ready.has(p.slot):
					return {}
				ready.erase(p.slot)
			"present":
				if not ready.has(p.slot) or ready[p.slot] != p.argument or not Appraisal.argument_valid(state,p.argument,rev,false):
					return {}
				var key: Array = semantic(p.argument)
				if key in used or spoken.size() >= MAX_PRESENTED or not historical_current(state,p,rev):
					return {}
				# Historical source, presentation and preparation are receipt-bound.
				used.append(key)
				spoken.append({"presentation_id":e.action_id,"argument":p.argument})
				ready.erase(p.slot)
			_:
				return {}
	return {"ready":ready,"presented":spoken,"used":used}

static func current(state: Dictionary, argument: Dictionary) -> bool:
	for candidate: Dictionary in Appraisal.argument_candidates(state):
		if semantic(candidate.argument) == semantic(argument):
			return true
	return false

static func apply(state: Dictionary, p: Dictionary, id: String) -> String:
	if not Appraisal.active(state) or not payload_shape(p) or p.slot not in Slots.SLOTS:
		return "deck_permission"
	var events: Array = state.campaign.get("deck_events",[])
	if events.size() >= MAX_EVENTS:
		return "deck_limit"
	var d: Dictionary = replay(state,events,0,0,[])
	if d.is_empty():
		return "deck_invalid"
	match p.op:
		"prepare":
			if not Appraisal.argument_valid(state,p.argument,int(state.revision)+1,true) or p.argument.slot != p.slot:
				return "deck_argument"
			if semantic(p.argument) in d.used or (d.ready.has(p.slot) and semantic(d.ready[p.slot]) == semantic(p.argument)):
				return "deck_duplicate"
		"remove":
			if p.argument != null or not d.ready.has(p.slot):
				return "deck_missing"
		"present":
			if not d.ready.has(p.slot) or d.ready[p.slot] != p.argument or not current(state,p.argument):
				return "deck_stale"
			if semantic(p.argument) in d.used or d.presented.size() >= MAX_PRESENTED:
				return "deck_duplicate"
			if p.has("current_argument"):
				if not Appraisal.argument_valid(state,p.current_argument,int(state.revision)+1,true) or semantic(p.argument) != semantic(p.current_argument):
					return "deck_current_proof"
			elif p.argument.source_action != latest_source(state,int(state.revision)+1):
				return "deck_current_proof"
		_:
			return "deck_operation"
	events.append({"action_id":id,"payload":p.duplicate(true)})
	state.campaign["deck_events"] = events
	return ""

static func valid(state: Dictionary, admitted: bool, admission: int, commands: Dictionary) -> bool:
	var events: Variant = state.campaign.get("deck_events",[])
	var ids: Array = commands.get("deck_action",[])
	if not events is Array or events.size() != ids.size() or (not admitted and not events.is_empty()):
		return false
	var terminal: Variant = state.campaign.get("negotiation",{}).get("terminal")
	var finish: int = Receipt.receipt_revision(state,terminal.action_id) if terminal != null else 0
	var d: Dictionary = replay(state,events,admission,finish,commands.get("record_hypothesis",[]))
	if d.is_empty():
		return false
	for e: Dictionary in events:
		if e.action_id not in ids:
			return false
	return true

static func words(argument: Dictionary, catalog: Dictionary) -> Dictionary:
	var record: Dictionary = argument.source_payload.duplicate(true)
	record["card_slot"] = argument.slot
	record["hypothesis_action_id"] = argument.source_action
	return Slots.project(record,catalog)

static func view(state: Dictionary) -> Dictionary:
	var d: Dictionary = replay(state,state.campaign.get("deck_events",[]),0,0,[])
	if d.is_empty():
		return {"ready":[],"presented":[],"latest_reply":{}}
	var ready: Array = []
	var catalog: Dictionary = Appraisal.public_reference()
	if Appraisal.active(state):
		for slot: String in Slots.SLOTS:
			if d.ready.has(slot):
				var argument: Dictionary = d.ready[slot]
				ready.append({"argument":argument,"current":current(state,argument),"label_key":words(argument,catalog).label_key})
	var presented: Array = []
	var appearance_claim: bool = false
	var latest: Dictionary = {}
	var offers: Array = state.campaign.get("negotiation",{}).get("offers",[])
	var last_offer: int = Receipt.receipt_revision(state,offers.back().action_id) if not offers.is_empty() else 0
	for original: Dictionary in d.presented:
		var row: Dictionary = original.duplicate(true)
		var line: Dictionary = words(row.argument,catalog)
		row["label_key"] = line.label_key
		row["speaker_key"] = "appraisal.deck_statement"
		row["response_key"] = "appraisal.deck_reply_" + str(row.argument.slot)
		row["claim_key"] = null
		row["claim_status"] = null
		if row.argument.slot == "appearance_id" and not appearance_claim:
			row["claim_key"] = "appraisal.deck_customer_claim"
			row["claim_status"] = "unconfirmed"
			appearance_claim = true
		presented.append(row)
		if Receipt.receipt_revision(state,row.presentation_id) > last_offer:
			latest = row
	return {"ready":ready,"presented":presented,"latest_reply":latest}

## Price basis is the last publicly presented appearance argument before the offer.
## New private judgments do not rewrite what was said. No stacking.
static func basis(state: Dictionary, ids: Variant, before_revision: int) -> Dictionary:
	if not ids is Array or ids.is_empty() or ids.size() > MAX_PRESENTED:
		return {}
	var presented: Array = view(state).presented
	var expected: Array = []
	var evidence: Variant = null
	for row: Dictionary in presented:
		if Receipt.receipt_revision(state,row.presentation_id) >= before_revision:
			continue
		expected.append(row.presentation_id)
		if row.argument.slot == "appearance_id":
			evidence = Appraisal.argument_evidence(row.argument)
	if expected != ids:
		return {}
	return {"evidence_id":evidence}
