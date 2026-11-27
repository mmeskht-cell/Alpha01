extends RefCounted
## Authored visual surface profiles are additive presentation facts.
## Never derive material from a legacy pattern, model, hypothesis or seed.
const PATH := "res://data/alpha_b3/surface_profiles_v1.json"
const FAMILIES := ["metal","plastic","paper","fabric","glass"]
const SLOTS := ["material_detail","wear_detail","display_damage_detail"]

static func current_fact(slot: String, fact: Dictionary, item: Dictionary) -> bool:
	return slot in SLOTS and fact.get("slot")==slot and fact.get("kind")=="fact" \
		and fact.has("version") and fact.get("version")==item.get("field_versions")

static func project(item_id: String,item: Dictionary,observed: Dictionary) -> Dictionary:
	if observed.is_empty(): return {}
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not document is Dictionary or document.get("version")!=1:
		return {}
	return from_document(document,item_id,item,observed)

static func from_document(document: Dictionary,item_id: String,item: Dictionary,observed: Dictionary) -> Dictionary:
	var specimen: Dictionary = document.get("specimens",{}).get(item_id,{})
	if specimen.is_empty() or specimen.get("def_id")!=item.get("def_id") or specimen.get("provenance")!=item.get("provenance_id"):
		return {}
	var result: Dictionary = {}
	for slot: String in SLOTS:
		var fact: Dictionary = observed.get(slot,{})
		var profile: Dictionary = specimen.get("surfaces",{}).get(slot,{})
		if profile.is_empty() or not current_fact(slot,fact,item) or str(fact.get("value"))!=str(profile.get("expected")):
			continue
		if profile.get("family") not in FAMILIES or str(profile.get("target","")).is_empty():
			continue
		result[slot] = {"family":profile.family,"target":profile.target}
	return result
