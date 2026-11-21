extends RefCounted
## Real but bounded 42-day variation: choose one already funded physical
## visitor/item from an authored optional group. No actor, money or stock mint.
## Both candidates already exist in a valid visit_days schedule; only one
## becomes eligible in a run. Never expose which future actor will arrive.
const Rules=preload("res://src/domain/value_rules.gd")
const VERSION:int=1
const MAX_GROUPS:int=16

static func _choice(seed:int,day:String,group:String,ids:Array)->String:
	var encoded:String=(str(seed)+":"+day+":"+group).sha256_text()
	var index:int=encoded.substr(0,7).hex_to_int()%ids.size()
	return ids[index]

static func valid(s:Dictionary,profile:Dictionary)->bool:
	var policy:Variant=profile.get("npc_visit_slots")
	if profile.get("id")!="campaign_42" or not Rules.keys(policy,["version","seed","groups"]) or policy.version!=VERSION or not Rules.integer(policy.seed,0,1000000000) or not policy.groups is Dictionary or policy.groups.is_empty() or policy.groups.size()>MAX_GROUPS or not profile.has("visit_days"):
		return false
	var seen:Dictionary={}
	for group:Variant in policy.groups:
		var g:Variant=policy.groups[group]
		if not Rules.identifier(group) or not Rules.keys(g,["day_id","candidates"]) or not Rules.identifier(g.day_id) or g.day_id not in profile.day_ids or not g.candidates is Array or g.candidates.size()<2 or g.candidates.size()>4:
			return false
		var day:int=profile.day_ids.find(g.day_id)+1
		for id:Variant in g.candidates:
			if not Rules.identifier(id) or seen.has(id) or id not in profile.visit_days[g.day_id] or not s.visits.has(id):
				return false
			seen[id]=true
			var v:Dictionary=s.visits[id]
			if v.get("scope",{}).get("kind")!="ordinary" or v.prices.size()!=1 or v.get("opens")!=(day-1)*1440 or v.get("expires")!=(day-1)*1440+600:
				return false
			if not s.wallets.has(v.seller) or not s.wallets.has(v.buyer):
				return false
			var root:String=str(v.prices.keys()[0])
			if not s.items.has(root) or s.items[root].owner_id!=v.seller or s.items[root].custodian_id!=v.seller or not s.items[root].parent_id.is_empty():
				return false
	return true

static func eligible(s:Dictionary,visit_id:String)->bool:
	var policy:Dictionary=s.calendar.profile.get("npc_visit_slots",{})
	if policy.is_empty():
		return true
	var groups:Dictionary=policy.groups
	for group:String in groups:
		var g:Dictionary=groups[group]
		if visit_id in g.candidates:
			return visit_id==_choice(int(policy.seed),g.day_id,group,g.candidates)
	return true
