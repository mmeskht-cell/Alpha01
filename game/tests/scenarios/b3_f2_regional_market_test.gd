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

func cross_item_memory(recovery:bool=false)->bool:
	for seed_value:int in range(101,125):
		var src:Dictionary = trial(seed_value,"regional_late_v2" if recovery else "regional_late_v1")
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
		if recovery:
			if not next_open(declined): return check(false,"next day after actual recovered relationship")
			var recovered:Dictionary = declined.snapshot()
			check(Market.prior_terms(recovered.alpha_shop,"G11")==0,"later paid battery trade supersedes earlier radio refusal")
			check(Market.market_history(recovered,5).customers.has("G11"),"genuine repeat-customer loyalty remains after recovery")
			check(FIVE not in recovered.alpha_shop.random_visits.plan and not declined.alpha_view().has("customer_bid_vkc"),"recovered relationship cannot create missing stock or expose unopened quote")
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

const TOOL_BUYER := "alpha_b3_g09_tool_d5"
const GEAR_SUPPLY := "week_gear_buy_d5"

func expanded_scope()->void:
	var src:Dictionary = trial(101,"regional_late_v2")
	var s:RefCounted = fresh(src)
	if not check(s!=null,"expanded seed initializes without new stock or wallets"): return
	var initial:Dictionary = s.snapshot()
	var count:int = 0
	for offer:Dictionary in initial.alpha_shop.profile.market_interest.offers:
		var rule:Array = Market.bid_rule(initial.alpha_shop.profile,offer.visit_id)
		if not rule.is_empty() and rule[0]==offer.item_id and rule[1]==offer.actor_id and int(rule[2])==int(offer.day): count+=1
	check(count==12,"all twelve existing M7 conditional demands bound to real commodity and actor")
	check(Market.market_key(initial.alpha_shop.profile,"TL04")=="workshop_tools" and Market.market_key(initial.alpha_shop.profile,"HY05")=="market_hygiene","separate tool and hygiene markets")
	var legacy_src:Dictionary = trial(101,"regional_late_v1")
	var legacy:RefCounted = fresh(legacy_src)
	if not check(legacy!=null,"V1 regional seed remains available"): return
	check(legacy.snapshot().items==initial.items and legacy.snapshot().wallets==initial.wallets and legacy.snapshot().visits==initial.visits,"V2 adds no stock, cash or seeded visits")
	check(Market.bid_rule(initial.alpha_shop.profile,"hygiene_sale").is_empty() and Market.bid_rule(initial.alpha_shop.profile,"visit_g01").is_empty() and Market.bid_rule(initial.alpha_shop.profile,"week_tool_buy_d7").is_empty(),"protected story, first sale and existing conditional FX untouched")
	check(not Market.expanded(legacy_src.alpha_profile) and Market.bid_rule(legacy_src.alpha_profile,TOOL_BUYER).is_empty(),"prior version unaffected by new policy")
	var bad:Dictionary = trial(101,"regional_late_v2")
	bad.state.visits[TOOL_BUYER].prices.TL04.VKC+=1
	var rejected:=Session.new()
	check(not rejected.initialize(bad.defs,bad.state,false,false,{},bad.alpha_profile),"additional market policy rejects tampered seed price")

func complete_tool_week()->bool:
	for seed_value:int in range(101,125):
		var src:Dictionary = trial(seed_value,"regional_late_v2")
		var s:RefCounted = fresh(src)
		if s==null or not go(s,"alpha_open"): continue
		var initial:Dictionary = s.snapshot()
		var ready:bool = true
		for day:int in range(2,5):
			if not next_open(s):
				ready=false
				break
		if not ready or not enter(s,"tool_buy") or not settle_item(s,"TL04",60) or not display_item(s,"TL04") or not next_open(s): continue
		if TOOL_BUYER not in s.snapshot().alpha_shop.random_visits.plan: continue
		var pre:Dictionary = s.snapshot()
		var flows:Dictionary = Market.market_history(pre,5)
		check(flows.flows=={"workshop_tools":-1} and flows.counts=={"workshop_tools":1},"actual tool purchase affects only tool market")
		check("공방 구역 · 공구" in s.alpha_view().market_bulletin and not s.alpha_view().has("customer_bid_vkc"),"regional news exposes past aggregate only")
		if not enter(s,TOOL_BUYER): return check(false,"actual D5 tool buyer arrives")
		var amount:int = int(s.alpha_view().get("customer_bid_vkc",0))
		check(amount>95,"tool shortage and actual earlier purchase change buyer offer")
		if not settle_item(s,"TL04",amount): return check(false,"real new commodity payment")
		var paid:Dictionary = s.snapshot()
		check(paid.items.TL04.owner_id=="G09" and paid.ledger.back().basis.VKC==60 and paid.wallets.player.VKC==initial.wallets.player.VKC-60+amount,"actual item basis, ownership and shop cash")
		if not next_open(s) or not next_open(s) or not advance(s,true): return check(false,"paid V2 week reaches final settlement")
		var final:Dictionary = s.snapshot()
		check(final.alpha_shop.phase=="COMPLETE" and final.alpha_shop.day==7 and final.wallets==paid.wallets and final.items==paid.items and final.ledger==paid.ledger,"seven days finish without phantom settlements")
		var totals:Dictionary = Market.market_history(final,8)
		check(totals.flows=={"workshop_tools":0} and totals.counts=={"workshop_tools":2},"two real tool settlements net to zero")
		check(wallet_total(final.wallets,"VKC")==wallet_total(initial.wallets,"VKC") and wallet_total(final.wallets,"USD")==wallet_total(initial.wallets,"USD") and final.items.size()==initial.items.size(),"full week finite stock and money")
		var store_repo:=Repo.new("user://zt_rebuild/f2_v2_week_"+str(Time.get_ticks_usec()))
		var cold:RefCounted = fresh(src)
		check(store_repo.save_session(s,"v2week").get("ok",false) and cold!=null and store_repo.load_session(cold,"v2week").get("ok",false) and cold.snapshot()==final and cold.alpha_view()==s.alpha_view(),"full week cold save and replay")
		return true
	return false

func expanded_supply()->bool:
	for seed_value:int in range(101,125):
		var sessions:Array = []
		var ready:bool = true
		for policy:String in ["regional_regular_v2","regional_late_v2"]:
			var s:RefCounted = fresh(trial(seed_value,policy))
			if s==null or not go(s,"alpha_open"):
				ready=false
				break
			for day:int in range(2,6):
				if not next_open(s):
					ready=false
					break
			if not ready or not enter(s,GEAR_SUPPLY):
				ready=false
				break
			sessions.append(s)
		if not ready or sessions.size()!=2: continue
		var normal:RefCounted = sessions[0]
		var late:RefCounted = sessions[1]
		var before:Dictionary = normal.snapshot()
		var late_before:Dictionary = late.snapshot()
		var normal_ask:int = int(before.visits[GEAR_SUPPLY].prices.GE03.VKC)
		var late_ask:int = int(late_before.visits[GEAR_SUPPLY].prices.GE03.VKC)
		check(before.wallets==late_before.wallets and before.items==late_before.items and late_ask-normal_ask==8,"same actual seller and goods, independent supply event changes ask")
		check(not late.alpha_view().currency_terms.trade.has("amount") and not late.alpha_view().has("customer_bid_vkc"),"seller private ask never projected as buyer bid")
		if not settle_item(normal,"GE03",normal_ask) or not settle_item(late,"GE03",late_ask): return check(false,"both regional supply branches settle")
		check(normal.snapshot().items.GE03.owner_id=="player" and late.snapshot().items.GE03.owner_id=="player" and normal.snapshot().wallets.player.VKC-late.snapshot().wallets.player.VKC==8,"different actual purchasing cost")
		return true
	return false

## Boundary audit uses a genuine acquired item, not modified live state.
## Mutated snapshots are attempted only through restore(), and must fail.
func authority_audit()->bool:
	for seed_value:int in range(101,125):
		var src:Dictionary = trial(seed_value,"regional_late_v2")
		var s:RefCounted = fresh(src)
		if s==null or not go(s,"alpha_open") or not next_open(s): continue
		if not enter(s,"battery_buy") or not settle_item(s,"BAT02",40) or not display_item(s,"BAT02"): continue
		var purchase:Dictionary = s.snapshot()
		var event_id:String = purchase.ledger.back().event_id
		# Repricing is an authorized public shelf action; it must not
		# fabricate supply pressure or erase the original receipt.
		for n:int in range(34):
			if not go(s,"alpha_reprice_display",{"item_id":"BAT02","amount":60+n,"currency":"VKC"}): return check(false,"real shelf repricing")
		if not next_open(s) or not next_open(s): return check(false,"later market opening")
		if FOUR not in s.snapshot().alpha_shop.random_visits.plan: continue
		if not enter(s,FOUR): return check(false,"real returning buyer")
		var opening:Dictionary = s.snapshot()
		var bid:int = int(s.alpha_view().get("customer_bid_vkc",0))
		check(opening.receipt_archive.has(event_id) and not opening.receipts.has(event_id) and opening.receipts.size()<=Session.MAX_RECEIPTS,"actual receipt compaction retains archived settlement")
		check(Market.market_history(opening,4).flows=={"port_battery":-1} and Market.market_history(opening,4).counts=={"port_battery":1},"archived trade counts once; 34 shelf prices do not count")
		check(opening.wallets==purchase.wallets and opening.items==purchase.items and opening.ledger==purchase.ledger,"repeated repricing cannot alter physical goods or money")
		check(bid>0 and bid==int(opening.visits[FOUR].prices.BAT02.VKC),"only the active real bid is projected")
		var old:Dictionary = opening.alpha_shop.commands[int(purchase.ledger.back().revision)-1]
		s.execute(old)
		check(s.snapshot()==opening,"replayed archived payment cannot execute again")
		var forged:Dictionary = opening.duplicate(true)
		forged.visits[FOUR].prices.BAT02.VKC+=1
		check(not s.restore(forged) and s.snapshot()==opening,"forged live market quote rejected atomically")
		forged=opening.duplicate(true)
		forged.wallets.player.VKC+=1
		check(not s.restore(forged) and s.snapshot()==opening,"forged cash rejected atomically")
		forged=opening.duplicate(true)
		forged.alpha_shop.profile.battery_market="regional_regular_v2"
		check(not s.restore(forged) and s.snapshot()==opening,"supply profile swap rejected")
		var other:RefCounted = fresh(trial(seed_value,"regional_regular_v2"))
		if not check(other!=null,"independent regular profile initializes"): return false
		var other_before:Dictionary = other.snapshot()
		check(not other.restore(opening) and other.snapshot()==other_before,"cold restore rejects another profile's otherwise valid save")
		var fit:Dictionary = s.spatial_fit("BAT02","G11_grid")
		if not fit.get("ok",false): return check(false,"real buyer placement")
		var p:Dictionary = trade(FOUR,"player","G11",bid,"G11_grid",fit.x,fit.y)
		p.item_id="BAT02"
		p.rotated=fit.rotated
		check(not s.execute(command(s,"alpha_trade",p)).get("ok",false) and s.snapshot()==opening,"public bid is not a payment agreement")
		if not go(s,"alpha_price_offer",{"amount":1}): return false
		var refused:Dictionary = s.snapshot()
		check(s.alpha_view().appraisal.offers.back().response=="declined" and s.alpha_view().customer_bid_vkc==bid and refused.wallets==opening.wallets and refused.items==opening.items,"refusal cannot change frozen bid or assets")
		check(not s.execute(command(s,"alpha_price_offer",{"amount":1})).get("ok",false) and s.snapshot()==refused,"duplicate offer is rejected without repricing")
		if not go(s,"alpha_price_offer",{"amount":bid}): return false
		var accepted:Dictionary = s.snapshot()
		check(accepted.wallets==opening.wallets and accepted.items==opening.items and accepted.ledger==opening.ledger,"acceptance remains separate from settlement")
		var wrong:Dictionary = p.duplicate(true)
		wrong.amount+=1
		check(not s.execute(command(s,"alpha_trade",wrong)).get("ok",false) and s.snapshot()==accepted,"altered agreed amount rejected")
		wrong=p.duplicate(true)
		wrong.currency="USD"
		check(not s.execute(command(s,"alpha_trade",wrong)).get("ok",false) and s.snapshot()==accepted,"currency substitution rejected")
		var payment:Dictionary = command(s,"alpha_trade",p)
		if not s.execute(payment).get("ok",false): return check(false,"actual agreed payment")
		var paid:Dictionary = s.snapshot()
		s.execute(payment)
		check(s.snapshot()==paid and paid.items.BAT02.owner_id=="G11" and paid.ledger.size()==opening.ledger.size()+1,"one actual payment and one original item")
		check(wallet_total(paid.wallets,"VKC")==wallet_total(opening.wallets,"VKC") and wallet_total(paid.wallets,"USD")==wallet_total(opening.wallets,"USD"),"actual global balances conserved")
		check(not s.alpha_view().has("customer_bid_vkc"),"completed customer cannot expose a new bid")
		var store_repo:=Repo.new("user://zt_rebuild/f2_audit_"+str(Time.get_ticks_usec()))
		var cold:RefCounted=fresh(src)
		check(store_repo.save_session(s,"audit").get("ok",false) and cold!=null and store_repo.load_session(cold,"audit").get("ok",false) and cold.snapshot()==paid and cold.alpha_view()==s.alpha_view(),"cold A/B save after archived receipt, rejected commands and actual sale")
		return true
	return false

## Real service custody, not a synthetic reputation flag. Compare paid
## completion against unpaid return from the same consent and physical item.
const SERVICE_JOB := "service_w002s"
const SERVICE_RETURN := "alpha_service_g04_return_d3"
const GEAR_BUYER := "alpha_b3_g03_gear_d6"
const RADIO_BUYER := "visit_g02_buy"
const REQUEST_ID := "tool_for_g03"
const COMMISSION_RETURN := "alpha_commission_g03_d4"

func service_radio_day(s:RefCounted, paid:bool)->bool:
	var collected:bool=false
	var bought:bool=false
	while int(s.alpha_view().remaining)>0:
		if not go(s,"alpha_next_customer") or not go(s,"alpha_ack_entry"): return false
		var id:String = s.alpha_view().active.id
		if id==SERVICE_RETURN:
			var action:String = "alpha_service_deliver" if paid else "alpha_service_return_unpaid"
			if not go(s,action,{"job_id":SERVICE_JOB}) or not go(s,"alpha_ack_exit"): return false
			collected=true
		elif id=="radio3_buy":
			if not settle_item(s,"R003",40) or not display_item(s,"R003"): return false
			bought=true
		elif not leave(s): return false
	return collected and bought

func service_memory()->bool:
	for seed_value:int in range(101,125):
		var src:Dictionary = trial(seed_value,"regional_late_v2")
		var paid:RefCounted=fresh(src)
		if paid==null or not go(paid,"alpha_open") or not next_open(paid): continue
		if not enter(paid,"watch_a") or not go(paid,"alpha_service_accept",{"job_id":SERVICE_JOB}) or not leave(paid): continue
		if not go(paid,"alpha_close") or not go(paid,"alpha_settle"): return false
		var agreed:Dictionary=paid.snapshot()
		var unpaid:RefCounted=fork_session(src,agreed)
		if unpaid==null: return false
		if not go(paid,"alpha_service_repair",{"job_id":SERVICE_JOB,"item_id":"W002S"}): return false
		var ready:bool=true
		for session:RefCounted in [paid,unpaid]:
			if not go(session,"alpha_next_day") or not go(session,"alpha_prepare_day") or not go(session,"alpha_open"):
				return false
			if SERVICE_RETURN not in session.snapshot().alpha_shop.random_visits.plan or "radio3_buy" not in session.snapshot().alpha_shop.random_visits.plan:
				ready=false
				break
			if not service_radio_day(session,session==paid): return false
			for day:int in range(4,7):
				if not next_open(session): return false
			if RADIO not in session.snapshot().alpha_shop.random_visits.plan:
				ready=false
				break
			if not enter(session,RADIO): return false
		if not ready: continue
		var a:Dictionary=paid.snapshot()
		var b:Dictionary=unpaid.snapshot()
		var av:Dictionary=paid.alpha_view()
		var bv:Dictionary=unpaid.alpha_view()
		var quote_a:int=int(av.get("customer_bid_vkc",0))
		var quote_b:int=int(bv.get("customer_bid_vkc",0))
		check(agreed.items.W002S.owner_id=="G04" and agreed.items.W002S.custodian_id=="player","shared actual service consent and custody")
		check(a.items.W002S.owner_id=="G04" and a.items.W002S.custodian_id=="G04" and a.items.W002S.functional and not b.items.W002S.functional and b.items.W002S.custodian_id=="G04","same customer object returned with real differing repair outcome")
		check(a.wallets.G04.VKC==b.wallets.G04.VKC-40 and a.wallets.player.VKC==b.wallets.player.VKC+30,"actual fee and ten VKC work cost, no phantom money")
		check(a.alpha_shop.services.settlements.size()==1 and a.alpha_shop.services.settlements[0].paid.VKC==40 and b.alpha_shop.services.settlements.size()==1 and b.alpha_shop.services.settlements[0].paid.VKC==0,"each branch has one actual service settlement")
		check(a.items.R003==b.items.R003 and Market.market_history(a,6)==Market.market_history(b,6),"service fee never masquerades as merchandise flow")
		check(Market.prior_terms(a.alpha_shop,"G04")==2 and Market.prior_terms(b.alpha_shop,"G04")==0 and quote_a>0 and quote_a-quote_b==2,"completed service causes real different later radio bid")
		check(av.npc_context.prior.get("outcome")=="service_delivered","returning customer public conversation reflects paid service")
		if not settle_item(paid,"R003",quote_a) or not settle_item(unpaid,"R003",quote_b): return check(false,"both actual later buyer settlements")
		check(paid.snapshot().items.R003.owner_id=="G04" and unpaid.snapshot().items.R003.owner_id=="G04","one original radio moves to funded customer in each alternative")
		return true
	return false

func commission_memory()->bool:
	var baseline:Dictionary=trial(101,"regional_late_v2")
	var rows:Array=baseline.alpha_profile.days[0]
	var availability:Dictionary={}
	for row:Dictionary in rows: availability[row.id]=true
	# Cheap source-only prefilter for the required D1 order. The actual
	# session still decides admission and performs all transactions.
	for seed_value:int in range(101,125):
		var proposal:Dictionary=Planner.plan(rows,availability,["visit_g01","alpha_marcus_intro","alpha_ian_hygiene_offer_d1"],seed_value,1)
		if not proposal.get("ok",false): continue
		var ordered:Array=ids(proposal.visits)
		if not ("radio_wholesale" in ordered and RADIO_BUYER in ordered) or ordered.find("radio_wholesale")>ordered.find(RADIO_BUYER): continue
		var src:Dictionary=trial(seed_value,"regional_late_v2")
		var paid:RefCounted=fresh(src)
		if paid==null or not go(paid,"alpha_open") or not enter(paid,"visit_g01") or not settle_item(paid,"R001",100) or not display_item(paid,"R001"): continue
		if not enter(paid,"radio_wholesale") or not go(paid,"alpha_commission_accept",{"request_id":REQUEST_ID}) or not leave(paid): continue
		# G09's V2 radio quote (130 basis + flow + preference) and
		# reserve exceed that actor's real 130 VKC budget. Use the
		# funded original G02 D1 sale AFTER accepting G03's order.
		# No wallet top-up or relaxed eligibility.
		if not enter(paid,RADIO_BUYER): continue
		if not settle_item(paid,"R001",170): return check(false,"funded D1 radio resale")
		if not next_open(paid) or not next_open(paid): return check(false,"D3 after funded D1 sale")
		if not enter(paid,"gear_buy") or not settle_item(paid,"GE03",80) or not display_item(paid,"GE03") or not next_open(paid): continue
		if not enter(paid,"tool_buy") or not settle_item(paid,"TL04",60) or not go(paid,"alpha_commission_reserve",{"request_id":REQUEST_ID,"item_id":"TL04"}): continue
		var reserved:Dictionary=paid.snapshot()
		var cancelled:RefCounted=fork_session(src,reserved)
		if cancelled==null: return false
		if not go(cancelled,"alpha_commission_cancel",{"request_id":REQUEST_ID}): return false
		if not enter(paid,COMMISSION_RETURN) or not go(paid,"alpha_commission_deliver",{"request_id":REQUEST_ID}) or not go(paid,"alpha_ack_exit"): return false
		var ready:bool=true
		for session:RefCounted in [paid,cancelled]:
			if not next_open(session) or not next_open(session): return false
			if GEAR_BUYER not in session.snapshot().alpha_shop.random_visits.plan:
				ready=false
				break
			if not enter(session,GEAR_BUYER): return false
		if not ready: continue
		var a:Dictionary=paid.snapshot()
		var b:Dictionary=cancelled.snapshot()
		var av:Dictionary=paid.alpha_view()
		var bv:Dictionary=cancelled.alpha_view()
		var quote_a:int=int(av.get("customer_bid_vkc",0))
		var quote_b:int=int(bv.get("customer_bid_vkc",0))
		check(reserved.items.TL04.owner_id=="player" and reserved.items.TL04.reservation_id==REQUEST_ID,"shared physical commission reservation")
		check(a.items.TL04.owner_id=="G03" and b.items.TL04.owner_id=="player" and b.items.TL04.reservation_id.is_empty(),"paid delivery versus released cancellation")
		check(a.wallets.G03.VKC==b.wallets.G03.VKC-90 and a.wallets.player.VKC==b.wallets.player.VKC+90 and a.ledger.size()==b.ledger.size()+1,"actual contract payment exactly once")
		check(a.alpha_shop.commissions.settlements.size()==1 and b.alpha_shop.commissions.settlements.is_empty(),"cancellation creates no contract revenue")
		check(a.items.GE03==b.items.GE03 and Market.market_history(a,6)==Market.market_history(b,6),"commission stays distinct from ordinary market-flow ledger")
		check(Market.prior_terms(a.alpha_shop,"G03")==2 and Market.prior_terms(b.alpha_shop,"G03")==0 and quote_a>0 and quote_a-quote_b==2,"completed commission changes subsequent actual buyer quote")
		check(av.npc_context.prior.get("outcome")=="commission_delivered","returning customer remembers completed commission")
		if not settle_item(paid,"GE03",quote_a) or not settle_item(cancelled,"GE03",quote_b): return check(false,"both funded later purchase opportunities settle")
		check(paid.snapshot().items.GE03.owner_id=="G03" and cancelled.snapshot().items.GE03.owner_id=="G03","later physical good changes owner once per alternative")
		var store_repo:=Repo.new("user://zt_rebuild/f2_commission_memory_"+str(Time.get_ticks_usec()))
		var cold:RefCounted=fresh(src)
		check(store_repo.save_session(paid,"fulfilled").get("ok",false) and cold!=null and store_repo.load_session(cold,"fulfilled").get("ok",false) and cold.snapshot()==paid.snapshot(),"cold save replays fulfilled order and subsequent trade")
		return true
	return false

func _initialize()->void:
	var args:=OS.get_cmdline_user_args()
	var part:String = args[0] if args.size()==1 else "all"
	if part not in ["all","quotes","memory","finite","recovery","scope","week","supplier","authority","service_memory","commission_memory"]: check(false,"unknown regional market part")
	if part in ["all","quotes"]:
		var bad:Dictionary = trial(101,"regional_regular_v1")
		bad.state.visits[LOW].prices.EL06.VKC+=1
		var rejected:=Session.new()
		check(not rejected.initialize(bad.defs,bad.state,false,false,{},bad.alpha_profile),"regional seed rejects altered immutable basis")
		check(quote_pair(),"same-day two-buyer and independent supply branch reached")
	if part in ["all","memory"]: check(cross_item_memory(),"real cross-commodity returning customer path reached")
	if part in ["all","finite"]: check(finite_buyer(),"finite budget branch reached")
	if part in ["all","recovery"]: check(cross_item_memory(true),"regional V2 relationship recovery branch reached")
	if part in ["all","scope"]: expanded_scope()
	if part in ["all","week"]: check(complete_tool_week(),"expanded paid seven-day route reached")
	if part in ["all","supplier"]: check(expanded_supply(),"expanded actual repeat supplier branches reached")
	if part in ["all","authority"]: check(authority_audit(),"V2 authority and archive audit path reached")
	if part in ["all","service_memory"]: check(service_memory(),"real paid and unpaid service memory branches reached")
	if part in ["all","commission_memory"]: check(commission_memory(),"real fulfilled and cancelled commission memory branches reached")
	print("B3_F2_REGIONAL_PART ",part,": ",checks," checks, ",failures," failures")
	quit(0 if failures==0 and checks>0 else 1)
