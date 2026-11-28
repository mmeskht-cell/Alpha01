extends "res://tests/b3_r2_product_integration_window.gd"
const Slots = preload("res://src/content/b3_campaign_slots.gd")
const Catalog = preload("res://src/domain/b3_integrated_catalog.gd")
const Play = preload("res://tests/fixtures/b3_campaign_play.gd")
const TitlePreferences = preload("res://src/presentation/ui_preferences.gd")
const TARGETS := {"food":"CS01","essentials":"CS05","hardware":"CS20","sealed":"CS17"}
const TEST_SIZES := {"720":Vector2i(1280,720),"1080":Vector2i(1920,1080)}
var title: Control

func boot_title(location: String) -> bool:
	var scene: String = ProjectSettings.get_setting("application/run/main_scene")
	if not check(scene=="res://scenes/app/main_menu.tscn","use production project entry"):
		return false
	title = (load(scene) as PackedScene).instantiate()
	title.set("save_directory_override",location)
	root.add_child(title)
	current_scene = title
	await frames()
	return check(title.find_child("menu_new",true,false)!=null and title.find_child("menu_f5_counter",true,false)==null
		and title.find_child("menu_civilian_supply",true,false)==null and title.find_child("menu_spatial_week",true,false)==null
		and title.find_child("technical_profiles",true,false)==null,"one product campaign in the real title")

func wait_for_shop(action_id: String) -> bool:
	if not await click_navigation(title,action_id): return false
	await create_timer(0.32).timeout
	await frames()
	host = current_scene as Control
	return check(is_instance_valid(host) and host.name=="B3CampaignShop" and host.session!=null and not host._blocked and host._slot()==Slots.KEY,"real title action opens regular B3 campaign")

func to_title() -> bool:
	if not await click_navigation(host,"preferences") or not await click_navigation(host,"return_title"):
		return false
	await create_timer(0.32).timeout
	await frames()
	title = current_scene as Control
	return check(is_instance_valid(title) and title.find_child("menu_new",true,false)!=null and title.find_child("menu_civilian_supply",true,false)==null,"counter returns to the same product title")

func damaged_slot(location: String,index: int) -> String:
	var path := Slots.directory(location,index)
	if DirAccess.make_dir_recursive_absolute(path)!=OK: return ""
	path = path.path_join(Slots.KEY+".a.json")
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null: return ""
	file.store_string("{damaged")
	file.close()
	return path

func menu_route(size: Vector2i,location: String) -> bool:
	var corrupt := damaged_slot(location,0)
	if not check(not corrupt.is_empty(),"fixture contains an occupied corrupt slot"): return false
	var prefs := TitlePreferences.defaults()
	prefs.font_size = 24
	prefs.motion = false
	prefs.sound = false
	prefs.language = "ko" if size.y==720 else "en"
	if not check(TitlePreferences.write(Slots.preferences_path(location),prefs),"title settings fixture"): return false
	if not await boot_title(location): return false
	var resume := title.find_child("menu_continue",true,false) as Button
	if not check(resume!=null and resume.disabled,"continue requires strictly valid save"): return false
	for key: String in ["menu_new","menu_continue","menu_load","menu_settings","menu_quit"]:
		var button := title.find_child(key,true,false) as Button
		if not check(button!=null and root.get_visible_rect().encloses(button.get_global_rect()) and button.size.y>=48,"title pointer target "+key): return false
	await capture("campaign_title_"+str(size.y)+"_"+str(prefs.language),size)
	if not await click_navigation(title,"menu_load"): return false
	var bad := title.find_child("menu_slot_1",true,false) as Button
	if not check(bad!=null and bad.disabled,"unusable generation is labelled and disabled"): return false
	if not await click_navigation(title,"menu_slot_back") or not await wait_for_shop("menu_new"): return false
	var initial: Dictionary = host.session.snapshot()
	if not check(host.save_directory_override==Slots.directory(location,1) and host.reading_scale==150 and host.counter_language==prefs.language and host.reduce_motion,"new campaign skips occupied damage and receives title preferences"): return false
	if not check(initial.alpha_shop.profile.integrated_catalog==1 and not initial.alpha_shop.profile.has("civilian_supply") and not initial.alpha_shop.profile.has("visit_plan_policy") and initial.wallets.player.VKC==180,"normal opening is the unchanged v1 integrated source"): return false
	if not check(AudioServer.is_bus_mute(0) and not host.sound.diagnostic_view().sound,"title mute reaches counter audio authority"): return false
	if not await click_navigation(host,"intro_mute"): return false
	var music_bus := AudioServer.get_bus_index("ZT Music")
	var sfx_bus := AudioServer.get_bus_index("ZT SFX")
	if not check(music_bus>=0 and sfx_bus>=0 and not AudioServer.is_bus_mute(0) and not AudioServer.is_bus_mute(music_bus)
		and not AudioServer.is_bus_mute(sfx_bus) and host.sound.diagnostic_view().sound and TitlePreferences.read(Slots.preferences_path(location)).sound,"intro unmute restores channels and persists"): return false
	if not await click_navigation(host,"intro_motion"): return false
	if not check(not host.reduce_motion and host.sound.diagnostic_view().motion and TitlePreferences.read(Slots.preferences_path(location)).motion,"intro motion preference persists"): return false
	if not await click_navigation(host,"intro_motion"): return false
	if not check(host.reduce_motion and not host.sound.diagnostic_view().motion and not TitlePreferences.read(Slots.preferences_path(location)).motion,"intro reduced motion restored on disk"): return false
	for beat in range(5):
		if not await click_navigation(host,"intro_next"): return false
	if not await click("alpha_open","OPEN_IDLE"): return false
	var settings_revision: int = host.session.snapshot().revision
	if not await click_navigation(host,"preferences") or not await click_navigation(host,"mute"): return false
	if not check(AudioServer.is_bus_mute(0) and AudioServer.is_bus_mute(sfx_bus) and not host.sound.diagnostic_view().sound
		and not TitlePreferences.read(Slots.preferences_path(location)).sound,"counter mute updates both authorities and disk"): return false
	if not await click_navigation(host,"mute"): return false
	if not check(not AudioServer.is_bus_mute(0) and not AudioServer.is_bus_mute(sfx_bus) and host.sound.diagnostic_view().sound
		and host.session.snapshot().revision==settings_revision,"counter unmute restores channel without gameplay mutation"): return false
	if not await click_navigation(host,"close_drawer"): return false
	var progressed: Dictionary = host.session.snapshot()
	if not await to_title() or not await wait_for_shop("menu_continue"): return false
	if not check(host.session.snapshot()==progressed and not host._intro,"continue cold-replays actual played snapshot"): return false
	if not await to_title() or not await click_navigation(title,"menu_load"): return false
	var played_slot := title.find_child("menu_slot_2",true,false) as Button
	if not check(played_slot!=null and not played_slot.disabled and played_slot.text.contains("1일차" if prefs.language=="ko" else "Day 1"),"load menu displays actual restored day"): return false
	if not await wait_for_shop("menu_slot_2"): return false
	if not check(host.session.snapshot()==progressed and FileAccess.get_file_as_string(corrupt)=="{damaged","explicit load replays and preserves damaged slot bytes"): return false
	await capture("campaign_continued_"+str(size.y),size)
	# Seed an explicit versioned fixture in the third slot. Loading it uses
	# the same real title/counter; no trial-mode button is exposed.
	var v2_source: Dictionary = preload("res://src/content/b3_integrated_campaign_seed.gd").content(105,2)
	var v2 := Play.fresh(v2_source)
	if not check(v2!=null and Play.go(v2,"alpha_open"),"versioned integrated fixture opens"): return false
	var v2_state: Dictionary = v2.snapshot()
	var v2_disk := ProductRepo.new(Slots.directory(location,2))
	if not check(v2_disk.save_session(v2,Slots.KEY).get("ok",false),"versioned product fixture saved"): return false
	if not await to_title(): return false
	if not await click_navigation(title,"menu_load") or not await wait_for_shop("menu_slot_3"): return false
	if not check(host.session.snapshot()==v2_state and host.session.snapshot().alpha_shop.profile.get("visit_plan_policy")==2
		and not host._intro,"same product title selects correct versioned source"): return false
	if not await to_title() or not await click_navigation(title,"menu_load") or not await wait_for_shop("menu_slot_2"): return false
	if not check(host.session.snapshot()==progressed and not host.session.snapshot().alpha_shop.profile.has("visit_plan_policy"),"previous v1 slot remains exactly loadable"): return false
	# Separate save root keeps the prior v1/v2/corrupt slot witness intact.
	var retry_location := location+"_retry"
	var retry := Play.fresh(preload("res://src/content/b3_integrated_campaign_seed.gd").content(105,3))
	if not check(retry!=null and Play.go(retry,"alpha_open"),"v3 fixture opens"): return false
	var retry_state: Dictionary = retry.snapshot()
	if not check(TitlePreferences.write(Slots.preferences_path(retry_location),prefs)
		and ProductRepo.new(Slots.directory(retry_location,0)).save_session(retry,Slots.KEY).get("ok",false),"isolated v3 product fixture saved"): return false
	if not await to_title(): return false
	title.set("save_directory_override",retry_location)
	# Opening the load list refreshes actual slot metadata from disk.
	if not await click_navigation(title,"menu_load") or not await wait_for_shop("menu_slot_1"): return false
	if not check(host.session.snapshot()==retry_state and host.session.snapshot().alpha_shop.profile.get("visit_plan_policy")==3,"real product loads v3 source without default activation"): return false
	# Actual integrated contact and recovery order, not a separate technical scene.
	if not await actions([["alpha_next_customer","CUSTOMER_ENTER"],["alpha_ack_entry","CUSTOMER_ACTIVE"],["alpha_contract_decline","CUSTOMER_ACTIVE"],["alpha_finish_customer","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"],["alpha_next_customer","CUSTOMER_ENTER"],["alpha_ack_entry","CUSTOMER_ACTIVE"]]): return false
	if not check(host.session.alpha_view().active.actor_id=="G01","real opening contact in integrated product"): return false
	if not await actions([["alpha_exchange_contact","CUSTOMER_ACTIVE"],["alpha_finish_customer","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"],["alpha_close","CLOSE_SETTLE"],["alpha_settle","EVENING_WORK"]]): return false
	if not await phone_route(size,true): return false
	var after_phone: Dictionary = host.session.snapshot()
	if not await to_title() or not await wait_for_shop("menu_continue"): return false
	return check(host.session.snapshot()==after_phone,"integrated product recovery advance and refund survive cold replay")

func settle_quote() -> bool:
	return await click_navigation(host,"use_counter_quote") and await actions([["offer","CUSTOMER_ACTIVE"],["settle_trade","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"]])

func appraise_model(target: String,row: Dictionary,model: Texture2D,size: Vector2i) -> bool:
	if not check(host.session.alpha_view().appraisal.item_id==target and visible_model(host.counter_item,model),"matching counter specimen "+target): return false
	if not await start_counter_appraisal(): return false
	if not check(visible_model(host.counter_item,model),"same physical article in inspection "+target): return false
	if row.functional:
		if not await click_navigation(host,"tool_function_detail") or not await click("apply_tool","CUSTOMER_ACTIVE"): return false
		if not check(host.session.alpha_view().appraisal.cards.any(func(card: Dictionary)->bool: return card.slot=="function_detail" and not card.public_active),"private function observation "+target): return false
	elif not str(row.family).is_empty():
		if not await inspect_product_surface("wear_detail",row.family): return false
		await frames()
		var caption := host.find_child("surface_caption",true,false) as Label
		var fold := host.find_child("lens",true,false) as Button
		var release := host.find_child("close_mat",true,false) as Button
		await capture("campaign_surface_geometry_"+target+"_"+str(size.y),size)
		if caption!=null and fold!=null and release!=null:
			print("B3_SURFACE_GEOMETRY ",JSON.stringify({"target":target,"caption":str(caption.get_global_rect()),"lines":caption.get_line_count(),"visible_lines":caption.get_visible_line_count(),"caption_min":str(caption.get_combined_minimum_size()),"caption_text":caption.text,"fold":str(fold.get_global_rect()),"release":str(release.get_global_rect()),"fold_min":str(fold.get_combined_minimum_size()),"release_min":str(release.get_combined_minimum_size())}))
		if not check(caption!=null and fold!=null and release!=null and caption.is_visible_in_tree() and fold.is_visible_in_tree() and release.is_visible_in_tree()
			and not caption.text.strip_edges().is_empty()
			and caption.get_visible_line_count()==caption.get_line_count()
			and caption.get_combined_minimum_size().x<=caption.size.x and caption.get_combined_minimum_size().y<=caption.size.y
			and caption.get_global_rect().position.x>=fold.get_global_rect().position.x-2.0
			and caption.get_global_rect().end.x<=release.get_global_rect().end.x+2.0
			and caption.get_global_rect().end.y<=minf(fold.get_global_rect().position.y,release.get_global_rect().position.y)
			and not fold.get_global_rect().intersects(release.get_global_rect()),"150 percent surface reading and lens actions remain separate "+target): return false
	else:
		if not await click_navigation(host,"tool_identity") or not await click("apply_tool","CUSTOMER_ACTIVE"): return false
		if not check(host.session.alpha_view().appraisal.surface_profiles.is_empty(),"uncertain sealed packaging has no fabricated specimen projection"): return false
	await capture("campaign_appraised_"+target+"_"+str(size.y),size)
	return await leave_counter_appraisal()

func product_route(target: String,size: Vector2i,location: String) -> bool:
	var route := Play.trade_witness(target)
	if not check(not route.is_empty(),"real opening plan produces both counterparties "+target): return false
	var session := Play.fresh(route.source)
	if not check(session!=null and session.restore(route.buy),"genuine pre-purchase replay fixture"): return false
	var prefs := TitlePreferences.defaults()
	prefs.language = "ko" if size.y==720 else "en"
	prefs.font_size = 24
	prefs.motion = false
	if not check(TitlePreferences.write(Slots.preferences_path(location),prefs) and ProductRepo.new(Slots.directory(location,0)).save_session(session,Slots.KEY).get("ok",false),"isolated profile and preferences ready"): return false
	if not await boot_title(location) or not await wait_for_shop("menu_continue"): return false
	if not check(host.session.snapshot()==route.buy and host.reading_scale==150 and host.counter_language==prefs.language,"product cold-load with 150% and chosen language"): return false
	var row: Dictionary = Catalog.models()[target]
	var specimen: Texture2D = CounterArt.ITEMS.model_texture(row.model,"inspection",target)
	var ask: int = int(host.session.alpha_view().customer_ask_vkc)
	var public_view: Dictionary = host.session.alpha_view()
	if not check(host._counter_speech(public_view).contains(str(ask)),"actual asking amount in localized customer line"): return false
	if not await appraise_model(target,row,specimen,size) or not await settle_quote(): return false
	var purchased: Dictionary = host.session.snapshot()
	if not check(purchased.items[target].owner_id=="player" and purchased.items[target].basis.VKC==ask,"physical purchase and cost basis"): return false
	if not await click_navigation(host,"stockroom") or not await click_navigation(host,"stock_"+target): return false
	var capacity := host.find_child("inventory_capacity",true,false) as Label
	if not check(capacity!=null and capacity.text.contains("/ 60") and capacity.text.contains("Occupied" if prefs.language=="en" else "사용"),"localized actual grid capacity"): return false
	var token := host.find_child("stock_"+target,true,false) as Control
	var sprite := token.get_node_or_null("ItemArt") as Sprite2D if token else null
	if not check(sprite!=null and sprite.is_visible_in_tree() and exact_model_face(sprite.texture,CounterArt.ITEMS.model_texture(row.model,"stock",target)),"stock image keeps exact same model "+target): return false
	# New click alternative is only a preview. Keep the original manual
	# placement route as a separate real pointer regression.
	if not await click_navigation(host,"preview_shelf_move"): return false
	if not check(host.session.snapshot()==purchased and host.draft.get("kind")=="alpha_display"
		and host.draft.result.ok and host.storage=="storefront_grid","shelf shortcut previews actual fit without mutation"): return false
	if not await click_navigation(host,"discard_draft"): return false
	if not check(host.session.snapshot()==purchased and host.draft.is_empty() and host.storage=="player_stock","cancel returns to original physical storage"): return false
	if not await click_navigation(host,"tab_storefront_grid") or not await click_navigation(host,"cell_0_0") or not await click("confirm_work","OPEN_IDLE"): return false
	if not check(host.session.snapshot().items[target].inventory=="storefront_grid","the real shelf holds the purchased article"): return false
	var displayed: Dictionary = host.session.snapshot()
	if not await click_navigation(host,"preview_stock_move"): return false
	if not check(host.session.snapshot()==displayed and host.draft.get("kind")=="alpha_withdraw_display" and host.draft.result.ok,"return shortcut remains read-only until confirmed"): return false
	if not await click("confirm_work","OPEN_IDLE"): return false
	var returned: Dictionary = host.session.snapshot()
	if not check(returned.items[target].inventory=="player_stock" and target not in returned.alpha_shop.displayed
		and returned.wallets==displayed.wallets and returned.ledger==displayed.ledger,"confirmed return preserves money and identity"): return false
	if not await click_navigation(host,"preview_shelf_move") or not await click("confirm_work","OPEN_IDLE"): return false
	var listed: Dictionary = host.session.snapshot()
	if not check(listed.items[target].inventory=="storefront_grid" and target in listed.alpha_shop.displayed
		and listed.wallets==returned.wallets and listed.ledger==returned.ledger,"confirmed shortcut re-lists the same physical stock"): return false
	await capture("campaign_display_"+target+"_"+str(size.y),size)
	if not await click_navigation(host,"close_drawer"): return false
	for day: int in range(int(purchased.alpha_shop.day),int(route.sale_day)):
		if not await next_morning(): return false
	if not await serve_until(Catalog.visit_id(target,false)): return false
	var bid: int = int(host.session.alpha_view().customer_bid_vkc)
	if not check(visible_model(host.counter_item,specimen),"repeat presentation preserves same specimen "+target): return false
	if not await start_counter_appraisal() or not await leave_counter_appraisal() or not await settle_quote(): return false
	var final: Dictionary = host.session.snapshot()
	var buyer: String = route.source.state.visits[Catalog.visit_id(target,false)].buyer
	if not check(final.items[target].owner_id==buyer and final.items[target].provenance_id==route.buy.items[target].provenance_id and final.items[target].basis.VKC==ask
		and final.wallets.player.VKC==route.buy.wallets.player.VKC-ask+bid
		and final.wallets[buyer].VKC==route.buy.wallets[buyer].VKC-bid+(ask if buyer==route.buy.items[target].owner_id else 0)
		and final.ledger.size()==route.buy.ledger.size()+2,"actual finite settlements and lineage for "+target): return false
	await capture("campaign_resold_"+target+"_"+str(size.y),size)
	if target=="CS20":
		return await maintenance_ledger_route(size,location)
	return true

# Construct a real, paid workshop lifecycle in an isolated save and use
# the normal product title and document UI to read the resulting ledger.
func maintenance_ledger_route(size: Vector2i,location: String) -> bool:
	var route := Play.trade_witness("CS20",true)
	if not check(not route.is_empty(),"real faulty catalog hardware for ledger witness"): return false
	var fixture := Play.fresh(route.source)
	if not check(fixture!=null and fixture.restore(route.buy),"ledger fixture replay"): return false
	var trade := Play.transfer(fixture,"CS20")
	if not check(not trade.is_empty() and Play.go(fixture,"alpha_inspect",{"slot":"function_detail"})
		and Play.go(fixture,"alpha_card_toggle",{"slot":"function_detail","selected":true}),"ledger fixture discloses actual fault"): return false
	trade.amount -= clampi(roundi(int(trade.amount)*0.10),1,3)
	if not check(Play.go(fixture,"alpha_price_offer",{"amount":trade.amount}) and fixture.alpha_view().appraisal.accepted.get("amount")==trade.amount
		and Play.go(fixture,"alpha_trade",trade) and Play.sequence(fixture,["alpha_ack_exit","alpha_close","alpha_settle"]),"ledger fixture genuine trade and evening phase"): return false
	var cost: Dictionary = fixture.alpha_stock_restore_cost("CS20")
	if not check(cost.VKC==5 and Play.go(fixture,"spatial_restore_item",{"actor":"player","item_id":"CS20"}),"ledger fixture pays for catalog repair"): return false
	var repaired: Dictionary = fixture.snapshot()
	var disposal: Dictionary = fixture.alpha_discard_preview("CS20")
	if not check(not disposal.is_empty() and disposal.payload.confirmed_ids==["CS20"]
		and fixture.snapshot()==repaired,"ledger fixture uses real read-only family preview"): return false
	if not check(Play.go(fixture,"spatial_discard",disposal.payload),"ledger fixture disposes same physical hardware"): return false
	var final: Dictionary = fixture.snapshot()
	var repair_event: Dictionary = repaired.object_events.back()
	var discard_event: Dictionary = final.object_events.back()
	if not check(final.wallets==repaired.wallets and discard_event.basis.VKC==trade.amount+cost.VKC and repair_event.expenses==cost
		and final.tombstones.has("CS20"),"disposal basis is not another cash payment"): return false
	# Preserve the real repaired state in a separate slot, then execute the
	# same disposition through the player's physical stock drawer.
	var live_fixture := Play.fresh(route.source)
	if not check(live_fixture!=null and live_fixture.restore(repaired)
		and ProductRepo.new(Slots.directory(location,1)).save_session(live_fixture,Slots.KEY).get("ok",false),"repaired article fixture saved"): return false
	if not await to_title() or not await click_navigation(title,"menu_load") or not await wait_for_shop("menu_slot_2"): return false
	if not check(host.session.snapshot()==repaired,"actual product loads repaired specimen"): return false
	if not await click_navigation(host,"stockroom") or not await click_navigation(host,"stock_CS20") or not await click_navigation(host,"f3_discard"): return false
	if not check(host.session.snapshot()==repaired and host.draft.get("kind")=="spatial_discard","real disposal preview leaves game unchanged"): return false
	if not await click_navigation(host,"discard_draft"): return false
	if not check(host.session.snapshot()==repaired and host.draft.is_empty(),"cancel does not dispose"): return false
	if not await click_navigation(host,"f3_discard") or not await click("confirm_work","EVENING_WORK"): return false
	var actual: Dictionary = host.session.snapshot()
	if not check(actual.wallets==final.wallets and actual.tombstones.has("CS20") and not actual.items.has("CS20")
		and actual.tombstones.CS20.basis==final.tombstones.CS20.basis and actual.ledger==final.ledger,"real confirmed disposal matches authority result"): return false
	var actual_discard: Dictionary = actual.object_events.back()
	if not await click_navigation(host,"close_drawer") or not await to_title() or not await click_navigation(title,"menu_load") or not await wait_for_shop("menu_slot_2"): return false
	if not check(host.session.snapshot()==actual,"actual disposal history persists after title reload"): return false
	if not await click_navigation(host,"ledger"): return false
	var repair_row := host.find_child("work_"+str(repair_event.event_id),true,false) as Button
	var discard_row := host.find_child("work_"+str(actual_discard.event_id),true,false) as Button
	var held := host.find_child("held_basis",true,false) as Label
	var totals := host.find_child("ledger_totals_heading",true,false) as Label
	var paid := host.find_child("maintenance_total",true,false) as Label
	var lost := host.find_child("discarded_basis",true,false) as Label
	if not check(repair_row!=null and discard_row!=null and paid!=null and lost!=null
		and paid.text.contains("5 VKC") and lost.text.contains("%d VKC"%int(discard_event.basis.VKC))
		and host.session.snapshot()==actual,"ledger shows actual non-F3 repair and loss separately, read-only"): return false
	if not check(totals!=null and totals.text.contains("All ledger totals" if size.y==1080 else "전체 장부 집계")
		and held!=null and held.text.contains("Held stock" if size.y==1080 else "보유 재고")
		and discard_row.get_index()<repair_row.get_index(),"stock basis visible and later disposal sorted before repair"): return false
	await capture("campaign_maintenance_ledger_"+str(size.y),size)
	if not await click_navigation(host,"close_drawer") or not await click_navigation(host,"news"): return false
	var market := host.find_child("market_notice_0",true,false) as Button
	if not check(market!=null and market.text.contains("Regional supply" if size.y==1080 else "지역 납품 공지")
		and host.session.snapshot()==actual,"actual news presents localized public supply information read-only"): return false
	await capture("campaign_market_news_"+str(size.y),size)
	return true

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=3 or not TEST_SIZES.has(args[1]) or (args[2]!="menu" and not TARGETS.has(args[2])) or DirAccess.make_dir_recursive_absolute(args[0])!=OK:
		quit(2)
		return
	out = args[0]
	var resolution: Vector2i = TEST_SIZES[args[1]]
	var location := "user://zt_rebuild/integrated_native_%s_%s_%d"%[args[1],args[2],Time.get_ticks_usec()]
	if await configure_native_window(resolution):
		var passed := false
		if args[2]=="menu":
			passed = await menu_route(resolution,location)
		else:
			passed = await product_route(TARGETS[args[2]],resolution,location)
		check(passed,"complete native product route "+args[1]+"/"+args[2])
	if is_instance_valid(title) and title==current_scene:
		title.get("_sound").shutdown_audio()
		await create_timer(0.25).timeout
		title.queue_free()
		await frames()
	await release_host()
	print("B3_CAMPAIGN_PRODUCT_WINDOW: ",checks," checks, ",failures," failures")
	Node.print_orphan_nodes()
	call_deferred("quit",0 if checks>0 and failures==0 else 1)
