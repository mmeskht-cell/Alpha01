extends RefCounted
## A separately saved B2 commission pilot: same real shop authority, existing
## civilian G03 wallet, and authored Day4 revisit. No buyer/item/cash mint.
const Cards = preload("res://src/content/alpha_b2_cards_seed.gd")
const Commission = preload("res://src/domain/alpha_commission.gd")

static func content() -> Dictionary:
	var base: Dictionary = Cards.content()
	var conf: Dictionary = Commission.config()
	if base.is_empty() or conf.is_empty() or conf.requests.size() != 1:
		return {}
	var next: Dictionary = base.duplicate(true)
	next.alpha_profile.content_version = "b2-cards-commission-1"
	next.alpha_profile["commission_profile_id"] = conf.profile_id
	for r: Dictionary in conf.requests:
		if next.state.visits.has(r.return_visit_id) or not next.state.items.has(r.return_item_id):
			return {}
		var amount: Dictionary = r.price.duplicate(true)
		next.state.visits[r.return_visit_id] = {
			"scope":{"visit_id":r.return_visit_id,"kind":"ordinary","purpose":"sale","completed":false,"required_ids":[]},
			"seller":"player","buyer":r.actor_id,
			"prices":{r.return_item_id:amount},
			"opens":(int(r.due_day)-1)*1440,
			"expires":(int(r.due_day)-1)*1440+600,
			"allow_inspection":false
		}
		next.alpha_profile.days[int(r.due_day)-1].append({
			"id":r.return_visit_id,"actor_id":r.actor_id,"kind":"regular",
			"purpose_key":"alpha.purpose.commission_return","contact_offer":false
		})
	return next
