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
		if profile.is_empty() or not current_fact(slot,fact,item):
			continue
		var expected: Variant = profile.get("expected")
		var value: Variant = fact.get("value")
		if expected is int or expected is float:
			if not (value is int or value is float) or float(value)!=float(expected): continue
		elif str(value)!=str(expected):
			continue
		if profile.get("family") not in FAMILIES or str(profile.get("target","")).is_empty():
			continue
		result[slot] = {"family":profile.family,"target":profile.target}
	return result

## Explicit new fictional observations for the spatial first-week candidate only.
## Changed field versions have no newly authored exterior evidence.
static func authored_readings(profile: Dictionary,item_id: String,item: Dictionary) -> Dictionary:
	if not profile.has("spatial_opening") or profile.get("week_proposal")!="first_week_proposal_1":
		return {}
	if item.get("field_versions")!={"functional":0,"restored":0,"composition":0}:
		return {}
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not document is Dictionary or document.get("version")!=1: return {}
	var specimen: Dictionary = document.get("specimens",{}).get(item_id,{})
	if not specimen.get("authored",false) or specimen.get("def_id")!=item.get("def_id") or specimen.get("provenance")!=item.get("provenance_id"): return {}
	if specimen.has("requires_supply"):
		var supply_version: Variant = profile.get("civilian_supply")
		if supply_version not in [1,2] or int(supply_version)<int(specimen.requires_supply): return {}
	var result := {}
	for slot: String in SLOTS:
		var surface: Dictionary = specimen.get("surfaces",{}).get(slot,{})
		if surface.get("family") not in FAMILIES or str(surface.get("target","")).is_empty() or surface.get("side") not in ["front","back"]: continue
		var value: Variant = surface.get("expected")
		if slot=="material_detail":
			if value not in ["parallel","cross"]: continue
		else:
			if not (value is int or value is float) or not is_finite(float(value)) or float(value)<0.0 or float(value)>100.0: continue
			value = int(value)
		result[slot] = {"value":value,"side":surface.side}
	return result
