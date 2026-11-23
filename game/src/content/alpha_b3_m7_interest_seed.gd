extends RefCounted
## Independent M7 source-only candidate on top of the accepted M5 seed.
## New calendar rows represent conditional interest by ALREADY-funded actors;
## no new inventory, wallets, free goods, story, or canonical B2 fixtures.
const Base = preload("res://src/content/alpha_b3_random_runtime_seed.gd")
const Interest = preload("res://src/domain/alpha_b3_market_interest.gd")

static func content(campaign_seed: int = 101) -> Dictionary:
	var source: Dictionary = Base.content(campaign_seed)
	if source.is_empty():
		return {}
	return Interest.extend_m7(source)
