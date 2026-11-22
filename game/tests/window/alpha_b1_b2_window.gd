extends SceneTree
## New alpha: real viewport, pixels and mouse-input route. No synthetic UI signals.
const B1 = preload("res://scenes/app/alpha_b1.tscn")
const B2 = preload("res://scenes/app/alpha_b2_trade_slice.tscn")
const B2Entry = preload("res://src/presentation/b2_launch_route.gd")
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
		printerr("FAIL: ", label)
	return ok

func frames() -> void:
	await process_frame
	await process_frame
	await process_frame

func capture(name: String, expected: Vector2i) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	if not check(pixels != null and not pixels.is_empty(), "rendered viewport " + name):
		return
	check(pixels.get_size() == expected, "real pixel dimensions " + name)
	check(pixels.save_png(out.path_join(name + ".png")) == OK, "screenshot " + name)

func click(name: String, phase: String) -> bool:
	var button := host.find_child(name, true, false) as Button
	if not check(button != null and button.is_visible_in_tree() and not button.disabled, "action visible " + name):
		return false
	var point: Vector2 = button.get_global_transform_with_canvas() * (button.size * 0.5)
	if not check(root.get_visible_rect().has_point(point), "button inside visible viewport " + name):
		return false
	var before: int = int(host.session.snapshot().revision)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.position = point
		event.global_position = point
		root.push_input(event, true)
	await frames()
	if name == "intro_skip":
		return check(not host._intro and host.session.snapshot().revision == before, "skip intro without state effect")
	return check(host.session.snapshot().revision == before + 1 and host.session.snapshot().alpha_shop.phase == phase, "pointer advances " + name + " to " + phase)

## Navigation pointers do not issue a shop command or increment the revision.
func click_navigation(scene: Control, button_id: String) -> bool:
	var button := scene.find_child(button_id,true,false) as Button
	if not check(button != null and button.is_visible_in_tree() and not button.disabled,
			"navigation control visible " + button_id):
		return false
	var point: Vector2=button.get_global_transform_with_canvas() * (button.size * 0.5)
	if not check(root.get_visible_rect().has_point(point),
			"navigation pointer within 720p " + button_id):
		return false
	for down: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=down
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
		event.position=point
		event.global_position=point
		root.push_input(event,true)
	await frames()
	return true

func install(scene: PackedScene, name: String) -> bool:
	host = scene.instantiate()
	host.save_directory_override = "user://zt_rebuild/window_" + name + "_" + str(Time.get_ticks_usec())
	root.add_child(host)
	await frames()
	return check(host.session != null and not host._blocked, "new alpha scene boots " + name) and check(host.theme != null and host.theme.default_font != null and host.theme.default_font.has_char(0xD55C) and host.theme.default_font.has_char(0xAE00), "verified Korean UI font supports Hangul glyphs")

func finish() -> void:
	if is_instance_valid(host):
		host.queue_free()
	await frames()
	print("ALPHA_B1_B2_WINDOW: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	out = args[0]
	root.size = Vector2i(1280, 720)
	if not await install(B1, "b1"):
		await finish()
		return
	var day_one: Dictionary = host.session.snapshot()
	await capture("alpha-b1-intro-720p", Vector2i(1280, 720))
	if not await click("intro_skip", "DAY_PREP"):
		await finish()
		return
	check(host.session.snapshot() == day_one, "intro skip keeps exact Day1 state")
	if not await click("alpha_open", "OPEN_IDLE") or not await click("alpha_next_customer", "CUSTOMER_ENTER") or not await click("alpha_ack_entry", "CUSTOMER_ACTIVE"):
		await finish()
		return
	check((host.find_child("alpha_speech", true, false) as Label).text.length() > 0, "same live counter has Korean dialogue")
	await capture("alpha-b1-customer-720p", Vector2i(1280, 720))
	root.size = Vector2i(1920, 1080)
	await frames()
	await capture("alpha-b1-customer-1080p", Vector2i(1920, 1080))
	if not await click("alpha_exchange_contact", "CUSTOMER_ACTIVE") or not await click("alpha_finish_customer", "CUSTOMER_EXIT") or not await click("alpha_ack_exit", "OPEN_IDLE") or not await click("alpha_close", "CLOSE_SETTLE") or not await click("alpha_settle", "EVENING_WORK"):
		await finish()
		return
	check(host.session.snapshot().alpha_shop.contacts.has("G01"), "consented contact saved in evening")
	var pre_preview: Dictionary = host.session.snapshot()
	var contact_button := host.find_child("alpha_contact_G01", true, false) as Button
	check(contact_button != null and not contact_button.disabled, "consented contact offered in evening only")
	if contact_button != null:
		contact_button.pressed.emit()
		await frames()
		var preview := host.find_child("alpha_contact_preview_text", true, false) as Label
		check(preview != null and preview.text.contains("선금") and preview.text.contains("지원하지"), "contact previews unmet order terms without fake dispatch")
		check(host.session.snapshot() == pre_preview, "contact preview does not touch money, ledger, items or save")
	root.size = Vector2i(1280, 720)
	await capture("alpha-b1-evening-contact-720p", Vector2i(1280, 720))
	root.size = Vector2i(1920, 1080)
	await capture("alpha-b1-evening-1080p", Vector2i(1920, 1080))
	if not await click("alpha_next_day", "NEXT_DAY") or not await click("alpha_prepare_day", "DAY_PREP"):
		await finish()
		return
	check(host.session.snapshot().alpha_shop.day == 2, "real Day2 after mouse clicks")
	host.queue_free()
	await frames()
	root.size = Vector2i(1280, 720)
	if not await install(B2, "b2"):
		await finish()
		return
	if not await click("intro_skip", "DAY_PREP") or not await click("alpha_open", "OPEN_IDLE") or not await click("alpha_next_customer", "CUSTOMER_ENTER") or not await click("alpha_ack_entry", "CUSTOMER_ACTIVE"):
		await finish()
		return
	await capture("alpha-b2-buy-720p", Vector2i(1280, 720))
	if not await click("b2_trade", "CUSTOMER_EXIT") or not await click("alpha_ack_exit", "OPEN_IDLE") or not await click("b2_display_R001", "OPEN_IDLE"):
		await finish()
		return
	check(host.session.snapshot().items.R001.inventory == "storefront_grid", "physical shelf owns purchased item")
	var shelf_basis: Dictionary=host.session.snapshot()
	if not await click("b2_withdraw_R001","OPEN_IDLE") or not await click("b2_display_R001","OPEN_IDLE"):
		await finish()
		return
	check(host.session.snapshot().items.R001.inventory=="storefront_grid" and host.session.snapshot().ledger==shelf_basis.ledger and host.session.snapshot().wallets==shelf_basis.wallets,"real pointer withdrawal and replacement preserve exact money and trade receipts")
	await capture("alpha-b2-shelf-720p", Vector2i(1280, 720))
	if not await click("alpha_next_customer", "CUSTOMER_ENTER") or not await click("alpha_ack_entry", "CUSTOMER_ACTIVE"):
		await finish()
		return
	root.size = Vector2i(1920, 1080)
	await frames()
	await capture("alpha-b2-sale-1080p", Vector2i(1920, 1080))
	if not await click("b2_trade", "CUSTOMER_EXIT") or not await click("alpha_ack_exit", "OPEN_IDLE") or not await click("alpha_close", "CLOSE_SETTLE") or not await click("alpha_settle", "EVENING_WORK"):
		await finish()
		return
	check(host.session.snapshot().ledger.size() == 2 and host.session.snapshot().wallets.player.VKC == 250, "two paid ledger transfers, no fictional money")
	await capture("alpha-b2-evening-1080p", Vector2i(1920, 1080))
	# Newly exposed opt-in menu entry uses the exact same multi-service B2
	# scene as the shared-counter integration test, never the legacy New Game.
	host.queue_free()
	await frames()
	root.size = Vector2i(1280, 720)
	if not check(ResourceLoader.exists(B2Entry.SCENE_PATH), "B2 unified entry route points to existing scene"):
		await finish()
		return
	var unified: PackedScene = load(B2Entry.SCENE_PATH) as PackedScene
	if not check(unified != null, "B2 unified menu route resolves a packed scene"):
		await finish()
		return
	if not await install(unified, "b2_unified"):
		await finish()
		return
	check(host._slot()=="alpha_b2_service_custody_multi_v3"
		and host.b2_interactive_mode and host.b2_commission_mode and host.b2_multi_service_mode,
		"B2 unified entry starts its independent multi-authority profile")
	await capture("alpha-b2-unified-intro-720p",Vector2i(1280,720))
	if not await click("intro_skip","DAY_PREP") or not await click("alpha_open","OPEN_IDLE") 			or not await click("alpha_next_customer","CUSTOMER_ENTER") or not await click("alpha_ack_entry","CUSTOMER_ACTIVE"):
		await finish()
		return
	check(host.session.alpha_view().active.actor_id=="G01" and host.find_child("b2_price_input",true,false)!=null,
		"unified entry has the real first customer's appraisal and price controls")
	var sticky_finish := host.find_child("alpha_finish_customer",true,false) as Button
	var right_board := host.find_child("alpha_shop_board",true,false) as PanelContainer
	check(sticky_finish!=null and right_board!=null and right_board.is_ancestor_of(sticky_finish),
		"B2 finish control is anchored in the permanent right-hand notebook, not buried in card scrolling")
	await capture("alpha-b2-unified-g01-720p",Vector2i(1280,720))
	if not await click("alpha_finish_customer","CUSTOMER_EXIT") or not await click("alpha_ack_exit","OPEN_IDLE") 			or not await click("alpha_next_customer","CUSTOMER_ENTER") or not await click("alpha_ack_entry","CUSTOMER_ACTIVE"):
		await finish()
		return
	check(host.session.alpha_view().active.actor_id=="G02" and host.find_child("b2_service_accept",true,false)!=null,
		"same unified 720p counter exposes G02's actual service offer")
	await capture("alpha-b2-unified-g02-service-720p",Vector2i(1280,720))
	# The real B2 pilot must be able to leave via visible mouse input and
	# recover its actual title menu. Returning is pure navigation: no grant,
	# settlement or offscreen second shop command.
	var saved: Dictionary=host.session.snapshot()
	var isolated_root: String=host._repo._root
	current_scene=host
	if not await click_navigation(host,"b2_return_title"):
		await finish()
		return
	var title := current_scene as Control
	if not check(title != null and title.name=="MainMenu"
			and title.find_child("menu_new",true,false)!=null
			and title.find_child("menu_continue",true,false)!=null
			and title.find_child("menu_b2_unified",true,false)!=null,
			"title restores legacy New Game/Continue and unified B2 entry"):
		await finish()
		return
	await capture("alpha-b2-unified-return-title-720p",Vector2i(1280,720))
	if not await click_navigation(title,"menu_b2_unified"):
		await finish()
		return
	host=current_scene as Control
	if not check(host != null and host.b2_multi_service_mode
			and host.session != null and not host._blocked
			and host._slot()=="alpha_b2_service_custody_multi_v3",
			"mouse re-entry from title opens exact unified B2 non-legacy profile"):
		await finish()
		return
	check(host._repo._root != isolated_root and not host._repo._root.is_empty(),
		"title re-entry never imports the earlier window test's isolated A/B save directory")
	# Even after real scene exit, the prior shop's actual saved state can be
	# cold restored byte-for-byte from its original isolated A/B generation.
	var source_copy: Control=unified.instantiate()
	source_copy.save_directory_override=isolated_root
	root.add_child(source_copy)
	await frames()
	check(not source_copy._blocked and source_copy.session != null
		and source_copy.session.snapshot()==saved,
		"real title navigation preserves prior opt-in session and its saved economy exactly")
	source_copy.queue_free()
	await frames()
	# B3 is a separate opt-in scene. Its first real seller is presented in
	# the same tested physical counter; no default New Game migration.
	host.queue_free()
	await frames()
	var b3_scene: PackedScene=load("res://scenes/app/alpha_b3_market_m1.tscn") as PackedScene
	if not check(b3_scene!=null,"B3 finite market pilot has a real Godot scene"):
		await finish()
		return
	if not await install(b3_scene,"b3_market"):
		await finish()
		return
	check(host.b3_market_mode and host._slot()=="alpha_b3_market_m1_v1"
		and not host._blocked and host.session.snapshot().items.R001.owner_id=="G01",
		"B3 starts a separate seeded economy and never inherits the B2 test save")
	await capture("alpha-b3-market-m1-intro-720p",Vector2i(1280,720))
	if not await click("intro_skip","DAY_PREP") or not await click("alpha_open","OPEN_IDLE")
			or not await click("alpha_next_customer","CUSTOMER_ENTER")
			or not await click("alpha_ack_entry","CUSTOMER_ACTIVE"):
		await finish()
		return
	check(host.session.alpha_view().active.actor_id=="G01"
		and host.find_child("b2_price_input",true,false)!=null,
		"B3 physical counter still supports original actual-item appraisal/offer")
	await capture("alpha-b3-market-m1-g01-720p",Vector2i(1280,720))
	await finish()
