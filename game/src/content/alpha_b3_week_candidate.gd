extends RefCounted
## Isolated balance proposal. All actors, goods, ordinary prices and wallets
## come from the seven-day campaign. Repeat only after the original visit.
const Base = preload("res://src/content/alpha_b3_m7_interest_seed.gd")
const VERSION = "first_week_proposal_1"
const REPEATS = {3:["battery_buy","watch_a"],4:["radio3_buy"],5:["battery_buy","watch_a","gear_buy"],6:["tool_buy","radio3_buy"],7:["tool_buy","watch_a","battery_buy"]}

static func content(campaign_seed: int = 101) -> Dictionary:
	var source: Dictionary = Base.content(campaign_seed)
	if source.is_empty():
		return {}
	var profile: Dictionary = source.alpha_profile
	profile["week_proposal"] = VERSION
	for day: int in REPEATS:
		var slots: Array = profile.days[day - 1]
		for original: String in REPEATS[day]:
			var trade: Dictionary = source.state.visits[original].duplicate(true)
			var actor: String = trade.seller
			if slots.any(func(row: Dictionary) -> bool: return row.actor_id == actor):
				continue
			var id: String = "week_" + original + "_d" + str(day)
			trade.scope.visit_id = id
			trade.opens = (day - 1) * 1440
			trade.expires = trade.opens + 600
			source.state.visits[id] = trade
			slots.append({"id":id,"actor_id":actor,"kind":"regular","purpose_key":"alpha.purpose.trade","contact_offer":actor == "G01"})
	return source
