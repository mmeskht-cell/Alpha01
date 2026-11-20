extends RefCounted
## Fixed-term calendar purchase pilot: no new acceptance/discount policy.
## All writes are on GameSession's detached candidate, replay included.
const Rules = preload("res://src/domain/value_rules.gd")
const Claims = preload("res://src/domain/visit_customer_claims.gd")
const Deck = preload("res://src/domain/visit_negotiation_deck.gd")
const Queue = preload("res://src/domain/campaign_visit_queue.gd")
const Visits = preload("res://src/domain/visit_primitives.gd")
const Receipt = preload("res://src/domain/receipt_primitives.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const GridRules = preload("res://src/domain/grid_primitives.gd")
const Observation = preload("res://src/domain/visit_appraisal_observation.gd")
const ACTION: String = "subject_price_offer"
const MAX_OFFERS: int = 3

static func terms(s: Dictionary,visit_id: String,item_id: String) -> Dictionary:
	if not Claims.enabled(s) or not Queue.permits(s,visit_id) or not s.items.has(item_id):
		return {}
	var item: Dictionary = s.items[item_id]
	if not Visits.purchase_open(s,visit_id,item_id,item.owner_id,false):
		return {}
	var v: Dictionary = s.visits[visit_id]
	var price: Dictionary = v.prices[item_id]
	var currency: String = "VKC" if price.VKC > 0 and price.USD == 0 else ("USD" if price.USD > 0 and price.VKC == 0 else "")
	if currency.is_empty():
		return {}
	return {"currency":currency,"amount":price[currency]}

static func opening_radio(s:Dictionary,visit:String)->bool:
	return s.get("calendar",{}).get("profile",{}).get("content_version") in ["demo7-integrated-2","demo7-integrated-3"] and visit=="visit_g01"

static func rows(s: Dictionary,visit_id: String) -> Array:
	return s.calendar.get("appraisal_offers",{}).get(visit_id,[]).duplicate(true)

## A seller accepts a disclosed functional reading as an explicit condition
## of this purchase only. Not a durability promise or automatic refund.
static func quality_option(s: Dictionary,visit_id: String,item_id: String) -> Dictionary:
	for fact: Dictionary in Observation.view(s,visit_id,item_id):
		if fact.current and not fact.is_claim and fact.observation_key in ["R001.function","function_status"] and fact.observed_value in ["serviceable","inoperable"] and Receipt.receipt_type(s,fact.evidence_id) == "inspect_subject" and Receipt.receipt_revision(s,fact.evidence_id) > 0:
			return {"kind":"function_at_trade","evidence_id":fact.evidence_id,"observed_value":fact.observed_value}
	return {}

static func apply(s: Dictionary,p: Dictionary,action_id: String) -> String:
	var fields: Array = ["visit_id","item_id","currency","amount","presented_ids"]
	if p.has("basis_version"):
		fields.append("basis_version")
		if p.basis_version != "current_public_v1":
			return "subject_offer_basis_version"
	if p.has("quality_evidence_id"):
		fields.append("quality_evidence_id")
		if not p.has("basis_version") or not Rules.identifier(p.quality_evidence_id):
			return "subject_offer_quality_shape"
	if not Rules.keys(p,fields) or not Rules.identifier(p.visit_id) or not Rules.identifier(p.item_id) or not Rules.integer(p.amount,1) or not p.presented_ids is Array or p.presented_ids.size() > Deck.MAX_PRESENTED:
		return "subject_offer_shape"
	var fixed: Dictionary = terms(s,p.visit_id,p.item_id)
	if fixed.is_empty() or p.currency != fixed.currency:
		return "subject_offer_permission"
	var quality: Dictionary = {}
	if p.has("quality_evidence_id"):
		quality = quality_option(s,p.visit_id,p.item_id)
		if quality.is_empty() or quality.evidence_id != p.quality_evidence_id:
			return "subject_offer_quality_evidence"
	var history: Array = rows(s,p.visit_id)
	if history.size() >= MAX_OFFERS:
		return "subject_offer_limit"
	if not Claims.demo3(s):
		for previous: Dictionary in history:
			if previous.amount == p.amount and previous.get("quality_condition",{}) == quality:
				return "subject_offer_duplicate"
	var available: Dictionary = {}
	var presented: Array = Deck.row_for(s,p.visit_id,p.item_id).presented
	var current_only: bool = p.has("basis_version")
	# Legacy offers replay unchanged before withdrawals existed. Once a visit
	# contains one, no old payload shape may revive withdrawn assertions.
	for speech: Dictionary in presented:
		if speech.has("withdraws_presentation_id"):
			current_only = true
	var current_ids: Array = Deck.public_basis(presented)
	for speech: Dictionary in presented:
		if not speech.has("withdraws_presentation_id") and (not current_only or speech.presentation_id in current_ids):
			available[speech.presentation_id] = speech
	var references: Array = []
	var seen: Array = []
	for id: Variant in p.presented_ids:
		if not Rules.identifier(id) or id in seen or not available.has(id) or Receipt.receipt_revision(s,id) < 1 or Receipt.receipt_type(s,id) != Deck.ACTION:
			return "subject_offer_reference"
		seen.append(id)
		references.append(available[id].duplicate(true))
	var accepted:bool=p.amount==fixed.amount
	if Claims.demo3(s):
		var policy:Dictionary=Claims.settlement(p.visit_id)
		var qualified:bool=not policy.is_empty() and Claims.supported_wear(s,p.visit_id,p.item_id,references)
		for previous:Dictionary in history:
			if previous.amount==p.amount and previous.get("quality_condition",{})==quality and Claims.supported_wear(s,p.visit_id,p.item_id,previous.presentations)==qualified:
				return "subject_offer_duplicate"
		if not policy.is_empty():
			accepted=int(p.amount)>=int(policy.floor)-(int(policy.discount) if qualified else 0) and int(p.amount)<=int(policy.ask)
			if accepted:
				s.visits[p.visit_id].prices[p.item_id][p.currency]=int(p.amount)
	elif opening_radio(s,p.visit_id):
		var supported:bool=false
		for speech:Dictionary in references:
			for id:String in speech.argument.evidence_ids:
				var record:Dictionary=s.calendar.appraisal_observations.get(id,{}).get("record",{})
				if record.get("item_id")==p.item_id and record.get("observation_key") in ["R001.wear","R001.casing_detail"] and speech.argument.slot_id=="appearance_id":
					supported=true
		accepted=int(p.amount)>= (100 if supported else 110) and int(p.amount)<=125
		if accepted:
			s.visits[p.visit_id].prices[p.item_id][p.currency]=int(p.amount)
	var offer_row: Dictionary = {"offer_id":action_id,"visit_id":p.visit_id,"item_id":p.item_id,"currency":p.currency,"amount":int(p.amount),"accepted":accepted,"presented_ids":seen,"presentations":references,"revision":int(s.revision)+1}
	if not quality.is_empty():
		offer_row["quality_condition"] = quality
	history.append(offer_row)
	if not s.calendar.has("appraisal_offers"):
		s.calendar["appraisal_offers"] = {}
	s.calendar.appraisal_offers[p.visit_id] = history
	return ""

## A raw legacy trade remains legal only if no explicit offer was made.
## Once offers exist, use the latest accepted receipt, never a UI-derived discount.
static func trade_error(s: Dictionary,p: Dictionary) -> String:
	var visit: Variant = p.get("visit_id")
	if not Rules.identifier(visit):
		return "subject_offer_visit" if p.has("offer_id") else ""
	var history: Array = rows(s,visit)
	if history.is_empty():
		# Frozen required-offer set is a replay/authorization guard, not a
		# price fallback. Missing policy cannot enable a raw trade shortcut.
		return "subject_offer_missing" if p.has("offer_id") or opening_radio(s,visit) or (Claims.demo3(s) and Claims.DEMO_TERMS.has(visit)) else ""
	var latest: Dictionary = history.back()
	if not latest.accepted or p.get("offer_id") != latest.offer_id or p.get("item_id") != latest.item_id or p.get("currency") != latest.currency or p.get("amount") != latest.amount:
		return "subject_offer_not_accepted"
	if terms(s,visit,latest.item_id).is_empty():
		return "subject_offer_permission"
	if latest.has("quality_condition") and latest.quality_condition != quality_option(s,visit,latest.item_id):
		return "subject_offer_quality_changed"
	return ""

static func view(s: Dictionary,visit: String,item: String) -> Dictionary:
	var fixed: Dictionary = terms(s,visit,item)
	if fixed.is_empty():
		return {}
	var history: Array = rows(s,visit)
	return {"currency":fixed.currency,"asking":int(Claims.settlement(visit).ask) if Claims.demo3(s) and not Claims.settlement(visit).is_empty() else (125 if opening_radio(s,visit) else fixed.amount),"offers":history,"remaining":MAX_OFFERS-history.size(),"can_offer":history.size()<MAX_OFFERS,"quality_option":quality_option(s,visit,item),"accepted_offer_id":history.back().offer_id if not history.is_empty() and history.back().accepted else null}

## Read-only placement geometry. No reservation or mutation.
## This preview intentionally exposes only root inventories owned by the buyer.
static func checkout(s: Dictionary,defs: Dictionary,visit: String,item: String) -> Dictionary:
	var offer: Dictionary = view(s,visit,item)
	if offer.is_empty() or offer.accepted_offer_id == null:
		return {}
	var accepted: Dictionary = offer.offers.back()
	var v: Dictionary = s.visits[visit]
	var footprint: Array = Objects.footprint(s,defs,item)
	var grids: Array = []
	var grid_ids: Array = s.inventories.keys()
	grid_ids.sort()
	for id: String in grid_ids:
		var storage: Dictionary = s.inventories[id]
		if not storage.host_item.is_empty() or not Objects.destination_accessible(s,id,v.buyer,v.buyer):
			continue
		var placements: Array = []
		for owned_id: String in s.items:
			var row: Dictionary = s.items[owned_id]
			if row.inventory != id or not row.parent_id.is_empty():
				continue
			var size: Array = Objects.footprint(s,defs,owned_id)
			placements.append({"item_id":owned_id,"x":row.x,"y":row.y,"width":size[0],"height":size[1],"rotated":row.rotated})
		var orientations: Array = [false] if footprint[0] == footprint[1] else [false,true]
		var options: Array = []
		for rotated: bool in orientations:
			for y: int in range(int(storage.height)):
				for x: int in range(int(storage.width)):
					var trial: Array = placements.duplicate()
					trial.append({"item_id":item,"x":x,"y":y,"width":footprint[0],"height":footprint[1],"rotated":rotated})
					if GridRules.validate(storage.width,storage.height,trial).ok:
						options.append({"inventory":id,"x":x,"y":y,"rotated":rotated})
		grids.append({"inventory":id,"width":storage.width,"height":storage.height,"orientations":orientations,"options":options})
	var result: Dictionary = {"offer_id":accepted.offer_id,"amount":accepted.amount,"currency":accepted.currency,"seller":v.seller,"buyer":v.buyer,"balance":s.wallets[v.buyer][accepted.currency],"affordable":s.wallets[v.buyer][accepted.currency]>=accepted.amount,"footprint":footprint,"grids":grids}
	if accepted.has("quality_condition"):
		result["quality_condition"] = accepted.quality_condition.duplicate(true)
	return result
