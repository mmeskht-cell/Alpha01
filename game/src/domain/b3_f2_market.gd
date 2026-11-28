extends RefCounted
## Opt-in seven-day market policy. No wallet, inventory or ledger of its own.
## The regional trial extends the unchanged battery witness using real visit IDs.
const Flow = preload("res://src/domain/regional_market_flow.gd")
const Receipts = preload("res://src/domain/receipt_primitives.gd")
const Clock = preload("res://src/domain/business_clock.gd")
const Cards = preload("res://src/domain/alpha_card_trade.gd")
const Catalog = preload("res://src/domain/b3_integrated_catalog.gd")
# Test policy only. A cautious G11 bids below G07 under identical public conditions.
const BUYER_OFFSETS = {"G07":0,"G11":-2}
const BIDS = ["battery_sale","alpha_b3_g11_battery_d4","alpha_b3_g11_battery_d5"]
const SUPPLIER = "week_battery_buy_d3"
const BATTERY := "BAT02"
# Immutable opening quote of this isolated fixture; never compound a frozen quote.
const BID_BASIS := 60
const PROFILES = ["regular_delivery","late_delivery","regional_regular_v1","regional_late_v1","regional_regular_v2","regional_late_v2"]
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

# V2 covers the entire authored M7 optional demand catalogue. Story,
# commissioned custody, pawn/recovery and mandatory D1/D5 terms stay fixed.
const EXTRA_MARKETS = {"WAT02":"market_watch","TL04":"workshop_tools","GE03":"workshop_goods","HY05":"market_hygiene"}
const EXTRA_LABELS = {"market_watch":"시장 구역 · 시계","workshop_tools":"공방 구역 · 공구","workshop_goods":"공방 구역 · 일반 장비","market_hygiene":"시장 구역 · 위생용품"}
const EXTRA_BIDS = {
	"alpha_b3_g09_radio_d2":["R001","G09",2,130],
	"alpha_b3_g08_watch_d4":["WAT02","G08",4,140],
	"alpha_b3_g09_tool_d5":["TL04","G09",5,95],
	"alpha_b3_g03_gear_d6":["GE03","G03",6,105],
	"alpha_b3_g03_hygiene_d7":["HY05","G03",7,90],
	"alpha_b3_g08_watch_d6":["WAT02","G08",6,140],
	"alpha_b3_g12_tool_d7":["TL04","G12",7,95]
}
# Only optional, existing repeat supplies, never original fixed contracts.
# Missing authored repeats (actor already scheduled) are not generated.
const REPEAT_ASKS = {
	"week_battery_buy_d5":["BAT02","G06",5,40],
	"week_battery_buy_d7":["BAT02","G06",7,40],
	"week_gear_buy_d5":["GE03","G08",5,80],
	"week_radio3_buy_d6":["R003","G10",6,40],
	"week_tool_buy_d6":["TL04","G01",6,60]
}
const EXTRA_PERSONAL = {"G03":{"offset":0,"reserve":5},"G09":{"offset":1,"reserve":5},"G12":{"offset":-1,"reserve":5}}
const SELLER_OFFSETS = {"G01":0,"G06":1,"G08":2,"G10":-1}

static func expanded(profile:Dictionary)->bool:
	return profile.get("battery_market") in ["regional_regular_v2","regional_late_v2"]

static func regional(profile:Dictionary)->bool:
	return profile.get("battery_market") in ["regional_regular_v1","regional_late_v1"] or expanded(profile)

static func market_key(profile:Dictionary, item_id:String)->String:
	var catalog_market := Catalog.market_key(profile,item_id)
	if not catalog_market.is_empty(): return catalog_market
	if expanded(profile) and EXTRA_MARKETS.has(item_id): return str(EXTRA_MARKETS[item_id])
	return str(ITEM_MARKETS.get(item_id,""))

static func buyer_policy(actor:String)->Dictionary:
	return PERSONAL.get(actor,EXTRA_PERSONAL.get(actor,{}))

static func bid_rule(profile:Dictionary, visit_id:String)->Array:
	if visit_id in BIDS:
		return [BATTERY,"G07" if visit_id=="battery_sale" else "G11",2 if visit_id=="battery_sale" else (4 if visit_id=="alpha_b3_g11_battery_d4" else 5),BID_BASIS]
	if expanded(profile) and EXTRA_BIDS.has(visit_id): return EXTRA_BIDS[visit_id]
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
	if expanded(profile):
		for id:String in EXTRA_BIDS:
			if not valid_bid_seed(state,id,EXTRA_BIDS[id]) or not scheduled_seed(profile,id,EXTRA_BIDS[id]): return false
		for id:String in REPEAT_ASKS:
			var rule:Array = REPEAT_ASKS[id]
			if not state.visits.has(id):
				if scheduled_seed(profile,id,rule): return false
				continue
			var v:Dictionary = state.visits[id]
			if not scheduled_seed(profile,id,rule) or v.seller!=rule[1] or v.buyer!="player" or v.scope.kind!="ordinary" or v.scope.completed or v.prices.size()!=1 or v.prices.get(rule[0])!={"VKC":rule[3],"USD":0} or int(v.opens)!=(int(rule[2])-1)*1440: return false
	var supplier:Dictionary = state.visits.get(SUPPLIER,{})
	return supplier.get("seller")=="G06" and supplier.get("buyer")=="player" and supplier.get("prices",{}).get("BAT02")=={"VKC":40,"USD":0}

static func shortage(profile:Dictionary, day:int)->bool:
	return profile.get("battery_market") in ["late_delivery","regional_late_v1","regional_late_v2"] and day in [3,4]

static func market_shortage(profile:Dictionary, market:String, day:int)->bool:
	if market=="port_battery": return shortage(profile,day)
	if Catalog.enabled(profile) and ((market=="market_food" and day in [3,4]) or (market=="market_medical" and day in [5,6])): return true
	if profile.get("battery_market") not in ["regional_late_v1","regional_late_v2"]: return false
	if expanded(profile) and ((market=="workshop_tools" and day in [5,6]) or (market=="workshop_goods" and day==5) or (market=="market_hygiene" and day==7)): return true
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
		var market:String = market_key(state.alpha_shop.profile,str(p.item_id))
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
				# In the regional policy, a later completed purchase supersedes
				# an earlier refusal. Do not permanently penalize a recovered
				# relationship. Retractions in this encounter still count.
				# V2 only: keep earlier replayable trial profiles unchanged.
				if expanded(shop.profile) and outcome=="traded": adjustment = 0
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
		var catalog_item := Catalog.visit_item(a.profile,slot.id)
		if not catalog_item.is_empty():
			_open_catalog_quote(state,slot,catalog_item,past)
			continue
		if slot.id==SUPPLIER:
			if not state.visits[slot.id].scope.completed:
				state.visits[slot.id].prices.BAT02 = {"VKC":0,"USD":1} if delayed else {"VKC":40,"USD":0}
			continue
		if expanded(a.profile) and REPEAT_ASKS.has(slot.id):
			var ask:Array = REPEAT_ASKS[slot.id]
			var seller_visit:Dictionary = state.visits[slot.id]
			if seller_visit.scope.completed: continue
			var ask_market:String = market_key(a.profile,ask[0])
			var ask_base:int = int(ask[3])
			var seller:String = str(ask[1])
			var seller_delta:int = int(SELLER_OFFSETS[seller]) - (2 if past.customers.has(seller) else 0) - prior_terms(a,seller)
			var ask_premium:int = 8 if market_shortage(a.profile,ask_market,day) else 0
			seller_visit.prices[ask[0]].VKC = Flow.bounded_quote(ask_base,ask_base+ask_premium,int(past.flows.get(ask_market,0)),3,6,seller_delta)
			continue
		var rule:Array = bid_rule(a.profile,slot.id)
		if rule.is_empty(): continue
		var visit:Dictionary = state.visits[slot.id]
		if visit.scope.completed: continue
		var item_id:String = rule[0]
		var base:int = int(rule[3])
		var market:String = market_key(a.profile,item_id)
		var personal:int = int(buyer_policy(visit.buyer).get("offset",0)) if regional(a.profile) else int(BUYER_OFFSETS[visit.buyer])
		if past.customers.has(visit.buyer): personal += 2
		personal += prior_terms(a,visit.buyer)
		var premium:int = 8 if market_shortage(a.profile,market,day) else 0
		visit.prices[item_id].VKC = Flow.bounded_quote(base,base+premium,int(past.flows.get(market,0)),3,6,personal)

static func _open_catalog_quote(state: Dictionary,slot: Dictionary,item_id: String,past: Dictionary) -> void:
	var shop: Dictionary = state.alpha_shop
	var visit: Dictionary = state.visits[slot.id]
	if visit.scope.completed: return
	var base := Catalog.price_basis(shop.profile,slot.id)
	var market := market_key(shop.profile,item_id)
	var buying: bool = visit.buyer=="player"
	var actor: String = slot.actor_id
	var history := prior_terms(shop,actor)
	var repeat_customer: bool = past.customers.has(actor)
	var personal := int(SELLER_OFFSETS.get(actor,0))-history-(1 if repeat_customer else 0) if buying else int(buyer_policy(actor).get("offset",0))+history+(1 if repeat_customer else 0)
	var premium := maxi(1,roundi(base*0.10)) if market_shortage(shop.profile,market,int(shop.day)) else 0
	visit.prices[item_id].VKC = Flow.bounded_quote(base,base+premium,int(past.flows.get(market,0)),1,3,personal)

## Optional regional buyers may preserve a modest cash reserve. A past public
## refusal raises the reserve, not the wallet. No protected contract uses it.
static func eligible(state:Dictionary, visit_id:String)->bool:
	if not Catalog.retry_open(state,visit_id): return false
	var a:Dictionary = state.alpha_shop
	var item_id := Catalog.visit_item(a.profile,visit_id)
	if not item_id.is_empty() and visit_id.ends_with("_sale"):
		var sale: Dictionary = state.visits[visit_id]
		var minimum_cash := Catalog.BUYER_RESERVE + (5 if prior_terms(a,sale.buyer)<0 else 0)
		return int(state.wallets[sale.buyer].VKC)>=int(sale.prices[item_id].VKC)+minimum_cash
	if not regional(a.profile) or (not REGIONAL_BIDS.has(visit_id) and not (expanded(a.profile) and EXTRA_BIDS.has(visit_id))): return true
	var rule:Array = bid_rule(a.profile,visit_id)
	var visit:Dictionary = state.visits[visit_id]
	var reserve:int = int(buyer_policy(visit.buyer).reserve) + (5 if prior_terms(a,visit.buyer)<0 else 0)
	return int(state.wallets[visit.buyer].VKC) >= int(visit.prices[rule[0]].VKC)+reserve

## Only an actual active, matching appraisal can disclose a buyer's opening bid.
static func public_bid(state:Dictionary, appraisal:Dictionary)->int:
	var a:Dictionary = state.alpha_shop
	if a.phase!="CUSTOMER_ACTIVE" or appraisal.is_empty() or appraisal.get("we_buy",true): return 0
	var item_id := Catalog.visit_item(a.profile,a.active)
	if not item_id.is_empty() and appraisal.get("item_id")==item_id:
		var catalog_visit: Dictionary = state.visits[a.active]
		return 0 if catalog_visit.scope.completed else int(catalog_visit.prices[item_id].VKC)
	var rule:Array = bid_rule(a.profile,a.active)
	if rule.is_empty() or appraisal.get("item_id")!=rule[0]: return 0
	var visit:Dictionary = state.visits[a.active]
	return 0 if visit.scope.completed else int(visit.prices[rule[0]].VKC)

static func bulletin(state:Dictionary)->String:
	var day := int(state.alpha_shop.day)
	if regional(state.alpha_shop.profile):
		var past:Dictionary = market_history(state,day)
		var lines:Array[String] = []
		var labels:Dictionary = MARKET_LABELS.duplicate()
		if expanded(state.alpha_shop.profile): labels.merge(EXTRA_LABELS)
		if Catalog.enabled(state.alpha_shop.profile):
			labels.merge({"market_food":"시장 구역 · 식량","market_medical":"시장 구역 · 의료용품"})
		for market:String in labels:
			var supply:String = "납품 지연" if market_shortage(state.alpha_shop.profile,market,day) else "정상 공급 공지"
			var count:int = int(past.counts.get(market,0))
			var net:int = int(past.flows.get(market,0))
			var trend:String = "거래 자료 부족" if count==0 else ("순매입" if net<0 else ("순매출" if net>0 else "순거래량 변동 없음"))
			lines.append("%s · %d일차 · 지역 납품 공지: %s\n상점 거래장(전일까지 %d건): %s"%[labels[market],day,supply,count,trend])
		return "\n".join(lines)
	var arrival := "전지 납품 지연" if shortage(state.alpha_shop.profile,day) else "전지 정상 공급"
	var net := int(history(state,day).net)
	var sales := "누적 순매입" if net<0 else ("누적 순매출" if net>0 else "순거래량 변동 없음")
	return "항구 납품 공지 · %d일차 · %s\n상점 전지 거래장 · 전일까지 %s"%[day,arrival,sales]
