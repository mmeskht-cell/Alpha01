extends SceneTree
const Fixture = preload("res://tests/fixtures/p2_watch_state.gd")
const PanelScript = preload("res://src/presentation/generic_appraisal_panel.gd")
const SaveRepo = preload("res://src/persistence/save_repository.gd")
var checks: int=0
var failures: int=0

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func cmd(s: RefCounted,id: String,kind: String,p: Dictionary={}) -> Dictionary:
	return {"action_id":id,"expected_revision":s.snapshot().revision,"type":kind,"payload":p}

func act(s: RefCounted,id: String,kind: String,p: Dictionary={}) -> bool:
	return s.execute(cmd(s,id,kind,p)).ok

func reject(s: RefCounted,c: Dictionary) -> bool:
	var before: Dictionary=s.snapshot()
	return not s.execute(c).ok and s.snapshot()==before

func pick(s: RefCounted,id: String,value: String) -> bool:
	return act(s,id,"assess_subject",{"visit_id":"watch_a","item_id":"W001","slot_id":"appearance_id","candidate_id":value})

func deck(s: RefCounted,id: String,op: String,ref_id: String) -> bool:
	return act(s,id,"subject_deck_action",{"visit_id":"watch_a","item_id":"W001","slot_id":"appearance_id","op":op,"ref_id":ref_id})

func offer(s: RefCounted,id: String,amount: int,refs: Array=[]) -> Dictionary:
	return cmd(s,id,"subject_price_offer",{"visit_id":"watch_a","item_id":"W001","currency":"VKC","amount":amount,"presented_ids":refs})

func trade(s: RefCounted,id: String,ref_id: String="",x: int=0) -> Dictionary:
	var p: Dictionary={"visit_id":"watch_a","item_id":"W001","seller":"seller","buyer":"player","currency":"VKC","amount":90,"inventory":"player_grid","x":x,"y":0,"rotated":false}
	if not ref_id.is_empty():
		p["offer_id"]=ref_id
	return cmd(s,id,"trade",p)

func current_offer(s: RefCounted,id: String,amount: int,refs: Array) -> Dictionary:
	var c: Dictionary = offer(s,id,amount,refs)
	c.payload["basis_version"] = "current_public_v1"
	return c

func direct_sheet() -> void:
	var s: RefCounted = Fixture.fresh(true,false,true)
	check(s!=null,"direct sheet fixture")
	if s==null:
		return
	check(act(s,"sheet_admit","calendar_next_visit"),"sheet admit")
	check(pick(s,"sheet_first","heavy_wear") and deck(s,"sheet_say","present_direct","sheet_first"),"first disclosed judgment")
	check(pick(s,"sheet_correct","visible_wear") and deck(s,"sheet_say2","present_direct","sheet_correct"),"public correction")
	check(s.calendar_view().appraisal.deck.public_basis_ids==["sheet_say2"],"only latest judgment is current price basis")
	check(reject(s,current_offer(s,"sheet_stale",90,["sheet_say"])) and reject(s,offer(s,"sheet_legacy_stale",90,["sheet_say"])),"superseded judgment refused for new and live legacy offer")
	check(s.execute(current_offer(s,"sheet_agreed",90,["sheet_say2"])).ok,"current offer accepted")
	var frozen: Dictionary = s.calendar_view().appraisal.price_offer.offers.back().duplicate(true)
	check(act(s,"sheet_model","assess_subject",{"visit_id":"watch_a","item_id":"W001","slot_id":"model_id","candidate_id":"meridian_12"}) and act(s,"sheet_model_say","subject_deck_action",{"visit_id":"watch_a","item_id":"W001","op":"present_direct","slot_id":"model_id","ref_id":"sheet_model"}),"additional disclosure after accepted price")
	check(act(s,"sheet_private","assess_subject",{"visit_id":"watch_a","item_id":"W001","slot_id":"function_id","candidate_id":"inoperable"}),"unpublished private assessment")
	check(deck(s,"sheet_withdraw","withdraw","sheet_say2"),"withdraw after accepted price")
	check(s.calendar_view().appraisal.deck.public_basis_ids==["sheet_model_say"],"withdrawn basis excluded")
	check(reject(s,current_offer(s,"sheet_withdrawn_ref",80,["sheet_say2"])) and reject(s,offer(s,"sheet_old_ref",80,["sheet_say2"])),"withdrawn basis blocked in new and legacy offer payloads")
	check(reject(s,current_offer(s,"sheet_withdraw_event_ref",80,["sheet_withdraw"])),"withdrawal is not a price argument")
	check(s.calendar_view().appraisal.price_offer.offers.back()==frozen,"accepted offer frozen after later disclosure and withdrawal")
	check(s.calendar_item_history("W001").records.is_empty(),"no final sheet before trade")
	check(s.execute(trade(s,"sheet_buy","sheet_agreed")).ok,"actual trade creates sheet")
	var row: Dictionary = s.calendar_item_history("W001").records[0]
	check(row.offer.presentations.size()==1 and row.offer.presentations[0].presentation_id=="sheet_say2","original price basis intact")
	var sheet: Dictionary = row.get("appraisal_sheet",{})
	check(not sheet.is_empty() and sheet.statements.size()==4 and sheet.current_ids==["sheet_model_say"],"final sheet includes all public not private judgments")
	if sheet.is_empty():
		return
	check(sheet.statements[1].corrects_presentation_id=="sheet_say" and sheet.statements[3].withdraws_presentation_id=="sheet_say2" and sheet.amounts.VKC==90 and sheet.transaction_id=="sheet_buy","correction and actual settled price preserved")
	var snapshot: Dictionary = s.snapshot()
	sheet.amounts.VKC=1
	check(s.snapshot()==snapshot and s.calendar_item_history("W001").records[0].appraisal_sheet.amounts.VKC==90,"sheet detached and read only")
	var reload: RefCounted=Fixture.fresh(true,false,true)
	check(reload.restore(snapshot) and reload.calendar_item_history("W001")==s.calendar_item_history("W001"),"sheet deterministic replay")
	var blank: RefCounted=Fixture.fresh(true,false,true)
	check(act(blank,"sheet_blank_admit","calendar_next_visit") and blank.execute(current_offer(blank,"sheet_blank_offer",90,[])).ok and blank.execute(trade(blank,"sheet_blank_buy","sheet_blank_offer")).ok,"blank new mode purchase")
	check(blank.calendar_item_history("W001").records[0].appraisal_sheet.statements.is_empty() and not blank.calendar_item_history("W001").records[0].appraisal_sheet.has("quality_condition"),"empty public sheet without inferred guarantee")

func quality_terms() -> void:
	var s: RefCounted = Fixture.fresh(true,false,true)
	check(s!=null,"quality fixture")
	if s==null:
		return
	check(act(s,"quality_admit","calendar_next_visit"),"quality admit")
	var proposal: Dictionary = current_offer(s,"quality_forged",90,[])
	proposal.payload["quality_evidence_id"]="unseen"
	check(reject(s,proposal),"unobserved quality condition refused")
	check(act(s,"quality_inspect","inspect_subject",{"visit_id":"watch_a","item_id":"W001","tool_id":"function_detail","target":"whole_function"}),"explicit function observation")
	var dto: Dictionary = s.calendar_view().appraisal.price_offer
	check(dto.quality_option.evidence_id=="quality_inspect" and dto.quality_option.observed_value=="serviceable","quality option based on acquired observation")
	check(dto.offers.is_empty() and s.calendar_view().appraisal.deck.presented.is_empty(),"inspection does not create commitment or speech")
	var before: Dictionary = s.snapshot()
	var c: Dictionary = current_offer(s,"quality_offer",90,[])
	c.payload["quality_evidence_id"]="quality_inspect"
	check(s.execute(c).ok,"explicit condition with price")
	var accepted: Dictionary = s.calendar_view().appraisal.price_offer.offers.back()
	check(accepted.accepted and accepted.presentations.is_empty() and accepted.quality_condition==dto.quality_option,"accepted explicit condition independent of cards")
	check(s.snapshot().wallets==before.wallets and s.snapshot().game_minutes==before.game_minutes,"offer no cash or clock effect")
	check(s.calendar_view().appraisal.checkout.quality_condition==dto.quality_option,"checkout reflects consent")
	check(s.execute(trade(s,"quality_purchase","quality_offer")).ok,"actual trade with accepted condition")
	var row: Dictionary = s.calendar_item_history("W001").records[0]
	check(row.appraisal_sheet.quality_condition==dto.quality_option and row.offer.quality_condition==dto.quality_option and row.appraisal_sheet.statements.is_empty(),"historical quality condition separated from hypotheses")
	check(row.appraisal_sheet.observations.size()==1 and row.appraisal_sheet.observations[0].evidence_id=="quality_inspect" and row.offer.observations==row.appraisal_sheet.observations,"quality-only historical observation projected")
	var reload: RefCounted = Fixture.fresh(true,false,true)
	check(reload.restore(s.snapshot()) and reload.calendar_item_history("W001")==s.calendar_item_history("W001"),"quality replay")
	var fake: Dictionary = s.snapshot()
	fake.calendar.appraisal_offers.watch_a[0].quality_condition.observed_value="inoperable"
	check(not reload.restore(fake),"quality tamper refused")

func observed_fact() -> void:
	var s: RefCounted=Fixture.fresh(true,false,true)
	if s==null:
		check(false,"observed fact fixture")
		return
	check(act(s,"fact_admit","calendar_next_visit"),"fact admit")
	var p: Dictionary={"visit_id":"watch_a","item_id":"W001","slot_id":"observed.function_status","op":"present_observation","ref_id":"fact_read"}
	check(reject(s,cmd(s,"fact_unseen","subject_deck_action",p)),"unseen fact cannot disclose")
	check(act(s,"fact_read","inspect_subject",{"visit_id":"watch_a","item_id":"W001","tool_id":"function_detail","target":"whole_function"}),"observed fact acquisition")
	var before: Dictionary=s.snapshot()
	var view: Dictionary=s.calendar_view().appraisal.deck
	check(view.observation_ready.size()==1 and view.direct_ready.is_empty() and view.presented.is_empty(),"observation ready distinct from hypothesis")
	check(act(s,"fact_say","subject_deck_action",p),"explicit fact disclosure")
	var speech: Dictionary=s.calendar_view().appraisal.deck.presented.back()
	check(speech.argument.statement_kind=="observation" and speech.argument.observed_value=="serviceable" and not speech.has("customer_response") and s.snapshot().wallets==before.wallets and s.snapshot().game_minutes==before.game_minutes,"actual observed fact only")
	check(reject(s,cmd(s,"fact_repeat","subject_deck_action",p)),"repeat fact refused")
	var forged: Dictionary=p.duplicate(true)
	forged.slot_id="observed.dial_wear"
	check(reject(s,cmd(s,"fact_wrong","subject_deck_action",forged)),"wrong observation slot refused")
	check(s.execute(current_offer(s,"fact_agreed",90,[])).ok and s.execute(trade(s,"fact_buy","fact_agreed")).ok,"price alone after public fact")
	var row: Dictionary=s.calendar_item_history("W001").records[0]
	check(row.offer.presentations.is_empty() and row.appraisal_sheet.statements.size()==1 and row.appraisal_sheet.observations[0].evidence_id=="fact_read","actual sheet retains disclosed fact independently of price")
	var replay: RefCounted=Fixture.fresh(true,false,true)
	check(replay.restore(s.snapshot()) and replay.snapshot()==s.snapshot(),"fact journal replay")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	direct_sheet()
	quality_terms()
	observed_fact()
	var s: RefCounted=Fixture.fresh(true,false,true)
	var legacy: RefCounted=Fixture.fresh()
	check(s!=null and legacy!=null,"fixtures")
	if s==null or legacy==null:
		quit(1)
		return
	check(reject(s,offer(s,"early",90)),"inactive rejected")
	check(act(s,"admit","calendar_next_visit"),"admit")
	check(s.calendar_view().appraisal.price_offer.asking==90,"existing fixed terms")
	check(reject(s,offer(s,"unknown",90,["future"])),"unknown speech")
	check(pick(s,"wear","heavy_wear") and deck(s,"draft","prepare","wear"),"private card")
	check(reject(s,offer(s,"private",90,["draft"])),"not presented cannot cite")
	check(act(s,"inspect","inspect_subject",{"visit_id":"watch_a","item_id":"W001","tool_id":"wear_detail","target":"dial_face"}),"observe acquired evidence")
	check(act(s,"link","link_subject_evidence",{"visit_id":"watch_a","item_id":"W001","slot_id":"appearance_id","evidence_id":"inspect"}) and deck(s,"draft2","prepare","link"),"refresh private evidence draft")
	check(deck(s,"say","present","draft2"),"disclose card")
	check(s.calendar_item_history("W001").records.is_empty(),"unbought item no transaction history")
	var before: Dictionary=s.snapshot()
	check(reject(s,offer(s,"dup_refs",90,["say","say"])),"duplicate references")
	var low: Dictionary=offer(s,"low",80,["say"])
	check(s.execute(low).ok and not s.calendar_view().appraisal.price_offer.offers[0].accepted,"below fixed price rejected by seller")
	var after_low: Dictionary=s.snapshot()
	check(s.execute(low).ok and s.snapshot()==after_low,"idempotent offer")
	check(reject(s,offer(s,"repeat_low",80,[])),"no repeated amount")
	check(reject(s,trade(s,"bypass")) and reject(s,trade(s,"rejected","low")),"cannot bypass rejected offer")
	check(s.snapshot().wallets==before.wallets and s.snapshot().items==before.items and s.snapshot().game_minutes==before.game_minutes and s.snapshot().ledger==before.ledger,"offer is free and does not trade")
	var frozen: Dictionary=s.calendar_view().appraisal.price_offer.offers[0].duplicate(true)
	check(pick(s,"revise","visible_wear"),"later assessment")
	check(s.calendar_view().appraisal.price_offer.offers[0]==frozen,"immutable offer after edit")
	check(s.execute(offer(s,"agreed",90,["say"])).ok,"fixed price accepted")
	var dto: Dictionary=s.calendar_view().appraisal.price_offer
	check(dto.accepted_offer_id=="agreed" and dto.offers[1].presentations[0]==frozen.presentations[0],"frozen public speech source")
	var checkout: Dictionary=s.calendar_view().appraisal.checkout
	check(checkout.offer_id=="agreed" and checkout.affordable and checkout.balance==180,"accepted offer checkout projection")
	check(checkout.grids.size()==1 and checkout.grids[0].inventory=="player_grid" and checkout.grids[0].options.size()==12,"root player grid only; free cells")
	check(reject(s,trade(s,"bad_id","low")) and reject(s,trade(s,"bad_cell","agreed",9)),"wrong receipt and placement atomic")
	var panel:=PanelScript.new()
	root.add_child(panel)
	panel.configure(s.calendar_view().appraisal,s.snapshot().revision,Callable(),"en",false,"customer")
	check(panel.find_child("price_offer_amount",true,false)!=null and panel.find_child("price_offer_public",true,false)!=null,"price and explicit public refs UI")
	var cell: Button=panel.find_child("place_player_grid_2_1",true,false) as Button
	var confirm: Button=panel.find_child("confirm_checkout",true,false) as Button
	var before_select: Dictionary=s.snapshot()
	check(cell!=null and not cell.disabled and confirm.disabled,"explicit cell before confirm")
	cell.pressed.emit()
	check(not confirm.disabled and s.snapshot()==before_select,"placement is local draft")
	panel.configure(s.calendar_view().appraisal,s.snapshot().revision,Callable(),"en",false,"appraisal")
	check(panel.find_child("price_offer_amount",true,false)==null,"no price controls in appraisal gaze")
	panel.configure(s.calendar_view().appraisal,s.snapshot().revision,Callable(),"ko",false,"customer")
	confirm=panel.find_child("confirm_checkout",true,false) as Button
	check(not confirm.disabled and s.snapshot()==before_select,"selection survives gaze and language")
	panel.queue_free()
	await process_frame
	var accepted: Dictionary=s.snapshot()
	var reload: RefCounted=Fixture.fresh(true,false,true)
	check(reload.restore(accepted) and reload.snapshot()==accepted,"cold replay")
	var fake: Dictionary=accepted.duplicate(true)
	fake.calendar.appraisal_offers.watch_a[0].accepted=true
	check(not reload.restore(fake) and reload.snapshot()==accepted,"tampered offer rejected")
	check(s.execute(trade(s,"purchase","agreed")).ok,"same transfer authority")
	check(s.snapshot().wallets.player.VKC==90 and s.snapshot().ledger.size()==1 and s.snapshot().items.W001.owner_id=="player","actual exact purchase and owner")
	check(s.snapshot().calendar.appraisal_offers.watch_a[0]==frozen and s.calendar_view().appraisal.is_empty(),"terminal retains offer and closes session")
	var after_purchase: Dictionary=s.snapshot()
	var history: Dictionary=s.calendar_item_history("W001")
	check(history.records.size()==1 and history.records[0].event_id=="purchase" and history.records[0].amounts.VKC==90,"single actual ledger trade")
	var linked: Dictionary=history.records[0].offer
	check(linked.offer_id=="agreed" and linked.presentations==frozen.presentations and linked.observations.size()==1,"accepted receipt public evidence and statement snapshot")
	check(linked.observations[0].evidence_id=="inspect" and not linked.observations[0].has("current") and not linked.observations[0].has("dependent_field_versions"),"historical observation not current truth")
	check(s.calendar_view().trade_history.items.size()==1 and s.calendar_item_history("W002").records.is_empty(),"only player traded identity listed")
	linked.amount=1
	check(s.snapshot()==after_purchase and s.calendar_item_history("W001").records[0].offer.amount==90,"detached read-only history")
	check(not history.records[0].has("from") and not history.records[0].has("to"),"no hidden external ownership")
	check(act(s,"next","calendar_next_visit") and act(s,"second_offer","subject_price_offer",{"visit_id":"watch_b","item_id":"W002","currency":"VKC","amount":90,"presented_ids":[]}),"second visit accepted")
	var next_checkout: Dictionary=s.calendar_view().appraisal.checkout
	check(next_checkout.grids[0].options.size()==11 and {"inventory":"player_grid","x":0,"y":0,"rotated":false} not in next_checkout.grids[0].options,"occupied cell excluded")
	var repo:=SaveRepo.new("user://zt_rebuild/p2_price_"+str(Time.get_ticks_usec()))
	check(repo.save_session(s,"price").ok and repo.load_session(reload,"price").ok and reload.snapshot()==s.snapshot(),"disk restore")
	check(reload.calendar_item_history("W001")==s.calendar_item_history("W001"),"history restored from authoritative sources")
	check(act(legacy,"legacy_admit","calendar_next_visit") and legacy.execute(trade(legacy,"legacy_purchase")).ok,"old direct trade unchanged")
	var blank: RefCounted=Fixture.fresh(true,false,true)
	check(act(blank,"blank_admit","calendar_next_visit") and blank.execute(offer(blank,"blank_offer",90)).ok and blank.execute(trade(blank,"blank_buy","blank_offer")).ok,"blank deck purchase")
	print("GATE2_P2_PRICE_OFFER: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
