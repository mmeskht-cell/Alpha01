extends RefCounted
## Opt-in seven-day market policy. No wallet, inventory or ledger of its own.
## The regional trial extends the unchanged battery witness using real visit IDs.
const Flow = preload("res://src/domain/regional_market_flow.gd")
const Receipts = preload("res://src/domain/receipt_primitives.gd")
const Clock = preload("res://src/domain/business_clock.gd")
const Cards = preload("res://src/domain/alpha_card_trade.gd")
# Test policy only. A cautious G11 bids below G07 under identical public conditions.
const BUYER_OFFSETS = {"G07":0,"G11":-2}
const BIDS = ["battery_sale","alpha_b3_g11_battery_d4","alpha_b3_g11_battery_d5"]
const SUPPLIER = "week_battery_buy_d3"
const BATTERY := "BAT02"
# Immutable opening quote of this isolated fixture; never compound a frozen quote.
const BID_BASIS := 60
const PROFILES = ["regular_delivery","late_delivery","regional_regular_v1","regional_late_v1"]
# Versioned, isolated fixture policy. No production balance is implied.
# Region and commodity group are separate; two radios share one group.
const ITEM_MARKETS = {"BAT02":"port_battery","EL06":"port_electronics","R001":"market_radio","R003":"market_radio"}
const MARKET_LABELS = {"port_battery":"항구 · 전지","port_electronics":"항구 · 전자용품","market_radio":"시장 구역 · 라디오"}
# item ID, actual buyer, authored day, immutable opening VKC basis
const REGIONAL_BIDS = {
	"radio3_sale":["R003","G11",3,60],
	"alpha_b3_g04_radio_d6":["R003","G04",6,60],
	"electronics_sale":["EL06","G07",6,115],
	"alpha_b3_g08_electronics_d7":["EL06","G08",7,115],
	"alpha_b3_g02_electronics_d7":["EL06","G02",7,115]
}
# Private preferences: conservative / higher-interest buyers. Minimum
# unspent cash applies only to new optional regional bids.
const PERSONAL = {"G02":{"offset":-2,"reserve":5},"G04":{"offset":0,"reserve":5},"G07":{"offset":0,"reserve":5},"G08":{"offset":2,"reserve":15},"G11":{"offset":-2,"reserve":10}}

static func regional(profile:Dictionary)->bool:
	return profile.get("battery_market") in ["regional_regular_v1","regional_late_v1"]

static func bid_rule(profile:Dictionary, visit_id:String)->Array:
	if visit_id in BIDS:
		return [BATTERY,"G07" if visit_id=="battery_sale" else "G11",2 if visit_id=="battery_sale" else (4 if visit_id=="alpha_b3_g11_battery_d4" else 5),BID_BASIS]
	if regional(profile): return REGIONAL_BIDS.get(visit_id,[])
	return []

static func valid_bid_seed(state:Dictionary, id:String, rule:Array)->bool:
	var visit:Dictionary = state.visits.get(id,{})
	var prices:Dictionary = visit.get("prices",{})
	return not visit.is_empty() and state.items.has(rule[0]) and state.wallets.has(rule[1]) and visit.get("buyer")==rule[1] and visit.get("seller")=="player" and prices.size()==1 and prices.get(rule[0])=={"VKC":rule[3],"USD":0} and int(visit.get("opens",-1))==(int(rule[2])-1)*1440 and visit.get("scope",{}).get("kind")=="ordinary" and not visit.get("scope",{}).get("completed",true)

static func scheduled_seed(profile:Dictionary, id:String, rule:Array)->bool:
	if not profile.get("days") is Array or profile.days.size()!=7: return false
	var rows:Variant = profile.days[int(rule[2])-1]
	if not rows is Array: return false
	for row:Variant in rows:
		if row is Dictionary and row.get("id")==id and row.get("actor_id")==rule[1] and row.get("kind")=="regular": return true
	return false

static func seed_valid(state:Dictionary, profile:Dictionary={})->bool:
	for id:String in BIDS:
		if not valid_bid_seed(state,id,bid_rule(profile,id)): return false
	if regional(profile):
		for id:String in REGIONAL_BIDS:
			if not valid_bid_seed(state,id,REGIONAL_BIDS[id]) or not scheduled_seed(profile,id,REGIONAL_BIDS[id]): return false
		for id:String in BIDS:
			if not scheduled_seed(profile,id,bid_rule(profile,id)): return false
	var supplier:Dictionary = state.visits.get(SUPPLIER,{})
	return supplier.get("seller")=="G06" and supplier.get("buyer")=="player" and supplier.get("prices",{}).get("BAT02")=={"VKC":40,"USD":0}

static func shortage(profile:Dictionary, day:int)->bool:
	return profile.get("battery_market") in ["late_delivery","regional_late_v1"] and day in [3,4]

static func market_shortage(profile:Dictionary, market:String, day:int)->bool:
	if market=="port_battery": return shortage(profile,day)
	if profile.get("battery_market")!="regional_late_v1": return false
	return (market=="port_electronics" and day==7) or (market=="market_radio" and day==6)

static func history(state:Dictionary, day:int)->Dictionary:
	var past:Dictionary = market_history(state,day)
	return {"net":int(past.flows.get("port_battery",0)),"customers":past.customers}

static func market_history(state:Dictionary, day:int)->Dictionary:
	var flows:Dictionary = {}
	var counts:Dictionary = {}
	var customers := {}
	var commands:Array = state.alpha_shop.commands
	var seen:Dictionary = {}
	for row:Dictionary in state.ledger:
		var revision := int(row.revision)
		if Clock.day_index(int(row.game_minutes))>=day or revision<1 or revision>commands.size(): continue
		var cmd:Dictionary = commands[revision-1]
		if cmd.type!="alpha_trade" or cmd.action_id!=row.event_id or cmd.payload.get("visit_id")!=row.visit_id: continue
		if seen.has(row.event_id) or "player" not in [row.from,row.to]: continue
		var p:Dictionary = cmd.payload
		if p.get("buyer")!=row.from or p.get("seller")!=row.to or row.root_ids!=[p.get("item_id")]: continue
		var currency:String = str(p.get("currency",""))
		if currency not in ["VKC","USD"]: continue
		var paid:Dictionary = {"VKC":0,"USD":0}
		paid[currency] = p.get("amount",0)
		if row.amounts!=paid: continue
		var visit:Dictionary = state.visits.get(row.visit_id,{})
		if visit.is_empty() or not visit.scope.completed or Clock.day_index(int(visit.opens))!=Clock.day_index(int(row.game_minutes)): continue
		if not Receipts.matches_receipt(state,row.event_id,cmd.type,p,revision): continue
		seen[row.event_id] = true
		var buying:bool = row.from=="player"
		var actor:String = row.to if buying else row.from
		customers[actor] = true
		var market:String = str(ITEM_MARKETS.get(p.item_id,""))
		if not market.is_empty():
			flows[market] = int(flows.get(market,0)) + (-1 if buying else 1)
			counts[market] = int(counts.get(market,0)) + 1
	return {"flows":flows,"counts":counts,"customers":customers}

static func prior_terms(shop:Dictionary, actor:String)->int:
	var adjustment := 0
	for index in range(int(shop.day)-1):
		for visit:Dictionary in shop.profile.days[index]:
			if visit.actor_id!=actor: continue
			var outcome:String = shop.outcomes.get(visit.id,"")
			if outcome in ["commission_delivered","service_delivered"]: adjustment = 2
			elif outcome in ["departed","traded"]:
				var notes:Dictionary = shop.get("appraisal",{}).get("visits",{}).get(visit.id,{})
				var offers:Array = notes.get("offers",[])
				if outcome=="departed" and not offers.is_empty() and offers.back().response=="declined": adjustment = -2
				# Count the standing public record once, even after repeated disclosure.
				if not Cards.public_history(notes).withdrawn_slots.is_empty(): adjustment = -2
	return adjustment

static func open_day(state:Dictionary, rows:Array)->void:
	var a:Dictionary = state.alpha_shop
	var day := int(a.day)
	var past := market_history(state,day)
	var delayed := shortage(a.profile,day)
	for slot:Dictionary in rows:
		if slot.id==SUPPLIER:
			if not state.visits[slot.id].scope.completed:
				state.visits[slot.id].prices.BAT02 = {"VKC":0,"USD":1} if delayed else {"VKC":40,"USD":0}
			continue
		var rule:Array = bid_rule(a.profile,slot.id)
		if rule.is_empty(): continue
		var visit:Dictionary = state.visits[slot.id]
		if visit.scope.completed: continue
		var item_id:String = rule[0]
		var base:int = int(rule[3])
		var market:String = ITEM_MARKETS[item_id]
		var personal:int = int(PERSONAL.get(visit.buyer,{}).get("offset",0)) if regional(a.profile) else int(BUYER_OFFSETS[visit.buyer])
		if past.customers.has(visit.buyer): personal += 2
		personal += prior_terms(a,visit.buyer)
		var premium:int = 8 if market_shortage(a.profile,market,day) else 0
		visit.prices[item_id].VKC = Flow.bounded_quote(base,base+premium,int(past.flows.get(market,0)),3,6,personal)

## Optional regional buyers may preserve a modest cash reserve. A past public
## refusal raises the reserve, not the wallet. No protected contract uses it.
static func eligible(state:Dictionary, visit_id:String)->bool:
	var a:Dictionary = state.alpha_shop
	if not regional(a.profile) or not REGIONAL_BIDS.has(visit_id): return true
	var rule:Array = REGIONAL_BIDS[visit_id]
	var visit:Dictionary = state.visits[visit_id]
	var reserve:int = int(PERSONAL[visit.buyer].reserve) + (5 if prior_terms(a,visit.buyer)<0 else 0)
	return int(state.wallets[visit.buyer].VKC) >= int(visit.prices[rule[0]].VKC)+reserve

## Only an actual active, matching appraisal can disclose a buyer's opening bid.
static func public_bid(state:Dictionary, appraisal:Dictionary)->int:
	var a:Dictionary = state.alpha_shop
	if a.phase!="CUSTOMER_ACTIVE" or appraisal.is_empty() or appraisal.get("we_buy",true): return 0
	var rule:Array = bid_rule(a.profile,a.active)
	if rule.is_empty() or appraisal.get("item_id")!=rule[0]: return 0
	var visit:Dictionary = state.visits[a.active]
	return 0 if visit.scope.completed else int(visit.prices[rule[0]].VKC)

static func bulletin(state:Dictionary)->String:
	var day := int(state.alpha_shop.day)
	if regional(state.alpha_shop.profile):
		var past:Dictionary = market_history(state,day)
		var lines:Array[String] = []
		for market:String in MARKET_LABELS:
			var supply:String = "납품 지연" if market_shortage(state.alpha_shop.profile,market,day) else "정상 공급 공지"
			var count:int = int(past.counts.get(market,0))
			var net:int = int(past.flows.get(market,0))
			var trend:String = "거래 자료 부족" if count==0 else ("순매입" if net<0 else ("순매출" if net>0 else "순거래량 변동 없음"))
			lines.append("%s · %d일차 · 지역 납품 공지: %s\n상점 거래장(전일까지 %d건): %s"%[MARKET_LABELS[market],day,supply,count,trend])
		return "\n".join(lines)
	var arrival := "전지 납품 지연" if shortage(state.alpha_shop.profile,day) else "전지 정상 공급"
	var net := int(history(state,day).net)
	var sales := "누적 순매입" if net<0 else ("누적 순매출" if net>0 else "순거래량 변동 없음")
	return "항구 납품 공지 · %d일차 · %s\n상점 전지 거래장 · 전일까지 %s"%[day,arrival,sales]
