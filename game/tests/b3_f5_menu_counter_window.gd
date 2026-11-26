extends "res://tests/b3_w20_pointer_window.gd"
## Actual title entry and normal F5 A/B generations, with a fresh directory per native resolution.
const Title = preload("res://scenes/app/main_menu.tscn")
const F5_SLOT := "b3_f5_counter_v1"

func open_f5(directory: String) -> bool:
	var title := Title.instantiate() as Control
	title.save_directory_override = directory
	root.add_child(title)
	current_scene = title
	await frames()
	if not await click_navigation(title,"menu_f5_counter"):
		title.queue_free()
		return false
	host = current_scene as Control
	return check(host!=null and host.name=="AlphaB3F5Counter" and host.session!=null and not host._blocked
		and host._slot()==F5_SLOT and host.save_directory_override==directory.path_join("f5_counter"),
		"real F5 menu entry opens the isolated F5 profile and save")

func enter_first_item(resolution: Vector2i) -> bool:
	var before: Dictionary = host.session.snapshot()
	for beat in range(5):
		if not check(host._intro and host._intro_page==beat,"intro beat reached in order"): return false
		if not await click_navigation(host,"intro_next"): return false
	if not check(not host._intro and host.session.snapshot()==before,"five intro beats preserve opening state"): return false
	for step: Array in [["alpha_open","OPEN_IDLE"],["alpha_next_customer","CUSTOMER_ENTER"],["alpha_ack_entry","CUSTOMER_ACTIVE"],
		["alpha_contract_decline","CUSTOMER_ACTIVE"],["alpha_finish_customer","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"],
		["alpha_next_customer","CUSTOMER_ENTER"],["alpha_ack_entry","CUSTOMER_ACTIVE"]]:
		if not await click(step[0],step[1]): return false
	if not check(host.session.alpha_view().appraisal.get("item_id")=="R001" and host.standing_actor.is_visible_in_tree()
			and visible_action("enter_appraisal") and not visible_action("offer"),"front view shows the customer and their real specimen"): return false
	await capture("f5_menu_first_item_"+str(resolution.y),resolution)
	return true

func scale_in_appraisal(percent: int,resolution: Vector2i,original: Dictionary) -> bool:
	for id: String in ["preferences","font_"+str(percent),"close_drawer"]:
		if not await click_navigation(host,id): return false
	if not check(host.reading_scale==percent and host.zoom and not host.standing_actor.is_visible_in_tree()
			and host.session.snapshot()==original, "font size leaves the overhead visit and authority unchanged"): return false
	if not await click_navigation(host,"notes") or not await click_navigation(host,"book_surface"): return false
	if visible_action("surface_judgment_open"):
		if not await click_navigation(host,"surface_judgment_open"): return false
	var book := host.find_child("r2_reference_desk",true,false) as Control
	var item := host.counter_item as Control
	var lift := host.find_child("finish_appraisal",true,false) as Control
	var grade := host.find_child("exterior_moderate",true,false) as Control
	var scroll := host.r2_book.scroll as Control
	if not check(book!=null and item!=null and lift!=null and grade!=null and scroll!=null
		and scroll.get_global_rect().encloses(grade.get_global_rect()) and root.get_visible_rect().encloses(book.get_global_rect())
		and not book.get_global_rect().intersects(item.get_global_rect())
		and not book.get_global_rect().intersects(lift.get_global_rect())
		and not visible_action("offer") and not visible_action("settle_trade"),
		"overhead book and item stay separately usable at this font size"): return false
	await capture("f5_menu_overhead_%d_%d"%[percent,resolution.y],resolution)
	return await click_navigation(host,"close_drawer")

func toggle_counter_motion() -> bool:
	for id: String in ["preferences","motion","close_drawer"]:
		if not await click_navigation(host,id): return false
	return true

func inspect_and_offer(resolution: Vector2i) -> bool:
	var opening: Dictionary = host.session.snapshot()
	var item := host.counter_item as TextureRect
	var original_texture := item.texture
	var original_size := item.size
	if host.reduce_motion and not await toggle_counter_motion(): return false
	if not await start_counter_appraisal(true): return false
	if not check(host.counter_item==item and item.texture==original_texture and item.size.x>original_size.x
		and not host.standing_actor.is_visible_in_tree(),"head tilt moves the real specimen and excludes the customer"): return false
	for percent: int in [100,125,150]:
		if not await scale_in_appraisal(percent,resolution,opening): return false
	for page in range(4):
		if visible_action("tool_wear_detail"): break
		if not await click_navigation(host,"more_tools"): return false
	if not await click_navigation(host,"tool_wear_detail") or not await click("apply_tool","CUSTOMER_ACTIVE"): return false
	var observed: Dictionary = host.session.snapshot()
	if not check(observed.items==opening.items and observed.wallets==opening.wallets
		and host.session.alpha_view().appraisal.cards.any(func(card: Dictionary)->bool: return card.slot=="wear_detail" and not card.public_active),
		"inspection adds only private observation knowledge"): return false
	await capture("f5_menu_observed_"+str(resolution.y),resolution)
	if not await leave_counter_appraisal(true) or not await click("fact_wear_detail","CUSTOMER_ACTIVE"): return false
	if not await choose_radio_offer_100(): return false
	var selected: Dictionary = host.session.snapshot()
	var basis: Dictionary = host.offer_basis.duplicate(true)
	var ratio: int = host.offer_ratio
	if not await start_counter_appraisal(true) or not await leave_counter_appraisal(true): return false
	if not check(host.session.snapshot()==selected and host.offer_basis==basis and host.offer_ratio==ratio
		and host.counter_item==item and host.standing_actor.is_visible_in_tree(),"reappraisal preserves the item, evidence and proportionate draft"): return false
	await capture("f5_menu_negotiation_"+str(resolution.y),resolution)
	if not await toggle_counter_motion(): return false
	if not check(host.reduce_motion,"reduced motion setting applies to the counter camera"): return false
	if not await start_counter_appraisal(true) or not await leave_counter_appraisal(true): return false
	if not check(host.session.snapshot()==selected and host.offer_ratio==ratio,"instant camera path keeps the same negotiation draft"): return false
	if not await click("offer","CUSTOMER_ACTIVE"): return false
	var agreed: Dictionary = host.session.snapshot()
	if not check(agreed.ledger==selected.ledger and agreed.wallets==selected.wallets and agreed.items==selected.items
		and host.session.alpha_view().npc_context.current_offer.public_slots.has("wear_detail"),
		"the proposal discloses the chosen evidence and does not pay"): return false
	if not await click("settle_trade","CUSTOMER_EXIT"): return false
	var paid: Dictionary = host.session.snapshot()
	if not check(paid.ledger.size()==agreed.ledger.size()+1 and paid.items.R001.owner_id=="player"
		and paid.wallets.player.VKC==agreed.wallets.player.VKC-100,"the physical transaction settles once at the agreed price"): return false
	await capture("f5_menu_receipt_"+str(resolution.y),resolution)
	return true

func menu_route(resolution: Vector2i) -> bool:
	var directory := "user://zt_rebuild/f5_menu_"+str(resolution.y)+"_"+str(Time.get_ticks_usec())
	if not await open_f5(directory) or not await enter_first_item(resolution) or not await inspect_and_offer(resolution): return false
	var settled: Dictionary = host.session.snapshot()
	await release_host()
	if not await open_f5(directory): return false
	if not check(not host._intro and host.session.snapshot()==settled and not visible_action("settle_trade"),
		"cold F5 title re-entry recovers the settled visit without another payment"): return false
	await capture("f5_menu_resumed_"+str(resolution.y),resolution)
	await release_host()
	return true

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=1 or DirAccess.make_dir_recursive_absolute(args[0])!=OK:
		quit(2)
		return
	out = args[0]
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		if not await configure_native_window(resolution): break
		if not await menu_route(resolution):
			check(false,"complete F5 title and counter route "+str(resolution.y))
			break
	await finish()
