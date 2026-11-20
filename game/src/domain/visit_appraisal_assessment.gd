extends RefCounted
## Visit-scoped public conjectures. GameSession journal is the only authority.
## No correct answer, customer policy, truth sampling or price mutation here.
const Rules = preload("res://src/domain/value_rules.gd")
const Observation = preload("res://src/domain/visit_appraisal_observation.gd")
const Catalog = preload("res://src/domain/public_appraisal_catalog.gd")
const Relevance = preload("res://src/domain/public_appraisal_relevance.gd")
const ACTIONS: Array = ["assess_subject","link_subject_evidence"]
const MAX_LINKS: int = 8

static func catalog(state: Dictionary,visit_id: String,item_id: String) -> Dictionary:
	if Observation.tools(state,visit_id,item_id).is_empty():
		return {}
	if Observation.basic_available(state,visit_id,item_id):
		# Frozen v1 extension, non-price hypotheses only; no invented reference.
		return Catalog.parse({"version":2,"def_id":state.items[item_id].def_id,"currency":"VKC","source_key":"review.basic.source","slots":[{"id":"function_id","category":"function","effect":"none","candidates":[{"id":"working","label_key":"review.basic.working","value":null},{"id":"not_working","label_key":"review.basic.not_working","value":null}]}]})
	var marker: Dictionary = state.get("calendar",{}).get("appraisal_profile",{})
	var row:Dictionary=Observation.source_for(state,state.items[item_id].def_id)
	var profile: Dictionary = Observation.source_catalog(row)
	if profile.is_empty() or marker.get("id") != Observation.PROFILE_ID or marker.get(row.get("marker","")) != Rules.canonical(profile).sha256_text() or profile.def_id != state.items[item_id].def_id:
		return {}
	return profile

static func empty() -> Dictionary:
	return {"selected":{},"links":{},"source_action":null}

static func assessment(state: Dictionary,visit_id: String,item_id: String) -> Dictionary:
	var saved: Dictionary = state.get("calendar",{}).get("appraisal_assessments",{}).get(visit_id,{})
	if saved.get("item_id") != item_id:
		return empty()
	return saved.assessment.duplicate(true)

static func slot_exists(profile: Dictionary,slot_id: String) -> bool:
	for slot: Dictionary in profile.slots:
		if slot.id == slot_id:
			return true
	return false

static func apply(state: Dictionary,kind: String,p: Dictionary,action_id: String) -> String:
	var fields: Array = ["visit_id","item_id","slot_id","candidate_id"] if kind == "assess_subject" else ["visit_id","item_id","slot_id","evidence_id"]
	if kind not in ACTIONS or not Rules.keys(p,fields) or not Rules.identifier(action_id):
		return "assessment_shape"
	for field: String in ["visit_id","item_id","slot_id"]:
		if not Rules.identifier(p[field]):
			return "assessment_shape"
	var profile: Dictionary = catalog(state,p.visit_id,p.item_id)
	if profile.is_empty() or not slot_exists(profile,p.slot_id):
		return "assessment_permission_or_slot"
	var row: Dictionary = assessment(state,p.visit_id,p.item_id)
	if kind == "assess_subject":
		if p.candidate_id != null and not Rules.identifier(p.candidate_id):
			return "assessment_candidate"
		if row.selected.get(p.slot_id) == p.candidate_id:
			return "assessment_unchanged"
		if p.candidate_id == null:
			row.selected.erase(p.slot_id)
			row.links.erase(p.slot_id)
		else:
			row.selected[p.slot_id] = p.candidate_id
		if not Catalog.estimate(profile,row.selected).get("ok",false):
			return "assessment_candidate"
	else:
		if not Rules.identifier(p.evidence_id) or not row.selected.has(p.slot_id):
			return "assessment_link"
		var ids: Array = row.links.get(p.slot_id,[]).duplicate()
		if p.evidence_id in ids:
			ids.erase(p.evidence_id)
		else:
			var eligible: bool = false
			for evidence: Dictionary in Observation.view(state,p.visit_id,p.item_id):
				if evidence.evidence_id == p.evidence_id and evidence.current and not evidence.is_claim:
					eligible = true
			if not eligible or ids.size() >= MAX_LINKS:
				return "assessment_evidence"
			ids.append(p.evidence_id)
			ids.sort()
		if ids.is_empty():
			row.links.erase(p.slot_id)
		else:
			row.links[p.slot_id] = ids
	row.source_action = action_id
	state.calendar.appraisal_assessments[p.visit_id] = {"item_id":p.item_id,"assessment":row}
	return ""

## Read-only suggestions depend on the kind of a current acquired observation
## and the public catalog slot, never the chosen answer or observed value.
## Unmapped profiles simply have no suggestions; other evidence stays usable.
static func evidence_suggestions(profile: Dictionary,facts: Array) -> Dictionary:
	var mapping: Dictionary = Relevance.mapping(profile)
	var result: Dictionary = {}
	for slot: Dictionary in profile.slots:
		var ids: Array = []
		var kinds: Array = mapping.get(slot.id,[])
		for fact: Dictionary in facts:
			if fact.get("current",false) and not fact.get("is_claim",true) and fact.get("observation_key") in kinds:
				ids.append(fact.evidence_id)
		result[slot.id] = ids
	return result

static func view(state: Dictionary,visit_id: String,item_id: String) -> Dictionary:
	var profile: Dictionary = catalog(state,visit_id,item_id)
	if profile.is_empty():
		return {}
	var row: Dictionary = assessment(state,visit_id,item_id)
	return {"catalog":profile,"assessment":row,"reference":Catalog.estimate(profile,row.selected),"evidence_suggestions":evidence_suggestions(profile,Observation.view(state,visit_id,item_id))}
