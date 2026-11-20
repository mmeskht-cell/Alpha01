extends RefCounted
## Stateless, fictional component-preview rules. GameSession remains sole authority.
const Rules = preload("res://src/domain/value_rules.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const Access = preload("res://src/domain/inspection_access.gd")
const Composite = preload("res://src/domain/campaign_composite_pilot.gd")
const Evidence = preload("res://src/domain/evidence_primitives.gd")
const Observation = preload("res://src/domain/observation_record.gd")
const Receipt = preload("res://src/domain/receipt_primitives.gd")
const Documents = preload("res://src/content/packaged_documents.gd")
const Math = preload("res://src/domain/appraisal_primitives.gd")
const Profile = preload("res://src/domain/inspection_profile.gd")
const CustomerInspection = preload("res://src/domain/customer_inspection.gd")
const PROFILE_PATH: String = "res://data/campaign/component_preview/profiles.json"
const BASE_TOOLS: Array = ["component_texture", "component_damage", "component_mark", "component_function"]
const FIELDS: Array = ["material_id", "condition_id", "series_id"]
const SERIES: Array = ["series_early", "series_late", "series_rebuilt"]

# Immutable content cache only; all mutable appraisal state remains in GameSession.
static var _book_cache: Dictionary = {}
static var _profile_cache: Dictionary = {}
static var _keys_cache: Array = []

static func _source() -> Dictionary:
	if not _book_cache.is_empty():
		return _book_cache
	var raw: Variant = Documents.read_object(PROFILE_PATH)
	if not raw is Dictionary or raw.get("version") != 1 or not raw.get("parts") is Array or not raw.get("regions_by_definition") is Dictionary or not raw.get("materials") is Array or not raw.get("conditions") is Array or not Rules.integer(raw.get("whole_reference")):
		return {}
	var keys: Dictionary = {}
	var by_definition: Dictionary = {}
	for def_id: Variant in raw.regions_by_definition:
		if not Rules.identifier(def_id) or not raw.regions_by_definition[def_id] is Array:
			return {}
		var regions_seen: Dictionary = {}
		var observations_seen: Dictionary = {}
		for region: Variant in raw.regions_by_definition[def_id]:
			if not Rules.keys(region, ["id", "label_key", "tools", "attached_tools"]) or not Rules.identifier(region.id) or not Rules.identifier(region.label_key) or regions_seen.has(region.id) or not region.tools is Dictionary or region.tools.is_empty() or not region.attached_tools is Array:
				return {}
			regions_seen[region.id] = true
			for tool: Variant in region.tools:
				var key: Variant = region.tools[tool]
				if tool not in BASE_TOOLS or not Rules.identifier(key) or not key.begins_with("component_") or observations_seen.has(key):
					return {}
				if (tool == "component_function") != (key == "component_function") or (key in BASE_TOOLS and key != tool) or (keys.has(key) and keys[key] != tool):
					return {}
				keys[key] = tool
				observations_seen[key] = tool
			for tool: Variant in region.attached_tools:
				if tool == "component_function" or not region.tools.has(tool):
					return {}
		by_definition[def_id] = observations_seen
	var material_ids: Dictionary = {}
	for material: Variant in raw.materials:
		if not Rules.keys(material, ["id", "pattern", "delta"]) or not Rules.identifier(material.id) or material_ids.has(material.id) or material.pattern not in ["pore", "parallel", "cross"] or not Rules.integer(material.delta, -50, 50):
			return {}
		material_ids[material.id] = true
	var condition_ids: Dictionary = {}
	for condition: Variant in raw.conditions:
		if not Rules.keys(condition, ["id", "min", "max", "factor"]) or not Rules.identifier(condition.id) or condition_ids.has(condition.id) or not Rules.integer(condition.min, 0, 100) or not Rules.integer(condition.max, int(condition.min), 100) or not Rules.integer(condition.factor, 0, 100):
			return {}
		condition_ids[condition.id] = true
	if material_ids.is_empty() or condition_ids.is_empty():
		return {}
	if not raw.get("function_rules") is Dictionary:
		return {}
	for def_id: Variant in raw.function_rules:
		var rule: Variant = raw.function_rules[def_id]
		if not by_definition.has(def_id) or not Rules.keys(rule, ["passive_root", "essential_tags", "secondary_tags"]) or not rule.passive_root is bool or not rule.essential_tags is Array or rule.essential_tags.is_empty() or not rule.secondary_tags is Array:
			return {}
		var tags: Dictionary = {}
		for tag: Variant in rule.essential_tags + rule.secondary_tags:
			if not Rules.identifier(tag) or tags.has(tag):
				return {}
			tags[tag] = true
	var profiles: Dictionary = {}
	for row: Variant in raw.parts:
		if not Rules.keys(row, ["id", "def_id", "provenance", "reference", "readings"]) or not Rules.identifier(row.id) or not Rules.identifier(row.def_id) or not Rules.identifier(row.provenance) or profiles.has(row.id) or not by_definition.has(row.def_id) or not Rules.integer(row.reference) or not row.readings is Dictionary:
			return {}
		var readings: Dictionary = row.readings
		if readings.has("regions") and not readings.regions is Dictionary:
			return {}
		for key: String in by_definition[row.def_id]:
			if key == "component_function":
				continue
			var field: String = key.trim_prefix("component_")
			var value: Variant = readings.get(field) if key in BASE_TOOLS else readings.get("regions", {}).get(key)
			match by_definition[row.def_id][key]:
				"component_texture":
					if not Profile.valid_reading("texture", value): return {}
				"component_damage":
					if not Profile.valid_reading("damage_index", value): return {}
				"component_mark":
					if not Profile.valid_reading("mark", value): return {}
		profiles[row.id] = Rules.normalized(row)
	_book_cache = Rules.normalized(raw)
	_profile_cache = profiles
	_keys_cache = keys.keys()
	return _book_cache

static func book() -> Dictionary:
	return _source().duplicate(true)

static func observation_keys() -> Array:
	_source()
	return _keys_cache.duplicate()

static func recognizes(key: Variant) -> bool:
	_source()
	return key is String and key in _keys_cache

static func profile(item_id: String, item: Dictionary) -> Dictionary:
	_source()
	var row: Dictionary = _profile_cache.get(item_id, {})
	if row.is_empty() or row.def_id != item.get("def_id") or row.provenance != item.get("provenance_id"):
		return {}
	return row.duplicate(true)

## Customer preview identity and content mapping are pinned to validated fixture data.
static func valid_customer_fixture(state: Dictionary, defs: Dictionary) -> bool:
	if not CustomerInspection.enabled(state):
		return true
	var source: Dictionary = _source()
	if source.is_empty() or state.items.size() != source.parts.size():
		return false
	for row: Dictionary in source.parts:
		if not state.items.has(row.id):
			return false
		var item: Dictionary = state.items[row.id]
		if profile(row.id, item).is_empty() or not defs.has(item.def_id):
			return false
		var rule: Dictionary = source.function_rules.get(item.def_id, {})
		if defs[item.def_id].kind == "composite":
			if rule.is_empty():
				return false
			var declared: Array = rule.essential_tags + rule.secondary_tags
			var actual: Array = defs[item.def_id].required_tags.duplicate()
			declared.sort()
			actual.sort()
			if declared != actual:
				return false
		for key: String in CustomerInspection.grant_for(state, row.id):
			if observation_spec(item, key, false).is_empty():
				return false
	return true

static func seed() -> Dictionary:
	if _source().is_empty():
		return {}
	var state: Dictionary = {"object_schema": 3, "revision": 0, "game_minutes": 600, "wallets": {"player": {"VKC": 100, "USD": 0}}, "inventories": {"player_grid": {"owner_id": "player", "width": 10, "height": 6, "host_item": ""}}, "items": {}, "ledger": [], "receipts": {}, "receipt_archive": {}, "tombstones": {}, "object_events": [], "knowledge": {}, "visits": {}, "phase": "workshop"}
	var basis: Dictionary = {"D001": 20, "D001_A": 50, "D001_B": 20, "D001_C": 10, "D002": 20}
	for row: Dictionary in _source().get("parts", []):
		var attached: bool = row.id.begins_with("D001_")
		var item: Dictionary = Objects.fresh_item(row.def_id, "player", "" if attached else "player_grid", -1 if attached else (0 if row.id == "D001" else 6), -1 if attached else 0, row.provenance)
		item.parent_id = "D001" if attached else ""
		item.basis = {"VKC": basis[row.id], "USD": 0}
		item.functional = row.id not in ["D001_B", "D001_C"]
		state.items[row.id] = item
	return state

static func eligible(state: Dictionary, id: String, detached_only: bool = true) -> bool:
	if (state.has("campaign") and not Composite.enabled(state)) or state.phase != "workshop" or not state.items.has(id):
		return false
	return Access.stock_access(state, id, "player", detached_only) and not profile(id, state.items[id]).is_empty()

## Profile supplies public region geometry/role and allowed instrument pairs, never readings.
static func regions(item: Dictionary, attached: bool) -> Array:
	var result: Array = []
	for region: Dictionary in _source().get("regions_by_definition", {}).get(item.get("def_id", ""), []):
		var tools: Dictionary = {}
		for tool: String in region.tools:
			if not attached or tool in region.attached_tools:
				tools[tool] = region.tools[tool]
		if not tools.is_empty():
			result.append({"id": region.id, "label_key": region.label_key, "tools": tools})
	return result

static func observation_spec(item: Dictionary, key: String, attached: bool) -> Dictionary:
	return Profile.region_spec(regions(item, attached), key)

static func inspection_regions(state: Dictionary, id: String) -> Array:
	if eligible(state, id, false):
		var owned: Dictionary = state.items[id]
		return regions(owned, not owned.parent_id.is_empty())
	if not (CustomerInspection.eligible(state, id) or Composite.eligible(state, id)):
		return []
	var item: Dictionary = state.items[id]
	var result: Array = []
	for region: Dictionary in regions(item, false):
		var tools: Dictionary = {}
		for tool: String in region.tools:
			var key: String = region.tools[tool]
			if item.parent_id.is_empty() or not observation_spec(item, key, true).is_empty() or CustomerInspection.extra_access(state, id, key) or Composite.extra_access(state, id, key):
				tools[tool] = key
		if not tools.is_empty():
			result.append({"id": region.id, "label_key": region.label_key, "tools": tools})
	return result

static func allowed_observation(state: Dictionary, id: String, key: String) -> bool:
	for region: Dictionary in inspection_regions(state, id):
		if key in region.tools.values():
			return true
	return false

static func may_hypothesize(state: Dictionary, id: String) -> bool:
	return eligible(state, id) or ((CustomerInspection.eligible(state, id) or Composite.eligible(state, id)) and not inspection_regions(state, id).is_empty())

static func legacy_function(state: Dictionary, defs: Dictionary, id: String) -> bool:
	if not state.items[id].functional or not Objects.complete(state, defs, id):
		return false
	for member: String in Objects.family(state, id):
		if not state.items[member].functional:
			return false
	return true

static func assembly_status(state: Dictionary, defs: Dictionary, id: String) -> String:
	var item: Dictionary = state.items[id]
	var rule: Dictionary = _source().function_rules.get(item.def_id, {})
	if rule.is_empty():
		return "serviceable" if legacy_function(state, defs, id) else "inoperable"
	var required: Array = defs[item.def_id].required_tags.duplicate()
	var configured: Array = rule.essential_tags + rule.secondary_tags
	required.sort()
	configured.sort()
	if required != configured or (not rule.passive_root and not item.functional):
		return "inoperable"
	var working: Dictionary = {}
	for member: String in Objects.family(state, id):
		if member != id:
			var child: Dictionary = state.items[member]
			working[defs[child.def_id].tag] = child.functional
	for tag: String in rule.essential_tags:
		if not working.get(tag, false):
			return "inoperable"
	for tag: String in rule.secondary_tags:
		if not working.get(tag, false):
			return "partial"
	return "serviceable"

static func legacy_composite_reading(record: Dictionary, item: Dictionary) -> bool:
	return record.get("observation_key") == "component_function" and record.get("observed_value") is bool and _source().get("function_rules", {}).has(item.get("def_id", ""))

static func fact_current(record: Dictionary, item: Dictionary) -> bool:
	return not legacy_composite_reading(record, item) and Evidence.is_current(record.dependent_field_versions, item.field_versions)

static func truth(state: Dictionary, defs: Dictionary, id: String, key: String) -> Variant:
	var item: Dictionary = state.items.get(id, state.tombstones.get(id, {}))
	var row: Dictionary = profile(id, item)
	if row.is_empty():
		return null
	match key:
		"component_texture": return row.readings.texture
		"component_damage": return row.readings.damage
		"component_mark": return row.readings.mark
		"component_function":
			if not state.items.has(id):
				return null
			if defs[item.def_id].kind == "composite":
				return assembly_status(state, defs, id)
			return item.functional
	return row.readings.get("regions", {}).get(key)

static func dependencies(item: Dictionary, defs: Dictionary, key: String) -> Dictionary:
	if key != "component_function":
		# These fixture surface and production characteristics do not change during functional repair.
		return {}
	var dep: Dictionary = {"functional": item.field_versions.functional}
	if defs[item.def_id].kind == "composite":
		dep["composition"] = item.field_versions.composition
	return dep

static func observe(state: Dictionary, defs: Dictionary, p: Dictionary, action_id: String) -> String:
	if not Rules.keys(p, ["actor", "item_id", "key"]) or p.actor != "player" or not Rules.identifier(p.item_id) or not recognizes(p.key) or not allowed_observation(state, p.item_id, p.key):
		return "component_observation_permission"
	var item: Dictionary = state.items[p.item_id]
	for record: Dictionary in state.knowledge.values():
		if record.item_id == p.item_id and record.observation_key == p.key and fact_current(record, item):
			return "evidence_already_known"
	var value: Variant = truth(state, defs, p.item_id, p.key)
	if value == null:
		return "component_observation_unknown"
	var minute: int = state.game_minutes
	if state.phase == "shop":
		var timing: Dictionary = Math.inspection_preview(minute, CustomerInspection.MINUTES, true)
		if not timing.ok:
			return timing.error
		minute = timing.end_minute
	var sampled: Dictionary = Observation.capture(action_id, p.item_id, p.key, "instrument", minute, value, dependencies(item, defs, p.key))
	if sampled.is_empty():
		return "observation_record"
	# Owned evening workshop clock remains frozen.
	state.game_minutes = minute
	state.knowledge[action_id] = sampled
	return ""

static func valid_observation(state: Dictionary, defs: Dictionary, id: String, record: Dictionary) -> bool:
	if not Observation.bound(state, id, record, "instrument") or not recognizes(record.observation_key) or (state.has("campaign") and not Composite.enabled(state)):
		return false
	var item: Dictionary = state.items.get(record.item_id, state.tombstones.get(record.item_id, {}))
	if profile(record.item_id, item).is_empty() or observation_spec(item, record.observation_key, false).is_empty():
		return false
	if not CustomerInspection.historical_access(state, record.item_id, record.observation_key, Receipt.receipt_revision(state, id), not observation_spec(item, record.observation_key, true).is_empty(), int(record.observed_at)):
		return false
	var dep: Variant = record.dependent_field_versions
	if record.observation_key != "component_function":
		return dep == {} and record.observed_value == truth(state, defs, record.item_id, record.observation_key)
	var expected: Array = ["functional"]
	if defs[item.def_id].kind == "composite":
		expected.append("composition")
	var composite: bool = defs[item.def_id].kind == "composite"
	if (not record.observed_value is bool and (not composite or record.observed_value not in ["serviceable", "partial", "inoperable"])) or not Rules.keys(dep, expected):
		return false
	for field: String in expected:
		if not Rules.integer(dep[field]) or (state.items.has(record.item_id) and dep[field] > item.field_versions[field]):
			return false
	if state.items.has(record.item_id) and Evidence.is_current(dep, item.field_versions):
		if composite and record.observed_value is bool:
			return record.observed_value == legacy_function(state, defs, record.item_id)
		return record.observed_value == truth(state, defs, record.item_id, record.observation_key)
	return true

static func selected_value(entries: Array, id: Variant, field: String) -> Variant:
	return Math.selected_value(entries, id, field)

static func empty_hypothesis() -> Dictionary:
	return {"material_id": null, "condition_id": null, "series_id": null}

static func valid_selection(p: Dictionary) -> bool:
	for field: String in FIELDS:
		if p.get(field) != null and not Rules.identifier(p[field]):
			return false
	var ref: Dictionary = _source()
	if ref.is_empty():
		return false
	return (p.material_id == null or selected_value(ref.materials, p.material_id, "delta") != null) and (p.condition_id == null or selected_value(ref.conditions, p.condition_id, "factor") != null) and (p.series_id == null or p.series_id in SERIES)

static func latest(state: Dictionary, item_id: String) -> Dictionary:
	var result: Dictionary = empty_hypothesis()
	var latest_revision: int = -1
	var records: Dictionary = state.get("component_hypotheses", {})
	for id: String in records:
		var row: Dictionary = records[id]
		if row.item_id == item_id:
			var revision: int = Receipt.receipt_revision(state, id)
			if revision > latest_revision:
				latest_revision = revision
				for field: String in FIELDS:
					result[field] = row[field]
	return result

static func record_hypothesis(state: Dictionary, p: Dictionary, id: String) -> String:
	if not Rules.keys(p, ["actor", "item_id", "material_id", "condition_id", "series_id"]) or p.actor != "player" or not Rules.identifier(p.item_id) or not may_hypothesize(state, p.item_id) or not valid_selection(p):
		return "component_hypothesis_permission"
	var selected: Dictionary = {}
	for field: String in FIELDS:
		selected[field] = p[field]
	if selected == latest(state, p.item_id):
		return "hypothesis_unchanged"
	if not state.has("component_hypotheses"):
		state["component_hypotheses"] = {}
	state.component_hypotheses[id] = p.duplicate(true)
	return ""

static func valid_hypotheses(state: Dictionary) -> bool:
	var records: Variant = state.get("component_hypotheses", {})
	if not records is Dictionary or (state.has("campaign") and state.has("component_hypotheses") and not Composite.enabled(state)):
		return false
	for id: Variant in records:
		var p: Variant = records[id]
		if not Rules.identifier(id) or not Rules.keys(p, ["actor", "item_id", "material_id", "condition_id", "series_id"]) or p.actor != "player" or not Rules.identifier(p.item_id) or not valid_selection(p):
			return false
		var item: Dictionary = state.items.get(p.item_id, state.tombstones.get(p.item_id, {}))
		if profile(p.item_id, item).is_empty() or not Receipt.matches_receipt(state, id, "record_component_hypothesis", p, Receipt.receipt_revision(state, id)):
			return false
		if not CustomerInspection.historical_access(state, p.item_id, "", Receipt.receipt_revision(state, id), not regions(item, true).is_empty()):
			return false
	return true

static func estimate(state: Dictionary, item_id: String) -> Variant:
	var row: Dictionary = profile(item_id, state.items[item_id])
	if row.is_empty():
		return null
	var selected: Dictionary = latest(state, item_id)
	var ref: Dictionary = _source()
	var delta: Variant = selected_value(ref.materials, selected.material_id, "delta")
	var factor: Variant = selected_value(ref.conditions, selected.condition_id, "factor")
	if factor == null or delta == null:
		return null
	var result: Dictionary = Math.reference_preview(maxi(0, int(row.reference) + int(delta)), factor)
	return result.get("estimate") if result.get("ok", false) else null

static func recovery(state: Dictionary, ids: Array) -> Dictionary:
	if ids.is_empty() or ids.size() > 128:
		return {"ok": false}
	var seen: Dictionary = {}
	var unknown: int = 0
	var subtotal: int = 0
	for id: Variant in ids:
		if not Rules.identifier(id) or seen.has(id) or not eligible(state, id, false):
			return {"ok": false}
		seen[id] = true
		var amount: Variant = estimate(state, id)
		if amount == null:
			unknown += 1
		else:
			subtotal += int(amount)
	return {"ok": true, "subtotal": subtotal, "unknown_count": unknown, "estimate": subtotal if unknown == 0 else null}

static func view(state: Dictionary, defs: Dictionary) -> Dictionary:
	if (state.has("campaign") and not Composite.enabled(state)) or (state.phase != "workshop" and not CustomerInspection.enabled(state) and not Composite.enabled(state)) or not state.wallets.has("player") or _source().is_empty():
		return {}
	var rows: Array = []
	var notes: Array = []
	for id: String in state.items:
		var accessible: Array = inspection_regions(state, id)
		var item: Dictionary = state.items[id]
		var info: Dictionary = profile(id, item)
		if info.is_empty():
			continue
		var available: bool = eligible(state, id, false) or not accessible.is_empty()
		var observations: Array = []
		for record: Dictionary in state.knowledge.values():
			if record.item_id == id and recognizes(record.observation_key):
				var public: Dictionary = Evidence.public_view(record, item.field_versions, id)
				if not public.is_empty():
					public.merge(observation_spec(item, record.observation_key, false))
					public.current = fact_current(record, item)
					observations.append(public)
		var hypothesis: Dictionary = latest(state, id)
		if not available:
			if id in CustomerInspection.IDS and (CustomerInspection.live_visit(state) or Composite.live(state)) and (not observations.is_empty() or hypothesis != empty_hypothesis()):
				notes.append({"id": id, "role": defs[item.def_id].tag, "observations": observations, "hypothesis": hypothesis, "component_estimate": estimate(state, id)})
			continue
		var root: bool = defs[item.def_id].kind == "composite"
		var reference: Variant = _source().whole_reference if root else null
		rows.append({"id": id, "role": defs[item.def_id].tag, "parent_id": item.parent_id, "can_inspect": eligible(state, id), "can_hypothesize": may_hypothesize(state, id), "regions": accessible, "observations": observations, "hypothesis": hypothesis, "component_reference": info.reference, "component_estimate": estimate(state, id), "whole_catalog_reference": reference, "basis": item.basis.duplicate(true), "x": item.x, "y": item.y})
	var ref: Dictionary = _source()
	return {"revision": state.revision, "minute": state.game_minutes, "wallet": state.wallets.player.duplicate(true), "parts": rows, "notes": notes, "materials": ref.materials.duplicate(true), "conditions": ref.conditions.duplicate(true), "series": SERIES.duplicate(), "customer": Composite.view(state) if Composite.enabled(state) else CustomerInspection.view(state), "phase": state.phase}
