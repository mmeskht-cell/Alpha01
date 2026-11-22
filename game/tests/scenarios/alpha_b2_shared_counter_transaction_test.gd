extends SceneTree
## One real, finite D1 counter session: buy R001 from G01, list it, accept
## G02's independently owned W001 for service, sell R001 to that same G02,
## then accept G03's unrelated tool commission. No synthetic wallets/items.
const Scene = preload("res://scenes/app/alpha_b2_service_multi.tscn")
var host: Control
var checks: int = 0
var failures: int = 0

func check(ok: bool, title: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", title)
	return ok

func press(id: String) -> bool:
	var button := host.find_child(id,true,false) as Button
	if not check(button!=null and button.is_visible_in_tree() and not button.disabled,
			"single counter action is available: "+id):
		return false
	button.pressed.emit()
	return true

func enter(actor_id: String) -> bool:
	return press("alpha_next_customer") and press("alpha_ack_entry") and check(
		host.session.alpha_view().active.actor_id==actor_id,"real finite visitor "+actor_id)

func quote(amount: String) -> bool:
	var field := host.find_child("b2_price_input",true,false) as LineEdit
	if not check(field!=null,"common appraisal and sale price field is available"):
		return false
	field.text=amount
	return press("b2_offer")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	host=Scene.instantiate()
	host.save_directory_override="user://zt_rebuild/b2_combined_counter_"+str(Time.get_ticks_usec())
	root.add_child(host)
	await process_frame
	if not check(host.session!=null and not host._blocked and host.b2_interactive_mode
			and host.b2_commission_mode and host.b2_multi_service_mode,
			"same real B2 scene has card, contract and two-customer custody authority"):
		quit(1)
		return
	var initial: Dictionary=host.session.snapshot()
	if not check(initial.wallets.player.VKC==180 and initial.items.R001.owner_id=="G01"
			and initial.items.W001.owner_id=="G02" and initial.items.TL04.owner_id=="G01",
			"preexisting money and physical goods; no fixture mint"):
		quit(1)
		return
	if not press("intro_skip") or not press("alpha_open") or not enter("G01"):
		quit(1)
		return
	if not press("b2_inspect_wear_detail") or not press("b2_card_wear_detail") or not quote("95") 			or not press("b2_trade") or not press("alpha_ack_exit") or not press("b2_display_R001"):
		quit(1)
		return
	var listed: Dictionary=host.session.snapshot()
	check(listed.wallets.player.VKC==85 and listed.ledger.size()==1
		and listed.items.R001.owner_id=="player" and listed.items.R001.inventory=="storefront_grid",
		"G01 purchase then genuine shelf placement retained cost and wallet")
	if not enter("G02"):
		quit(1)
		return
	check(host.find_child("b2_service_accept",true,false)!=null
		and host.find_child("b2_price_input",true,false)!=null,
		"same G02 visit offers custody consent and retail purchase without a second menu")
	if not press("b2_service_accept"):
		quit(1)
		return
	var held: Dictionary=host.session.snapshot()
	check(held.items.W001.owner_id=="G02" and held.items.W001.custodian_id=="player"
		and held.items.W001.inventory=="service_grid" and held.wallets.player.VKC==85,
		"customer's service consent changes only custody, never title or cash")
	check(host.find_child("b2_display_W001",true,false)==null
		and host.find_child("b2_price_input",true,false)!=null,
		"customer-held item never becomes retail stock; independent card sale survives custody")
	if not press("b2_inspect_function_detail") or not press("b2_card_function_detail") 			or not quote("175") or not press("b2_trade") or not press("alpha_ack_exit"):
		quit(1)
		return
	var sold: Dictionary=host.session.snapshot()
	check(sold.wallets.player.VKC==260 and sold.ledger.size()==2
		and sold.items.R001.owner_id=="G02" and sold.items.R001.inventory=="G02_grid"
		and sold.items.R001.basis.VKC==95 and sold.alpha_shop.displayed.is_empty(),
		"same G02 pays for actually displayed radio with original cost and one settlement")
	check(sold.items.W001.owner_id=="G02" and sold.items.W001.custodian_id=="player",
		"completing G02's retail transaction does not return or sell the entrusted W001")
	if not enter("G03"):
		quit(1)
		return
	check(host.find_child("b2_commission_accept",true,false)!=null
		and host.find_child("b2_board_custody_W001",true,false)!=null,
		"third customer's independent request coexists with prior owner's held property")
	if not press("b2_commission_accept"):
		quit(1)
		return
	var concurrent: Dictionary=host.session.snapshot()
	check(concurrent.alpha_shop.commissions.entries.tool_for_g03.status=="accepted"
		and concurrent.items.W001.owner_id=="G02" and concurrent.items.W001.custodian_id=="player"
		and concurrent.wallets.player.VKC==260 and concurrent.ledger.size()==2,
		"new G03 obligation does not mint cash, copy radio or take G02 customer title")
	var location: String=host._repo._root
	var slot: String=host._slot()
	host.queue_free()
	await process_frame
	host=Scene.instantiate()
	host.save_directory_override=location
	root.add_child(host)
	await process_frame
	check(not host._blocked and host.session!=null and host._slot()==slot
		and host.session.snapshot()==concurrent,
		"same real UI profile cold resumes sale, held custody and open commission atomically")
	check(host.find_child("b2_board_custody_W001",true,false)!=null
		and host.find_child("b2_commission_status_tool_for_g03",true,false)!=null,
		"cold-resumed active G03 counter still renders actual obligations and custody title")
	host.queue_free()
	await process_frame
	print("ALPHA_B2_SHARED_COUNTER_CHECKS=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
