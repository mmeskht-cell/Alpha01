extends SceneTree
## 42-day same real seller, actual trade-backed memory reprices a repeat
## encounter without editing a prior receipt, inventing liquidity or exposing
## the customer's private negotiation trait.
const Watch=preload("res://tests/fixtures/p2_watch_state.gd")
const Session=preload("res://src/domain/game_session.gd")
const Policy=preload("res://src/domain/npc_bargaining_policy.gd")
var checks:int=0
var failures:int=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func fixture()->Dictionary:
	var old:RefCounted=Watch.fresh()
	if old==null:
		return {}
	var s:Dictionary=old.snapshot()
	var p:Dictionary=s.calendar.profile.duplicate(true)
	s.erase("calendar")
	p.id="campaign_42"
	p.day_ids=[]
	p.visit_days={}
	for i:int in range(1,43):
		var day:String="d"+str(i)
		p.day_ids.append(day)
		p.visit_days[day]=["watch_a"] if i==1 else (["watch_b"] if i==2 else [])
	s.visits.watch_b.opens=1440
	s.visits.watch_b.expires=2040
	p["regional_world"]={"version":1,"regions":{"market_quarter":{"status":"ordinary"}},
		"events":{},"gates":{}}
	var row:Dictionary={"region":"market_quarter","category":"civilian_goods",
		"def_id":"fictional_watch_p2","currency":"VKC",
		"prices":{"ordinary":90,"strained":90,"limited":90}}
	p["market_flow"]={"version":1,"flow_step":0,"max_flow_delta":0,
		"buyers":{},"entries":{
			"watch_a":{"region":row.region,"category":row.category,"item_id":"W001",
				"def_id":row.def_id,"currency":row.currency,"prices":row.prices.duplicate(true)},
			"watch_b":{"region":row.region,"category":row.category,"item_id":"W002",
				"def_id":row.def_id,"currency":row.currency,"prices":row.prices.duplicate(true)}}}
	p["npc_population"]={"version":1,"seed":9284,"actors":{
		"seller":{"kind":"mercenary","region":"market_quarter"}}}
	p["npc_bargaining"]={"version":1,"traits":{
		"cautious":{"seller_delta":5,"buyer_delta":-5},
		"impatient":{"seller_delta":-5,"buyer_delta":5},
		"methodical":{"seller_delta":0,"buyer_delta":0},
		"reserved":{"seller_delta":2,"buyer_delta":-2}},
		"loyalty_step":2,"max_trades":2}
	var defs:Dictionary={"fictional_watch_p2":{"def_id":"fictional_watch_p2","category":"fixture",
		"localization_key":"p2.watch.meridian12","render_key":"placeholder_none","width":1,"height":1}}
	return {"defs":defs,"state":s,"profile":p}

func cmd(s:RefCounted,kind:String,id:String,p:Dictionary={})->Dictionary:
	return s.execute({"action_id":id,"expected_revision":s.snapshot().revision,"type":kind,"payload":p})

func _initialize()->void:
	var f:Dictionary=fixture()
	check(not f.is_empty(),"funded original merchant/profile")
	var invalid:Dictionary=f.duplicate(true)
	invalid.profile.npc_bargaining.traits.erase("reserved")
	check(not Policy.valid({"calendar":{"npc_population":{"actors":{"seller":{"private_trait":"methodical"}}}}},
		invalid.profile),"missing trait policy rejected")
	var s:=Session.new()
	check(s.initialize(f.defs,f.state,false,false,f.profile),"42 day personality policy initialized")
	if s.snapshot().is_empty():
		printerr("BARGAIN_INIT ",s.initialization_error())
		quit(1)
		return
	var behavior_key:String=s.snapshot().calendar.npc_population.actors.seller.private_trait
	var trait_price:int=int(f.profile.npc_bargaining.traits[behavior_key].seller_delta)
	check(not s.calendar_view().has("npc_visitor"),"no private future customer disclosed")
	check(cmd(s,"calendar_next_visit","first_guest").get("ok",false),
		"existing funded customer admitted")
	var first:Dictionary=s.calendar_view()
	check(first.npc_visitor.actor_id=="seller" and not first.npc_visitor.has("private_trait"),
		"public persona hides private bargaining trait")
	check(first.regional_market.active_offer.amount==90+trait_price,
		"personality actually changes first firm quote")
	var amount:int=int(first.regional_market.active_offer.amount)
	check(cmd(s,"trade","paid_watch_a",{"visit_id":"watch_a","item_id":"W001",
		"seller":"seller","buyer":"player","currency":"VKC","amount":amount,
		"inventory":"player_grid","x":0,"y":0,"rotated":false}).get("ok",false),
		"only real paid trade enters customer memory")
	check(cmd(s,"calendar_close","d1_close").get("ok",false)
		and cmd(s,"calendar_morning","d2_open").get("ok",false),
		"second day starts from actual first encounter")
	check(cmd(s,"calendar_next_visit","second_guest").get("ok",false),
		"same actor returns with the second real W002")
	var second:Dictionary=s.calendar_view()
	check(second.regional_market.active_offer.amount==90+trait_price-2,
		"verified prior paid trade applies bounded repeat-business adjustment")
	check(second.npc_visitor.returning and second.customer_memory.trades==1,
		"same actor has first-hand history; no free loyalty")
	check(not second.regional_market.has("future_balance"),"future buyer money still private")
	var snap:Dictionary=s.snapshot()
	var cold:=Session.new()
	check(cold.initialize(f.defs,f.state,false,false,f.profile) and cold.restore(snap)
		and cold.snapshot()==snap and cold.calendar_view().regional_market.active_offer.amount==second.regional_market.active_offer.amount,
		"same personality and memory price survive exact saved replay")
	var forged:Dictionary=snap.duplicate(true)
	forged.calendar.npc_population.actors.seller.private_trait="not_a_trait"
	check(not cold.restore(forged) and cold.snapshot()==snap,
		"forged NPC personality on load rejected")
	print("NPC_BARGAINING_POLICY: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
