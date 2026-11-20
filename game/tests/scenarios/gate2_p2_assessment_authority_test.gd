extends SceneTree
const Fixture = preload("res://tests/fixtures/p2_watch_state.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
const Assessment = preload("res://src/domain/visit_appraisal_assessment.gd")
const Relevance = preload("res://src/domain/public_appraisal_relevance.gd")
const Observation = preload("res://src/domain/visit_appraisal_observation.gd")
const Profiles = preload("res://src/domain/inspection_profile.gd")
var checks: int = 0
var failures: int = 0
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func cmd(s: RefCounted,kind: String,id: String,p: Dictionary = {}) -> Dictionary:
	return {"action_id":id,"expected_revision":s.snapshot().revision,"type":kind,"payload":p}

func select_card(s: RefCounted,id: String,slot: String,value: Variant,visit: String = "watch_a",item: String = "W001") -> Dictionary:
	return cmd(s,"assess_subject",id,{"visit_id":visit,"item_id":item,"slot_id":slot,"candidate_id":value})

func link(s: RefCounted,id: String,slot: String,evidence: String) -> Dictionary:
	return cmd(s,"link_subject_evidence",id,{"visit_id":"watch_a","item_id":"W001","slot_id":slot,"evidence_id":evidence})

func reject(s: RefCounted,c: Dictionary) -> bool:
	var before: Dictionary = s.snapshot()
	return not s.execute(c).ok and s.snapshot() == before

func verify_public_mapping()->void:
	var data:Dictionary=Relevance.load_mapping()
	check(data.size()==3,"public relevance contains both authored families and nonprice function")
	var demo:Dictionary={"calendar":{"profile":{"content_version":"demo7-integrated-3"}}}
	var book:Dictionary=Observation.book(demo)
	for row:Dictionary in Observation.sources(demo):
		var catalog:Dictionary=Observation.source_catalog(row)
		var tools:Dictionary=Profiles.tools_for(book,row.def_id)
		var keys:Array=[]
		for tool:Dictionary in tools.values():
			keys.append(tool.evidence_id)
		var mapping:Dictionary=Relevance.mapping(catalog)
		check(not mapping.is_empty(),"public relevance for "+row.def_id)
		for slot:String in mapping:
			check(Assessment.slot_exists(catalog,slot),"mapped public slot exists "+slot)
			for key:String in mapping[slot]:
				check(key in keys,"mapped observation is defined by public tool "+key)
	check(Relevance.mapping({"version":2})=={"function_id":["function_status"]},"basic non-price relevance retained")
	check(Relevance.mapping({"version":1,"def_id":"unknown"}).is_empty(),"unknown definition yields no recommendation")
	var invalid:Dictionary={"version":1,"definitions":{"watch":{"appearance_id":["wear","wear"]}},"nonprice":{"function_id":["function_status"]}}
	check(Relevance.parse(invalid).is_empty(),"duplicate relevance rejected")
	invalid.definitions.watch.appearance_id=["wear"]
	invalid.definitions.watch["bad slot"]=["wear"]
	check(Relevance.parse(invalid).is_empty(),"invalid slot rejected")
	invalid.definitions.watch.erase("bad slot")
	invalid.definitions.watch.appearance_id=[{"observed_value":43}]
	check(Relevance.parse(invalid).is_empty(),"no truth or reading in mapping")
	var copy:Dictionary=Relevance.mapping({"version":1,"def_id":"portable_radio"})
	copy.clear()
	check(not Relevance.mapping({"version":1,"def_id":"portable_radio"}).is_empty(),"public mapping detached copy")

func _initialize() -> void:
	verify_public_mapping()
	var s: RefCounted = Fixture.fresh()
	var reverse: RefCounted = Fixture.fresh()
	check(s != null and reverse != null,"fresh authority fixture")
	if s == null or reverse == null:
		quit(1)
		return
	check(reject(s,select_card(s,"early","model_id","meridian_12")),"no inactive hypothesis")
	check(s.execute(cmd(s,"calendar_next_visit","admit")).ok and reverse.execute(cmd(reverse,"calendar_next_visit","admit")).ok,"active visits")
	var baseline: Dictionary = s.snapshot()
	check(s.calendar_view().appraisal.reference.estimate == null and s.calendar_view().appraisal.assessment.selected.is_empty(),"empty selection not answered")
	check(s.execute(select_card(s,"appearance","appearance_id","visible_wear")).ok,"condition first")
	check(s.execute(select_card(s,"model","model_id","meridian_12a")).ok,"alternative conjecture accepted")
	check(s.execute(select_card(s,"material","material_id","decorative_case")).ok,"material choice")
	check(reverse.execute(select_card(reverse,"material","material_id","decorative_case")).ok and reverse.execute(select_card(reverse,"model","model_id","meridian_12a")).ok and reverse.execute(select_card(reverse,"appearance","appearance_id","visible_wear")).ok,"reverse selection order")
	check(s.calendar_view().appraisal.reference == reverse.calendar_view().appraisal.reference and s.calendar_view().appraisal.reference.estimate == 160,"order independent reference")
	check(s.snapshot().game_minutes == baseline.game_minutes and s.snapshot().wallets == baseline.wallets and s.snapshot().items == baseline.items,"free conjecture no actual state change")
	check(reject(s,select_card(s,"wrong","model_id","selvar_r18")),"foreign candidate refused")
	check(reject(s,select_card(s,"other","model_id","meridian_12","watch_a","W002")),"wrong subject")
	check(reject(s,select_card(s,"repeat","model_id","meridian_12a")),"unchanged selection")
	check(reject(s,link(s,"forged","appearance_id","invented")),"unobserved evidence refused")
	check(s.execute(cmd(s,"inspect_subject","wear",{"visit_id":"watch_a","item_id":"W001","tool_id":"wear_detail","target":"dial_face"})).ok,"actual evidence acquisition")
	var before_suggestion: Dictionary = s.snapshot()
	var suggestions: Dictionary = s.calendar_view().appraisal.evidence_suggestions
	check(suggestions.appearance_id==["wear"] and suggestions.model_id.is_empty() and suggestions.material_id.is_empty(),"observed wear only relevant to appearance")
	check(s.snapshot()==before_suggestion and s.calendar_view().appraisal.assessment.links.is_empty(),"suggestions read-only, no automatic link")
	var facts: Array = [{"evidence_id":"current","observation_key":"dial_wear","observed_value":10,"current":true,"is_claim":false},{"evidence_id":"stale","observation_key":"dial_wear","current":false,"is_claim":false},{"evidence_id":"claim","observation_key":"dial_wear","current":true,"is_claim":true},{"evidence_id":"mark","observation_key":"back_mark","current":true,"is_claim":false}]
	var projection: Dictionary = Assessment.evidence_suggestions(s.calendar_view().appraisal.catalog,facts)
	check(projection.appearance_id==["current"] and projection.model_id==["mark"] and projection.mark_id==["mark"],"stale and customer claims excluded, relevance not exclusive")
	facts[0].observed_value=99
	check(Assessment.evidence_suggestions(s.calendar_view().appraisal.catalog,facts)==projection,"recommendations independent of observation value")
	var l: Dictionary = link(s,"attach","appearance_id","wear")
	check(s.execute(l).ok and s.calendar_view().appraisal.assessment.links.appearance_id == ["wear"],"explicit link")
	var pinned: Dictionary = s.snapshot()
	check(s.execute(l).ok and s.snapshot() == pinned,"link receipt retry")
	check(s.execute(select_card(s,"revise","appearance_id","heavy_wear")).ok and s.calendar_view().appraisal.assessment.links.appearance_id == ["wear"],"revision keeps chosen observation reference")
	check(s.calendar_view().appraisal.reference.estimate == 120,"new reference only")
	check(s.calendar_view().appraisal.evidence_suggestions==suggestions,"suggestions independent of selected candidate")
	check(s.execute(link(s,"unlink","appearance_id","wear")).ok and s.calendar_view().appraisal.assessment.links.is_empty(),"remove evidence")
	check(s.execute(link(s,"relink","appearance_id","wear")).ok,"relink")
	check(s.execute(select_card(s,"clear","appearance_id",null)).ok and s.calendar_view().appraisal.assessment.links.is_empty() and s.calendar_view().appraisal.reference.estimate == null,"clear removes links and price estimate")
	check(reject(s,link(s,"empty_slot","appearance_id","wear")),"no link without hypothesis")
	check(s.execute(select_card(s,"function","function_id","inoperable")).ok,"unconfirmed function choice allowed")
	var saved: Dictionary = s.snapshot()
	var loaded: RefCounted = Fixture.fresh()
	check(loaded.restore(saved) and loaded.snapshot() == saved,"cold restore")
	var fake: Dictionary = saved.duplicate(true)
	fake.calendar.appraisal_assessments.watch_a.assessment.selected.model_id = "meridian_12"
	check(not loaded.restore(fake) and loaded.snapshot() == saved,"tampered judgment refused")
	fake = saved.duplicate(true)
	fake.calendar.appraisal_assessments.watch_a.assessment.links.model_id = ["forged"]
	check(not loaded.restore(fake),"tampered link refused")
	check(s.execute(cmd(s,"calendar_decline_visit","decline",{"visit_id":"watch_a"})).ok and s.calendar_view().appraisal.is_empty(),"close access")
	check(s.execute(cmd(s,"calendar_next_visit","next")).ok and s.calendar_view().appraisal.assessment.selected.is_empty(),"next visit isolated")
	check(s.snapshot().calendar.appraisal_assessments.has("watch_a"),"previous judgment retained")
	check(reject(s,select_card(s,"cross_visit","model_id","meridian_12","watch_a","W001")),"closed visit cannot edit")
	var repo := Repo.new("user://zt_rebuild/p2_assess_"+str(Time.get_ticks_usec()))
	check(repo.save_session(s,"p2_assess").ok and repo.load_session(loaded,"p2_assess").ok and loaded.snapshot() == s.snapshot(),"disk restore")
	print("GATE2_P2_ASSESSMENT_AUTHORITY: ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
