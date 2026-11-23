extends RefCounted
## New opt-in profile: the M3 finite economy and actor identities are unchanged.
## Randomness is only a source-bound visit selection policy attached to the
## initial profile. A production launcher must persist the chosen seed before
## presenting a New Game; this separate pilot has no automatic seed creation.
const Base = preload("res://src/content/alpha_b3_fx_seed.gd")
const Rules = preload("res://src/domain/value_rules.gd")

static func content(campaign_seed: int = 101) -> Dictionary:
	if not Rules.integer(campaign_seed, 1, Rules.LIMIT):
		return {}
	var original: Dictionary = Base.content()
	if original.is_empty():
		return {}
	var data: Dictionary = original.duplicate(true)
	data.alpha_profile["visit_random"] = {
		"version": 1, "seed": campaign_seed,
		"locked_ids": ["alpha_marcus_intro", "hygiene_sale"]
	}
	return data
