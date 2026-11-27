extends "res://src/presentation/b3_civilian_supply_shop.gd"
const ExpandedSeed = preload("res://src/content/b3_civilian_supply_v2_seed.gd")

func _slot() -> String:
	return "b3_civilian_supply_v2"

func _week_source(seed_value: int) -> Dictionary:
	return ExpandedSeed.content(seed_value)
