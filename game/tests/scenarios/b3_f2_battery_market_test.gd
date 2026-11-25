extends "res://tests/scenarios/alpha_b3_m6_seven_day_real_trade_test.gd"
## Opt-in seven-day market. Every item and wallet comes from the normal spatial seed.
const Week = preload("res://src/content/b3_spatial_week_seed.gd")
const Market = preload("res://src/domain/b3_f2_market.gd")
const FOUR := "alpha_b3_g11_battery_d4"
const FIVE := "alpha_b3_g11_battery_d5"

func enter(s:RefCounted, id:String)->bool:
	while int(s.alpha_view().remaining)>0:
		if not go(s,"alpha_next_customer") or not go(s,"alpha_ack_entry"): return false
		if s.alpha_view().active.id==id: return true
		if not go(s,"alpha_finish_customer") or not go(s,"alpha_ack_exit"): return false
	return false

func next_open(s:RefCounted)->bool:
	return advance(s) and go(s,"alpha_open")

func settle_battery(s:RefCounted, price:int)->bool:
	var v:Dictionary = s.alpha_view().active
	var visit:Dictionary = s.snapshot().visits[v.id]
	var dest:String = "player_stock" if visit.buyer=="player" else str(visit.buyer)+"_grid"
	var fit:Dictionary = s.spatial_fit("BAT02",dest)
	if not fit.get("ok",false): return false
	var p := trade(v.id,visit.seller,visit.buyer,price,dest,fit.x,fit.y)
	p.rotated = fit.rotated
	p.item_id = "BAT02"
	if not go(s,"alpha_price_offer",{"amount":price}): return false
	var cmd := command(s,"alpha_trade",p)
	if not s.execute(cmd).get("ok",false): return false
	var paid:Dictionary = s.snapshot()
	s.execute(cmd)
	return check(s.snapshot()==paid,"duplicate settlement changes nothing") and go(s,"alpha_ack_exit")

func supply_pair()->void:
	var base:Dictionary = Week.content(101)
	var regular := fresh(base)
	if not check(regular!=null,"F1 initializes without market"): return
	check(not regular.alpha_view().has("market_bulletin"),"F1 public view stays isolated")
	var broken := base.duplicate(true)
	broken.alpha_profile["battery_market"] = "late_delivery"
	broken.state.visits[FOUR].prices.BAT02.VKC += 1
	var rejected := Session.new()
	check(not rejected.initialize(broken.defs,broken.state,false,false,{},broken.alpha_profile),"F2 refuses mismatched opening terms")
	var purses:Array = []
	var quotes:Array = []
	for policy:String in ["regular_delivery","late_delivery"]:
		var src := base.duplicate(true)
		src.alpha_profile["battery_market"] = policy
		var s := fresh(src)
		if not check(s!=null and go(s,"alpha_open") and next_open(s) and next_open(s),"same seed through D3"): return
		var state:Dictionary = s.snapshot()
		purses.append(state.wallets.player.duplicate())
		if not check(state.visits.has(Market.SUPPLIER),"real repeat merchant exists"): return
		quotes.append(state.visits[Market.SUPPLIER].prices.BAT02.duplicate())
		check(not s.alpha_view().has("customer_bid_vkc"),"no future customer amount at idle counter")
	check(purses[0]==purses[1] and quotes[0]=={"VKC":40,"USD":0} and quotes[1]=={"VKC":0,"USD":1},"same cash, independent optional supplier terms")

func supplier_checkout(policy:String)->bool:
	for seed_value in range(101,117):
		var src:Dictionary = Week.content(seed_value)
		src.alpha_profile["battery_market"] = policy
		var s := fresh(src)
		if s==null or not go(s,"alpha_open") or not next_open(s) or not next_open(s): return false
		if not enter(s,Market.SUPPLIER): continue
		var state:Dictionary = s.snapshot()
		if policy=="regular_delivery": return settle_battery(s,40)
		var fit:Dictionary = s.spatial_fit("BAT02","player_stock")
		if not fit.get("ok",false): return false
		if not go(s,"alpha_price_offer",{"amount":1}): return false
		var p := trade(Market.SUPPLIER,"G06","player",40,"player_stock",fit.x,fit.y)
		p.item_id = "BAT02"
		p.rotated = fit.rotated
		var offered:Dictionary = s.snapshot()
		var view:Dictionary = s.alpha_view()
		check(state.wallets.player.VKC>=40 and state.wallets.player.USD==0,"VKC-funded player has no USD")
		check(view.appraisal.offers.back().currency=="USD" and view.appraisal.offers.back().response=="declined" and view.appraisal.accepted.is_empty(),"USD offer is unfunded and cannot become an agreement")
		check(not view.currency_terms.trade.has("amount") and not view.has("customer_bid_vkc"),"supplier private price is not projected")
		return view.currency_terms.trade.currency=="USD" and not s.execute(command(s,"alpha_trade",p)).get("ok",false) and s.snapshot()==offered and offered.wallets==state.wallets
	return false

func same_item_path(seed_value:int)->bool:
	var src:Dictionary = Week.content(seed_value)
	src.alpha_profile["battery_market"] = "late_delivery"
	var s := fresh(src)
	if s==null or not go(s,"alpha_open") or not next_open(s): return false
	if not enter(s,"battery_buy"): return false
	var before:Dictionary = s.snapshot()
	if not settle_battery(s,40): return false
	var fit:Dictionary = s.spatial_fit("BAT02","storefront_grid")
	if not fit.get("ok",false) or not go(s,"alpha_display",{"item_id":"BAT02","x":fit.x,"y":fit.y,"rotated":fit.rotated}): return false
	if not next_open(s) or not next_open(s) or not enter(s,FOUR): return false
	var d4:int = s.alpha_view().customer_bid_vkc
	var opening:Dictionary = s.snapshot()
	check(Market.history(opening,4).net==-1,"completed purchase removes one unit of local supply")
	var repeated := opening.duplicate(true)
	repeated.ledger.append(repeated.ledger.back().duplicate(true))
	check(Market.history(repeated,4)==Market.history(opening,4),"duplicate ledger row has no second market effect")
	var wrong_amount := opening.duplicate(true)
	wrong_amount.ledger.back().amounts.VKC += 1
	check(Market.history(wrong_amount,4).net==0,"ledger amount must match signed settlement")
	var wrong_day := opening.duplicate(true)
	wrong_day.ledger.back().game_minutes += 1440
	check(Market.history(wrong_day,4).net==0,"ledger day must match bound visit")
	var reopened := opening.duplicate(true)
	Market.open_day(reopened,reopened.alpha_shop.profile.days[3])
	check(reopened==opening,"opening calculation is idempotent on same day and history")
	var altered := opening.duplicate(true)
	var receipt_id:String = altered.ledger.back().event_id
	altered.receipts.erase(receipt_id)
	altered.receipt_archive.erase(receipt_id)
	check(Market.history(altered,4).net==0,"unsigned ledger copy cannot affect next quote")
	var store_repo := Repo.new("user://zt_rebuild/f2_"+str(Time.get_ticks_usec()))
	if not check(store_repo.save_session(s,"battery").get("ok",false),"save while G11 is at counter"): return false
	var later := fresh(src)
	if not check(later!=null and store_repo.load_session(later,"battery").get("ok",false) and later.snapshot()==s.snapshot(),"cold replay preserves frozen offer"): return false
	if not go(later,"alpha_price_offer",{"amount":1}): return false
	check(later.alpha_view().customer_bid_vkc==d4 and later.alpha_view().appraisal.offers.back().response=="declined","declined proposal does not reprice current visit")
	if not go(later,"alpha_finish_customer") or not go(later,"alpha_ack_exit") or not next_open(later) or not enter(later,FIVE): return false
	var d5:int = later.alpha_view().customer_bid_vkc
	var remembered:Dictionary = later.alpha_view().npc_context.prior
	check(remembered.get("outcome")=="departed" and remembered.get("offer",{}).get("response")=="declined","repeat G11 actually remembers the public D4 refusal")
	check(d4-d5==10,"delivery resumes and G11 remembers declined negotiation once")
	check(d4!=d5 and later.snapshot().items.BAT02==s.snapshot().items.BAT02,"same displayed battery across dates with distinct real offers")
	if not settle_battery(s,d4) or not settle_battery(later,d5): return false
	for branch:RefCounted in [s,later]:
		var state:Dictionary = branch.snapshot()
		var paid:int = state.ledger.back().amounts.VKC
		check(state.items.BAT02.owner_id=="G11" and state.ledger.size()==before.ledger.size()+2,"one purchase and one funded resale per timeline")
		check(state.wallets.G11.VKC==before.wallets.G11.VKC-paid and state.wallets.player.VKC==before.wallets.player.VKC-40+paid,"buyer and shop pay actual prices")
		check(wallet_total(state.wallets,"VKC")==wallet_total(before.wallets,"VKC") and state.items.size()==before.items.size(),"finite cash and stock")
	return true

func _initialize()->void:
	var args := OS.get_cmdline_user_args()
	var part:String = args[0] if args.size()==1 else "all"
	if part not in ["all","supply","regular","late","resale"]:
		check(false,"unknown F2 test part")
	if part in ["all","supply"]: supply_pair()
	if part in ["all","regular"]:
		check(supplier_checkout("regular_delivery"),"G06 accepts actual VKC purchase on D3")
	if part in ["all","late"]:
		check(supplier_checkout("late_delivery"),"same merchant rejects VKC for new USD-only spot trade")
	if part in ["all","resale"]:
		var found := false
		for seed_value in range(101,117):
			if same_item_path(seed_value):
				found = true
				break
		check(found,"real D2 purchase with alternative D4 and D5 funded G11 sales")
	print("B3_F2_MARKET_PART ",part,": ",checks," checks, ",failures," failures")
	quit(0 if failures==0 and checks>0 else 1)
