extends RefCounted
## A1c1: finite predeclared visit admission, independent of day-one adapters.
## No new item, money, contract, or narrative generation. Candidate-only mutation.
const Rules = preload("res://src/domain/value_rules.gd")
const Clock = preload("res://src/domain/business_clock.gd")
const Visits = preload("res://src/domain/visit_primitives.gd")
const Service = preload("res://src/domain/campaign_service.gd")
const Reaction = preload("res://src/domain/calendar_reaction.gd")
const Regional=preload("res://src/domain/regional_world_state.gd")
const Npc=preload("res://src/domain/npc_continuity.gd")
const Market=preload("res://src/domain/regional_market_flow.gd")
const VisitorSlots=preload("res://src/domain/npc_visit_slots.gd")
const ACTIONS: Array = ["calendar_next_visit", "calendar_decline_visit"]

static func seed(state: Dictionary, profile: Dictionary, service_visits: Dictionary = {}) -> Dictionary:
	var schedule: Variant = profile.get("visit_days")
	if not schedule is Dictionary or schedule.size() != profile.day_ids.size():
		return {}
	var seen: Dictionary = {}
	for index: int in range(profile.day_ids.size()):
		var ids: Variant = schedule.get(profile.day_ids[index])
		if not ids is Array:
			return {}
		var start: int = index * Clock.DAY_MINUTES
		for id: Variant in ids:
			if not Rules.identifier(id) or seen.has(id) or (not state.visits.has(id) and not service_visits.has(id)):
				return {}
			if service_visits.has(id):
				if service_visits[id].day != index + 1:
					return {}
				seen[id] = true
				continue
			var v: Variant = state.visits[id]
			if not v is Dictionary or not v.get("scope") is Dictionary or v.scope.get("completed") != false or v.get("opens") != start or v.get("expires") != start + Clock.BUSINESS_MINUTES or not v.get("prices") is Dictionary:
				return {}
			if v.scope.get("kind") == "ordinary" and v.prices.size() != 1:
				return {}
			seen[id] = true
	var carry:Dictionary=profile.get("carryover_returns",{})
	for id:String in carry:
		if seen.has(id) or not service_visits.has(id) or service_visits[id].kind!="return" or service_visits[id].day!=profile.day_ids.size()+1:
			return {}
	if seen.size() != state.visits.size() + service_visits.size()-carry.size():
		return {}
	return {"active": "", "outcomes": {}}

static func today(s: Dictionary) -> Array:
	var index: int = Clock.day_index(int(s.game_minutes)) - 1
	var ids: Array = s.calendar.profile.day_ids
	if index >= ids.size():
		return []
	var result:Array=s.calendar.profile.visit_days[ids[index]].duplicate()
	# Only realized world visits enter the queue. Never expose future rules.
	var rules:Dictionary=s.calendar.profile.get("reentry_rules",{})
	var actual:Array=[]
	for id:String in rules:
		if s.visits.has(id) and int(rules[id].day)==index+1:
			actual.append(id)
	actual.sort()
	for id:String in actual:
		result.append(id)
		var resale:Dictionary=rules[id].get("resale",{})
		if not resale.is_empty() and s.visits.has(resale.id):
			result.append(resale.id)
	return result

static func eligible(s:Dictionary,id:String)->bool:
	if not VisitorSlots.eligible(s,id) or not Service.eligible(s,id) or not Reaction.eligible(s,id) or not Regional.eligible(s,id) or not Npc.eligible(s,id) or not Market.eligible(s,id):
		return false
	# A repeatedly offered object must still physically belong to the seller
	# at THIS opening, not merely at seed time. A prior paid sale makes the
	# later appointment unavailable; a refusal leaves it eligible.
	if s.calendar.profile.get("id")=="campaign_42" and s.visits.has(id):
		var ordinary:Dictionary=s.visits[id]
		if ordinary.get("scope",{}).get("kind")=="ordinary":
			var offered:Dictionary=ordinary.get("prices",{})
			if offered.size()!=1:
				return false
			var item_id:String=str(offered.keys()[0])
			var good:Dictionary=s.items.get(item_id,{})
			if good.is_empty() or good.get("owner_id")!=ordinary.seller or good.get("custodian_id")!=ordinary.seller or good.get("status")!="stock" or good.get("protected",true) or not str(good.get("reservation_id","")).is_empty():
				return false
	if s.calendar.profile.content_version not in ["demo7-integrated-1","demo7-integrated-2","demo7-integrated-3"]:
		return true
	# Finite authored demo alternatives require actual current possession.
	if id=="clinic_service" and not s.calendar.contracts.facts.has("clinic_supply_confirmed"):
		return false
	if id=="radio_return_sale" and s.calendar.queue.outcomes.get("radio_return")!="traded":
		return false
	if s.visits.has(id):
		var v:Dictionary=s.visits[id]
		for item_id:String in v.prices:
			var item:Dictionary=s.items.get(item_id,{})
			if item.get("owner_id")!=v.seller or item.get("custodian_id")!=v.seller:
				return false
	return true

static func next_id(s: Dictionary) -> String:
	for id: String in today(s):
		if not s.calendar.queue.outcomes.has(id) and id != s.calendar.queue.active and eligible(s, id):
			return id
	return ""

static func apply(s: Dictionary, kind: String, payload: Dictionary) -> String:
	if not s.calendar.has("queue") or not Clock.business_at(int(s.game_minutes), s.phase):
		return "visit_queue_unavailable"
	var q: Dictionary = s.calendar.queue
	match kind:
		"calendar_next_visit":
			if not payload.is_empty() or not q.active.is_empty() or not Clock.business_at(int(s.game_minutes), s.phase, false):
				return "visit_admission"
			var id: String = next_id(s)
			if id.is_empty():
				return "visit_queue_empty"
			var market_error:String=Market.admit(s,id)
			if not market_error.is_empty():
				return market_error
			q.active = id
		"calendar_decline_visit":
			if not Rules.keys(payload, ["visit_id"]) or q.active.is_empty() or payload.visit_id != q.active:
				return "visit_decline"
			Service.offer_ended(s, q.active, "declined")
			q.outcomes[q.active] = "declined"
			q.active = ""
		_:
			return "visit_queue_command"
	return ""

static func permits(s: Dictionary, id: Variant) -> bool:
	return id is String and not id.is_empty() and s.calendar.queue.active == id and not s.calendar.queue.outcomes.has(id) and s.visits.has(id) and Visits.in_window(s.visits.get(id), int(s.game_minutes), s.phase)

static func finish(s: Dictionary, outcome: String = "traded") -> void:
	var q: Dictionary = s.calendar.queue
	q.outcomes[q.active] = outcome
	q.active = ""

static func close(s: Dictionary) -> void:
	var q: Dictionary = s.calendar.queue
	for id: String in today(s):
		if not q.outcomes.has(id):
			q.outcomes[id] = "missed" if eligible(s, id) else "not_applicable"
			Service.offer_ended(s, id, "missed")
	q.active = ""

static func view(s: Dictionary) -> Dictionary:
	if not s.calendar.has("queue"):
		return {}
	var q: Dictionary = s.calendar.queue
	var id: String = q.active
	var remaining: int = 0
	for pending: String in today(s):
		if not q.outcomes.has(pending) and pending != id and eligible(s, pending):
			remaining += 1
	var terms: Dictionary = {}
	if not id.is_empty():
		terms = s.visits[id].duplicate(true) if s.visits.has(id) else Service.terms_view(s, id)
	return {"active": id, "terms": terms, "remaining": remaining, "can_next": id.is_empty() and remaining > 0 and Clock.business_at(int(s.game_minutes), s.phase, false), "outcomes": q.outcomes.duplicate(true)}
