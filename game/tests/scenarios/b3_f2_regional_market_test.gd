extends "res://tests/scenarios/b3_f2_battery_market_test.gd"
## Actual finite regional trade paths. Source seeds, commands, save and replay
## are the existing seven-day engine; no simulated cash or copied item IDs.
const HIGH := "alpha_b3_g08_electronics_d7"
const LOW := "alpha_b3_g02_electronics_d7"
const RADIO := "alpha_b3_g04_radio_d6"

func trial(seed_value:int, policy:String)->Dictionary:
	var src:Dictionary = Week.content(seed_value)
	if not src.is_empty(): src.alpha_profile["battery_market"] = policy
	return src

func settle_item(s:RefCounted, item_id:String, price:int)->bool:
	var v:Dictionary = s.alpha_view().active
	var visit:Dictionary = s.snapshot().visits[v.id]
	var dest:String = "player_stock" if visit.buyer=="player" else str(visit.buyer)+"_grid"
	var fit:Dictionary = s.spatial_fit(item_id,dest)
	if not fit.get("ok",false): return false
	var p:Dictionary = trade(v.id,visit.seller,visit.buyer,price,dest,fit.x,fit.y)
	p.item_id = item_id
	p.rotated = fit.rotated
	return go(s,"alpha_price_offer",{"amount":price}) and go(s,"alpha_trade",p) and go(s,"alpha_ack_exit")

func display_item(s:RefCounted, item_id:String)->bool:
	var fit:Dictionary = s.spatial_fit(item_id,"storefront_grid")
	return fit.get("ok",false) and go(s,"alpha_display",{"item_id":item_id,"x":fit.x,"y":fit.y,"rotated":fit.rotated})

func leave(s:RefCounted)->bool:
	return go(s,"alpha_finish_customer") and go(s,"alpha_ack_exit")

func fork_session(src:Dictionary, state:Dictionary)->RefCounted:
	var s:RefCounted = fresh(src)
	if s==null or not s.restore(state): return null
	return s

func electronic_open(src:Dictionary, spend_g02:bool=false)->RefCounted:
	var s:RefCounted = fresh(src)
	if s==null or not go(s,"alpha_open"): return null
	if spend_g02:
		if not enter(s,"visit_g01") or not settle_item(s,"R001",100) or not display_item(s,"R001"): return null
		if not enter(s,"visit_g02_buy") or not settle_item(s,"R001",170): return null
	for day:int in range(2,7):
		if not next_open(s): return null
	if not enter(s,"electronics_buy") or not settle_item(s,"EL06",80) or not display_item(s,"EL06") or not next_open(s): return null
	return s

func quote_pair()->bool:
	for seed_value:int in range(101,125):
		var src:Dictionary = trial(seed_value,"regional_late_v1")
		var late:RefCounted = electronic_open(src)
		if late==null: continue
		var opening:Dictionary = late.snapshot()
		if HIGH not in opening.alpha_shop.random_visits.plan or LOW not in opening.alpha_shop.random_visits.plan: continue
		var regular_src:Dictionary = trial(seed_value,"regional_regular_v1")
		var normal:RefCounted = electronic_open(regular_src)
		if normal==null or HIGH not in normal.snapshot().alpha_shop.random_visits.plan: continue
		var low:RefCounted = fork_session(src,opening)
		if low==null: return check(false,"cold command replay fork")
		check(not late.alpha_view().has("customer_bid_vkc"),"no unopened buyer quote")
		var news:String = late.alpha_view().market_bulletin
		check("항구 · 전자용품" in news and "시장 구역 · 라디오" in news and "거래 자료 부족" in news,"dated regional news separates observed history from missing data")
		var observed:Dictionary = Market.market_history(opening,7)
		check(observed.flows=={"port_electronics":-1} and observed.counts=={"port_electronics":1},"one actual electronics purchase, no other group effect")
		check(normal.snapshot().wallets==opening.wallets and normal.snapshot().items.EL06==opening.items.EL06,"same stock and cash under independent regional supply policies")
		if not enter(late,HIGH) or not enter(low,LOW) or not enter(normal,HIGH): return check(false,"both real buyer appointments and regular comparison")
		var high_bid:int = int(late.alpha_view().get("customer_bid_vkc",0))
		var low_bid:int = int(low.alpha_view().get("customer_bid_vkc",0))
		var regular_bid:int = int(normal.alpha_view().get("customer_bid_vkc",0))
		check(high_bid>0 and high_bid-low_bid==4 and high_bid-regular_bid==8,"same electronics item: actual personality difference and independent supply effect")
		check(late.snapshot().items.EL06==low.snapshot().items.EL06,"same physical item in alternative timelines")
		var store_repo := Repo.new("user://zt_rebuild/f2_regional_"+str(Time.get_ticks_usec()))
		var reloaded:RefCounted = fresh(src)
		if not check(store_repo.save_session(late,"electronics").get("ok",false) and reloaded!=null and store_repo.load_session(reloaded,"electronics").get("ok",false) and reloaded.snapshot()==late.snapshot(),"cold save preserves regional quote and stock"): return false
		for branch:RefCounted in [reloaded,low,normal]:
			var active:Dictionary = branch.alpha_view()
			var actor:String = active.active.actor_id
			var amount:int = int(active.customer_bid_vkc)
			if not settle_item(branch,"EL06",amount): return check(false,"real sale to "+actor)
			var paid:Dictionary = branch.snapshot()
			check(paid.items.EL06.owner_id==actor and paid.ledger.back().basis.VKC==80 and paid.ledger.back().amounts.VKC==amount,"funded resale retains real purchase basis")
			check(paid.wallets[actor].VKC==opening.wallets[actor].VKC-amount and paid.wallets.player.VKC==opening.wallets.player.VKC+amount,"actual payer and shop balances")
			check(wallet_total(paid.wallets,"VKC")==wallet_total(opening.wallets,"VKC") and wallet_total(paid.wallets,"USD")==wallet_total(opening.wallets,"USD") and paid.items.size()==opening.items.size(),"finite economy across branch")
			check(HIGH not in paid.alpha_shop.outcomes or LOW not in paid.alpha_shop.outcomes or paid.alpha_shop.outcomes[HIGH]!="traded" or paid.alpha_shop.outcomes[LOW]!="traded","only one resale of original item")
		return true
	return false

func cross_item_memory()->bool:
	for seed_value:int in range(101,125):
		var src:Dictionary = trial(seed_value,"regional_late_v1")
		var s:RefCounted = fresh(src)
		if s==null or not go(s,"alpha_open") or not next_open(s): continue
		if not enter(s,"battery_buy") or not settle_item(s,"BAT02",40) or not display_item(s,"BAT02"): continue
		if not next_open(s) or not enter(s,"radio3_buy") or not settle_item(s,"R003",40) or not display_item(s,"R003"): continue
		if not enter(s,"radio3_sale"): continue
		var radio:Dictionary = s.snapshot()
		var declined:RefCounted = fork_session(src,radio)
		if declined==null: return check(false,"radio conversation fork")
		var radio_bid:int = int(declined.alpha_view().get("customer_bid_vkc",0))
		if not go(declined,"alpha_price_offer",{"amount":1}) or not leave(declined) or not leave(s): return check(false,"different actual public response")
		if not next_open(declined) or not next_open(s): return check(false,"D4 opening")
		if FOUR not in s.snapshot().alpha_shop.random_visits.plan or FOUR not in declined.snapshot().alpha_shop.random_visits.plan: continue
		if not enter(s,FOUR) or not enter(declined,FOUR): return check(false,"G11 real repeat appointment")
		var plain:Dictionary = s.alpha_view()
		var remembered:Dictionary = declined.alpha_view()
		check(radio_bid>0 and plain.customer_bid_vkc-remembered.customer_bid_vkc==2,"actual radio refusal changes later battery bid")
		check(remembered.npc_context.prior.get("offer",{}).get("response")=="declined" and remembered.npc_context.prior.outcome=="departed","public memory crosses commodity groups")
		check(s.snapshot().wallets==declined.snapshot().wallets and s.snapshot().items==declined.snapshot().items,"refusal does not create money or stock")
		var history:Dictionary = Market.market_history(declined.snapshot(),4)
		check(history.flows=={"port_battery":-1,"market_radio":-1},"radio and battery flow are independently counted")
		var battery_amount:int = int(remembered.customer_bid_vkc)
		if not settle_item(declined,"BAT02",battery_amount): return check(false,"repeat customer's actual battery payment")
		# Another genuine item remains available: sale of BAT02 cannot clone R003.
		check(declined.snapshot().items.R003.owner_id=="player" and declined.snapshot().items.BAT02.owner_id=="G11","cross-item memory preserves both unique item identities")
		return true
	return false

func finite_buyer()->bool:
	for seed_value:int in range(101,125):
		var src:Dictionary = trial(seed_value,"regional_regular_v1")
		var rich:RefCounted = electronic_open(src)
		var spent:RefCounted = electronic_open(src,true)
		if rich==null or spent==null: continue
		var r:Dictionary = rich.snapshot()
		var p:Dictionary = spent.snapshot()
		if LOW not in r.alpha_shop.random_visits.plan or HIGH not in p.alpha_shop.random_visits.plan: continue
		check(p.wallets.G02.VKC==r.wallets.G02.VKC-170 and p.items.R001.owner_id=="G02","earlier actual settlement exhausts a repeat buyer's budget")
		check(not Market.eligible(p,LOW) and LOW not in p.alpha_shop.random_visits.plan,"unfunded future visitor cannot appear")
		check(Market.eligible(p,HIGH) and p.items.EL06.owner_id=="player","another finite customer remains eligible")
		if not enter(spent,HIGH): return check(false,"funded buyer arrives instead")
		var amount:int = int(spent.alpha_view().customer_bid_vkc)
		if not settle_item(spent,"EL06",amount): return check(false,"funded alternative customer settles")
		check(spent.snapshot().items.EL06.owner_id=="G08","real purchase opportunity remains")
		return true
	return false

func _initialize()->void:
	var args:=OS.get_cmdline_user_args()
	var part:String = args[0] if args.size()==1 else "all"
	if part not in ["all","quotes","memory","finite"]: check(false,"unknown regional market part")
	if part in ["all","quotes"]:
		var bad:Dictionary = trial(101,"regional_regular_v1")
		bad.state.visits[LOW].prices.EL06.VKC+=1
		var rejected:=Session.new()
		check(not rejected.initialize(bad.defs,bad.state,false,false,{},bad.alpha_profile),"regional seed rejects altered immutable basis")
		check(quote_pair(),"same-day two-buyer and independent supply branch reached")
	if part in ["all","memory"]: check(cross_item_memory(),"real cross-commodity returning customer path reached")
	if part in ["all","finite"]: check(finite_buyer(),"finite budget branch reached")
	print("B3_F2_REGIONAL_PART ",part,": ",checks," checks, ",failures," failures")
	quit(0 if failures==0 and checks>0 else 1)
