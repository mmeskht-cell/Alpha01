extends SceneTree
## A real opt-in 42-day exchange on the common GameSession wallet authority.
const Watch=preload("res://tests/fixtures/p2_watch_state.gd")
const Session=preload("res://src/domain/game_session.gd")
const Finance=preload("res://src/domain/calendar_exchange_market.gd")
var checks:int=0
var failures:int=0

func check(value:bool,label:String)->void:
	checks+=1
	if not value:
		failures+=1
		printerr("FAIL: ",label)

func fixture()->Dictionary:
	var original:RefCounted=Watch.fresh()
	if original==null:
		return {}
	var s:Dictionary=original.snapshot()
	var profile:Dictionary=s.calendar.profile.duplicate(true)
	s.erase("calendar")
	s.wallets["broker"]={"VKC":0,"USD":3}
	s.inventories["broker_grid"]={"owner_id":"broker","width":4,"height":3,"host_item":""}
	profile.id="campaign_42"
	profile.day_ids=[]
	profile.visit_days={}
	for i:int in range(1,43):
		var day:String="d"+str(i)
		profile.day_ids.append(day)
		profile.visit_days[day]=["watch_a","watch_b"] if i==1 else []
	profile["exchange_market"]={"version":1,"quotes":{
		"morning_fx":{"counterparty":"broker","give_currency":"VKC","give_amount":100,
			"receive_currency":"USD","receive_amount":2,"first_day":1,"last_day":2},
		"no_liquidity":{"counterparty":"broker","give_currency":"VKC","give_amount":10,
			"receive_currency":"USD","receive_amount":3,"first_day":1,"last_day":1}}}
	var defs:Dictionary={"fictional_watch_p2":{"def_id":"fictional_watch_p2","category":"fixture",
		"localization_key":"p2.watch.meridian12","render_key":"placeholder_none","width":1,"height":1}}
	return {"defs":defs,"seed":s,"profile":profile}

func command(s:RefCounted,type:String,id:String,p:Dictionary)->Dictionary:
	return s.execute({"action_id":id,"expected_revision":s.snapshot().revision,"type":type,"payload":p})

func _initialize()->void:
	var f:Dictionary=fixture()
	check(not f.is_empty(),"fixture exists")
	var s:=Session.new()
	check(s.initialize(f.defs,f.seed,false,false,f.profile),"opt in 42d seed uses finite broker USD")
	if s.snapshot().is_empty():
		quit(1)
		return
	check(s.calendar_view().exchange_market.quotes.size()==2,"only public quotes exposed")
	check(not s.calendar_view().exchange_market.has("broker_wallet"),"counterparty liquidity private")
	var starting:Dictionary=s.snapshot()
	check(not command(s,"calendar_exchange","bad_fx",{"quote_id":"fake"}).get("ok",false)
		and s.snapshot()==starting,"unknown quote rejects atomically")
	check(not command(s,"calendar_exchange","too_little",{"quote_id":"morning_fx","give_amount":1}).get("ok",false)
		and s.snapshot()==starting,"cannot override quoted FX amounts")
	check(command(s,"calendar_exchange","fx_once",{"quote_id":"morning_fx"}).get("ok",false),"valid finite transfer")
	var snap:Dictionary=s.snapshot()
	check(snap.wallets.player=={"VKC":80,"USD":2} and snap.wallets.broker=={"VKC":100,"USD":1},
		"FX balances conserve both currencies across two real actors")
	check(snap.ledger.is_empty() and snap.calendar.exchange_market.settlements.size()==1,
		"no synthetic goods trade or counterfeit ledger row")
	check(s.calendar_view().exchange_market.quotes.size()==1,"consumed quote not advertised")
	check(not command(s,"calendar_exchange","fx_twice",{"quote_id":"morning_fx"}).get("ok",false)
		and s.snapshot()==snap,"one-quote per exact finite allocation")
	check(not command(s,"calendar_exchange","insufficient",{"quote_id":"no_liquidity"}).get("ok",false)
		and s.snapshot()==snap,"broker cannot mint absent USD")
	var retry:Dictionary=s.execute({"action_id":"fx_once","expected_revision":0,"type":"calendar_exchange","payload":{"quote_id":"morning_fx"}})
	check(retry.get("ok",false) and s.snapshot()==snap,"idempotent identical receipt")
	var cold:=Session.new()
	check(cold.initialize(f.defs,f.seed,false,false,f.profile) and cold.restore(snap) and cold.snapshot()==snap,
		"cold deterministic replay of FX settlement")
	var forgery:Dictionary=snap.duplicate(true)
	forgery.wallets.player.USD+=1
	check(not cold.restore(forgery) and cold.snapshot()==snap,"no forged USD on load")
	var bad:Dictionary=f.profile.duplicate(true)
	bad.exchange_market.quotes.morning_fx.counterparty="absent_actor"
	check(Finance.seed(f.seed,bad).is_empty(),"no phantom FX money source")
	bad=f.profile.duplicate(true)
	bad.exchange_market.quotes.morning_fx.receive_amount=-10
	check(Finance.seed(f.seed,bad).is_empty(),"negative price rejected")
	print("CALENDAR_EXCHANGE_MARKET: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
