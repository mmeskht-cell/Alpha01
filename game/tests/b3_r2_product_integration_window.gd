extends "res://tests/b3_w20_pointer_window.gd"
## Authored private integration walk. Requires permission to run and original R2 art.
const Review = preload("res://scenes/app/alpha_b3_r2_art_review.tscn")
const ProductSource = preload("res://src/content/b3_spatial_week_seed.gd")
const ProductSession = preload("res://src/domain/game_session.gd")
const ProductRepo = preload("res://src/persistence/save_repository.gd")
const CounterArt = preload("res://src/presentation/native_v23_art.gd")
const ProductSurface = preload("res://src/presentation/surface_visuals.gd")
const PRODUCT_SLOT := "spatial_week_v1"
const SupplyReview = preload("res://scenes/app/alpha_b3_civilian_supply.tscn")
const SupplySource = preload("res://src/content/b3_civilian_supply_seed.gd")
const SupplyRules = preload("res://src/domain/b3_civilian_supply.gd")
const SUPPLY_SLOT := "b3_civilian_supply_v1"
const ProductPlanner = preload("res://src/domain/alpha_b3_visit_randomizer.gd")
const ProductCommission = preload("res://src/domain/alpha_commission.gd")
const ProductService = preload("res://src/domain/alpha_service_custody.gd")

## Choose a reproducible authored seed for this particular pledge/FX route.
## Use the real planner with conservative eligibility and potential returns
## protected. Never alter a live campaign or inject a visitor into its plan.
func product_seed() -> int:
	var source: Dictionary = ProductSource.content(101)
	if source.is_empty(): return -1
	var profile: Dictionary = source.alpha_profile
	for candidate: int in range(101,613):
		var suitable := true
		for pair: Array in [[2,"watch_a"],[7,"alpha_b3_fx_broker_d7"]]:
			var day: int = pair[0]
			var rows: Array = profile.days[day-1]
			var available: Dictionary = {}
			var locked: Array = []
			for row: Dictionary in rows:
				var id: String = row.id
				available[id] = true
				if id in profile.visit_random.locked_ids or ProductCommission.is_return_visit(id,str(profile.commission_profile_id)) or ProductService.is_return_visit(id,str(profile.service_profile_id)):
					locked.append(id)
			var plan: Dictionary = ProductPlanner.plan(rows,available,locked,candidate,day)
			if not plan.get("ok",false) or not plan.visits.any(func(row: Dictionary)->bool: return row.id==pair[1]):
				suitable = false
				break
		if suitable: return candidate
	return -1

func install_product(resolution: Vector2i) -> bool:
	var seed_value: int = product_seed()
	if not check(seed_value>0,"reproducible authored pledge and FX seed exists"): return false
	var source: Dictionary = ProductSource.content(seed_value)
	var initial := ProductSession.new()
	if not check(initial.initialize(source.defs,source.state,false,false,{},source.alpha_profile),"valid initial product authority"): return false
	var location := "user://zt_rebuild/r2_product_"+str(resolution.y)+"_"+str(Time.get_ticks_usec())
	var db := ProductRepo.new(location)
	if not check(db.save_session(initial,PRODUCT_SLOT).get("ok",false),"save genuine revision-zero product fixture"): return false
	print("R2_PRODUCT_NATIVE_SEED ",seed_value," resolution=",resolution.y)
	host = Review.instantiate()
	host.save_directory_override = location
	root.add_child(host)
	await frames()
	return check(host.session!=null and not host._blocked and not host._intro and host._slot()==PRODUCT_SLOT and host.session.snapshot()==initial.snapshot(),"native product resumes the exact seeded revision-zero profile without replaying intro") and check(host.theme!=null and host.theme.default_font!=null and host.theme.default_font.has_char(0xD55C) and host.theme.default_font.has_char(0xAE00),"verified Korean UI font supports Hangul glyphs")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=1 or DirAccess.make_dir_recursive_absolute(args[0])!=OK:
		quit(2)
		return
	out = args[0]
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		if not await configure_native_window(resolution): break
		if not await install_product(resolution): break
		if not await shop_route(resolution,resolution.y==720):
			check(false,"complete product integration route "+str(resolution.y))
			break
		await release_host()
		if not await civilian_supply_route(resolution):
			check(false,"complete isolated civilian supply route "+str(resolution.y))
			break
		await release_host()
	await finish()

## Test planning does not inject visitors. Pick a seed where the real planner
## selects the target even with every candidate assumed eligible.
func supply_seed(target: String) -> Dictionary:
	for seed_value: int in range(104,168,4):
		var source: Dictionary = SupplySource.content(seed_value)
		if source.is_empty(): continue
		var profile: Dictionary = source.alpha_profile
		var included := true
		for suffix: String in ["_buy","_sale"]:
			var id := "civilian_"+target+suffix
			var day := floori(float(source.state.visits[id].opens)/1440.0)+1
			var rows: Array = profile.days[day-1]
			var eligible := {}
			var locked: Array = []
			for row: Dictionary in rows:
				eligible[row.id] = true
				if row.id in profile.visit_random.locked_ids or (day==1 and row.id=="visit_g01") or ProductCommission.is_return_visit(row.id,str(profile.commission_profile_id)) or ProductService.is_return_visit(row.id,str(profile.service_profile_id)):
					locked.append(row.id)
			var plan: Dictionary = ProductPlanner.plan(rows,eligible,locked,seed_value,day)
			if not plan.get("ok",false) or not plan.visits.any(func(row:Dictionary)->bool:return row.id==id):
				included = false
				break
		if included: return source
	return {}

func civilian_price(amount: int) -> bool:
	if not await click_navigation(host,"counter_offer"): return false
	await reveal_action("provisional_plus_1")
	for index in range(amount-1):
		if not await click_navigation(host,"provisional_plus_1"): return false
	await reveal_action("basis_provisional")
	if not await click_navigation(host,"basis_provisional") or not await click_navigation(host,"close_drawer"): return false
	var visible_amount := host.find_child("offer_amount",true,false) as Label
	return check(visible_amount!=null and visible_amount.text=="%d VKC"%amount,"player-authored provisional amount reaches actual offer docket")

func civilian_supply_route(resolution: Vector2i) -> bool:
	var target := "CS01" if resolution.y==720 else "CS05"
	var source := supply_seed(target)
	if not check(not source.is_empty(),"real seeded civilian purchase and later buyer can both be selected"): return false
	print("CIVILIAN_SUPPLY_NATIVE_SEED ",source.alpha_profile.visit_random.seed," target=",target," resolution=",resolution.y)
	var initial := ProductSession.new()
	if not check(initial.initialize(source.defs,source.state,false,false,{},source.alpha_profile),"new civilian source initializes"): return false
	var row: Dictionary = source.state.items[target]
	var buy_id := "civilian_"+target+"_buy"
	var sale_id := "civilian_"+target+"_sale"
	var buy: Dictionary = source.state.visits[buy_id]
	var sale: Dictionary = source.state.visits[sale_id]
	var buy_day := floori(float(buy.opens)/1440.0)+1
	var sale_day := floori(float(sale.opens)/1440.0)+1
	var cost := int(buy.prices[target].VKC)
	var resale := int(sale.prices[target].VKC)
	var location := "user://zt_rebuild/civilian_supply_native_"+str(resolution.y)+"_"+str(Time.get_ticks_usec())
	var disk := ProductRepo.new(location)
	if not check(disk.save_session(initial,SUPPLY_SLOT).get("ok",false),"new content isolated save slot"): return false
	host = SupplyReview.instantiate()
	host.save_directory_override = location
	host.title_preferences = {"language":"ko"}
	root.add_child(host)
	await frames()
	if not check(host.session!=null and not host._blocked and not host._intro and host.session.snapshot()==initial.snapshot(),"new scene reloads exact genuine civilian seed"): return false
	if not await click("alpha_open","OPEN_IDLE"): return false
	for day in range(1,buy_day):
		if not await next_morning(): return false
	if not await serve_until(buy_id): return false
	var model: Texture2D = CounterArt.ITEMS.model_texture(row.def_id,"inspection",target)
	if not check(host.session.alpha_view().appraisal.item_id==target and visible_model(host.counter_item,model),"actual civilian package on counter uses exact authored art"): return false
	if not await start_counter_appraisal(true): return false
	if not await inspect_product_surface("wear_detail","metal" if target=="CS01" else "paper"): return false
	await capture("civilian_supply_observed_"+str(resolution.y),resolution)
	if not await leave_counter_appraisal(true) or not await civilian_price(cost): return false
	if not await actions([["offer","CUSTOMER_ACTIVE"],["settle_trade","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"]]): return false
	var bought: Dictionary = host.session.snapshot()
	if not check(bought.items[target].owner_id=="player" and bought.items[target].basis.VKC==cost and bought.wallets.player.VKC==source.state.wallets.player.VKC-cost,"real civilian purchase changes owner, basis and cash once"): return false
	if not await click_navigation(host,"stockroom") or not await click_navigation(host,"stock_"+target): return false
	var token := host.find_child("stock_"+target,true,false) as Button
	var sprite := token.get_node_or_null("ItemArt") as Sprite2D if token else null
	var stock_art: Texture2D = CounterArt.ITEMS.model_texture(row.def_id,"stock",target)
	if not check(sprite!=null and sprite.is_visible_in_tree() and exact_model_face(sprite.texture,stock_art),"same civilian package visible in stock grid"): return false
	if not await click_navigation(host,"tab_storefront_grid") or not await click_navigation(host,"cell_0_0") or not await click("confirm_work","OPEN_IDLE"): return false
	await capture("civilian_supply_display_"+str(resolution.y),resolution)
	if not await click_navigation(host,"close_drawer"): return false
	for day in range(buy_day,sale_day):
		if not await next_morning(): return false
	if not await serve_until(sale_id): return false
	if not check(host.session.alpha_view().appraisal.item_id==target and visible_model(host.counter_item,model),"later real buyer sees same physical package"): return false
	if not await start_counter_appraisal(true) or not await leave_counter_appraisal(true) or not await civilian_price(resale): return false
	if not await actions([["offer","CUSTOMER_ACTIVE"],["settle_trade","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"]]): return false
	var end: Dictionary = host.session.snapshot()
	var recorded: Array = end.ledger.filter(func(entry:Dictionary)->bool:return target in entry.root_ids)
	if not check(end.items[target].owner_id==sale.buyer and end.items[target].provenance_id==row.provenance_id and recorded.size()==2
		and end.wallets.player.VKC==source.state.wallets.player.VKC-cost+resale and end.items.size()==source.state.items.size(),"civilian resale conserves identity and records exactly two settlements"): return false
	for currency: String in ["VKC","USD"]:
		var original := 0
		var current := 0
		for wallet: Dictionary in source.state.wallets.values(): original += int(wallet[currency])
		for wallet: Dictionary in end.wallets.values(): current += int(wallet[currency])
		if not check(original==current,"civilian trade conserves total "+currency): return false
	await capture("civilian_supply_resold_"+str(resolution.y),resolution)
	return true

func actions(steps: Array) -> bool:
	for step: Array in steps:
		if not await click(step[0],step[1]): return false
	return true

# The desk and stock views deliberately crop transparent margins. Validate the
# actual visible resource and its exact occupied bounds, not object identity alone.
func exact_model_face(shown: Texture2D, original: Texture2D) -> bool:
	if shown==null or original==null: return false
	var pixels := original.get_image()
	if pixels==null or pixels.is_empty(): return false
	var used := pixels.get_used_rect()
	if not used.has_area(): return false
	if used.size==pixels.get_size():
		return shown==original
	if not shown is AtlasTexture: return false
	var crop := shown as AtlasTexture
	return crop.atlas==original and crop.region==Rect2(used) and crop.margin==Rect2()

func visible_model(node: TextureRect, original: Texture2D) -> bool:
	return is_instance_valid(node) and node.is_visible_in_tree() and node.size.x>0 and node.size.y>0 and exact_model_face(node.texture,original)

func inspect_product_surface(slot: String,family: String) -> bool:
	for page in range(4):
		if visible_action("tool_"+slot): break
		if not await click_navigation(host,"more_tools"): return false
	if not await click_navigation(host,"tool_"+slot) or not await click("apply_tool","CUSTOMER_ACTIVE"): return false
	var a: Dictionary = host.session.alpha_view().appraisal
	var descriptor: Dictionary = ProductSurface.observed(a.cards,slot,int(a.surface_seed),a.get("surface_profiles",{}))
	var plate := host.find_child("r2_observed_sample",true,false) as Control
	var expected := ProductSurface.texture_for(descriptor)
	return check(descriptor.get("base")==family and expected!=null and plate!=null and plate.is_visible_in_tree() and plate.get("sample")==expected
		and a.cards.any(func(card:Dictionary)->bool:return card.slot==slot and not card.public_active),"observed "+str(a.item_id)+" "+slot+" displays only its acquired private surface")

func shop_route(resolution: Vector2i,refund: bool) -> bool:
	# This route starts from a real saved revision-zero profile. Fresh five-beat
	# intro and revision-zero resume are independently exercised by the menu and week routes.
	if not await actions([["alpha_open","OPEN_IDLE"],["alpha_next_customer","CUSTOMER_ENTER"],["alpha_ack_entry","CUSTOMER_ACTIVE"]]): return false
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
	var watch: Texture2D = CounterArt.ITEMS.model_texture("fictional_watch_p2","counter","WAT02")
	var visitor := host.standing_actor as TextureRect
	var portrait := CounterArt.customer_texture("G04")
	await capture("r2_c7_pledge_"+str(resolution.y),resolution)
	var correct_actor := check(host.session.alpha_view().active.actor_id=="G04" and portrait!=null and is_instance_valid(visitor) and visitor.is_visible_in_tree() and visitor.texture==portrait and visitor.size.x>0 and visitor.size.y>0,
		"real G04 pledge visit displays its nonempty authored portrait")
	var correct_face := check(visible_model(host.counter_item,watch),
		"real pledge counter displays the original Meridian face or its exact alpha crop")
	var correct_grid := check(host.session.spatial_dimensions("WAT02")==[1,1],"pledge watch retains its authoritative one-cell footprint")
	if not (correct_actor and correct_face and correct_grid): return false
	var pledge_button := host.find_child("week_pledge",true,false) as Button
	if not check(is_instance_valid(pledge_button) and pledge_button.is_visible_in_tree() and host.find_children("week_pledge","Button",true,false).size()==1,"presented pledge has one visible named control"): return false
	var before: Dictionary = host.session.snapshot()
	if not await start_counter_appraisal(true): return false
	if not check(is_instance_valid(pledge_button) and not pledge_button.is_visible_in_tree() and not visible_action("week_pledge"),"appraisal hides the retained pledge control without replacing it"): return false
	if not check(visible_model(host.counter_item,watch),"watch appraisal displays the same model face and exact crop as the counter"): return false
	if not await click_navigation(host,"turn_item"): return false
	var back: Texture2D = CounterArt.ITEMS.model_texture("fictional_watch_p2","inspection","WAT02",true)
	await capture("r2_c7_watch_caseback_"+str(resolution.y),resolution)
	var correct_back := check(back!=null and back!=watch and visible_model(host.counter_item,back),"watch flip displays the distinct authored caseback and exact crop")
	var unchanged := check(host.session.snapshot()==before,"watch flip and inspection navigation do not change authority")
	if not (correct_back and unchanged): return false
	if not check(host.session.alpha_view().appraisal.get("surface_profiles",{}).is_empty(),"unobserved watch surfaces not disclosed"): return false
	if not await inspect_product_surface("wear_detail","metal"): return false
	await capture("r2_c7_watch_back_surface_"+str(resolution.y),resolution)
	var acquired_back: Dictionary = host.session.snapshot()
	if not await click_navigation(host,"turn_item"): return false
	if not check(host.session.snapshot()==acquired_back and not visible_action("r2_observed_sample"),"front cannot display the rear observation after turning"): return false
	if not await inspect_product_surface("display_damage_detail","glass"): return false
	await capture("r2_c7_watch_front_surface_"+str(resolution.y),resolution)
	var inspected: Dictionary = host.session.snapshot()
	if not check(inspected.items==before.items and inspected.wallets==before.wallets and inspected.ledger==before.ledger,"watch surface observations preserve goods, cash and ledger"): return false
	if not await leave_counter_appraisal(true): return false
	await capture("r2_c7_pledge_negotiation_"+str(resolution.y),resolution)
	var slip := host.find_child("pledge_counter_slip",true,false) as Control
	var tray := host.find_child("attachment_pocket",true,false) as Control
	var request := host.find_child("visitor_papers",true,false) as Control
	if not check(slip!=null and slip.is_visible_in_tree() and is_instance_valid(pledge_button) and slip.get_global_rect().encloses(pledge_button.get_global_rect())
		and tray!=null and not slip.get_global_rect().intersects(tray.get_global_rect())
		and request!=null and not slip.get_global_rect().intersects(request.get_global_rect())
		and not slip.get_global_rect().intersects(host.counter_item.get_global_rect()),"pledge action sits on its own counter slip without covering the evidence, request or item"): return false
	if not check(is_instance_valid(pledge_button) and pledge_button.is_visible_in_tree() and host.find_child("week_pledge",true,false)==pledge_button and host.find_children("week_pledge","Button",true,false).size()==1,"negotiation restores the same unique pledge control"): return false
	if not await actions([["week_pledge","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"]]): return false
	if not check(not visible_action("week_pledge"),"settled pledge control no longer visible"): return false
	if not check(host.session.snapshot().items.WAT02.inventory=="pawn_grid" and host.session.snapshot().wallets.player.VKC==before.wallets.player.VKC-40,"pledge retains custody and exact principal"): return false
	var pledged: Dictionary = host.session.snapshot()
	if not await click_navigation(host,"stockroom") or not await click_navigation(host,"tab_pawn_grid"): return false
	if not await click_navigation(host,"stock_WAT02"): return false
	var stock := host.find_child("stock_WAT02",true,false) as Button
	var stock_art := stock.get_node_or_null("ItemArt") as Sprite2D if stock else null
	var detail := host.find_child("inventory_specimen",true,false) as TextureRect
	await capture("r2_c7_watch_pawn_inventory_"+str(resolution.y),resolution)
	var grid_face := check(is_instance_valid(stock_art) and stock_art.is_visible_in_tree() and exact_model_face(stock_art.texture,watch),"pawn grid displays the exact shared face or alpha crop")
	var detail_face := check(visible_model(detail,watch) and is_instance_valid(stock_art) and detail.texture==stock_art.texture,"pawn detail displays the same cached model face as the grid")
	var custody_unchanged := check(host.session.snapshot()==pledged,"pawn grid and detail inspection do not change custody or authority")
	if not (grid_face and detail_face and custody_unchanged): return false
	if not await click_navigation(host,"close_drawer"): return false
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
		var tool_before: Dictionary = host.session.snapshot()
		if not await start_counter_appraisal(true) or not await inspect_product_surface("wear_detail","metal"): return false
		await capture("r2_c4_tool_surface_"+str(resolution.y),resolution)
		var tool_after: Dictionary = host.session.snapshot()
		if not check(tool_after.items==tool_before.items and tool_after.wallets==tool_before.wallets and tool_after.ledger==tool_before.ledger,"tool observation preserves goods, money and ledger"): return false
		if not await leave_counter_appraisal(true): return false
		if not await actions([["alpha_finish_customer","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"]]): return false
	if not await click("alpha_close","CLOSE_SETTLE"): return false
	var before_document: Dictionary = host.session.snapshot()
	if not await click_navigation(host,"ledger"): return false
	if not await click_navigation(host,"folio_contracts"): return false
	for row: Array in [["pledge_principal","40 VKC"],["pledge_terms","45 VKC"],["pledge_due","4"]]:
		var field := host.find_child(row[0],true,false) as Label
		if not check(field!=null and field.is_visible_in_tree() and field.text.contains(row[1]),"pledge document separates authoritative term "+row[0]): return false
	if not check(host.session.snapshot()==before_document,"opening pledge document does not change authority"): return false
	var pledge_image := host.find_child("pledge_specimen",true,false) as TextureRect
	if not check(pledge_image!=null and pledge_image.is_visible_in_tree() and pledge_image.texture==watch,
		"pawn document shows the same front model used on the counter"): return false
	await capture("r2_c7_watch_pledge_document_"+str(resolution.y),resolution)
	await reveal_action("week_redeem")
	if not await click("week_redeem","CLOSE_SETTLE"): return false
	if not check(host.session.snapshot().alpha_shop.week_pawn.status=="redeemed","D4 redemption through original authority"): return false
	await capture("r2_c7_redeemed_"+str(resolution.y),resolution)
	if not await click_navigation(host,"close_drawer"): return false
	if not await actions([["alpha_settle","EVENING_WORK"],["alpha_next_day","NEXT_DAY"],["alpha_prepare_day","DAY_PREP"],["alpha_open","OPEN_IDLE"]]): return false
	if not await serve_until("hygiene_buy"): return false
	var paper_before: Dictionary = host.session.snapshot()
	if not check(host.session.alpha_view().appraisal.item_id=="HY05","real hygiene visit retains paper-wrapped specimen identity"): return false
	if not await start_counter_appraisal(true) or not await inspect_product_surface("wear_detail","paper"): return false
	await capture("r2_c7_hygiene_paper_"+str(resolution.y),resolution)
	var paper_after: Dictionary = host.session.snapshot()
	if not check(paper_after.items==paper_before.items and paper_after.wallets==paper_before.wallets and paper_after.ledger==paper_before.ledger,"paper observation adds knowledge without altering goods, money or ledger"): return false
	if not await leave_counter_appraisal(true): return false
	if not await actions([["alpha_finish_customer","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"]]): return false
	if not await next_morning() or not await next_morning(): return false
	if not await serve_until("alpha_b3_fx_broker_d7"): return false
	var broker := CounterArt.customer_texture("alpha_broker")
	var broker_node := host.standing_actor as TextureRect
	if not check(broker!=null and broker!=portrait and is_instance_valid(broker_node) and broker_node.is_visible_in_tree() and broker_node.texture==broker and broker_node.size.x>0 and broker_node.size.y>0,"the FX visit displays its distinct authored broker portrait"): return false
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
	for index in range(10):
		if not check(int(host.session.alpha_view().remaining)>0,"authored fixture still has a visit before "+visit_id):
			print("R2_PRODUCT_PLAN_DIAGNOSTIC day=",host.session.alpha_view().day," target=",visit_id," plan=",host.session.snapshot().alpha_shop.random_visits.plan)
			return false
		if not await actions([["alpha_next_customer","CUSTOMER_ENTER"],["alpha_ack_entry","CUSTOMER_ACTIVE"]]): return false
		var live: Dictionary = host.session.alpha_view()
		if live.active.id==visit_id: return true
		# Marcus requires an explicit contract decision before departure.
		# Use the same real decline control as the existing product route.
		if live.active.id=="alpha_marcus_intro" and live.contracts.get("rad1_first",{}).get("can_accept",false):
			if not await click("alpha_contract_decline","CUSTOMER_ACTIVE"): return false
		print("R2_VISIT_PASS day=",live.day," visit=",live.active.id," target=",visit_id)
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
