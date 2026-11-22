extends RefCounted
## Independent B3 experimental content. It preserves every B2 source item,
## ledger origin, and wallet; only an optional dated genuine buyer visit is
## added to the alpha shop's own finite schedule.
const Base = preload("res://src/content/alpha_b2_service_multi_seed.gd")
const Interest = preload("res://src/domain/alpha_b3_market_interest.gd")

static func content() -> Dictionary:
	var base: Dictionary=Base.content()
	if base.is_empty():
		return {}
	return Interest.extend(base)
