extends RefCounted
const Retention=preload("res://src/domain/appraisal_history_retention.gd")
## Read-only projection of validated, player-participating ledger records.
## No external simulation, separate save fields, private tracking tier or hidden state.
const DISPLAY_LIMIT: int = 12
const Receipt = preload("res://src/domain/receipt_primitives.gd")
const Evidence = preload("res://src/domain/evidence_primitives.gd")
const Rules = preload("res://src/domain/value_rules.gd")
const Deck = preload("res://src/domain/visit_negotiation_deck.gd")
const BasicSaleQuality=preload("res://src/domain/basic_sale_quality.gd")
const Merchant=preload("res://src/domain/calendar_merchant_contracts.gd")

static func public_history(state: Dictionary, item_id: String) -> Dictionary:
	var records: Array = []
	var omitted: int = 0
	if item_id.is_empty():
		return {"records": records, "omitted": omitted}
	var ledger: Array = state.get("ledger", [])
	for i: int in range(ledger.size() - 1, -1, -1):
		var entry: Dictionary = ledger[i]
		if item_id not in entry.item_ids or "player" not in [entry.from, entry.to]:
			continue
		if records.size() >= DISPLAY_LIMIT:
			omitted += 1
			continue
		# Only one traded root has a known complete transaction price.
		# A child or multi-root delivery must not inherit that total.
		var amount: Variant = null
		if entry.root_ids.size() == 1 and entry.root_ids[0] == item_id:
			amount = entry.amounts.duplicate(true)
		records.append({"minute": int(entry.game_minutes), "direction": "purchase" if entry.from == "player" else "sale", "amounts": amount})
	return {"records": records, "omitted": omitted}

## Calendar extension to L1. A validated ledger is the sole source of
## transaction existence. No second persisted history or invisible external data.
static func calendar_history(state: Dictionary,item_id: String) -> Dictionary:
	var result: Dictionary = {"records":[],"omitted":0,"work_records":[],"work_omitted":0}
	if not Rules.identifier(item_id):
		return result
	var ledger: Array = state.get("ledger",[])
	for i: int in range(ledger.size()-1,-1,-1):
		var entry: Dictionary = ledger[i]
		if item_id not in entry.item_ids or "player" not in [entry.from,entry.to]:
			continue
		if result.records.size() >= DISPLAY_LIMIT:
			result.omitted += 1
			continue
		var single_root: bool = entry.root_ids.size()==1 and entry.root_ids[0]==item_id
		var row: Dictionary = {"event_id":entry.event_id,"minute":int(entry.game_minutes),"direction":"purchase" if entry.from=="player" else "sale","amounts":entry.amounts.duplicate(true) if single_root else null}
		if single_root and row.direction=="purchase":
			var offer: Dictionary = _bound_offer(state,entry,item_id)
			if not offer.is_empty():
				row["offer"] = offer
			var sheet: Dictionary = _public_sheet(state,entry,item_id,offer)
			if not sheet.is_empty():
				row["appraisal_sheet"] = sheet
		elif single_root and row.direction=="sale":
			var sale_sheet:Dictionary=BasicSaleQuality.sheet(state,entry,item_id)
			if not sale_sheet.is_empty():
				row["appraisal_sheet"]=sale_sheet
		result.records.append(row)
	var events: Array = state.get("object_events",[])
	for i: int in range(events.size()-1,-1,-1):
		var e: Dictionary = events[i]
		if item_id not in e.item_ids:
			continue
		var work: Dictionary = _work_row(state,e,item_id)
		if work.is_empty():
			continue
		if result.work_records.size() >= DISPLAY_LIMIT:
			result.work_omitted += 1
		else:
			result.work_records.append(work)
	if state.get("calendar",{}).has("merchant_contracts"):
		result["contract_records"]=[]
		for contract:Dictionary in Merchant.item_records(state,item_id):
			if contract.kind=="order_delivery":
				result.records.append({"event_id":contract.event_id,"minute":contract.minute,
					"direction":"sale","amounts":contract.amounts.duplicate(true),
					"contract_kind":"order"})
			else:
				result.contract_records.append(contract)
		result.records.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
			return int(a.minute)>int(b.minute) if a.minute!=b.minute else str(a.event_id)>str(b.event_id))
		if result.records.size()>DISPLAY_LIMIT:
			result.omitted+=result.records.size()-DISPLAY_LIMIT
			result.records=result.records.slice(0,DISPLAY_LIMIT)
		if result.contract_records.size()>DISPLAY_LIMIT:
			result.contract_records=result.contract_records.slice(0,DISPLAY_LIMIT)
	return result

## Final disclosed appraisal is distinct from the earlier accepted offer.
## Only an actual trade can produce this view; no hidden facts, private draft,
## implied warranty, or second persisted record. Legacy visits retain old DTOs.
static func _public_sheet(state: Dictionary,entry: Dictionary,item_id: String,offer: Dictionary) -> Dictionary:
	var journal: Array = state.get("calendar",{}).get("commands",[])
	var revision: int = int(entry.revision)
	if revision < 1 or revision > journal.size():
		return {}
	var cmd: Dictionary = journal[revision-1]
	var p: Dictionary = cmd.payload
	if cmd.type != "trade" or cmd.action_id != entry.event_id or p.get("visit_id") != entry.visit_id or p.get("item_id") != item_id or not Receipt.matches_receipt(state,entry.event_id,"trade",p,revision):
		return {}
	var records: Array = Deck.row_for(state,entry.visit_id,item_id).presented
	var disclosed: Array = []
	var direct: bool = false
	for speech: Dictionary in records:
		var id: String = speech.presentation_id
		var rev: int = Receipt.receipt_revision(state,id)
		if rev < 1 or rev >= revision or rev > journal.size():
			continue
		var event: Dictionary = journal[rev-1]
		var q: Dictionary = event.payload
		if event.type != Deck.ACTION or event.action_id != id or q.get("visit_id") != entry.visit_id or q.get("item_id") != item_id or q.get("op") not in ["present","present_direct","present_observation","withdraw"] or not Receipt.matches_receipt(state,id,Deck.ACTION,q,rev):
			continue
		direct = direct or q.op in ["present_direct","present_observation","withdraw"]
		disclosed.append(speech.duplicate(true))
	# A blank-card transaction using the new offer contract has a valid empty sheet.
	if not direct and not offer.is_empty():
		var offer_rev: int = int(offer.revision)
		if offer_rev > 0 and offer_rev < revision:
			var offer_command: Dictionary = journal[offer_rev-1]
			direct = offer_command.get("payload",{}).get("basis_version") == "current_public_v1"
	if not direct:
		return {}
	var sheet: Dictionary = {"transaction_id":entry.event_id,"revision":revision,"offer_id":offer.get("offer_id"),"amounts":entry.amounts.duplicate(true),"statements":disclosed,"current_ids":Deck.public_basis(disclosed),"observations":_historical_observations(state,disclosed,entry.visit_id,item_id,revision)}
	if offer.has("quality_condition"):
		sheet["quality_condition"] = offer.quality_condition.duplicate(true)
		for fact: Dictionary in offer.get("observations",[]):
			if fact.evidence_id!=offer.quality_condition.evidence_id:
				continue
			var present: bool = false
			for existing: Dictionary in sheet.observations:
				if existing.evidence_id==fact.evidence_id:
					present=true
			if not present:
				sheet.observations.append(fact.duplicate(true))
	return sheet

static func _historical_observations(state: Dictionary,statements: Array,visit_id: String,item_id: String,before_revision: int) -> Array:
	var observations: Array = []
	var seen: Array = []
	for speech: Dictionary in statements:
		for id: String in speech.argument.evidence_ids:
			if id in seen:
				continue
			seen.append(id)
			var saved: Dictionary = Retention.records(state).get(id,{})
			var fact: Dictionary = saved.get("record",{})
			var fact_revision: int = Receipt.receipt_revision(state,id)
			if saved.get("visit_id") != visit_id or fact.get("item_id") != item_id or fact.get("observer_id") != "player" or fact_revision < 1 or fact_revision >= before_revision or Receipt.receipt_type(state,id) != "inspect_subject":
				continue
			var public_fact: Dictionary = Evidence.public_view(fact,fact.get("dependent_field_versions",{}),item_id)
			if public_fact.is_empty() or public_fact.is_claim:
				continue
			public_fact.erase("current")
			observations.append(public_fact)
	return observations

static func _bound_offer(state: Dictionary,entry: Dictionary,item_id: String) -> Dictionary:
	var journal: Array = state.get("calendar",{}).get("commands",[])
	var revision: int = int(entry.revision)
	if revision < 1 or revision > journal.size():
		return {}
	var command: Dictionary = journal[revision-1]
	var p: Dictionary = command.payload
	if command.type!="trade" or command.action_id!=entry.event_id or p.get("visit_id")!=entry.visit_id or p.get("item_id")!=item_id or not Rules.identifier(p.get("offer_id")) or not Receipt.matches_receipt(state,entry.event_id,"trade",p,revision):
		return {}
	var rows: Array = state.calendar.get("appraisal_offers",{}).get(entry.visit_id,[])
	for offer: Dictionary in rows:
		if offer.offer_id!=p.offer_id or not offer.accepted or offer.item_id!=item_id or offer.visit_id!=entry.visit_id or offer.currency!=p.currency or offer.amount!=p.amount or offer.revision>=revision or entry.amounts.get(offer.currency)!=offer.amount:
			continue
		if Receipt.receipt_revision(state,offer.offer_id)!=offer.revision or Receipt.receipt_type(state,offer.offer_id)!="subject_price_offer":
			continue
		var sources: Array = offer.presentations.duplicate(true)
		if offer.has("quality_condition"):
			sources.append({"argument":{"evidence_ids":[offer.quality_condition.evidence_id]}})
		var observations: Array = _historical_observations(state,sources,entry.visit_id,item_id,int(offer.revision))
		var result: Dictionary = {"offer_id":offer.offer_id,"revision":offer.revision,"currency":offer.currency,"amount":offer.amount,"presentations":offer.presentations.duplicate(true),"observations":observations}
		if offer.has("quality_condition"):
			result["quality_condition"] = offer.quality_condition.duplicate(true)
		return result
	return {}

## Only actual player-authored workshop events. Journal and receipt bind
## identity and operation even after receipt compaction. No synthetic timestamps.
static func _work_row(state: Dictionary,e: Dictionary,item_id: String) -> Dictionary:
	var rev: int = int(e.revision)
	var journal: Array = state.get("calendar",{}).get("commands",[])
	if rev < 1 or rev > journal.size() or e.type not in ["attach","detach","restore_item","discard","replace_component","clean_exterior"] or item_id not in e.item_ids:
		return {}
	var cmd: Dictionary = journal[rev-1]
	var p: Dictionary = cmd.payload
	if cmd.action_id!=e.event_id or cmd.type!=e.type or p.get("actor")!="player" or not Receipt.matches_receipt(state,e.event_id,e.type,p,rev):
		return {}
	var row: Dictionary = {"event_id":e.event_id,"revision":rev,"kind":e.type}
	match e.type:
		"attach","detach":
			if e.item_ids!=[p.get("root_id"),p.get("child_id")]:
				return {}
			row["role"]="root" if p.root_id==item_id else "child"
			row["related_item_id"]=p.child_id if p.root_id==item_id else p.root_id
		"replace_component":
			if e.item_ids!=[p.get("root_id"),p.get("old_child_id"),p.get("child_id")]:
				return {}
			row["role"]="root" if p.root_id==item_id else ("outgoing" if p.old_child_id==item_id else "incoming")
			row["root_id"]=p.root_id
			row["old_child_id"]=p.old_child_id
			row["child_id"]=p.child_id
		"clean_exterior":
			if e.item_ids!=[p.get("item_id")]:
				return {}
		"restore_item":
			if e.item_ids!=[p.get("item_id")]:
				return {}
			row["expense"]=e.expenses.duplicate(true)
		"discard":
			if e.item_ids!=p.get("confirmed_ids") or p.get("item_id") not in e.item_ids:
				return {}
			row["group_size"]=e.item_ids.size()
			row["loss"]=e.basis.duplicate(true) if e.item_ids.size()==1 else null
	return row

## Recent unique player-traded or personally worked IDs. No current external
## ownership, location, unacted-on specimen or inferred past.
static func calendar_index(state: Dictionary) -> Dictionary:
	var recent: Dictionary={}
	for e: Dictionary in state.get("ledger",[]):
		if "player" not in [e.from,e.to]:
			continue
		for id: String in e.item_ids:
			recent[id]=maxi(int(recent.get(id,0)),int(e.revision))
	for e: Dictionary in state.get("object_events",[]):
		for id: String in e.item_ids:
			if not _work_row(state,e,id).is_empty():
				recent[id]=maxi(int(recent.get(id,0)),int(e.revision))
	if state.get("calendar",{}).has("merchant_contracts"):
		var indexed:Dictionary={}
		for event:Dictionary in state.calendar.merchant_contracts.get("events",[]):
			var item_id:String=str(event.get("item_id",""))
			if not Rules.identifier(item_id) or indexed.has(item_id):
				continue
			indexed[item_id]=true
			for record:Dictionary in Merchant.item_records(state,item_id):
				recent[item_id]=maxi(int(recent.get(item_id,0)),int(record.revision))
	var ids: Array=recent.keys()
	ids.sort_custom(func(a: String,b: String) -> bool:
		return a<b if recent[a]==recent[b] else recent[a]>recent[b])
	var items: Array=[]
	for id: String in ids.slice(0,DISPLAY_LIMIT):
		items.append({"item_id":id,"history":calendar_history(state,id)})
	return {"items":items,"omitted":ids.size()-items.size()}
