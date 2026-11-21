extends RefCounted
## New B2 appraisal/card/offer slice is opt-in and has an independent save.
## The B1 and earlier B2 fixed-price profiles keep their original command
## history and historical saved-slot identifiers.
const B2 = preload("res://src/content/alpha_b2_seed.gd")

static func content() -> Dictionary:
	var source: Dictionary = B2.content()
	if source.is_empty():
		return {}
	var result: Dictionary = source.duplicate(true)
	result.alpha_profile.content_version = "b2-cards-pilot-1"
	result.alpha_profile["appraisal_id"] = "alpha_b2_cards_pilot_1"
	return result
