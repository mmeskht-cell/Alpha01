extends RefCounted
const Retention=preload("res://src/domain/appraisal_history_retention.gd")
## Optional functional term for existing ordinary fixed-price sales.
## Settlement only: no durability warranty or automatic refund.
const Rules=preload("res://src/domain/value_rules.gd")
const Receipt=preload("res://src/domain/receipt_primitives.gd")
const Evidence=preload("res://src/domain/evidence_primitives.gd")
const Record=preload("res://src/domain/observation_record.gd")
const Access=preload("res://src/domain/inspection_access.gd")
const Visits=preload("res://src/domain/visit_primitives.gd")
const Claims=preload("res://src/domain/visit_customer_claims.gd")
const SALES:Dictionary={"battery_sale":"battery","tool_sale":"demo_tool","electronics_sale":"demo_electronics"}
const FIELD:String="sale_quality_evidence_id"

static func available(s:Dictionary,visit_id:String,item_id:String)->bool:
	if not SALES.has(visit_id) or not Claims.demo3(s) or not Claims.enabled(s) or not s.items.has(item_id) or s.calendar.get("queue",{}).get("active")!=visit_id:
		return false
	var v:Dictionary=s.visits.get(visit_id,{})
	return SALES[visit_id]==s.items[item_id].def_id and Visits.in_window(v,int(s.game_minutes),s.phase) and v.scope.kind=="ordinary" and v.scope.purpose=="sale" and not v.scope.completed and v.seller=="player" and v.buyer!="player" and v.prices.has(item_id) and Access.stock_access(s,item_id,"player",true)

static func bound_record(s:Dictionary,id:String,item_id:String)->Dictionary:
	var r:Dictionary=s.get("knowledge",{}).get(id,{})
	if not r.is_empty():
		if r.get("item_id")==item_id and r.get("observation_key")=="functional" and r.get("observed_value") is bool and Record.bound(s,id,r,"record") and r.dependent_field_versions.has("functional"):
			return r
		return {}
	var e:Dictionary=Retention.records(s).get(id,{})
	r=e.get("record",{})
	if r.is_empty() or r.get("item_id")!=item_id or r.get("observer_id")!="player" or r.get("observation_key")!="function_status" or r.get("observed_value") not in ["serviceable","inoperable"] or e.get("tool_id")!="basic_function_v1" or e.get("target")!="basic_whole_function" or not r.get("dependent_field_versions",{}).has("functional"):
		return {}
	var payload:Dictionary={"visit_id":e.visit_id,"item_id":item_id,"tool_id":e.tool_id,"target":e.target}
	return r if Receipt.matches_receipt(s,id,"inspect_subject",payload,Receipt.receipt_revision(s,id)) else {}

static func condition(r:Dictionary)->Dictionary:
	var working:bool=r.observed_value if r.observed_value is bool else r.observed_value=="serviceable"
	return {"kind":"function_at_trade","evidence_id":r.evidence_id,"observed_value":"serviceable" if working else "inoperable"}

static func option(s:Dictionary,visit_id:String,item_id:String)->Dictionary:
	if not available(s,visit_id,item_id):
		return {}
	var best:Dictionary={}
	var best_rev:int=-1
	var ids:Array=s.get("knowledge",{}).keys()+Retention.records(s).keys()
	for id:String in ids:
		var r:Dictionary=bound_record(s,id,item_id)
		if r.is_empty() or not Evidence.eligible_ground(r,s.items[item_id].field_versions,item_id,["functional","function_status"]):
			continue
		var rev:int=Receipt.receipt_revision(s,id)
		if rev>best_rev:
			best_rev=rev
			best=condition(r)
	return best

static func error(s:Dictionary,p:Dictionary)->String:
	if not p.has(FIELD):
		return ""
	if not Rules.identifier(p.get(FIELD)) or not Rules.identifier(p.get("visit_id")) or not Rules.identifier(p.get("item_id")) or p.get("seller")!="player":
		return "sale_quality_shape"
	var eligible:Dictionary=option(s,p.visit_id,p.item_id)
	return "" if not eligible.is_empty() and eligible.evidence_id==p[FIELD] else "sale_quality_evidence"

static func sheet(s:Dictionary,entry:Dictionary,item_id:String)->Dictionary:
	var rev:int=int(entry.revision)
	var journal:Array=s.get("calendar",{}).get("commands",[])
	if rev<1 or rev>journal.size():
		return {}
	var cmd:Dictionary=journal[rev-1]
	var p:Dictionary=cmd.payload
	if cmd.type!="trade" or cmd.action_id!=entry.event_id or p.get("item_id")!=item_id or p.get("visit_id")!=entry.visit_id or p.get("seller")!="player" or not Rules.identifier(p.get(FIELD)) or not Receipt.matches_receipt(s,entry.event_id,"trade",p,rev):
		return {}
	var id:String=p[FIELD]
	var r:Dictionary=bound_record(s,id,item_id)
	if r.is_empty() or Receipt.receipt_revision(s,id)>=rev:
		return {}
	var fact:Dictionary=Evidence.public_view(r,r.dependent_field_versions,item_id)
	if fact.is_empty() or fact.is_claim:
		return {}
	fact.erase("current")
	return {"transaction_id":entry.event_id,"revision":rev,"offer_id":null,"amounts":entry.amounts.duplicate(true),"statements":[],"current_ids":[],"observations":[fact],"quality_condition":condition(r)}
