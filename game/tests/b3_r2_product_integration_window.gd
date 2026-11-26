extends "res://tests/b3_w20_pointer_window.gd"
## Authored private integration walk. Requires permission to run and original R2 art.
const Review = preload("res://scenes/app/alpha_b3_r2_art_review.tscn")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=1 or DirAccess.make_dir_recursive_absolute(args[0])!=OK:
		quit(2)
		return
	out = args[0]
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		if not await configure_native_window(resolution): break
		if not await install(Review,"r2_product_"+str(resolution.y)): break
		if not await shop_route(resolution,resolution.y==720):
			check(false,"complete product integration route "+str(resolution.y))
			break
		await release_host()
	await finish()

func actions(steps: Array) -> bool:
	for step: Array in steps:
		if not await click(step[0],step[1]): return false
	return true

func shop_route(resolution: Vector2i,refund: bool) -> bool:
	if not await actions([["intro_skip","DAY_PREP"],["alpha_open","OPEN_IDLE"],["alpha_next_customer","CUSTOMER_ENTER"],["alpha_ack_entry","CUSTOMER_ACTIVE"]]): return false
	await capture("r2_c7_marcus_"+str(resolution.y),resolution)
	if not await actions([["alpha_contract_decline","CUSTOMER_ACTIVE"],["alpha_finish_customer","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"],["alpha_next_customer","CUSTOMER_ENTER"],["alpha_ack_entry","CUSTOMER_ACTIVE"],["alpha_exchange_contact","CUSTOMER_ACTIVE"]]): return false
	if not await choose_radio_offer_100(): return false
	if not await actions([["offer","CUSTOMER_ACTIVE"],["settle_trade","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"]]): return false
	if not await inventory_route(resolution): return false
	if not await intake_service_if_offered(resolution): return false
	if not await actions([["alpha_close","CLOSE_SETTLE"]]): return false
	await capture("r2_c7_close_"+str(resolution.y),resolution)
	if not await click("alpha_settle","EVENING_WORK"): return false
	if host.session.snapshot().items.W001.get("status")=="custody_service":
		if not await work_service(resolution): return false
	if not await phone_route(resolution,refund): return false
	if not await set_inline_scale(150 if refund else 125): return false
	if not await click_navigation(host,"ledger"): return false
	if not await click_navigation(host,"folio_outbound"): return false
	await capture("r2_c5_outbound_"+str(resolution.y),resolution)
	if not await click_navigation(host,"folio_trades"): return false
	await capture("r2_c5_receipt_"+str(resolution.y),resolution)
	if not await click_navigation(host,"close_drawer"): return false
	if not await click_navigation(host,"news"): return false
	await capture("r2_c5_news_"+str(resolution.y),resolution)
	if not await click_navigation(host,"close_drawer"): return false
	if not await set_inline_scale(100): return false
	if not await actions([["alpha_next_day","NEXT_DAY"],["alpha_prepare_day","DAY_PREP"],["alpha_open","OPEN_IDLE"]]): return false
	if not await serve_until("watch_a"): return false
	await capture("r2_c7_pledge_"+str(resolution.y),resolution)
	var before: Dictionary = host.session.snapshot()
	if not await actions([["week_pledge","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"]]): return false
	if not check(host.session.snapshot().items.WAT02.inventory=="pawn_grid" and host.session.snapshot().wallets.player.VKC==before.wallets.player.VKC-40,"pledge retains custody and exact principal"): return false
	if not await next_morning(): return false
	if not refund:
		if not check(host.session.snapshot().alpha_shop.outbound.tool_search.status=="delayed","D3 reports the authored delay"): return false
		if not await click_navigation(host,"ledger"): return false
		if not await click_navigation(host,"folio_outbound"): return false
		await capture("r2_c4_delay_"+str(resolution.y),resolution)
		if not await click_navigation(host,"close_drawer"): return false
	if not await next_morning(): return false
	if not refund:
		if not await serve_until("tool_buy"): return false
		if not check(host.session.alpha_view().appraisal.item_id=="TL04" and host.session.snapshot().alpha_shop.outbound.tool_search.status=="goods_offered","actual dispatched goods arrive as a regular counter visit"): return false
		await capture("r2_c4_goods_return_"+str(resolution.y),resolution)
		if not await actions([["alpha_finish_customer","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"]]): return false
	if not await click("alpha_close","CLOSE_SETTLE"): return false
	if not await click_navigation(host,"ledger"): return false
	if not await click_navigation(host,"folio_contracts"): return false
	await reveal_action("week_redeem")
	if not await click("week_redeem","CLOSE_SETTLE"): return false
	if not check(host.session.snapshot().alpha_shop.week_pawn.status=="redeemed","D4 redemption through original authority"): return false
	await capture("r2_c7_redeemed_"+str(resolution.y),resolution)
	if not await click_navigation(host,"close_drawer"): return false
	if not await actions([["alpha_settle","EVENING_WORK"],["alpha_next_day","NEXT_DAY"],["alpha_prepare_day","DAY_PREP"],["alpha_open","OPEN_IDLE"]]): return false
	if not await next_morning() or not await next_morning(): return false
	if not await serve_until("alpha_b3_fx_broker_d7"): return false
	if not await click_navigation(host,"visitor_papers"): return false
	await capture("r2_c7_fx_quote_"+str(resolution.y),resolution)
	var funds: Dictionary = host.session.snapshot().wallets.player
	if not await click("b3_fx_accept","CUSTOMER_ACTIVE"): return false
	var changed: Dictionary = host.session.snapshot().wallets.player
	if not check(changed.VKC==funds.VKC-30 and changed.USD==funds.USD+1,"broker settles the original 30 VKC for 1 USD once"): return false
	if not await actions([["alpha_finish_customer","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"],["alpha_close","CLOSE_SETTLE"],["alpha_settle","EVENING_WORK"],["alpha_next_day","COMPLETE"]]): return false
	await capture("r2_c7_week_complete_"+str(resolution.y),resolution)
	return true

func phone_route(resolution: Vector2i,refund: bool) -> bool:
	var before: Dictionary = host.session.snapshot()
	if not await set_inline_scale(150 if refund else 125): return false
	if not await click_navigation(host,"phone"): return false
	var desk := host.find_child("r2_phone_workspace",true,false) as Control
	if not await click_navigation(host,"contact_G01"): return false
	if not await click_navigation(host,"terms_tool_search"): return false
	var confirm := host.find_child("phone_tool_search",true,false) as Control
	if not check(confirm!=null and root.get_visible_rect().encloses(confirm.get_global_rect()),"scaled phone confirmation fits the actual window"): return false
	await capture("r2_c4_terms_"+str(resolution.y),resolution)
	if not check(host.session.snapshot()==before,"phone and terms do not transact"): return false
	if not await click("phone_tool_search","EVENING_WORK"): return false
	var paid: Dictionary = host.session.snapshot()
	if not check(paid.wallets.player.VKC==before.wallets.player.VKC-10,"actual 10 VKC advance"): return false
	if not check(desk!=null and desk==host.find_child("r2_phone_workspace",true,false),"retained phone desk across payment"): return false
	await capture("r2_c4_advance_"+str(resolution.y),resolution)
	if refund:
		if not await click_navigation(host,"terms_tool_search"): return false
		if not await click("phone_tool_search","EVENING_WORK"): return false
		if not check(host.session.snapshot().wallets.player.VKC==before.wallets.player.VKC,"actual 10 VKC refund"): return false
		await capture("r2_c4_refund_"+str(resolution.y),resolution)
	if not await click_navigation(host,"close_drawer"): return false
	return await set_inline_scale(100)

func set_inline_scale(percent: int) -> bool:
	var before: Dictionary = host.session.snapshot()
	for id: String in ["preferences","font_"+str(percent),"close_drawer"]:
		if not await click_navigation(host,id): return false
	return check(host.reading_scale==percent and host.session.snapshot()==before,"font control is local and reaches the requested scale")

func inventory_route(resolution: Vector2i) -> bool:
	if not await click_navigation(host,"stockroom"): return false
	if not await click_navigation(host,"stock_R001"): return false
	var before: Dictionary = host.session.snapshot()
	if not await click_navigation(host,"tab_service_grid"): return false
	if not await click_navigation(host,"cell_0_0"): return false
	if not check(not host.draft.is_empty() and not host.draft.result.ok and host.session.snapshot()==before,"service grid rejects player stock without moving or debiting"): return false
	if not check(host.find_child("confirm_work",true,false)==null,"forbidden placement has no confirm action"): return false
	await capture("r2_c6_blocked_"+str(resolution.y),resolution)
	if not await click_navigation(host,"discard_draft"): return false
	if not check(host.storage=="player_stock" and host.session.snapshot()==before,"cancel returns to the authoritative origin"): return false
	var radio := host.find_child("stock_R001",true,false) as Control
	var shelf := host.find_child("tab_storefront_grid",true,false) as Control
	if not await drag_between(radio,shelf): return false
	if not check(host.storage=="storefront_grid","tab drop changes the visible grid after release"): return false
	if not await click_navigation(host,"cell_5_2"): return false
	if not check(not host.draft.is_empty() and host.draft.result.get("error")=="inventory_placement" and host.session.snapshot()==before,"edge rejects an overflowing footprint without moving or debiting"): return false
	if not check(host.find_child("confirm_work",true,false)==null,"overflowing footprint has no confirm action"): return false
	await capture("r2_c6_edge_"+str(resolution.y),resolution)
	if not await click_navigation(host,"rotate"): return false
	if not await click_navigation(host,"cell_0_0"): return false
	if not check(host.draft.result.ok and host.draft.payload.rotated!=before.items.R001.rotated and host.session.snapshot()==before,"rotated placement preview is read-only"): return false
	await capture("r2_c6_pending_"+str(resolution.y),resolution)
	if not await click("confirm_work","OPEN_IDLE"): return false
	if not check(host.session.snapshot().items.R001.inventory=="storefront_grid" and host.session.snapshot().items.R001.rotated!=before.items.R001.rotated,"listing commits placement and rotation together"): return false
	await capture("r2_c6_placed_"+str(resolution.y),resolution)
	if not await click_navigation(host,"item_history"): return false
	await capture("r2_c5_item_history_"+str(resolution.y),resolution)
	if not await click_navigation(host,"close_drawer"): return false
	return await click_navigation(host,"close_drawer")

func next_morning() -> bool:
	return await actions([["alpha_close","CLOSE_SETTLE"],["alpha_settle","EVENING_WORK"],["alpha_next_day","NEXT_DAY"],["alpha_prepare_day","DAY_PREP"],["alpha_open","OPEN_IDLE"]])

func serve_until(visit_id: String) -> bool:
	for index in range(8):
		if not await actions([["alpha_next_customer","CUSTOMER_ENTER"],["alpha_ack_entry","CUSTOMER_ACTIVE"]]): return false
		if host.session.alpha_view().active.id==visit_id: return true
		if not await actions([["alpha_finish_customer","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"]]): return false
	return check(false,"fixture visit reached")

func reveal_action(id: String) -> void:
	var target := host.find_child(id,true,false) as Control
	if not target: return
	var ancestor := target.get_parent()
	while ancestor and not ancestor is ScrollContainer:
		ancestor = ancestor.get_parent()
	if ancestor is ScrollContainer:
		ancestor.ensure_control_visible(target)
		await frames()

func intake_service_if_offered(resolution: Vector2i) -> bool:
	while int(host.session.alpha_view().remaining)>0:
		if not await actions([["alpha_next_customer","CUSTOMER_ENTER"],["alpha_ack_entry","CUSTOMER_ACTIVE"]]): return false
		var view: Dictionary = host.session.alpha_view()
		var has_job: bool = view.services.entries.any(func(job:Dictionary)->bool:return job.item_id=="W001" and job.can_accept)
		if has_job:
			var subtitle := host.find_child("Utterance",true,false) as Label
			if not check(subtitle!=null and subtitle.is_visible_in_tree() and "맡기" in subtitle.text and not visible_action("offer"),"service intake has its own speech and starts with service paperwork"): return false
			if not await click_navigation(host,"visitor_papers"): return false
			if not await click("b2_service_accept","CUSTOMER_ACTIVE"): return false
			await capture("r2_c7_service_intake_"+str(resolution.y),resolution)
		if not await actions([["alpha_finish_customer","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"]]): return false
		if has_job: return true
	print("R2_PRODUCT_SERVICE_NOT_DRAWN: current authoritative visit seed offered no W001 job")
	return true

func work_service(resolution: Vector2i) -> bool:
	if not await click_navigation(host,"stockroom"): return false
	if not await click_navigation(host,"tab_service_grid"): return false
	if not await click_navigation(host,"stock_W001"): return false
	var original: Dictionary = host.session.snapshot()
	if not await click_navigation(host,"b2_service_repair"): return false
	if not check(host.draft.result.ok and host.session.snapshot()==original,"service preview preserves customer property and wallet"): return false
	var cost: int = int(host.draft.result.VKC)
	await capture("r2_c6_work_pending_"+str(resolution.y),resolution)
	if not await click_navigation(host,"discard_draft"): return false
	if not check(host.session.snapshot()==original,"no settlement on work cancellation"): return false
	if not await click_navigation(host,"b2_service_repair"): return false
	if not await click("confirm_work","EVENING_WORK"): return false
	var repaired: Dictionary = host.session.snapshot()
	if not check(repaired.items.W001.owner_id==original.items.W001.owner_id and repaired.items.W001.custodian_id=="player" and repaired.wallets.player.VKC==original.wallets.player.VKC+cost and repaired.ledger==original.ledger,"authorized work changes neither ownership nor trade ledger"): return false
	await capture("r2_c6_work_committed_"+str(resolution.y),resolution)
	return await click_navigation(host,"close_drawer")
