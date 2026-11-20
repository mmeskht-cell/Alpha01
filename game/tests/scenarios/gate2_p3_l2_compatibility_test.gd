extends SceneTree
## Bounded real calendar transaction + seven-day idle closure, not a campaign bot.
const Fixture=preload("res://tests/fixtures/p2_watch_state.gd")
const Registry=preload("res://src/domain/dormant_registry.gd")
const Audit=preload("res://src/domain/calendar_identity_audit.gd")
const Tracking=preload("res://src/domain/selective_tracking.gd")
const Codec=preload("res://src/persistence/registry_pilot_format.gd")
const Checkpoint=preload("res://src/persistence/checkpoint_format.gd")
const Legacy=preload("res://src/domain/snapshot_format.gd")
const Repo=preload("res://src/persistence/save_repository.gd")
const Rules=preload("res://src/domain/value_rules.gd")
var checks:int=0
var failures:int=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func fresh()->RefCounted:
	return Fixture.fresh(true,false,true)

func act(s:RefCounted,id:String,kind:String,p:Dictionary={})->bool:
	return s.execute({"action_id":id,"expected_revision":s.snapshot().revision,"type":kind,"payload":p}).ok

func measure(s:RefCounted,seed:Dictionary,day:int)->bool:
	var full:Dictionary=s.snapshot()
	var start:int=Time.get_ticks_usec()
	var p:Dictionary=Audit.begin(s)
	if p.is_empty():
		return false
	var sleeping:Dictionary=Audit.sleep(p,"W002",s)
	if sleeping.is_empty():
		return false
	var tracked:Dictionary=Tracking.promote(sleeping,"W001","tracked",false,s)
	if tracked.is_empty():
		return false
	tracked=Tracking.retain_reference(tracked,"W001","purchase",s)
	if tracked.is_empty():
		return false
	tracked=Tracking.promote(tracked,"W002","narrative",true,s)
	if tracked.is_empty():
		return false
	var packed:String=Codec.pack(tracked,s,seed)
	var checkpoint:String=Checkpoint.encode("s".repeat(64),full,[],full)
	var unpacked:Dictionary=Codec.unpack(packed,s,seed)
	var restored:Dictionary=Checkpoint.decode(checkpoint,"s".repeat(64),fresh)
	var size:int=Legacy.encoded_size(full)
	var valid:bool=not packed.is_empty() and not checkpoint.is_empty() and unpacked.get("state")==full and unpacked.get("partition")==tracked and restored.get("state")==full and s.snapshot()==full and size<=Legacy.MAX_BYTES
	print("ZT_P3_L2_SAMPLE ",JSON.stringify({"days":day,"revision":full.revision,"active_authority":full.items.size(),"partition_active":tracked.state.items.size(),"partition_dormant_roots":tracked.dormant.size(),"tracked_rows":tracked.tracking.size(),"v3_guard_bytes":size,"registry_bytes":packed.to_utf8_buffer().size(),"v4_bytes":checkpoint.to_utf8_buffer().size(),"probe_us":Time.get_ticks_usec()-start,"ok":valid}))
	check(valid,"exact three-format sample "+str(day))
	check(Registry.locate(tracked,"W002")=="dormant" and Registry.locate(tracked,"W001")=="active" and Registry.materialize(tracked,s)==full,"disjoint identity resolution "+str(day))
	check(Registry.sleep_family(tracked,"W001",s).is_empty() and Tracking.suspend(tracked,"W002",s).is_empty(),"player stock and pinned tracking protected "+str(day))
	var wake:Dictionary=Audit.wake(tracked,"W002",s)
	check(not wake.is_empty() and Registry.materialize(wake,s)==full and wake.tracking==tracked.tracking,"lossless detached wake "+str(day))
	var duplicate:Dictionary=tracked.duplicate(true)
	duplicate.state.items["W002"]=full.items.W002.duplicate(true)
	check(Registry.materialize(duplicate,s).is_empty(),"duplicate ID denied "+str(day))
	check(Tracking.retain_reference(tracked,"W002","purchase",s).is_empty(),"foreign event not retained "+str(day))
	var audited:Dictionary=Audit.audit(tracked,s)
	check(audited.ok and audited.items=={"W001":"active","W002":"dormant"} and audited.revision==full.revision and audited.binding==full.calendar.binding,"private seed-bound identity audit "+str(day))
	check(not Audit.audit(duplicate,s).ok,"candidate duplicate audit denied "+str(day))
	var false_ref:Dictionary=tracked.duplicate(true)
	false_ref.state.calendar.appraisal_offers.watch_a[0].presentations[0].argument.evidence_ids=["invented"]
	check(not Audit.audit(false_ref,s).ok and s.snapshot()==full,"tampered frozen evidence denied "+str(day))
	var suspended:Dictionary=Tracking.suspend(tracked,"W001",s)
	check(not suspended.is_empty() and not suspended.tracking.W001.enabled and suspended.tracking.W001.refs==["purchase"],"suspension retains references "+str(day))
	var reload:RefCounted=fresh()
	check(not reload.restore(tracked.state) and reload.restore(unpacked.state) and reload.calendar_item_history("W001")==s.calendar_item_history("W001"),"partition not a live save; materialized history exact "+str(day))
	return valid

func _initialize()->void:
	var s:RefCounted=fresh()
	check(s!=null,"calendar fixture")
	if s==null:
		quit(1)
		return
	var seed:Dictionary=s.snapshot()
	check(Audit.sleep(Audit.begin(s),"W002",s).is_empty(),"pending visit protected")
	var subject:Dictionary={"visit_id":"watch_a","item_id":"W001"}
	check(act(s,"admit","calendar_next_visit"),"admit")
	check(act(s,"hypothesis","assess_subject",subject.merged({"slot_id":"appearance_id","candidate_id":"heavy_wear"})),"hypothesis")
	check(act(s,"observe","inspect_subject",subject.merged({"tool_id":"wear_detail","target":"dial_face"})),"inspection")
	check(act(s,"link","link_subject_evidence",subject.merged({"slot_id":"appearance_id","evidence_id":"observe"})),"link")
	check(act(s,"draft","subject_deck_action",subject.merged({"slot_id":"appearance_id","op":"prepare","ref_id":"link"})) and act(s,"say","subject_deck_action",subject.merged({"slot_id":"appearance_id","op":"present","ref_id":"draft"})),"public claim")
	check(act(s,"offer","subject_price_offer",subject.merged({"currency":"VKC","amount":90,"presented_ids":["say"]})),"accepted price")
	check(act(s,"purchase","trade",subject.merged({"seller":"seller","buyer":"player","currency":"VKC","amount":90,"inventory":"player_grid","x":0,"y":0,"rotated":false,"offer_id":"offer"})),"settled purchase")
	check(act(s,"admit_b","calendar_next_visit") and act(s,"decline_b","calendar_decline_visit",{"visit_id":"watch_b"}),"declined separate specimen")
	for day:int in range(1,8):
		if not act(s,"close_"+str(day),"calendar_close") or not act(s,"morning_"+str(day),"calendar_morning"):
			check(false,"calendar boundary "+str(day))
			quit(1)
			return
		if day in [1,7]:
			check(measure(s,seed,day),"bounded compatibility sample "+str(day))
	var final:Dictionary=s.snapshot()
	check(final.ledger.size()==1 and final.items.size()==2 and final.calendar.commands.size()==final.revision and s.calendar_view().complete,"no generation or deletion during sample")
	check(s.calendar_item_history("W001").records[0].offer.observations[0].evidence_id=="observe" and s.calendar_item_history("W002").records.is_empty(),"only actual history")
	var repo:=Repo.new("user://zt_rebuild/p3_l2_"+str(Time.get_ticks_usec()))
	var loaded:RefCounted=fresh()
	check(repo.save_session(s,"compatibility").ok and repo.load_session(loaded,"compatibility").ok and loaded.snapshot()==final,"unchanged runtime save roundtrip")
	print("GATE2_P3_L2_COMPATIBILITY: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
