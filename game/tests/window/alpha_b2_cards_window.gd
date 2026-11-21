extends SceneTree
## Independent true-window probe of the new B2 counter with real mouse clicks,
## preserved screen render at 1280x720 and 1920x1080. The price input value
## is assigned as UI text; the buttons are exercised via actual pointer events.
const Scene = preload("res://scenes/app/alpha_b2_cards.tscn")
var host: Control
var out: String
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
	return ok

func frames() -> void:
	await process_frame
	await process_frame
	await process_frame

func capture(name: String, expected: Vector2i) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if not check(image != null and not image.is_empty(), "screenshot exists " + name):
		return
	check(image.get_size() == expected and image.save_png(out.path_join(name+".png")) == OK,"real image at "+str(expected)+" "+name)

func click(id: String) -> bool:
	var button := host.find_child(id,true,false) as Button
	if not check(button != null and button.is_visible_in_tree() and not button.disabled,"interactive button "+id):
		return false
	var ancestor: Node = button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(button)
		ancestor = ancestor.get_parent()
	await frames()
	var point: Vector2 = button.get_global_transform_with_canvas() * (button.size*0.5)
	if not check(root.get_visible_rect().has_point(point),"pointer within screen "+id):
		return false
	for down: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.position = point
		event.global_position = point
		root.push_input(event,true)
	await frames()
	return true

func offer(amount: int) -> bool:
	var input := host.find_child("b2_price_input",true,false) as LineEdit
	if not check(input != null,"editable current quote input"):
		return false
	input.text = str(amount)
	return await click("b2_offer")

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	out = args[0]
	root.size = Vector2i(1280,720)
	host = Scene.instantiate()
	host.save_directory_override = "user://zt_rebuild/b2_cards_window_"+str(Time.get_ticks_usec())
	root.add_child(host)
	await frames()
	check(host.theme != null and host.theme.default_font != null and host.theme.default_font.has_char(0xD55C) and host.theme.default_font.has_char(0xAE00), "verified Korean UI font supports Hangul glyphs")
	if not check(host.session != null and not host._blocked,"B2 card scene boots"):
		quit(1)
		return
	await capture("b2-cards-intro-720p",Vector2i(1280,720))
	for key: String in ["intro_skip","alpha_open","alpha_next_customer","alpha_ack_entry"]:
		if not await click(key):
			quit(1)
			return
	var work_area := host.find_child("alpha_work_area",true,false) as HBoxContainer
	var scroller := host.find_child("alpha_card_scroll",true,false) as ScrollContainer
	var board := host.find_child("alpha_shop_board",true,false) as PanelContainer
	var cash := host.find_child("b2_board_cash",true,false) as Label
	check(work_area!=null and scroller!=null and board!=null and cash!=null, "one split counter presents actions and real ledger")
	if scroller!=null and board!=null:
		check(scroller.get_global_rect().end.x < board.get_global_rect().position.x and board.get_global_rect().end.x <= 1280.0,"720p split work surface fits viewport without overlapping buttons")
	check(cash!=null and cash.text.contains("180 VKC"),"ledger displays actual starting cash")
	var inspection_sheet := host.find_child("b2_inspection_sheet",true,false) as PanelContainer
	var private_sheet := host.find_child("b2_private_sheet",true,false) as PanelContainer
	var offer_sheet := host.find_child("b2_price_sheet",true,false) as PanelContainer
	check(inspection_sheet!=null and private_sheet!=null and offer_sheet!=null,"one scroll surface has inspect, private card and offer sections")
	if inspection_sheet!=null and private_sheet!=null and offer_sheet!=null:
		check(inspection_sheet.get_global_rect().position.y < private_sheet.get_global_rect().position.y and private_sheet.get_global_rect().position.y < offer_sheet.get_global_rect().position.y,"inspection and card selection precede price submission visually")
	var private_heading := host.find_child("b2_private_sheet_title",true,false) as Label
	check(private_heading!=null and private_heading.text.contains("개인 감정표"),"cards clearly marked private before choosing public disclosure")
	await capture("b2-cards-inspection-720p",Vector2i(1280,720))
	if not await click("b2_inspect_wear_detail") or not await click("b2_card_wear_detail") or not await offer(95):
		quit(1)
		return
	check(host.session.alpha_view().appraisal.accepted.get("amount",0) == 95, "real click accepted supported purchase price")
	var negotiated_speech := host.find_child("alpha_speech",true,false) as Label
	check(negotiated_speech != null and negotiated_speech.text.contains("95 VKC") and negotiated_speech.text.contains("1건"), "same customer speaks price and only one disclosed fact after real mouse offer")
	var response := host.find_child("b2_last_response",true,false) as Label
	check(response!=null and response.text.contains("공개 1건"),"post-offer visible receipt states only one shared fact")
	var evidence := host.find_child("b2_board_evidence",true,false) as Label
	check(evidence!=null and evidence.text.contains("공개 선택 1건"),"read-only side notebook shows only one explicitly disclosed card")
	await capture("b2-cards-agreement-720p",Vector2i(1280,720))
	for key: String in ["b2_trade","alpha_ack_exit","b2_display_R001","alpha_next_customer","alpha_ack_entry"]:
		if not await click(key):
			quit(1)
			return
	check(host.session.snapshot().items.R001.inventory == "storefront_grid","shelf contains actual item")
	var stocked := host.find_child("b2_board_stock",true,false) as Label
	check(stocked!=null and stocked.text.contains("진열 1"),"right-side notebook follows actual physical shelf state")
	root.size = Vector2i(1920,1080)
	await frames()
	await capture("b2-cards-buyer-1080p",Vector2i(1920,1080))
	if not await click("b2_inspect_function_detail") or not await click("b2_card_function_detail") or not await offer(175) or not await click("b2_trade"):
		quit(1)
		return
	check(host.session.snapshot().wallets.player.VKC == 260 and host.session.snapshot().ledger.size() == 2,"full two-sided economic loop from real mouse clicks")
	var sale_cash := host.find_child("b2_board_cash",true,false) as Label
	check(sale_cash!=null and sale_cash.text.contains("260 VKC"),"1080p side notebook reflects settled revenue, not a guessed offer")
	await capture("b2-cards-sale-1080p",Vector2i(1920,1080))
	var traded_speech := host.find_child("alpha_speech",true,false) as Label
	check(traded_speech != null and traded_speech.text.contains("거래가 끝났습니다"), "customer receives settled-exit dialogue only after actual wallet and stock transfer")
	for id: String in ["alpha_ack_exit","alpha_close","alpha_settle","alpha_next_day","alpha_prepare_day"]:
		if not await click(id):
			quit(1)
			return
	for day: int in [2,3]:
		for id: String in ["alpha_open","alpha_close","alpha_settle","alpha_next_day","alpha_prepare_day"]:
			if not await click(id):
				quit(1)
				return
	for id: String in ["alpha_open","alpha_next_customer","alpha_ack_entry"]:
		if not await click(id):
			quit(1)
			return
	check(host.session.alpha_view().active.actor_id == "G12" and host.session.alpha_view().npc_context.prior.is_empty(), "unrelated G12 has no earlier buyer disclosure")
	for id: String in ["alpha_finish_customer","alpha_ack_exit","alpha_next_customer","alpha_ack_entry"]:
		if not await click(id):
			quit(1)
			return
	var repeat_visit: Dictionary = host.session.alpha_view()
	var repeat_speech := host.find_child("alpha_speech",true,false) as Label
	check(repeat_visit.active.actor_id == "G01" and repeat_visit.npc_context.prior.offer.amount == 95, "same G01 comes back with real old public deal")
	check(repeat_speech != null and repeat_speech.text.contains("지난번") and repeat_speech.text.contains("95 VKC"), "returning customer actually speaks previous agreed quote")
	check(host.find_child("alpha_contract_rad1_first",true,false)==null,"ordinary repeat customer's counter hides unrelated named supplier contract")
	root.size = Vector2i(1280,720)
	await capture("b2-cards-return-g01-720p",Vector2i(1280,720))
	host.queue_free()
	await frames()
	print("ALPHA_B2_CARDS_WINDOW: ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
