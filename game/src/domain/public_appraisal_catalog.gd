extends RefCounted
## Definition-driven PUBLIC appraisal reference. Never reads hidden item state.
## Version 1: one model base, at most one appearance multiplier, independent
## additive deltas, optional non-price slots. All slots optional to the player.
const Rules = preload("res://src/domain/value_rules.gd")
const Math = preload("res://src/domain/appraisal_primitives.gd")
const CATEGORIES: Array = ["identification","appearance","material","function","special"]
const EFFECTS: Array = ["base","percent","delta","none"]

static func parse(raw: Variant) -> Dictionary:
	if not Rules.keys(raw,["version","def_id","currency","source_key","slots"]) or raw.version not in [1,2] or raw.currency != "VKC" or not Rules.identifier(raw.def_id) or not Rules.identifier(raw.source_key) or not raw.slots is Array or raw.slots.is_empty() or raw.slots.size() > 12:
		return {}
	var ids: Dictionary = {}
	var base_count: int = 0
	var percent_count: int = 0
	for slot: Variant in raw.slots:
		if not Rules.keys(slot,["id","category","effect","candidates"]) or not Rules.identifier(slot.id) or ids.has(slot.id) or slot.category not in CATEGORIES or slot.effect not in EFFECTS or not slot.candidates is Array or slot.candidates.is_empty() or slot.candidates.size() > 32:
			return {}
		ids[slot.id] = true
		if raw.version==2 and slot.effect!="none":
			return {}
		if slot.effect == "base":
			if slot.category != "identification":
				return {}
			base_count += 1
		elif slot.effect == "percent":
			if slot.category != "appearance":
				return {}
			percent_count += 1
		var candidates: Dictionary = {}
		for row: Variant in slot.candidates:
			if not Rules.keys(row,["id","label_key","value"]) or not Rules.identifier(row.id) or candidates.has(row.id) or not Rules.identifier(row.label_key):
				return {}
			candidates[row.id] = true
			match slot.effect:
				"base":
					if not Rules.integer(row.value):
						return {}
				"percent":
					if not Rules.integer(row.value,0,Math.MAX_PERCENT):
						return {}
				"delta":
					if not Rules.integer(row.value,-Rules.LIMIT,Rules.LIMIT):
						return {}
				"none":
					if row.value != null:
						return {}
	if (raw.version==1 and base_count!=1) or (raw.version==2 and (base_count!=0 or percent_count!=0)) or percent_count > 1:
		return {}
	return Rules.normalized(raw)

static func selected(profile: Dictionary, selection: Variant) -> Dictionary:
	if not selection is Dictionary:
		return {}
	var values: Dictionary = {}
	for slot: Dictionary in profile.slots:
		var id: Variant = selection.get(slot.id)
		var found: bool = id == null
		var value: Variant = null
		if id != null:
			if not Rules.identifier(id):
				return {}
			for row: Dictionary in slot.candidates:
				if row.id == id:
					found = true
					value = row.value
					break
		if not found:
			return {}
		values[slot.id] = value
	for id: Variant in selection:
		if not values.has(id):
			return {}
	return {"values":values}

static func estimate(raw: Variant, selection: Variant) -> Dictionary:
	var profile: Dictionary = parse(raw)
	if profile.is_empty():
		return {}
	var result: Dictionary = selected(profile,selection)
	if result.is_empty():
		return {}
	var values: Dictionary = result.values
	var base: Variant = null
	var percent: Variant = 100
	var adjustment: int = 0
	for slot: Dictionary in profile.slots:
		var value: Variant = values[slot.id]
		match slot.effect:
			"base": base = value
			"percent": percent = value
			"delta":
				if value != null:
					adjustment += int(value)
	var preview: Dictionary = Math.reference_preview(null if base == null else int(base)+adjustment,percent)
	if preview.get("ok",false):
		preview["model_reference"] = base
		preview["selected_values"] = values
	return preview

## Same reference math as legacy R001; detailed catalog remains the UI source.
static func radio_adapter(ref: Dictionary) -> Dictionary:
	if ref.is_empty():
		return {}
	var slots: Array = []
	for definition: Array in [["model_id","identification","base","model_candidates","reference_amount"],["appearance_id","appearance","percent","appearance_candidates","factor_percent"],["material_id","material","delta","material_candidates","delta"],["batch_id","special","none","batch_candidates",""]]:
		var rows: Array = []
		for row: Dictionary in ref.get(definition[3],[]):
			rows.append({"id":row.id,"label_key":row.get("label_key",row.get("name_key","")),"value":null if definition[2] == "none" else row.get(definition[4])})
		slots.append({"id":definition[0],"category":definition[1],"effect":definition[2],"candidates":rows})
	return parse({"version":1,"def_id":"portable_radio","currency":ref.get("currency"),"source_key":ref.get("source_key"),"slots":slots})
