extends RefCounted
## A new seven-day opt-in content version. Broker initial liquidity comes
## from the existing alpha42_mechanics fixture (100 VKC, 5 USD).
const Base=preload("res://src/content/alpha_b3_market_m2_seed.gd")
const FX=preload("res://src/domain/alpha_b3_fx.gd")

static func content() -> Dictionary:
	var origin: Dictionary=Base.content()
	var c: Dictionary=FX.config()
	if origin.is_empty() or c.is_empty():
		return {}
	var next: Dictionary=origin.duplicate(true)
	if next.state.wallets.has(c.counterparty) or next.state.inventories.has(c.counterparty+"_grid"):
		return {}
	next.state.wallets[c.counterparty]={"VKC":100,"USD":5}
	next.state.inventories[c.counterparty+"_grid"]={"owner_id":c.counterparty,"width":10,"height":6,"host_item":""}
	next.alpha_profile.days[int(c.day)-1].append({"id":c.visit_id,"actor_id":c.counterparty,"kind":"named","purpose_key":"b3.fx.visit","contact_offer":false})
	next.alpha_profile.content_version=FX.VERSION
	next.alpha_profile["fx_profile"]=c.duplicate(true)
	return next
