extends RefCounted
## Opt-in B2 two-customer custody profile: both original demo service objects
## already exist, belong to two real NPC wallets, and have bounded due visits.
## Neither this content nor its calendar creates stock, cash or settlements.
const RecoverySeed = preload("res://src/content/alpha_b2_service_recovery_seed.gd")
const Custody = preload("res://src/domain/alpha_service_custody.gd")

static func content() -> Dictionary:
	var base: Dictionary = RecoverySeed.content()
	var cfg: Dictionary = Custody.config(Custody.MULTI_PROFILE_ID)
	if base.is_empty() or cfg.is_empty() or cfg.jobs.size() != 2:
		return {}
	var next: Dictionary = base.duplicate(true)
	for job: Dictionary in cfg.jobs:
		# G02 already owns the D3 recovery row inherited from RecoverySeed.
		# Only new G04 appointments are appended to finite day capacity.
		for appointment: Dictionary in [
			{"id":job.return_visit_id,"day":int(job.due_day)},
			{"id":job.recovery_visit_id,"day":int(job.recovery_day)}
		]:
			var rows: Array = next.alpha_profile.days[int(appointment.day)-1]
			var found: bool = false
			for row: Dictionary in rows:
				if row.id == appointment.id and row.actor_id == job.actor_id:
					found = true
					break
				if row.id == appointment.id or row.actor_id == job.actor_id:
					return {}
			if found:
				continue
			if rows.size() >= 10:
				return {}
			rows.append({"id":appointment.id,"actor_id":job.actor_id,"kind":"regular","purpose_key":"b2.service.return","contact_offer":false})
	next.alpha_profile.content_version = "b2-cards-commission-service-multi-3"
	next.alpha_profile.service_profile_id = Custody.MULTI_PROFILE_ID
	return next
