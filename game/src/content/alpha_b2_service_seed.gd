extends RefCounted
## Standalone B2 service/custody pilot, atop the fully verified named+regular
## procurement scenario. Original W001/G02 is never replicated or sold.
const Named = preload("res://src/content/alpha_b2_named_commission_seed.gd")
const Service = preload("res://src/domain/alpha_service_custody.gd")

static func content() -> Dictionary:
	var base: Dictionary = Named.content()
	var cfg: Dictionary = Service.config()
	if base.is_empty() or cfg.is_empty() or cfg.jobs.size() != 1:
		return {}
	var data: Dictionary = base.duplicate(true)
	var item: Dictionary = data.state.items.get("W001", {})
	if item.is_empty() or item.owner_id != "G02" or item.custodian_id != "G02" or item.functional or item.status != "stock" or not data.state.inventories.has("service_grid"):
		return {}
	var d2: Array = data.alpha_profile.days[1]
	for row: Dictionary in d2:
		if row.actor_id == "G02" or row.id == "alpha_service_g02_return_d2":
			return {}
	data.alpha_profile.days[1].append({
		"id":"alpha_service_g02_return_d2","actor_id":"G02","kind":"regular",
		"purpose_key":"b2.service.return","contact_offer":false
	})
	data.alpha_profile.content_version = "b2-cards-commission-service-1"
	data.alpha_profile["service_profile_id"] = Service.PROFILE_ID
	return data
