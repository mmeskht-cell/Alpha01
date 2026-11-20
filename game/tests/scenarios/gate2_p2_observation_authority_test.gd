extends SceneTree
const Fixture = preload("res://tests/fixtures/p2_watch_state.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func fresh(enabled: bool = true, wrong: bool = false) -> RefCounted:
	return Fixture.fresh(enabled,wrong)

func cmd(s: RefCounted,kind: String,id: String,p: Dictionary = {}) -> Dictionary:
	return {"action_id":id,"expected_revision":s.snapshot().revision,"type":kind,"payload":p}

func payload(visit: String,item: String,tool: String,target: String) -> Dictionary:
	return {"visit_id":visit,"item_id":item,"tool_id":tool,"target":target}

func reject(s: RefCounted,kind: String,id: String,p: Dictionary = {}) -> bool:
	var before: Dictionary = s.snapshot()
	return not s.execute(cmd(s,kind,id,p)).ok and s.snapshot() == before

func _initialize() -> void:
	var s: RefCounted = fresh()
	var old: RefCounted = fresh(false)
	check(s != null,"opt-in calendar fixture")
	check(old != null,"old calendar fixture")
	if s == null or old == null:
		quit(1)
		return
	check(fresh(true,true) == null,"wrong specimen provenance at seed")
	var p: Dictionary = payload("watch_a","W001","wear_detail","dial_face")
	check(s.calendar_view().appraisal.is_empty() and reject(s,"inspect_subject","early",p),"unadmitted no observation or leak")
	check(old.execute(cmd(old,"calendar_next_visit","old_admit")).ok and reject(old,"inspect_subject","old_inspect",p),"legacy profile does not adopt new authority")
	check(s.execute(cmd(s,"calendar_next_visit","admit_a")).ok,"admit first witness")
	check(s.calendar_view().appraisal.item_id == "W001" and s.calendar_view().appraisal.evidence.is_empty(),"public tools only")
	check(reject(s,"inspect_subject","wrong",payload("watch_a","W002","wear_detail","dial_face")),"cross subject reject")
	check(reject(s,"inspect_subject","wrong_region",payload("watch_a","W001","wear_detail","back_mark")),"cross region reject")
	var forged: Dictionary = p.duplicate(true)
	forged["value"] = 0
	check(reject(s,"inspect_subject","forged",forged),"client truth reject")
	var action: Dictionary = cmd(s,"inspect_subject","wear_a",p)
	var before: Dictionary = s.snapshot()
	check(s.execute(action).ok,"commit novel inspection")
	var observed: Dictionary = s.snapshot()
	check(observed.game_minutes == 5 and observed.wallets == before.wallets and observed.items == before.items,"only time and knowledge changed")
	check(s.calendar_view().appraisal.evidence[0].observed_value == 43,"known sample public")
	check(s.execute(action).ok and s.snapshot() == observed,"receipt retry no second time cost")
	check(reject(s,"inspect_subject","repeat_wear",p),"same current observation cannot charge again")
	check(s.execute(cmd(s,"inspect_subject","function_a",payload("watch_a","W001","function_detail","whole_function"))).ok,"live function observation")
	check(s.calendar_view().appraisal.evidence.size() == 2 and s.snapshot().game_minutes == 10,"two independent observations")
	var active_saved: Dictionary = s.snapshot()
	var cold: RefCounted = fresh()
	check(cold.restore(active_saved) and cold.snapshot() == active_saved,"cold replay active observations")
	var tampered: Dictionary = active_saved.duplicate(true)
	tampered.calendar.appraisal_observations.wear_a.record.observed_value = 0
	check(not cold.restore(tampered) and cold.snapshot() == active_saved,"forged observation denied")
	tampered = active_saved.duplicate(true)
	tampered.calendar.appraisal_observations.wear_a.record.dependent_field_versions = {"functional":99}
	check(not cold.restore(tampered),"forged dependency denied")
	tampered = active_saved.duplicate(true)
	tampered.calendar.appraisal_observations.wear_a.visit_id = "watch_b"
	check(not cold.restore(tampered),"forged visit denied")
	check(not old.restore(active_saved),"legacy profile cannot adopt save")
	check(s.execute(cmd(s,"calendar_decline_visit","decline_a",{"visit_id":"watch_a"})).ok and s.calendar_view().appraisal.is_empty(),"departure revokes new observation and DTO")
	check(s.execute(cmd(s,"calendar_next_visit","admit_b")).ok and s.calendar_view().appraisal.evidence.is_empty(),"new visit no other object's observations")
	check(s.execute(cmd(s,"inspect_subject","wear_b",payload("watch_b","W002","wear_detail","dial_face"))).ok and s.calendar_view().appraisal.evidence[0].observed_value == 12,"second unique specimen")
	check(s.execute(cmd(s,"inspect_subject","function_b",payload("watch_b","W002","function_detail","whole_function"))).ok and s.calendar_view().appraisal.evidence[1].observed_value == "inoperable","actual second specimen function")
	var purchase: Dictionary = {"visit_id":"watch_b","item_id":"W002","seller":"seller","buyer":"player","currency":"VKC","amount":90,"inventory":"player_grid","x":0,"y":0,"rotated":false}
	check(s.execute(cmd(s,"trade","purchase",purchase)).ok and s.snapshot().wallets.player.VKC == 90 and s.calendar_view().appraisal.is_empty(),"actual trade closes observation access")
	check(s.snapshot().calendar.appraisal_observations.size() == 4,"historical facts retained after departure")
	for day: int in range(1,8):
		check(s.execute(cmd(s,"calendar_close","close_"+str(day))).ok,"calendar close")
		check(s.execute(cmd(s,"calendar_morning","morning_"+str(day))).ok,"calendar morning")
	check(s.calendar_view().complete and s.snapshot().game_minutes == 10080,"demo boundary")
	# Current fixture has fewer than 32 commands; cold replay covers all records.
	var final: Dictionary = s.snapshot()
	var repo := Repo.new("user://zt_rebuild/p2_watch_" + str(Time.get_ticks_usec()))
	check(repo.save_session(s,"p2_watch").ok,"actual disk save")
	var loaded: RefCounted = fresh()
	check(repo.load_session(loaded,"p2_watch").ok and loaded.snapshot() == final,"actual disk restore")
	print("GATE2_P2_OBSERVATION_AUTHORITY: ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
