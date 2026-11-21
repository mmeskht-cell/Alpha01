extends SceneTree
## Cross-system 42-day verification with original finite money/goods;
## alternative real purchase versus pawn loan affects a later return quote.
const Watch=preload("res://tests/fixtures/p2_watch_state.gd")
const Session=preload("res://src/domain/game_session.gd")
const Objects=preload("res://src/domain/object_schema.gd")
const Visits=preload("res://src/domain/npc_generated_visits.gd")
const Clock=preload("res://src/domain/business_clock.gd")
var checks:int=0
var failures:int=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: "+label)
static func cash(n:int)->Dictionary:
	return {"VKC":n,"USD":0}
static func market(id:String,n:int)->Dictionary:
	return {"region":"market_quarter","category":"field_goods",
		"item_id":id,"def_id":"fictional_watch_p2","currency":"VKC",
		"prices":{"ordinary":n,"strained":n,"limited":n}}
static func fixture()->Dictionary:
	var base:RefCounted=Watch.fresh(false)
	if base==null:
		return {}
	var s:Dictionary=base.snapshot()
	var p:Dictionary=s.calendar.profile.duplicate(true)
	s.erase("calendar")
	s.wallets.seller.VKC=100
	s.wallets["merc_a"]=cash(20)
	s.wallets["order_buyer"]=cash(300)
	s.wallets["escrow"]=cash(0)
	s.wallets["broker"]={"VKC":0,"USD":3}
	s.inventories["merc_grid"]={"owner_id":"merc_a","width":4,"height":3,"host_item":""}
	s.inventories["order_grid"]={"owner_id":"order_buyer","width":4,"height":3,"host_item":""}
	s.inventories["broker_grid"]={"owner_id":"broker","width":2,"height":2,"host_item":""}
	s.items["SELL01"]=Objects.fresh_item("fictional_watch_p2","player","player_grid",2,0,"original_item")
	for i:int in range(4):
		s.items["A"+str(100+i)]=Objects.fresh_item("fictional_watch_p2","merc_a",
			"merc_grid",i,0,"real_merc_goods")
	s.visits.watch_b.opens=4320
	s.visits.watch_b.expires=4920
	p.id="campaign_42"
	p.day_ids=[]
	p.visit_days={}
	for n:int in range(1,43):
		var day:String="d"+str(n)
		p.day_ids.append(day)
		p.visit_days[day]=["watch_a"] if n==1 else (["watch_b"] if n==4 else [])
	p["regional_world"]={"version":1,"regions":{"market_quarter":{"status":"ordinary"}},"events":{},"gates":{}}
	p["market_flow"]={"version":1,"flow_step":0,"max_flow_delta":0,"buyers":{},
		"entries":{"watch_a":market("W001",90),"watch_b":market("W002",90)}}
	p["npc_population"]={"version":1,"seed":410,"actors":{
		"seller":{"kind":"mercenary","region":"market_quarter"},
		"merc_a":{"kind":"mercenary","region":"market_quarter"}}}
	p["npc_bargaining"]={"version":1,"traits":{
		"cautious":{"seller_delta":5,"buyer_delta":-5},
		"impatient":{"seller_delta":-5,"buyer_delta":5},
		"methodical":{"seller_delta":0,"buyer_delta":0},
		"reserved":{"seller_delta":2,"buyer_delta":-2}},"loyalty_step":2,"max_trades":3}
	p["npc_generated_visits"]={"version":1,"seed":22,"slots":{
		"d3_merc":{"day_id":"d3","region":"market_quarter","candidates":[
			{"actor":"merc_a","item_id":"A100","price":cash(62),"side":"offer"},
			{"actor":"merc_a","item_id":"A101","price":cash(64),"side":"offer"}]},
		"d6_merc":{"day_id":"d6","region":"market_quarter","candidates":[
			{"actor":"merc_a","item_id":"A102","price":cash(68),"side":"offer"},
			{"actor":"merc_a","item_id":"A103","price":cash(72),"side":"offer"}]}}}
	p["npc_continuity"]={"version":1,"gates":{
		"d6_merc":{"prior_visit":"d3_merc","outcome":"traded"}}}
	var material:Dictionary=Visits.expand(s,p)
	if material.is_empty():
		return {}
	for id:String in ["d3_merc","d6_merc"]:
		var v:Dictionary=material.state.visits[id]
		var item:String=str(v.prices.keys()[0])
		p.market_flow.entries[id]=market(item,int(v.prices[item].VKC))
	p["merchant_contracts"]={"version":1,"escrow_actor":"escrow",
		"pawns":{"p1":{"customer":"seller","visit_id":"watch_a","item_id":"W001",
			"principal":cash(40),"repayment":cash(45),"repayment_day":2,"due_day":2,
			"placement":{"inventory":"player_grid","x":0,"y":0,"rotated":false}}},
		"orders":{"o1":{"customer":"order_buyer","def_id":"fictional_watch_p2",
			"price":cash(100),"offer_day":1,"due_day":2}}}
	p["exchange_market"]={"version":1,"quotes":{
		"fx":{"counterparty":"broker","give_currency":"VKC","give_amount":20,
			"receive_currency":"USD","receive_amount":1,"first_day":1,"last_day":2}}}
	var defs:Dictionary={"fictional_watch_p2":{"def_id":"fictional_watch_p2",
		"category":"fixture","localization_key":"p2.watch.meridian12",
		"render_key":"placeholder_none","width":1,"height":1}}
	return {"state":s,"profile":p,"defs":defs}
func open(f:Dictionary)->RefCounted:
	var session:=Session.new()
	if session.initialize(f.defs,f.state,false,false,f.profile):
		return session
	printerr("CROSS_INIT "+session.initialization_error())
	return null
func action(session:RefCounted,kind:String,id:String,p:Dictionary={})->bool:
	var result:Dictionary=session.execute({"action_id":id,
		"expected_revision":session.snapshot().revision,"type":kind,"payload":p})
	if not result.get("ok",false):
		printerr("CROSS_BAD_ACTION "+id+" "+str(result.get("error","")))
	return bool(result.get("ok",false))
func to_day(s:RefCounted,day:int,name:String)->bool:
	while Clock.day_index(int(s.snapshot().game_minutes))<day:
		var n:int=Clock.day_index(int(s.snapshot().game_minutes))
		if s.snapshot().phase=="shop" and not action(s,"calendar_close",name+"_c"+str(n)):
			return false
		if s.snapshot().phase=="workshop" and not action(s,"calendar_morning",name+"_m"+str(n)):
			return false
	return true
func buy_active(s:RefCounted,visit:String,id:String,x:int)->bool:
	var v:Dictionary=s.calendar_view().visits.terms
	var item:String=str(v.prices.keys()[0])
	var amount:int=int(v.prices[item].VKC)
	return action(s,"trade",id,{"visit_id":visit,"item_id":item,
		"seller":v.seller,"buyer":"player","currency":"VKC","amount":amount,
		"inventory":"player_grid","x":x,"y":0,"rotated":false})
func run(f:Dictionary,pledge:bool,buy_d3:bool)->Dictionary:
	var s:RefCounted=open(f)
	if s==null:
		return {}
	check(not s.calendar_view().has("npc_visitor"),"no future NPC identity leaked")
	check(action(s,"calendar_next_visit","arrival"),"actual original D1 arrival")
	if pledge:
		check(action(s,"merchant_pawn_accept","p1_loan",{"contract_id":"p1"}),"actual cash pawn")
	else:
		check(buy_active(s,"watch_a","d1_purchase",0),"actual first-hand D1 purchase")
	check(action(s,"merchant_order_accept","o1_escrow",{"contract_id":"o1"}),
		"real buyer cash held separately")
	check(action(s,"calendar_exchange","fx_cash",{"quote_id":"fx"}),
		"real FX with funded broker")
	var original:Dictionary=s.snapshot()
	check(original.wallets.escrow.VKC==100 and original.wallets.player.USD==1
		and original.wallets.broker.USD==2 and original.wallets.broker.VKC==20,
		"all currencies conserved at real counterparties")
	check(to_day(s,2,"route"),"real D2 opened")
	if pledge:
		check(action(s,"merchant_pawn_redeem","p1_repay",{"contract_id":"p1"}),
			"only debtor's authored D2 repayment settles pawn")
	var deliveries:Array=s.calendar_view().merchant_contracts.orders.o1.delivery_options
	check(not deliveries.is_empty(),"real destination space for paid order")
	if deliveries.is_empty():
		return {}
	var selected:Dictionary={}
	for row:Dictionary in deliveries:
		if row.item_id=="SELL01":
			selected=row
			break
	check(not selected.is_empty(),"order can explicitly pick original SELL01 among matching real SKUs")
	if selected.is_empty():
		return {}
	if not pledge:
		check(deliveries.size()>=2,"physical order offers two distinct compatible owned IDs")
	check(action(s,"merchant_order_deliver","o1_ship",{"contract_id":"o1",
		"item_id":selected.item_id,"placement":selected.placement}),
		"physical shop stock delivered, reserved money settles once")
	check(s.snapshot().items.SELL01.owner_id=="order_buyer"
		and s.snapshot().items.SELL01.provenance_id=="original_item"
		and s.snapshot().wallets.escrow.VKC==0,
		"original ownership/provenance and escrow intact")
	check(to_day(s,3,"route"),"D3 real business morning")
	check(action(s,"calendar_next_visit","merc_open"),"generated financed D3 mercenary visit")
	var current:Dictionary=s.calendar_view()
	check(current.npc_visitor.actor_id=="merc_a" and not current.npc_visitor.has("private_trait"),
		"stable mercenary identity without secret trait")
	if buy_d3:
		check(buy_active(s,"d3_merc","merc_trade",0),"D3 actual mercenary good purchased")
	else:
		check(action(s,"calendar_decline_visit","merc_reject",{"visit_id":"d3_merc"}),
			"explicit D3 witness refusal with no transaction")
	check(to_day(s,4,"route"),"D4 real continuation")
	check(action(s,"calendar_next_visit","seller_return"),"same D1 seller returns D4")
	var return_price:int=int(s.calendar_view().regional_market.active_offer.amount)
	check(action(s,"calendar_decline_visit","seller_leave",{"visit_id":"watch_b"}),
		"unpaid D4 offer left untraded")
	check(to_day(s,6,"route"),"D6 real continuation")
	if buy_d3:
		check(action(s,"calendar_next_visit","merc_returns"),"D6 return requires actual D3 trade")
		var v:Dictionary=s.calendar_view()
		var behavior:String=str(s.snapshot().calendar.npc_population.actors.merc_a.private_trait)
		var base:int=int(f.profile.market_flow.entries.d6_merc.prices.ordinary)
		check(v.regional_market.active_offer.amount==base+int(f.profile.npc_bargaining.traits[behavior].seller_delta)-2,
			"repeat customer gets only receipt-backed 2 VKC loyalty")
		check(buy_active(s,"d6_merc","repeat_trade",3),"D6 second pre-existing real good")
	else:
		check(not s.calendar_view().visits.can_next,
			"rejected D3 does not create a phantom D6 repeat visit")
	var saved:Dictionary=s.snapshot()
	var cold:RefCounted=open(f)
	check(cold!=null and cold.restore(saved) and cold.snapshot()==saved,
		"exact deterministic paid/declined route restores cold")
	return {"session":s,"price":return_price,"snapshot":saved}
func _initialize()->void:
	var f:Dictionary=fixture()
	check(not f.is_empty(),"one truly finite 42-day cross-domain profile")
	if f.is_empty():
		quit(1)
		return
	var loan:Dictionary=run(f,true,true)
	var sale:Dictionary=run(f,false,false)
	if loan.is_empty() or sale.is_empty():
		quit(1)
		return
	check(int(loan.price)==int(sale.price)+2,
		"actual D1 purchase changes D4 seller bargaining, pawn alone does not")
	check(loan.snapshot.wallets.player.VKC!=sale.snapshot.wallets.player.VKC,
		"pawn vs purchased and D3 customer choice change cash trajectory")
	var live:RefCounted=loan.session
	check(to_day(live,42,"long"),"continuous common 42-day calendar never ends at D7")
	check(action(live,"calendar_close","last_close")
		and action(live,"calendar_morning","last_morning"),"true final day 42 closure")
	var finished:Dictionary=live.snapshot()
	check(live.calendar_view().complete and finished.game_minutes==60480,
		"42-day boundary correctly separates demo seven")
	check(finished.revision>80 and JSON.stringify(finished).to_utf8_buffer().size()<1048576,
		"bounded 42-day journal+wallet+inventory under one MiB serialized snapshot")
	var frozen:RefCounted=open(f)
	check(frozen!=null and frozen.restore(finished) and frozen.snapshot()==finished,
		"full D42 merchant, NPC, FX and inventory cold replay")
	var fake:Dictionary=finished.duplicate(true)
	fake.wallets.merc_a.VKC+=1
	check(not frozen.restore(fake) and frozen.snapshot()==finished,
		"forged post-D42 wallet denied without corrupting memory")
	print("ALPHA_CROSS_SYSTEM_42DAY: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
