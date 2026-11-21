extends SceneTree
## Real 42-day six-visit capacity without minting actors, goods or cash.
## Re-offer the same finite stock on later days only while still owned.
const Watch=preload("res://tests/fixtures/p2_watch_state.gd")
const Session=preload("res://src/domain/game_session.gd")
const Objects=preload("res://src/domain/object_schema.gd")
const Generated=preload("res://src/domain/npc_generated_visits.gd")
const Queue=preload("res://src/domain/campaign_visit_queue.gd")
const Clock=preload("res://src/domain/business_clock.gd")
var count:int=0
var fails:int=0
func check(ok:bool,label:String)->void:
	count+=1
	if not ok:
		fails+=1
		printerr("FAIL: "+label)
func money(n:int)->Dictionary:
	return {"VKC":n,"USD":0}
func fixture()->Dictionary:
	var starter:RefCounted=Watch.fresh(false)
	if starter==null:
		return {}
	var s:Dictionary=starter.snapshot()
	var p:Dictionary=s.calendar.profile.duplicate(true)
	s.erase("calendar")
	p.id="campaign_42"
	p.day_ids=[]
	p.visit_days={}
	for d:int in range(1,43):
		var key:String="d"+str(d)
		p.day_ids.append(key)
		p.visit_days[key]=["watch_a","watch_b"] if d==1 else []
	p["regional_world"]={"version":1,
		"regions":{"quarter":{"status":"ordinary"}},"events":{},"gates":{}}
	p["market_flow"]={"version":1,"flow_step":0,"max_flow_delta":0,
		"buyers":{},"entries":{}}
	var actors:Dictionary={}
	for n:int in range(6):
		var actor:String="seller_"+str(n)
		actors[actor]={"kind":"mercenary","region":"quarter"}
		s.wallets[actor]=money(100)
		s.inventories[actor+"_grid"]={"owner_id":actor,"width":4,"height":3,"host_item":""}
		for opt:int in range(2):
			var item_id:String=actor+"_item_"+str(opt)
			s.items[item_id]=Objects.fresh_item("fictional_watch_p2",actor,actor+"_grid",opt,0,"real_42day_supply")
	p["npc_population"]={"version":1,"seed":7242,"actors":actors}
	var slots:Dictionary={}
	for day:int in range(1,43):
		for n:int in range(2 if day==1 else 0,6):
			var slot_id:String="guest_"+str(day).pad_zeros(2)+"_"+str(n)
			var actor:String="seller_"+str(n)
			slots[slot_id]={"day_id":"d"+str(day),"region":"quarter",
				"candidates":[
				{"actor":actor,"item_id":actor+"_item_0","price":money(25),"side":"offer"},
				{"actor":actor,"item_id":actor+"_item_1","price":money(25),"side":"offer"}]}
	check(slots.size()==250,"250 future appointment slots plus two actual fixed D1 customers")
	p["npc_generated_visits"]={"version":1,"seed":904,"slots":slots}
	var realized:Dictionary=Generated.expand(s,p)
	if realized.is_empty():
		return {}
	for id:String in slots:
		var visit:Dictionary=realized.state.visits[id]
		var good:String=str(visit.prices.keys()[0])
		p.market_flow.entries[id]={"region":"quarter","category":"watch","item_id":good,
			"def_id":"fictional_watch_p2","currency":"VKC",
			"prices":{"ordinary":25,"strained":25,"limited":25}}
	var defs:Dictionary={"fictional_watch_p2":{"def_id":"fictional_watch_p2","category":"fixture",
		"localization_key":"p2.watch.meridian12","render_key":"placeholder_none",
		"width":1,"height":1}}
	return {"seed":s,"profile":p,"defs":defs}
func command(s:RefCounted,kind:String,p:Dictionary={})->bool:
	var r:Dictionary=s.execute({"type":kind,"payload":p,
		"action_id":"traffic_"+str(s.snapshot().revision+1),
		"expected_revision":s.snapshot().revision})
	if not r.get("ok",false):
		printerr("TRAFFIC_BAD_COMMAND "+kind+" "+str(r.get("error","")))
	return bool(r.get("ok",false))
func _initialize()->void:
	var f:Dictionary=fixture()
	check(not f.is_empty(),"all 250 generated physical visits are finite and authentically owned")
	if f.is_empty():
		quit(1)
		return
	var s:=Session.new()
	check(s.initialize(f.defs,f.seed,false,false,f.profile),"single GameSession seeded from 42-day visit capacity data")
	if s.snapshot().is_empty():
		printerr("TRAFFIC_INIT "+s.initialization_error())
		quit(1)
		return
	var start:Dictionary=s.snapshot()
	check(start.visits.size()==252 and start.items.size()==14,
		"252 visit IDs reuse exactly 12 mercenary items and the original 2")
	var final_month:Dictionary={}
	var week_1:int=0
	var week_6:int=0
	var valid:bool=true
	for day:int in range(1,43):
		var remaining:int=int(s.calendar_view().visits.remaining)
		if day==1:
			week_1=remaining
		if day==42:
			week_6=remaining
		if remaining!=6:
			printerr("FAIL: D",day," expected 6 physically backed appointments but got ",remaining)
			valid=false
			break
		if not command(s,"calendar_close"):
			valid=false
			break
		if not command(s,"calendar_morning"):
			valid=false
			break
	check(valid and week_1==6 and week_6==6,
		"6 real funded ordinary visit opportunities on all 42 days without stock creation")
	check(s.calendar_view().complete and s.snapshot().game_minutes==60480,
		"schedule closes at true 42-day boundary")
	var end_state:Dictionary=s.snapshot()
	check(end_state.items.size()==start.items.size() and
		end_state.wallets.size()==start.wallets.size() and
		end_state.calendar.queue.outcomes.size()==252,
		"untraded goods, wallets and all 252 witnessed/missed opportunities conserved")
	var bytes:int=JSON.stringify(end_state).to_utf8_buffer().size()
	print("ALPHA42_TRAFFIC_BYTES: ",bytes)
	check(bytes<1048576,"42-day 250 appointments with no omitted history fit 1MiB JSON")
	var cold:=Session.new()
	check(cold.initialize(f.defs,f.seed,false,false,f.profile) and cold.restore(end_state)
		and cold.snapshot()==end_state,"42-day 252-appointment calendar survives full cold replay")
	var forged:Dictionary=end_state.duplicate(true)
	forged.wallets.seller_1.VKC+=1
	check(not cold.restore(forged) and cold.snapshot()==end_state,
		"no silent newly minted NPC cash on cold replay")
	var alternate:=Session.new()
	check(alternate.initialize(f.defs,f.seed,false,false,f.profile),
		"fresh independently playable trade route opens")
	check(command(alternate,"calendar_next_visit") and
		command(alternate,"calendar_decline_visit",{"visit_id":"watch_a"}) and
		command(alternate,"calendar_next_visit") and
		command(alternate,"calendar_decline_visit",{"visit_id":"watch_b"}),
		"authored first customers respectfully declined without fiat changes")
	check(command(alternate,"calendar_next_visit"),"genuine selected mercenary enters D1")
	var active:String=str(alternate.calendar_view().visits.active)
	var v:Dictionary=alternate.calendar_view().visits.terms
	var id:String=str(v.prices.keys()[0])
	check(command(alternate,"trade",{"visit_id":active,"item_id":id,
		"seller":v.seller,"buyer":"player","currency":"VKC","amount":25,
		"inventory":"player_grid","x":0,"y":0,"rotated":false}),
		"first sold stock changes real ownership once")
	var same_good:String=""
	for visit_id:String in alternate.snapshot().visits:
		var later:Dictionary=alternate.snapshot().visits[visit_id]
		if later.opens>0 and later.seller==v.seller and later.prices.has(id):
			same_good=visit_id
			break
	check(not same_good.is_empty() and not Queue.eligible(alternate.snapshot(),same_good),
		"future re-offer of sold stock disabled; cannot transact ghosts")
	print("ALPHA42_TRAFFIC_CAPACITY: ",count," checks, ",fails," failures")
	quit(0 if fails==0 else 1)
