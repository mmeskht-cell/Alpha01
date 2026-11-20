extends RefCounted
## Non-authoritative, public recommendation metadata. Never samples an item,
## checks a candidate answer, changes a price, or grants inspection/link access.
const Rules=preload("res://src/domain/value_rules.gd")
const Documents=preload("res://src/content/packaged_documents.gd")
const PATH:String="res://data/campaign/gate2/public_evidence_relevance_v1.json"

static func valid_slots(raw:Variant)->bool:
	if not raw is Dictionary or raw.is_empty() or raw.size()>12:
		return false
	for slot:Variant in raw:
		if not Rules.identifier(slot) or not raw[slot] is Array or raw[slot].is_empty() or raw[slot].size()>32:
			return false
		var seen:Array=[]
		for key:Variant in raw[slot]:
			if not Rules.identifier(key) or key in seen:
				return false
			seen.append(key)
	return true

static func parse(raw:Variant)->Dictionary:
	if not Rules.keys(raw,["version","definitions","nonprice"]) or raw.version!=1 or not raw.definitions is Dictionary or raw.definitions.is_empty() or raw.definitions.size()>128 or not valid_slots(raw.nonprice):
		return {}
	for id:Variant in raw.definitions:
		if not Rules.identifier(id) or id=="nonprice" or not valid_slots(raw.definitions[id]):
			return {}
	return raw.duplicate(true)

static func load_mapping()->Dictionary:
	var data:Dictionary=parse(Documents.read_object(PATH))
	if data.is_empty():
		return {}
	var result:Dictionary=data.definitions
	result["nonprice"]=data.nonprice
	return result

static func mapping(profile:Dictionary)->Dictionary:
	var data:Dictionary=load_mapping()
	return data.get("nonprice" if profile.get("version")==2 else str(profile.get("def_id","")),{})
