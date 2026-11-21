extends RefCounted
## Finite, authored market orders for the optional campaign_42 profile.
## Authoritative goods, money and settlement remain only in GameSession.
## Price is fixed once at admission; supply/demand are projections of
## existing object ownership, actual funded customers and paid receipts.
const Rules=preload("res://src/domain/value_rules.gd")
const Clock=preload("res://src/domain/business_clock.gd")
const Trace=preload("res://src/domain/world_causal_trace.gd")
const Bargain=preload("res://src/domain/npc_bargaining_policy.gd")
const MAX_ORDERS:int=128
const MAX_BUYERS:int=64
const STATUSES:Array=["ordinary","strained","limited"]
const CONTRACT:int=1

static func policy(s:Dictionary)->Dictionary:
	return s.get("calendar",{}).get("profile",{}).get("market_flow",{})

static func _item_id(visit:Dictionary)->String:
	var prices:Variant=visit.get("prices",{})
	return str(prices.keys()[0]) if prices is Dictionary and prices.size()==1 else ""

static func _money(s:Dictionary,visit_id:String,entry:Dictionary)->Dictionary:
	var visit:Dictionary=s.get("visits",{}).get(visit_id,{})
	var item:String=_item_id(visit)
	if visit.is_empty() or item!=str(entry.get("item_id","")):
		return {}
	var original:Dictionary=visit.prices[item]
	var currency:String=str(entry.get("currency",""))
	if not original.has(currency) or not Rules.integer(original.get(currency),1):
		return {}
	return original

## The seed contains finite, real goods and real buyers; no phantom stock.
## Range bound +/-25% per authored quote prevents accidental windfalls.
static func seed_valid(s:Dictionary,profile:Dictionary)->bool:
	var m:Variant=profile.get("market_flow")
	if profile.get("id")!="campaign_42" or not profile.has("regional_world") or not Rules.keys(m,["version","entries","buyers","flow_step","max_flow_delta"]) or m.version!=CONTRACT or not m.entries is Dictionary or m.entries.is_empty() or m.entries.size()>MAX_ORDERS or not m.buyers is Dictionary or m.buyers.size()>MAX_BUYERS or not Rules.integer(m.flow_step,0,10) or not Rules.integer(m.max_flow_delta,0,50):
		return false
	var regions:Dictionary=profile.regional_world.get("regions",{})
	for actor_id:Variant in m.buyers:
		var buyer:Variant=m.buyers[actor_id]
		if not Rules.identifier(actor_id) or actor_id=="player" or not s.wallets.has(actor_id) or not Rules.keys(buyer,["categories","reserve"]) or not buyer.categories is Array or buyer.categories.is_empty() or buyer.categories.size()>16 or not Rules.integer(buyer.reserve,0,1000000):
			return false
		var seen:Dictionary={}
		for category:Variant in buyer.categories:
			if not Rules.identifier(category) or seen.has(category):
				return false
			seen[category]=true
	for visit_id:Variant in m.entries:
		var e:Variant=m.entries[visit_id]
		if not Rules.identifier(visit_id) or not Rules.keys(e,["region","category","item_id","def_id","currency","prices"]) or not Rules.identifier(e.region) or not regions.has(e.region) or not Rules.identifier(e.category) or not Rules.identifier(e.item_id) or not Rules.identifier(e.def_id) or e.currency not in ["VKC","USD"] or not Rules.keys(e.prices,STATUSES):
			return false
		var v:Dictionary=s.visits.get(visit_id,{})
		if v.is_empty() or v.scope.get("kind")!="ordinary" or v.scope.get("purpose") not in ["purchase","sale"] or v.scope.get("completed") or _item_id(v)!=e.item_id or not s.items.has(e.item_id) or s.items[e.item_id].def_id!=e.def_id or not s.wallets.has(v.seller) or not s.wallets.has(v.buyer):
			return false
		var initial:Dictionary=_money(s,visit_id,e)
		if initial.is_empty() or initial["USD" if e.currency=="VKC" else "VKC"]!=0:
			return false
		var basis:int=int(initial[e.currency])
		for status:String in STATUSES:
			if not Rules.integer(e.prices[status],maxi(1,int(ceili(basis*0.75))),maxi(1,int(floori(basis*1.25)))):
				return false
		if v.seller=="player":
			if not m.buyers.has(v.buyer) or e.category not in m.buyers[v.buyer].categories:
				return false
	return true

## Signed, actual historic settlements only. Delivered items and payments
## are never duplicated in this domain; "flow" is a reversible projection.
## A player purchase removes one market unit; resale adds one.
static func _settled_flow(s:Dictionary,region:String,category:String,before_day:int)->int:
	var total:int=0
	var entries:Dictionary=policy(s).get("entries",{})
	for row:Dictionary in s.get("ledger",[]):
		var id:String=str(row.get("visit_id",""))
		var e:Dictionary=entries.get(id,{})
		if e.is_empty() or e.region!=region or e.category!=category or Clock.day_index(int(row.get("game_minutes",0)))>=before_day:
			continue
		if e.item_id not in row.get("root_ids",[]) or not Trace.verified_trade_row(s,row):
			continue
		# Ledger from/to are CASH direction (buyer -> seller), not goods.
		# Verify both recorded parties against the signed visit before a
		# past receipt can influence stock pressure in the next opening.
		var v:Dictionary=s.visits.get(id,{})
		if v.is_empty() or row.get("from")!=v.buyer or row.get("to")!=v.seller:
			continue
		if v.buyer=="player":
			total-=1 # player bought: one fewer local offered good
		elif v.seller=="player":
			total+=1 # player sold: one more good returned to circulation
	return total

## Quote exists only for an authored order, never a new item or new wallet.
static func quote(s:Dictionary,visit_id:String)->Dictionary:
	var e:Dictionary=policy(s).get("entries",{}).get(visit_id,{})
	if e.is_empty() or not s.get("calendar",{}).has("regional_world"):
		return {}
	var status:String=str(s.calendar.regional_world.get("status",{}).get(e.region,""))
	if status not in STATUSES:
		return {}
	var initial:Dictionary=s.visits[visit_id].prices[e.item_id]
	var basis:int=int(initial[e.currency])
	var m:Dictionary=policy(s)
	var net:int=_settled_flow(s,e.region,e.category,Clock.day_index(int(s.game_minutes)))
	var delta:int=clampi(-net*int(m.flow_step),-int(m.max_flow_delta),int(m.max_flow_delta))
	var negotiated_delta:int=Bargain.adjustment(s,visit_id)
	var settled:int=clampi(int(e.prices[status])+delta+negotiated_delta,maxi(1,int(ceili(basis*0.75))),maxi(1,int(floori(basis*1.25))))
	return {"visit_id":visit_id,"item_id":e.item_id,"region":e.region,"category":e.category,"currency":e.currency,"amount":settled}

static func eligible(s:Dictionary,visit_id:String)->bool:
	var e:Dictionary=policy(s).get("entries",{}).get(visit_id,{})
	if e.is_empty():
		return true
	var v:Dictionary=s.visits.get(visit_id,{})
	if v.is_empty() or v.scope.completed or not s.items.has(e.item_id):
		return false
	var item:Dictionary=s.items[e.item_id]
	if item.owner_id!=v.seller or item.custodian_id!=v.seller:
		return false
	var offer:Dictionary=quote(s,visit_id)
	if offer.is_empty():
		return false
	if v.seller=="player":
		var buyer:Dictionary=policy(s).buyers.get(v.buyer,{})
		if buyer.is_empty() or e.category not in buyer.categories:
			return false
		return int(s.wallets[v.buyer][e.currency])>=int(offer.amount)+int(buyer.reserve)
	return true

## Called inside calendar_next_visit candidate; the existing trade primitive
## checks this frozen visit.prices amount and performs the ONLY money transfer.
static func admit(s:Dictionary,visit_id:String)->String:
	if not policy(s).get("entries",{}).has(visit_id):
		return ""
	if not eligible(s,visit_id):
		return "market_order_unavailable"
	var offer:Dictionary=quote(s,visit_id)
	var price:Dictionary={"VKC":0,"USD":0}
	price[offer.currency]=offer.amount
	s.visits[visit_id].prices[offer.item_id]=price
	return ""

## Public: only the ACTUALLY admitted offer and the player's past deals.
## No hidden customer budget, unstaged NPC stock, future quote or secret state.
static func view(s:Dictionary)->Dictionary:
	var result:Dictionary={"settled":[]}
	var entries:Dictionary=policy(s).get("entries",{})
	for row:Dictionary in s.get("ledger",[]):
		var id:String=str(row.get("visit_id",""))
		if not entries.has(id) or not Trace.verified_trade_row(s,row):
			continue
		var entry:Dictionary=entries[id]
		var visit:Dictionary=s.visits.get(id,{})
		if visit.is_empty() or entry.item_id not in row.get("root_ids",[]) or row.get("from")!=visit.buyer or row.get("to")!=visit.seller:
			continue
		result.settled.append({"visit_id":id,"region":entry.region,"category":entry.category,"revision":row.revision})
	var active:String=str(s.get("calendar",{}).get("queue",{}).get("active",""))
	if entries.has(active):
		var e:Dictionary=entries[active]
		var v:Dictionary=s.visits[active]
		var settled_price:Dictionary=v.prices[e.item_id]
		result["active_offer"]={"visit_id":active,"region":e.region,"category":e.category,
			"item_id":e.item_id,"currency":e.currency,"amount":settled_price[e.currency]}
	return result
