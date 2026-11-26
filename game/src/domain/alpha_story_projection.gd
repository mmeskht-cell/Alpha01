extends RefCounted
## Read-only authored narrative projection. Supported event kinds may be extended by data.
## This is not a quest executor, a new visit, or a source of economic effects.
const Rules = preload("res://src/domain/value_rules.gd")
const PATH: String = "res://data/alpha_b2/story_source_beats_1.json"

const MAX_BEATS: int = 256

static func config() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return validate(value)

static func validate(value: Variant) -> Dictionary:
	if not Rules.keys(value, ["version","beats"]) or value.version != 1 or not value.beats is Array or value.beats.size() > MAX_BEATS:
		return {}
	var ids: Dictionary = {}
	var triggers: Dictionary = {}
	for entry: Variant in value.beats:
		if not entry is Dictionary:
			return {}
		var fields: Array = ["id","kind","text_key"]
		match str(entry.get("kind","")):
			"customer_open":
				fields.append_array(["day","visit_id","actor_id","item_id"])
			"contract_fact":
				fields.append_array(["first_day","last_day","contract_id","status"])
			_:
				return {}
		if not Rules.keys(entry, fields) or not Rules.identifier(entry.id) or ids.has(entry.id) or not Rules.identifier(entry.text_key):
			return {}
		ids[entry.id] = true
		if entry.kind == "customer_open":
			if not Rules.integer(entry.day, 1, 42) or not Rules.identifier(entry.visit_id) or not Rules.identifier(entry.actor_id) or not Rules.identifier(entry.item_id):
				return {}
			var trigger := Rules.canonical([entry.kind,entry.day,entry.visit_id,entry.actor_id,entry.item_id])
			if triggers.has(trigger): return {}
			triggers[trigger] = true
		else:
			if not Rules.integer(entry.first_day, 1, 42) or not Rules.integer(entry.last_day, int(entry.first_day), 42) or not Rules.identifier(entry.contract_id) or entry.status not in ["paid", "defaulted"]:
				return {}
			for day: int in range(int(entry.first_day),int(entry.last_day)+1):
				var trigger := Rules.canonical([entry.kind,day,entry.contract_id,entry.status])
				if triggers.has(trigger): return {}
				triggers[trigger] = true
	return value

static func view(state: Dictionary) -> Dictionary:
	var result: Dictionary = {"speech_key":"","fact_key":""}
	if not state.has("alpha_shop"):
		return result
	var a: Dictionary = state.alpha_shop
	if not a.has("profile") or not a.has("day") or not a.has("phase"):
		return result
	var narrative: Dictionary = config()
	if narrative.is_empty():
		return result
	for beat: Dictionary in narrative.beats:
		if beat.kind == "customer_open":
			if a.day != beat.day or a.phase != "CUSTOMER_ACTIVE" or a.active != beat.visit_id:
				continue
			var row_found: bool = false
			for row: Dictionary in a.profile.days[int(a.day)-1]:
				if row.id == beat.visit_id and row.actor_id == beat.actor_id:
					row_found = true
					break
			if not row_found:
				continue
			var visit: Dictionary = state.visits.get(beat.visit_id,{})
			var item: Dictionary = state.items.get(beat.item_id,{})
			if not visit.is_empty() and not item.is_empty() and visit.seller == beat.actor_id and visit.buyer == "player" and visit.scope.kind == "ordinary" and visit.scope.purpose == "purchase" and not visit.scope.completed and visit.prices.has(beat.item_id) and item.owner_id == beat.actor_id:
				result.speech_key = beat.text_key
		elif beat.kind == "contract_fact":
			# Contract consequence is a shop record, never spoken by an absent
			# supplier. Existing GameSession payment/delivery is authoritative.
			if a.day < beat.first_day or a.day > beat.last_day or a.phase == "CUSTOMER_ACTIVE" or not a.has("contracts") or not a.profile.get("contracts",{}).has(beat.contract_id):
				continue
			var row: Dictionary = a.contracts.rows.get(beat.contract_id,{})
			if row.is_empty() or row.status != beat.status:
				continue
			if beat.status == "paid":
				if str(row.get("pay_action","")).is_empty():
					continue
				for receipt: Dictionary in a.contracts.settlements:
					if receipt.contract_id == beat.contract_id and receipt.kind == "payment" and receipt.action_id == row.pay_action:
						result.fact_key = beat.text_key
						break
			elif beat.status == "defaulted" and not str(row.get("end_action","")).is_empty() and not a.settled_days.is_empty():
				result.fact_key = beat.text_key
	return result
