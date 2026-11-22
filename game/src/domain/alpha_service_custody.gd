extends RefCounted
## Isolated B2 custody-service commission. Original customer always owns the
## existing object; only lawful custody and bounded restoration permission move.
## Neither acceptance nor repair mints a new item or transaction visit.
const Rules = preload("res://src/domain/value_rules.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const PATH: String = "res://data/alpha_b2/service_custody_pilot_1.json"
const PROFILE_ID: String = "b2_service_custody_pilot_1"
const RECOVERY_PROFILE_ID: String = "b2_service_custody_recovery_2"
const RECOVERY_PATH: String = "res://data/alpha_b2/service_custody_recovery_2.json"
const MULTI_PROFILE_ID: String = "b2_service_custody_multi_3"
const MULTI_PATH: String = "res://data/alpha_b2/service_custody_multi_3.json"
const ACTIONS: Array = ["alpha_service_accept","alpha_service_decline","alpha_service_repair","alpha_service_deliver","alpha_service_return_unpaid"]

static func config(profile_id: String = PROFILE_ID) -> Dictionary:
	if profile_id not in [PROFILE_ID, RECOVERY_PROFILE_ID, MULTI_PROFILE_ID]:
		return {}
	var source: String = MULTI_PATH if profile_id == MULTI_PROFILE_ID else (RECOVERY_PATH if profile_id == RECOVERY_PROFILE_ID else PATH)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(source))
	if not Rules.keys(data,["version","profile_id","jobs"]) or data.version != 1 or data.profile_id != profile_id or not data.jobs is Array or data.jobs.is_empty() or data.jobs.size() > 3:
		return {}
	return data

static func profile_valid(profile: Dictionary, state: Dictionary) -> bool:
	var cfg: Dictionary = config(str(profile.get("service_profile_id","")))
	if cfg.is_empty() or not profile.has("days") or not state.inventories.has("service_grid") or state.inventories.service_grid.owner_id != "player":
		return false
	var ids: Dictionary = {}
	var item_ids: Dictionary = {}
	var custody_slots: Dictionary = {}
	for job: Dictionary in cfg.jobs:
		var required: Array = ["job_id","actor_id","offer_visit_id","return_visit_id","offer_day","due_day","item_id","fee","text_key"]
		var recovery: bool = str(profile.service_profile_id) in [RECOVERY_PROFILE_ID,MULTI_PROFILE_ID]
		if recovery:
			required.append_array(["recovery_visit_id","recovery_day"])
		if str(profile.service_profile_id) == MULTI_PROFILE_ID:
			required.append("placement")
		if not Rules.keys(job,required):
			return false
		if recovery and (not Rules.identifier(job.recovery_visit_id) or not Rules.integer(job.recovery_day,int(job.due_day)+1,profile.days.size()) or job.recovery_visit_id in [job.offer_visit_id,job.return_visit_id]):
			return false
		for key: String in ["job_id","actor_id","offer_visit_id","return_visit_id","item_id","text_key"]:
			if not Rules.identifier(job[key]):
				return false
		if ids.has(job.job_id) or item_ids.has(job.item_id) or job.offer_visit_id == job.return_visit_id or not Rules.integer(job.offer_day,1,profile.days.size()) or not Rules.integer(job.due_day,int(job.offer_day)+1,profile.days.size()) or not Objects.money(job.fee,false):
			return false
		if int(job.fee.VKC)+int(job.fee.USD) <= 0 or (int(job.fee.VKC)>0 and int(job.fee.USD)>0):
			return false
		if not state.wallets.has(job.actor_id) or not state.items.has(job.item_id) or state.visits.has(job.return_visit_id):
			return false
		var item: Dictionary = state.items[job.item_id]
		if item.owner_id != job.actor_id or item.custodian_id != job.actor_id or item.inventory != job.actor_id+"_grid" or item.status != "stock" or item.functional or item.service_permission or item.protected or not item.reservation_id.is_empty() or not item.parent_id.is_empty():
			return false
		var offered: bool = false
		var returned: bool = false
		for row: Dictionary in profile.days[int(job.offer_day)-1]:
			if row.id == job.offer_visit_id and row.actor_id == job.actor_id:
				offered = true
		for row: Dictionary in profile.days[int(job.due_day)-1]:
			if row.id == job.return_visit_id and row.actor_id == job.actor_id and row.kind == "regular":
				returned = true
		if not offered or not returned:
			return false
		if str(profile.service_profile_id) == MULTI_PROFILE_ID:
			var placement: Variant = job.get("placement",{})
			if not Rules.keys(placement,["inventory","x","y","rotated"]) or placement.inventory != "service_grid" or placement.rotated != false or not Rules.integer(placement.x,0,int(state.inventories.service_grid.width)-1) or not Rules.integer(placement.y,0,int(state.inventories.service_grid.height)-1):
				return false
			var slot: String = str(placement.x) + ":" + str(placement.y)
			if custody_slots.has(slot):
				return false
			custody_slots[slot] = true
		if recovery:
			var recovery_found: bool = false
			for row: Dictionary in profile.days[int(job.recovery_day)-1]:
				if row.id == job.recovery_visit_id and row.actor_id == job.actor_id and row.kind == "regular":
					recovery_found = true
			if not recovery_found or state.visits.has(job.recovery_visit_id):
				return false
		ids[job.job_id] = true
		item_ids[job.item_id] = true
	return true

static func _id(state: Dictionary) -> String:
	return str(state.alpha_shop.profile.get("service_profile_id",""))

static func _job(state: Dictionary, job_id: String) -> Dictionary:
	for row: Dictionary in config(_id(state)).get("jobs",[]):
		if row.job_id == job_id:
			return row
	return {}

static func is_return_visit(visit_id: String, profile_id: String) -> bool:
	for row: Dictionary in config(profile_id).get("jobs",[]):
		if row.return_visit_id == visit_id or (row.has("recovery_visit_id") and row.recovery_visit_id == visit_id):
			return true
	return false

static func seed(profile_id: String) -> Dictionary:
	var jobs: Dictionary = {}
	for row: Dictionary in config(profile_id).get("jobs",[]):
		jobs[row.job_id] = {"status":"unoffered","accepted_action":"","work_action":"","return_action":"","original":{},"paid":{"VKC":0,"USD":0}}
	return {"jobs":jobs,"settlements":[]}

static func current(state: Dictionary, row: Dictionary, returning: bool = false) -> bool:
	var a: Dictionary = state.alpha_shop
	if a.phase != "CUSTOMER_ACTIVE":
		return false
	if not returning:
		return a.day == row.offer_day and a.active == row.offer_visit_id
	if a.day == row.due_day and a.active == row.return_visit_id:
		return true
	return row.has("recovery_visit_id") and a.day == row.recovery_day and a.active == row.recovery_visit_id and state.alpha_shop.services.jobs[row.job_id].status == "overdue_custody"

static func scheduled(state: Dictionary, visit_id: String) -> bool:
	for row: Dictionary in config(_id(state)).get("jobs",[]):
		if row.return_visit_id == visit_id:
			return state.alpha_shop.services.jobs[row.job_id].status in ["accepted","repaired"]
		if row.has("recovery_visit_id") and row.recovery_visit_id == visit_id:
			return state.alpha_shop.services.jobs[row.job_id].status == "overdue_custody"
	return true

static func on_entry(state: Dictionary, action_id: String) -> void:
	for row: Dictionary in config(_id(state)).jobs:
		var job: Dictionary = state.alpha_shop.services.jobs[row.job_id]
		if job.status == "unoffered" and current(state,row):
			job.status = "offered"

static func on_leave(state: Dictionary, action_id: String) -> void:
	for row: Dictionary in config(_id(state)).jobs:
		var job: Dictionary = state.alpha_shop.services.jobs[row.job_id]
		if job.status == "offered" and current(state,row):
			job.status = "missed"

static func on_close(state: Dictionary, action_id: String) -> void:
	for row: Dictionary in config(_id(state)).jobs:
		var job: Dictionary = state.alpha_shop.services.jobs[row.job_id]
		if state.alpha_shop.day == row.offer_day and job.status in ["unoffered","offered"]:
			job.status = "missed"

static func on_settle(state: Dictionary, action_id: String) -> void:
	for row: Dictionary in config(_id(state)).jobs:
		var job: Dictionary = state.alpha_shop.services.jobs[row.job_id]
		# Unclaimed customer property remains legally their property and in
		# actual shop custody; never teleport an item to simulate a missed pickup.
		if state.alpha_shop.day == row.due_day and job.status in ["accepted","repaired"]:
			job.status = "overdue_custody"

static func work_gate(state: Dictionary, p: Dictionary) -> String:
	if not Rules.keys(p,["job_id","item_id"]) or not Rules.identifier(p.job_id) or not Rules.identifier(p.item_id):
		return "alpha_service_work_shape"
	var row: Dictionary = _job(state,p.job_id)
	if row.is_empty() or row.item_id != p.item_id or state.alpha_shop.phase != "EVENING_WORK":
		return "alpha_service_work_phase"
	var job: Dictionary = state.alpha_shop.services.jobs[row.job_id]
	var item: Dictionary = state.items[row.item_id]
	if job.status != "accepted" or item.owner_id != row.actor_id or item.custodian_id != "player" or item.status != "custody_service" or not item.service_permission or not item.reservation_id.is_empty() or item.functional:
		return "alpha_service_work_permission"
	return ""

static func after_work(state: Dictionary, job_id: String, action_id: String) -> void:
	var job: Dictionary = state.alpha_shop.services.jobs[job_id]
	job.status = "repaired"
	job.work_action = action_id

static func apply(state: Dictionary, command: Dictionary) -> String:
	var p: Dictionary = command.payload
	if command.type not in ACTIONS or command.type == "alpha_service_repair" or not Rules.keys(p,["job_id"]) or not Rules.identifier(p.job_id):
		return "alpha_service_shape"
	var row: Dictionary = _job(state,p.job_id)
	if row.is_empty():
		return "alpha_service_unknown"
	var job: Dictionary = state.alpha_shop.services.jobs[row.job_id]
	var item: Dictionary = state.items[row.item_id]
	if command.type in ["alpha_service_accept","alpha_service_decline"]:
		if job.status != "offered" or not current(state,row):
			return "alpha_service_offer"
		if command.type == "alpha_service_decline":
			job.status = "declined"
			return ""
		if item.owner_id != row.actor_id or item.custodian_id != row.actor_id or item.inventory != row.actor_id+"_grid" or item.status != "stock" or item.functional or item.protected or not item.reservation_id.is_empty() or not item.parent_id.is_empty():
			return "alpha_service_custody"
		job.original = {"inventory":item.inventory,"x":int(item.x),"y":int(item.y),"rotated":bool(item.rotated)}
		item.owner_id = row.actor_id
		item.custodian_id = "player"
		item.status = "custody_service"
		item.service_permission = true
		var placement: Dictionary = row.get("placement",{"inventory":"service_grid","x":0,"y":0,"rotated":false})
		item.inventory = str(placement.inventory)
		item.x = int(placement.x)
		item.y = int(placement.y)
		item.rotated = bool(placement.rotated)
		item.version += 1
		job.status = "accepted"
		job.accepted_action = command.action_id
		return ""
	if not current(state,row,true) or job.status not in ["accepted","repaired","overdue_custody"] or item.owner_id != row.actor_id or item.custodian_id != "player" or item.status != "custody_service" or not item.service_permission or not item.reservation_id.is_empty():
		return "alpha_service_return_permission"
	var paid: bool = command.type == "alpha_service_deliver"
	if paid and (job.work_action.is_empty() or not item.functional or not item.restored):
		return "alpha_service_unfinished"
	var fee: Dictionary = Rules.normalized(row.fee.duplicate(true))
	if paid:
		for curr: String in ["VKC","USD"]:
			if state.wallets[row.actor_id][curr] < fee[curr] or not Rules.integer(state.wallets.player[curr]+fee[curr]):
				return "alpha_service_funds"
	# Only the original physical inventory slot is allowed; final state
	# goes through ObjectSchema/grid validation on the detached candidate.
	item.custodian_id = row.actor_id
	item.status = "stock"
	item.service_permission = false
	for field: String in ["inventory","x","y","rotated"]:
		item[field] = job.original[field]
	item.version += 1
	if paid:
		for curr: String in ["VKC","USD"]:
			state.wallets[row.actor_id][curr] -= fee[curr]
			state.wallets.player[curr] += fee[curr]
		job.paid = fee.duplicate(true)
		job.status = "delivered"
	else:
		job.status = "returned_unpaid"
	job.return_action = command.action_id
	state.alpha_shop.services.settlements.append({"job_id":row.job_id,"action_id":command.action_id,"item_id":row.item_id,"actor_id":row.actor_id,"paid":fee if paid else {"VKC":0,"USD":0}})
	state.alpha_shop.outcomes[state.alpha_shop.active] = "service_delivered" if paid else "service_returned"
	state.alpha_shop.phase = "CUSTOMER_EXIT"
	return ""

static func view(state: Dictionary) -> Dictionary:
	var result: Dictionary = {"entries":[]}
	if not state.alpha_shop.has("services"):
		return result
	for row: Dictionary in config(_id(state)).get("jobs",[]):
		var job: Dictionary = state.alpha_shop.services.jobs[row.job_id]
		if job.status == "unoffered" and state.alpha_shop.active != row.offer_visit_id:
			continue
		var item: Dictionary = state.items[row.item_id]
		result.entries.append({
			"job_id":row.job_id,"actor_id":row.actor_id,"item_id":row.item_id,
			"status":job.status,"fee":Rules.normalized(row.fee.duplicate(true)),
			"due_day":row.due_day,"recovery_day":int(row.get("recovery_day",0)),"text_key":row.text_key,"def_id":item.def_id,
			"can_accept":job.status=="offered" and current(state,row),
			"can_repair":job.status=="accepted" and state.alpha_shop.phase=="EVENING_WORK",
			"can_deliver":job.status in ["repaired","overdue_custody"] and not str(job.work_action).is_empty() and item.functional and item.restored and current(state,row,true),
			"can_return":job.status in ["accepted","repaired","overdue_custody"] and current(state,row,true)
		})
	return result
