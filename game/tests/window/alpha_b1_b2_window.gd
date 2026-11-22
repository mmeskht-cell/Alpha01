extends SceneTree
## New alpha: real viewport, pixels and mouse-input route. No synthetic UI signals.
const B1 = preload("res://scenes/app/alpha_b1.tscn")
const B2 = preload("res://scenes/app/alpha_b2_trade_slice.tscn")
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
	await finish()
