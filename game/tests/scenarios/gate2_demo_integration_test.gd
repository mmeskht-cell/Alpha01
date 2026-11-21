extends SceneTree
const Seed=preload("res://src/content/demo7_seed.gd")
const Runtime=preload("res://src/application/demo7_runtime.gd")
const CivilianSeed=preload("res://src/content/civilian_candidate_seed.gd")
const ConditionSession=preload("res://src/domain/game_session.gd")
const CheckpointFormat=preload("res://src/persistence/checkpoint_format.gd")
const ValueRules=preload("res://src/domain/value_rules.gd")
var checks:int=0
var failures:int=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func action(r:RefCounted,kind:String,p:Dictionary={})->bool:
	var v:Dictionary=r.view()
	var a:Dictionary=r.submit(kind,p,v.revision)
	if not a.ok or not a.get("persisted",false):
		printerr("DEMO_COMMAND ",kind," ",p," ",a)
		return false
	return true

func _initialize()->void:
	var args:=OS.get_cmdline_user_args()
	var parts:Array[String]=["canonical","civilian","condition_v1","condition_v2","alpha"]
	if not args.is_empty():
		if args.size()!=1 or not parts.has(args[0]):
			printerr("FAIL: unknown demo integration part")
			quit(2)
			return
		parts.assign([args[0]])
	for part:String in parts:
		print("ZT_DEMO_INTEGRATION_PART_BEGIN ",part)
		match part:
			"canonical": _canonical()
			"civilian": _civilian_candidate()
			"condition_v1": _civilian_candidate(true)
			"condition_v2":
				_condition_paths()
				_design_conformance()
			"alpha":
				_alpha_playtest()
		print("ZT_DEMO_INTEGRATION_PART_END ",part," cumulative_checks=",checks," failures=",failures)
		if failures>0:
			quit(1)
			return
	if args.is_empty():
		print("GATE2_DEMO_INTEGRATION: ",checks," checks, ",failures," failures")
	else:
		print("GATE2_DEMO_INTEGRATION_PART ",args[0],": ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)

func _canonical()->void:
	var r:=Runtime.new()
	var dir:String="user://zt_rebuild/demo7/test_"+str(Time.get_ticks_usec())
	check(r.open(dir),"actual packaged content and save adapter: "+r.error)
	if r.error!="" or r.blocked or r.localization==null:
		check(false,"canonical runtime unavailable")
		return
	check(r.view().wallet.VKC==180 and r.view().stock.is_empty() and not r.view().obligations.contracts.is_empty(),"canonical initial state no stock")
	check(action(r,"calendar_accept_contract",{"contract_id":"rad1_first"}),"actual story contract")
	var expected:Array=[225,310,395,135,170,210,260]
	for day:int in range(1,8):
		print("ZT_DEMO_CANONICAL_DAY ",day)
		var seen:int=0
		while r.view().visits.can_next and seen<10:
			seen+=1
			if not action(r,"calendar_next_visit"):
				check(false,"admit day "+str(day))
				return
			var v:Dictionary=r.view()
			var terms:Dictionary=v.visits.terms
			var trade:Dictionary=v.trade
			if not trade.is_empty():
				if not v.get("appraisal",{}).is_empty():
					var subject:Dictionary={"visit_id":trade.visit_id,"item_id":trade.item_id}
					var tool:Dictionary=v.appraisal.tools.wear_detail
					check(action(r,"inspect_subject",subject.merged({"tool_id":"wear_detail","target":tool.target})),"production inspection")
					var evidence:String=r.view().appraisal.evidence[0].evidence_id
					var presented:Array=[]
					if trade.visit_id=="visit_g01":
						check(action(r,"inspect_subject",subject.merged({"tool_id":"casing_detail","target":"additional_casing_evidence"})),"second radio observation")
						check(r.view().minute==15,"authored radio time")
						check(action(r,"subject_price_offer",subject.merged({"currency":"VKC","amount":100,"presented_ids":[]})) and r.view().appraisal.price_offer.accepted_offer_id==null,"unsupported low offer refused")
						check(action(r,"assess_subject",subject.merged({"slot_id":"model_id","candidate_id":"selvar_r18"})) and action(r,"assess_subject",subject.merged({"slot_id":"appearance_id","candidate_id":"heavy_wear"})),"manual initial mistaken radio hypothesis")
						check(action(r,"link_subject_evidence",subject.merged({"slot_id":"appearance_id","evidence_id":evidence})),"link acquired evidence without auto-correcting hypothesis")
						check(action(r,"subject_deck_action",subject.merged({"slot_id":"appearance_id","op":"prepare","ref_id":r.view().appraisal.assessment.source_action})),"prepare radio claim")
						var card:String=r.snapshot().calendar.appraisal_decks.visit_g01.deck.ready.appearance_id.card_id
						check(action(r,"subject_deck_action",subject.merged({"slot_id":"appearance_id","op":"present","ref_id":card})),"present mistaken radio claim")
						var mistaken:Dictionary=r.view().appraisal.deck.presented[0]
						check(mistaken.customer_response.relation=="disagrees" and not mistaken.customer_response.verified,"radio customer counterclaim is not an adjudication")
						var financial_before:Dictionary=r.snapshot()
						check(action(r,"subject_price_offer",subject.merged({"currency":"VKC","amount":105,"presented_ids":[mistaken.presentation_id],"basis_version":"current_public_v1"})),"mistaken claim can support an attempted offer")
						var rejected:Dictionary=r.view().appraisal.price_offer.offers.back()
						check(not rejected.accepted and r.view().appraisal.price_offer.accepted_offer_id==null,"contradictory disclosed wear judgment cannot unlock the existing discount")
						check(r.snapshot().wallets==financial_before.wallets and r.snapshot().items==financial_before.items and r.snapshot().game_minutes==financial_before.game_minutes and r.snapshot().ledger==financial_before.ledger,"rejected offer has no invented penalty or settlement")
						check(action(r,"assess_subject",subject.merged({"slot_id":"appearance_id","candidate_id":"visible_wear"})),"correct hypothesis using acquired evidence")
						check(action(r,"subject_deck_action",subject.merged({"slot_id":"appearance_id","op":"present_direct","ref_id":r.view().appraisal.assessment.source_action})),"disclose corrected judgment")
						var corrected:Dictionary=r.view().appraisal.deck.presented.back()
						check(corrected.get("corrects_presentation_id","")==mistaken.presentation_id and r.view().appraisal.deck.presented[0]==mistaken and not corrected.has("customer_response"),"correction preserves old speech and does not repeat customer beat")
						presented.append(corrected.presentation_id)
						check(r.view().appraisal.deck.public_basis_ids==presented,"public current basis excludes the superseded hypothesis")
					if trade.visit_id=="radio_return":
						check(action(r,"inspect_subject",subject.merged({"tool_id":"function_detail","target":"whole_function_sample"})),"returned radio current inspection")
					check(action(r,"subject_price_offer",subject.merged({"currency":trade.currency,"amount":trade.amount,"presented_ids":presented,"basis_version":"current_public_v1"})),"production offer")
					v=r.view()
					if trade.visit_id=="visit_g01":
						check(v.appraisal.price_offer.offers.size()==3 and v.appraisal.price_offer.offers.back().accepted and int(v.appraisal.price_offer.offers.back().amount)==100 and v.appraisal.price_offer.remaining==0,"corrected supported judgment unlocks original 100 price on final attempt")
				var p:Dictionary=trade.duplicate()
				p.erase("label")
				p.erase("placement")
				p.merge(trade.placement)
				if not v.get("appraisal",{}).is_empty():
					p["offer_id"]=v.appraisal.price_offer.accepted_offer_id
				if not action(r,"trade",p):
					check(false,"settlement "+trade.visit_id)
					return
			else:
				var p:Dictionary={"visit_id":v.visits.active,"job_id":terms.job_id}
				check(action(r,"calendar_accept_service" if terms.kind=="service_offer" else "calendar_deliver_service",p),"service "+v.visits.active)
		check(seen<10,"finite daily visits")
		check(action(r,"calendar_close"),"close "+str(day))
		for work:Dictionary in r.view().work:
			check(action(r,"restore_item",{"actor":"player","item_id":work.id}),"evening restoration")
		check(r.view().wallet.VKC==expected[day-1],"day cash "+str(day)+" actual "+str(r.view().wallet.VKC))
		if day==5:
			check(r.view().obligations.contracts.rad1_first.status=="delivered","actual delivery no medicine simulation")
		if day==6:
			check(r.view().obligations.facts.has("clinic_supply_confirmed"),"actual clinic fact")
		check(action(r,"calendar_morning"),"morning "+str(day))
		if day==2:
			check(r.snapshot().calendar.dormant.has("R001") and not r.snapshot().items.has("R001"),"actual radio dormant")
		if day==5:
			check(r.view().world_news.news.size()==1 and r.view().world_news.news[0].cause_refs.size()==2,"causal clinic news")
		if day==6:
			check(r.snapshot().items.R001.owner_id=="G02" and not r.snapshot().items.R001.functional and r.snapshot().visits.has("radio_return"),"authored return changes live state, not identity")
	check(r.view().complete and r.view().minute==10080 and r.snapshot().items.R001.owner_id=="G08","week boundary and same R001 actual resale")
	check(r.snapshot().ledger.size()==18,"ordinary actual ledger")
	check(r.snapshot().calendar.tracking.R001.refs.size()==4,"retained actual radio trades")
	check(r.snapshot().calendar.services.jobs.job7.status=="complete" and r.snapshot().items.W007S.custodian_id=="player" and r.snapshot().calendar.services.jobs.job7.paid=={"VKC":0,"USD":0} and not r.snapshot().calendar.queue.outcomes.has("pickup7"),"D7 completed custody retained without D8 payout")
	check(r.view().visits.remaining==0 and not r.view().visits.can_next,"no D8 appointment")
	var state:Dictionary=r.snapshot()
	check(r.view().trade_history.items.size()>0,"public history")
	r.close()
	var recovered:=Runtime.new()
	check(recovered.open(dir) and recovered.snapshot()==state,"resume production v4 exact")
	recovered.close()


# Bounded actual content/adapter route: skip optional canonical appointments;
# never edit the canonical state or grant extra player funds.
func _civilian_candidate(condition:bool=false)->void:
	var original:Dictionary=Seed.content()
	var extra:Dictionary=CivilianSeed.content(condition)
	var sale:String="civil_receiver_condition_v1" if condition else "civil_receiver_sale"
	if extra.is_empty():
		check(false,"civilian candidate content")
		return
	check(not original.state.items.has("CR06") and extra.state.wallets.player==original.state.wallets.player and extra.profile.visit_days.d6.size()==original.profile.visit_days.d6.size()+2,"candidate additive and original starting money unchanged")
	var canonical:RefCounted=Seed.fresh()
	var separate:RefCounted=CivilianSeed.fresh(condition)
	if separate==null:
		check(false,"candidate seed validates")
		return
	check(canonical!=null and canonical.snapshot().calendar.binding!=separate.snapshot().calendar.binding and not canonical.restore(separate.snapshot()),"distinct binding refuses cross profile state")
	var directory:String="user://zt_rebuild/demo7/civilian_probe_"+str(Time.get_ticks_usec())
	var r:=Runtime.new()
	if not r.open(directory,true,condition) or r.blocked:
		check(false,"candidate actual adapter opens "+r.error)
		r.close()
		return
	check(r.view().civilian_candidate and r.view().wallet.VKC==180,"candidate runtime marker")
	for day:int in range(1,8):
		print("ZT_DEMO_CIVILIAN_DAY ",day," condition_v1=",condition)
		var count:int=0
		while r.view().visits.can_next and count<12:
			count+=1
			if not action(r,"calendar_next_visit"):
				check(false,"candidate admit day "+str(day))
				r.close()
				return
			var v:Dictionary=r.view()
			var visit:String=v.visits.active
			if visit not in ["civil_receiver_buy","civil_spare_buy",sale]:
				if not action(r,"calendar_decline_visit",{"visit_id":visit}):
					check(false,"candidate decline "+visit)
					r.close()
					return
				continue
			var payload:Dictionary=v.trade.duplicate(true)
			payload.erase("label")
			payload.erase("placement")
			payload.merge(v.trade.placement)
			if visit==sale:
				if condition:
					var before:Dictionary=r.snapshot()
					check(v.condition_quote.tier=="verify_complete" and not v.condition_quote.can_sell and v.trade.amount==55,"no hidden actual condition in stale quote")
					check(not r.submit("trade",payload,v.revision).ok and r.snapshot()==before,"unverified completeness rejects sale atomically")
				for key:String in ["complete","functional","restored"]:
					check(action(r,"observe",{"actor":"player","item_id":"CR06","key":key}),"candidate reinspection "+key)
					if condition:
						var expected:Dictionary={"complete":55,"functional":110,"restored":150}
						check(r.view().condition_quote.can_sell and r.view().trade.amount==expected[key],"actual current evidence price "+key)
				check(r.inventory_appraisal("CR06").quality=="refurbished","candidate functional grade before sale")
				if condition:
					var current:Dictionary=r.snapshot()
					check(not r.submit("trade",payload,r.view().revision).ok and r.snapshot()==current,"stale price cannot settle with current revision")
					payload.amount=r.view().trade.amount
			if not action(r,"trade",payload):
				check(false,"candidate trade "+visit)
				r.close()
				return
			if visit=="civil_receiver_buy":
				check(action(r,"observe",{"actor":"player","item_id":"CR06","key":"functional"}),"candidate root inspect")
				check(action(r,"observe",{"actor":"player","item_id":"CR06_C","key":"functional"}),"candidate component inspect")
		check(count<12,"bounded candidate visits "+str(day))
		if not action(r,"calendar_close"):
			check(false,"candidate close day "+str(day))
			r.close()
			return
		if day==6:
			var layout:Dictionary=r.composition_options("CR06")
			if layout.is_empty() or layout.slots[2].replace.is_empty():
				check(false,"candidate spare compatible and available")
				r.close()
				return
			check(not r.view().work.any(func(row:Dictionary)->bool: return row.id=="CR06"),"known defective component blocks restoration preview")
			var before_work:Dictionary=r.snapshot()
			check(not r.submit("restore_item",{"actor":"player","item_id":"CR06"},r.view().revision).ok and r.snapshot()==before_work,"known defective component rejects actual work atomically")
			check(action(r,"replace_component",layout.slots[2].replace[0]),"candidate exchange")
			check(not r.view().work.any(func(row:Dictionary)->bool: return row.id=="CR06"),"stale function sample cannot advertise work")
			var before_review:Dictionary=r.snapshot()
			check(action(r,"observe",{"actor":"player","item_id":"CR06","key":"functional","owned_review":true}) and r.snapshot().game_minutes==before_review.game_minutes and r.snapshot().wallets==before_review.wallets,"current evening defect review is free")
			check(r.view().work.any(func(row:Dictionary)->bool: return row.id=="CR06" and row.cost=={"VKC":5,"USD":0}),"current defect and visible complete composition advertise conditional work at exact cost")
			check(action(r,"restore_item",{"actor":"player","item_id":"CR06"}),"candidate paid restoration")
			check(not r.view().work.any(func(row:Dictionary)->bool: return row.id=="CR06"),"restoration invalidates pre-work evidence")
			check(r.inventory_appraisal("CR06").basis.VKC==80 and not r.inventory_appraisal("CR06").tests[0].fact.current,"actual family basis and stale observation")
		if not action(r,"calendar_morning"):
			check(false,"candidate morning "+str(day))
			r.close()
			return
	var snapshot:Dictionary=r.snapshot()
	check(r.view().complete and snapshot.items.CR06.owner_id=="G07" and snapshot.items.CR06_C.owner_id=="player" and snapshot.wallets.player.VKC==135,"candidate all seven fees, purchases, restoration, resale, residual part")
	check(not r.item_history("CR06").items.is_empty() and not r.item_history("CM06C").items.is_empty(),"candidate item history")
	r.close()
	var restarted:=Runtime.new()
	check(restarted.open(directory,true,condition) and not restarted.blocked and restarted.snapshot()==snapshot,"candidate checkpoint recovery exact")
	restarted.close()
	var isolated:=Runtime.new()
	check(isolated.open(directory) and not isolated.blocked and isolated.snapshot().revision==0 and not isolated.snapshot().items.has("CR06"),"canonical slot not overwritten by candidate")
	isolated.close()
	if condition:
		var old:=Runtime.new()
		check(old.open(directory,true) and not old.blocked and old.snapshot().revision==0 and old.snapshot().visits.has("civil_receiver_sale"),"old fixed candidate slot isolated")
		old.close()

# Branch the validated D6 checkpoint, not a separate lengthy campaign for
# every alternative. This uses the real session commands and replay.
func condition_command(s:RefCounted,kind:String,p:Dictionary={})->Dictionary:
	var revision:int=s.snapshot().revision
	return s.execute({"action_id":"condition_"+str(revision+1),"expected_revision":revision,"type":kind,"payload":p})

func condition_action(s:RefCounted,kind:String,p:Dictionary={})->bool:
	var result:Dictionary=condition_command(s,kind,p)
	if not result.ok:
		check(false,"condition setup "+kind+" "+str(result.get("error","")))
	return result.ok

func condition_admit(s:RefCounted,id:String)->bool:
	for i:int in range(12):
		if not s.calendar_view().visits.can_next or not condition_action(s,"calendar_next_visit"):
			return false
		var active:String=s.calendar_view().visits.active
		if active==id:
			return true
		if not condition_action(s,"calendar_decline_visit",{"visit_id":active}):
			return false
	return false

func condition_purchase(s:RefCounted)->bool:
	for day:int in range(1,6):
		if not condition_action(s,"calendar_close") or not condition_action(s,"calendar_morning"):
			return false
	if not condition_admit(s,"civil_receiver_buy"):
		check(false,"condition D6 admitted")
		return false
	return condition_action(s,"trade",{"visit_id":"civil_receiver_buy","item_id":"CR06","seller":"G06","buyer":"player","currency":"VKC","amount":70,"inventory":"player_stock","x":0,"y":0,"rotated":false})

func condition_sale(s:RefCounted)->bool:
	if not condition_action(s,"calendar_morning"):
		return false
	return condition_admit(s,"civil_receiver_condition_v2")

func condition_inspect(s:RefCounted,key:String)->bool:
	return condition_action(s,"observe",{"actor":"player","item_id":"CR06","key":key})

func condition_payload(amount:int)->Dictionary:
	return {"visit_id":"civil_receiver_condition_v2","item_id":"CR06","seller":"player","buyer":"G07","currency":"VKC","amount":amount,"inventory":"G07_grid","x":6,"y":4,"rotated":false}

func condition_quote_check(s:RefCounted,tier:String,amount:int,allowed:bool)->void:
	var before:Dictionary=s.snapshot()
	var q:Dictionary=s.calendar_view().get("condition_quote",{})
	check(not q.is_empty() and q.tier==tier and q.amount==amount and q.can_sell==allowed,"v2 public quote "+tier)
	check(s.snapshot()==before,"quote is read only "+tier)

func condition_settle(s:RefCounted,amount:int)->void:
	var before:Dictionary=s.snapshot()
	var wrong:Dictionary=condition_command(s,"trade",condition_payload(amount+1))
	check(not wrong.ok and wrong.error=="condition_quote_changed" and s.snapshot()==before,"forged amount rejected "+str(amount))
	if not condition_action(s,"trade",condition_payload(amount)):
		return
	var after:Dictionary=s.snapshot()
	var event:Dictionary=after.ledger.back()
	check(after.wallets.player.VKC==before.wallets.player.VKC+amount and after.wallets.G07.VKC==before.wallets.G07.VKC-amount and event.amounts.VKC==amount and after.visits.civil_receiver_condition_v2.prices.CR06.VKC==amount,"exact dynamic settlement "+str(amount))
	check(after.items.CR06.owner_id=="G07" and after.items.CR06_C.owner_id=="G07","family transfer "+str(amount))

func _condition_paths()->void:
	var original:RefCounted=CivilianSeed.fresh(true,2)
	if original==null or not condition_purchase(original) or not condition_inspect(original,"complete") or not condition_action(original,"calendar_close"):
		check(false,"v2 branch checkpoint")
		return
	var checkpoint:Dictionary=original.snapshot()
	var old:RefCounted=CivilianSeed.fresh(true,1)
	check(old!=null and old.snapshot().calendar.binding!=checkpoint.calendar.binding and not old.restore(checkpoint),"v1/v2 journals isolated")
	for route:String in ["unverified","inoperable","incomplete"]:
		var s:RefCounted=CivilianSeed.fresh(true,2)
		if s==null or not s.restore(checkpoint):
			check(false,"branch restore "+route)
			continue
		if route=="incomplete":
			var options:Dictionary=s.composition_options("CR06","player_stock")
			if options.is_empty() or options.slots[2].detach.is_empty() or not condition_action(s,"detach",options.slots[2].detach):
				check(false,"incomplete branch detach")
				continue
		if not condition_sale(s):
			check(false,"branch D7 "+route)
			continue
		if route=="incomplete":
			condition_quote_check(s,"verify_complete",40,false)
			check(condition_inspect(s,"complete"),"reinspect incomplete")
			condition_quote_check(s,"incomplete",40,false)
			var before:Dictionary=s.snapshot()
			var rejected:Dictionary=condition_command(s,"trade",condition_payload(40))
			check(not rejected.ok and rejected.error=="condition_quote_changed" and s.snapshot()==before,"incomplete sale rejected atomically")
			check(s.snapshot().items.CR06_C.parent_id.is_empty(),"detached identity retained")
		elif route=="inoperable":
			condition_quote_check(s,"unverified",40,true)
			check(condition_inspect(s,"functional"),"observe actual defect")
			condition_quote_check(s,"inoperable",45,true)
			condition_settle(s,45)
		else:
			condition_quote_check(s,"unverified",40,true)
			condition_settle(s,40)
		var replay:RefCounted=CivilianSeed.fresh(true,2)
		check(replay!=null and replay.restore(s.snapshot()) and replay.snapshot()==s.snapshot(),"branch full replay "+route)
	# Test-only working seed, not a modification of authored content. A complete
	# never-restored item must admit the serviceable tier with actual observations.
	var content:Dictionary=CivilianSeed.content(true,2)
	content.state.items.CR06.functional=true
	content.state.items.CR06_C.functional=true
	var s:=ConditionSession.new()
	if not s.initialize(content.defs,content.state,false,false,content.profile) or not condition_purchase(s) or not condition_inspect(s,"complete") or not condition_action(s,"calendar_close") or not condition_sale(s):
		check(false,"working fixture setup")
		return
	condition_quote_check(s,"unverified",40,true)
	check(condition_inspect(s,"functional"),"working fixture function")
	condition_quote_check(s,"functional",110,true)
	check(condition_inspect(s,"restored"),"working fixture not restored")
	condition_quote_check(s,"serviceable",160,true)
	condition_settle(s,160)
	var replay:=ConditionSession.new()
	check(replay.initialize(content.defs,content.state,false,false,content.profile) and replay.restore(s.snapshot()) and replay.snapshot()==s.snapshot(),"working fixture settlement replay")
	# Affordability is an offer-specific public boolean; no exact buyer wallet.
	var low:Dictionary=CivilianSeed.content(true,2)
	low.state.wallets.G07.VKC=0
	var unfunded:=ConditionSession.new()
	if not unfunded.initialize(low.defs,low.state,false,false,low.profile) or not condition_purchase(unfunded) or not condition_inspect(unfunded,"complete") or not condition_action(unfunded,"calendar_close") or not condition_sale(unfunded):
		check(false,"unfunded fixture setup")
		return
	var q:Dictionary=unfunded.calendar_view().condition_quote
	check(q.can_sell and not q.buyer_can_pay and not q.has("buyer_wallet"),"funding availability only")
	var before:Dictionary=unfunded.snapshot()
	var rejected:Dictionary=condition_command(unfunded,"trade",condition_payload(40))
	check(not rejected.ok and rejected.error=="insufficient_funds" and unfunded.snapshot()==before,"unfunded settlement atomic")
	# The candidate may set a provisional price on a draft, but failure of
	# placement must also roll back that price, all money and all ownership.
	var blocked:RefCounted=CivilianSeed.fresh(true,2)
	if blocked==null or not blocked.restore(checkpoint) or not condition_sale(blocked):
		check(false,"placement branch setup")
		return
	before=blocked.snapshot()
	var bad:Dictionary=condition_payload(40)
	bad.x=9
	bad.y=5
	rejected=condition_command(blocked,"trade",bad)
	check(not rejected.ok and blocked.snapshot()==before,"invalid placement rolls back dynamic quote and ledger")
	condition_settle(blocked,40)

# B policy regression: old empty close is still replayable; new explicit
# choices must be exact and atomic. Use a funded test-only seed, not new prices.
func _design_conformance()->void:
	var c:Dictionary=Seed.content()
	c.state.wallets.player.VKC=500
	var base:=ConditionSession.new()
	if not base.initialize(c.defs,c.state,false,false,c.profile) or not condition_action(base,"calendar_accept_contract",{"contract_id":"rad1_first"}):
		check(false,"explicit contract fixture")
		return
	for day:int in range(1,4):
		if not condition_action(base,"calendar_close",{"contract_choices":{}}) or not condition_action(base,"calendar_morning"):
			return
	var checkpoint:Dictionary=base.snapshot()
	var malformed:Dictionary=condition_command(base,"calendar_close",{"contract_choices":{}})
	check(not malformed.ok and base.snapshot()==checkpoint,"due contract omitted from explicit choice rejected")
	for choice:String in ["pay","default"]:
		var s:=ConditionSession.new()
		if not s.initialize(c.defs,c.state,false,false,c.profile) or not s.restore(checkpoint):
			check(false,"explicit contract checkpoint")
			continue
		check(condition_action(s,"calendar_close",{"contract_choices":{"rad1_first":choice}}),"explicit due close "+choice)
		var state:Dictionary=s.snapshot()
		check(state.wallets.player.VKC==int(checkpoint.wallets.player.VKC)-15-(300 if choice=="pay" else 0) and state.calendar.contracts.rows.rad1_first.status==("paid" if choice=="pay" else "defaulted"),"exact explicit settlement "+choice)
		check(state.calendar.contracts.supplies.rad1_supply_1.status==("paid" if choice=="pay" else "available"),"finite supply "+choice)
		var replay:=ConditionSession.new()
		check(replay.initialize(c.defs,c.state,false,false,c.profile) and replay.restore(state) and replay.snapshot()==state,"explicit close replay "+choice)
	var owned:RefCounted=CivilianSeed.fresh(true,2)
	if owned==null or not condition_purchase(owned):
		check(false,"owned review fixture")
		return
	var before:Dictionary=owned.snapshot()
	var p:Dictionary={"actor":"player","item_id":"CR06","key":"functional","owned_review":true}
	check(condition_action(owned,"observe",p) and owned.snapshot().game_minutes==before.game_minutes and owned.snapshot().wallets==before.wallets,"owned daytime review free")
	var inspected:Dictionary=owned.snapshot()
	check(not condition_command(owned,"observe",p).ok and owned.snapshot()==inspected,"same known review refused")
	if not condition_action(owned,"calendar_close",{"contract_choices":{}}):
		return
	var evening:Dictionary=owned.snapshot()
	p.key="complete"
	var first:Dictionary=owned.execute({"action_id":"zz_b_review","expected_revision":evening.revision,"type":"observe","payload":p})
	check(first.ok and owned.snapshot().game_minutes==evening.game_minutes and owned.snapshot().wallets==evening.wallets,"owned evening review free")
	if not first.ok:
		return
	# Both observations occur at the same frozen minute. Reverse lexical
	# action IDs ensure canonical JSON loads the old observation last.
	var layout:Dictionary=owned.composition_options("CR06","player_stock")
	if layout.is_empty() or layout.slots[2].detach.is_empty() or not condition_action(owned,"detach",layout.slots[2].detach):
		check(false,"same-minute review detach setup")
		return
	var after_detach:Dictionary=owned.snapshot()
	var second:Dictionary=owned.execute({"action_id":"aa_b_review","expected_revision":after_detach.revision,"type":"observe","payload":p})
	check(second.ok and owned.snapshot().game_minutes==evening.game_minutes,"same-minute second review")
	if not second.ok:
		return
	var live:Dictionary=owned.inventory_appraisal("CR06").tests[1].fact
	check(live.current and live.evidence_id=="aa_b_review" and live.observed_value==false,"latest current completeness live")
	# Exercise the exact production v4 checkpoint decoder, including numeric
	# normalization before restore. Raw JSON.parse_string is not a load path.
	var terminal:Dictionary=owned.snapshot()
	var encoded:String=CheckpointFormat.encode("b_review",terminal,[],terminal)
	var decoded:Dictionary=CheckpointFormat.decode(encoded,"b_review",func()->RefCounted: return CivilianSeed.fresh(true,2))
	check(decoded.get("ok",false),"same-minute production checkpoint decode "+str(decoded.get("error","")))
	if not decoded.get("ok",false):
		return
	var ordered:Dictionary=decoded.state
	check(ValueRules.canonical(ordered)==ValueRules.canonical(terminal),"checkpoint preserved entire state")
	var ids:Array=ordered.knowledge.keys()
	check(ids.find("aa_b_review")>=0 and ids.find("zz_b_review")>ids.find("aa_b_review"),"canonical checkpoint reverses observation insertion order")
	var reopened:RefCounted=CivilianSeed.fresh(true,2)
	if reopened==null or not reopened.restore(ordered):
		check(false,"same-minute decoded checkpoint restore")
		return
	var reloaded:Dictionary=reopened.inventory_appraisal("CR06").tests[1].fact
	check(reloaded==live and not reopened.inventory_appraisal("CR06").tests[1].allowed,"current completeness independent of save key order")
	var after_layout:Dictionary=owned.composition_options("CR06","player_stock")
	if after_layout.is_empty() or after_layout.slots[2].attach.is_empty() or not condition_action(owned,"attach",after_layout.slots[2].attach[0]):
		check(false,"restore composition for disposal path")
		return
	var before_discard:Dictionary=owned.snapshot()
	var preview:Dictionary=owned.discard_preview("CR06")
	check(preview.ok and preview.item_ids.size()==4,"whole family preview")
	check(not condition_command(owned,"discard",{"actor":"player","item_id":"CR06","confirmed_ids":["CR06"]}).ok and owned.snapshot()==before_discard,"reject partial disposal family")
	check(condition_action(owned,"discard",{"actor":"player","item_id":"CR06","confirmed_ids":preview.item_ids}),"explicit family disposal")
	var disposed:Dictionary=owned.snapshot()
	check(disposed.wallets==before_discard.wallets and disposed.game_minutes==before_discard.game_minutes and disposed.tombstones.has("CR06") and not disposed.items.has("CR06"),"disposal no cash, actual tombstone")
	var restored:RefCounted=CivilianSeed.fresh(true,2)
	check(restored!=null and restored.restore(disposed) and restored.snapshot()==disposed,"owned observation and disposal replay")
	if not disposed.tombstones.has("CR06") or not condition_action(owned,"calendar_morning"):
		return
	# A destroyed root cannot become a buyer visit or reappear as saleable stock.
	check(not condition_admit(owned,"civil_receiver_condition_v2"),"discarded root cannot admit conditional buyer")
	check(owned.snapshot().tombstones.has("CR06") and not owned.snapshot().items.has("CR06"),"terminal identity preserved while visiting other customers")
	check(condition_action(owned,"calendar_close") and owned.snapshot().calendar.queue.outcomes.get("civil_receiver_condition_v2")=="not_applicable","future inquiry ends without trade or artificial completion")
	var after:Dictionary=owned.snapshot()
	var replay:RefCounted=CivilianSeed.fresh(true,2)
	check(replay!=null and replay.restore(after) and replay.snapshot()==after,"discard and subsequent visit boundary replay")


# The opt-in alpha runs two actual seven-day choices without minting cash,
# changing the canonical fixture, or directly mutating a snapshot.
func _alpha_trade(r:RefCounted)->bool:
	var v:Dictionary=r.view()
	var trade:Dictionary=v.get("trade",{})
	if trade.is_empty() or trade.get("placement",{}).is_empty():
		return false
	var payload:Dictionary=trade.duplicate(true)
	payload.erase("label")
	payload.erase("placement")
	payload.merge(trade.placement)
	if not v.get("appraisal",{}).is_empty():
		var subject:Dictionary={"visit_id":trade.visit_id,"item_id":trade.item_id}
		var chosen:int=125 if trade.visit_id=="visit_g01" else int(trade.amount)
		if not action(r,"subject_price_offer",subject.merged({"currency":trade.currency,"amount":chosen,"presented_ids":[]})):
			return false
		var accepted:Variant=r.view().appraisal.price_offer.get("accepted_offer_id")
		if accepted==null:
			printerr("ALPHA_OFFER_NOT_ACCEPTED ",trade.visit_id)
			return false
		payload["offer_id"]=accepted
		payload["amount"]=chosen
	return action(r,"trade",payload)

func _alpha_playtest()->void:
	var canon:RefCounted=Seed.fresh()
	var isolated:RefCounted=CivilianSeed.fresh(true,3)
	check(canon!=null and isolated!=null and canon.snapshot().calendar.binding!=isolated.snapshot().calendar.binding and not canon.restore(isolated.snapshot()),"alpha isolated from canonical")
	var outcomes:Dictionary={}
	for route:String in ["speculate","repair"]:
		var directory:String="user://zt_rebuild/demo7/alpha_proof_"+route+"_"+str(Time.get_ticks_usec())
		var r:=Runtime.new()
		if not r.open(directory,true,true,3) or r.blocked:
			check(false,"alpha opens "+route+" "+r.error)
			continue
		check(r.view().alpha_playtest and r.view().condition_version==3 and r.view().wallet.VKC==180 and r.view().stock.is_empty(),"alpha fresh isolated save "+route)
		for day:int in range(1,8):
			var count:int=0
			while r.view().visits.can_next and count<14:
				count+=1
				if not action(r,"calendar_next_visit"):
					break
				var v:Dictionary=r.view()
				var visit:String=v.visits.active
				var purchase:bool=visit in ["visit_g01","visit_g02_buy","battery_buy","battery_sale","electronics_buy","electronics_sale"]
				if visit=="alpha_field_tool_buy":
					check(day==6 and v.wallet.VKC==205,"D6 valid-earned cash before competing acquisitions")
					purchase=route=="speculate"
				elif visit=="civil_receiver_buy":
					if route=="speculate":
						check(not v.trade_can_pay and v.wallet.VKC==60,"field tool crowds out receiver purchase")
						var denied:Dictionary=v.trade.duplicate(true)
						denied.erase("label")
						denied.erase("placement")
						denied.merge(v.trade.placement)
						var before:Dictionary=r.snapshot()
						check(not r.submit("trade",denied,v.revision).ok and r.snapshot()==before,"unaffordable receiver is atomic")
					purchase=route=="repair"
				elif visit=="civil_spare_buy":
					purchase=route=="repair"
				elif visit=="alpha_field_tool_sale":
					purchase=route=="speculate"
				elif visit=="civil_receiver_condition_v3":
					if route=="repair":
						for key:String in ["complete","functional","restored"]:
							check(action(r,"observe",{"actor":"player","item_id":"CR06","key":key}),"D7 actual evidence "+key)
						check(r.view().condition_quote.amount==150 and r.view().condition_quote.can_sell,"repaired receiver current quote")
						purchase=route=="repair"
				if purchase:
					if not _alpha_trade(r):
						check(false,"alpha actual settlement "+route+" "+visit)
						break
					if visit=="civil_receiver_buy":
						check(action(r,"observe",{"actor":"player","item_id":"CR06","key":"functional"}),"observed root defect")
						check(action(r,"observe",{"actor":"player","item_id":"CR06_C","key":"functional"}),"observed component defect")
				else:
					if not action(r,"calendar_decline_visit",{"visit_id":visit}):
						check(false,"alpha decline "+visit)
						break
			check(count<14,"bounded alpha queue D"+str(day)+" "+route)
			if not action(r,"calendar_close"):
				check(false,"alpha closing D"+str(day))
				break
			if day==6:
				if route=="speculate":
					check(r.snapshot().items.TL06A.owner_id=="player" and r.snapshot().items.CR06.owner_id=="G06","speculation retains alternative property")
				else:
					var layout:Dictionary=r.composition_options("CR06")
					if not layout.is_empty() and not layout.slots[2].replace.is_empty():
						check(action(r,"replace_component",layout.slots[2].replace[0]),"evening component replacement")
						check(action(r,"observe",{"actor":"player","item_id":"CR06","key":"functional","owned_review":true}),"free owned reinspection")
						check(action(r,"restore_item",{"actor":"player","item_id":"CR06"}),"evening paid restoration")
					else:
						check(false,"compatible physical spare present")
					check(r.snapshot().items.CR06.owner_id=="player" and r.snapshot().items.CM06C.owner_id=="player","repair retains asset and replacement part")
			if not action(r,"calendar_morning"):
				check(false,"alpha morning D"+str(day))
				break
		var final:Dictionary=r.snapshot()
		outcomes[route]=final.wallets.player.VKC
		check(r.view().complete and (final.items.TL06A.owner_id=="G10" if route=="speculate" else final.items.CR06.owner_id=="G07"),"D7 authored buyer receives selected asset "+route)
		check(outcomes[route]==(225 if route=="speculate" else 235),"actual alpha ledger "+route+" cash="+str(outcomes[route]))
		r.close()
		var resumed:=Runtime.new()
		check(resumed.open(directory,true,true,3) and not resumed.blocked and resumed.snapshot()==final,"exact alpha save/reopen "+route)
		resumed.close()
		var old:=Runtime.new()
		check(old.open(directory,true,true,2) and old.snapshot().revision==0 and not old.snapshot().items.has("TL06A"),"v2 saved content isolated from alpha "+route)
		old.close()
	check(outcomes.has("speculate") and outcomes.has("repair") and outcomes.speculate!=outcomes.repair,"actual strategies diverge without fixture replacement")
