extends RefCounted
## Small deterministic event-state bridge: 1-8 fictional districts, authored
## categories, independent shortages and proof-bound local recovery.
## No military power arithmetic, hidden NPC inventory, invented goods, money or
## changes to a negotiated/quoted price. Every gate is content-bound.
const Rules=preload("res://src/domain/value_rules.gd")
const Clock=preload("res://src/domain/business_clock.gd")
const Trace=preload("res://src/domain/world_causal_trace.gd")
const Receipt=preload("res://src/domain/receipt_primitives.gd")
const MAX_REGIONS:int=8
const MAX_EVENTS:int=128
const MAX_GATES:int=128
const STATUSES:Array=["ordinary","strained","limited"]

static func seed_valid(state:Dictionary,profile:Dictionary)->bool:
	var world:Variant=profile.get("regional_world")
	if not Rules.keys(world,["version","regions","events","gates"]) or world.version!=1 or not world.regions is Dictionary or world.regions.is_empty() or world.regions.size()>MAX_REGIONS or not world.events is Dictionary or world.events.size()>MAX_EVENTS or not world.gates is Dictionary or world.gates.size()>MAX_GATES:
		return false
	for region_id:Variant in world.regions:
		var region:Variant=world.regions[region_id]
		if not Rules.identifier(region_id) or not Rules.keys(region,["status"]) or region.status not in STATUSES:
			return false
	for id:Variant in world.events:
		var event:Variant=world.events[id]
		if not Rules.identifier(id) or not Rules.keys(event,["day","region","topic","without_player","with_player","cause_visit","source"]) or not Rules.integer(event.day,2,profile.day_ids.size()) or not world.regions.has(event.region) or not Rules.identifier(event.topic) or event.without_player not in STATUSES or event.with_player not in STATUSES or not event.source in ["local_market_notice","clinic_notice","civilian_rumor"] or not event.cause_visit is String:
			return false
		if not event.cause_visit.is_empty():
			var visit:Dictionary=state.visits.get(event.cause_visit,{})
			if visit.is_empty() or visit.get("scope",{}).get("kind")!="ordinary" or int(visit.expires)>=(int(event.day)-1)*Clock.DAY_MINUTES or "player" not in [visit.seller,visit.buyer]:
				return false
	for visit_id:Variant in world.gates:
		var rule:Variant=world.gates[visit_id]
		if not Rules.identifier(visit_id) or not state.visits.has(visit_id) or not Rules.keys(rule,["event_id","status"]) or not world.events.has(rule.event_id) or rule.status not in STATUSES:
			return false
		if Clock.day_index(int(state.visits[visit_id].opens))!=int(world.events[rule.event_id].day):
			return false
	return true

static func seed(s:Dictionary,profile:Dictionary)->Dictionary:
	if not seed_valid(s,profile):
		return {}
	var status:Dictionary={}
	for region_id:String in profile.regional_world.regions:
		status[region_id]=profile.regional_world.regions[region_id].status
	return {"status":status,"events":{}}

## Called within authoritative morning candidate. An absent action cannot
## promote a shortage to a successful player intervention.
static func morning(s:Dictionary,opening_action:String)->void:
	var model:Dictionary=s.get("calendar",{}).get("profile",{}).get("regional_world",{})
	if model.is_empty() or not s.calendar.has("regional_world"):
		return
	var day:int=Clock.day_index(int(s.game_minutes))
	var ids:Array=model.events.keys()
	ids.sort()
	for id:String in ids:
		var event:Dictionary=model.events[id]
		if event.day!=day or s.calendar.regional_world.events.has(id):
			continue
		var cause:Dictionary=Trace.trade_for_visit(s,event.cause_visit) if not event.cause_visit.is_empty() else {}
		var supported:bool=not cause.is_empty()
		var status:String=event.with_player if supported else event.without_player
		s.calendar.regional_world.events[id]={"day":day,"region":event.region,"topic":event.topic,"source":event.source,
			"status":status,"external_event":id,"cause":str(cause.get("event_id","")),"opening_action":opening_action}
		s.calendar.regional_world.status[event.region]=status

static func event_verified(s:Dictionary,id:String)->Dictionary:
	var actual:Dictionary=s.get("calendar",{}).get("regional_world",{}).get("events",{}).get(id,{})
	if actual.is_empty():
		return {}
	var opening:String=str(actual.get("opening_action",""))
	var revision:int=Receipt.receipt_revision(s,opening)
	var commands:Array=s.calendar.get("commands",[])
	if revision<1 or revision>commands.size():
		return {}
	var cmd:Dictionary=commands[revision-1]
	if cmd.type!="calendar_morning" or cmd.action_id!=opening or not Receipt.matches_receipt(s,opening,"calendar_morning",cmd.payload,revision):
		return {}
	var authored:Dictionary=s.calendar.profile.regional_world.events.get(id,{})
	if authored.is_empty() or actual.get("day")!=authored.day or actual.get("region")!=authored.region or actual.get("topic")!=authored.topic or actual.get("source")!=authored.source or actual.get("external_event")!=id:
		return {}
	var cause:Dictionary=Trace.trade_for_visit(s,authored.cause_visit) if not authored.cause_visit.is_empty() else {}
	var fulfilled:bool=not cause.is_empty()
	if actual.get("cause")!=str(cause.get("event_id","")) or actual.get("status")!=(authored.with_player if fulfilled else authored.without_player):
		return {}
	return actual

static func eligible(s:Dictionary,visit_id:String)->bool:
	var policy:Dictionary=s.get("calendar",{}).get("profile",{}).get("regional_world",{})
	if policy.is_empty() or not policy.gates.has(visit_id):
		return true
	var gate:Dictionary=policy.gates[visit_id]
	var event:Dictionary=event_verified(s,gate.event_id)
	return not event.is_empty() and event.status==gate.status

## Public results only: confirmed known events and verified local response.
## No foresight into unopened days, external owners or NPC private budgets.
static func view(s:Dictionary)->Dictionary:
	var result:Dictionary={"regions":{},"events":[]}
	if not s.get("calendar",{}).has("regional_world"):
		return result
	var events:Dictionary=s.calendar.regional_world.events
	for region_id:String in s.calendar.profile.regional_world.regions:
		result.regions[region_id]=s.calendar.profile.regional_world.regions[region_id].status
	var ids:Array=events.keys()
	ids.sort_custom(func(a:String,b:String)->bool:
		return a<b if events[a].day==events[b].day else events[a].day<events[b].day)
	for id:String in ids:
		var row:Dictionary=event_verified(s,id)
		if row.is_empty():
			continue
		# Rumored events may affect private authored encounters but must never
		# reveal their real source receipt or actual state as confirmed news.
		var rumor:bool=row.source=="civilian_rumor"
		if not rumor:
			result.regions[row.region]=row.status
		var refs:Array=[] if rumor else [id]
		if not rumor and not row.cause.is_empty():
			refs.append(row.cause)
		result.events.append({"event_id":id,"day":row.day,"region":row.region,"topic":row.topic,
			"source":row.source,"certainty":"unconfirmed" if rumor else "confirmed",
			"status":"unverified" if rumor else row.status,"cause_refs":refs})
	return result
