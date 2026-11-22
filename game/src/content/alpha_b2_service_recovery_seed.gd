extends RefCounted
## Q05 isolated recovery pilot: extra D3 actual visitor only when customer missed D2.
## Reuses existing G02, W001, 30 VKC fee and actual workshop expense.
const ServiceSeed = preload("res://src/content/alpha_b2_service_seed.gd")
const Custody = preload("res://src/domain/alpha_service_custody.gd")

static func content() -> Dictionary:
	var original: Dictionary = ServiceSeed.content()
	var cfg: Dictionary = Custody.config(Custody.RECOVERY_PROFILE_ID)
	if original.is_empty() or cfg.is_empty() or cfg.jobs.size() != 1:
		return {}
	var next: Dictionary = original.duplicate(true)
	var job: Dictionary = cfg.jobs[0]
	var day: Array = next.alpha_profile.days[int(job.recovery_day)-1]
	if day.size() >= 10:
		return {}
	for visit: Dictionary in day:
		if visit.actor_id == job.actor_id or visit.id == job.recovery_visit_id:
			return {}
	day.append({"id":job.recovery_visit_id,"actor_id":job.actor_id,"kind":"regular","purpose_key":"b2.service.return","contact_offer":false})
	next.alpha_profile.content_version = "b2-cards-commission-service-recovery-2"
	next.alpha_profile.service_profile_id = Custody.RECOVERY_PROFILE_ID
	return next
