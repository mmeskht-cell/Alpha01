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
	# The complete receiver is larger than the disassembled receiver. Exercise
	# the genuine newly freed cells first, then clear them by moving the part.
	var body: Dictionary = before.items[Trial.ROOT]
	var dimensions: Array = host.session.spatial_dimensions(Trial.ROOT)
	var full_size := Vector2i(int(dimensions[1] if body.rotated else dimensions[0]),int(dimensions[0] if body.rotated else dimensions[1]))
	var full_area := Rect2i(Vector2i(int(body.x),int(body.y)),full_size)
	var placement: Dictionary = {}
	for option: Dictionary in composition.slots[1].detach_positions:
		if full_area.has_point(Vector2i(int(option.x),int(option.y))):
			placement = option
			break
	if not check(not placement.is_empty(),"authority offers a newly freed cell inside the former full footprint"): return false
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
	var expected := {"actor":"player","root_id":Trial.ROOT,"child_id":Trial.SPARE}
	var live: Dictionary = host.session.composition_options(Trial.ROOT,"player_stock")
	var blocked: Dictionary = host.session.spatial_action_preview("spatial_attach",expected)
	var socket := host.find_child("work_socket_"+Trial.PART_B,true,false) as Control
	if not check(is_instance_valid(socket) and socket.is_visible_in_tree(),"empty physical socket remains visible"): return false
	if not check(full_area.has_point(Vector2i(int(split.items[Trial.BAD].x),int(split.items[Trial.BAD].y))) and not blocked.get("ok",false) and blocked.get("error")=="inventory_placement" and not live.slots[1].attach.has(expected) and host.session.snapshot()==split,"expanding receiver correctly refuses overlap with its detached module"): return false
	var blocked_drag := {"item":Trial.SPARE,"origin":"player_stock","revision":split.revision}
	if not check(not socket.call("accepts",blocked_drag),"socket refuses a geometrically blocked replacement"): return false
	await capture("f5_civilian_attach_blocked",resolution)
	# Move the existing detached piece to a valid cell outside the completed
	# footprint. Neither the obstruction nor the part is silently removed.
	var destination := Vector2i(-1,-1)
	var stock: Dictionary = split.inventories.player_stock
	for y: int in range(int(stock.height)):
		for x: int in range(int(stock.width)):
			var point := Vector2i(x,y)
			if full_area.has_point(point): continue
			var move := {"actor":"player","item_id":Trial.BAD,"inventory":"player_stock","x":x,"y":y,"rotated":false}
			if host.session.spatial_action_preview("spatial_move",move).get("ok",false):
				destination = point
				break
		if destination.x>=0: break
	if not check(destination.x>=0 and host.session.snapshot()==split,"a real legal clearance cell exists without mutation"): return false
	var obstruction := host.find_child("stock_"+Trial.BAD,true,false) as Control
	var clearance := host.find_child("cell_%d_%d"%[destination.x,destination.y],true,false) as Control
	if not await drag_between(obstruction,clearance): return false
	if not check(host.draft.get("kind")=="spatial_move" and host.draft.result.ok and host.session.snapshot()==split,"moving the obstruction is an explicit read-only placement preview"): return false
	if not await click("confirm_work","EVENING_WORK"): return false
	var cleared: Dictionary = host.session.snapshot()
	if not check(cleared.items[Trial.BAD].x==destination.x and cleared.items[Trial.BAD].y==destination.y and cleared.items.size()==split.items.size() and cleared.wallets==split.wallets and cleared.ledger==split.ledger,"one confirmed movement clears expansion space without loss or payment"): return false
	if not await click_navigation(host,"stock_"+Trial.ROOT): return false
	if not await click_navigation(host,"work_slot_1"): return false
	split = cleared
	var spare := host.find_child("stock_"+Trial.SPARE,true,false) as Control
	socket = host.find_child("work_socket_"+Trial.PART_B,true,false) as Control
	if not check(is_instance_valid(socket) and socket.is_visible_in_tree(),"cleared physical socket remains visible"): return false
	live = host.session.composition_options(Trial.ROOT,"player_stock")
	if not check(host.session.spatial_action_preview("spatial_attach",expected).get("ok",false) and live.slots[1].attach.has(expected) and host.session.snapshot()==split,"clearing the footprint restores the exact spare to the authorized attachment list"): return false
	var data := {"item":Trial.SPARE,"origin":"player_stock","revision":split.revision}
	if not check(socket.call("accepts",data),"visible socket accepts the current projected spare"): return false
	var stale := data.duplicate(true)
	stale.revision = int(split.revision)-1
	if not check(not socket.call("accepts",stale),"visible socket refuses stale drag data"): return false
	await capture("f5_civilian_attach_ready",resolution)
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
