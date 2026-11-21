extends RefCounted
## Optional policy: a bounded, economically meaningful personality effect
## on already-authored regional offers. Never changes the seeded wallet,
## owns a good, rerolls on reload or reveals private customer traits.
const Rules=preload("res://src/domain/value_rules.gd")
const TRAITS:Array=["cautious","impatient","methodical","reserved"]
const Trace=preload("res://src/domain/world_causal_trace.gd")
const VERSION:int=1

static func valid(s:Dictionary,profile:Dictionary)->bool:
	var policy:Variant=profile.get("npc_bargaining",{})
	if profile.get("id")!="campaign_42" or not profile.has("market_flow") or not profile.has("npc_population") or not s.get("calendar",{}).has("npc_population") or not Rules.keys(policy,["version","traits","loyalty_step","max_trades"]) or policy.version!=VERSION or not policy.traits is Dictionary or policy.traits.size()!=TRAITS.size() or not Rules.integer(policy.loyalty_step,0,3) or not Rules.integer(policy.max_trades,0,3):
		return false
	for trait:String in TRAITS:
		var row:Variant=policy.traits.get(trait)
		if not Rules.keys(row,["seller_delta","buyer_delta"]) or not Rules.integer(row.seller_delta,-10,10) or not Rules.integer(row.buyer_delta,-10,10):
			return false
	# Personalities only apply to already funded economic actors whose
	# stable seed identity was validated by NpcPopulation.seed.
	for actor:String in s.calendar.npc_population.actors:
		var persona:Dictionary=s.calendar.npc_population.actors[actor]
		if persona.get("private_trait") not in TRAITS:
			return false
	return true

static func adjustment(s:Dictionary,visit_id:String)->int:
	var policy:Dictionary=s.get("calendar",{}).get("profile",{}).get("npc_bargaining",{})
	if policy.is_empty() or not s.visits.has(visit_id) or not s.calendar.has("npc_population"):
		return 0
	var visit:Dictionary=s.visits[visit_id]
	var actor:String=str(visit.seller) if visit.buyer=="player" else str(visit.buyer)
	var persona:Dictionary=s.calendar.npc_population.actors.get(actor,{})
	var personality:Dictionary=policy.traits.get(persona.get("private_trait",""),{})
	if personality.is_empty():
		return 0
	var count:int=mini(int(Trace.customer_memory(s,actor).get("trades",0)),int(policy.max_trades))
	var loyalty:int=count*int(policy.loyalty_step)
	# Selling to the player: repeat trade lowers quoted ask. Buying from
	# the player: repeat trade increases quoted bid. Never fake goodwill.
	return int(personality.seller_delta)-loyalty if visit.buyer=="player" else int(personality.buyer_delta)+loyalty
