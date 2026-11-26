extends "res://src/presentation/b3_spatial_shop.gd"
## Explicit F3 candidate launcher; separate slot, no existing save conversion.
func _slot()->String:
	return "b3_f3_composite_v1"

func _week_source(seed_value:int)->Dictionary:
	return preload("res://src/content/b3_f3_composite_seed.gd").content(seed_value)
