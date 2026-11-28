extends RefCounted
## The regular campaign inherits the complete F5 source and adds the catalog.
const FirstWeek = preload("res://src/content/b3_f3_composite_seed.gd")
const Catalog = preload("res://src/domain/b3_integrated_catalog.gd")

# v1 remains the product save source; v2/v3 are opt-in trials.
const PLANNER_TRIAL_KEY := "b3_campaign_planner_v2"
const RETRY_TRIAL_KEY := "b3_campaign_retry_v3"
const DEFAULT_VERSION := 1

# The default parameter is the immutable original source. Only a genuine
# new-game launch chooses DEFAULT_VERSION; legacy callers stay on v1.
static func content(seed_value: int,version: int=1) -> Dictionary:
	if version not in [1,2,3]: return {}
	var source := Catalog.extend(FirstWeek.content(seed_value))
	if version==3:
		return Catalog.add_retry_opportunities(source)
	if version==2 and not source.is_empty():
		source.alpha_profile["visit_plan_policy"] = 2
	return source
