extends "res://src/presentation/b3_spatial_shop.gd"

@export_enum("regular_delivery","late_delivery","regional_regular_v1","regional_late_v1") var delivery_profile:String = "late_delivery"

func _slot()->String:
	return "b3_f2_"+delivery_profile

func _week_source(seed_value:int)->Dictionary:
	var source := super._week_source(seed_value)
	if not source.is_empty(): source.alpha_profile["battery_market"] = delivery_profile
	return source
