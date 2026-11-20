extends RefCounted
## Render public observation keys and actual observed values only.
const LABELS:Dictionary={"R001.wear":"review.fact.surface","dial_wear":"review.fact.surface","R001.casing_detail":"review.fact.mark","back_mark":"review.fact.mark","R001.material":"review.fact.texture","case_texture":"review.fact.texture","R001.batch":"review.fact.batch","R001.function":"review.fact.function","function_status":"review.fact.function","R001.display_damage":"review.fact.display"}
const VALUES:Dictionary={"parallel":"review.value.parallel","cross":"review.value.cross","serviceable":"review.value.serviceable","inoperable":"review.value.inoperable","— ? —":"review.value.unreadable"}

static func label(key:String,tr_key:Callable)->String:
	var translated:String=LABELS.get(key,"review.fact.unknown")
	return str(tr_key.call(translated)) if tr_key.is_valid() else translated

static func reading(key:String,value:Variant,tr_key:Callable)->String:
	var value_key:String=""
	if value==null:
		value_key="review.value.unknown"
	elif value is bool:
		value_key="review.value.yes" if value else "review.value.no"
	elif value is String:
		value_key=VALUES.get(value,"")
	if not value_key.is_empty():
		return str(tr_key.call(value_key)) if tr_key.is_valid() else value_key
	if key in ["R001.wear","dial_wear","R001.display_damage"] and (value is int or value is float):
		return str(value)+"/100"
	# Inscriptions are observed text, not localization identifiers.
	return str(value)

static func fact(key:String,value:Variant,tr_key:Callable)->String:
	return label(key,tr_key)+" · "+reading(key,value,tr_key)
