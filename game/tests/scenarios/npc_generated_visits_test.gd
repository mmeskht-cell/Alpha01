extends SceneTree
## An actual D3 mercenary encounter materialized from finite authored
## actor, physical item and original money, before GameSession replay seed.
const Watch=preload("res://tests/fixtures/p2_watch_state.gd")
const Objects=preload("res://src/domain/object_schema.gd")
const Session=preload("res://src/domain/game_session.gd")
const VisitSource=preload("res://src/domain/npc_generated_visits.gd")
var checks:int=0
var failures:int=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func money(v:int)->Dictionary:
	return {"VKC":v,"USD":0}

func fixture(seed:int=26)->Dictionary:
	var src:RefCounted=Watch.fresh(false)
	if src==null:
		return {}
	var s:Dictionary=src.snapshot()
	var p:Dictionary=s.calendar.profile.duplicate(true)
	s.erase("calendar")
	p.id="campaign_42"
	p.day_ids=[]
	p.visit_days={}
	for n:int in range(1,43):
		var d:String="d"+str(n)
		p.day_ids.append(d)
		p.visit_days[d]=["watch_a","watch_b"] if n==1 else []
	for row:Array in [["merc_a","A100",0],["merc_b","B100",1]]:
		var actor:String=row[0]
		var item:String=row[1]
		s.wallets[actor]=money(70)
		s.inventories[actor+"_grid"]={"owner_id":actor,"width":4,"height":3,"host_item":""}
		s.items[item]=Objects.fresh_item("fictional_watch_p2",actor,actor+"_grid",int(row[2]),0,"real_merc_stock")
	p["regional_world"]={"version":1,"regions":{"market_quarter":{"status":"ordinary"}},
		"events":{},"gates":{}}
	p["market_flow"]={"version":1,"flow_step":0,"max_flow_delta":0,"buyers":{},
		"entries":{"watch_a":{"region":"market_quarter","category":"civilian_goods",
			"item_id":"W001","def_id":"fictional_watch_p2","currency":"VKC",
			"prices":{"ordinary":90,"strained":90,"limited":90}}}}
	p["npc_population"]={"version":1,"seed":1001,"actors":{
		"merc_a":{"kind":"mercenary","region":"market_quarter"},
		"merc_b":{"kind":"scavenger","region":"market_quarter"},
		"seller":{"kind":"mercenary","region":"market_quarter"}}}
	p["npc_generated_visits"]={"version":1,"seed":seed,"slots":{"d3_merc_guest":{
		"day_id":"d3","region":"market_quarter",
		"candidates":[
			{"actor":"merc_a","item_id":"A100","price":money(65),"side":"offer"},
			{"actor":"merc_b","item_id":"B100","price":money(75),"side":"offer"}]}}}
	var defs:Dictionary={"fictional_watch_p2":{"def_id":"fictional_watch_p2",
		"category":"fixture","localization_key":"p2.watch.meridian12",
		"render_key":"placeholder_none","width":1,"height":1}}
	return {"state":s,"profile":p,"defs":defs}

func cmd(s:RefCounted,kind:String,id:String,p:Dictionary={})->Dictionary:
	return s.execute({"action_id":id,"expected_revision":s.snapshot().revision,"type":kind,"payload":p})

func _initialize()->void:
	var f:Dictionary=fixture()
	check(not f.is_empty(),"finite authored mercenary pool")
	var a:Dictionary=VisitSource.expand(f.state,f.profile)
	var b:Dictionary=VisitSource.expand(f.state,f.profile)
	check(not a.is_empty() and a==b,"same seed materializes exactly the same physical visit")
	var invalid:Dictionary=f.duplicate(true)
	invalid.profile.npc_generated_visits.slots.d3_merc_guest.candidates[1].actor="missing_wallet"
	check(VisitSource.expand(invalid.state,invalid.profile).is_empty(),"no fake visitor with missing wallet")
	invalid=f.duplicate(true)
	invalid.state.items.B100.owner_id="player"
	check(VisitSource.expand(invalid.state,invalid.profile).is_empty(),"no newly invented inventory ownership")
	invalid=f.duplicate(true)
	invalid.profile.npc_population.actors.merc_b.kind="civilian"
	check(VisitSource.expand(invalid.state,invalid.profile).is_empty(),"no random civilian visitor (NPC_SCOPE)")
	var s:=Session.new()
	check(s.initialize(f.defs,f.state,false,false,f.profile),"new visitor seeded via real campaign calendar")
	if s.snapshot().is_empty():
		printerr("VISIT_SOURCE_INIT ",s.initialization_error())
		quit(1)
		return
	var grown:Dictionary=s.snapshot()
	check(grown.visits.has("d3_merc_guest") and grown.visits.size()==3
		and grown.calendar.profile.visit_days.d3==["d3_merc_guest"],
		"one selected visit exists in the true GameSession state and schedule")
	check(not s.calendar_view().has("npc_visitor") and not s.calendar_view().visits.active,
		"no D3 guest disclosed on D1")
	check(cmd(s,"calendar_close","close_d1").get("ok",false)
		and cmd(s,"calendar_morning","morning_d2").get("ok",false)
		and cmd(s,"calendar_close","close_d2").get("ok",false)
		and cmd(s,"calendar_morning","morning_d3").get("ok",false),
		"two genuine days transition to generated D3 visit")
	check(cmd(s,"calendar_next_visit","admit_generated").get("ok",false),
		"automatic generated encounter admitted to the normal queue")
	var view:Dictionary=s.calendar_view()
	var t:Dictionary=view.visits.terms
	var item_id:String=str(t.prices.keys()[0])
	var actor:String=t.seller
	check(actor in ["merc_a","merc_b"] and item_id==("A100" if actor=="merc_a" else "B100"),
		"guest presents the same item it already physically owned")
	check(view.npc_visitor.actor_id==actor and not view.npc_visitor.has("private_trait"),
		"actual generated customer has stable non-leaking personality")
	var price:int=int(t.prices[item_id].VKC)
	check(cmd(s,"trade","paid_d3",{"visit_id":"d3_merc_guest","item_id":item_id,
		"seller":actor,"buyer":"player","currency":"VKC","amount":price,
		"inventory":"player_grid","x":0,"y":0,"rotated":false}).get("ok",false),
		"ordinary player trade settles real newly scheduled guest with existing authority")
	var actual:Dictionary=s.snapshot()
	check(actual.items[item_id].owner_id=="player" and actual.wallets[actor].VKC==70+price
		and actual.ledger.size()==1,
		"both real item ownership and customer funds change once")
	var other:String="B100" if item_id=="A100" else "A100"
	check(actual.items[other].owner_id!= "player","alternate candidate never sold or minted a good")
	var cold:=Session.new()
	check(cold.initialize(f.defs,f.state,false,false,f.profile)
		and cold.restore(actual) and cold.snapshot()==actual,
		"seeded D3 visit and actual item receipt survive cold deterministic replay")
	var variants:Dictionary={}
	for n:int in range(0,12):
		var sample:Dictionary=fixture(n)
		var candidate:Dictionary=VisitSource.expand(sample.state,sample.profile)
		if not candidate.is_empty():
			var v:Dictionary=candidate.state.visits.d3_merc_guest
			variants[v.seller]=true
	check(variants.size()==2,"distinct world seeds choose either already-funded mercenary")
	print("NPC_GENERATED_VISITS: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
