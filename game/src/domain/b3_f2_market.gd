extends RefCounted
## Private seven-day battery market. No wallet, inventory or ledger of its own.
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

static func seed_valid(state:Dictionary)->bool:
	var expected := {"battery_sale":"G07","alpha_b3_g11_battery_d4":"G11","alpha_b3_g11_battery_d5":"G11"}
	for id:String in expected:
		var visit:Dictionary = state.visits.get(id,{})
		if visit.get("buyer")!=expected[id] or visit.get("seller")!="player": return false
		if visit.get("prices",{}).get("BAT02")!={"VKC":BID_BASIS,"USD":0}: return false
	var supplier:Dictionary = state.visits.get(SUPPLIER,{})
	return supplier.get("seller")=="G06" and supplier.get("buyer")=="player" and supplier.get("prices",{}).get("BAT02")=={"VKC":40,"USD":0}

static func shortage(profile:Dictionary, day:int)->bool:
	return profile.get("battery_market")=="late_delivery" and day in [3,4]

static func history(state:Dictionary, day:int)->Dictionary:
	var net := 0
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
		if BATTERY in row.root_ids: net += -1 if buying else 1 # Positive means goods returned to local circulation.
	return {"net":net,"customers":customers}

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
	var past := history(state,day)
	var delayed := shortage(a.profile,day)
	for slot:Dictionary in rows:
		if slot.id==SUPPLIER:
			if not state.visits[slot.id].scope.completed:
				state.visits[slot.id].prices.BAT02 = {"VKC":0,"USD":1} if delayed else {"VKC":40,"USD":0}
			continue
		if slot.id not in BIDS: continue
		var visit:Dictionary = state.visits[slot.id]
		if visit.scope.completed: continue
		var base := BID_BASIS
		var personal := int(BUYER_OFFSETS[visit.buyer])
		if past.customers.has(visit.buyer): personal += 2
		personal += prior_terms(a,visit.buyer)
		visit.prices.BAT02.VKC = Flow.bounded_quote(base,base+(8 if delayed else 0),past.net,3,6,personal)

static func bulletin(state:Dictionary)->String:
	var day := int(state.alpha_shop.day)
	var arrival := "전지 납품 지연" if shortage(state.alpha_shop.profile,day) else "전지 정상 공급"
	var net := int(history(state,day).net)
	var sales := "누적 순매입" if net<0 else ("누적 순매출" if net>0 else "순거래량 변동 없음")
	return "항구 납품 공지 · %d일차 · %s\n상점 전지 거래장 · 전일까지 %s"%[day,arrival,sales]
