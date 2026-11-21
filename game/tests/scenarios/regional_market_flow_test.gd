extends SceneTree
## One physical W001 / W002, same real actor, two region outcomes,
## an actual next-day negotiated quote and a finite third-day buyer.
const Watch=preload("res://tests/fixtures/p2_watch_state.gd")
const Context=preload("res://tests/fixtures/gate0_c_state.gd")
const Session=preload("res://src/domain/game_session.gd")
const Market=preload("res://src/domain/regional_market_flow.gd")
const Population=preload("res://src/domain/npc_population.gd")
const Rules=preload("res://src/domain/value_rules.gd")
const Repo=preload("res://src/persistence/save_repository.gd")
var checks:int=0
var failures:int=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func money(amount:int)->Dictionary:
	return {"VKC":amount,"USD":0}

func terms(visit:String,item:String)->Dictionary:
	return {"region":"market_quarter","category":"civilian_goods","item_id":item,
		"def_id":"fictional_watch_p2","currency":"VKC",
		"prices":{"ordinary":90,"limited":70,"strained":100}} if visit!="buy_back" else {
		"region":"market_quarter","category":"civilian_goods","item_id":item,
		"def_id":"fictional_watch_p2","currency":"VKC",
		"prices":{"ordinary":110,"limited":95,"strained":120}}

func fixture()->Dictionary:
	var original:RefCounted=Watch.fresh()
	if original==null:
		return {}
	var s:Dictionary=original.snapshot()
	var profile:Dictionary=s.calendar.profile.duplicate(true)
	s.erase("calendar")
	profile.id="campaign_42"
	profile.day_ids=[]
	profile.visit_days={}
	for day:int in range(1,43):
		var name:String="d"+str(day)
		profile.day_ids.append(name)
		profile.visit_days[name]=[]
	profile.visit_days.d1=["watch_a"]
	profile.visit_days.d2=["watch_b","watch_c"]
	profile.visit_days.d3=["buy_back"]
	s.visits.watch_b.opens=1440
	s.visits.watch_b.expires=2040
	var extra:Dictionary=s.visits.watch_b.duplicate(true)
	extra.scope.visit_id="watch_c"
	s.visits["watch_c"]=extra
	var buy_back:Dictionary=Context.visit("buy_back","player","collector",{"W001":money(110)})
	buy_back.opens=2880
	buy_back.expires=3480
	s.visits["buy_back"]=buy_back
	s.wallets["collector"]=money(130)
	s.inventories["collector_grid"]={"owner_id":"collector","width":4,"height":3,"host_item":""}
	profile["npc_continuity"]={"version":1,"gates":{"watch_b":{"prior_visit":"watch_a","outcome":"traded"}}}
	profile["regional_world"]={"version":1,"regions":{"market_quarter":{"status":"ordinary"},"old_quarter":{"status":"ordinary"}},
		"events":{"market_d2":{"day":2,"region":"market_quarter","topic":"civilian_supply",
			"without_player":"strained","with_player":"limited",
			"cause_visit":"watch_a","source":"local_market_notice"}},"gates":{}}
	profile["npc_population"]={"version":1,"seed":582,"actors":{
		"seller":{"kind":"scavenger","region":"market_quarter"},
		"collector":{"kind":"civilian","region":"market_quarter"}}}
	profile["market_flow"]={"version":1,"flow_step":5,"max_flow_delta":10,
		"buyers":{"collector":{"categories":["civilian_goods"],"reserve":20}},
		"entries":{"watch_a":terms("watch_a","W001"),
			"watch_b":terms("watch_b","W002"),
			"watch_c":terms("watch_c","W002"),
			"buy_back":terms("buy_back","W001")}}
	var definitions:Dictionary={"fictional_watch_p2":{"def_id":"fictional_watch_p2",
		"category":"fixture","localization_key":"p2.watch.meridian12",
		"render_key":"placeholder_none","width":1,"height":1}}
	return {"defs":definitions,"initial":s,"profile":profile}

func cmd(s:RefCounted,kind:String,id:String,p:Dictionary={})->Dictionary:
	var command:Dictionary={"action_id":id,"expected_revision":s.snapshot().revision,
		"type":kind,"payload":p}
	return s.execute(command)

func trade_payload(visit:String,item:String,seller:String,buyer:String,amount:int,inventory:String)->Dictionary:
	return {"visit_id":visit,"item_id":item,"seller":seller,"buyer":buyer,"currency":"VKC",
		"amount":amount,"inventory":inventory,"x":1 if item=="W002" else 0,"y":0,"rotated":false}

func advance(s:RefCounted,day:int)->bool:
	return cmd(s,"calendar_close","close_"+str(day)).get("ok",false) and cmd(s,"calendar_morning","open_"+str(day+1)).get("ok",false)

func branch(c:Dictionary,paid:bool)->Dictionary:
	var s:=Session.new()
	if not s.initialize(c.defs,c.initial,false,false,c.profile):
		printerr("MARKET_INIT ",s.initialization_error())
		return {}
	if not cmd(s,"calendar_next_visit","visit_a").get("ok",false):
		return {}
	var admission:Dictionary=s.calendar_view().regional_market
	var guest:Dictionary=s.calendar_view().get("npc_visitor",{})
	if guest.get("actor_id")!="seller" or guest.has("private_trait") or guest.has("wallet") or guest.get("returning",true):
		return {}
	if admission.get("active_offer",{}).get("amount")!=90:
		return {}
	var outcome:Dictionary=cmd(s,"trade","settled_a",trade_payload("watch_a","W001","seller","player",90,"player_grid")) if paid else cmd(s,"calendar_decline_visit","refused_a",{"visit_id":"watch_a"})
	if not outcome.get("ok",false) or not advance(s,1):
		return {}
	return {"session":s}

func _initialize()->void:
	var c:Dictionary=fixture()
	check(not c.is_empty(),"authored market and schedule seed")
	var personae:Dictionary=Population.seed(c.initial,c.profile)
	check(personae.get("actors",{}).size()==2 and personae.actors.seller.actor_id=="seller","bounded seeded real customer identities")
	check(Population.seed(c.initial,c.profile)==personae,"seed deterministic across repeated creation")
	var changed:Dictionary=c.profile.duplicate(true)
	changed.npc_population.seed=583
	check(Population.seed(c.initial,changed).actors.seller.generation_id!=personae.actors.seller.generation_id,"campaign seed gives a distinct generation identity")
	var invalid_npc:Dictionary=c.profile.duplicate(true)
	invalid_npc.npc_population.actors.seller.region="old_quarter"
	check(Population.seed(c.initial,invalid_npc).is_empty(),"no phantom actor outside authored market")
	invalid_npc=c.profile.duplicate(true)
	invalid_npc.npc_population.actors["new_wallet"]={"kind":"civilian","region":"market_quarter"}
	check(Population.seed(c.initial,invalid_npc).is_empty(),"no procedurally minted money or wallet")
	if c.is_empty():
		quit(1)
		return
	var invalid:Dictionary=c.duplicate(true)
	invalid.profile.market_flow.entries.watch_b.def_id="forged"
	check(not Market.seed_valid(invalid.initial,invalid.profile),"reject bogus SKU evidence")
	invalid=c.duplicate(true)
	invalid.profile.market_flow.entries.watch_b.prices.limited=1
	check(not Market.seed_valid(invalid.initial,invalid.profile),"reject unbounded phantom price")
	invalid=c.duplicate(true)
	invalid.profile.market_flow.buyers.collector.categories=["unrelated"]
	check(not Market.seed_valid(invalid.initial,invalid.profile),"reject ineligible NPC demand")
	var paid:Dictionary=branch(c,true)
	var refused:Dictionary=branch(c,false)
	check(not paid.is_empty() and not refused.is_empty(),"actual player trade / explicit decline diverge")
	if paid.is_empty() or refused.is_empty():
		quit(1)
		return
	var a:RefCounted=paid.session
	var b:RefCounted=refused.session
	check(a.calendar_view().world_regions.regions.market_quarter=="limited" and b.calendar_view().world_regions.regions.market_quarter=="strained","same external shortage differs only by paid trade")
	check(a.calendar_view().visits.can_next and b.calendar_view().visits.can_next,"both branches have finite Day2 offers")
	check(cmd(a,"calendar_next_visit","day2_paid").get("ok",false),"paid path admits returning customer")
	check(cmd(b,"calendar_next_visit","day2_refused").get("ok",false),"refused path admits alternative real customer offer")
	var va:Dictionary=a.calendar_view()
	var vb:Dictionary=b.calendar_view()
	check(va.visits.active=="watch_b" and vb.visits.active=="watch_c","NPC continuity is not retroactively invented")
	check(va.npc_visitor.actor_id=="seller" and va.npc_visitor.alias==personae.actors.seller.alias and va.npc_visitor.returning,"real trade returns the SAME generated persona")
	check(vb.npc_visitor.actor_id=="seller" and not vb.npc_visitor.returning,"declined alternative has no invented paid relationship")
	check(va.regional_market.active_offer.amount==75 and vb.regional_market.active_offer.amount==100,"authored status plus previous paid flow reprices actual visit")
	check(va.visits.terms.prices.W002.VKC==75 and vb.visits.terms.prices.W002.VKC==100,"market quote frozen in real transaction authority")
	var before:Dictionary=a.snapshot()
	var forged:Dictionary=cmd(a,"trade","bad_amount",trade_payload("watch_b","W002","seller","player",90,"player_grid"))
	check(not forged.get("ok",false) and a.snapshot()==before,"stale seed price cannot be paid after market quote")
	check(cmd(a,"trade","settled_b",trade_payload("watch_b","W002","seller","player",75,"player_grid")).get("ok",false),"real changed price settles once")
	check(cmd(b,"trade","settled_c",trade_payload("watch_c","W002","seller","player",100,"player_grid")).get("ok",false),"alternative market price settles with own wallet")
	check(a.snapshot().wallets.player.VKC==0 and b.snapshot().wallets.player.VKC==65,"paid ledger and actor balances reflect no phantom income")
	check(a.snapshot().items.W002.owner_id=="player" and b.snapshot().items.W002.owner_id=="player","item ID remains actual transferred item")
	check(a.calendar_view().regional_market.settled.size()==2 and b.calendar_view().regional_market.settled.size()==1,"market history only real receipt-linked trades")
	check(advance(a,2) and advance(b,2),"next day after finite sales")
	check(a.calendar_view().visits.can_next and not b.calendar_view().visits.can_next,"third-day buyer exists only for physically owned W001")
	check(cmd(a,"calendar_next_visit","day3_buy_back").get("ok",false),"real funded collector requests acquired item")
	var quote:Dictionary=a.calendar_view().regional_market.active_offer
	check(quote.amount==105 and quote.item_id=="W001","next day net stock flow reprices collector demand")
	check(a.calendar_view().npc_visitor.actor_id=="collector" and a.calendar_view().npc_visitor.alias==personae.actors.collector.alias,"third day different finite buyer has own stable persona")
	check(cmd(a,"trade","resold",trade_payload("buy_back","W001","player","collector",105,"collector_grid")).get("ok",false),"collector's finite budget pays actual price")
	check(a.snapshot().wallets.collector.VKC==25 and a.snapshot().items.W001.owner_id=="collector","collector reserve and actual item custody preserved")
	check(not a.calendar_view().regional_market.has("active_offer"),"completed market quote no longer leaks")
	var saved:Dictionary=a.snapshot()
	var cold:=Session.new()
	check(cold.initialize(c.defs,c.initial,false,false,c.profile) and cold.restore(saved) and cold.snapshot()==saved,"all dynamic prices and events replay exactly")
	var changed_persona:Dictionary=saved.duplicate(true)
	changed_persona.calendar.npc_population.actors.seller.alias="FORGED"
	check(not cold.restore(changed_persona) and cold.snapshot()==saved,"generated identity cannot be changed by forged save")
	var tampered:Dictionary=saved.duplicate(true)
	tampered.visits.buy_back.prices.W001.VKC=110
	check(not cold.restore(tampered) and cold.snapshot()==saved,"forged settled market price denied on restore")
	var repo:=Repo.new("user://zt_rebuild/market_flow_"+str(Time.get_ticks_usec()))
	check(repo.save_session(a,"market_flow").get("ok",false),"actual v4 disk save")
	var loaded:=Session.new()
	check(loaded.initialize(c.defs,c.initial,false,false,c.profile) and repo.load_session(loaded,"market_flow").get("ok",false) and loaded.snapshot()==saved,"actual v4 disk load exact")
	print("REGIONAL_MARKET_FLOW: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
