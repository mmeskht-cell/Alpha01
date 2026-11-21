extends SceneTree
## A 42-day profile with 33 genuine watch visits, 132 instrument readings.
## Unlike synthetic state edits, EVERY reading is a GameSession command.
const Watch=preload("res://tests/fixtures/p2_watch_state.gd")
const Session=preload("res://src/domain/game_session.gd")
const Objects=preload("res://src/domain/object_schema.gd")
const Retention=preload("res://src/domain/appraisal_history_retention.gd")
const Rules=preload("res://src/domain/value_rules.gd")
const Checkpoint=preload("res://src/persistence/checkpoint_format.gd")
var checks:int=0
var failures:int=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func command(s:RefCounted,kind:String,id:String,p:Dictionary={})->bool:
	var result:Dictionary=s.execute({"action_id":id,"expected_revision":s.snapshot().revision,"type":kind,"payload":p})
	if not result.get("ok",false):
		printerr("LONG_RETENTION_REJECT ",kind," ",id," ",result)
	return result.get("ok",false)

func fixture()->Dictionary:
	var old:RefCounted=Watch.fresh()
	if old==null:
		return {}
	var state:Dictionary=old.snapshot()
	state.erase("calendar")
	var visits:Dictionary={}
	var ids:Array=[]
	var schedule:Dictionary={}
	for day:int in range(1,43):
		var day_id:String="d"+str(day)
		ids.append(day_id)
		schedule[day_id]=[]
	for i:int in range(33):
		var day:int=int(i/8)+1
		var id:String="history_"+str(i)
		var row:Dictionary=state.visits.watch_a.duplicate(true)
		row.scope.visit_id=id
		row.opens=(day-1)*1440
		row.expires=row.opens+600
		visits[id]=row
		schedule["d"+str(day)].append(id)
	state.visits=visits
	var profile:Dictionary={"id":"campaign_42","content_version":"p2-watch-authority-1","day_ids":ids,"visit_days":schedule,"appraisal_profile":"watch_p2_v1","observation_retention":"lossless_v1"}
	var defs:Dictionary={"fictional_watch_p2":{"def_id":"fictional_watch_p2","category":"fixture","localization_key":"p2.watch.meridian12","render_key":"placeholder_none","width":1,"height":1}}
	return {"defs":defs,"state":state,"profile":profile}

func _initialize()->void:
	var content:Dictionary=fixture()
	check(not content.is_empty(),"fixture creation")
	if content.is_empty():
		quit(1)
		return
	var s:=Session.new()
	check(s.initialize(content.defs,content.state,false,false,content.profile),"42day opt-in initialization "+s.initialization_error())
	if s.initialization_error()!="":
		quit(1)
		return
	var tools:Array=[
		["wear_detail","dial_face"],["batch_detail","back_mark"],
		["material_detail","case_surface"],["function_detail","whole_function"]
	]
	for i:int in range(33):
		var day:int=int(i/8)+1
		var visit:String="history_"+str(i)
		if not command(s,"calendar_next_visit","admit_"+str(i)):
			check(false,"admit "+visit)
			break
		for k:int in range(tools.size()):
			var row:Array=tools[k]
			if not command(s,"inspect_subject","ob_"+str(i)+"_"+str(k),{"visit_id":visit,"item_id":"W001","tool_id":row[0],"target":row[1]}):
				check(false,"actual four-tool appraisal "+visit)
				break
		if not command(s,"calendar_decline_visit","decline_"+str(i),{"visit_id":visit}):
			check(false,"decline "+visit)
			break
		if i==7 or i==15 or i==23 or i==31:
			if not command(s,"calendar_close","close_"+str(day)) or not command(s,"calendar_morning","morning_"+str(day)):
				check(false,"next day "+str(day))
				break
	var saved:Dictionary=s.snapshot()
	var retained:Dictionary=Retention.records(saved)
	check(retained.size()==132,"full 132 independently receipted observations retained")
	check(saved.calendar.appraisal_observations.size()<=Retention.MAX_ACTIVE and saved.calendar.appraisal_observation_archive.size()==4,"128 active and 4 full historical records")
	check(Retention.valid(saved) and retained.has("ob_0_0") and retained.has("ob_32_3"),"earliest and latest sample still exist")
	check(retained.get("ob_0_0",{}).get("record",{}).get("observed_value")==43,"earliest sample value preserved without digest substitution")
	check(retained.get("ob_32_3",{}).get("record",{}).get("observed_value")=="serviceable","latest live sample preserved")
	var cold:=Session.new()
	check(cold.initialize(content.defs,content.state,false,false,content.profile) and cold.restore(saved) and cold.snapshot()==saved,"full replay/cold restore exact")
	var corrupted:Dictionary=saved.duplicate(true)
	var first:String=str(corrupted.calendar.appraisal_observation_archive.keys()[0]) if not corrupted.calendar.appraisal_observation_archive.is_empty() else ""
	if not first.is_empty():
		corrupted.calendar.appraisal_observation_archive[first].record.observed_value=999
		check(not cold.restore(corrupted) and cold.snapshot()==saved,"archived evidence alteration cannot pass replay")
	var encoded:String=Checkpoint.encode("long_retention",saved,[],saved)
	check(not encoded.is_empty(),"v4 checkpoint carries entire archive")
	if not encoded.is_empty():
		var decoded:Dictionary=Checkpoint.decode(encoded,"long_retention",func()->RefCounted:
			var loaded:=Session.new()
			if loaded.initialize(content.defs,content.state,false,false,content.profile):
				return loaded
			return null)
		check(decoded.get("ok",false) and decoded.state==saved,"production v4 decoder replays full lossless history")
	var old:RefCounted=Watch.fresh()
	check(old!=null and old.snapshot().calendar.get("appraisal_observation_archive",{})=={},"legacy 7day stays unchanged")
	# The extra 42-day actors do not generate money; only the existing 2 wallets
	# expand to 51 live custodians. 7day has the old 32-wallet threshold.
	var lots:Dictionary=content.duplicate(true)
	for i:int in range(49):
		var actor:String="actor_"+str(i)
		lots.state.wallets[actor]={"VKC":0,"USD":0}
		lots.state.inventories[actor+"_grid"]={"owner_id":actor,"width":1,"height":1,"host_item":""}
	var pool:=Session.new()
	check(pool.initialize(lots.defs,lots.state,false,false,lots.profile) and pool.snapshot().wallets.size()==51,"42day 51 custodians and 0 invented liquidity")
	print("LONG_HISTORY_RETENTION: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
