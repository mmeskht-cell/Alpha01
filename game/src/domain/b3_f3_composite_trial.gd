extends RefCounted
## Isolated fictional civilian electronics trial. Components are abstract tags.
const ROOT := "F3R01"
const MODEL := "f3_receiver_v1"
const PART_A := "f3_module_a"
const PART_B := "f3_module_b"
const BAD := "F3R01_B"
const SPARE := "F3S01"
const BUY := "f3_receiver_buy"
const SUPPLY := "f3_spare_buy"
const SELL := "f3_receiver_sale"
const RETURN := "f3_receiver_return"
const VISITS = {BUY:[1,ROOT,"G12","player",70],SUPPLY:[2,SPARE,"G12","player",15],SELL:[3,ROOT,"player","G05",100],RETURN:[4,ROOT,"G05","player",90]}

static func enabled(profile:Dictionary)->bool:
	return profile.get("f3_composite_trial")==1

static func seed_valid(state:Dictionary,profile:Dictionary)->bool:
	if not enabled(profile) or not profile.has("spatial_opening") or profile.get("battery_market")!="regional_late_v2" or not profile.get("days") is Array or profile.days.size()!=7: return false
	for id:String in VISITS:
		var rule:Array=VISITS[id]
		var v:Dictionary=state.visits.get(id,{})
		if v.get("seller")!=rule[2] or v.get("buyer")!=rule[3] or v.get("prices",{}).size()!=1 or v.get("prices",{}).get(rule[1])!={"VKC":rule[4],"USD":0} or int(v.get("opens",-1))!=(int(rule[0])-1)*1440 or v.get("scope",{}).get("kind")!="ordinary" or v.get("scope",{}).get("completed",true): return false
		var actor:String=rule[2] if rule[3]=="player" else rule[3]
		var rows:Variant=profile.days[int(rule[0])-1]
		if not rows is Array: return false
		var found:bool=false
		for row:Variant in rows:
			if row is Dictionary and row.get("id")==id and row.get("actor_id")==actor and row.get("kind")=="regular": found=true
		if not found: return false
	for id:String in [ROOT,"F3R01_A",BAD,SPARE]:
		var item:Dictionary=state.items.get(id,{})
		if item.get("owner_id")!="G12" or item.get("custodian_id")!="G12" or item.get("basis")!={"VKC":null,"USD":null}: return false
	return state.items[ROOT].def_id==MODEL and not state.items[ROOT].functional and state.items.F3R01_A.def_id==PART_A and state.items.F3R01_A.parent_id==ROOT and state.items.F3R01_A.functional and state.items[BAD].def_id==PART_B and state.items[BAD].parent_id==ROOT and not state.items[BAD].functional and state.items[SPARE].def_id==PART_B and state.items[SPARE].parent_id=="" and state.items[SPARE].functional

## Explicit inspection of the matching live specimen only.
static func signal_value(state:Dictionary,id:String)->String:
	var item:Dictionary=state.items[id]
	if not item.functional: return "inoperable"
	var tags:Array=[]
	for part:Dictionary in state.items.values():
		if part.parent_id!=id: continue
		if not part.functional or part.def_id not in [PART_A,PART_B]: return "inoperable"
		if part.def_id in tags: return "inoperable"
		tags.append(part.def_id)
	return "serviceable" if tags.size()==2 else "inoperable"

static func observation_current(state:Dictionary,id:String,observation:Dictionary)->bool:
	if not state.items.has(id): return false
	if observation.slot=="identity": return true
	if observation.slot!="function_detail": return false
	var old:Dictionary=observation.get("version",{})
	var now:Dictionary=state.items[id].field_versions
	return old.get("functional",-1)==now.functional and old.get("composition",-1)==now.composition
