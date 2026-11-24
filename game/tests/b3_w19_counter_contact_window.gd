extends "res://tests/window/b3_spatial_week_window.gd"
## Supplemental first-day route; existing W17/W18 routes remain independent.
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=1:
		quit(2)
		return
	out=args[0]
	if DirAccess.make_dir_recursive_absolute(out)!=OK:
		quit(2)
		return
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=resolution
		if not await install(Spatial,"w19_"+str(resolution.y)) or not await desk_day(resolution):
			check(false,"complete W19 first-day desk and outbound route")
			break
		await release_host()
	await finish()

func desk_day(resolution: Vector2i) -> bool:
	var suffix := "_"+str(resolution.y)
	for step: Array in [["intro_skip","DAY_PREP"],["alpha_open","OPEN_IDLE"],["alpha_next_customer","CUSTOMER_ENTER"],["alpha_ack_entry","CUSTOMER_ACTIVE"]]:
		if not await click(step[0],step[1]): return false
	await capture("w19_incoming_terms"+suffix,resolution)
	for step: Array in [["alpha_contract_decline","CUSTOMER_ACTIVE"],["alpha_finish_customer","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"],["alpha_next_customer","CUSTOMER_ENTER"],["alpha_ack_entry","CUSTOMER_ACTIVE"]]:
		if not await click(step[0],step[1]): return false
	await capture("w19_counter"+suffix,resolution)
	if not await click("alpha_exchange_contact","CUSTOMER_ACTIVE"): return false
	var initial: Dictionary=host.session.snapshot()
	if not await click_navigation(host,"tool_wear_detail"): return false
	if not await click("apply_tool","CUSTOMER_ACTIVE"): return false
	var observed: Dictionary=host.session.snapshot()
	if not await click_navigation(host,"apply_tool"): return false
	if not check(host.session.snapshot()==observed,"known surface reopens for free"): return false
	if not await click_navigation(host,"notes"): return false
	await capture("w19_loupe_book"+suffix,resolution)
	if not await click_navigation(host,"close_drawer"): return false
	if not await click("fact_wear_detail","CUSTOMER_ACTIVE"): return false
	var price := host.find_child("price",true,false) as LineEdit
	price.grab_focus()
	price.clear()
	price.insert_text_at_caret("100")
	if not await click("offer","CUSTOMER_ACTIVE"): return false
	await capture("w19_offer_response"+suffix,resolution)
	for step: Array in [["settle_trade","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"],["alpha_close","CLOSE_SETTLE"],["alpha_settle","EVENING_WORK"]]:
		if not await click(step[0],step[1]): return false
	if not check(host.session.snapshot().items.R001.owner_id=="player","purchase delivered"): return false
	var before: Dictionary=host.session.snapshot()
	if not await click_navigation(host,"phone"): return false
	if not await click_navigation(host,"contact_G01"): return false
	if not await click_navigation(host,"terms_tool_search"): return false
	await capture("w19_outbound_terms"+suffix,resolution)
	if not check(before==host.session.snapshot(),"dial and review without a payment"): return false
	if not await click("phone_tool_search","EVENING_WORK"): return false
	if not check(host.session.snapshot().wallets.player.VKC==before.wallets.player.VKC-10,"one real advance"): return false
	await capture("w19_outbound_receipt"+suffix,resolution)
	if not await click_navigation(host,"terms_tool_search"): return false
	if not await click("phone_tool_search","EVENING_WORK"): return false
	if not check(host.session.snapshot().wallets.player.VKC==before.wallets.player.VKC,"actual refund"): return false
	if not await click_navigation(host,"close_drawer"): return false
	if not await click_navigation(host,"ledger"): return false
	await capture("w19_evening_ledger"+suffix,resolution)
	return check(initial.revision<host.session.snapshot().revision,"bounded first-day progression")
