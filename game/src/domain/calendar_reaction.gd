extends RefCounted
## P4 representative authored world response, same replay authority.
## An actual paid return is the sole positive cause in this pilot.
## Personal contacts are not automatically official organization business.
const Rules=preload("res://src/domain/value_rules.gd")
const Clock=preload("res://src/domain/business_clock.gd")
const Receipt=preload("res://src/domain/receipt_primitives.gd")
const MAX_RULES:int=8

static func seed(s:Dictionary,p:Dictionary)->Dictionary:
	var rules:Variant=p.get("reaction_rules")
	if not rules is Dictionary or rules.is_empty() or rules.size()>MAX_RULES or not s.calendar.has("services") or not s.calendar.has("queue"):
		return {}
	var jobs:Dictionary=s.calendar.services.jobs
	var seen_jobs:Dictionary={}
	var seen_visits:Dictionary={}
	var seen_days:Dictionary={}
	for id:Variant in rules:
		var r:Variant=rules[id]
		if p.get("content_version") in ["demo7-integrated-2","demo7-integrated-3"] and r is Dictionary and r.has("trade_visit"):
			if not Rules.identifier(id) or not Rules.keys(r,["day","trade_visit","opportunity_id","local_public","organization_id"]) or not Rules.integer(r.day,2,p.day_ids.size()) or not Rules.identifier(r.trade_visit) or not s.visits.has(r.trade_visit) or not Rules.identifier(r.opportunity_id) or not s.calendar.services.visits.has(r.opportunity_id) or not r.local_public is bool or r.organization_id!="" or seen_days.has(r.day):
				return {}
			var trade:Dictionary=s.visits[r.trade_visit]
			var opportunity:Dictionary=s.calendar.services.visits[r.opportunity_id]
			if trade.seller!="player" or trade.scope.purpose!="sale" or trade.expires>=(int(r.day)-1)*Clock.DAY_MINUTES or opportunity.kind!="offer" or opportunity.day!=r.day or jobs[opportunity.job_id].terms.customer!=trade.buyer:
				return {}
			seen_days[r.day]=true
			continue
		if not Rules.identifier(id) or not Rules.keys(r,["day","service_id","opportunity_id","local_public","organization_id"]):
			return {}
		if not Rules.integer(r.day,2,p.day_ids.size()) or not Rules.identifier(r.service_id) or not jobs.has(r.service_id) or seen_jobs.has(r.service_id) or seen_days.has(r.day) or not Rules.identifier(r.opportunity_id) or seen_visits.has(r.opportunity_id) or not s.visits.has(r.opportunity_id) or not r.local_public is bool or not r.organization_id is String or (not r.organization_id.is_empty() and not Rules.identifier(r.organization_id)):
			return {}
		var job:Dictionary=jobs[r.service_id]
		var v:Dictionary=s.visits[r.opportunity_id]
		var first_return:Dictionary=s.calendar.services.visits[job.terms.return_ids[0]]
		if r.day<=first_return.day or v.scope.kind!="ordinary" or v.scope.purpose!="sale" or v.seller!="player" or v.buyer!=job.terms.customer or v.prices.size()!=1 or r.opportunity_id not in p.visit_days[p.day_ids[int(r.day)-1]]:
			return {}
		var item:String=v.prices.keys()[0]
		if not s.items.has(item) or s.items[item].owner_id!="player" or not s.items[item].parent_id.is_empty():
			return {}
		seen_jobs[r.service_id]=true
		seen_visits[r.opportunity_id]=true
		seen_days[r.day]=true
	return {"local":0,"organizations":{},"contacts":{},"links":{},"events":{},"market":"ordinary"}

## Called only at the following opening, after real receipts already exist.
static func morning(s:Dictionary,action:String)->void:
	if not s.calendar.has("reaction"):
		return
	var w:Dictionary=s.calendar.reaction
	for id:String in s.calendar.profile.reaction_rules:
		var r:Dictionary=s.calendar.profile.reaction_rules[id]
		if r.day!=Clock.day_index(int(s.game_minutes)) or w.events.has(id):
			continue
		var cause:String=""
		var contact:String=""
		var fulfilled:bool=false
		var external:String="market_disruption"
		if r.has("trade_visit"):
			external="clinic_supply_disruption"
			contact=s.visits[r.trade_visit].buyer
			for e:Dictionary in s.ledger:
				if e.visit_id==r.trade_visit and Receipt.receipt_type(s,e.event_id)=="trade":
					cause=e.event_id
					fulfilled=true
					break
		else:
			var job:Dictionary=s.calendar.services.jobs[r.service_id]
			contact=job.terms.customer
			cause=job.return_action
			fulfilled=job.status=="delivered" and job.paid==job.terms.fee and Receipt.receipt_type(s,cause)=="calendar_deliver_service"
		# Same independent disruption in both branches. Actual service provides
		# one authored limited commercial recovery path, not a universal score.
		w.market="limited_service" if fulfilled else "interrupted"
		w.events[id]={"day":r.day,"external_event":external,"cause":cause if fulfilled else "","opening_action":action,"result":w.market,"opportunity_id":r.opportunity_id if fulfilled else ""}
		if fulfilled:
			if not w.contacts.has(contact):
				w.contacts[contact]=[]
			w.contacts[contact].append(cause)
			if r.local_public:
				w.local=mini(20,int(w.local)+1)
			if not r.organization_id.is_empty():
				w.organizations[r.organization_id]=mini(20,int(w.organizations.get(r.organization_id,0))+1)
			w.links[r.opportunity_id]={"contact":contact,"cause":cause,"event_id":id,"day":r.day}

static func _rule_for(s:Dictionary,visit:String)->Dictionary:
	for r:Dictionary in s.calendar.profile.get("reaction_rules",{}).values():
		if r.opportunity_id==visit:
			return r
	return {}

## A real contact is not a currency. Availability requires actual stock,
## buyer funds, current day, an unconsumed appointment and a causal link.
static func eligible(s:Dictionary,visit:String)->bool:
	var r:Dictionary=_rule_for(s,visit)
	if r.is_empty():
		return true
	var link:Dictionary=s.calendar.get("reaction",{}).get("links",{}).get(visit,{})
	if link.is_empty() or Clock.day_index(int(s.game_minutes))!=link.day or s.calendar.queue.outcomes.has(visit):
		return false
	if r.has("trade_visit"):
		return s.calendar.services.visits.has(visit)
	var v:Dictionary=s.visits[visit]
	var item:Dictionary=s.items.get(v.prices.keys()[0],{})
	if item.is_empty() or item.owner_id!="player" or item.custodian_id!="player" or item.status!="stock" or item.protected or not item.reservation_id.is_empty() or not item.parent_id.is_empty():
		return false
	var price:Dictionary=v.prices.values()[0]
	for currency:String in ["VKC","USD"]:
		if s.wallets[v.buyer][currency]<price[currency]:
			return false
	return true

## Public actual events only. The underlying score, relationship memory,
## exact eligibility formula and future authored candidates stay private.
static func view(s:Dictionary)->Dictionary:
	var result:Dictionary={"news":[]}
	for id:String in s.calendar.get("reaction",{}).get("events",{}):
		var row:Dictionary=s.calendar.reaction.events[id]
		var recovered:bool=row.result=="limited_service"
		var sources:Array=[row.external_event]
		if recovered:
			sources.append(row.cause)
		if row.external_event=="clinic_supply_disruption":
			result.news.append({"article_id":id,"day":row.day,"source":"clinic_notice","certainty":"confirmed","cause_refs":sources,"ko":"위생품 납품으로 진료소 일부 서비스가 재개되었습니다. 후속 정비 의뢰가 접수되었습니다." if recovered else "위생품 공급 차질로 진료소 일부 서비스가 보류되었습니다.","en":"The clinic reopened limited services after the delivery. A repair request is available." if recovered else "Some clinic services remain suspended due to supply disruption."})
			continue
		result.news.append({"article_id":id,"day":row.day,"source":"local_market_notice","certainty":"confirmed","cause_refs":sources,"ko":"시장 운영 차질 속에서 완료된 정비 의뢰를 바탕으로 제한된 거래 협력이 이어졌습니다." if recovered else "시장 운영에 차질이 발생했습니다. 추가 협력은 확인되지 않았습니다.","en":"Market operations were disrupted. A completed repair supported limited commercial cooperation." if recovered else "Market operations were disrupted. No additional cooperation has been confirmed."})
	return result
