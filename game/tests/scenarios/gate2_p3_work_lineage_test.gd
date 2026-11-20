extends SceneTree
const Session=preload("res://src/domain/game_session.gd")
const Fixture=preload("res://tests/fixtures/gate0_c_state.gd")
const SaveRepo=preload("res://src/persistence/save_repository.gd")
const HistoryScript=preload("res://src/presentation/generic_trade_history.gd")
var checks: int=0
var failures: int=0

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func fresh() -> RefCounted:
	var seed: Dictionary=Fixture.make()
	seed.wallets.player.USD=7
	seed.visits.purchase.expires=600
	seed.visits["resale"]=Fixture.visit("resale","player","buyer",{"X01":{"VKC":95,"USD":0}})
	seed.visits.resale.opens=1440
	seed.visits.resale.expires=2040
	var ids: Array=["d1","d2","d3","d4","d5","d6","d7"]
	var days: Dictionary={}
	for day: String in ids:
		days[day]=[]
	days["d1"]=["purchase"]
	days["d2"]=["resale"]
	var profile: Dictionary={"id":"demo_7","content_version":"p3-work-fixture-1","day_ids":ids,"visit_days":days}
	var s:=Session.new()
	return s if s.initialize(Fixture.definitions(),seed,false,false,profile) else null

func act(s: RefCounted,id: String,kind: String,p: Dictionary={}) -> bool:
	return s.execute({"action_id":id,"expected_revision":s.snapshot().revision,"type":kind,"payload":p}).ok

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var s: RefCounted=fresh()
	check(s!=null,"fixture")
	if s==null:
		quit(1)
		return
	check(s.calendar_history_index().items.is_empty() and s.calendar_item_history("X01").work_records.is_empty(),"unacted-on external item hidden")
	check(act(s,"admit","calendar_next_visit"),"admit")
	var buy: Dictionary=Fixture.purchase().payload
	buy["visit_id"]="purchase"
	check(act(s,"buy","trade",buy) and act(s,"close","calendar_close"),"actual purchase and workshop")
	check(act(s,"split","detach",{"actor":"player","root_id":"X01","child_id":"X01_A","inventory":"player_grid","x":5,"y":0,"rotated":false}),"synthetic composition event")
	check(act(s,"join","attach",{"actor":"player","root_id":"X01","child_id":"X01_A"}),"synthetic recombination event")
	check(act(s,"repair","restore_item",{"actor":"player","item_id":"X01"}),"actual maintenance event")
	var before: Dictionary=s.snapshot()
	var history: Dictionary=s.calendar_item_history("X01")
	var child: Dictionary=s.calendar_item_history("X01_A")
	check(history.records.size()==1 and history.records[0].amounts.VKC==70 and child.records[0].amounts==null,"root price only")
	check(history.work_records.size()==3 and history.work_records[0].expense=={"VKC":5,"USD":2},"maintenance expense not purchase")
	check(history.work_records[1].kind=="attach" and history.work_records[2].kind=="detach","reverse revision order")
	check(history.work_records[1].related_item_id=="X01_A" and history.work_records[1].role=="root" and child.work_records[0].related_item_id=="X01" and child.work_records[0].role=="child","independent counterpart identities")
	check(child.work_records.size()==2 and s.calendar_item_history("X01_B").work_records.is_empty(),"no unrelated work inheritance")
	check(not history.work_records[0].has("minute") and not history.work_records[0].has("owner_id"),"no invented time or external ownership")
	check(s.snapshot()==before and before.items.X01.basis.VKC==25,"read-only and actual basis preserved")
	var disposal: RefCounted=fresh()
	check(disposal.restore(before),"separate disposal branch")
	var preview: Dictionary=disposal.discard_preview("X01")
	check(preview.ok and act(disposal,"discard","discard",{"actor":"player","item_id":"X01","confirmed_ids":preview.item_ids}),"actual discard")
	var discarded: Dictionary=disposal.calendar_item_history("X01").work_records[0]
	check(discarded.kind=="discard" and discarded.group_size==4 and discarded.loss==null,"group loss not assigned to each item")
	check(disposal.calendar_item_history("X01_A").work_records[0].loss==null and disposal.snapshot().tombstones.has("X01_A"),"terminal child record retained")
	for i: int in range(34):
		check(act(s,"move_"+str(i),"move",{"actor":"player","item_id":"X01","inventory":"player_grid","x":i%2,"y":0,"rotated":false}),"bounded archive move "+str(i))
	check(s.snapshot().receipt_archive.has("repair") and s.calendar_item_history("X01")==history,"archived receipt still bound; moves not work history")
	check(act(s,"morning","calendar_morning") and act(s,"resale_admit","calendar_next_visit"),"next day sale")
	check(act(s,"sale","trade",{"visit_id":"resale","item_id":"X01","seller":"player","buyer":"buyer","currency":"VKC","amount":95,"inventory":"buyer_grid","x":0,"y":0,"rotated":false}),"actual same-ID resale")
	var sold: Dictionary=s.snapshot()
	var final: Dictionary=s.calendar_item_history("X01")
	check(final.records.size()==2 and final.records[0].direction=="sale" and final.records[0].amounts.VKC==95 and final.work_records==history.work_records,"purchase work sale linked")
	check(s.calendar_item_history("X01_A").records[0].amounts==null,"no child resale total")
	var panel:=HistoryScript.new()
	root.add_child(panel)
	panel.configure(s.calendar_history_index(),Callable(),"en")
	check(panel.find_child("history_work_repair_X01",true,false)!=null and panel.find_child("history_work_join_X01_A",true,false)!=null,"history panel shows root and child records")
	panel.configure(s.calendar_history_index(),Callable(),"ko")
	check(panel.find_child("history_work_repair_X01",true,false)!=null and s.snapshot()==sold,"bilingual free read")
	panel.queue_free()
	await process_frame
	var reload: RefCounted=fresh()
	check(reload.restore(sold) and reload.calendar_item_history("X01")==final,"cold replay projection")
	var fake: Dictionary=sold.duplicate(true)
	fake.object_events[2].expenses.VKC=0
	check(not reload.restore(fake) and reload.snapshot()==sold,"tampered maintenance rejected by replay")
	var repo:=SaveRepo.new("user://zt_rebuild/p3_work_"+str(Time.get_ticks_usec()))
	check(repo.save_session(s,"work").ok and repo.load_session(reload,"work").ok and reload.calendar_item_history("X01")==final,"disk replay projection")
	print("GATE2_P3_WORK_LINEAGE: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
