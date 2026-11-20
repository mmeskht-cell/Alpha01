extends SceneTree
const Fixture = preload("res://tests/fixtures/p2_watch_state.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
const Deck = preload("res://src/domain/visit_negotiation_deck.gd")
const Receipt = preload("res://src/domain/receipt_primitives.gd")
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

func deck(s: RefCounted,id: String,op: String,slot: String,ref_id: String,visit: String = "watch_a",item: String = "W001") -> Dictionary:
	return cmd(s,"subject_deck_action",id,{"visit_id":visit,"item_id":item,"op":op,"slot_id":slot,"ref_id":ref_id})

func reject(s: RefCounted,c: Dictionary) -> bool:
	var before: Dictionary = s.snapshot()
	return not s.execute(c).ok and s.snapshot() == before

func direct_presentation() -> void:
	var s: RefCounted = Fixture.fresh(true,false,true)
	check(s != null,"direct fixture")
	if s == null:
		return
	check(reject(s,deck(s,"direct_early","present_direct","appearance_id","none")),"direct inactive rejected")
	check(s.execute(cmd(s,"calendar_next_visit","direct_admit")).ok,"direct admit")
	var start: Dictionary = s.snapshot()
	check(s.execute(select_card(s,"direct_private","appearance_id","visible_wear")).ok,"direct private judgment")
	check(s.calendar_view().appraisal.deck.ready.is_empty() and s.calendar_view().appraisal.deck.presented.is_empty(),"private creates no prepared duplicate or speech")
	check(s.execute(select_card(s,"direct_edit","appearance_id","heavy_wear")).ok,"revise before disclosure")
	check(reject(s,deck(s,"direct_stale","present_direct","appearance_id","direct_private")),"direct stale ref refused")
	check(reject(s,deck(s,"direct_forged","present_direct","appearance_id","invented")),"direct forged ref refused")
	check(reject(s,deck(s,"direct_wrong_item","present_direct","appearance_id","direct_edit","watch_a","W002")),"direct wrong item refused")
	var say: Dictionary = deck(s,"direct_say","present_direct","appearance_id","direct_edit")
	check(s.execute(say).ok,"one command directly discloses current judgment")
	var public_row: Dictionary = s.calendar_view().appraisal.deck.presented[0].duplicate(true)
	check(public_row.argument.candidate_id == "heavy_wear" and public_row.argument.evidence_ids.is_empty() and public_row.argument.statement_kind == "hypothesis","unverified judgment remains hypothesis")
	check(s.calendar_view().appraisal.deck.ready.is_empty(),"no stored preparation")
	var spoken: Dictionary = s.snapshot()
	check(s.execute(say).ok and s.snapshot()==spoken,"direct idempotent")
	check(reject(s,deck(s,"direct_repeat","present_direct","appearance_id","direct_edit")),"direct semantic duplicate refused")
	check(s.snapshot().wallets==start.wallets and s.snapshot().items==start.items and s.snapshot().ledger==start.ledger and s.snapshot().game_minutes==start.game_minutes,"direct no economic or clock effects")
	check(s.execute(select_card(s,"direct_correct","appearance_id","visible_wear")).ok,"new private correction")
	check(s.calendar_view().appraisal.deck.presented[0]==public_row,"private correction leaves public record")
	check(s.execute(deck(s,"direct_say2","present_direct","appearance_id","direct_correct")).ok,"explicit correction")
	var records: Array = s.calendar_view().appraisal.deck.presented
	check(records.size()==2 and records[0]==public_row and records[1].get("corrects_presentation_id")=="direct_say","correction refers to original speech")
	var active: Dictionary = s.snapshot()
	var reload: RefCounted = Fixture.fresh(true,false,true)
	check(reload.restore(active) and reload.snapshot()==active,"direct cold replay")
	var fake: Dictionary = active.duplicate(true)
	fake.calendar.appraisal_decks.watch_a.deck.presented[1].corrects_presentation_id = "invented"
	check(not reload.restore(fake) and reload.snapshot()==active,"direct tampered correction resisted")
	check(s.execute(cmd(s,"calendar_decline_visit","direct_decline",{"visit_id":"watch_a"})).ok,"direct decline")
	check(s.snapshot().calendar.appraisal_decks.watch_a.deck.presented.size()==2 and s.snapshot().ledger.is_empty(),"decline preserves speech without fake trade")
	check(reject(s,deck(s,"direct_closed","present_direct","appearance_id","direct_correct")),"closed direct refused")

func withdrawal_and_reaffirmation() -> void:
	var session: RefCounted = Fixture.fresh(true,false,true)
	check(session != null,"withdraw fixture")
	if session == null:
		return
	check(session.execute(cmd(session,"calendar_next_visit","withdraw_admit")).ok,"withdraw admit")
	check(session.execute(select_card(session,"withdraw_pick","appearance_id","heavy_wear")).ok,"withdraw private pick")
	check(session.execute(deck(session,"withdraw_say","present_direct","appearance_id","withdraw_pick")).ok,"withdraw initial public")
	var original: Dictionary = session.calendar_view().appraisal.deck.presented[0].duplicate(true)
	var before: Dictionary = session.snapshot()
	check(reject(session,deck(session,"withdraw_forged","withdraw","appearance_id","invented")),"withdraw forged refused")
	check(reject(session,deck(session,"withdraw_wrong","withdraw","model_id","withdraw_say")),"withdraw wrong slot refused")
	var withdraw: Dictionary = deck(session,"withdraw_event","withdraw","appearance_id","withdraw_say")
	check(session.execute(withdraw).ok,"explicit withdrawal")
	var after: Dictionary = session.snapshot()
	var dto: Dictionary = session.calendar_view().appraisal.deck
	check(dto.presented.size()==2 and dto.presented[0]==original and dto.presented[1].withdraws_presentation_id=="withdraw_say","withdrawal preserves original")
	check(dto.public_basis_ids.is_empty() and dto.direct_ready.size()==1,"no active public basis, private remains")
	check(session.execute(withdraw).ok and session.snapshot()==after,"withdrawal idempotent")
	check(reject(session,deck(session,"withdraw_repeat","withdraw","appearance_id","withdraw_say")),"repeat withdrawal denied")
	check(session.execute(deck(session,"withdraw_reaffirm","present_direct","appearance_id","withdraw_pick")).ok,"explicit same judgment reaffirmed")
	dto = session.calendar_view().appraisal.deck
	check(dto.public_basis_ids==["withdraw_reaffirm"] and dto.presented[2].corrects_presentation_id=="withdraw_event" and not dto.presented[2].has("customer_response"),"reaffirmation chain, no repeated customer beat")
	check(reject(session,deck(session,"withdraw_dup","present_direct","appearance_id","withdraw_pick")),"active duplicate denied")
	check(session.execute(select_card(session,"withdraw_other","appearance_id","visible_wear")).ok and session.execute(deck(session,"withdraw_other_say","present_direct","appearance_id","withdraw_other")).ok,"correct to another judgment")
	check(session.execute(select_card(session,"withdraw_back","appearance_id","heavy_wear")).ok and session.execute(deck(session,"withdraw_back_say","present_direct","appearance_id","withdraw_back")).ok,"return to earlier judgment explicitly")
	check(session.snapshot().wallets==before.wallets and session.snapshot().items==before.items and session.snapshot().game_minutes==before.game_minutes and session.snapshot().ledger==before.ledger,"no clock or economic effect")
	var reload: RefCounted = Fixture.fresh(true,false,true)
	var snapshot: Dictionary = session.snapshot()
	check(reload.restore(snapshot) and reload.snapshot()==snapshot,"withdrawal deterministic replay")
	var forged: Dictionary = snapshot.duplicate(true)
	forged.calendar.appraisal_decks.watch_a.deck.presented[1].withdraws_presentation_id="fake"
	check(not reload.restore(forged) and reload.snapshot()==snapshot,"withdrawal tamper denied")

func _initialize() -> void:
	direct_presentation()
	withdrawal_and_reaffirmation()
	var s: RefCounted = Fixture.fresh()
	var legacy: RefCounted = Fixture.fresh(false)
	check(s != null and legacy != null,"fixtures")
	if s == null or legacy == null:
		quit(1)
		return
	check(reject(s,deck(s,"early","prepare","appearance_id","no_source")),"no inactive deck")
	check(s.execute(cmd(s,"calendar_next_visit","admit")).ok,"admit")
	check(s.calendar_view().appraisal.deck.ready.is_empty() and s.calendar_view().appraisal.deck.presented.is_empty(),"empty deck valid")
	check(legacy.execute(cmd(legacy,"calendar_next_visit","old_admit")).ok and reject(legacy,deck(legacy,"legacy","prepare","appearance_id","no_source")),"old profile cannot use deck")
	check(s.execute(select_card(s,"appearance","appearance_id","visible_wear")).ok,"private hypothesis")
	check(s.calendar_view().appraisal.deck.presented.is_empty(),"assessment not public")
	var pre_deck: Dictionary = s.snapshot()
	var old_save: RefCounted = Fixture.fresh()
	check(old_save.restore(pre_deck),"pre-deck compatible snapshot")
	check(reject(s,deck(s,"forged_source","prepare","appearance_id","unknown")),"invented source refused")
	var prep: Dictionary = deck(s,"prepare_1","prepare","appearance_id","appearance")
	check(s.execute(prep).ok,"prepare unsupported hypothesis")
	var prepared: Dictionary = s.snapshot()
	check(s.execute(prep).ok and s.snapshot() == prepared,"idempotent prepare")
	var ready: Dictionary = s.calendar_view().appraisal.deck.ready[0]
	check(ready.argument.evidence_ids.is_empty() and ready.argument.statement_kind == "hypothesis" and ready.current,"not certified fact")
	check(s.calendar_view().appraisal.deck.presented.is_empty(),"prepared not spoken")
	check(reject(s,deck(s,"repeat","prepare","appearance_id","appearance")),"duplicate ready denied")
	check(reject(s,deck(s,"wrong_card","present","appearance_id","forged")),"forged card denied")
	check(reject(s,deck(s,"wrong_item","present","appearance_id","prepare_1","watch_a","W002")),"wrong subject denied")
	check(s.execute(select_card(s,"model","model_id","meridian_12")).ok and s.calendar_view().appraisal.deck.ready[0].current,"unrelated slot edit keeps ready card")
	var speech: Dictionary = deck(s,"say_1","present","appearance_id","prepare_1")
	check(s.execute(speech).ok,"explicit presentation")
	var published: Dictionary = s.calendar_view().appraisal.deck.presented[0].duplicate(true)
	check(published.argument.source_action == "appearance" and published.current_source_action == "model" and published.card_id == "prepare_1","source and current proof")
	var after_speech: Dictionary = s.snapshot()
	check(s.execute(speech).ok and s.snapshot() == after_speech,"idempotent presentation")
	check(s.calendar_view().appraisal.deck.ready.is_empty(),"spoken card removed from ready")
	check(reject(s,deck(s,"again","prepare","appearance_id","model")),"same conjecture cannot be repeated")
	check(s.snapshot().wallets == pre_deck.wallets and s.snapshot().items == pre_deck.items and s.snapshot().game_minutes == pre_deck.game_minutes and s.snapshot().ledger == pre_deck.ledger,"deck free, no trade or price effects")
	check(s.execute(select_card(s,"heavy","appearance_id","heavy_wear")).ok,"new hypothesis")
	check(s.execute(deck(s,"prepare_2","prepare","appearance_id","heavy")).ok,"prepare changed card")
	check(s.execute(cmd(s,"inspect_subject","wear",{"visit_id":"watch_a","item_id":"W001","tool_id":"wear_detail","target":"dial_face"})).ok,"additional observation")
	check(s.execute(cmd(s,"link_subject_evidence","link",{"visit_id":"watch_a","item_id":"W001","slot_id":"appearance_id","evidence_id":"wear"})).ok,"link acquired observation")
	check(not s.calendar_view().appraisal.deck.ready[0].current and reject(s,deck(s,"stale","present","appearance_id","prepare_2")),"changed link invalidates old draft")
	check(s.execute(deck(s,"remove","remove","appearance_id","prepare_2")).ok,"remove stale")
	check(s.execute(deck(s,"prepare_3","prepare","appearance_id","link")).ok,"prepare with evidence")
	check(s.execute(deck(s,"say_2","present","appearance_id","prepare_3")).ok,"new version presented")
	check(s.calendar_view().appraisal.deck.presented[0] == published and s.calendar_view().appraisal.deck.presented[1].argument.evidence_ids == ["wear"],"previous speech immutable")
	check(s.execute(select_card(s,"func","function_id","inoperable")).ok,"function conjecture")
	check(s.execute(cmd(s,"inspect_subject","function_read",{"visit_id":"watch_a","item_id":"W001","tool_id":"function_detail","target":"whole_function"})).ok,"acquire conflicting function fact")
	check(s.execute(cmd(s,"link_subject_evidence","func_link",{"visit_id":"watch_a","item_id":"W001","slot_id":"function_id","evidence_id":"function_read"})).ok,"claim may contradict evidence")
	check(s.execute(deck(s,"func_ready","prepare","function_id","func_link")).ok,"ready function")
	var stale_state: Dictionary = s.snapshot()
	stale_state.items.W001.field_versions.functional = 1
	check(not Deck.current(stale_state,"watch_a","W001",stale_state.calendar.appraisal_decks.watch_a.deck.ready.function_id.argument),"version change invalidates current proof")
	# Use actual committed unrelated edits to compact receipts; no arbitrary state mutation.
	for i: int in range(34):
		check(s.execute(select_card(s,"edit_"+str(i),"model_id","meridian_12a" if i % 2 == 0 else "meridian_12")).ok,"unrelated edit "+str(i))
	check(s.snapshot().receipt_archive.has("func_link") and Receipt.receipt_revision(s.snapshot(),"func_link") > 0,"source archived")
	check(s.calendar_view().appraisal.deck.ready[0].current,"archived source still current")
	var active: Dictionary = s.snapshot()
	var reload: RefCounted = Fixture.fresh()
	check(reload.restore(active) and reload.snapshot() == active,"cold replay with archived source")
	check(reload.calendar_view().appraisal.deck == s.calendar_view().appraisal.deck,"DTO stable on restore")
	var fake: Dictionary = active.duplicate(true)
	fake.calendar.appraisal_decks.watch_a.deck.presented[0].argument.candidate_id = "heavy_wear"
	check(not reload.restore(fake) and reload.snapshot() == active,"tampered presentation refused")
	check(s.execute(deck(s,"say_function","present","function_id","func_ready")).ok,"present archived ready")
	check(s.execute(deck(s,"model_ready","prepare","model_id","edit_33")).ok,"unspoken draft remains")
	check(s.execute(cmd(s,"calendar_decline_visit","decline",{"visit_id":"watch_a"})).ok,"terminal decline")
	check(s.calendar_view().appraisal.is_empty() and s.snapshot().calendar.appraisal_decks.watch_a.deck.ready.is_empty() and s.snapshot().calendar.appraisal_decks.watch_a.deck.presented.size() == 3,"terminal retains spoken records only")
	check(s.execute(cmd(s,"calendar_next_visit","next")).ok and s.calendar_view().appraisal.deck.presented.is_empty(),"different visit isolated")
	check(reject(s,deck(s,"closed","present","model_id","model_ready")),"closed cannot present")
	# Blank deck is never a prerequisite for a trade.
	var purchase: Dictionary = {"visit_id":"watch_b","item_id":"W002","seller":"seller","buyer":"player","currency":"VKC","amount":90,"inventory":"player_grid","x":0,"y":0,"rotated":false}
	check(s.execute(cmd(s,"trade","purchase",purchase)).ok and s.snapshot().wallets.player.VKC == 90 and s.snapshot().ledger.size() == 1,"blank deck actual purchase unchanged")
	var repo := Repo.new("user://zt_rebuild/p2_deck_"+str(Time.get_ticks_usec()))
	check(repo.save_session(s,"p2_deck").ok and repo.load_session(reload,"p2_deck").ok and reload.snapshot() == s.snapshot(),"disk restore")
	print("GATE2_P2_DECK_AUTHORITY: ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
