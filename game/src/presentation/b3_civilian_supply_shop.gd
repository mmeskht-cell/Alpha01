extends "res://src/presentation/b3_f5_shop.gd"
## Isolated content candidate. Never loads or replaces an old F5 generation.
const SupplySeed = preload("res://src/content/b3_civilian_supply_seed.gd")
const Food = preload("res://src/presentation/preserved_food_visuals.gd")
const Essentials = preload("res://src/presentation/approved_civilian_visuals.gd")

func _slot() -> String:
	return "b3_civilian_supply_v1"

func _week_source(seed_value: int) -> Dictionary:
	return SupplySeed.content(seed_value)

func _text(key: String) -> String:
	for prefix: String in ["b2.item.","item."]:
		if key.begins_with(prefix):
			var model := key.trim_prefix(prefix)
			var labels: Dictionary = Food.LABELS.get(model,Essentials.LABELS.get(model,{}))
			if not labels.is_empty(): return str(labels.get(counter_language,labels.ko))
	return super._text(key)

func _fact_caption(slot: String,value: Variant) -> String:
	if slot=="identity" and (Food.LABELS.has(str(value)) or Essentials.LABELS.has(str(value))):
		return _text("b2.item."+str(value))
	return super._fact_caption(slot,value)
