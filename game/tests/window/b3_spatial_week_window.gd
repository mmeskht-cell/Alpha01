extends "res://tests/window/alpha_b1_b2_window.gd"
const Spatial = preload("res://scenes/app/alpha_b3_week_candidate.tscn")

## Godot Ogg playback decoders may still be owned by the audio mixer immediately
## after stop(). Drain one bounded mixer interval before freeing each B3 host.
## Keep the real soundtrack and the strict leak assertion unchanged.
func release_host() -> void:
	if not is_instance_valid(host):
		return
	if is_instance_valid(host.sound):
		host.sound.shutdown_audio()
		await create_timer(0.25).timeout
	if is_instance_valid(host):
		host.queue_free()
	await frames()

func finish() -> void:
	await release_host()
	print("B3_SPATIAL_WEEK_WINDOW: ", checks, " checks, ", failures, " failures")
	# All nested await continuations must unwind before SceneTree teardown.
	# Keep the CI leak detector strict: never suppress the engine warning.
	Node.print_orphan_nodes()
	call_deferred("quit", 0 if failures == 0 else 1)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=1:
		quit(2)
		return
	out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1024,768),Vector2i(1440,900)]:
		root.size = resolution
		if not await install(Spatial,"spatial"):
			await finish()
			return
		var initial: Dictionary = host.session.snapshot()
		var location: String = host.save_directory_override
		for i: int in range(5):
			await capture("spatial_intro_%d_%d"%[i+1,resolution.y],resolution)
			if not await click_navigation(host,"intro_next"):
				await finish()
				return
		check(not host._intro and host.session.snapshot()==initial,"five beats preserve the exact opening")
		await release_host()
		host = Spatial.instantiate()
		host.save_directory_override = location
		root.add_child(host)
		await frames()
		check(not host._intro and host.session.snapshot()==initial,"resume at revision zero without repeating the intro")
		for step: Array in [["alpha_open","OPEN_IDLE"],["alpha_next_customer","CUSTOMER_ENTER"],["alpha_ack_entry","CUSTOMER_ACTIVE"],["alpha_contract_decline","CUSTOMER_ACTIVE"],["alpha_finish_customer","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"],["alpha_next_customer","CUSTOMER_ENTER"],["alpha_ack_entry","CUSTOMER_ACTIVE"]]:
			if not await click(step[0],step[1]):
				await finish()
				return
		check(host.session.alpha_view().active.id=="visit_g01","real G01 immediately follows Marcus")
		if not await click_navigation(host,"specimen"):
			await finish()
			return
		var before_book: Dictionary = host.session.snapshot()
		await click_navigation(host,"notes")
		await capture("spatial_reference_%d"%resolution.y,resolution)
		await click_navigation(host,"close_drawer")
		check(host.zoom and host.session.snapshot()==before_book,"book preserves inspection, visitor and entire economic state")
		var tool: Dictionary = host.session.alpha_view().appraisal.tools[0]
		await click_navigation(host,"tool_"+str(tool.id))
		var target: Button = host.find_child("apply_tool",true,false)
		if target != null and target.text=="뒤집어 조사":
			await click_navigation(host,"apply_tool")
		if not await click("apply_tool","CUSTOMER_ACTIVE") or not await click("fact_"+str(tool.id),"CUSTOMER_ACTIVE"):
			await finish()
			return
		var input := host.find_child("price",true,false) as LineEdit
		input.grab_focus()
		input.insert_text_at_caret("100")
		await frames()
		check(input.text == "100","edited live price field retains the 100 VKC draft")
		await capture("spatial_inspection_%d"%resolution.y,resolution)
		if not await click("offer","CUSTOMER_ACTIVE"):
			printerr("B3_SPATIAL_OFFER_DIAGNOSTIC displayed=",input.text,
				" draft=",host.price_text," message=",host._message,
				" revision=",host.session.snapshot().revision)
			await finish()
			return
		if not await click("settle_trade","CUSTOMER_EXIT"):
			await finish()
			return
		var paid: Dictionary = host.session.snapshot()
		check(paid.ledger.size()==1 and paid.items.R001.owner_id=="player" and paid.wallets.player.VKC==initial.wallets.player.VKC-100,"physical sale and finite wallet")
		await click("alpha_ack_exit","OPEN_IDLE")
		await click_navigation(host,"stockroom")
		await click_navigation(host,"stock_R001")
		await click_navigation(host,"tab_storefront_grid")
		var before_place: Dictionary = host.session.snapshot()
		await click_navigation(host,"cell_0_0")
		check(host.session.snapshot()==before_place,"placement draft preserves full authoritative state")
		await click_navigation(host,"discard_draft")
		check(host.selected=="R001" and host.session.snapshot()==before_place,"cancel keeps stock selection and ownership")
		await click_navigation(host,"cell_0_0")
		await click("confirm_work","OPEN_IDLE")
		check(host.session.snapshot().items.R001.inventory=="storefront_grid","actual grid listing")
		var listed: Dictionary = host.session.snapshot()
		var tag_input := host.find_child("Amount",true,false) as LineEdit
		check(tag_input!=null,"displayed item has a physical price slip")
		if tag_input==null:
			await finish()
			return
		tag_input.text = "145"
		await click("Apply","OPEN_IDLE")
		var priced: Dictionary = host.session.snapshot()
		check(priced.revision==listed.revision+1 and priced.ledger==listed.ledger and priced.items==listed.items and priced.wallets==listed.wallets,"repricing writes one tag without settling a sale")
		check(preload("res://src/domain/alpha_shop_cycle.gd").displayed_ask(priced,"R001")=={"amount":145,"currency":"VKC"},"shelf shows the journaled price for the selected instance")
		await capture("spatial_shelf_%d"%resolution.y,resolution)
		await release_host()
	if await install(Spatial,"spatial_skip"):
		var before: Dictionary = host.session.snapshot()
		await click_navigation(host,"intro_next")
		await click("intro_skip","DAY_PREP")
		check(host.session.snapshot()==before,"partial skip preserves seed, contract, medication, inventory and ledger")
	await finish()
