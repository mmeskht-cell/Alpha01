extends "res://tests/scenarios/b3_f2_regional_market_test.gd"
## New opt-in civilian composite path; all operations use GameSession.
const F3Source=preload("res://src/content/b3_f3_composite_seed.gd")
const F3=preload("res://src/domain/b3_f3_composite_trial.gd")
const IntegratedSource=preload("res://src/content/b3_integrated_campaign_seed.gd")
const CampaignPlay=preload("res://tests/fixtures/b3_campaign_play.gd")

func f3_basis(state:Dictionary,ids:Array)->int:
	var sum:int=0
	for id:String in ids: sum+=int(state.items[id].basis.VKC)
	return sum

func f3_observe(s:RefCounted,slot:String)->bool:
	return go(s,"alpha_inspect",{"slot":slot}) and go(s,"alpha_card_toggle",{"slot":slot,"selected":true})

func f3_value(view:Dictionary,slot:String)->String:
	for card:Dictionary in view.appraisal.cards:
		if card.slot==slot: return str(card.value)
	return ""

func f3_find_fact(rows:Array,slot:String,value:String)->Dictionary:
	for row:Dictionary in rows:
		for fact:Dictionary in row.facts:
			if fact.slot==slot and fact.value==value: return fact
	return {}

func f3_work(s:RefCounted,kind:String,p:Dictionary)->bool:
	var before:Dictionary=s.snapshot()
	return check(s.spatial_action_preview(kind,p).get("ok",false) and s.snapshot()==before,"read-only workshop preview "+kind) and go(s,kind,p)

func f3_close(s:RefCounted)->bool:
	return go(s,"alpha_close") and go(s,"alpha_settle")

func f3_open(s:RefCounted)->bool:
	return go(s,"alpha_next_day") and go(s,"alpha_prepare_day") and go(s,"alpha_open")

func scope_test()->void:
	var base:Dictionary=Week.content(101)
	base.alpha_profile["battery_market"]="regional_late_v2"
	var src:Dictionary=F3Source.content(101)
	if not check(not src.is_empty(),"new source fits existing authored days"): return
	var s:RefCounted=fresh(src)
	if not check(s!=null,"new composite seed validates"): return
	check(src.state.wallets==base.state.wallets and src.state.items.size()==base.state.items.size()+4 and src.state.visits.size()==base.state.visits.size()+4,"only finite new trial stock and visits, no cash")
	for id:String in base.state.items: 
		if not check(src.state.items[id]==base.state.items[id],"old item unchanged "+id): return
	for id:String in base.defs:
		if not check(src.defs[id]==base.defs[id],"old definition unchanged "+id): return
	var bad:Dictionary=F3Source.content(101)
	bad.state.visits[F3.SELL].prices[F3.ROOT].VKC+=1
	var rejected:=Session.new()
	check(not rejected.initialize(bad.defs,bad.state,false,false,{},bad.alpha_profile),"tampered trial visit terms rejected")
	check(s.alpha_view().appraisal.is_empty() and s.alpha_item_history(F3.ROOT).records.is_empty(),"unseen item has no fabricated appraisal or history")

func f3_enter(s:RefCounted,integrated:bool,id:String)->bool:
	return CampaignPlay.reach(s,id) if integrated else enter(s,id)

func f3_route(integrated:bool=false)->bool:
	for seed_value:int in range(101,125):
		var src:Dictionary=IntegratedSource.content(seed_value) if integrated else F3Source.content(seed_value)
		if src.is_empty(): return check(false,"source schedule must exist")
		var s:RefCounted=fresh(src)
		if s==null or not go(s,"alpha_open"): return false
		if integrated and not check(s.snapshot().alpha_shop.profile.get("integrated_catalog")==1,"same regular campaign source with legacy components"): return false
		if not f3_enter(s,integrated,F3.BUY): continue
		# No assertions until the necessary deterministic visitor witness
		# is found; failures on the chosen path remain fatal.
		if not f3_observe(s,"identity") or not f3_observe(s,"function_detail") or not settle_item(s,F3.ROOT,70): return check(false,"real inspected composite purchase")
		var purchased:Dictionary=s.snapshot()
		if not f3_close(s): return false
		var split:Dictionary={"actor":"player","root_id":F3.ROOT,"child_id":F3.BAD,"inventory":"player_stock","x":5,"y":0,"rotated":false}
		if not f3_work(s,"spatial_detach",split): return false
		var disassembled:Dictionary=s.snapshot()
		if not f3_open(s): return false
		if F3.SUPPLY not in s.snapshot().alpha_shop.random_visits.plan: continue
		if not f3_enter(s,integrated,F3.SUPPLY) or not settle_item(s,F3.SPARE,15) or not f3_close(s): return false
		var incomplete:Dictionary=s.snapshot()
		check(not s.spatial_action_preview("spatial_restore_item",{"actor":"player","item_id":F3.ROOT}).get("ok",false) and s.snapshot()==incomplete,"incomplete composite cannot be restored")
		check(f3_basis(purchased,[F3.ROOT,"F3R01_A",F3.BAD])==70 and f3_basis(disassembled,[F3.ROOT,"F3R01_A",F3.BAD])==70,"actual allocated purchase basis preserved on detach")
		check(disassembled.items[F3.BAD].parent_id=="" and disassembled.items[F3.BAD].owner_id=="player" and disassembled.items.size()==purchased.items.size(),"detached original identity remains real stock")
		var attach:Dictionary={"actor":"player","root_id":F3.ROOT,"child_id":F3.SPARE}
		if not f3_work(s,"spatial_attach",attach): return false
		var assembled:Dictionary=s.snapshot()
		check(not s.spatial_action_preview("spatial_attach",{"actor":"player","root_id":F3.ROOT,"child_id":F3.BAD}).get("ok",false) and s.snapshot()==assembled,"duplicate compatible tag rejected without mutation")
		if not f3_work(s,"spatial_restore_item",{"actor":"player","item_id":F3.ROOT}): return false
		var restored:Dictionary=s.snapshot()
		check(restored.items[F3.ROOT].functional and restored.items[F3.ROOT].restored and restored.items[F3.SPARE].parent_id==F3.ROOT and not restored.items[F3.BAD].functional,"same root restored with actual replacement and original broken part retained")
		check(restored.wallets.player.VKC==purchased.wallets.player.VKC-20 and f3_basis(restored,[F3.ROOT,"F3R01_A",F3.BAD,F3.SPARE])==90,"actual spare purchase and repair cost capitalized once")
		var old:Dictionary=s.alpha_item_history(F3.ROOT)
		var old_function:Dictionary=f3_find_fact(old.prior_offers,"function_detail","inoperable")
		var old_identity:Dictionary=f3_find_fact(old.prior_offers,"identity",F3.MODEL)
		check(not old_function.is_empty() and old_function.get("current")==false and old_identity.get("current")==true,"original observation retained, only affected evidence stale")
		check(old.work_records.size()==3 and old.work_records[0].expense.VKC==5 and old.work_records[1].related_item_id==F3.SPARE and old.work_records[2].related_item_id==F3.BAD,"actual repair cost and independent part history")
		check(s.alpha_item_history(F3.BAD).work_records.size()==1 and s.alpha_item_history(F3.SPARE).work_records.size()==1 and s.snapshot()==restored,"read-only distinct part histories")
		if not display_item(s,F3.ROOT) or not f3_open(s): return false
		if F3.SELL not in s.snapshot().alpha_shop.random_visits.plan: continue
		if not f3_enter(s,integrated,F3.SELL) or not f3_observe(s,"function_detail"): return false
		check(f3_value(s.alpha_view(),"function_detail")=="serviceable","new actual appraisal sees changed aggregate condition")
		if not settle_item(s,F3.ROOT,100): return false
		var sold:Dictionary=s.snapshot()
		check(sold.items[F3.ROOT].owner_id=="G05" and sold.items[F3.SPARE].owner_id=="G05" and sold.items[F3.BAD].owner_id=="player","only actual attached family transfers")
		check(sold.ledger.back().root_ids==[F3.ROOT] and sold.ledger.back().basis.VKC==90-int(sold.items[F3.BAD].basis.VKC) and s.alpha_item_history(F3.SPARE).records[0].amounts==null,"root sale basis excludes detached loss and child does not inherit total price")
		if not next_open(s): return false
		if F3.RETURN not in s.snapshot().alpha_shop.random_visits.plan: continue
		if not f3_enter(s,integrated,F3.RETURN): return check(false,"actual same owner can return the original composite")
		if not f3_observe(s,"function_detail") or not settle_item(s,F3.ROOT,90): return false
		var final:Dictionary=s.snapshot()
		var history:Dictionary=s.alpha_item_history(F3.ROOT)
		check(final.items[F3.ROOT].owner_id=="player" and final.items[F3.SPARE].parent_id==F3.ROOT and final.items[F3.ROOT].provenance_id==purchased.items[F3.ROOT].provenance_id and final.items.size()==purchased.items.size(),"same-ID return without replacement mint")
		check(history.records.size()==3 and history.records[0].amounts.VKC==90 and history.records[1].amounts.VKC==100 and history.records[2].amounts.VKC==70 and history.work_records==old.work_records,"purchase repair sale return chronological lineage")
		check(f3_find_fact(history.prior_offers,"function_detail","inoperable").get("current")==false and f3_find_fact(history.prior_offers,"function_detail","serviceable").get("current")==true,"new facts never rewrite old appraisal")
		check(wallet_total(final.wallets,"VKC")==wallet_total(src.state.wallets,"VKC")-5 and wallet_total(final.wallets,"USD")==wallet_total(src.state.wallets,"USD"),"only actual workshop expense leaves economy")
		var proposals:Array=history.prior_offers
		check(proposals.size()==3 and proposals[0].amount==70 and proposals[1].amount==100 and proposals[2].amount==90,"actual chronological proposals, not alphabetical visit IDs")
		if proposals.size()==3:
			check(proposals[0].revision<proposals[1].revision and proposals[1].revision<proposals[2].revision,"history order uses genuine receipt revisions")
		var db:=Repo.new("user://zt_rebuild/f3_composite_"+str(Time.get_ticks_usec()))
		var cold:RefCounted=fresh(src)
		var saved:Dictionary=db.save_session(s,"composite")
		check(saved.get("ok",false),"composite A/B disk save: "+str(saved.get("error","ok")))
		if not check(cold!=null,"independent cold source initializes"): return false
		var loaded:Dictionary=db.load_session(cold,"composite")
		check(loaded.get("ok",false),"composite A/B disk restore: "+str(loaded.get("error","ok")))
		check(cold.snapshot()==final,"cold physical state, wallet, ledger and journal unchanged")
		check(cold.alpha_item_history(F3.ROOT)==history,"cold replay preserves physical lineage and appraisal dates")
		var reopened:Dictionary=cold.alpha_item_history(F3.ROOT,F3.RETURN)
		check(reopened.prior_offers.size()==2 and reopened.prior_offers[0].amount==70 and reopened.prior_offers[1].amount==100,"current visit excluded without reordering earlier proposals")
		# Explicitly reverse the insertion order of this dictionary only.
		# Same canonical state, same commands, no injected economic facts.
		var reordered:Dictionary=final.duplicate(true)
		var old_rows:Dictionary=reordered.alpha_shop.appraisal.visits
		var keys:Array=old_rows.keys()
		keys.reverse()
		var reversed_rows:Dictionary={}
		for id:String in keys: reversed_rows[id]=old_rows[id]
		reordered.alpha_shop.appraisal.visits=reversed_rows
		check(cold.restore(reordered) and cold.snapshot()==final and cold.alpha_item_history(F3.ROOT)==history,"dictionary order cannot alter actual appraisal history")
		if integrated:
			print("B3_INTEGRATED_COMPOSITE_WITNESS ",JSON.stringify({"seed":seed_value,"root":F3.ROOT,"replacement":F3.SPARE,"ledger_entries":final.ledger.size(),"work_entries":history.work_records.size()}))
		return true
	return false

func f3_choices()->bool:
	for seed_value:int in range(101,125):
		var src:Dictionary=F3Source.content(seed_value)
		var live:RefCounted=fresh(src)
		if live==null or not go(live,"alpha_open"): return false
		if not enter(live,F3.BUY): continue
		var before:Dictionary=live.snapshot()
		check(live.alpha_view().appraisal.composite_access=="not_requested" and not live.execute(command(live,"alpha_inspect",{"slot":"f3_part_b"})).get("ok",false) and live.snapshot()==before,"no interior observation before consent")
		check(live.alpha_discard_preview(F3.ROOT).is_empty(),"customer stock cannot be discarded")
		if not go(live,"alpha_composite_consent"): return false
		check(live.alpha_view().appraisal.composite_access=="granted" and live.snapshot().items==before.items and live.snapshot().wallets==before.wallets,"consent changes access only")
		if not f3_observe(live,"f3_part_a") or not f3_observe(live,"f3_part_b"): return false
		check(f3_value(live.alpha_view(),"f3_part_a")=="serviceable" and f3_value(live.alpha_view(),"f3_part_b")=="inoperable" and live.snapshot().items==before.items,"separate read-only fictional module observations")
		if not settle_item(live,F3.ROOT,70): return false
		check(live.alpha_discard_preview(F3.ROOT).is_empty(),"daytime disposal unavailable")
		if not f3_close(live): return false
		var purchased:Dictionary=live.snapshot()
		var keep:RefCounted=fork_session(src,purchased)
		var broken:RefCounted=fork_session(src,purchased)
		if keep==null or broken==null: return false
		var whole:Dictionary=live.alpha_discard_preview(F3.ROOT)
		if not check(not whole.is_empty() and whole.payload.confirmed_ids.size()==3 and whole.basis.VKC==70 and live.snapshot()==purchased,"whole-family loss preview is read only"): return false
		var wrong:Dictionary=whole.payload.duplicate(true)
		wrong.confirmed_ids=[F3.ROOT]
		check(not live.execute(command(live,"spatial_discard",wrong)).get("ok",false) and live.snapshot()==purchased,"partial confirmation cannot destroy family")
		var disposal:Dictionary=command(live,"spatial_discard",whole.payload)
		if not live.execute(disposal).get("ok",false): return check(false,"actual whole-family disposal")
		var gone:Dictionary=live.snapshot()
		live.execute(disposal)
		check(live.snapshot()==gone and gone.wallets==purchased.wallets and gone.ledger==purchased.ledger and gone.items.size()==purchased.items.size()-3,"no cash reward or duplicate loss")
		for id:String in whole.payload.confirmed_ids:
			check(gone.tombstones.has(id) and not gone.items.has(id) and gone.tombstones[id].provenance_id==purchased.items[id].provenance_id,"terminal original identity "+id)
		var h:Dictionary=live.alpha_item_history(F3.ROOT)
		check(h.records.size()==1 and h.work_records.size()==1 and h.work_records[0].group_size==3 and h.work_records[0].loss==null,"group loss never repeated as single item cost")
		var split:Dictionary={"actor":"player","root_id":F3.ROOT,"child_id":"F3R01_A","inventory":"player_stock","x":5,"y":0,"rotated":false}
		if not f3_work(keep,"spatial_detach",split): return false
		var remainder:Dictionary=keep.alpha_discard_preview(F3.ROOT)
		if not check(not remainder.is_empty() and remainder.payload.confirmed_ids.size()==2 and int(remainder.basis.VKC)+int(keep.snapshot().items.F3R01_A.basis.VKC)==70,"recovery separates retained cost from written-off cost"): return false
		if not go(keep,"spatial_discard",remainder.payload): return false
		var saved_part:Dictionary=keep.snapshot()
		check(saved_part.items.F3R01_A.owner_id=="player" and saved_part.items.F3R01_A.functional and saved_part.items.F3R01_A.parent_id=="" and saved_part.wallets==gone.wallets and saved_part.items.size()==gone.items.size()+1,"recover real reusable part, not fictional cash")
		check(keep.alpha_item_history("F3R01_A").work_records.size()==1,"retained component has its own history")
		if not display_item(broken,F3.ROOT) or not f3_open(broken) or not next_open(broken): return false
		if F3.SELL not in broken.snapshot().alpha_shop.random_visits.plan: continue
		if not enter(broken,F3.SELL): return false
		check(broken.alpha_view().get("customer_bid_vkc",0)==50,"actual broken-unit buyer quote differs from restored 100")
		if not settle_item(broken,F3.ROOT,50): return false
		check(broken.snapshot().wallets.player.VKC==purchased.wallets.player.VKC+50 and broken.snapshot().items[F3.ROOT].owner_id=="G05","actual unrepaired sale settles lower price")
		if not next_open(broken): return false
		if F3.RETURN not in broken.snapshot().alpha_shop.random_visits.plan: continue
		if not enter(broken,F3.RETURN) or not go(broken,"alpha_composite_consent"): return false
		var denied:Dictionary=broken.snapshot()
		check(broken.alpha_view().appraisal.composite_access=="denied" and not broken.execute(command(broken,"alpha_inspect",{"slot":"f3_part_a"})).get("ok",false) and broken.snapshot()==denied,"returning owner refuses interior access; no previous grant carryover")
		for session:RefCounted in [live,keep]:
			if not f3_open(session) or not next_open(session): return false
			check(F3.SELL not in session.snapshot().alpha_shop.random_visits.plan and not session.snapshot().items.has(F3.ROOT),"disposed item cannot become a later buyer visit")
			if not next_open(session): return false
			check(F3.RETURN not in session.snapshot().alpha_shop.random_visits.plan and not session.snapshot().items.has(F3.ROOT),"disposed ID cannot reenter")
		var db:=Repo.new("user://zt_rebuild/f3_recovery_"+str(Time.get_ticks_usec()))
		var cold:RefCounted=fresh(src)
		check(db.save_session(keep,"recovery").get("ok",false) and cold!=null and db.load_session(cold,"recovery").get("ok",false) and cold.snapshot()==keep.snapshot() and cold.alpha_item_history(F3.ROOT)==keep.alpha_item_history(F3.ROOT),"cold replay retains terminal loss and recovered part")
		return true
	return false

func _initialize()->void:
	var args:=OS.get_cmdline_user_args()
	var part:String=args[0] if args.size()==1 else "all"
	if part not in ["all","scope","route","choices","integrated_route"]: check(false,"unknown F3 part")
	if part in ["all","scope"]: scope_test()
	if part in ["all","route"]: check(f3_route(),"F3 actual composite vertical path reached")
	if part=="integrated_route": check(f3_route(true),"same composite lifecycle in regular integrated campaign")
	if part in ["all","choices"]: check(f3_choices(),"actual consent, recovery and condition-price alternatives reached")
	print("B3_F3_COMPOSITE_PART ",part,": ",checks," checks, ",failures," failures")
	quit(0 if failures==0 and checks>0 else 1)
