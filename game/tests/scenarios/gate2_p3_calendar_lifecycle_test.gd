extends SceneTree
const Session=preload("res://src/domain/game_session.gd")
const Fixture=preload("res://tests/fixtures/gate0_c_state.gd")
const Watch=preload("res://tests/fixtures/p2_watch_state.gd")
const Objects=preload("res://src/domain/object_schema.gd")
const Repo=preload("res://src/persistence/checkpoint_repository.gd")
const Legacy=preload("res://src/persistence/save_repository.gd")
var checks:int=0
var failures:int=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func fresh(enabled:bool=true,reentry:bool=false,blocked:bool=false,tracking:bool=false)->RefCounted:
	var seed:Dictionary=Fixture.make()
	seed.wallets.player.USD=7
	seed.visits.purchase.expires=600
	seed.visits["resale"]=Fixture.visit("resale","player","buyer",{"X01":{"VKC":95,"USD":0}})
	seed.visits.resale.opens=1440
	seed.visits.resale.expires=2040
	seed.items["blocker"]=Objects.fresh_item("sample_consumable","buyer","buyer_grid",3 if blocked else 5,2 if blocked else 0,"fixture_blocker")
	var ids:Array=["d1","d2","d3","d4","d5","d6","d7"]
	var days:Dictionary={}
	for id:String in ids:
		days[id]=[]
	days.d1=["purchase"]
	days.d2=["resale"]
	var profile:Dictionary={"id":"demo_7","content_version":"p3-lifecycle-fixture-1","day_ids":ids,"visit_days":days}
	if enabled:
		profile["lifecycle_version"]="calendar-lifecycle-1"
	if reentry:
		profile["reentry_rules"]={"return_x":{"item_id":"X01","prior_sale":"resale","seller":"buyer","day":3,"price":{"VKC":80,"USD":0},"placement":{"inventory":"buyer_grid","x":3,"y":2,"rotated":false}}}
	if tracking:
		profile["tracking_candidates"]={"X01":{"tier":"tracked","pinned":false},"X01_A":{"tier":"narrative","pinned":true},"X01_B":{"tier":"narrative","pinned":false},"X01_C":{"tier":"narrative","pinned":false}}
	var s:=Session.new()
	return s if s.initialize(Fixture.definitions(),seed,false,false,profile) else null

func cmd(s:RefCounted,id:String,kind:String,p:Dictionary={})->Dictionary:
	return {"action_id":id,"expected_revision":s.snapshot().revision,"type":kind,"payload":p}

func act(s:RefCounted,id:String,kind:String,p:Dictionary={})->bool:
	return s.execute(cmd(s,id,kind,p)).ok

func reject(s:RefCounted,command:Dictionary,world:bool=true)->bool:
	var before:Dictionary=s.snapshot()
	var r:Dictionary=s.execute_world(command) if world else s.execute(command)
	return not r.ok and s.snapshot()==before

func _initialize()->void:
	var s:RefCounted=fresh()
	var old:RefCounted=fresh(false)
	check(s!=null and old!=null,"both profiles")
	if s==null or old==null:
		quit(1)
		return
	var sleep:Dictionary={"root_id":"X01"}
	check(reject(s,cmd(s,"future","world_sleep_family",sleep)),"pending visits protect family")
	check(reject(old,cmd(old,"disabled","world_sleep_family",{"root_id":"blocker"})),"legacy world denied")
	check(act(s,"admit","calendar_next_visit"),"admit")
	var buy:Dictionary=Fixture.purchase().payload
	buy["visit_id"]="purchase"
	check(act(s,"purchase","trade",buy),"actual purchase")
	check(reject(s,cmd(s,"owned","world_sleep_family",sleep)),"player owned stock denied")
	check(act(s,"close","calendar_close") and act(s,"repair","restore_item",{"actor":"player","item_id":"X01"}),"actual repair")
	check(act(s,"morning","calendar_morning") and act(s,"sale_admit","calendar_next_visit"),"later visit")
	check(act(s,"sale","trade",{"visit_id":"resale","item_id":"X01","seller":"player","buyer":"buyer","currency":"VKC","amount":95,"inventory":"buyer_grid","x":0,"y":0,"rotated":false}),"actual sale")
	var sold:Dictionary=s.snapshot()
	var history:Dictionary=s.calendar_item_history("X01")
	var child_history:Dictionary=s.calendar_item_history("X01_A")
	check(history.records.size()==2 and history.work_records.size()==1,"historical record before sleep")
	var sleep_cmd:Dictionary=cmd(s,"sleep","world_sleep_family",sleep)
	check(reject(s,sleep_cmd,false),"player world route denied")
	check(s.execute_world(sleep_cmd).ok,"world commits actual sleep")
	var asleep:Dictionary=s.snapshot()
	check(not asleep.items.has("X01") and asleep.calendar.dormant.X01.size()==4 and asleep.items.size()==1,"whole family absent from active grid")
	check(asleep.wallets==sold.wallets and asleep.ledger==sold.ledger and asleep.object_events==sold.object_events and asleep.game_minutes==sold.game_minutes,"no economic or time change")
	check(s.calendar_item_history("X01")==history and s.calendar_item_history("X01_A")==child_history and s.knowledge_view("X01").is_empty(),"history accessible; live inspect denied")
	check(s.execute_world(sleep_cmd).ok and s.snapshot()==asleep and reject(s,sleep_cmd,false),"idempotent world receipt never grants player permission")
	check(reject(s,cmd(s,"again","world_sleep_family",sleep)),"already dormant denied")
	check(reject(s,cmd(s,"missing","world_wake_family",{"root_id":"unknown","inventory":"buyer_grid","x":0,"y":0,"rotated":false})),"unknown identity denied")
	var wake_p:Dictionary={"root_id":"X01","inventory":"buyer_grid","x":5,"y":0,"rotated":false}
	check(reject(s,cmd(s,"collision","world_wake_family",wake_p)),"occupied reentry atomic")
	wake_p.x=3
	wake_p.y=2
	var wake_cmd:Dictionary=cmd(s,"wake","world_wake_family",wake_p)
	check(s.execute_world(wake_cmd).ok,"same family reactivation with fresh placement")
	var awake:Dictionary=s.snapshot()
	check(awake.calendar.dormant.is_empty() and awake.items.X01.x==3 and awake.items.X01.y==2 and awake.items.X01.owner_id=="buyer","fresh geometry same owner")
	check(awake.items.X01_A==sold.items.X01_A and awake.items.X01.basis==sold.items.X01.basis and awake.items.X01.provenance_id==sold.items.X01.provenance_id and awake.items.X01.functional,"child identity condition and basis preserved")
	check(s.calendar_item_history("X01")==history and awake.wallets==asleep.wallets,"world transitions not fabricated trade or work")
	var reload:RefCounted=fresh()
	check(reload.restore(asleep) and reload.restore(awake) and reload.snapshot()==awake,"cold exact replay")
	var fake:Dictionary=asleep.duplicate(true)
	fake.calendar.dormant.X01.X01_A.provenance_id="forged"
	check(not reload.restore(fake) and reload.snapshot()==awake,"tampered dormant identity denied")
	fake=asleep.duplicate(true)
	fake.items["X01"]=sold.items.X01
	check(not reload.restore(fake),"active/dormant duplicate denied")
	check(not old.restore(asleep),"old profile cannot load new seed")
	var dir:String="user://zt_rebuild/p3_life_"+str(Time.get_ticks_usec())
	var repo:=Repo.new(dir)
	check(not Legacy.new(dir).save_session(s,"legacy").ok,"opt-in v3 writer denied")
	check(repo.save("life",sold,[sleep_cmd],asleep,fresh).ok,"v4 world tail sleep")
	check(repo.save("life",asleep,[wake_cmd],awake,fresh).ok and repo.load_state("life",fresh).get("state")==awake,"v4 world tail wake exact")
	var file:=FileAccess.open(dir.path_join("life.v4.b.json"),FileAccess.WRITE)
	if file!=null:
		file.store_string("broken")
		file.close()
	var recovered:Dictionary=repo.load_state("life",fresh)
	check(recovered.get("recovered",false) and recovered.get("state")==asleep,"A/B prior dormant recovery")
	var w:RefCounted=Watch.fresh(true,false,true,true)
	check(w!=null,"opt-in appraisal fixture")
	if w!=null:
		check(act(w,"admit_a","calendar_next_visit") and act(w,"decline_a","calendar_decline_visit",{"visit_id":"watch_a"}) and act(w,"admit_b","calendar_next_visit"),"watch visit")
		check(act(w,"read_b","inspect_subject",{"visit_id":"watch_b","item_id":"W002","tool_id":"wear_detail","target":"dial_face"}),"actual observation")
		check(act(w,"decline_b","calendar_decline_visit",{"visit_id":"watch_b"}) and act(w,"close","calendar_close") and act(w,"morning","calendar_morning"),"expired visit")
		var observed:Dictionary=w.snapshot()
		check(w.execute_world(cmd(w,"sleep_b","world_sleep_family",{"root_id":"W002"})).ok,"observed external watch sleep")
		check(w.snapshot().calendar.appraisal_observations==observed.calendar.appraisal_observations and w.calendar_item_history("W002").records.is_empty(),"historical observation retained; no fake trade")
		var cold:RefCounted=Watch.fresh(true,false,true,true)
		check(cold.restore(w.snapshot()),"appraisal dormant replay")
	_return_tests(dir)
	_tracking_tests(dir)
	_watch_tracking()
	print("GATE2_P3_CALENDAR_LIFECYCLE: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)

func return_fixture()->RefCounted:
	return fresh(true,true)

func prepare_return(s:RefCounted,sell:bool=true)->bool:
	if not act(s,"admit","calendar_next_visit"):
		return false
	var buy:Dictionary=Fixture.purchase().payload
	buy["visit_id"]="purchase"
	if not act(s,"purchase","trade",buy) or not act(s,"close","calendar_close") or not act(s,"repair","restore_item",{"actor":"player","item_id":"X01"}) or not act(s,"morning","calendar_morning") or not act(s,"sale_admit","calendar_next_visit"):
		return false
	if sell:
		if not act(s,"sale","trade",{"visit_id":"resale","item_id":"X01","seller":"player","buyer":"buyer","currency":"VKC","amount":95,"inventory":"buyer_grid","x":0,"y":0,"rotated":false}):
			return false
		if not s.execute_world(cmd(s,"sleep","world_sleep_family",{"root_id":"X01"})).ok:
			return false
	else:
		if not act(s,"decline","calendar_decline_visit",{"visit_id":"resale"}):
			return false
	return true

func _return_tests(dir:String)->void:
	var s:RefCounted=return_fixture()
	check(s!=null and fresh(false,true)==null,"return rules require lifecycle opt-in")
	if s==null:
		return
	var p:Dictionary={"rule_id":"return_x"}
	check(reject(s,cmd(s,"early","world_open_visit",p)),"no future visit")
	check(not s.calendar_view().visits.terms.has("return_x") and not s.snapshot().visits.has("return_x"),"future terms not admitted")
	if not prepare_return(s):
		check(false,"prepare actual sale and dormancy")
		return
	check(reject(s,cmd(s,"same_day","world_open_visit",p)),"cannot return same day")
	check(act(s,"close2","calendar_close") and act(s,"morning2","calendar_morning"),"return date")
	var asleep:Dictionary=s.snapshot()
	check(s.calendar_view().visits.remaining==0 and not asleep.visits.has("return_x"),"no visit before world realization")
	var opening:Dictionary=cmd(s,"realize_return","world_open_visit",p)
	check(reject(s,opening,false) and reject(s,cmd(s,"injected","world_open_visit",p.merged({"price":1}))),"world-only and immutable authored terms")
	check(s.execute_world(opening).ok,"atomic return and visit")
	var opened:Dictionary=s.snapshot()
	if not opened.visits.has("return_x"):
		check(false,"return visit missing")
		return
	check(opened.items.X01.owner_id=="buyer" and opened.items.X01.provenance_id==asleep.calendar.dormant.X01.X01.provenance_id and opened.items.X01_A==asleep.calendar.dormant.X01.X01_A and opened.calendar.dormant.is_empty(),"same family and valid placement")
	check(opened.wallets==asleep.wallets and opened.ledger==asleep.ledger and opened.object_events==asleep.object_events and opened.game_minutes==asleep.game_minutes,"no invented sale or work")
	check(opened.visits.return_x.prices.X01.VKC==80 and s.calendar_view().visits.remaining==1 and s.calendar_view().visits.terms.is_empty(),"realized queue only")
	check(s.execute_world(opening).ok and s.snapshot()==opened and reject(s,opening,false) and reject(s,cmd(s,"duplicate","world_open_visit",p)),"one return receipt")
	check(reject(s,cmd(s,"pending","world_sleep_family",{"root_id":"X01"})),"returned visit protects stock")
	check(act(s,"admit_return","calendar_next_visit") and s.calendar_view().visits.active=="return_x","ordinary queue admits returned item")
	check(act(s,"repurchase","trade",{"visit_id":"return_x","item_id":"X01","seller":"buyer","buyer":"player","currency":"VKC","amount":80,"inventory":"player_grid","x":0,"y":0,"rotated":false}),"same ID repurchase")
	var terminal:Dictionary=s.snapshot()
	var hist:Dictionary=s.calendar_item_history("X01")
	check(hist.records.size()==3 and hist.records[0].amounts.VKC==80 and hist.work_records.size()==1,"actual continuous history")
	var cold:RefCounted=return_fixture()
	check(cold.restore(terminal) and cold.snapshot()==terminal,"cold exact return replay")
	var fake:Dictionary=terminal.duplicate(true)
	fake.visits.return_x.prices.X01.VKC=1
	check(not cold.restore(fake) and cold.snapshot()==terminal,"forged terms denied")
	var repo:=Repo.new(dir)
	check(repo.save("return",asleep,[opening],opened,return_fixture).ok and repo.load_state("return",return_fixture).get("state")==opened,"v4 return receipt replay")
	var hold:RefCounted=return_fixture()
	if hold!=null and prepare_return(hold,false) and act(hold,"close2","calendar_close") and act(hold,"morning2","calendar_morning"):
		check(reject(hold,cmd(hold,"held","world_open_visit",p)) and hold.snapshot().items.X01.owner_id=="player","held item cannot return")
	else:
		check(false,"hold fixture")
	var blocked:RefCounted=fresh(true,true,true)
	if blocked!=null and prepare_return(blocked) and act(blocked,"close2","calendar_close") and act(blocked,"morning2","calendar_morning"):
		check(reject(blocked,cmd(blocked,"blocked","world_open_visit",p)) and not blocked.snapshot().visits.has("return_x"),"blocked wake creates no appointment")
		check(act(blocked,"close3","calendar_close") and act(blocked,"morning3","calendar_morning") and reject(blocked,cmd(blocked,"late","world_open_visit",p)),"missed day not silently rerolled")
	else:
		check(false,"collision fixture")

func tracking_fixture()->RefCounted:
	return fresh(true,false,false,true)

func track(s:RefCounted,id:String,kind:String,p:Dictionary)->bool:
	return s.execute_world(cmd(s,id,kind,p)).ok

func _tracking_tests(dir:String)->void:
	var s:RefCounted=tracking_fixture()
	check(s!=null and fresh(false,false,false,true)==null,"tracking requires opt-in")
	if s==null:
		return
	var old:RefCounted=fresh()
	var root:Dictionary={"item_id":"X01"}
	var begin:Dictionary=s.snapshot()
	var promote:Dictionary=cmd(s,"promote","world_track_promote",root)
	check(reject(s,promote,false) and reject(old,cmd(old,"disabled_track","world_track_promote",root)),"private track permission")
	check(reject(s,cmd(s,"unknown_track","world_track_promote",{"item_id":"blocker"})),"authored candidate required")
	check(s.execute_world(promote).ok,"root promotion")
	var promoted:Dictionary=s.snapshot()
	check(promoted.calendar.tracking.X01.refs.is_empty() and promoted.wallets==begin.wallets and promoted.game_minutes==begin.game_minutes,"no fabricated past or reward")
	check(s.execute_world(promote).ok and s.snapshot()==promoted and reject(s,promote,false),"receipt idempotence without player bypass")
	check(track(s,"promote_a","world_track_promote",{"item_id":"X01_A"}) and track(s,"promote_b","world_track_promote",{"item_id":"X01_B"}),"independent child tracking")
	check(reject(s,cmd(s,"over_authored","world_track_promote",{"item_id":"X01_C"})),"authored budget enforced")
	check(reject(s,cmd(s,"suspend_active","world_track_suspend",root)),"active stock not suspended")
	check(prepare_return(s),"actual trade work sale sleep")
	var before_refs:Dictionary=s.snapshot()
	var reference:Dictionary=cmd(s,"retain_buy","world_track_reference",root.merged({"event_id":"purchase"}))
	check(s.execute_world(reference).ok and track(s,"retain_work","world_track_reference",root.merged({"event_id":"repair"})),"real purchase and work references")
	check(reject(s,cmd(s,"foreign","world_track_reference",{"item_id":"X01_A","event_id":"repair"})) and reject(s,cmd(s,"invented","world_track_reference",root.merged({"event_id":"invented"}))),"foreign and invented refs denied")
	check(reject(s,cmd(s,"duplicate_ref","world_track_reference",root.merged({"event_id":"purchase"}))),"duplicate retained reference denied")
	check(reject(s,cmd(s,"pinned","world_track_suspend",{"item_id":"X01_A"})),"pinned independent component protected")
	check(track(s,"suspend","world_track_suspend",root),"unprotected dormant tracking suspended")
	var stopped:Dictionary=s.snapshot()
	check(not stopped.calendar.tracking.X01.enabled and stopped.calendar.tracking.X01.refs==["purchase","repair"] and stopped.ledger==before_refs.ledger,"retained references and ledger intact")
	check(reject(s,cmd(s,"stopped_ref","world_track_reference",root.merged({"event_id":"sale"}))),"no new retention while suspended")
	check(track(s,"resume","world_track_promote",root) and s.snapshot().calendar.tracking.X01.refs==["purchase","repair"],"resume preserves refs")
	check(s.calendar_item_history("X01").records.size()==2 and not s.calendar_item_history("X01").has("tier") and not s.calendar_view().has("tracking"),"no tier exposure or fake trades")
	var cold:RefCounted=tracking_fixture()
	check(cold.restore(stopped) and cold.restore(s.snapshot()),"exact tracking replay")
	var forged:Dictionary=stopped.duplicate(true)
	forged.calendar.tracking.X01.refs.append("sale")
	check(not cold.restore(forged),"uncommitted reference tamper denied")
	var repo:=Repo.new(dir)
	var one_ref:RefCounted=tracking_fixture()
	check(one_ref.restore(before_refs) and one_ref.execute_world(reference).ok,"reference tail fixture")
	check(repo.save("tracking",before_refs,[reference],one_ref.snapshot(),tracking_fixture).ok and repo.load_state("tracking",tracking_fixture).get("state")==one_ref.snapshot(),"v4 tracking world tail")
	var disposal:RefCounted=tracking_fixture()
	if disposal!=null and act(disposal,"admit","calendar_next_visit"):
		var buy:Dictionary=Fixture.purchase().payload
		buy["visit_id"]="purchase"
		if act(disposal,"purchase","trade",buy) and track(disposal,"promote","world_track_promote",root) and track(disposal,"retain","world_track_reference",root.merged({"event_id":"purchase"})) and act(disposal,"close","calendar_close"):
			var pending:Dictionary=disposal.discard_preview("X01")
			if not pending.ok:
				check(false,"pending disposal preview")
				return
			var blocked_discard:Dictionary={"actor":"player","item_id":"X01","confirmed_ids":pending.item_ids}
			check(reject(disposal,cmd(disposal,"pending_discard","discard",blocked_discard),false),"future resale blocks disposal without mutation")
			if not act(disposal,"morning","calendar_morning") or not act(disposal,"sale_admit","calendar_next_visit") or not act(disposal,"decline","calendar_decline_visit",{"visit_id":"resale"}) or not act(disposal,"close2","calendar_close") or not act(disposal,"morning2","calendar_morning") or not act(disposal,"close3","calendar_close"):
				check(false,"expire resale before independent terminal tests")
				return
			var protected_branch:RefCounted=tracking_fixture()
			check(protected_branch.restore(disposal.snapshot()) and track(protected_branch,"pin","world_track_promote",{"item_id":"X01_A"}),"pinned branch")
			var preview:Dictionary=disposal.discard_preview("X01")
			if preview.ok:
				var p:Dictionary={"actor":"player","item_id":"X01","confirmed_ids":preview.item_ids}
				check(reject(protected_branch,cmd(protected_branch,"discard","discard",p),false),"pinned disposal atomic rejection")
				check(act(disposal,"discard","discard",p) and disposal.snapshot().tombstones.has("X01") and not disposal.snapshot().calendar.tracking.X01.enabled and disposal.snapshot().calendar.tracking.X01.refs==["purchase"],"terminal keeps refs and frees slot")
				check(reject(disposal,cmd(disposal,"resume_dead","world_track_promote",root)),"terminal cannot promote")
			else:
				check(false,"discard preview")
		else:
			check(false,"disposal fixture")
	else:
		check(false,"disposal seed")

func _watch_tracking()->void:
	var s:RefCounted=Watch.fresh(true,false,true,true,true)
	check(s!=null,"tracking appraisal seed")
	if s==null:
		return
	var subject:Dictionary={"visit_id":"watch_a","item_id":"W001"}
	var root:Dictionary={"item_id":"W001"}
	check(track(s,"promote","world_track_promote",root) and act(s,"admit","calendar_next_visit"),"watch track")
	check(act(s,"observe","inspect_subject",subject.merged({"tool_id":"wear_detail","target":"dial_face"})),"watch acquired observation")
	check(track(s,"retain_obs","world_track_reference",root.merged({"event_id":"observe"})),"calendar observation exact ref")
	check(act(s,"hypothesis","assess_subject",subject.merged({"slot_id":"appearance_id","candidate_id":"heavy_wear"})) and act(s,"link","link_subject_evidence",subject.merged({"slot_id":"appearance_id","evidence_id":"observe"})) and act(s,"draft","subject_deck_action",subject.merged({"slot_id":"appearance_id","op":"prepare","ref_id":"link"})),"private draft")
	check(reject(s,cmd(s,"private_ref","world_track_reference",root.merged({"event_id":"draft"}))),"private draft not retainable")
	check(act(s,"say","subject_deck_action",subject.merged({"slot_id":"appearance_id","op":"present","ref_id":"draft"})) and track(s,"retain_say","world_track_reference",root.merged({"event_id":"say"})),"actual public presentation retained")
	check(act(s,"offer","subject_price_offer",subject.merged({"currency":"VKC","amount":90,"presented_ids":["say"]})) and track(s,"retain_offer","world_track_reference",root.merged({"event_id":"offer"})),"actual offer retained")
	var reload:RefCounted=Watch.fresh(true,false,true,true,true)
	check(reload.restore(s.snapshot()) and reload.snapshot().calendar.tracking.W001.refs==["observe","say","offer"],"appraisal tracking exact replay")
