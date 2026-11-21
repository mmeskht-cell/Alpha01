extends RefCounted
## Opt-in 42-day procedural visitor persona pilot. Economic actors, goods,
## inventory, admission and settlement are STILL authored GameSession facts.
## The generated persona is persistent in the seed and never rerolled on load.
const Rules=preload("res://src/domain/value_rules.gd")
const Npc=preload("res://src/domain/npc_continuity.gd")
const VERSION:int=1
const MAX_ACTORS:int=16
const KINDS:Array=["scavenger","mercenary","civilian"]
const PREFIX:Array=["ASH","MOTH","SABLE","WREN","GREY","IVY","SLATE","DUSK"]
const SUFFIX:Array=["NORTH","LOW","STONE","DUST","VALE","RIVER","COLD","ROAD"]
const OUTFITS:Array=["worn_coat","rain_cape","work_jacket","patched_vest"]
const TRAITS:Array=["cautious","impatient","methodical","reserved"]

static func _choice(source:String, size:int)->int:
	var value:int=0
	for index:int in range(source.length()):
		value=(value*33+source.unicode_at(index))%2147483647
	return value%size

static func seed(state:Dictionary,profile:Dictionary)->Dictionary:
	var policy:Variant=profile.get("npc_population",{})
	if profile.get("id")!="campaign_42" or not profile.has("market_flow") or not profile.has("regional_world") or not Rules.keys(policy,["version","seed","actors"]) or policy.version!=VERSION or not Rules.integer(policy.seed,0,1000000000) or not policy.actors is Dictionary or policy.actors.is_empty() or policy.actors.size()>MAX_ACTORS:
		return {}
	var result:Dictionary={}
	var ids:Array=policy.actors.keys()
	ids.sort()
	for actor:Variant in ids:
		var entry:Variant=policy.actors[actor]
		if not Rules.identifier(actor) or actor=="player" or not Rules.keys(entry,["kind","region"]) or entry.kind not in KINDS or not Rules.identifier(entry.region) or not profile.regional_world.regions.has(entry.region) or not state.wallets.has(actor):
			return {}
		var has_inventory:bool=false
		for storage:Dictionary in state.inventories.values():
			if storage.get("owner_id")==actor:
				has_inventory=true
				break
		if not has_inventory:
			return {}
		# A procedural identity may decorate only an existing, ordinary,
		# already financed, region-bound market visitor. It grants no stock.
		var appears:bool=false
		for visit_id:String in profile.market_flow.entries:
			var visit:Dictionary=state.visits.get(visit_id,{})
			if profile.market_flow.entries[visit_id].region==entry.region and visit.get("scope",{}).get("kind")=="ordinary" and (visit.get("buyer")==actor or visit.get("seller")==actor):
				appears=true
				break
		if not appears:
			return {}
		var basis:String=str(policy.seed)+":"+actor+":"+entry.region
		var prefix:String=PREFIX[_choice(basis+":name1",PREFIX.size())]
		var suffix:String=SUFFIX[_choice(basis+":name2",SUFFIX.size())]
		result[actor]={"actor_id":actor,"generation_id":"visitor_"+str(policy.seed)+"_"+actor,
			"alias":prefix+" "+suffix,"kind":entry.kind,"region":entry.region,
			"outfit":OUTFITS[_choice(basis+":outfit",OUTFITS.size())],
			"private_trait":TRAITS[_choice(basis+":trait",TRAITS.size())]}
	return {"version":VERSION,"actors":result}

## Show only the guest standing at the counter, not future arrivals,
## bank balances, preferences, private negotiation traits or stock.
static func active_view(state:Dictionary)->Dictionary:
	var active:String=str(state.get("calendar",{}).get("queue",{}).get("active",""))
	var visit:Dictionary=state.get("visits",{}).get(active,{})
	if visit.is_empty():
		return {}
	var actor:String=Npc.actor(visit)
	var persona:Dictionary=state.calendar.get("npc_population",{}).get("actors",{}).get(actor,{})
	if persona.is_empty():
		return {}
	var history:Dictionary=Npc.visible_history(state,actor)
	return {"actor_id":actor,"alias":persona.alias,"kind":persona.kind,
		"region":persona.region,"outfit":persona.outfit,
		"returning":int(history.get("trades",0))+int(history.get("declines",0))>0}
