extends SceneTree
const Fixture = preload("res://tests/fixtures/p2_watch_state.gd")
const Claims = preload("res://src/domain/visit_customer_claims.gd")
const RuleSet = preload("res://src/domain/value_rules.gd")
const AppraisalPanelScript = preload("res://src/presentation/generic_appraisal_panel.gd")
const SaveRepo = preload("res://src/persistence/save_repository.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func cmd(s: RefCounted,id: String,kind: String,p: Dictionary = {}) -> Dictionary:
	return {"action_id":id,"type":kind,"expected_revision":s.snapshot().revision,"payload":p}

func act(s: RefCounted,id: String,kind: String,p: Dictionary = {}) -> bool:
	return s.execute(cmd(s,id,kind,p)).ok

func subject(visit: String = "watch_a",item: String = "W001") -> Dictionary:
	return {"visit_id":visit,"item_id":item}

func pick(s: RefCounted,id: String,slot: String,value: String,visit: String = "watch_a",item: String = "W001") -> bool:
	var p: Dictionary = subject(visit,item)
	p.merge({"slot_id":slot,"candidate_id":value})
	return act(s,id,"assess_subject",p)

func card(s: RefCounted,id: String,op: String,slot: String,ref_id: String,visit: String = "watch_a",item: String = "W001") -> Dictionary:
	var p: Dictionary = subject(visit,item)
	p.merge({"op":op,"slot_id":slot,"ref_id":ref_id})
	return cmd(s,id,"subject_deck_action",p)

func speeches(s: RefCounted) -> Array:
	return s.calendar_view().appraisal.deck.presented

func _initialize() -> void:
	run.call_deferred()

func verify_demo_policy()->void:
	var policy:Dictionary=Claims.demo_policy()
	if not check_policy_loaded(policy):
		return
	check(RuleSet.canonical(policy).sha256_text()==Claims.binding("demo7-integrated-3"),"packaged authored policy exact historical binding")
	for visit:String in Claims.DEMO_TERMS:
		check(Claims.settlement(visit)==Claims.DEMO_TERMS[visit],"unchanged settlement "+visit)
	check(Claims.settlement("unknown_visit").is_empty(),"no invented terms for unmapped visit")
	var changed:Dictionary=policy.duplicate(true)
	changed.terms.visit_g01.floor=1
	check(Claims.validated_demo_policy(changed).is_empty(),"altered floor rejected, no implicit migration")
	changed=policy.duplicate(true)
	changed.radio_beats.visit_g01.appearance_id.candidate_id="heavy_wear"
	check(Claims.validated_demo_policy(changed).is_empty(),"altered seller recollection rejected")
	changed=policy.duplicate(true)
	changed.version="unapproved"
	check(Claims.validated_demo_policy(changed).is_empty(),"unknown policy version rejected")
	var detached:Dictionary=Claims.settlement("visit_g01")
	detached.floor=1
	check(Claims.settlement("visit_g01").floor==110,"caller cannot mutate cached authority content")

func check_policy_loaded(policy:Dictionary)->bool:
	check(not policy.is_empty(),"packaged demo3 policy available")
	return not policy.is_empty()

func run() -> void:
	verify_demo_policy()
	var s: RefCounted = Fixture.fresh(true,false,true)
	var old: RefCounted = Fixture.fresh()
	check(s != null and old != null,"both profile generations")
	if s == null or old == null:
		quit(1)
		return
	check(act(s,"admit","calendar_next_visit"),"admit")
	check(s.calendar_view().appraisal.deck.presented.is_empty(),"no future claims in deck")
	check(pick(s,"wear","appearance_id","heavy_wear") and s.execute(card(s,"draft","prepare","appearance_id","wear")).ok,"private draft")
	check(speeches(s).is_empty(),"no response before explicit speech")
	var before: Dictionary = s.snapshot()
	var speech: Dictionary = card(s,"say","present","appearance_id","draft")
	check(s.execute(speech).ok,"present")
	var public: Dictionary = speeches(s)[0]
	var response: Dictionary = public.get("customer_response",{})
	check(response.get("relation")=="disagrees" and response.get("candidate_id")=="light_wear","authored disagreement")
	check(response.get("is_claim")==true and response.get("verified")==false and response.get("basis")=="seller_recollection" and response.get("presentation_id")=="say","source explicit and not verified")
	check(s.calendar_view().appraisal.evidence.is_empty(),"claim not instrument evidence")
	check(s.snapshot().wallets==before.wallets and s.snapshot().game_minutes==before.game_minutes and s.snapshot().ledger==before.ledger and s.snapshot().items==before.items,"no economy time or truth mutation")
	var after: Dictionary = s.snapshot()
	check(s.execute(speech).ok and s.snapshot()==after,"idempotent response")
	var panel := AppraisalPanelScript.new()
	root.add_child(panel)
	panel.configure(s.calendar_view().appraisal,s.snapshot().revision,Callable(),"en",false,"customer")
	check(panel.find_child("claim_a_wear_claim",true,false)!=null,"claim visible to customer view")
	panel.configure(s.calendar_view().appraisal,s.snapshot().revision,Callable(),"en",false,"appraisal")
	check(panel.find_child("claim_a_wear_claim",true,false)!=null,"claim retained during investigation")
	panel.queue_free()
	await process_frame
	var p: Dictionary = subject()
	p.merge({"slot_id":"appearance_id","evidence_id":"a_wear_claim"})
	check(not act(s,"fake_link","link_subject_evidence",p) and s.snapshot()==after,"cannot link unverified claim as fact")
	check(pick(s,"no_evidence_pick","appearance_id","visible_wear") and s.execute(card(s,"no_evidence_draft","prepare","appearance_id","no_evidence_pick")).ok,"unsupported competing draft")
	var unsupported: Dictionary = card(s,"unsupported_rebut","present","appearance_id","no_evidence_draft")
	unsupported.payload["claim_id"]="a_wear_claim"
	var unsupported_before: Dictionary = s.snapshot()
	check(not s.execute(unsupported).ok and s.snapshot()==unsupported_before,"no evidence cannot explicitly rebut")
	check(s.execute(card(s,"remove_unsupported","remove","appearance_id","no_evidence_draft")).ok and pick(s,"restore_wear","appearance_id","heavy_wear"),"restore initial private hypothesis")
	var observe: Dictionary = subject()
	observe.merge({"tool_id":"wear_detail","target":"dial_face"})
	check(act(s,"inspect","inspect_subject",observe),"independent observation")
	p["evidence_id"]="inspect"
	check(act(s,"link","link_subject_evidence",p),"link actual evidence")
	check(s.execute(card(s,"revised","prepare","appearance_id","link")).ok,"prepare new evidence")
	var prepared: Dictionary = s.snapshot()
	var bad: Dictionary = card(s,"bad_claim","present","appearance_id","revised")
	bad.payload["claim_id"] = "b_wear_claim"
	check(not s.execute(bad).ok and s.snapshot()==prepared,"foreign claim rejected")
	bad.payload["claim_id"] = "a_model_claim"
	check(not s.execute(bad).ok and s.snapshot()==prepared,"undisclosed claim rejected")
	bad.payload["claim_id"] = "a_wear_claim"
	bad.payload["op"] = "remove"
	check(not s.execute(bad).ok and s.snapshot()==prepared,"claim reference on remove rejected")
	var options: Array = s.calendar_view().appraisal.deck.ready[0].rebuttal_options
	check(options.size()==1 and options[0].claim_id=="a_wear_claim" and options[0].new_evidence_ids==["inspect"],"authority derives current claim option")
	var counter_panel := AppraisalPanelScript.new()
	root.add_child(counter_panel)
	counter_panel.configure(s.calendar_view().appraisal,s.snapshot().revision,Callable(),"en",false,"customer")
	check(counter_panel.find_child("rebut_revised_a_wear_claim",true,false)!=null,"explicit rebuttal button")
	counter_panel.configure(s.calendar_view().appraisal,s.snapshot().revision,Callable(),"en",false,"appraisal")
	check(counter_panel.find_child("rebut_revised_a_wear_claim",true,false)==null,"private gaze cannot rebut")
	counter_panel.queue_free()
	await process_frame
	var rebut: Dictionary = card(s,"say_again","present","appearance_id","revised")
	rebut.payload["claim_id"]="a_wear_claim"
	check(s.execute(rebut).ok,"explicit response with newly linked evidence")
	check(speeches(s)[1].rebuttal.claim_presentation_id=="say" and speeches(s)[1].rebuttal.new_evidence_ids==["inspect"] and not speeches(s)[1].rebuttal.verified,"rebuttal lineage and no truth certification")
	var after_rebut: Dictionary = s.snapshot()
	check(s.execute(rebut).ok and s.snapshot()==after_rebut,"idempotent rebuttal")
	check(pick(s,"other_wear","appearance_id","visible_wear") and s.execute(card(s,"repeat_draft","prepare","appearance_id","other_wear")).ok,"changed conjecture can be drafted")
	var repeated: Dictionary = card(s,"repeat_rebut","present","appearance_id","repeat_draft")
	repeated.payload["claim_id"]="a_wear_claim"
	var repeat_before: Dictionary = s.snapshot()
	check(not s.execute(repeated).ok and s.snapshot()==repeat_before,"cannot recycle already used evidence for same claim")
	check(s.calendar_view().appraisal.deck.ready[0].rebuttal_options.is_empty(),"no UI rebut option when evidence reused")
	check(s.execute(card(s,"remove_repeat","remove","appearance_id","repeat_draft")).ok,"remove private repeat draft")
	check(speeches(s)[0]==public and not speeches(s)[1].has("customer_response"),"same authored beat once, old claim immutable")
	check(pick(s,"model","model_id","meridian_12a") and s.execute(card(s,"model_draft","prepare","model_id","model")).ok and s.execute(card(s,"model_say","present","model_id","model_draft")).ok,"other authored beat")
	check(speeches(s)[2].customer_response.relation=="agrees" and not speeches(s)[2].customer_response.verified,"agreement is not certification")
	var snapshot: Dictionary = s.snapshot()
	var reload: RefCounted = Fixture.fresh(true,false,true)
	check(reload.restore(snapshot) and reload.snapshot()==snapshot,"deterministic cold replay")
	var fake: Dictionary = snapshot.duplicate(true)
	fake.calendar.appraisal_decks.watch_a.deck.presented[0].customer_response.verified=true
	check(not reload.restore(fake) and reload.snapshot()==snapshot,"tampered verified claim refused")
	fake = snapshot.duplicate(true)
	fake.calendar.appraisal_decks.watch_a.deck.presented[1].rebuttal.claim_presentation_id="model_say"
	check(not reload.restore(fake) and reload.snapshot()==snapshot,"tampered rebuttal source refused")
	var repo := SaveRepo.new("user://zt_rebuild/p2_claim_"+str(Time.get_ticks_usec()))
	check(repo.save_session(s,"claims").ok and repo.load_session(reload,"claims").ok and reload.snapshot()==snapshot,"disk restore preserves response")
	check(act(s,"decline","calendar_decline_visit",{"visit_id":"watch_a"}) and s.calendar_view().appraisal.is_empty(),"terminal visit")
	check(act(s,"next","calendar_next_visit") and speeches(s).is_empty(),"next customer independent")
	check(pick(s,"b_wear","appearance_id","light_wear","watch_b","W002") and s.execute(card(s,"b_draft","prepare","appearance_id","b_wear","watch_b","W002")).ok and s.execute(card(s,"b_say","present","appearance_id","b_draft","watch_b","W002")).ok,"new customer speech")
	check(speeches(s)[0].customer_response.beat_id=="b_wear_claim" and speeches(s)[0].customer_response.item_id=="W002","visit/item isolation")
	check(act(old,"old_admit","calendar_next_visit") and pick(old,"old_wear","appearance_id","heavy_wear") and old.execute(card(old,"old_draft","prepare","appearance_id","old_wear")).ok and old.execute(card(old,"old_say","present","appearance_id","old_draft")).ok,"legacy deck")
	check(not speeches(old)[0].has("customer_response"),"old snapshot semantics unchanged")
	print("GATE2_P2_CUSTOMER_CLAIMS: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
