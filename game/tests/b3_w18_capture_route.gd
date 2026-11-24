extends "res://tests/window/b3_spatial_week_window.gd"
## W18 supplemental rendered evidence. Real viewport pointer route, isolated saves.
## The original B3 460-check script remains unchanged and runs independently.

func finish() -> void:
	await release_host()
	print("B3_W18_CAPTURE: ",checks," checks, ",failures," failures")
	Node.print_orphan_nodes()
	call_deferred("quit",0 if failures==0 else 1)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=1:
		quit(2)
		return
	out = args[0]
	if DirAccess.make_dir_recursive_absolute(out)!=OK:
		quit(2)
		return
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = resolution
		if not await install(Spatial,"w18_"+str(resolution.y)):
			await finish()
			return
		if not await _w18_route(resolution):
			check(false,"complete W18 capture route "+str(resolution.y))
			await finish()
			return
		await release_host()
	await finish()

func _w18_route(resolution: Vector2i) -> bool:
	var suffix := "_"+str(resolution.y)
	if not await click("intro_skip","DAY_PREP"): return false
	for step: Array in [["alpha_open","OPEN_IDLE"],["alpha_next_customer","CUSTOMER_ENTER"],["alpha_ack_entry","CUSTOMER_ACTIVE"],["alpha_contract_decline","CUSTOMER_ACTIVE"],["alpha_finish_customer","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"],["alpha_next_customer","CUSTOMER_ENTER"],["alpha_ack_entry","CUSTOMER_ACTIVE"]]:
		if not await click(step[0],step[1]): return false
	if not check(host.session.alpha_view().active.id=="visit_g01","actual G01 radio visit after Marcus"): return false
	if not await click_navigation(host,"specimen"): return false
	var prior: Dictionary = host.session.snapshot()
	if not await click_navigation(host,"notes"): return false
	await capture("01_initial_book"+suffix,resolution)
	if not await click_navigation(host,"close_drawer"): return false
	if not check(host.zoom and host.session.snapshot()==prior,"book navigation preserves state"): return false
	var found := false
	for page: int in range(3):
		var wear := host.find_child("tool_wear_detail",true,false) as Button
		if wear!=null and wear.is_visible_in_tree():
			found = true
			break
		if not await click_navigation(host,"more_tools"): return false
	if not check(found,"visible wear tool in paged tray"): return false
	if not await click_navigation(host,"tool_wear_detail"): return false
	if not await click("apply_tool","CUSTOMER_ACTIVE"): return false
	if not await click("fact_wear_detail","CUSTOMER_ACTIVE"): return false
	await capture("02_observation_and_slip"+suffix,resolution)
	if not await click_navigation(host,"notes"): return false
	if not await click_navigation(host,"book_surface"): return false
	await capture("03_surface_reference"+suffix,resolution)
	if not await click_navigation(host,"close_drawer"): return false
	var price := host.find_child("price",true,false) as LineEdit
	if not check(price!=null and price.is_visible_in_tree(),"live offer editor"): return false
	price.grab_focus()
	price.clear()
	price.insert_text_at_caret("100")
	await frames()
	if not await click("offer","CUSTOMER_ACTIVE"): return false
	await capture("04_public_offer"+suffix,resolution)
	if not await click("settle_trade","CUSTOMER_EXIT"): return false
	if not check(host.session.snapshot().items.R001.owner_id=="player","actual purchased radio"): return false
	if not await click("alpha_ack_exit","OPEN_IDLE"): return false
	if not await click_navigation(host,"stockroom"): return false
	if not await click_navigation(host,"stock_R001"): return false
	await capture("05_selected_stock"+suffix,resolution)
	if not await click_navigation(host,"tab_storefront_grid"): return false
	var stock_before: Dictionary = host.session.snapshot()
	if not await click_navigation(host,"cell_0_0"): return false
	if not check(not host.draft.is_empty() and host.draft.result.ok and host.session.snapshot()==stock_before,"valid preview is read-only"): return false
	await capture("06_placement_preview"+suffix,resolution)
	if not await click_navigation(host,"discard_draft"): return false
	if not check(host.draft.is_empty() and host.selected=="R001" and host.session.snapshot()==stock_before,"cancel preserves item, money and selection"): return false
	await capture("07_cancelled_placement"+suffix,resolution)
	return true
