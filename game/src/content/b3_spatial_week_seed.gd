extends RefCounted
const Week = preload("res://src/content/alpha_b3_week_candidate.gd")

static func content(seed_value: int) -> Dictionary:
	var source: Dictionary = Week.content(seed_value)
	if not source.is_empty():
		source.alpha_profile["spatial_opening"] = 1
		source.state.inventories.storefront_grid.width = 6
		source.state.inventories.storefront_grid.height = 3
		source.state.inventories["pawn_grid"] = {"owner_id":"player","width":4,"height":3,"host_item":""}
	return source
