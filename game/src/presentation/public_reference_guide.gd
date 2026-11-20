extends RefCounted
## Public-only, replaceable reference guide. Never loads specimen profiles,
## examines item IDs, adjudicates a hypothesis, or modifies authoritative prices.
const Docs=preload("res://src/content/packaged_documents.gd")
const Relevance=preload("res://src/domain/public_appraisal_relevance.gd")
const PATH:String="res://data/presentation/public_reference_guide.json"

static func description_key(candidate:Dictionary)->String:
	var guide:Dictionary=Docs.read_object(PATH)
	if guide.get("version")!=1 or not guide.get("descriptions") is Dictionary:
		return ""
	var key:Variant=guide.descriptions.get(str(candidate.get("label_key","")),"")
	return str(key) if key is String else ""

# A reference row must correspond exactly to the current public candidates.
# Unknown or incomplete art entries degrade to prose rather than adding facts.
static func comparison(catalog:Dictionary,slot:Dictionary)->Dictionary:
	var guide:Dictionary=Docs.read_object(PATH)
	if guide.get("version")!=1 or not guide.get("comparisons") is Dictionary:
		return {}
	var key:String=str(catalog.get("def_id",""))+"/"+str(slot.get("id",""))
	var row:Variant=guide.comparisons.get(key,{})
	if not row is Dictionary or row.is_empty() or not row.get("samples") is Dictionary or not slot.get("candidates") is Array:
		return {}
	var kind:String=str(row.get("kind",""))
	if kind not in ["radio","texture","stamp","wear","text"] or str(row.get("id","")).is_empty() or str(row.get("caption_key","")).is_empty():
		return {}
	var candidates:Array=slot.candidates
	if candidates.size()<2 or candidates.size()>3 or row.samples.size()!=candidates.size():
		return {}
	var entries:Array=[]
	for candidate:Dictionary in candidates:
		var sample:Variant=row.samples.get(str(candidate.get("id","")))
		if not sample is String or str(sample).is_empty() or str(sample).length()>(96 if kind=="text" else 32):
			return {}
		if kind=="text" and not sample.begins_with("book.compare.sample."):
			return {}
		if kind=="texture" and sample not in ["pits","parallel","cross"]:
			return {}
		if kind=="radio" and sample not in ["selvar_r18","selvar_r18s"]:
			return {}
		if kind=="wear" and sample not in ["light","visible","heavy"]:
			return {}
		entries.append({"label_key":str(candidate.get("label_key","")),"sample":sample})
	return {"id":row.id,"kind":kind,"caption_key":row.caption_key,"entries":entries}

# A tool topic may be relevant to several chapters. This is navigation metadata,
# not evidence, an answer, a grant, or a change to assessment links.
static func related_chapters(catalog:Dictionary,observation_key:String)->Array[int]:
	var result:Array[int]=[]
	if observation_key.is_empty() or not catalog.get("slots") is Array:
		return result
	var mapping:Dictionary=Relevance.mapping(catalog)
	for index:int in range(catalog.slots.size()):
		var slot:Dictionary=catalog.slots[index]
		if observation_key in mapping.get(str(slot.get("id","")),[]):
			result.append(index)
	return result

# Renderer opt-in from approved public definition/tool descriptors. A match
# only selects a presentation. The authority still validates every action.
# No specimen IDs, durations, observed values, or pricing rules are used.
static func native_capability(app:Dictionary)->Dictionary:
	if str(app.get("visit_id","")).is_empty() or str(app.get("item_id","")).is_empty():
		return {}
	var tools:Variant=app.get("tools",{})
	var catalog:Variant=app.get("catalog",{})
	if not tools is Dictionary or tools.is_empty() or not catalog is Dictionary or not catalog.get("slots",[]) is Array or catalog.get("slots",[]).is_empty():
		return {}
	var guide:Dictionary=Docs.read_object(PATH)
	if guide.get("version")!=1 or not guide.get("native_capabilities") is Dictionary:
		return {}
	var row:Variant=guide.native_capabilities.get(str(catalog.get("def_id","")),{})
	if not row is Dictionary or row.is_empty() or row.get("catalog_version")!=catalog.get("version") or row.get("counter_role") not in ["inspection","counter"] or not row.get("tools") is Dictionary:
		return {}
	if row.tools.size()!=tools.size():
		return {}
	for id:Variant in tools:
		var spec:Variant=tools[id]
		var display:Variant=row.tools.get(id,{})
		if not spec is Dictionary or not display is Dictionary or display.is_empty():
			return {}
		if str(spec.get("evidence_id","")).is_empty() or display.get("evidence")!=spec.get("evidence_id") or not display.get("title") is String or str(display.title).is_empty():
			return {}
	return row.duplicate(true)
