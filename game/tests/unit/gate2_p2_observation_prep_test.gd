extends SceneTree
const Authority = preload("res://src/domain/visit_appraisal_observation.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const Rules = preload("res://src/domain/value_rules.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func fixture() -> Dictionary:
	var items: Dictionary = {}
	items.W001 = Objects.fresh_item("fictional_watch_p2","seller","seller_grid",0,0,"p2_watch_a")
	items.W002 = Objects.fresh_item("fictional_watch_p2","seller","seller_grid",1,0,"p2_watch_b")
	items.W002.functional = false
	var visits: Dictionary = {}
	for pair: Array in [["watch_visit_a","W001"],["watch_visit_b","W002"]]:
		visits[pair[0]] = {"scope":{"visit_id":pair[0],"kind":"ordinary","purpose":"purchase","completed":false,"required_ids":[]},"seller":"seller","buyer":"player","prices":{pair[1]:{"VKC":90,"USD":0}},"opens":1440,"expires":2040,"allow_inspection":true}
	return {"phase":"shop","game_minutes":1440,"items":items,"inventories":{"seller_grid":{"owner_id":"seller","width":4,"height":4,"host_item":""}},"visits":visits,"calendar":{"queue":{"active":"watch_visit_a"}},"appraisal_observations":{}}

func payload(visit: String,item: String,tool: String,target: String) -> Dictionary:
	return {"visit_id":visit,"item_id":item,"tool_id":tool,"target":target}

func _initialize() -> void:
	var state: Dictionary = fixture()
	var Docs=preload("res://src/content/packaged_documents.gd")
	var Profiles=preload("res://src/domain/inspection_profile.gd")
	var legacy:Dictionary=Profiles.parse(Docs.read_object(Authority.PATH))
	check(Rules.canonical(Authority.book())==Rules.canonical(legacy),"legacy merged book byte semantics unchanged")
	var extended:Dictionary=Profiles.parse(Docs.read_object("res://data/campaign/gate2/demo_radio_inspection.json"))
	var expected:Dictionary=legacy.duplicate(true)
	expected.profiles.merge(extended.profiles)
	expected.specimens.merge(extended.specimens)
	var demo:Dictionary={"calendar":{"profile":{"content_version":"demo7-integrated-3"}}}
	check(Rules.canonical(Authority.book(demo))==Rules.canonical(expected),"demo3 inspection content hash unchanged")
	check(Authority.source_for({},"portable_radio").is_empty() and Authority.source_for(demo,"unknown_definition").is_empty(),"registry cannot grant unavailable or unknown profile")
	check(Authority.source_for(demo,"portable_radio").marker=="radio_catalog_sha" and Authority.source_for({},"fictional_watch_p2").marker=="catalog_sha","historical marker keys retained")
	var detached:Array=Authority.sources(demo)
	detached[0].marker="changed"
	check(Authority.source_for(demo,"fictional_watch_p2").marker=="catalog_sha","registry copies cannot mutate route")
	check(not Authority.book().is_empty(),"packaged observation profile")
	check(Authority.tools(state,"watch_visit_a","W001").size() == 4,"authorized public tools")
	check(Authority.tools(state,"watch_visit_b","W002").is_empty(),"inactive visit no tools")
	check(Authority.tools(state,"watch_visit_a","W002").is_empty(),"other subject no tools")
	check(not Authority.tools(state,"watch_visit_a","W001").wear_detail.has("value"),"no hidden readings")
	var p: Dictionary = payload("watch_visit_a","W001","wear_detail","dial_face")
	var before: Dictionary = state.duplicate(true)
	var result: Dictionary = Authority.prepare(state,p,"observe_a")
	check(result.ok and result.end_minute == 1445 and result.entry.record.observed_value == 43,"actual specimen and absolute day two clock")
	check(state == before,"pure preparation no side effects")
	if not result.ok:
		quit(1)
		return
	state.appraisal_observations.observe_a = result.entry
	state.game_minutes = result.end_minute
	check(Authority.view(state,"watch_visit_a","W001").size() == 1,"public captured reading")
	check(Authority.prepare(state,p,"repeat").error == "evidence_already_known","repeat current reading refused")
	check(not Authority.prepare(state,payload("watch_visit_a","W001","wear_detail","back_mark"),"wrong").ok,"wrong region refused")
	check(not Authority.prepare(state,payload("watch_visit_b","W002","wear_detail","dial_face"),"wrong_visit").ok,"inactive visit refused")
	p["value"] = 0
	check(not Authority.prepare(state,p,"fake").ok,"client-supplied reading refused")
	p.erase("value")
	var f: Dictionary = payload("watch_visit_a","W001","function_detail","whole_function")
	var first: Dictionary = Authority.prepare(state,f,"function_0")
	check(first.ok and first.entry.record.observed_value == "serviceable" and first.entry.record.dependent_field_versions == {"functional":0},"sample live function and version")
	state.appraisal_observations.function_0 = first.entry
	state.game_minutes = first.end_minute
	state.items.W001.functional = false
	state.items.W001.field_versions.functional = 1
	var second: Dictionary = Authority.prepare(state,f,"function_1")
	check(second.ok and second.entry.record.observed_value == "inoperable","changed state reinspection")
	check(state.appraisal_observations.function_0.record.observed_value == "serviceable","old reading not rewritten")
	var facts: Array = Authority.view(state,"watch_visit_a","W001")
	check(not facts[1].current and facts[0].current,"only affected fact stale")
	state.calendar.queue.active = "watch_visit_b"
	check(Authority.view(state,"watch_visit_a","W001").is_empty(),"closed context no hidden history access")
	var b: Dictionary = Authority.prepare(state,payload("watch_visit_b","W002","wear_detail","dial_face"),"observe_b")
	check(b.ok and b.entry.record.observed_value == 12,"same definition distinct specimen")
	state.items.W002.provenance_id = "forged"
	check(Authority.tools(state,"watch_visit_b","W002").is_empty(),"provenance mismatch")
	state.items.W002.provenance_id = "p2_watch_b"
	state.visits.watch_visit_b.allow_inspection = false
	check(not Authority.prepare(state,payload("watch_visit_b","W002","wear_detail","dial_face"),"no_consent").ok,"explicit inspection grant required")
	state.visits.watch_visit_b.allow_inspection = true
	state.game_minutes = 2036
	check(not Authority.prepare(state,payload("watch_visit_b","W002","wear_detail","dial_face"),"late").ok,"closing overrun refused")
	state.game_minutes = 2035
	check(Authority.prepare(state,payload("watch_visit_b","W002","wear_detail","dial_face"),"exact").end_minute == 2040,"exact closing boundary")
	state.visits.watch_visit_b.expires = 2039
	check(not Authority.prepare(state,payload("watch_visit_b","W002","wear_detail","dial_face"),"expiry").ok,"visit expiry before inspection end")
	print("GATE2_P2_OBSERVATION_PREP: ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
