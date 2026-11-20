extends RefCounted
## Stateless radio appraisal. Only GameSession's detached candidate may change.
const Rules = preload("res://src/domain/value_rules.gd")
const Receipt = preload("res://src/domain/receipt_primitives.gd")
const Documents = preload("res://src/content/packaged_documents.gd")
const Math = preload("res://src/domain/appraisal_primitives.gd")
const Catalog = preload("res://src/domain/public_appraisal_catalog.gd")
const REFERENCE_PATH: String = "res://data/campaign/gate1_1/appraisal_reference.json"
const MATERIAL_PATH: String = "res://data/campaign/gate1_1/material_reference.json"
const ACTIONS: Array = ["inspect_radio", "record_hypothesis"]
const CardDialogue = preload("res://src/domain/appraisal_card_dialogue.gd")
const Links = preload("res://src/domain/appraisal_card_links.gd")
const Profile = preload("res://src/domain/inspection_profile.gd")
const Visits = preload("res://src/domain/visit_primitives.gd")
const Access = preload("res://src/domain/inspection_access.gd")
## Immutable historical adapter for the schema3 opening fixture.
## Later campaign samples must be persisted, not read from this frozen data.
static func tools() -> Dictionary:
	return Profile.tools_for(Profile.legacy_book(), "portable_radio")

static func empty() -> Dictionary:
	return {"evidence": {}, "model_id": null, "appearance_id": null, "hypothesis_action_id": null}

static func public_reference() -> Dictionary:
	var raw: Variant = Documents.read_object(REFERENCE_PATH)
	if not raw is Dictionary or raw.get("currency") != "VKC" or not raw.get("model_candidates") is Array or not raw.get("appearance_candidates") is Array or not raw.get("source") is Dictionary:
		return {}
	var models: Array = []
	var appearances: Array = []
	var seen: Dictionary = {}
	for model: Variant in raw.model_candidates:
		if not Rules.keys(model, ["id", "name_key", "description_key", "reference_amount", "render_key"]) or not Rules.identifier(model.id) or seen.has(model.id) or not Rules.integer(model.reference_amount):
			return {}
		for key: String in ["name_key", "description_key", "render_key"]:
			if not Rules.identifier(model[key]):
				return {}
		seen[model.id] = true
		models.append(Rules.normalized(model))
	seen.clear()
	for condition: Variant in raw.appearance_candidates:
		if not Rules.keys(condition, ["id", "label_key", "factor_percent"]) or not Rules.identifier(condition.id) or seen.has(condition.id) or not Rules.identifier(condition.label_key) or not Rules.integer(condition.factor_percent, 0, Math.MAX_PERCENT):
			return {}
		seen[condition.id] = true
		appearances.append(Rules.normalized(condition))
	if models.is_empty() or appearances.is_empty() or not Rules.identifier(raw.source.get("label_key")):
		return {}
	var extra: Dictionary = material_reference()
	if extra.is_empty():
		return {}
	return {"currency": "VKC", "model_candidates": models, "appearance_candidates": appearances, "source_key": raw.source.label_key, "material_candidates": extra.materials, "batch_candidates": extra.batches, "condition_scale": extra.condition_scale}

static func material_reference() -> Dictionary:
	var raw: Variant = Documents.read_object(MATERIAL_PATH)
	if not raw is Dictionary or raw.get("version") != 1 or not raw.get("materials") is Array or not raw.get("batches") is Array or not raw.get("condition_scale") is Array:
		return {}
	var seen: Dictionary = {}
	for row: Variant in raw.materials:
		if not Rules.keys(row, ["id", "label_key", "description_key", "pattern", "delta"]) or not Rules.identifier(row.id) or seen.has(row.id) or not Rules.identifier(row.label_key) or not Rules.identifier(row.description_key) or row.pattern not in ["pore", "parallel", "cross"] or not Rules.integer(row.delta, -50, 50):
			return {}
		seen[row.id] = true
	seen.clear()
	for row: Variant in raw.batches:
		if not Rules.keys(row, ["id", "label_key", "description_key", "pattern", "year_range"]) or not Rules.identifier(row.id) or seen.has(row.id) or not Rules.identifier(row.label_key) or not Rules.identifier(row.description_key) or not row.pattern is String or (row.year_range != null and not row.year_range is String):
			return {}
		seen[row.id] = true
	if raw.materials.size() != 3 or raw.batches.size() != 3 or raw.condition_scale != [{"id": "light_wear", "min": 0, "max": 25}, {"id": "visible_wear", "min": 26, "max": 65}, {"id": "heavy_wear", "min": 66, "max": 100}]:
		return {}
	return Rules.normalized({"materials": raw.materials, "batches": raw.batches, "condition_scale": raw.condition_scale})

static func amount_for(entries: Array, id: Variant, field: String) -> Variant:
	return Math.selected_value(entries, id, field)

static func estimate(record: Dictionary, ref: Dictionary) -> Dictionary:
	var selection: Dictionary = {}
	for slot: String in CardDialogue.SLOTS:
		selection[slot] = record.get(slot)
	var result: Dictionary = Catalog.estimate(Catalog.radio_adapter(ref),selection)
	if result.get("ok",false):
		result["material_delta"] = result.selected_values.material_id
		result.erase("selected_values")
	return result

static func active(state: Dictionary) -> bool:
	return state.campaign.queue.active_visit_id == "visit_g01" and Visits.purchase_open(state, "visit_g01", "R001", "G01", false) and Access.stock_access(state, "R001", "G01", true)

static func apply(state: Dictionary, kind: String, payload: Dictionary, action_id: String) -> String:
	if not active(state):
		return "appraisal_permission"
	var c: Dictionary = state.campaign
	var record: Dictionary = c.get("appraisal", empty())
	match kind:
		"inspect_radio":
			if not Rules.keys(payload, ["item_id", "tool_id", "target"]) or payload.item_id != "R001" or not payload.tool_id is String or not tools().has(payload.tool_id):
				return "inspection_shape"
			var tool: Dictionary = tools()[payload.tool_id]
			if payload.target != tool.target:
				return "inspection_target"
			if record.evidence.has(tool.evidence_id):
				return "evidence_already_known"
			var time: Dictionary = Math.inspection_preview(state.game_minutes, tool.minutes, true)
			if not time.ok:
				return time.error
			state["game_minutes"] = time.end_minute
			record.evidence[tool.evidence_id] = {"action_id": action_id, "tool_id": payload.tool_id, "observed_at": time.end_minute, "text_key": tool.text_key}
		"record_hypothesis":
			var linked_card: bool = Rules.keys(payload, ["item_id", "model_id", "appearance_id", "material_id", "batch_id", "card_slot", "card_links"])
			var link_edit: bool = Rules.keys(payload, ["item_id", "model_id", "appearance_id", "material_id", "batch_id", "link_slot", "card_links"])
			var card: bool = linked_card or Rules.keys(payload, ["item_id", "model_id", "appearance_id", "material_id", "batch_id", "card_slot"])
			var extended: bool = card or link_edit or Rules.keys(payload, ["item_id", "model_id", "appearance_id", "material_id", "batch_id"])
			if (not extended and not Rules.keys(payload, ["item_id", "model_id", "appearance_id"])) or payload.item_id != "R001":
				return "hypothesis_shape"
			for key: String in ["model_id", "appearance_id", "material_id", "batch_id"]:
				if payload.get(key) != null and not Rules.identifier(payload[key]):
					return "hypothesis_shape"
			var next: Dictionary = {"model_id": payload.model_id, "appearance_id": payload.appearance_id, "material_id": payload.get("material_id"), "batch_id": payload.get("batch_id")}
			var preview: Dictionary = estimate(next, public_reference())
			if preview.is_empty() or not preview.ok:
				return "hypothesis_candidate"
			var unchanged: bool = record.model_id == next.model_id and record.appearance_id == next.appearance_id and record.get("material_id") == next.material_id and record.get("batch_id") == next.batch_id
			if link_edit:
				if not unchanged or not Links.edit_valid(record, payload.card_links, payload.link_slot):
					return "card_link_edit"
			elif unchanged:
				return "hypothesis_unchanged"
			if linked_card and not Links.placement_valid(record, next, payload.card_links, payload.card_slot):
				return "card_link_placement"
			if record.has("card_links") and not linked_card and not link_edit:
				return "card_links_required"
			if card and not CardDialogue.single_change(record, next, payload.card_slot):
				return "card_slot_change"
			record.erase("card_slot")
			record.erase("link_slot")
			if card:
				record["card_slot"] = payload.card_slot
			if link_edit:
				record["link_slot"] = payload.link_slot
			if linked_card or link_edit:
				record["card_links"] = payload.card_links.duplicate(true)
			record["model_id"] = next.model_id
			record["appearance_id"] = next.appearance_id
			record["hypothesis_action_id"] = action_id
			if extended:
				record["material_id"] = next.material_id
				record["batch_id"] = next.batch_id
			else:
				record.erase("material_id")
				record.erase("batch_id")
		_:
			return "appraisal_command"
	c["appraisal"] = record
	return ""

## Receipt hash binds persistent facts to the same authoritative command, even after compaction.
# Compatibility entry points for older fixture tests and callers.
static func matches_receipt(state: Dictionary, id: Variant, kind: String, payload: Dictionary, revision: int) -> bool:
	return Receipt.matches_receipt(state, id, kind, payload, revision)

static func receipt_revision(state: Dictionary, id: Variant) -> int:
	return Receipt.receipt_revision(state, id)

## Appraisal is optional for earlier schema3 opening saves. No invented evidence on restore.
static func valid(state: Dictionary, admitted: bool, admission_revision: int, commands: Dictionary) -> bool:
	var record: Variant = state.campaign.get("appraisal", empty())
	var fields: Array = ["evidence", "model_id", "appearance_id", "hypothesis_action_id"]
	if record is Dictionary and record.has("material_id"):
		fields += ["material_id", "batch_id"]
		if record.has("card_slot"):
			fields.append("card_slot")
			if record.card_slot not in CardDialogue.SLOTS:
				return false
		if record.has("card_links"):
			fields.append("card_links")
			if record.has("link_slot"):
				fields.append("link_slot")
			if record.has("card_slot") == record.has("link_slot"):
				return false
			if record.has("link_slot") and record.link_slot not in CardDialogue.SLOTS:
				return false
	if not Rules.keys(record, fields) or not record.evidence is Dictionary:
		return false
	if tools().is_empty() or not admitted and record != empty():
		return false
	var preview: Dictionary = estimate(record, public_reference())
	if preview.is_empty() or not preview.ok:
		return false
	var inspection_ids: Array = commands.get("inspect_radio", [])
	var hypotheses: Array = commands.get("record_hypothesis", [])
	if inspection_ids.size() != record.evidence.size() or record.evidence.size() > tools().size():
		return false
	var elapsed: int = 0
	var ordered: Array = []
	var used: Array = []
	for evidence_id: Variant in record.evidence:
		var entry: Variant = record.evidence[evidence_id]
		if not Rules.keys(entry, ["action_id", "tool_id", "observed_at", "text_key"]) or not entry.tool_id is String or not tools().has(entry.tool_id):
			return false
		var tool: Dictionary = tools()[entry.tool_id]
		var revision: int = receipt_revision(state, entry.action_id)
		if evidence_id != tool.evidence_id or entry.text_key != tool.text_key or entry.action_id not in inspection_ids or entry.action_id in used or revision <= admission_revision or not Rules.integer(entry.observed_at, 1, 600):
			return false
		if not matches_receipt(state, entry.action_id, "inspect_radio", {"item_id": "R001", "tool_id": entry.tool_id, "target": tool.target}, revision):
			return false
		used.append(entry.action_id)
		ordered.append({"revision": revision, "minutes": tool.minutes, "observed_at": entry.observed_at})
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.revision < b.revision)
	for entry: Dictionary in ordered:
		elapsed += int(entry.minutes)
		if entry.observed_at != elapsed:
			return false
	if state.game_minutes != elapsed:
		return false
	if hypotheses.is_empty():
		return record.hypothesis_action_id == null and record.model_id == null and record.appearance_id == null and not record.has("material_id")
	var latest_revision: int = -1
	var latest_id: String = ""
	for id: String in hypotheses:
		var revision: int = receipt_revision(state, id)
		if revision <= admission_revision:
			return false
		if revision > latest_revision:
			latest_revision = revision
			latest_id = id
	if record.has("card_links"):
		if not Links.valid(record, record.card_links):
			return false
		for refs: Array in record.card_links.values():
			for id: String in refs:
				if receipt_revision(state, record.evidence[id].action_id) >= latest_revision:
					return false
	return record.hypothesis_action_id == latest_id and matches_receipt(state, latest_id, "record_hypothesis", hypothesis_payload(record), latest_revision)

static func hypothesis_payload(record: Dictionary) -> Dictionary:
	var payload: Dictionary = {"item_id":"R001","model_id":record.model_id,"appearance_id":record.appearance_id}
	if record.has("material_id"):
		payload["material_id"] = record.material_id
		payload["batch_id"] = record.batch_id
	for key: String in ["card_slot","link_slot","card_links"]:
		if record.has(key):
			payload[key] = record[key]
	return payload.duplicate(true)

## This is a public conjecture ready for local preparation, not an earned benefit.
static func argument_candidates(state: Dictionary) -> Array:
	if not active(state):
		return []
	var record: Dictionary = state.campaign.get("appraisal", empty())
	var rows: Array = []
	if record.hypothesis_action_id == null:
		return rows
	var ref: Dictionary = public_reference()
	for slot: String in CardDialogue.SLOTS:
		if record.get(slot) == null:
			continue
		var copy: Dictionary = record.duplicate(true)
		copy["card_slot"] = slot
		var words: Dictionary = CardDialogue.project(copy, ref)
		rows.append({"argument":{"slot":slot,"source_action":record.hypothesis_action_id,"source_payload":hypothesis_payload(record)}, "label_key":words.label_key, "evidence_ids":record.get("card_links",{}).get(slot,[]).duplicate()})
	return rows

## Historical validity binds exact public hypothesis and links to a prior receipt.
## Current preparation also requires the latest source; never infer hidden truth.
static func argument_valid(state: Dictionary, argument: Variant, before_revision: int, current: bool) -> bool:
	if not Rules.keys(argument, ["slot","source_action","source_payload"]) or argument.slot not in CardDialogue.SLOTS or not Rules.identifier(argument.source_action):
		return false
	var p: Variant = argument.source_payload
	if not p is Dictionary or p.get("item_id") != "R001" or p.get(argument.slot) == null:
		return false
	var source_revision: int = receipt_revision(state, argument.source_action)
	if source_revision < 1 or source_revision >= before_revision or not matches_receipt(state, argument.source_action, "record_hypothesis", p, source_revision):
		return false
	var record: Dictionary = state.campaign.get("appraisal",empty())
	if current and (record.hypothesis_action_id != argument.source_action or hypothesis_payload(record) != p):
		return false
	var candidate: Dictionary = {"model_id":p.get("model_id"),"appearance_id":p.get("appearance_id"),"material_id":p.get("material_id"),"batch_id":p.get("batch_id"),"evidence":record.evidence}
	var preview: Dictionary = estimate(candidate, public_reference())
	if not preview.get("ok",false) or not Links.valid(candidate,p.get("card_links",{})):
		return false
	for refs: Array in p.get("card_links",{}).values():
		for id: String in refs:
			if receipt_revision(state, record.evidence[id].action_id) >= source_revision:
				return false
	return true

static func argument_evidence(argument: Dictionary) -> Variant:
	# The legacy customer accepts one relevant public wear observation, no stacked factors.
	if argument.slot == "appearance_id" and argument.source_payload.get("appearance_id") == "visible_wear" and "R001.wear" in argument.source_payload.get("card_links",{}).get("appearance_id",[]):
		return "R001.wear"
	return null


## Original schema3 first-visit R001 function was immutable and true (Opening.valid).
## Historical fixture readings cannot be reinterpreted from a later live condition.
## General campaign observations will require persisted sampled values/dependencies.
static func reading_for(_state: Dictionary, tool_id: String) -> Dictionary:
	return Profile.legacy_reading(Profile.legacy_book(), "R001", "portable_radio", "bootstrap_R001", tool_id)

static func view(state: Dictionary) -> Dictionary:
	return _project(state, true) if active(state) else {}

static func acquired_view(state: Dictionary) -> Dictionary:
	if not state.items.has("R001") or state.items.R001.owner_id != "player" or state.items.R001.custodian_id != "player" or state.campaign.get("negotiation", {}).get("terminal") == null or state.campaign.negotiation.terminal.kind != "purchased":
		return {}
	return _project(state, false)

static func _project(state: Dictionary, interactive: bool) -> Dictionary:
	var record: Dictionary = state.campaign.get("appraisal", empty())
	var facts: Array = []
	var tool_views: Array = []
	var configured: Dictionary = tools()
	for tool_id: String in configured:
		var tool: Dictionary = configured[tool_id]
		var known: bool = record.evidence.has(tool.evidence_id)
		var time: Dictionary = Math.inspection_preview(state.game_minutes, tool.minutes, not known)
		if interactive:
			tool_views.append({"tool_id": tool_id, "target": tool.target, "known": known, "minutes": 0 if known else tool.minutes, "available": not known and time.ok})
		if known:
			var fact: Dictionary = record.evidence[tool.evidence_id]
			facts.append({"evidence_id": tool.evidence_id, "text_key": fact.text_key, "observed_at": fact.observed_at, "tool_id": tool_id, "reading": reading_for(state, tool_id)})
	var ref: Dictionary = public_reference()
	var spoken: Dictionary = CardDialogue.project(record, ref) if interactive else {}
	var offers: Array = state.campaign.get("negotiation", {}).get("offers", [])
	if not spoken.is_empty() and not offers.is_empty() and receipt_revision(state, offers.back().action_id) > receipt_revision(state, spoken.action_id):
		spoken = {}
	return {"item_id": "R001", "visible_key": "day1.radio.visible_shape", "function_status": reading_for(state, "function_detail").value if record.evidence.has("R001.function") else "unknown", "evidence": facts, "tools": tool_views, "catalog": ref, "hypothesis": {"model_id": record.model_id, "appearance_id": record.appearance_id, "material_id": record.get("material_id"), "batch_id": record.get("batch_id")}, "reference": estimate(record, ref), "card_dialogue": spoken, "argument_candidates": argument_candidates(state) if interactive else [], "card_links": record.get("card_links", {}).duplicate(true)}
