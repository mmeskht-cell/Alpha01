extends RefCounted
## Isolated B2 named/regular parity pilot. Reuses two real finite purchases:
## G01's TL04 D4 -> G03 and G05's HY05 D5 -> Ian. The existing D5
## hygiene_sale visit and Ian's original 90 VKC wallet are NOT duplicated.
## The published B2 G03 commission profile/slot stays byte-for-byte stable.
const G03 = preload("res://src/content/alpha_b2_commission_seed.gd")
const Commission = preload("res://src/domain/alpha_commission.gd")

static func content() -> Dictionary:
	var base: Dictionary = G03.content()
	var config: Dictionary = Commission.config(Commission.NAMED_PROFILE)
	if base.is_empty() or config.is_empty() or config.requests.size() != 2:
		return {}
	var result: Dictionary = base.duplicate(true)
	# D5's original hygiene_sale is already the real Ian buyer's physical
	# transaction: reuse its visit ID, 90 VKC amount and HY05 provenance.
	var real: Dictionary = result.state.visits.get("hygiene_sale", {})
	if real.is_empty() or real.buyer != "ian" or real.seller != "player" or real.prices.get("HY05", {}).get("VKC", 0) != 90:
		return {}
	# Ian's D1 offer is a genuine named encounter, with no fake trade
	# window or funds. Only this new profile receives the extra visit.
	result.alpha_profile.days[0].append({
		"id":"alpha_ian_hygiene_offer_d1", "actor_id":"ian", "kind":"named",
		"purpose_key":"b2.commission.hygiene_ian", "contact_offer":false
	})
	result.alpha_profile.content_version = "b2-cards-commission-named-1"
	result.alpha_profile.commission_profile_id = Commission.NAMED_PROFILE
	return result
