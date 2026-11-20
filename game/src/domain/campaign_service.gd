extends RefCounted
## A1c2: fixed service offers and real custody/return, no separate item registry.
## All writes happen on the single GameSession candidate, replayed from trusted seed.
const Rules = preload("res://src/domain/value_rules.gd")
const Clock = preload("res://src/domain/business_clock.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const Relations = preload("res://src/domain/object_relation_primitives.gd")
const ACTIONS: Array = ["calendar_accept_service", "calendar_deliver_service", "calendar_return_unpaid"]

static func seed(s: Dictionary, defs: Dictionary, profile: Dictionary) -> Dictionary:
	var configured: Variant = profile.get("services")
	if not configured is Dictionary or configured.size() > 128 or not profile.visit_days is Dictionary or not Objects.validate(s, defs):
		return {}
	var days: Dictionary = {}
	for index: int in range(profile.day_ids.size()):
		var ids: Variant = profile.visit_days.get(profile.day_ids[index])
		if not ids is Array:
			return {}
		for visit: Variant in ids:
			if not Rules.identifier(visit) or days.has(visit):
				return {}
			days[visit] = index
	# A demo may retain explicitly authored next-day pickups without running them.
	var carry:Dictionary=profile.get("carryover_returns",{})
	for visit:Variant in carry:
		if not Rules.identifier(visit) or days.has(visit) or s.visits.has(visit) or not Rules.integer(carry[visit],profile.day_ids.size()+1,profile.day_ids.size()+1):
			return {}
		days[visit]=int(carry[visit])-1
	var result: Dictionary = {"jobs": {}, "visits": {}}
	var used_items: Dictionary = {}
	for id: Variant in configured:
		var t: Variant = configured[id]
		if not Rules.identifier(id) or not Rules.keys(t, ["offer_id", "return_ids", "item_id", "customer", "fee", "placement"]):
			return {}
		if not Rules.identifier(t.offer_id) or not days.has(t.offer_id) or not t.return_ids is Array or t.return_ids.is_empty() or not Rules.identifier(t.item_id) or used_items.has(t.item_id) or not s.items.has(t.item_id) or not Rules.identifier(t.customer) or t.customer == "player" or not s.wallets.has(t.customer):
			return {}
		if not Objects.money(t.fee, false) or (t.fee.VKC == 0 and t.fee.USD == 0) or not Rules.keys(t.placement, ["inventory", "x", "y", "rotated"]):
			return {}
		var dest: Dictionary = t.placement
		if not Rules.identifier(dest.inventory) or not s.inventories.has(dest.inventory) or s.inventories[dest.inventory].owner_id != "player" or not s.inventories[dest.inventory].host_item.is_empty() or not Rules.integer(dest.x, 0, 9) or not Rules.integer(dest.y, 0, 9) or not dest.rotated is bool:
			return {}
		var item: Dictionary = s.items[t.item_id]
		if not defs[item.def_id].restorable or not defs[item.def_id].inside.is_empty() or not item.parent_id.is_empty():
			return {}
		var last: int = int(days[t.offer_id])
		for visit: Variant in [t.offer_id] + t.return_ids:
			if not Rules.identifier(visit) or not days.has(visit) or result.visits.has(visit) or s.visits.has(visit):
				return {}
			if carry.has(visit) and (visit==t.offer_id or int(days[t.offer_id])!=profile.day_ids.size()-1):
				return {}
			if visit != t.offer_id:
				if int(days[visit]) <= last:
					return {}
				last = int(days[visit])
			result.visits[visit] = {"job_id": id, "kind": "offer" if visit == t.offer_id else "return", "day": int(days[visit]) + 1}
		used_items[t.item_id] = true
		result.jobs[id] = {"terms": t.duplicate(true), "status": "offered", "original": {}, "accepted_action": "", "work_action": "", "return_action": "", "paid": {"VKC": 0, "USD": 0}}
	for visit:String in carry:
		if not result.visits.has(visit) or result.visits[visit].kind!="return":
			return {}
	# No pre-existing service custody may bypass this authority.
	for item: Dictionary in s.items.values():
		if item.status == "custody_service" or item.service_permission:
			return {}
	return result

static func entry(s: Dictionary, visit: String) -> Dictionary:
	return s.calendar.get("services", {}).get("visits", {}).get(visit, {})

static func eligible(s: Dictionary, visit: String) -> bool:
	var e: Dictionary = entry(s, visit)
	if e.is_empty():
		return true
	var job: Dictionary = s.calendar.services.jobs[e.job_id]
	return job.status == "offered" if e.kind == "offer" else job.status in ["accepted", "complete"]

static func offer_ended(s: Dictionary, visit: String, outcome: String) -> void:
	var e: Dictionary = entry(s, visit)
	if not e.is_empty() and e.kind == "offer" and s.calendar.services.jobs[e.job_id].status == "offered":
		s.calendar.services.jobs[e.job_id].status = outcome

static func terms_view(s: Dictionary, visit: String) -> Dictionary:
	var e: Dictionary = entry(s, visit)
	if e.is_empty():
		return {}
	var job: Dictionary = s.calendar.services.jobs[e.job_id]
	return {"kind": "service_" + e.kind, "job_id": e.job_id, "item_id": job.terms.item_id, "customer": job.terms.customer, "fee": job.terms.fee.duplicate(true), "status": job.status}

static func view(s: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: String in s.calendar.get("services", {}).get("jobs", {}):
		var job: Dictionary = s.calendar.services.jobs[id]
		if not job.accepted_action.is_empty():
			result[id] = {"item_id": job.terms.item_id, "customer": job.terms.customer, "fee": job.terms.fee.duplicate(true), "status": job.status, "paid": job.paid.duplicate(true)}
	return result

static func work_job(s: Dictionary, item_id: Variant) -> String:
	if not Rules.identifier(item_id):
		return ""
	for id: String in s.calendar.get("services", {}).get("jobs", {}):
		var job: Dictionary = s.calendar.services.jobs[id]
		if job.terms.item_id == item_id and job.status == "accepted":
			return id
	return ""

static func finish_work(s: Dictionary, id: String, action: String) -> void:
	var job: Dictionary = s.calendar.services.jobs[id]
	job.status = "complete"
	job.work_action = action

static func funded(s: Dictionary, job: Dictionary) -> bool:
	for currency: String in ["VKC", "USD"]:
		if s.wallets[job.terms.customer][currency] < job.terms.fee[currency] or not Rules.integer(s.wallets.player[currency] + job.terms.fee[currency]):
			return false
	return true

static func apply(s: Dictionary, defs: Dictionary, kind: String, p: Dictionary, action: String) -> String:
	if not s.calendar.has("services") or not Clock.business_at(int(s.game_minutes), s.phase) or not Rules.keys(p, ["visit_id", "job_id"]) or not Rules.identifier(p.visit_id) or not Rules.identifier(p.job_id) or s.calendar.queue.active != p.visit_id or s.calendar.queue.outcomes.has(p.visit_id):
		return "service_visit"
	var e: Dictionary = entry(s, p.visit_id)
	if e.is_empty() or e.job_id != p.job_id or e.day != Clock.day_index(int(s.game_minutes)) or not eligible(s, p.visit_id):
		return "service_visit"
	var job: Dictionary = s.calendar.services.jobs[p.job_id]
	var t: Dictionary = job.terms
	if not s.items.has(t.item_id):
		return "service_item"
	var item: Dictionary = s.items[t.item_id]
	if kind == "calendar_accept_service":
		if e.kind != "offer" or job.status != "offered" or item.functional or not Objects.complete(s, defs, t.item_id) or not funded(s, job):
			return "service_accept"
		var family: Dictionary = Relations.disposition_family(Objects.nodes(s, defs), t.item_id, t.customer)
		if not family.ok or not s.inventories[item.inventory].host_item.is_empty() or not defs[item.def_id].inside.is_empty():
			return "service_custody"
		job.original = {"inventory": item.inventory, "x": item.x, "y": item.y, "rotated": item.rotated}
		for id: String in family.item_ids:
			var row: Dictionary = s.items[id]
			row.custodian_id = "player"
			row.status = "custody_service"
			row.service_permission = id == t.item_id
			row.version += 1
		for key: String in t.placement:
			item[key] = t.placement[key]
		job.status = "accepted"
		job.accepted_action = action
	elif kind in ["calendar_deliver_service", "calendar_return_unpaid"]:
		if e.kind != "return" or job.status not in ["accepted", "complete"] or item.owner_id != t.customer or item.custodian_id != "player" or item.status != "custody_service" or not item.service_permission:
			return "service_return"
		var paid: bool = kind == "calendar_deliver_service"
		if paid and (job.status != "complete" or not item.functional or not item.restored or not funded(s, job)):
			return "service_payment"
		if not Objects.destination_accessible(s, job.original.inventory, t.customer, t.customer):
			return "service_return_grid"
		for id: String in Objects.family(s, t.item_id):
			var row: Dictionary = s.items[id]
			if row.owner_id != t.customer or row.custodian_id != "player" or row.status != "custody_service" or row.protected or not row.reservation_id.is_empty():
				return "service_custody"
			row.custodian_id = t.customer
			row.status = "stock"
			row.service_permission = false
			row.version += 1
		for key: String in job.original:
			item[key] = job.original[key]
		if paid:
			for currency: String in ["VKC", "USD"]:
				s.wallets[t.customer][currency] -= t.fee[currency]
				s.wallets.player[currency] += t.fee[currency]
			job.paid = t.fee.duplicate(true)
		job.status = "delivered" if paid else ("returned_unpaid" if not job.work_action.is_empty() else "cancelled")
		job.return_action = action
	else:
		return "service_command"
	return ""
