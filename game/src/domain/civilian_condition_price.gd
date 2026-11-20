extends RefCounted
## Fictional civilian sale offer derived only from fresh public evidence.
const Evidence=preload("res://src/domain/evidence_primitives.gd")
const Access=preload("res://src/domain/inspection_access.gd")
const VISIT="civil_receiver_condition_v1"
const VISIT_V2="civil_receiver_condition_v2"

static func recognizes(visit_id:String)->bool:
	return visit_id in [VISIT,VISIT_V2]

const ITEM="CR06"

static func quote(s:Dictionary,defs:Dictionary,visit_id:String)->Dictionary:
	if not recognizes(visit_id) or not s.visits.has(visit_id) or not s.items.has(ITEM):
		return {}
	var visit:Dictionary=s.visits[visit_id]
	# v1 is replay-frozen. v2 removes the incentive to conceal a known defect.
	var risk_price:int=40 if visit_id==VISIT_V2 else 55
	var item:Dictionary=s.items[ITEM]
	if visit.scope.completed or visit.seller!="player" or visit.buyer!="G07" or visit.scope.kind!="ordinary" or visit.scope.purpose!="sale" or not visit.prices.has(ITEM) or item.def_id!="civil_receiver" or not Access.stock_access(s,ITEM,"player"):
		return {}
	if defs.get(item.def_id,{}).get("category")!="civilian_electronics":
		return {}
	var known:Dictionary={}
	for record:Dictionary in s.knowledge.values():
		if record.item_id!=ITEM or record.observer_id!="player":
			continue
		var fact:Dictionary=Evidence.public_view(record,item.field_versions,ITEM)
		if not fact.is_empty() and fact.current and not fact.is_claim and fact.observation_key in ["complete","functional","restored"] and fact.observed_value is bool:
			known[fact.observation_key]=fact.observed_value
	if known.get("complete")!=true:
		return {"item_id":ITEM,"amount":risk_price,"currency":"VKC","can_sell":false,"tier":"incomplete" if known.get("complete")==false else "verify_complete"}
	if known.get("functional")==false:
		return {"item_id":ITEM,"amount":45,"currency":"VKC","can_sell":true,"tier":"inoperable"}
	if known.get("functional")!=true:
		return {"item_id":ITEM,"amount":risk_price,"currency":"VKC","can_sell":true,"tier":"unverified"}
	if not known.has("restored"):
		return {"item_id":ITEM,"amount":110,"currency":"VKC","can_sell":true,"tier":"functional"}
	return {"item_id":ITEM,"amount":150 if known.restored else 160,"currency":"VKC","can_sell":true,"tier":"refurbished" if known.restored else "serviceable"}

static func label(tier:String,ko:bool)->String:
	var labels:Dictionary={
		"unavailable":["현재 이 물품은 거래할 수 없습니다","This item cannot be traded now"],
		"verify_complete":["구성 완전성 확인 후 판매 가능","Verify completeness before sale"],
		"incomplete":["불완전 구성 · 판매 불가","Incomplete assembly · sale unavailable"],
		"inoperable":["작동 불가 확인 · 할인 매입","Confirmed inoperable · discounted offer"],
		"unverified":["기능 미확인 · 위험 할인","Function unverified · risk discount"],
		"functional":["작동 확인 · 정비 상태 미확인","Function verified · restoration unknown"],
		"refurbished":["정비품 확인 · 정비품 가격","Verified refurbished · refurbished offer"],
		"serviceable":["사용 가능 확인 · 정상 가격","Verified serviceable · serviceable offer"]}
	var pair:Array=labels.get(tier,["",""])
	return pair[0 if ko else 1]
