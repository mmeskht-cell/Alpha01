extends "res://tests/scenarios/b3_f2_regional_market_test.gd"
## New opt-in civilian composite path; all operations use GameSession.
const F3Source=preload("res://src/content/b3_f3_composite_seed.gd")
const F3=preload("res://src/domain/b3_f3_composite_trial.gd")

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

func f3_route()->bool:
	for seed_value:int in range(101,125):
		var src:Dictionary=F3Source.content(seed_value)
		if src.is_empty(): return check(false,"source schedule must exist")
		var s:RefCounted=fresh(src)
		if s==null or not go(s,"alpha_open"): return false
		if not enter(s,F3.BUY): continue
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
		if not enter(s,F3.SUPPLY) or not settle_item(s,F3.SPARE,15) or not f3_close(s): return false
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
		if not enter(s,F3.SELL) or not f3_observe(s,"function_detail"): return false
		check(f3_value(s.alpha_view(),"function_detail")=="serviceable","new actual appraisal sees changed aggregate condition")
		if not settle_item(s,F3.ROOT,100): return false
		var sold:Dictionary=s.snapshot()
		check(sold.items[F3.ROOT].owner_id=="G05" and sold.items[F3.SPARE].owner_id=="G05" and sold.items[F3.BAD].owner_id=="player","only actual attached family transfers")
		check(sold.ledger.back().root_ids==[F3.ROOT] and sold.ledger.back().basis.VKC==90-int(sold.items[F3.BAD].basis.VKC) and s.alpha_item_history(F3.SPARE).records[0].amounts==null,"root sale basis excludes detached loss and child does not inherit total price")
		if not next_open(s): return false
		if F3.RETURN not in s.snapshot().alpha_shop.random_visits.plan: continue
		if not enter(s,F3.RETURN): return check(false,"actual same owner can return the original composite")
		if not f3_observe(s,"function_detail") or not settle_item(s,F3.ROOT,90): return false
		var final:Dictionary=s.snapshot()
		var history:Dictionary=s.alpha_item_history(F3.ROOT)
		check(final.items[F3.ROOT].owner_id=="player" and final.items[F3.SPARE].parent_id==F3.ROOT and final.items[F3.ROOT].provenance_id==purchased.items[F3.ROOT].provenance_id and final.items.size()==purchased.items.size(),"same-ID return without replacement mint")
		check(history.records.size()==3 and history.records[0].amounts.VKC==90 and history.records[1].amounts.VKC==100 and history.records[2].amounts.VKC==70 and history.work_records==old.work_records,"purchase repair sale return chronological lineage")
		check(f3_find_fact(history.prior_offers,"function_detail","inoperable").get("current")==false and f3_find_fact(history.prior_offers,"function_detail","serviceable").get("current")==true,"new facts never rewrite old appraisal")
		check(wallet_total(final.wallets,"VKC")==wallet_total(src.state.wallets,"VKC")-5 and wallet_total(final.wallets,"USD")==wallet_total(src.state.wallets,"USD"),"only actual workshop expense leaves economy")
		var db:=Repo.new("user://zt_rebuild/f3_composite_"+str(Time.get_ticks_usec()))
		var cold:RefCounted=fresh(src)
		check(db.save_session(s,"composite").get("ok",false) and cold!=null and db.load_session(cold,"composite").get("ok",false) and cold.snapshot()==final and cold.alpha_item_history(F3.ROOT)==history,"cold replay preserves physical lineage and appraisal dates")
		return true
	return false

func _initialize()->void:
	var args:=OS.get_cmdline_user_args()
	var part:String=args[0] if args.size()==1 else "all"
	if part not in ["all","scope","route"]: check(false,"unknown F3 part")
	if part in ["all","scope"]: scope_test()
	if part in ["all","route"]: check(f3_route(),"F3 actual composite vertical path reached")
	print("B3_F3_COMPOSITE_PART ",part,": ",checks," checks, ",failures," failures")
	quit(0 if failures==0 and checks>0 else 1)
