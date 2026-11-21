extends SceneTree
## Deterministic selection of one actually backed visit from two real actors.
const Watch=preload("res://tests/fixtures/p2_watch_state.gd")
const Session=preload("res://src/domain/game_session.gd")
const Slots=preload("res://src/domain/npc_visit_slots.gd")
var checks:int=0
var failures:int=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func fixture(seed:int=121)->Dictionary:
	var original:RefCounted=Watch.fresh()
	if original==null:
		return {}
	var s:Dictionary=original.snapshot()
	var p:Dictionary=s.calendar.profile.duplicate(true)
	s.erase("calendar")
	# W002 belongs to another pre-financed merchant, not a generated owner.
	s.wallets["seller_b"]={"VKC":0,"USD":0}
	s.inventories["seller_b_grid"]={"owner_id":"seller_b","width":4,"height":3,"host_item":""}
	s.items.W002.owner_id="seller_b"
	s.items.W002.custodian_id="seller_b"
	s.items.W002.inventory="seller_b_grid"
	s.visits.watch_b.seller="seller_b"
	p.id="campaign_42"
	p.day_ids=[]
	p.visit_days={}
	for i:int in range(1,43):
		var day:String="d"+str(i)
		p.day_ids.append(day)
		p.visit_days[day]=["watch_a","watch_b"] if i==1 else []
	p["npc_visit_slots"]={"version":1,"seed":seed,"groups":{"morning":{"day_id":"d1","candidates":["watch_a","watch_b"]}}}
	var defs:Dictionary={"fictional_watch_p2":{"def_id":"fictional_watch_p2","category":"fixture","localization_key":"p2.watch.meridian12","render_key":"placeholder_none","width":1,"height":1}}
	return {"initial":s,"profile":p,"defs":defs}

func cmd(s:RefCounted,type:String,id:String,p:Dictionary={})->Dictionary:
	return s.execute({"action_id":id,"expected_revision":s.snapshot().revision,"type":type,"payload":p})

func _initialize()->void:
	var c:Dictionary=fixture()
	check(Slots.valid(c.initial,c.profile),"validated two real funded actors and physical items")
	var bad:Dictionary=c.duplicate(true)
	bad.initial.wallets.erase("seller_b")
	check(not Slots.valid(bad.initial,bad.profile),"unfunded NPC actor rejected")
	bad=c.duplicate(true)
	bad.initial.items.W002.owner_id="seller"
	check(not Slots.valid(bad.initial,bad.profile),"phantom seller item rejected")
	bad=c.duplicate(true)
	bad.profile.npc_visit_slots.groups.morning.candidates=["watch_a","watch_a"]
	check(not Slots.valid(bad.initial,bad.profile),"duplicate visit candidates rejected")
	var first:=Session.new()
	var second:=Session.new()
	check(first.initialize(c.defs,c.initial,false,false,c.profile) and second.initialize(c.defs,c.initial,false,false,c.profile),"opt-in profile seeds real authority")
	if first.snapshot().is_empty() or second.snapshot().is_empty():
		quit(1)
		return
	check(first.calendar_view().visits.remaining==1 and second.calendar_view().visits.remaining==1,"only one valid candidate appears, no fake second visit")
	check(cmd(first,"calendar_next_visit","next_a").get("ok",false) and cmd(second,"calendar_next_visit","next_b").get("ok",false),"both identical seeds open customer")
	var active:String=first.calendar_view().visits.active
	check(active==second.calendar_view().visits.active and active in ["watch_a","watch_b"],"stable choice across fresh sessions")
	var seller:String="seller" if active=="watch_a" else "seller_b"
	var item:String="W001" if active=="watch_a" else "W002"
	check(first.calendar_view().visits.terms.seller==seller,"actual current guest owns presented item")
	check(cmd(first,"trade","physical_trade",{"visit_id":active,"item_id":item,"seller":seller,
		"buyer":"player","currency":"VKC","amount":90,"inventory":"player_grid","x":0,"y":0,"rotated":false}).get("ok",false),"actual player purchase of selected stocked item")
	var snap:Dictionary=first.snapshot()
	check(snap.items[item].owner_id=="player" and snap.wallets[seller].VKC==90 and snap.wallets.player.VKC==90,
		"ordinary GameSession ownership and payment exactly")
	check(snap.items["W002" if item=="W001" else "W001"].owner_id!= "player",
		"unselected item remains real customer property")
	check(snap.ledger.size()==1 and first.calendar_view().visits.remaining==0,
		"no second future client or phantom trade after selected visit")
	var cold:=Session.new()
	check(cold.initialize(c.defs,c.initial,false,false,c.profile) and cold.restore(snap) and cold.snapshot()==snap,
		"saved random choice and real receipt survive cold replay")
	var variants:Dictionary={}
	for n:int in range(0,16):
		var trial:Dictionary=fixture(n)
		var x:=Session.new()
		if x.initialize(trial.defs,trial.initial,false,false,trial.profile):
			variants[Slots._choice(n,"d1","morning",["watch_a","watch_b"])]=true
	check(variants.size()==2,"different world seeds can pick either existing backed customer")
	print("NPC_VISIT_SLOTS: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
