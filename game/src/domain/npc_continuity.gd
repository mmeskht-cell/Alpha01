extends RefCounted
## Authored long-campaign return conditions, derived from PAID trades or
## explicit witnessed declines. No fake goodwill balance or personal memories.
## Actual customer liquidity is still held by GameSession wallets.
const Rules=preload("res://src/domain/value_rules.gd")
const Receipt=preload("res://src/domain/receipt_primitives.gd")
const Trace=preload("res://src/domain/world_causal_trace.gd")
const MAX_GATES:int=128

static func actor(visit:Dictionary)->String:
	if visit.is_empty():
		return ""
	return str(visit.get("seller","")) if visit.get("buyer")=="player" else str(visit.get("buyer",""))

static func seed_valid(state:Dictionary,profile:Dictionary)->bool:
	var policy:Variant=profile.get("npc_continuity")
	if not Rules.keys(policy,["version","gates"]) or policy.version!=1 or not policy.gates is Dictionary or policy.gates.size()>MAX_GATES:
		return false
	for visit_id:Variant in policy.gates:
		var rule:Variant=policy.gates[visit_id]
		if not Rules.identifier(visit_id) or not Rules.keys(rule,["prior_visit","outcome"]) or rule.outcome not in ["traded","declined"] or not Rules.identifier(rule.prior_visit):
			return false
		var prior:Dictionary=state.visits.get(rule.prior_visit,{})
		var next:Dictionary=state.visits.get(visit_id,{})
		if prior.is_empty() or next.is_empty() or actor(prior).is_empty() or actor(prior)!=actor(next) or actor(prior)=="player" or int(prior.expires)>=int(next.opens) or not state.wallets.has(actor(prior)):
			return false
	return true

static func _declined(s:Dictionary,visit_id:String)->bool:
	if s.get("calendar",{}).get("queue",{}).get("outcomes",{}).get(visit_id)!="declined":
		return false
	var commands:Array=s.get("calendar",{}).get("commands",[])
	for index:int in range(commands.size()):
		var cmd:Dictionary=commands[index]
		if cmd.get("type")!="calendar_decline_visit" or cmd.get("payload",{}).get("visit_id")!=visit_id or int(cmd.get("expected_revision",-1))!=index:
			continue
		if Receipt.matches_receipt(s,cmd.action_id,"calendar_decline_visit",cmd.payload,index+1):
			return true
	return false

static func eligible(s:Dictionary,visit_id:String)->bool:
	var rules:Dictionary=s.get("calendar",{}).get("profile",{}).get("npc_continuity",{}).get("gates",{})
	if not rules.has(visit_id):
		return true
	var rule:Dictionary=rules[visit_id]
	if rule.outcome=="traded":
		return not Trace.trade_for_visit(s,rule.prior_visit).is_empty()
	return _declined(s,rule.prior_visit)

## A public first-hand encounter record only, never a hidden NPC thought.
static func visible_history(s:Dictionary,actor_id:String)->Dictionary:
	if not Rules.identifier(actor_id) or actor_id=="player" or not s.wallets.has(actor_id):
		return {}
	var deals:Dictionary=Trace.customer_memory(s,actor_id)
	var last_decline:String=""
	var command_count:int=0
	for cmd:Dictionary in s.get("calendar",{}).get("commands",[]):
		if cmd.get("type")!="calendar_decline_visit" or not s.visits.has(cmd.get("payload",{}).get("visit_id","")):
			continue
		if actor(s.visits[cmd.payload.visit_id])==actor_id and _declined(s,cmd.payload.visit_id):
			command_count+=1
			last_decline=cmd.payload.visit_id
	if deals.is_empty() and command_count==0:
		return {}
	return {"actor_id":actor_id,"trades":int(deals.get("trades",0)),"declines":command_count,
		"last_declined_visit":last_decline}
