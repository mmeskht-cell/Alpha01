extends RefCounted
## New alpha profile only: finite, zero-deposit single-item incoming orders.
## An offer creates no money, item, buyer, or entitlement. The only delivery
## is a real GameSession._transfer with a source-bound authored return visit.
const Rules = preload("res://src/domain/value_rules.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const PROFILE_DIRECTORY: String = "res://data/alpha_b2/"
const PROFILE_REGISTRY: String = "res://data/alpha_b2/commission_profiles_1.json"
const DEFAULT_PROFILE: String = "b2_commission_pilot_1"
const NAMED_PROFILE: String = "b2_commission_named_parity_1"
const ACTIONS: Array = ["alpha_commission_accept", "alpha_commission_decline", "alpha_commission_reserve", "alpha_commission_cancel", "alpha_commission_deliver"]

## Data-only, strictly confined registry. Existing published IDs stay pinned
## to their original files, so changing this index cannot silently substitute
## a different authored economy for a restored pilot save.
static func profiles() -> Dictionary:
	var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_REGISTRY))
	if not Rules.keys(record, ["version", "profiles"]) or record.version != 1 or not record.profiles is Dictionary:
		return {}
	var entries: Dictionary = record.profiles
	if entries.size() < 2 or entries.size() > 16:
		return {}
	if entries.get(DEFAULT_PROFILE, "") != "commission_pilot_1.json" or entries.get(NAMED_PROFILE, "") != "commission_named_parity_1.json":
		return {}
	for id: Variant in entries:
		var filename: Variant = entries[id]
		if not Rules.identifier(id) or not filename is String:
			return {}
		if filename != filename.get_file() or not filename.begins_with("commission_") or not filename.ends_with("_1.json") or filename.contains("..") or not Rules.identifier(filename):
			return {}
	return entries

static func config(profile_id: String = DEFAULT_PROFILE) -> Dictionary:
	if not Rules.identifier(profile_id):
		return {}
	var entries: Dictionary = profiles()
	if not entries.has(profile_id):
		return {}
	var path: String = PROFILE_DIRECTORY + str(entries[profile_id])
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not Rules.keys(value, ["version", "profile_id", "requests"]) or value.version != 1 or value.profile_id != profile_id or not value.requests is Array:
		return {}
	if value.requests.is_empty() or value.requests.size() > 16:
		return {}
	return value

static func _profile_id(state: Dictionary) -> String:
	return str(state.alpha_shop.profile.get("commission_profile_id", "")) if state.has("alpha_shop") else ""

static func profile_valid(profile: Dictionary, state: Dictionary) -> bool:
	return profile_valid_with_config(profile, state, config(str(profile.get("commission_profile_id", ""))))

## Pure shape/authority check also exercised against malformed Q08 fixture
## copies. The runtime path always supplies a registry-validated config.
static func profile_valid_with_config(profile: Dictionary, state: Dictionary, c: Dictionary) -> bool:
	if not Rules.keys(c, ["version", "profile_id", "requests"]) or c.version != 1 or not c.requests is Array or c.requests.is_empty() or c.requests.size() > 16:
		return false
	if profile.get("commission_profile_id") != c.profile_id or not profile.has("days") or not profile.days is Array:
		return false
	var ids: Dictionary = {}
	var offer_visits: Dictionary = {}
	var return_visits: Dictionary = {}
	var source_items: Dictionary = {}
	for r: Variant in c.requests:
		var shape: Array = ["request_id","actor_id","offer_visit_id","return_visit_id","offer_day","due_day","target_def_id","return_item_id","require_functional","price","text_key"]
		# Strict exact-key validation also applies to the two optional
		# receiver-grid coordinates: allow both together, never only one.
		if r is Dictionary and (r.has("delivery_x") or r.has("delivery_y")):
			shape.append_array(["delivery_x","delivery_y"])
		if not Rules.keys(r, shape):
			return false
		for key: String in ["request_id","actor_id","offer_visit_id","return_visit_id","target_def_id","return_item_id","text_key"]:
			if not Rules.identifier(r[key]):
				return false
		if ids.has(r.request_id) or offer_visits.has(r.offer_visit_id) or return_visits.has(r.return_visit_id) or source_items.has(r.return_item_id) or return_visits.has(r.offer_visit_id) or offer_visits.has(r.return_visit_id) or r.offer_visit_id == r.return_visit_id or not Rules.integer(r.offer_day, 1, profile.days.size()) or not Rules.integer(r.due_day, int(r.offer_day) + 1, profile.days.size()):
			return false
		if not r.require_functional is bool or not Objects.money(r.price, false) or int(r.price.VKC) + int(r.price.USD) <= 0 or (int(r.price.VKC) > 0 and int(r.price.USD) > 0):
			return false
		# An authored return must choose a real free cell in the receiver's
		# existing physical inventory. The old pilot defaults to (0,0).
		if not Rules.integer(r.get("delivery_x", 0), 0, 9) or not Rules.integer(r.get("delivery_y", 0), 0, 5):
			return false
		if not state.wallets.has(r.actor_id) or not state.items.has(r.return_item_id) or state.items[r.return_item_id].def_id != r.target_def_id:
			return false
		var visit: Dictionary = state.visits.get(r.return_visit_id, {})
		if visit.is_empty() or visit.seller != "player" or visit.buyer != r.actor_id or visit.prices.size() != 1 or Rules.canonical(visit.prices.get(r.return_item_id, {})) != Rules.canonical(r.price) or visit.opens != (int(r.due_day) - 1) * 1440 or visit.scope.kind != "ordinary" or visit.scope.purpose != "sale":
			return false
		var offer: bool = false
		var returned: bool = false
		for row: Dictionary in profile.days[int(r.offer_day) - 1]:
			if row.id == r.offer_visit_id and row.actor_id == r.actor_id:
				offer = true
		for row: Dictionary in profile.days[int(r.due_day) - 1]:
			if row.id == r.return_visit_id and row.actor_id == r.actor_id:
				returned = true
		if not offer or not returned:
			return false
		ids[r.request_id] = true
		offer_visits[r.offer_visit_id] = true
		return_visits[r.return_visit_id] = true
		source_items[r.return_item_id] = true
	return true

static func seed(profile_id: String = DEFAULT_PROFILE) -> Dictionary:
	var entries: Dictionary = {}
	for r: Dictionary in config(profile_id).get("requests",[]):
		entries[r.request_id] = {
			"status":"unoffered","item_id":"","offer_action":"","accept_action":"",
			"reserve_action":"","deliver_action":"","end_action":"","verified_functional":false
		}
	return {"entries":entries,"settlements":[]}

static func current(state: Dictionary, r: Dictionary, return_trip: bool = false) -> bool:
	var a: Dictionary = state.alpha_shop
	return a.phase == "CUSTOMER_ACTIVE" and a.day == (r.due_day if return_trip else r.offer_day) and a.active == (r.return_visit_id if return_trip else r.offer_visit_id)

static func is_return_visit(visit_id: String, profile_id: String = DEFAULT_PROFILE) -> bool:
	for r: Dictionary in config(profile_id).get("requests", []):
		if r.return_visit_id == visit_id:
			return true
	return false

static func scheduled(state: Dictionary, visit_id: String) -> bool:
	for r: Dictionary in config(_profile_id(state)).get("requests", []):
		if r.return_visit_id == visit_id:
			return state.alpha_shop.commissions.entries[r.request_id].status in ["accepted","ready"]
	return true

static func _request(request_id: String, profile_id: String) -> Dictionary:
	for r: Dictionary in config(profile_id).get("requests",[]):
		if r.request_id == request_id:
			return r
	return {}

static func on_entry(state: Dictionary, action_id: String) -> void:
	for r: Dictionary in config(_profile_id(state)).requests:
		var entry: Dictionary = state.alpha_shop.commissions.entries[r.request_id]
		if entry.status == "unoffered" and current(state,r):
			entry.status = "offered"
			entry.offer_action = action_id

static func on_leave(state: Dictionary, action_id: String) -> void:
	for r: Dictionary in config(_profile_id(state)).requests:
		var entry: Dictionary = state.alpha_shop.commissions.entries[r.request_id]
		if entry.status == "offered" and current(state,r):
			entry.status = "missed"
			entry.end_action = action_id

static func on_close(state: Dictionary, action_id: String) -> void:
	for r: Dictionary in config(_profile_id(state)).requests:
		var entry: Dictionary = state.alpha_shop.commissions.entries[r.request_id]
		if state.alpha_shop.day == r.offer_day and entry.status in ["unoffered","offered"]:
			entry.status = "missed"
			entry.end_action = action_id

static func on_settle(state: Dictionary, action_id: String) -> void:
	for r: Dictionary in config(_profile_id(state)).requests:
		var entry: Dictionary = state.alpha_shop.commissions.entries[r.request_id]
		if state.alpha_shop.day == r.due_day and entry.status in ["accepted","ready"]:
			if entry.status == "ready" and state.items.has(entry.item_id) and state.items[entry.item_id].reservation_id == r.request_id:
				state.items[entry.item_id].reservation_id = ""
			entry.status = "expired"
			entry.end_action = action_id

## An accepted pickup is a real, still-unserved visit. Closing the shop
## before its authored appointment would expire the contract without giving
## the customer the promised chance to arrive. Closing becomes possible
## again after serving the visit or explicitly cancelling the obligation.
## No visit is created or extended here; this only protects the finite slot.
static func pending_pickup(state: Dictionary) -> String:
	var a: Dictionary = state.get("alpha_shop", {})
	if a.is_empty() or not a.has("commissions") or a.phase != "OPEN_IDLE":
		return ""
	var day: int = int(a.day)
	for r: Dictionary in config(_profile_id(state)).get("requests", []):
		if int(r.due_day) != day:
			continue
		var entry: Dictionary = a.commissions.entries.get(r.request_id, {})
		if str(entry.get("status", "")) not in ["accepted", "ready"]:
			continue
		for i: int in range(int(a.cursor), a.profile.days[day - 1].size()):
			if str(a.profile.days[day - 1][i].id) == str(r.return_visit_id):
				return str(r.request_id)
	return ""

static func reserve_gate(state: Dictionary, r: Dictionary, item_id: String) -> String:
	var a: Dictionary = state.alpha_shop
	if a.phase not in ["OPEN_IDLE","EVENING_WORK"] or a.day > r.due_day or not state.items.has(item_id):
		return "alpha_commission_reserve_phase"
	var item: Dictionary = state.items[item_id]
	if item_id != r.return_item_id or item.def_id != r.target_def_id:
		return "alpha_commission_wrong_item"
	if item.owner_id != "player" or item.custodian_id != "player" or item.inventory != "player_stock" or item.status != "stock" or item.protected or not item.reservation_id.is_empty() or not item.parent_id.is_empty() or item_id in a.displayed:
		return "alpha_commission_ownership"
	# Pilot's actual source specimen is a simple civilian good. Functional
	# checking occurs on the selected physical object, not on a claimed card.
	if r.require_functional and not item.functional:
		return "alpha_commission_function"
	return ""

static func apply(state: Dictionary, command: Dictionary) -> String:
	var p: Dictionary = command.payload
	if command.type not in ACTIONS or command.type == "alpha_commission_deliver" or not Rules.keys(p, ["request_id"]) and not Rules.keys(p, ["request_id","item_id"]):
		return "alpha_commission_shape"
	if not Rules.identifier(p.request_id):
		return "alpha_commission_shape"
	var r: Dictionary = _request(p.request_id, _profile_id(state))
	if r.is_empty():
		return "alpha_commission_unknown"
	var entry: Dictionary = state.alpha_shop.commissions.entries[r.request_id]
	match command.type:
		"alpha_commission_accept", "alpha_commission_decline":
			if not Rules.keys(p, ["request_id"]) or entry.status != "offered" or not current(state,r):
				return "alpha_commission_offer"
			if command.type == "alpha_commission_accept":
				entry.status = "accepted"
				entry.accept_action = command.action_id
			else:
				entry.status = "declined"
				entry.end_action = command.action_id
		"alpha_commission_reserve":
			if not Rules.keys(p, ["request_id","item_id"]) or not Rules.identifier(p.item_id) or entry.status != "accepted":
				return "alpha_commission_reserve_shape"
			var denial: String = reserve_gate(state,r,p.item_id)
			if not denial.is_empty():
				return denial
			state.items[p.item_id].reservation_id = r.request_id
			entry.item_id = p.item_id
			entry.status = "ready"
			entry.reserve_action = command.action_id
			entry.verified_functional = true if r.require_functional else false
		"alpha_commission_cancel":
			if not Rules.keys(p, ["request_id"]) or entry.status not in ["accepted","ready"] or state.alpha_shop.day > r.due_day or state.alpha_shop.phase not in ["OPEN_IDLE","EVENING_WORK"]:
				return "alpha_commission_cancel_denied"
			if entry.status == "ready" and state.items.has(entry.item_id) and state.items[entry.item_id].reservation_id == r.request_id:
				state.items[entry.item_id].reservation_id = ""
			entry.status = "cancelled"
			entry.end_action = command.action_id
		_:
			return "alpha_commission_command"
	return ""

static func delivery_gate(state: Dictionary, command: Dictionary) -> String:
	var p: Dictionary = command.payload
	if not Rules.keys(p,["request_id"]) or not Rules.identifier(p.request_id):
		return "alpha_commission_delivery_shape"
	var r: Dictionary = _request(p.request_id, _profile_id(state))
	if r.is_empty() or not state.alpha_shop.commissions.entries.has(r.request_id):
		return "alpha_commission_unknown"
	var entry: Dictionary = state.alpha_shop.commissions.entries[r.request_id]
	if entry.status != "ready" or not current(state,r,true) or entry.item_id != r.return_item_id:
		return "alpha_commission_delivery_context"
	var item: Dictionary = state.items.get(entry.item_id,{})
	var visit: Dictionary = state.visits.get(r.return_visit_id,{})
	if item.is_empty() or item.owner_id != "player" or item.custodian_id != "player" or item.inventory != "player_stock" or item.reservation_id != r.request_id or item.protected or item.status != "stock" or not item.parent_id.is_empty() or not visit.scope.has("completed") or visit.scope.completed:
		return "alpha_commission_delivery_ownership"
	if item.def_id != r.target_def_id or (r.require_functional and not item.functional):
		return "alpha_commission_delivery_quality"
	var curr: String = "VKC" if int(r.price.VKC) > 0 else "USD"
	if state.wallets[r.actor_id][curr] < int(r.price[curr]):
		return "alpha_commission_buyer_funds"
	return ""

static func transfer_payload(state: Dictionary, request_id: String) -> Dictionary:
	var r: Dictionary = _request(request_id, _profile_id(state))
	var item_id: String = state.alpha_shop.commissions.entries[request_id].item_id
	return {"visit_id":r.return_visit_id, "item_id":item_id,
		"seller":"player","buyer":r.actor_id,"currency":"VKC" if int(r.price.VKC) > 0 else "USD",
		"amount":int(r.price.VKC) if int(r.price.VKC) > 0 else int(r.price.USD),
		"inventory":r.actor_id+"_grid","x":int(r.get("delivery_x",0)),"y":int(r.get("delivery_y",0)),"rotated":false}

static func after_delivery(state: Dictionary, request_id: String, action_id: String) -> void:
	var r: Dictionary = _request(request_id, _profile_id(state))
	var entry: Dictionary = state.alpha_shop.commissions.entries[request_id]
	entry.status = "fulfilled"
	entry.deliver_action = action_id
	state.alpha_shop.commissions.settlements.append({"request_id":request_id,"action_id":action_id,"visit_id":r.return_visit_id,"item_id":entry.item_id,"price":Rules.normalized(r.price.duplicate(true))})
	state.alpha_shop.outcomes[state.alpha_shop.active] = "commission_delivered"
	state.alpha_shop.phase = "CUSTOMER_EXIT"

static func view(state: Dictionary) -> Dictionary:
	var result: Dictionary = {"entries":[]}
	if not state.alpha_shop.has("commissions"):
		return result
	var a: Dictionary = state.alpha_shop
	for r: Dictionary in config(_profile_id(state)).requests:
		var entry: Dictionary = a.commissions.entries[r.request_id]
		if entry.status == "unoffered" and a.active != r.offer_visit_id:
			continue
		var options: Array = []
		if entry.status == "accepted" and a.phase in ["OPEN_IDLE","EVENING_WORK"] and a.day <= r.due_day:
			for id: String in state.items:
				if reserve_gate(state,r,id).is_empty():
					options.append(id)
		var can_accept: bool = entry.status == "offered" and current(state,r)
		var can_deliver: bool = entry.status == "ready" and current(state,r,true)
		result.entries.append({
			"request_id":r.request_id,"actor_id":r.actor_id,"status":entry.status,
			"due_day":r.due_day,"price":r.price.duplicate(true),"target_def_id":r.target_def_id,
			"text_key":r.text_key,"item_id":entry.item_id,
			"can_accept":can_accept,"can_deliver":can_deliver,"can_cancel":entry.status in ["accepted","ready"] and a.day <= r.due_day,
			"reserve_options":options,"checked":entry.verified_functional
		})
	return result
