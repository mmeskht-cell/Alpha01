extends RefCounted
## Optional read-only 42-day authored future-event projection.
## No second narrative authority, economic mutation or ending execution.
const Rules=preload("res://src/domain/value_rules.gd")
const Clock=preload("res://src/domain/business_clock.gd")
const Trace=preload("res://src/domain/world_causal_trace.gd")
const Receipt=preload("res://src/domain/receipt_primitives.gd")

static func valid(s:Dictionary,p:Dictionary)->bool:
	var f:Variant=p.get("future_events")
	if p.get("id")!="campaign_42" or not Rules.keys(f,["version","events","endings"]) or f.version!=1 or not f.events is Dictionary or f.events.is_empty() or f.events.size()>16 or not f.endings is Dictionary or f.endings.size()>8:
		return false
	var days:Dictionary={}
	for id:Variant in f.events:
		var row:Variant=f.events[id]
		if not Rules.identifier(id) or not row is Dictionary or not Rules.integer(row.get("day"),2,42) or not Rules.identifier(row.get("trade_key")) or not Rules.identifier(row.get("alternative_key")):
			return false
		if row.has("visit_id"):
			if not Rules.keys(row,["day","visit_id","trade_key","alternative_key"]) or not Rules.identifier(row.visit_id) or not s.visits.has(row.visit_id) or s.visits[row.visit_id].get("scope",{}).get("kind")!="ordinary" or int(row.day)<=Clock.day_index(int(s.visits[row.visit_id].expires)):
				return false
		else:
			if not Rules.keys(row,["day","prior_event","requires","trade_key","alternative_key"]) or not Rules.identifier(row.prior_event) or row.requires!="traded" or not f.events.has(row.prior_event):
				return false
			var prior:Dictionary=f.events[row.prior_event]
			if not Rules.integer(prior.get("day"),2,42) or int(prior.day)>=int(row.day):
				return false
		days[id]=int(row.day)
	for id:Variant in f.endings:
		var row:Variant=f.endings[id]
		if not Rules.identifier(id) or not Rules.keys(row,["day","event_id","requires","label_key"]) or not Rules.integer(row.day,2,42) or not Rules.identifier(row.event_id) or not days.has(row.event_id) or row.requires not in ["traded","alternative","declined","missed"] or not Rules.identifier(row.label_key) or int(row.day)<=int(days[row.event_id]):
			return false
	return true

static func _decline(s:Dictionary,visit:String)->String:
	var commands:Array=s.get("calendar",{}).get("commands",[])
	for i:int in range(commands.size()):
		var c:Dictionary=commands[i]
		if c.get("type")=="calendar_decline_visit" and c.get("payload",{}).get("visit_id")==visit and Receipt.matches_receipt(s,c.get("action_id"),"calendar_decline_visit",c.payload,i+1):
			return str(c.action_id)
	return ""

static func _outcome(s:Dictionary,visit:String)->Dictionary:
	var o:String=str(s.get("calendar",{}).get("queue",{}).get("outcomes",{}).get(visit,""))
	if o=="traded":
		var paid:Dictionary=Trace.trade_for_visit(s,visit)
		if not paid.is_empty():
			return {"outcome":"traded","cause_action":paid.event_id,"certainty":"confirmed"}
	if o=="declined":
		var receipt:String=_decline(s,visit)
		if not receipt.is_empty():
			return {"outcome":"declined","cause_action":receipt,"certainty":"confirmed"}
	if o in ["missed","not_applicable"]:
		return {"outcome":o,"cause_action":"","certainty":"recorded_visit_outcome"}
	return {}

static func view(s:Dictionary)->Dictionary:
	var f:Dictionary=s.get("calendar",{}).get("profile",{}).get("future_events",{})
	var result:Dictionary={"events":[],"ending_candidates":[]}
	if f.is_empty():
		return result
	var today:int=Clock.day_index(int(s.game_minutes))
	var rows:Dictionary={}
	var ids:Array=f.events.keys()
	ids.sort_custom(func(a:String,b:String)->bool:
		return str(a)<str(b) if int(f.events[a].day)==int(f.events[b].day) else int(f.events[a].day)<int(f.events[b].day))
	for id:String in ids:
		var rule:Dictionary=f.events[id]
		if int(rule.day)>today:
			continue
		var cause:Dictionary={}
		if rule.has("visit_id"):
			cause=_outcome(s,rule.visit_id)
		else:
			var prior:Dictionary=rows.get(rule.prior_event,{})
			if not prior.is_empty():
				cause={"outcome":"traded" if prior.outcome==rule.requires else "alternative",
					"cause_action":str(prior.get("cause_action","")),"certainty":"derived"}
		if cause.is_empty():
			continue
		var row:Dictionary={"event_id":id,"day":int(rule.day),"outcome":cause.outcome,
			"text_key":rule.trade_key if cause.outcome=="traded" else rule.alternative_key,
			"cause_action":str(cause.cause_action),"certainty":cause.certainty}
		rows[id]=row
		result.events.append(row.duplicate(true))
	var ending_ids:Array=f.endings.keys()
	ending_ids.sort()
	for id:String in ending_ids:
		var rule:Dictionary=f.endings[id]
		var actual:Dictionary=rows.get(rule.event_id,{})
		if int(rule.day)<=today and not actual.is_empty() and actual.outcome==rule.requires:
			result.ending_candidates.append({"hook_id":id,"source_event":rule.event_id,
				"label_key":rule.label_key,"candidate_only":true})
	return result
