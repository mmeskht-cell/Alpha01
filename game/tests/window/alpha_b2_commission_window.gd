extends SceneTree
## Real pointer/checkpoint for one same-counter zero-deposit commission offer.
## Does not replace headless multi-day ownership and settlement tests.
const Scene = preload("res://scenes/app/alpha_b2_commission.tscn")
const NamedScene = preload("res://scenes/app/alpha_b2_named_commission.tscn")
var host: Control
var path: String
var checks: int=0
var failures: int=0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)
	return ok

func frames() -> void:
	await process_frame
	await process_frame
	await process_frame

func click(id: String) -> bool:
	var control := host.find_child(id,true,false) as Button
	if not check(control!=null and control.is_visible_in_tree() and not control.disabled,"button available "+id):
		return false
	var parent: Node=control.get_parent()
	while parent!=null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(control)
		parent=parent.get_parent()
	await frames()
	var screen: Vector2=control.get_global_transform_with_canvas()*(control.size*0.5)
	if not check(root.get_visible_rect().has_point(screen),"pointer inside viewport "+id):
		return false
	for down: bool in [true,false]:
		var e:=InputEventMouseButton.new()
		e.button_index=MOUSE_BUTTON_LEFT
		e.pressed=down
		e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
		e.position=screen
		e.global_position=screen
		root.push_input(e,true)
	await frames()
	return true

func shot(name: String, expected: Vector2i) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	var image: Image=root.get_texture().get_image()
	if not check(image!=null and not image.is_empty(),"frame captured "+name):
		return
	check(image.get_size()==expected and image.save_png(path.path_join(name+".png"))==OK,"real resolution "+name)

func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=1:
		quit(2)
		return
	path=args[0]
	root.size=Vector2i(1280,720)
	host=Scene.instantiate()
	host.save_directory_override="user://zt_rebuild/b2_commission_window_"+str(Time.get_ticks_usec())
	root.add_child(host)
	await frames()
	check(host.theme != null and host.theme.default_font != null and host.theme.default_font.has_char(0xD55C) and host.theme.default_font.has_char(0xAE00), "verified Korean UI font supports Hangul glyphs")
	if not check(host.session!=null and not host._blocked,"commission scene loads"):
		quit(1)
		return
	await shot("commission-intro-720p",Vector2i(1280,720))
	if not await click("intro_skip") or not await click("alpha_open"):
		quit(1)
		return
	for i: int in range(2):
		for id: String in ["alpha_next_customer","alpha_ack_entry","alpha_finish_customer","alpha_ack_exit"]:
			if not await click(id):
				quit(1)
				return
			if i == 0 and id == "alpha_ack_entry" and not await click("alpha_exchange_contact"):
				quit(1)
				return
	for id: String in ["alpha_next_customer","alpha_ack_entry"]:
		if not await click(id):
			quit(1)
			return
	check(host.session.alpha_view().active.actor_id=="G03","real same counter G03 request")
	check((host.find_child("alpha_speech",true,false) as Label).text.contains("공구"),"real customer speaks the request, not generic placeholder")
	var request_terms := host.find_child("b2_commission_status_tool_for_g03",true,false) as Label
	check(request_terms!=null and request_terms.text.contains("의뢰 조건") and request_terms.text.contains("D4") and not request_terms.text.contains("한 점을 구해"),"same-counter request is spoken once with compact terms receipt")
	check(host.find_child("alpha_contract_rad1_first",true,false)==null,"other supplier's contract is hidden during G03 request")
	var board := host.find_child("alpha_shop_board",true,false) as PanelContainer
	var scroller := host.find_child("alpha_card_scroll",true,false) as ScrollContainer
	var cash := host.find_child("b2_board_cash",true,false) as Label
	check(board!=null and scroller!=null and cash!=null,"commission shares original split shop counter")
	if board!=null and scroller!=null:
		check(board.get_global_rect().position.x > scroller.get_global_rect().end.x and board.get_global_rect().end.x <= 1280.0,"720p request and shop ledger each have visible nonoverlapping space")
	check(cash!=null and cash.text.contains("180 VKC"),"request preview does not mint cash or pay advance")
	await shot("commission-request-720p",Vector2i(1280,720))
	root.size=Vector2i(1920,1080)
	await frames()
	await shot("commission-request-1080p",Vector2i(1920,1080))
	if not await click("b2_commission_accept"):
		quit(1)
		return
	check(host.session.alpha_view().commissions.entries[0].status=="accepted" and host.session.snapshot().wallets.player.VKC==180,"mouse accepts obligation, no deposit")
	await shot("commission-accepted-1080p",Vector2i(1920,1080))
	for id: String in ["alpha_finish_customer","alpha_ack_exit","alpha_next_customer","alpha_ack_entry"]:
		if not await click(id):
			quit(1)
			return
	var named_visit: Dictionary = host.session.alpha_view()
	var named_speech := host.find_child("alpha_speech",true,false) as Label
	check(named_visit.active.actor_id == "marcus" and named_visit.active.kind == "named", "named actor uses same counter pointer path")
	check(named_speech != null and named_speech.text.contains("300 VKC") and named_speech.text.contains("D4") and not named_speech.text.contains("공구") and named_visit.npc_context.prior.is_empty(), "named Marcus explains actual RAD-1 supplier terms without learning G03 request")
	var supplier_slip := host.find_child("alpha_contract_rad1_first",true,false) as Label
	check(supplier_slip!=null and supplier_slip.text.contains("300 VKC") and not supplier_slip.text.contains("rad1_first") and host.find_child("b2_commission_status_tool_for_g03",true,false)==null,"named counter shows actual terms without internal IDs or foreign commission")
	await shot("commission-named-1080p",Vector2i(1920,1080))
	for id: String in ["alpha_finish_customer","alpha_ack_exit","alpha_close","alpha_settle"]:
		if not await click(id):
			quit(1)
			return
	var before_contact: Dictionary=host.session.snapshot()
	if not await click("alpha_contact_G01"):
		quit(1)
		return
	var preview := host.find_child("alpha_contact_preview_text",true,false) as Label
	check(preview!=null and preview.text.contains("선금"),"actual consent unlocks read-only night order conditions")
	check(host.session.snapshot()==before_contact,"night contact selection does not mutate session")
	await frames()
	var contact_scroll := host.find_child("alpha_card_scroll",true,false) as ScrollContainer
	var contact_panel := host.find_child("alpha_contact_preview",true,false) as Control
	var night_board := host.find_child("alpha_shop_board",true,false) as PanelContainer
	check(contact_scroll!=null and contact_panel!=null and night_board!=null and night_board.get_global_rect().intersects(contact_panel.get_global_rect()),"selected contact preview visible in right-hand night dossier rather than clipped action list")
	if contact_panel!=null:
		check(contact_panel.get_global_rect().end.y <= root.get_visible_rect().end.y,"night contact conditions fit without offscreen bottom at 1080p")
	await shot("commission-evening-contact-1080p",Vector2i(1920,1080))
	root.size=Vector2i(1280,720)
	var contact_720 := host.find_child("alpha_contact_preview",true,false) as Control
	check(contact_720!=null and contact_720.get_global_rect().end.y <= 720.0,"720p selected contact conditions fully visible without action-area scrolling")
	await shot("commission-evening-contact-720p",Vector2i(1280,720))
	host.queue_free()
	await frames()
	if not await run_named_counter():
		quit(1)
		return
	print("ALPHA_B2_COMMISSION_WINDOW: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)

## Separate named parity profile. Uses exactly the same scene script and
## mouse-controlled offer, physical procurement, reservation and handover.
func run_named_counter() -> bool:
	root.size = Vector2i(1280,720)
	host = NamedScene.instantiate()
	host.save_directory_override = "user://zt_rebuild/b2_named_window_" + str(Time.get_ticks_usec())
	root.add_child(host)
	await frames()
	if not check(host.session != null and not host._blocked and host._slot() == "alpha_b2_named_commission_parity_v1", "isolated named scene, distinct save slot"):
		return false
	if not await click("intro_skip") or not await click("alpha_open"):
		return false
	for actor: String in ["G01","G02","G03","marcus","ian"]:
		if not await click("alpha_next_customer") or not await click("alpha_ack_entry"):
			return false
		var view: Dictionary = host.session.alpha_view()
		check(str(view.active.actor_id) == actor,"actual named parity D1 visitor " + actor)
		if actor == "ian":
			var speech := host.find_child("alpha_speech",true,false) as Label
			var slip := host.find_child("b2_commission_status_hygiene_for_ian",true,false) as Label
			check(view.active.kind == "named" and speech != null and speech.text.contains("위생 물자") and slip != null and slip.text.contains("D5"),"Ian issues actual named incoming order, not RAD-1 replacement")
			check(host.find_child("b2_commission_status_tool_for_g03",true,false)==null,"Ian cannot see regular G03 request slip")
			await shot("named-ian-request-720p",Vector2i(1280,720))
			if not await click("b2_commission_accept"):
				return false
			check(host.session.snapshot().wallets.player.VKC == 180 and host.session.snapshot().alpha_shop.commissions.entries.hygiene_for_ian.status == "accepted","named mouse acceptance does not grant advance")
		if not await click("alpha_finish_customer") or not await click("alpha_ack_exit"):
			return false
	if not await click("alpha_close") or not await click("alpha_settle"):
		return false
	for d: int in [2,3,4]:
		for action: String in ["alpha_next_day","alpha_prepare_day","alpha_open","alpha_close","alpha_settle"]:
			if not await click(action):
				return false
	for action: String in ["alpha_next_day","alpha_prepare_day","alpha_open","alpha_next_customer","alpha_ack_entry"]:
		if not await click(action):
			return false
	check(host.session.alpha_view().active.actor_id == "G05","D5 source seller is existing G05, not fabricated stock")
	var price := host.find_child("b2_price_input",true,false) as LineEdit
	if not check(price != null,"D5 existing general appraisal-price input"):
		return false
	price.text = "60"
	for action: String in ["b2_offer","b2_trade","alpha_ack_exit"]:
		if not await click(action):
			return false
	check(host.session.snapshot().wallets.player.VKC==120 and host.session.snapshot().items.HY05.owner_id=="player","named job sources HY05 using real 60 VKC purchase")
	if not await click("b2_commission_reserve_HY05"):
		return false
	check(host.session.snapshot().items.HY05.reservation_id=="hygiene_for_ian","real physical item reserved for named actor")
	if not await click("alpha_next_customer") or not await click("alpha_ack_entry"):
		return false
	var ready: Dictionary = host.session.alpha_view()
	check(ready.active.actor_id == "ian" and ready.active.kind=="named","actual Ian D5 visit has named category")
	check(host.find_child("b2_commission_deliver",true,false)!=null,"same delivery action as regular G03 appears for named Ian")
	await shot("named-ian-ready-720p",Vector2i(1280,720))
	if not await click("b2_commission_deliver"):
		return false
	var state: Dictionary=host.session.snapshot()
	check(state.items.HY05.owner_id=="ian" and state.items.HY05.reservation_id.is_empty() and state.items.HY05.basis.VKC==60, "mouse delivered same HY05 with preserved original cost basis")
	check(state.wallets.player.VKC==210 and state.wallets.ian.VKC==25 and state.ledger.size()==2 and state.alpha_shop.commissions.settlements.size()==1, "named real customer funds and one settlement, no G03 ghost earnings")
	root.size=Vector2i(1920,1080)
	await shot("named-ian-settled-1080p",Vector2i(1920,1080))
	host.queue_free()
	await frames()
	return true
