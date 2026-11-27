extends "res://tests/b3_w20_pointer_window.gd"
## Actual title entry and normal F5 A/B generations, with a fresh directory per native resolution.
const Title = preload("res://scenes/app/main_menu.tscn")
const Preferences = preload("res://src/presentation/ui_preferences.gd")
const Surface = preload("res://src/presentation/surface_visuals.gd")
const F5_SLOT := "b3_f5_counter_v1"

func open_f5(directory: String, language: String = "ko") -> bool:
	var preferences := Preferences.defaults()
	preferences.language = language
	var path := directory.path_join("ui_preferences.json")
	if not FileAccess.file_exists(path):
		if not check(Preferences.write(path,preferences),"write isolated title preferences"): return false
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
		and host._slot()==F5_SLOT and host.save_directory_override==directory.path_join("f5_counter")
		and host.counter_language==language,"real F5 menu entry opens the isolated F5 profile, save and title language")

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
	var language_suffix := "_en" if host.counter_language=="en" else ""
	await capture("f5_menu_first_item_"+str(resolution.y)+language_suffix,resolution)
	return true

func scale_in_appraisal(percent: int,resolution: Vector2i,original: Dictionary) -> bool:
	for id: String in ["preferences","font_"+str(percent),"close_drawer"]:
		if not await click_navigation(host,id): return false
	if not check(host.reading_scale==percent and host.zoom and not host.standing_actor.is_visible_in_tree()
			and host.session.snapshot()==original, "font size leaves the overhead visit and authority unchanged"): return false
	if not await click_navigation(host,"notes") or not await click_navigation(host,"book_surface"): return false
	if not comparison_controls_fit(): return false
	if visible_action("surface_judgment_open"):
		if not await click_navigation(host,"surface_judgment_open"): return false
	var book := host.find_child("r2_reference_desk",true,false) as Control
	var item := host.counter_item as Control
	var lift := host.find_child("finish_appraisal",true,false) as Control
	var grade := host.find_child("exterior_moderate",true,false) as Control
	var scroll := host.r2_book.scroll as Control
	var page := host.r2_book.pages as Control
	var price_tab := host.find_child("book_prices",true,false) as Button
	if not check(book!=null and item!=null and lift!=null and grade!=null and scroll!=null
		and page.size.x>=376 and grade.size.x>=44 and grade.size.y>=44
		and price_tab!=null and price_tab.autowrap_mode==TextServer.AUTOWRAP_OFF
		and price_tab.text==("Prices" if host.counter_language=="en" else "시세")
		and scroll.get_global_rect().encloses(grade.get_global_rect()) and root.get_visible_rect().encloses(book.get_global_rect())
		and not book.get_global_rect().intersects(item.get_global_rect())
		and not book.get_global_rect().intersects(lift.get_global_rect())
		and not visible_action("offer") and not visible_action("settle_trade"),
		"overhead book and item stay separately usable at this font size"): return false
	var language_suffix := "_en" if host.counter_language=="en" else ""
	await capture("f5_menu_overhead_%d_%d%s"%[percent,resolution.y,language_suffix],resolution)
	return await click_navigation(host,"close_drawer")

func comparison_controls_fit() -> bool:
	var viewport: Rect2 = host.r2_book.scroll.get_global_rect()
	var controls := ["material_write","material_hold","exterior_minimal","exterior_moderate","exterior_severe","exterior_unknown"]
	for family: String in Surface.MATERIALS:
		controls.append("reference_"+family)
	for id: String in controls:
		var target := host.find_child(id,true,false) as Button
		if not check(target!=null and target.is_visible_in_tree() and target.size.x>=44 and target.size.y>=44
			and viewport.encloses(target.get_global_rect()),"reference or judgment fits without scrolling: "+id):
			print("F5_COMPARISON_GEOMETRY id=%s scale=%d language=%s scroll=%s target=%s pages=%s"%[id,host.reading_scale,host.counter_language,viewport,target.get_global_rect() if target else Rect2(),host.r2_book.pages.get_global_rect()])
			return false
	for id: String in ["exterior_minimal","exterior_moderate","exterior_severe","exterior_unknown"]:
		var grade := host.find_child(id,true,false) as Button
		if not check(grade!=null and grade.autowrap_mode==TextServer.AUTOWRAP_OFF and grade.size.x>=grade.get_minimum_size().x,
			"wear judgment stays on one full readable line: "+id): return false
	for id: String in ["reference_base_caption","reference_wear_0_caption","reference_wear_1_caption","reference_wear_2_caption"]:
		var caption := host.find_child(id,true,false) as Label
		if not check(caption!=null and caption.is_visible_in_tree() and caption.autowrap_mode==TextServer.AUTOWRAP_OFF
			and caption.size.x>=caption.get_minimum_size().x and viewport.encloses(caption.get_global_rect()),
			"reference caption fits without splitting or clipping: "+id): return false
	return true

func toggle_counter_motion() -> bool:
	for id: String in ["preferences","motion","close_drawer"]:
		if not await click_navigation(host,id): return false
	return true

func negotiation_geometry(resolution: Vector2i) -> bool:
	var slots := ["news","fact_wear_detail","attachment_pocket","reappraise","alpha_finish_customer","counter_offer","offer"]
	var occupied: Array[Rect2] = []
	for id: String in slots:
		var target := host.find_child(id,true,false) as Control
		if not check(target!=null and target.is_visible_in_tree() and target.size.x>=44 and target.size.y>=44,
			"usable and visible negotiation target "+id): return false
		var bounds := target.get_global_rect()
		if not check(root.get_visible_rect().encloses(bounds),"negotiation target stays on screen: "+id): return false
		for prior: Rect2 in occupied:
			if not check(not prior.intersects(bounds),"negotiation targets have separate hit areas: "+id): return false
		occupied.append(bounds)
	var before: Dictionary = host.session.snapshot()
	if not await click_navigation(host,"notes"): return false
	var book := host.find_child("r2_reference_desk",true,false) as Control
	var price := host.find_child("counter_offer",true,false) as Control
	var offer := host.find_child("offer",true,false) as Control
	if not check(book!=null and price!=null and offer!=null and price.is_visible_in_tree() and offer.is_visible_in_tree()
		and not book.get_global_rect().intersects(price.get_global_rect())
		and not book.get_global_rect().intersects(offer.get_global_rect())
		and host.session.snapshot()==before,"opening claims and reference leaves the live offer slip accessible"):
		return false
	await capture("f5_menu_open_reference_offer_"+str(resolution.y),resolution)
	return await click_navigation(host,"close_drawer")

func inspect_and_offer(resolution: Vector2i) -> bool:
	var opening: Dictionary = host.session.snapshot()
	var item := host.counter_item as TextureRect
	var original_texture := item.texture
	var original_frame := Rect2(item.position,item.size)
	var model: String = host.session.alpha_view().appraisal.def_id
	if host.reduce_motion and not await toggle_counter_motion(): return false
	if not await start_counter_appraisal(true): return false
	var new_frame := Rect2(item.position,item.size)
	if not check(host.counter_item==item and host.session.alpha_view().appraisal.def_id==model
		and new_frame.get_center().distance_to(original_frame.get_center())>44
		and not host.standing_actor.is_visible_in_tree(),"head tilt moves the same real specimen to the mat and excludes the customer"): return false
	if item.get_meta("overhead_art",false):
		if not check(item.texture!=original_texture,"the overhead role uses separate authored art"): return false
	else:
		if not check(item.texture==original_texture and new_frame.size.is_equal_approx(original_frame.size),
			"missing overhead art leaves the original crop unscaled"): return false
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
	var observed_view: Dictionary = host.session.alpha_view().appraisal
	var surface := host.find_child("r2_observed_sample",true,false) as Control
	var descriptor: Dictionary = Surface.observed(observed_view.cards,"wear_detail",int(observed_view.surface_seed),observed_view.get("surface_profiles",{}))
	if not check(observed_view.item_id=="R001" and descriptor.get("base")=="metal" and str(descriptor.get("overlay","")).begins_with("metal_wear_"),"R001 acquired wear uses authored metal surface rather than neutral"): return false
	if not check(surface!=null and surface.is_visible_in_tree() and surface.get("sample")!=null
		and surface.size.x>=200 and not surface.get_global_rect().intersects(item.get_global_rect())
		and root.get_visible_rect().encloses(surface.get_global_rect()),"larger independent surface plate has valid texture and separate bounds"): return false
	await capture("f5_menu_observed_"+str(resolution.y),resolution)
	if not await click_navigation(host,"notes") or not await click_navigation(host,"book_surface"): return false
	var comparison_book := host.find_child("r2_reference_desk",true,false) as Control
	surface = host.find_child("r2_observed_sample",true,false) as Control
	if not check(comparison_book!=null and surface!=null and surface.is_visible_in_tree()
		and not surface.get_global_rect().intersects(comparison_book.get_global_rect())
		and not item.get_global_rect().intersects(comparison_book.get_global_rect())
		and host.session.snapshot()==observed,"surface, specimen and reference guide coexist without new authority changes"): return false
	await capture("f5_menu_surface_comparison_"+str(resolution.y),resolution)
	var actual_pixels := displayed_surface_pixels()
	for family: String in Surface.MATERIALS:
		if not await click_navigation(host,"reference_"+family): return false
		if not check(host.reference_material==family and host.session.snapshot()==observed
			and displayed_surface_pixels()==actual_pixels,"turning the reference changes only the book: "+family): return false
	if visible_action("surface_judgment_open"):
		if not await click_navigation(host,"surface_judgment_open"): return false
	if not await click("material_write","CUSTOMER_ACTIVE"): return false
	var judged: Dictionary = host.session.snapshot()
	if not check(judged.items==observed.items and judged.wallets==observed.wallets and judged.ledger==observed.ledger
		and host.session.alpha_view().appraisal.surface_judgments.material==host.reference_material,
		"a real page action writes private judgment without changing the item or presenting it"): return false
	if not check(displayed_surface_pixels()==actual_pixels and host.reference_material=="glass",
		"a different private guess cannot replace the observed surface"): return false
	if not await click("material_hold","CUSTOMER_ACTIVE"): return false
	if not check(host.session.alpha_view().appraisal.surface_judgments.get("material","unknown")=="unknown"
		and host.session.snapshot().ledger==observed.ledger,"defer clears the private material judgment without a trade"): return false
	if not await click_navigation(host,"close_drawer"): return false
	if not await leave_counter_appraisal(true) or not await click("fact_wear_detail","CUSTOMER_ACTIVE"): return false
	if not await choose_radio_offer_100(): return false
	var selected: Dictionary = host.session.snapshot()
	var basis: Dictionary = host.offer_basis.duplicate(true)
	var ratio: int = host.offer_ratio
	if not await start_counter_appraisal(true) or not await leave_counter_appraisal(true): return false
	if not check(host.session.snapshot()==selected and host.offer_basis==basis and host.offer_ratio==ratio
		and host.counter_item==item and host.standing_actor.is_visible_in_tree(),"reappraisal preserves the item, evidence and proportionate draft"): return false
	if not await negotiation_geometry(resolution): return false
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

func displayed_surface_pixels() -> PackedByteArray:
	var plate := host.find_child("r2_observed_sample",true,false) as Control
	if plate==null or not plate.is_visible_in_tree(): return PackedByteArray()
	var sample := plate.get("sample") as Texture2D
	return sample.get_image().get_data() if sample else PackedByteArray()

func menu_route(resolution: Vector2i) -> bool:
	var directory := "user://zt_rebuild/demo7/f5_menu_"+str(resolution.y)+"_"+str(Time.get_ticks_usec())
	if not await open_f5(directory) or not await enter_first_item(resolution) or not await inspect_and_offer(resolution): return false
	var settled: Dictionary = host.session.snapshot()
	await release_host()
	if not await open_f5(directory): return false
	if not check(not host._intro and host.session.snapshot()==settled and not visible_action("settle_trade"),
		"cold F5 title re-entry recovers the settled visit without another payment"): return false
	await capture("f5_menu_resumed_"+str(resolution.y),resolution)
	await release_host()
	return true

func english_reading_route(resolution: Vector2i) -> bool:
	var directory := "user://zt_rebuild/demo7/f5_menu_en_"+str(resolution.y)+"_"+str(Time.get_ticks_usec())
	if not await open_f5(directory,"en") or not await enter_first_item(resolution): return false
	var before: Dictionary = host.session.snapshot()
	if not await start_counter_appraisal(true): return false
	for percent: int in [100,125,150]:
		if not await scale_in_appraisal(percent,resolution,before): return false
	if not await leave_counter_appraisal(true): return false
	if not check(host.session.snapshot()==before,"English reference and camera leave visit state unchanged"): return false
	if not await start_counter_appraisal(true): return false
	var lens := host.find_child("tool_wear_detail",true,false) as Control
	var specimen := host.find_child("specimen",true,false) as Control
	if not await drag_between(lens,specimen): return false
	var acquired: Dictionary = host.session.snapshot()
	var pixels := displayed_surface_pixels()
	if not check(acquired.revision==before.revision+1 and not pixels.is_empty(),"one real F5 lens drop acquires the observed pixels"): return false
	if not await click_navigation(host,"apply_tool"): return false
	if not check(host.session.snapshot()==acquired and displayed_surface_pixels()==pixels,"reapplying a known lens is free and keeps the same pixels"): return false
	if not await click_navigation(host,"notes") or not comparison_controls_fit(): return false
	await capture("f5_menu_surface_comparison_"+str(resolution.y)+"_en",resolution)
	await release_host()
	if not await open_f5(directory,"en"): return false
	if not check(not host._intro and host.session.snapshot()==acquired,"cold title re-entry preserves the active observation"): return false
	if not await start_counter_appraisal(true) or not await click_navigation(host,"lens"): return false
	if not check(host.session.snapshot()==acquired and displayed_surface_pixels()==pixels,"restored observation reopens without a command and matches the earlier pixels"): return false
	await capture("f5_menu_surface_restored_"+str(resolution.y)+"_en",resolution)
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
		if not await english_reading_route(resolution):
			check(false,"English reference retains its usable layout at "+str(resolution.y))
			break
	await finish()
