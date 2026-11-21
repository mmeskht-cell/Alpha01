extends SceneTree
## Stage5: Add D8 SKU, funded NPC and D9 conditional fact without altering
## GameSession, Calendar or the seven-day canonical seed.
const Watch=preload("res://tests/fixtures/p2_watch_state.gd")
const Context=preload("res://tests/fixtures/gate0_c_state.gd")
const Session=preload("res://src/domain/game_session.gd")
const Objects=preload("res://src/domain/object_schema.gd")
var checks:int=0
var failures:int=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func money(n:int)->Dictionary:
	return {"VKC":n,"USD":0}

func fixture()->Dictionary:
	var baseline:RefCounted=Watch.fresh(false)
	if baseline==null:
		return {}
	var state:Dictionary=baseline.snapshot()
	var profile:Dictionary=state.calendar.profile.duplicate(true)
	state.erase("calendar")
	profile.id="campaign_42"
	profile.day_ids=[]
	profile.visit_days={}
	for n:int in range(1,43):
		var day:String="d"+str(n)
		profile.day_ids.append(day)
		profile.visit_days[day]=["watch_a","watch_b"] if n==1 else []
	profile.visit_days.d8=["new_supplier_offer"]
	profile["contracts"]={}
	profile["story_rules"]={"probe_after_sale":{"day":9,"source":"trade",
		"source_id":"new_supplier_offer","outcome":"traded","text_key":"story.probe_after_sale"}}
	state.wallets["new_supplier"]=money(0)
	state.inventories["new_supplier_grid"]={"owner_id":"new_supplier",
		"width":4,"height":3,"host_item":""}
	state.items["D08_SAMPLE"]=Objects.fresh_item("fixture_daily_tool","new_supplier",
		"new_supplier_grid",0,0,"future_provenance_from_authored_data")
	var v:Dictionary=Context.visit("new_supplier_offer","new_supplier","player",
		{"D08_SAMPLE":money(50)})
	v.opens=7*1440
	v.expires=v.opens+600
	state.visits["new_supplier_offer"]=v
	var defs:Dictionary={
		"fictional_watch_p2":{"def_id":"fictional_watch_p2","category":"fixture",
			"localization_key":"p2.watch.meridian12","render_key":"placeholder_none",
			"width":1,"height":1},
		"fixture_daily_tool":{"def_id":"fixture_daily_tool","category":"fixture",
			"localization_key":"item.demo_tool","render_key":"placeholder_none",
			"width":2,"height":1}}
	return {"defs":defs,"state":state,"profile":profile}

func command(s:RefCounted,type:String,id:String,p:Dictionary={})->Dictionary:
	return s.execute({"action_id":id,"expected_revision":s.snapshot().revision,
		"type":type,"payload":p})

func day8(c:Dictionary)->RefCounted:
	var s:=Session.new()
	if not s.initialize(c.defs,c.state,false,false,c.profile):
		printerr("GROWTH_INIT: ",s.initialization_error())
		return null
	for day:int in range(1,8):
		if not command(s,"calendar_close","close_"+str(day)).get("ok",false):
			return null
		if not command(s,"calendar_morning","morning_"+str(day+1)).get("ok",false):
			return null
	return s

func _initialize()->void:
	var c:Dictionary=fixture()
	check(not c.is_empty(),"new SKU and funded actor data fixture")
	if c.is_empty():
		quit(1)
		return
	var purchased:RefCounted=day8(c)
	var declined:RefCounted=day8(c)
	check(purchased!=null and declined!=null,"both branches reach a real D8 without new engine code")
	if purchased==null or declined==null:
		quit(1)
		return
	check(purchased.calendar_view().day==8 and purchased.snapshot().wallets.player.VKC==75,
		"seven overheads and D8 content loaded within 42-day common calendar")
	check(purchased.calendar_view().visits.remaining==1,"new actor visit is a real dated visit")
	check(command(purchased,"calendar_next_visit","open_new").get("ok",false)
		and command(declined,"calendar_next_visit","open_refused").get("ok",false),
		"both branches admit genuine future visitor")
	var terms:Dictionary=purchased.calendar_view().visits.terms
	check(terms.seller=="new_supplier" and terms.prices.D08_SAMPLE.VKC==50,
		"new item definition and customer budget valid")
	check(command(purchased,"trade","new_goods_paid",{"visit_id":"new_supplier_offer",
		"item_id":"D08_SAMPLE","seller":"new_supplier","buyer":"player","currency":"VKC",
		"amount":50,"inventory":"player_grid","x":0,"y":0,"rotated":false}).get("ok",false),
		"new SKU moved using unchanged atomic trade command")
	check(command(declined,"calendar_decline_visit","new_goods_refused",
		{"visit_id":"new_supplier_offer"}).get("ok",false),
		"refusal does not transfer new commodity")
	check(purchased.snapshot().items.D08_SAMPLE.owner_id=="player"
		and purchased.snapshot().wallets.new_supplier.VKC==50
		and purchased.snapshot().wallets.player.VKC==25,
		"new catalog data preserves actual funds and original item ID")
	check(declined.snapshot().items.D08_SAMPLE.owner_id=="new_supplier"
		and declined.snapshot().ledger.is_empty(),
		"refused branch keeps exact backing goods and no sale")
	for pair:Array in [[purchased,"sale"],[declined,"refusal"]]:
		var s:RefCounted=pair[0]
		var label:String=pair[1]
		check(command(s,"calendar_close","d8_close_"+label).get("ok",false)
			and command(s,"calendar_morning","d9_morning_"+label).get("ok",false),
			"same data-driven D9 opening after "+label)
	check(purchased.calendar_view().obligations.facts.has("probe_after_sale"),
		"real trade receipt activates conditional story event fact")
	check(not declined.calendar_view().obligations.facts.has("probe_after_sale"),
		"same event cannot arise from declined sale")
	var fact:Dictionary=purchased.calendar_view().obligations.facts.get("probe_after_sale",{})
	check(fact.get("cause_action")=="new_goods_paid"
		and fact.get("text_key")=="story.probe_after_sale",
		"future story hook records exact verified cause, not a fabricated narrative")
	var final_state:Dictionary=purchased.snapshot()
	var cold:=Session.new()
	check(cold.initialize(c.defs,c.state,false,false,c.profile)
		and cold.restore(final_state) and cold.snapshot()==final_state,
		"42-day profile save and D9 conditional fact survive cold replay")
	var fake:Dictionary=final_state.duplicate(true)
	fake.calendar.contracts.facts.probe_after_sale.cause_action="fabricated_action"
	check(not cold.restore(fake) and cold.snapshot()==final_state,
		"fabricated conditional story fact cannot be restored")
	print("ALPHA_CONTENT_GROWTH: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
