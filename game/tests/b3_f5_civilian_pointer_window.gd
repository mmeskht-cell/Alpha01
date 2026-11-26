extends "res://tests/b3_f2_private_market_window.gd"
## Existing F3 source and normal A/B save. The workshop uses native pointer movements.
const F5Scene = preload("res://scenes/app/alpha_b3_f5_counter.tscn")
const CompositeSource = preload("res://src/content/b3_f3_composite_seed.gd")
const Trial = preload("res://src/domain/b3_f3_composite_trial.gd")
const F5_SLOT := "b3_f5_counter_v1"

func purchase(s: RefCounted,id: String,amount: int) -> bool:
	var visit: Dictionary = s.alpha_view().active
	var fit: Dictionary = s.spatial_fit(id,"player_stock")
	if not fit.get("ok",false): return false
	return f2_command(s,"alpha_price_offer",{"amount":amount}) and f2_command(s,"alpha_trade",{"visit_id":visit.id,"item_id":id,"seller":visit.actor_id,"buyer":"player","currency":"VKC","amount":amount,"inventory":"player_stock","x":fit.x,"y":fit.y,"rotated":fit.rotated}) and f2_command(s,"alpha_ack_exit")

func civilian_fixture() -> RefCounted:
	for seed_value in range(101,125):
		var src: Dictionary = CompositeSource.content(seed_value)
		if src.is_empty(): return null
		var s := F2Session.new()
		if not s.initialize(src.defs,src.state,false,false,{},src.alpha_profile): return null
		if not f2_command(s,"alpha_open"): return null
		if not f2_enter(s,Trial.BUY): continue
		if not purchase(s,Trial.ROOT,70) or not f2_morning(s): return null
		if not f2_enter(s,Trial.SUPPLY): continue
		if not purchase(s,Trial.SPARE,15) or not f2_command(s,"alpha_close") or not f2_command(s,"alpha_settle"): return null
		return s
	return null

func f5_install(location: String) -> void:
	host = F5Scene.instantiate()
	host.save_directory_override = location
	root.add_child(host)
	await frames()

func civilian_work(resolution: Vector2i,location: String,before: Dictionary) -> bool:
	if not check(host.session!=null and not host._blocked and host.session.snapshot()==before,"F5 resumes existing composite profile in its own slot"): return false
	if not await click_navigation(host,"stockroom"): return false
	if not await click_navigation(host,"stock_"+Trial.ROOT): return false
	if not await click_navigation(host,"work_slot_1"): return false
	var composition: Dictionary = host.session.composition_options(Trial.ROOT,"player_stock")
	var placement: Dictionary = composition.slots[1].detach
	if not check(not placement.is_empty(),"existing authority exposes a free cell for the actual module"): return false
	var grid := host.find_child("cell_%d_%d"%[placement.x,placement.y],true,false) as Control
	var module := host.find_child("detach_"+Trial.BAD,true,false) as Control
	if not await drag_between(module,grid): return false
	if not check(host.draft.get("kind")=="spatial_detach" and host.draft.result.ok and host.session.snapshot()==before,"dragging an installed module produces a read-only preview"): return false
	await capture("f5_civilian_detach_preview",resolution)
	if not await click_navigation(host,"discard_draft"): return false
	if not check(host.session.snapshot()==before and before.items[Trial.BAD].parent_id==Trial.ROOT,"cancel retains the real attachment"): return false
	if not await drag_between(host.find_child("detach_"+Trial.BAD,true,false),grid): return false
	if not await click("confirm_work","EVENING_WORK"): return false
	var split: Dictionary = host.session.snapshot()
	if not check(split.items[Trial.BAD].parent_id=="" and split.items[Trial.BAD].owner_id=="player" and split.items.size()==before.items.size(),"one real detach preserves item identity and ownership"): return false
	var spare := host.find_child("stock_"+Trial.SPARE,true,false) as Control
	var socket := host.find_child("work_socket_"+Trial.PART_B,true,false) as Control
	if not check(is_instance_valid(socket) and socket.is_visible_in_tree(),"replacement available in the existing socket"): return false
	if not await drag_between(spare,socket): return false
	if not check(host.draft.get("kind")=="spatial_attach" and host.draft.result.ok and host.session.snapshot()==split,"grid-to-socket drop previews actual replacement"): return false
	if not await click("confirm_work","EVENING_WORK"): return false
	if not await click_navigation(host,"repair"): return false
	if not await click("confirm_work","EVENING_WORK"): return false
	var completed: Dictionary = host.session.snapshot()
	var history: Dictionary = host.session.alpha_item_history(Trial.ROOT)
	var basis := 0
	for id: String in [Trial.ROOT,"F3R01_A",Trial.BAD,Trial.SPARE]:
		basis += int(completed.items[id].basis.VKC)
	if not check(completed.items[Trial.SPARE].parent_id==Trial.ROOT and completed.items[Trial.ROOT].restored and basis==90 and completed.wallets.player.VKC==before.wallets.player.VKC-5 and completed.ledger==before.ledger and history.work_records.size()==3,"attach and restore preserve cost and write one work record per operation"): return false
	await capture("f5_civilian_restored",resolution)
	await release_host()
	await f5_install(location)
	return check(host.session!=null and not host._blocked and host.session.snapshot()==completed and host.session.alpha_item_history(Trial.ROOT)==history,"cold resume retains the real module and three work records")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=1 or DirAccess.make_dir_recursive_absolute(args[0])!=OK:
		quit(2)
		return
	out = args[0]
	var resolution := Vector2i(1280,720)
	var fixture := civilian_fixture()
	if check(fixture!=null,"existing F3 route reaches evening with both physical items") and await configure_native_window(resolution):
		var before: Dictionary = fixture.snapshot()
		var location := "user://zt_rebuild/f5_pointer_"+str(Time.get_ticks_usec())
		var db := F2Repo.new(location)
		if check(db.save_session(fixture,F5_SLOT).get("ok",false),"isolated F5 workshop fixture saved by the normal repository"):
			await f5_install(location)
			if not await civilian_work(resolution,location,before): check(false,"complete F5 workshop pointer route")
	await finish()
