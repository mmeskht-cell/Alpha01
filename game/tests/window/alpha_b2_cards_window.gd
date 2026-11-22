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
	var item_surface := host.find_child("b2_item_surface",true,false) as PanelContainer
	var item_hotspots := host.find_child("b2_item_hotspots",true,false) as GridContainer
	check(item_surface!=null and item_hotspots!=null and item_surface.is_visible_in_tree(),"physical item surface has interactive inspection regions, not only a text list")
	var item_art := host.find_child("b2_item_art",true,false) as TextureRect
	var card_direction := host.find_child("b2_card_direction",true,false) as Label
	check(item_art != null and item_art.texture != null and item_art.is_visible_in_tree(),"real pre-existing item image is presented without inferred hidden qualities")
	if item_art != null:
		check(item_art.get_global_rect().end.y <= 720.0 and item_art.get_global_rect().position.y >= 0.0,"source-bound item art is fully in the first 720p viewport without hidden scrolling")
	check(card_direction != null and card_direction.text.contains("매입"),"buyer-side explanatory direction distinguishes source and destination without hidden math")
	if inspection_sheet!=null and private_sheet!=null and offer_sheet!=null:
		check(inspection_sheet.get_global_rect().position.y < private_sheet.get_global_rect().position.y and private_sheet.get_global_rect().position.y < offer_sheet.get_global_rect().position.y,"inspection and card selection precede price submission visually")
	var private_heading := host.find_child("b2_private_sheet_title",true,false) as Label
	check(private_heading!=null and private_heading.text.contains("개인 감정표"),"cards clearly marked private before choosing public disclosure")
	await capture("b2-cards-inspection-720p",Vector2i(1280,720))
	var zoom_btn := host.find_child("b2_zoom_toggle",true,false) as Button
	check(zoom_btn!=null,"real item image has direct enlargement control")
	if not await click("b2_zoom_toggle"):
		quit(1)
		return
	var enlarged := host.find_child("b2_item_art",true,false) as TextureRect
	check(enlarged!=null and enlarged.custom_minimum_size.y==260.0 and host.session.alpha_view().appraisal.cards.is_empty(),"native 720p pointer zoom enlarges same image, never uncovers uninspected truth")
	await capture("b2-cards-item-enlarged-720p",Vector2i(1280,720))
	if not await click("b2_zoom_toggle"):
		quit(1)
		return
	check((host.find_child("b2_item_art",true,false) as TextureRect).custom_minimum_size.y==144.0,"unzoom restores base image before evidence submission")
	var nav_button := host.find_child("b2_jump_b2_price_sheet",true,false) as Button
	var nav_event: Dictionary = {"hit":false}
	if nav_button != null:
		nav_button.pressed.connect(func() -> void: nav_event.hit = true)
	if not await click("b2_jump_b2_price_sheet"):
		quit(1)
		return
	var price_section := host.find_child("b2_price_sheet",true,false) as PanelContainer
	print("B2_NAV_DIAGNOSTIC pressed=",nav_event.hit," scroll=",scroller.scroll_vertical if scroller!=null else -1,
		" price_y=",price_section.get_global_rect().position.y if price_section!=null else -1,
		" viewport_end=",scroller.get_global_rect().end.y if scroller!=null else -1,
		" max=",scroller.get_v_scroll_bar().max_value if scroller!=null else -1)
	check(bool(nav_event.hit) and scroller!=null and scroller.scroll_vertical > 0 and price_section!=null and price_section.get_global_rect().position.y < scroller.get_global_rect().end.y,"actual button signal and pointer move must bring price form into visible work pane")
	if not await click("b2_jump_b2_inspection_sheet"):
		quit(1)
		return
	if not await click("b2_inspect_wear_detail") or not await click("b2_card_wear_detail") or not await offer(95):
		quit(1)
		return
	check(host.session.alpha_view().appraisal.accepted.get("amount",0) == 95, "real click accepted supported purchase price")
	var negotiated_speech := host.find_child("alpha_speech",true,false) as Label
	check(negotiated_speech != null and negotiated_speech.text.contains("95 VKC") and negotiated_speech.text.contains("1건"), "same customer speaks price and only one disclosed fact after real mouse offer")
	var response := host.find_child("b2_last_response",true,false) as Label
	check(response!=null and response.text.contains("공개 1건"),"post-offer visible receipt states only one shared fact")
	var disclosed := host.find_child("b2_offer_public_receipt",true,false) as Label
	check(disclosed!=null and disclosed.text.contains("외관 마모") and not disclosed.text.contains("기능 검사"),"public receipt exposes chosen card only, never private unread facts")
	var evidence := host.find_child("b2_board_evidence",true,false) as Label
	check(evidence!=null and evidence.text.contains("공개 선택 1건"),"read-only side notebook shows only one explicitly disclosed card")
	await capture("b2-cards-agreement-720p",Vector2i(1280,720))
	for key: String in ["b2_trade","alpha_ack_exit","b2_display_R001","alpha_next_customer","alpha_ack_entry"]:
		if not await click(key):
			quit(1)
			return
	check(host.session.snapshot().items.R001.inventory == "storefront_grid","shelf contains actual item")
	var sell_direction := host.find_child("b2_card_direction",true,false) as Label
	check(sell_direction != null and sell_direction.text.contains("판매"),"same art/cards/counter spells out sell-side economic role")
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
	# The return-visitor context also sells a real TL04 tool. It uses the
	# same inspection/card/offer surface, not a product-specific popup.
	var tool_view: Dictionary = host.session.alpha_view()
	check(tool_view.appraisal.item_id == "TL04" and tool_view.appraisal.def_id == "demo_tool","D4 original seller now has a generic provenance-bound tool")
	if not await click("b2_inspect_condition_detail"):
		quit(1)
		return
	var tool_card := host.find_child("b2_card_condition_detail",true,false) as Button
	check(tool_card != null and tool_card.text.contains("사용 가능") and not tool_card.text.contains("공개 이력"),"one actual tool condition starts privately in Korean")
	if not await click("b2_card_condition_detail") or not await offer(1):
		quit(1)
		return
	check(host.session.alpha_view().npc_context.current_offer.public_slots == ["condition_detail"] and host.session.snapshot().ledger.size() == 2,"only explicitly published tool evidence is heard; no third trade")
	await capture("b2-cards-generic-tool-720p",Vector2i(1280,720))
	host.queue_free()
	await frames()
	# Alternative same-customer negotiation: removing a disclosed card must not
	# make the next rebuttal or drawer falsely label it private again.
	host = Scene.instantiate()
	host.save_directory_override = "user://zt_rebuild/b2_cards_public_memory_window_" + str(Time.get_ticks_usec())
	root.add_child(host)
	await frames()
	if not check(host.session != null and not host._blocked,"public memory scenario boots without old save state"):
		quit(1)
		return
	for id: String in ["intro_skip","alpha_open","alpha_next_customer","alpha_ack_entry","b2_inspect_identity","b2_inspect_wear_detail","b2_card_wear_detail"]:
		if not await click(id):
			quit(1)
			return
	if not await offer(94) or not await click("b2_card_wear_detail"):
		quit(1)
		return
	var known_card := host.find_child("b2_card_wear_detail",true,false) as Button
	var private_card := host.find_child("b2_card_identity",true,false) as Button
	check(known_card != null and known_card.text.contains("공개 이력") and private_card != null and not private_card.text.contains("공개 이력"),"de-selected card stays public while never-shared identity stays private")
	if not await offer(95):
		quit(1)
		return
	var remembered_speech := host.find_child("alpha_speech",true,false) as Label
	check(remembered_speech != null and remembered_speech.text.contains("기억합니다") and remembered_speech.text.contains("외관 마모"),"real second-price mouse quote prompts remembered disclosed-fact rebuttal")
	check(host.session.alpha_view().npc_context.current_offer.known_slots == ["wear_detail"] and host.session.alpha_view().npc_context.current_offer.public_slots.is_empty(),"rendered rebuttal faithfully shows full public knowledge vs zero newly disclosed cards")
	var customer_claim := host.find_child("b2_customer_claim",true,false) as Label
	check(customer_claim != null and customer_claim.text.contains("고객 주장"),"actual counter separates unverified seller words from verified physical evidence")
	if not await click("b2_statement_retract_wear_detail"):
		quit(1)
		return
	var corrected_offer: Dictionary = host.session.alpha_view().npc_context.current_offer
	var correction_speech := host.find_child("alpha_speech",true,false) as Label
	check(corrected_offer.known_slots == ["wear_detail"] and corrected_offer.withdrawn_slots == ["wear_detail"] and corrected_offer.active_slots.is_empty(),"physical mouse withdrawal preserves customer recollection but changes public standing")
	check(correction_speech != null and correction_speech.text.contains("철회"),"NPC dialogue reacts to voluntary disclosure correction")
	await capture("b2-cards-public-withdrawal-720p",Vector2i(1280,720))
	if not await click("b2_statement_reaffirm_wear_detail"):
		quit(1)
		return
	check(host.session.alpha_view().npc_context.current_offer.active_slots == ["wear_detail"] and host.session.snapshot().alpha_shop.appraisal.visits.visit_g01.statements.size() == 2,"same real mouse drawer reaffirms without making another economic offer")
	await capture("b2-cards-public-memory-720p",Vector2i(1280,720))
	host.queue_free()
	await frames()
	print("ALPHA_B2_CARDS_WINDOW: ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
