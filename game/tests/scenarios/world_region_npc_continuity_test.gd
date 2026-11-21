extends SceneTree
const Watch=preload("res://tests/fixtures/p2_watch_state.gd")
const Session=preload("res://src/domain/game_session.gd")
const Rules=preload("res://src/domain/value_rules.gd")
const Regional=preload("res://src/domain/regional_world_state.gd")
const Npc=preload("res://src/domain/npc_continuity.gd")
const Queue=preload("res://src/domain/campaign_visit_queue.gd")
var checks:int=0
var failures:int=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func content()->Dictionary:
	var old:RefCounted=Watch.fresh()
	if old==null:
		return {}
	var state:Dictionary=old.snapshot()
	var profile:Dictionary=state.calendar.profile.duplicate(true)
	state.erase("calendar")
	# W001 sold on Day1, W002 optionally presented to that SAME returning
	# seller on Day2, without creating unbounded NPC wallets or product IDs.
	state.visits.watch_b.opens=1440
	state.visits.watch_b.expires=2040
	profile.visit_days.d1=["watch_a"]
	profile.visit_days.d2=["watch_b"]
	profile["npc_continuity"]={"version":1,"gates":{"watch_b":{"prior_visit":"watch_a","outcome":"traded"}}}
	profile["regional_world"]={"version":1,
		"regions":{"market_quarter":{"status":"ordinary"},"old_quarter":{"status":"ordinary"}},
		"events":{"market_d2":{"day":2,"region":"market_quarter","topic":"civilian_supply",
			"without_player":"strained","with_player":"limited",
			"cause_visit":"watch_a","source":"local_market_notice"}},
		"gates":{"watch_b":{"event_id":"market_d2","status":"limited"}}}
	var defs:Dictionary={"fictional_watch_p2":{"def_id":"fictional_watch_p2","category":"fixture","localization_key":"p2.watch.meridian12","render_key":"placeholder_none","width":1,"height":1}}
	return {"state":state,"profile":profile,"defs":defs}

func execute(s:RefCounted,kind:String,id:String,p:Dictionary={})->bool:
	var command:Dictionary={"action_id":id,"expected_revision":s.snapshot().revision,"type":kind,"payload":p}
	var r:Dictionary=s.execute(command)
	if not r.get("ok",false):
		printerr("WORLD_SCOPE_REJECT ",kind," ",r)
	return r.get("ok",false)

func route(c:Dictionary,paid:bool)->Dictionary:
	var s:=Session.new()
	if not s.initialize(c.defs,c.state,false,false,c.profile):
		return {"ok":false,"error":s.initialization_error()}
	if not execute(s,"calendar_next_visit","first_visit"):
		return {"ok":false}
	if paid:
		var buy:Dictionary={"visit_id":"watch_a","item_id":"W001","seller":"seller","buyer":"player",
			"currency":"VKC","amount":90,"inventory":"player_grid","x":0,"y":0,"rotated":false}
		if not execute(s,"trade","settled",buy):
			return {"ok":false}
	else:
		if not execute(s,"calendar_decline_visit","refused",{"visit_id":"watch_a"}):
			return {"ok":false}
	if not execute(s,"calendar_close","close_d1") or not execute(s,"calendar_morning","morning_d2"):
		return {"ok":false}
	return {"ok":true,"session":s}

func _initialize()->void:
	var c:Dictionary=content()
	check(not c.is_empty(),"opt-in authored two-region fixture")
	if c.is_empty():
		quit(1)
		return
	var paid:Dictionary=route(c,true)
	var refused:Dictionary=route(c,false)
	check(paid.get("ok",false) and refused.get("ok",false),"real trade or real decline two branches")
	if not paid.get("ok",false) or not refused.get("ok",false):
		quit(1)
		return
	var a:RefCounted=paid.session
	var b:RefCounted=refused.session
	var p:Dictionary=a.calendar_view()
	var q:Dictionary=b.calendar_view()
	check(p.world_regions.events.size()==1 and p.world_regions.events[0].status=="limited" and p.world_regions.events[0].cause_refs==["market_d2","settled"],"paid supply affects local report with actual receipt")
	check(q.world_regions.events.size()==1 and q.world_regions.events[0].status=="strained" and q.world_regions.events[0].cause_refs==["market_d2"],"independent shortage occurs without player money")
	check(p.world_regions.regions.market_quarter=="limited" and q.world_regions.regions.market_quarter=="strained" and p.world_regions.regions.old_quarter=="ordinary","local rather than city-wide impact")
	check(Regional.eligible(a.snapshot(),"watch_b") and Npc.eligible(a.snapshot(),"watch_b") and p.visits.can_next,"real response and actual prior sale unlock authored follow-up")
	check(not Regional.eligible(b.snapshot(),"watch_b") and not Npc.eligible(b.snapshot(),"watch_b") and not q.visits.can_next,"declining does not invent a successful customer agreement")
	check(a.snapshot().wallets.player.VKC==75 and b.snapshot().wallets.player.VKC==165,"actual 90 transfer, 15 daily overhead and no invented grant")
	check(a.snapshot().items.W001.owner_id=="player" and b.snapshot().items.W001.owner_id=="seller","property stays route-specific")
	check(Npc.visible_history(a.snapshot(),"seller").get("trades")==1 and Npc.visible_history(b.snapshot(),"seller").get("declines")==1,"two remembered first-hand outcomes, no fake private affection")
	var replay:=Session.new()
	var saved:Dictionary=a.snapshot()
	check(replay.initialize(c.defs,c.state,false,false,c.profile) and replay.restore(saved) and replay.snapshot()==saved,"actual world state replays after save")
	var tampered:Dictionary=saved.duplicate(true)
	tampered.calendar.regional_world.events.market_d2.status="strained"
	check(not replay.restore(tampered) and replay.snapshot()==saved,"forged world result cannot survive replay")
	var invalid:Dictionary=c.duplicate(true)
	invalid.profile.regional_world.events.market_d2.cause_visit="future_unknown"
	check(not Regional.seed_valid(invalid.state,invalid.profile),"unbacked player world event rejected at seed")
	invalid=c.duplicate(true)
	invalid.profile.npc_continuity.gates.watch_b.prior_visit="future_unknown"
	check(not Npc.seed_valid(invalid.state,invalid.profile),"unbacked customer memory gate rejected")
	print("WORLD_REGION_NPC_CONTINUITY: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
