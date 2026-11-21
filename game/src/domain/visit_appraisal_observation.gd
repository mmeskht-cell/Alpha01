extends RefCounted
## P2-B1 stateless observation preparation for explicitly granted ordinary
## detached customer goods. Caller owns atomic commit and historical replay.
## No arbitrary caller-supplied reading, actor, scope, duration or dependency.
const Rules = preload("res://src/domain/value_rules.gd")
const Profiles = preload("res://src/domain/inspection_profile.gd")
const Access = preload("res://src/domain/inspection_access.gd")
const Visits = preload("res://src/domain/visit_primitives.gd")
const Clock = preload("res://src/domain/business_clock.gd")
const Observation = preload("res://src/domain/observation_record.gd")
const Evidence = preload("res://src/domain/evidence_primitives.gd")
const Documents = preload("res://src/content/packaged_documents.gd")
const PATH: String = "res://data/campaign/gate2/watch_inspection_profile.json"
const PROFILE_ID: String = "watch_p2_v1"
const PUBLIC_PATH: String = "res://data/campaign/gate2/watch_public_catalog.json"
const Catalog = preload("res://src/domain/public_appraisal_catalog.gd")
const CustomerClaims = preload("res://src/domain/visit_customer_claims.gd")
const MAX_OBSERVATIONS: int = 128

# Immutable catalog/profile routing for the existing approved versions.
# Keep the marker field names and underlying documents identical so older
# saves replay using the same content hashes. No user-provided path accepted.
const SOURCES: Array = [
	{"def_id":"fictional_watch_p2","inspection":PATH,"catalog":PUBLIC_PATH,"marker":"catalog_sha","radio_extension":false},
	{"def_id":"portable_radio","inspection":"res://data/campaign/gate2/demo_radio_inspection.json","catalog":"res://data/campaign/gate2/demo_radio_catalog.json","marker":"radio_catalog_sha","radio_extension":true}
]

static func sources(state:Dictionary)->Array:
	var result:Array=[]
	for row:Dictionary in SOURCES:
		if not row.radio_extension or demo_v2(state):
			result.append(row.duplicate(true))
	return result

static func source_for(state:Dictionary,def_id:String)->Dictionary:
	for row:Dictionary in sources(state):
		if row.def_id==def_id:
			return row
	return {}

static func source_catalog(row:Dictionary)->Dictionary:
	if row.is_empty():
		return {}
	var catalog:Dictionary=Catalog.parse(Documents.read_object(str(row.get("catalog",""))))
	return catalog if catalog.get("def_id")==row.get("def_id") else {}

static func demo_v2(state:Dictionary)->bool:
	return state.get("calendar",{}).get("profile",{}).get("content_version") in ["demo7-integrated-2","demo7-integrated-3"]

static func book(state:Dictionary={}) -> Dictionary:
	var result:Dictionary={"version":1,"profiles":{},"specimens":{}}
	for row:Dictionary in sources(state):
		var source:Dictionary=Profiles.parse(Documents.read_object(row.inspection))
		if source.is_empty() or source.profiles.size()!=1 or not source.profiles.has(row.def_id):
			return {}
		for id:String in source.specimens:
			if result.specimens.has(id):
				return {}
		if result.profiles.has(row.def_id):
			return {}
		result.profiles.merge(source.profiles)
		result.specimens.merge(source.specimens)
	return result

# Data-model level eligibility: the same authored, abstract 5-minute function
# check applies to any permitted ordinary purchase of these three definitions.
# No visit-ID whitelist or added private specimen table. Existing demo3 visits
# retain identical tool ID, evidence meaning, time and seed/replay binding.
# New definitions still require explicit review; restricted goods do not qualify.
const BASIC_DEFINITIONS_V1:Array=["battery","demo_tool","demo_electronics"]
const BASIC_TOOL:String="basic_function_v1"

static func basic_available(state:Dictionary,visit_id:String,item_id:String)->bool:
	if not CustomerClaims.demo3(state) or not CustomerClaims.enabled(state) or not permitted(state,visit_id,item_id):
		return false
	var visit:Dictionary=state.visits.get(visit_id,{})
	if visit.is_empty() or visit.scope.get("kind")!="ordinary" or visit.scope.get("purpose")!="purchase":
		return false
	if state.items[item_id].def_id not in BASIC_DEFINITIONS_V1:
		return false
	var marker:Dictionary=state.calendar.get("appraisal_profile",{})
	return marker.get("id")==PROFILE_ID and marker.get("content_sha")==Rules.canonical(book(state)).sha256_text()

static func basic_in_progress(state:Dictionary,visit_id:String,item_id:String)->bool:
	if state.calendar.get("appraisal_assessments",{}).has(visit_id) or state.calendar.get("appraisal_decks",{}).has(visit_id) or state.calendar.get("appraisal_offers",{}).has(visit_id):
		return true
	for entry:Dictionary in records(state).values():
		if entry.visit_id==visit_id and entry.record.item_id==item_id:
			return true
	return false

static func radio_catalog()->Dictionary:
	return Catalog.parse(Documents.read_object("res://data/campaign/gate2/demo_radio_catalog.json"))

## Preserve the original sample content hash; new demo binds the authored WAT02 ID to the existing watch specimen.
static func specimen_id(state:Dictionary,id:String)->String:
	return "W001" if state.get("calendar",{}).get("profile",{}).get("content_version") in ["demo7-integrated-1","demo7-integrated-2","demo7-integrated-3"] and id=="WAT02" else id

static func records(state: Dictionary) -> Dictionary:
	return state.get("calendar",{}).get("appraisal_observations",state.get("appraisal_observations",{}))

static func active_visit(state: Dictionary, visit_id: String) -> bool:
	var calendar: Variant = state.get("calendar",{}).get("queue")
	if calendar is Dictionary:
		return calendar.get("active") == visit_id
	var queue: Variant = state.get("campaign",{}).get("queue")
	if queue is Dictionary:
		return queue.get("active_visit_id") == visit_id
	return false

static func permitted(state: Dictionary, visit_id: String, subject_id: String) -> bool:
	if not active_visit(state,visit_id) or not state.items.has(subject_id):
		return false
	var item: Dictionary = state.items[subject_id]
	return Visits.purchase_open(state,visit_id,subject_id,item.owner_id,true) and Access.stock_access(state,subject_id,item.owner_id,true)

static func current(record: Dictionary, item: Dictionary) -> bool:
	return Evidence.is_current(record.dependent_field_versions,item.field_versions)

## Scope is rechecked on each access; no private specimen values in tools.
static func tools(state: Dictionary, visit_id: String, subject_id: String) -> Dictionary:
	if not permitted(state,visit_id,subject_id):
		return {}
	var item: Dictionary = state.items[subject_id]
	if basic_available(state,visit_id,subject_id):
		return {BASIC_TOOL:{"target":"basic_whole_function","minutes":5,"evidence_id":"function_status","text_key":"review.basic.function"}}
	var data: Dictionary = book(state)
	var specimen: Dictionary = data.get("specimens",{}).get(specimen_id(state,subject_id),{})
	if specimen.is_empty() or specimen.def_id != item.def_id or specimen.provenance != item.provenance_id:
		return {}
	return Profiles.tools_for(data,item.def_id)

## A novel observation's resulting receipt-bound payload is prepared without
## mutating the candidate; the eventual GameSession authority commits both
## time and persisted record together. Fixture geometry identifies abstract regions.
static func prepare(state: Dictionary, p: Variant, action_id: String) -> Dictionary:
	if not Rules.keys(p,["visit_id","item_id","tool_id","target"]) or not Rules.identifier(action_id):
		return {"ok":false,"error":"observation_shape"}
	for key: String in ["visit_id","item_id","tool_id","target"]:
		if not Rules.identifier(p[key]):
			return {"ok":false,"error":"observation_shape"}
	var configured: Dictionary = tools(state,p.visit_id,p.item_id)
	if not configured.has(p.tool_id):
		return {"ok":false,"error":"observation_permission"}
	var spec: Dictionary = configured[p.tool_id]
	if p.target != spec.target:
		return {"ok":false,"error":"observation_target"}
	var item: Dictionary = state.items[p.item_id]
	for entry: Dictionary in records(state).values():
		if entry.visit_id == p.visit_id and entry.record.item_id == p.item_id and entry.record.observation_key == spec.evidence_id and current(entry.record,item):
			return {"ok":false,"error":"evidence_already_known"}
	var minute: int = int(state.game_minutes)
	var timing: Dictionary = Clock.inspection_at(minute,spec.minutes,true,state.phase)
	if not timing.ok:
		return timing
	if int(timing.end_minute) > int(state.visits[p.visit_id].expires):
		return {"ok":false,"error":"observation_visit_expired"}
	var sample: Dictionary = {"kind":"function_status","value":"serviceable" if item.functional else "inoperable"} if p.tool_id==BASIC_TOOL and basic_available(state,p.visit_id,p.item_id) else Profiles.legacy_reading(book(state),specimen_id(state,p.item_id),item.def_id,item.provenance_id,p.tool_id)
	if sample.is_empty():
		return {"ok":false,"error":"observation_sample"}
	var dependencies: Dictionary = {}
	# Static specimen observations are immutable in this isolated pilot.
	# Function is sampled from live authoritative state, not fixture's initial reading.
	if sample.kind == "function_status":
		dependencies["functional"] = item.field_versions.functional
		sample.value = "serviceable" if item.functional else "inoperable"
	var record: Dictionary = Observation.capture(action_id,p.item_id,spec.evidence_id,"instrument",int(timing.end_minute),sample.value,dependencies)
	if record.is_empty():
		return {"ok":false,"error":"observation_record"}
	return {"ok":true,"end_minute":timing.end_minute,"entry":{"visit_id":p.visit_id,"tool_id":p.tool_id,"target":p.target,"record":record}}

## Only active visit observations are projected here. Stored historical
## observations may be read by a later separately authorized lineage view.
static func view(state: Dictionary, visit_id: String, subject_id: String) -> Array:
	if not permitted(state,visit_id,subject_id):
		return []
	var result: Array = []
	var history: Dictionary = records(state)
	var ids: Array = history.keys()
	ids.sort_custom(func(a: String,b: String) -> bool:
		var am: int = int(history[a].record.observed_at)
		var bm: int = int(history[b].record.observed_at)
		return a < b if am == bm else am < bm)
	for id: String in ids:
		var entry: Dictionary = history[id]
		if entry.visit_id != visit_id or entry.record.item_id != subject_id:
			continue
		var projected: Dictionary = Evidence.public_view(entry.record,state.items[subject_id].field_versions,subject_id)
		if not projected.is_empty():
			result.append(projected)
	return result

## Opt-in immutable profile binding, only for calendar test content.
static func seed(state: Dictionary, profile: Dictionary) -> Dictionary:
	if profile.get("appraisal_profile") != PROFILE_ID or not profile.has("visit_days"):
		return {}
	var context:Dictionary={"calendar":{"profile":profile}}
	var source: Dictionary = book(context)
	if source.is_empty():
		return {}
	var matching: int = 0
	for id: String in state.items:
		var item: Dictionary = state.items[id]
		if item.def_id not in source.profiles:
			continue
		var row: Dictionary = source.specimens.get(specimen_id({"calendar":{"profile":profile}},id),{})
		if row.is_empty() or row.def_id != item.def_id or row.provenance != item.provenance_id:
			return {}
		matching += 1
	if matching == 0:
		return {}
	var marker: Dictionary = {"id":PROFILE_ID,"content_sha":Rules.canonical(source).sha256_text()}
	for row:Dictionary in sources(context):
		var public_catalog:Dictionary=source_catalog(row)
		if public_catalog.is_empty():
			return {}
		marker[row.marker]=Rules.canonical(public_catalog).sha256_text()
	if profile.get("content_version") in [CustomerClaims.VERSION,"demo7-integrated-1","demo7-integrated-2","demo7-integrated-3"]:
		marker["customer_claims_sha"] = CustomerClaims.binding(profile.get("content_version",""))
	return marker

## Only GameSession's detached candidate or authoritative journal replay calls this.
static func apply(state: Dictionary, p: Dictionary, action_id: String) -> String:
	var marker: Dictionary = state.get("calendar",{}).get("appraisal_profile",{})
	if marker.get("id") != PROFILE_ID or marker.get("content_sha") != Rules.canonical(book(state)).sha256_text():
		return "appraisal_profile_unavailable"
	var history: Dictionary = records(state)
	if history.size() >= MAX_OBSERVATIONS or history.has(action_id):
		return "appraisal_observation_limit"
	var result: Dictionary = prepare(state,p,action_id)
	if not result.ok:
		return result.error
	state.game_minutes = result.end_minute
	history[action_id] = result.entry
	return ""

static func active_view(state: Dictionary,basic_visit:String="") -> Dictionary:
	var visit_id: String = state.calendar.get("queue",{}).get("active","")
	var v: Dictionary = state.visits.get(visit_id,{})
	var prices: Dictionary = v.get("prices",{})
	if prices.size() != 1:
		return {}
	var subject_id: String = prices.keys()[0]
	if basic_available(state,visit_id,subject_id) and basic_visit!=visit_id and not basic_in_progress(state,visit_id,subject_id):
		return {}
	var configured: Dictionary = tools(state,visit_id,subject_id)
	if configured.is_empty():
		return {}
	return {"visit_id":visit_id,"item_id":subject_id,"tools":configured,"evidence":view(state,visit_id,subject_id)}
