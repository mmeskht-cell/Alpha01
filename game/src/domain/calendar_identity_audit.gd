extends RefCounted
## Private engineering audit, NOT a live state or player DTO.
const Rules=preload("res://src/domain/value_rules.gd")
const Registry=preload("res://src/domain/dormant_registry.gd")
const Tracking=preload("res://src/domain/selective_tracking.gd")
const Receipt=preload("res://src/domain/receipt_primitives.gd")

static func fail(reason:String)->Dictionary:
	return {"ok":false,"error":reason}

static func _ref(index:Dictionary,id:Variant,live:bool=false)->bool:
	return Rules.identifier(id) and index.has(id) and (not live or index[id]=="active")

static func _subject(full:Dictionary,index:Dictionary,visit:String,item:Variant)->bool:
	return _ref(index,item) and full.visits.has(visit) and full.visits[visit].prices.has(item)

static func _evidence(c:Dictionary,visit:String,item:String,ids:Array)->bool:
	for id:Variant in ids:
		var row:Dictionary=c.get("appraisal_observations",{}).get(id,{})
		if row.get("visit_id")!=visit or row.get("record",{}).get("item_id")!=item:
			return false
	return true

static func _action(full:Dictionary,id:Variant,kinds:Array)->bool:
	return Rules.identifier(id) and Receipt.receipt_revision(full,id)>0 and Receipt.receipt_type(full,id) in kinds

static func _argument(full:Dictionary,visit:String,item:String,arg:Dictionary)->bool:
	return _action(full,arg.source_action,["assess_subject","link_subject_evidence"]) and _evidence(full.calendar,visit,item,arg.evidence_ids)

static func audit(partition:Dictionary,authority:RefCounted)->Dictionary:
	# Replay validates exact seed binding, every receipt and the complete state.
	var full:Dictionary=Registry.materialize(partition,authority)
	if full.is_empty() or not full.has("calendar") or not Tracking.valid(partition,full):
		return fail("calendar_replay_or_tracking")
	var c:Dictionary=full.calendar
	var index:Dictionary={}
	for id:String in partition.state.items:
		index[id]="active"
	for id:String in full.tombstones:
		index[id]="terminal"
	for family:Dictionary in partition.dormant.values():
		for id:String in family:
			index[id]="dormant"
	for visit:String in full.visits:
		var v:Dictionary=full.visits[visit]
		var pending:bool=not v.scope.completed and int(v.expires)>=int(full.game_minutes)
		for id:String in v.prices.keys()+v.scope.required_ids:
			if not _ref(index,id,pending):
				return fail("visit_item")
	for entry:Dictionary in full.ledger:
		for id:String in entry.item_ids+entry.root_ids:
			if not _ref(index,id):
				return fail("ledger_item")
	for entry:Dictionary in full.object_events:
		for id:String in entry.item_ids:
			if not _ref(index,id):
				return fail("work_item")
	for entry:Dictionary in full.knowledge.values():
		if not _ref(index,entry.item_id):
			return fail("knowledge_item")
	for entry:Dictionary in full.get("component_hypotheses",{}).values():
		if not _ref(index,entry.item_id):
			return fail("hypothesis_item")
	var jobs:Dictionary=c.get("services",{}).get("jobs",{})
	for job:Dictionary in jobs.values():
		var id:String=job.terms.item_id
		var live:bool=job.status in ["offered","accepted","complete"]
		if not _ref(index,id,live):
			return fail("service_item")
		if live:
			for member:String in full.items:
				if full.items[member].parent_id==id and not _ref(index,member,true):
					return fail("service_family")
	for visit:String in c.get("services",{}).get("visits",{}):
		if not jobs.has(c.services.visits[visit].job_id):
			return fail("service_visit")
	var active:String=c.get("queue",{}).get("active","")
	if not active.is_empty() and not full.visits.has(active) and not c.get("services",{}).get("visits",{}).has(active):
		return fail("queue_visit")
	for id:String in c.get("appraisal_observations",{}):
		var row:Dictionary=c.appraisal_observations[id]
		if not _subject(full,index,row.visit_id,row.record.item_id) or not _action(full,id,["inspect_subject"]):
			return fail("observation")
	for visit:String in c.get("appraisal_assessments",{}):
		var row:Dictionary=c.appraisal_assessments[visit]
		if not _subject(full,index,visit,row.item_id) or not _action(full,row.assessment.source_action,["assess_subject","link_subject_evidence"]):
			return fail("assessment")
		for ids:Array in row.assessment.links.values():
			if not _evidence(c,visit,row.item_id,ids):
				return fail("assessment_evidence")
	for visit:String in c.get("appraisal_decks",{}):
		var row:Dictionary=c.appraisal_decks[visit]
		if not _subject(full,index,visit,row.item_id):
			return fail("deck_item")
		for card:Dictionary in row.deck.ready.values():
			if visit!=active or not _ref(index,row.item_id,true) or not _action(full,card.card_id,["subject_deck_action"]) or not _argument(full,visit,row.item_id,card.argument):
				return fail("ready_card")
		for speech:Dictionary in row.deck.presented:
			if not _action(full,speech.presentation_id,["subject_deck_action"]) or not _argument(full,visit,row.item_id,speech.argument):
				return fail("presented_card")
	for visit:String in c.get("appraisal_offers",{}):
		for offer:Dictionary in c.appraisal_offers[visit]:
			if not _subject(full,index,visit,offer.item_id) or not _action(full,offer.offer_id,["subject_price_offer"]):
				return fail("offer_item")
			var presented:Array=c.get("appraisal_decks",{}).get(visit,{}).get("deck",{}).get("presented",[])
			if offer.presented_ids.size()!=offer.presentations.size():
				return fail("offer_snapshot")
			for i:int in range(offer.presentations.size()):
				var speech:Dictionary=offer.presentations[i]
				if speech.presentation_id!=offer.presented_ids[i] or speech not in presented or not _argument(full,visit,offer.item_id,speech.argument):
					return fail("offer_presentation")
	var supplies:Dictionary={}
	for id:String in c.get("contracts",{}).get("supplies",{}):
		var row:Dictionary=c.contracts.supplies[id]
		if index.has(id) or not c.contracts.rows.has(row.contract) or c.profile.contracts[row.contract].supply_id!=id:
			return fail("contract_supply")
		supplies[id]=row.status
	for row:Dictionary in c.get("contracts",{}).get("settlements",[]):
		if not supplies.has(row.supply_id) or c.contracts.supplies[row.supply_id].contract!=row.contract_id:
			return fail("contract_settlement")
	var doses:Dictionary={}
	for id:String in c.get("medicine",{}).get("stock",{}):
		doses[id]=c.medicine.stock[id].status
	for offer:Dictionary in c.get("medicine",{}).get("contracts",{}).values():
		for tranche:Dictionary in offer.tranches:
			if not doses.has(tranche.id):
				return fail("medicine_tranche")
	return {"ok":true,"items":index,"contract_supplies":supplies,"medicine_doses":doses,"binding":c.binding,"revision":full.revision}

static func begin(authority:RefCounted)->Dictionary:
	var p:Dictionary=Registry.begin(authority.snapshot(),authority)
	return p if not p.is_empty() and audit(p,authority).ok else {}

static func sleep(partition:Dictionary,root:String,authority:RefCounted)->Dictionary:
	if not audit(partition,authority).ok:
		return {}
	var p:Dictionary=Registry.sleep_family(partition,root,authority)
	return p if not p.is_empty() and audit(p,authority).ok else {}

static func wake(partition:Dictionary,root:String,authority:RefCounted)->Dictionary:
	if not audit(partition,authority).ok:
		return {}
	var p:Dictionary=Registry.wake_family(partition,root,authority)
	return p if not p.is_empty() and audit(p,authority).ok else {}
