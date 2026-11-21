extends RefCounted
## B1 reuses the current finite demo inventory/wallet/actor identities without
## adopting its legacy clock, trade fixtures or future contract mutations.
const Demo = preload("res://src/content/demo7_seed.gd")

static func content() -> Dictionary:
	var original: Dictionary = Demo.content()
	if original.is_empty():
		return {}
	var days: Array = []
	for day_index: int in range(original.profile.visit_days.size()):
		var day: Array = []
		var seen: Dictionary = {}
		var key: String = "d" + str(day_index + 1)
		for visit_id: String in original.profile.visit_days[key]:
			if not original.state.visits.has(visit_id):
				continue
			var visit: Dictionary = original.state.visits[visit_id]
			var actor: String = str(visit.seller if visit.buyer == "player" else visit.buyer)
			if seen.has(actor):
				continue
			seen[actor] = true
			day.append({
				"id": visit_id, "actor_id": actor,
				"kind": "named" if actor in ["ian", "marcus"] else "regular",
				"purpose_key": "alpha.purpose.trade",
				"contact_offer": actor == "G01"
			})
		# Existing supplier; presentation-only visit. Contract is not accepted or charged here.
		if day_index == 0:
			day.append({"id":"alpha_marcus_intro","actor_id":"marcus","kind":"named","purpose_key":"alpha.purpose.contract","contact_offer":false})
		days.append(day)
	return {"defs": original.defs, "state": original.state,
		"alpha_profile": {"id":"alpha_b1_v1","content_version":"b1-preview-2",
			"days": days, "unavailable_actors":[]}}
