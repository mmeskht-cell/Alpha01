extends RefCounted
## B3-M2 is a NEW profile and save authority, not an overwrite of the
## verified B3-M1 or B2 save-bound content version.
const Base = preload("res://src/content/alpha_b2_service_multi_seed.gd")
const Market = preload("res://src/domain/alpha_b3_market_interest.gd")

static func content() -> Dictionary:
	var origin: Dictionary=Base.content()
	if origin.is_empty():
		return {}
	return Market.extend(origin, Market.CONTENT_VERSION_M2)
