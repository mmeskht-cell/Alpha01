extends "res://tests/window/b3_spatial_week_window.gd"
## Supplemental pointer path. Existing full campaign and W17-W19 routes remain independent.
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=1 or DirAccess.make_dir_recursive_absolute(args[0])!=OK:
		quit(2)
		return
	out=args[0]
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		if not await configure_native_window(resolution): break
		if not await install(Spatial,"w20_pointer_"+str(resolution.y)): break
		if not await counter_drag(resolution): break
		await release_host()
	await finish()

# Run each resolution inside the physical Xvfb screen, without a title bar
# or retained window offset clipping the lower part of the 1080p client.
# This changes only the test window, not the shipped project's display mode.
func configure_native_window(resolution: Vector2i) -> bool:
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	var screen: int = root.current_screen
	var origin: Vector2i = DisplayServer.screen_get_position(screen)
	var screen_size: Vector2i = DisplayServer.screen_get_size(screen)
	if not check(screen_size.x>=resolution.x and screen_size.y>=resolution.y,"physical screen fits requested resolution"): return false
	root.position = origin
	root.size = resolution
	root.position = origin
	for frame in range(12):
		await process_frame
		if root.size==resolution and root.position==origin: break
	await frames()
	print("W20_WINDOW requested=",resolution," size=",root.size," position=",root.position," screen_origin=",origin," screen_size=",screen_size," viewport=",root.get_visible_rect()," scale=",root.get_screen_transform())
	if not check(root.size==resolution,"actual native window resolution"): return false
	if not check(Rect2i(origin,screen_size).encloses(Rect2i(root.position,root.size)),"whole native client inside physical screen"): return false
	var visible: Rect2 = root.get_visible_rect()
	# Verify near each corner in the logical input coordinate space before
	# installing the host. Do not silently select a different drag endpoint.
	for fraction: Vector2 in [Vector2(0.05,0.05),Vector2(0.95,0.05),Vector2(0.05,0.95),Vector2(0.95,0.95)]:
		if not check(await sync_pointer(visible.position+visible.size*fraction),"native pointer reaches viewport corner"): return false
	return true

# Root Viewport native drop validation may read the display-server pointer,
# rather than the coordinates of a synthetic push_input event. Keep both
# positions in sync, and fail rather than bypass native hit testing.
func sync_pointer(point: Vector2) -> bool:
	root.warp_mouse(point)
	for frame in range(8):
		await process_frame
		if root.get_mouse_position().distance_to(point)<=2.0: return true
	print("W20_POINTER_MISMATCH requested=",point," actual=",root.get_mouse_position()," window=",root.position," size=",root.size," display_pointer=",DisplayServer.mouse_get_position()," viewport=",root.get_visible_rect())
	return false

func drag_between(source: Control,target: Control) -> bool:
	if not check(is_instance_valid(source) and is_instance_valid(target),"drag endpoints exist"): return false
	if not check(source.is_visible_in_tree() and target.is_visible_in_tree(),"drag endpoints visible"): return false
	var start := source.get_global_transform_with_canvas()*(source.size*0.5)
	var end := target.get_global_transform_with_canvas()*(target.size*0.5)
	if not check(root.get_visible_rect().has_point(start) and root.get_visible_rect().has_point(end),"drag endpoints inside viewport"): return false
	if not check(await sync_pointer(start),"native pointer reaches drag source"): return false
	var begin := InputEventMouseMotion.new()
	begin.position=start
	begin.global_position=start
	root.push_input(begin,true)
	await frames()
	var hovered := root.gui_get_hovered_control()
	print("W20_DRAG_START source=",source.name," target=",target.name," start=",start," end=",end," hover=",str(hovered.get_path()) if is_instance_valid(hovered) else "none")
	var saw_drag := false
	var payload: Variant = null
	var prior := start
	for step in range(11):
		var point := start.lerp(end,float(step)/10)
		if not check(await sync_pointer(point),"native pointer matches drag motion"): return false
		var move := InputEventMouseMotion.new()
		move.position=point
		move.global_position=point
		move.relative=point-prior
		move.button_mask=0 if step==0 else MOUSE_BUTTON_MASK_LEFT
		root.push_input(move,true)
		if step==10:
			await process_frame
			var final_hover := root.gui_get_hovered_control()
			print("W20_DRAG_RELEASE requested=",point," actual=",root.get_mouse_position()," local=",target.get_local_mouse_position()," target_size=",target.size," hover=",str(final_hover.get_path()) if is_instance_valid(final_hover) else "none")
			if not check(Rect2(Vector2.ZERO,target.size).has_point(target.get_local_mouse_position()),"native release inside intended target"): return false
			if not check(root.gui_is_dragging(),"drag still active before native release"): return false
		if step==0 or step==10:
			var press := InputEventMouseButton.new()
			press.position=point
			press.global_position=point
			press.button_index=MOUSE_BUTTON_LEFT
			press.pressed=step==0
			press.button_mask=MOUSE_BUTTON_MASK_LEFT if step==0 else 0
			root.push_input(press,true)
		prior=point
		await process_frame
		if root.gui_is_dragging():
			saw_drag = true
			payload = root.gui_get_drag_data()
		if step==9:
			var over := root.gui_get_hovered_control()
			print("W20_DRAG_OVER dragging=",root.gui_is_dragging()," hover=",str(over.get_path()) if is_instance_valid(over) else "none"," payload=",payload," actual=",root.get_mouse_position()," target_local=",target.get_local_mouse_position())
	await frames()
	print("W20_DRAG_END started=",saw_drag," successful=",root.gui_is_drag_successful()," revision=",host.session.snapshot().revision)
	return check(saw_drag,"real GUI drag started") and check(root.gui_is_drag_successful(),"real GUI drop accepted")

func counter_drag(resolution: Vector2i) -> bool:
	for step: Array in [["intro_skip","DAY_PREP"],["alpha_open","OPEN_IDLE"],["alpha_next_customer","CUSTOMER_ENTER"],["alpha_ack_entry","CUSTOMER_ACTIVE"],["alpha_contract_decline","CUSTOMER_ACTIVE"],["alpha_finish_customer","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"],["alpha_next_customer","CUSTOMER_ENTER"],["alpha_ack_entry","CUSTOMER_ACTIVE"]]:
		if not await click(step[0],step[1]): return false
	var wear := host.find_child("tool_wear_detail",true,false) as Control
	for page in range(4):
		if is_instance_valid(wear) and wear.is_visible_in_tree(): break
		if not await click_navigation(host,"more_tools"): return false
		wear = host.find_child("tool_wear_detail",true,false) as Control
	if not check(is_instance_valid(wear) and wear.is_visible_in_tree(),"wear tool actually visible before drag"): return false
	var before: int = host.session.snapshot().revision
	if not await drag_between(host.find_child("tool_wear_detail",true,false),host.find_child("specimen",true,false)): return false
	if not check(host.session.snapshot().revision==before+1,"one real drag inspection"): return false
	if not await drag_between(host.find_child("fact_wear_detail",true,false),host.find_child("attachment_pocket",true,false)): return false
	if not check(host.session.snapshot().revision==before+2,"one attachment change"): return false
	var found := false
	for card: Dictionary in host.session.alpha_view().appraisal.cards:
		if card.slot=="wear_detail": found=card.selected and not card.public_active
	if not check(found,"attached evidence remains private before offer"): return false
	await capture("w20_attached_"+str(resolution.y),resolution)
	if not await click_navigation(host,"notes"): return false
	await capture("w20_surface_"+str(resolution.y),resolution)
	if not check(host.session.snapshot().revision==before+2,"opening reference has no authority effect"): return false
	return await valuation_update_route(resolution)

func valuation_update_route(resolution: Vector2i) -> bool:
	var initial: Dictionary = host.session.snapshot()
	if not await click_navigation(host,"book_prices"): return false
	if not await click_navigation(host,"basis_catalog_selvar_r18"): return false
	if not await click_navigation(host,"close_drawer"): return false
	for step in range(10):
		if not await click_navigation(host,"ratio_minus_5"): return false
	var amount := host.find_child("offer_amount",true,false) as Label
	if not check(amount!=null and amount.text=="100 VKC" and host.offer_ratio==500 and host.session.snapshot()==initial,"initial 50 percent offer is read-only"): return false
	if not await click_navigation(host,"notes"): return false
	if not await click_navigation(host,"book_surface"): return false
	if not await click_navigation(host,"surface_judgment_open"): return false
	if not await click("exterior_moderate","CUSTOMER_ACTIVE"): return false
	var judged: Dictionary = host.session.snapshot()
	if not check(judged.revision==initial.revision+1 and judged.wallets==initial.wallets and judged.ledger==initial.ledger and judged.items==initial.items,"new private judgment changes only authorized record"): return false
	if not await click_navigation(host,"close_drawer"): return false
	amount = host.find_child("offer_amount",true,false) as Label
	var basis := host.find_child("counter_offer",true,false) as Button
	if not check(amount!=null and amount.text=="100 VKC" and basis!=null and basis.text.contains("160"),"old offer frozen while new appraisal shown"): return false
	await capture("w20_valuation_pending_"+str(resolution.y),resolution)
	if not await click_navigation(host,"counter_offer"): return false
	if not await click_navigation(host,"basis_update"): return false
	if not await click_navigation(host,"close_drawer"): return false
	amount = host.find_child("offer_amount",true,false) as Label
	if not check(amount!=null and amount.text=="80 VKC" and host.offer_ratio==500 and host.session.snapshot()==judged,"explicit valuation update retains ratio and changes only draft"): return false
	var public: Dictionary = host.session.alpha_view().npc_context
	if not check(public.current_offer.is_empty() and public.latest_spoken.is_empty(),"private assessment and ratio never become NPC speech"): return false
	await capture("w20_valuation_applied_"+str(resolution.y),resolution)
	return true
