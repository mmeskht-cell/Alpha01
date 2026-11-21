extends SceneTree
## One and the same Control scene for ordinary visitors and an actual
## commission; UI signals must flow through GameSession and save A/B.
const Scene = preload("res://scenes/app/alpha_b2_commission.tscn")
var host: Control
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
	return ok

func press(id: String) -> bool:
	var button := host.find_child(id,true,false) as Button
	if not check(button != null and not button.disabled and button.is_visible_in_tree(), "one-counter action "+id):
		return false
	button.pressed.emit()
	return true

func enter() -> bool:
	return press("alpha_next_customer") and press("alpha_ack_entry")

func exit_customer() -> bool:
	return press("alpha_finish_customer") and press("alpha_ack_exit")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	host=Scene.instantiate()
	host.save_directory_override="user://zt_rebuild/b2_commission_host_"+str(Time.get_ticks_usec())
	root.add_child(host)
	await process_frame
	check(host.theme != null and host.theme.default_font != null and host.theme.default_font.has_char(0xD55C) and host.theme.default_font.has_char(0xAE00), "verified Korean UI font supports Hangul glyphs")
	if not check(host.session != null and not host._blocked and host.b2_commission_mode,"commission scene boots, separate save profile"):
		quit(1)
		return
	if not press("intro_skip") or not press("alpha_open"):
		quit(1)
		return
	for actor: String in ["G01","G02"]:
		if not enter() or not check(host.session.alpha_view().active.actor_id==actor,"visit "+actor):
			quit(1)
			return
		if actor == "G01":
			check(press("alpha_exchange_contact"),"actual agreed G01 contact in D1 counter")
		if not exit_customer():
			quit(1)
			return
	if not enter() or not check(host.session.alpha_view().active.actor_id=="G03","same regular G03 customer"):
		quit(1)
		return
	var request_slip := host.find_child("b2_commission_status_tool_for_g03",true,false) as Label
	check(request_slip != null and request_slip.text.contains("D4") and not request_slip.text.contains("D4.0"),"commission due date shown as whole day")
	check((host.find_child("alpha_speech",true,false) as Label).text.contains("공구"),"G03 request is spoken in same dialogue bubble")
	check(press("b2_commission_accept"),"customer request accepted by UI")
	check(host.session.snapshot().wallets.player.VKC==180 and host.session.alpha_view().commissions.entries[0].status=="accepted","no advance paid or fake wallet")
	if not exit_customer() or not press("alpha_close") or not press("alpha_settle"):
		quit(1)
		return
	var snapshot_before_preview: Dictionary=host.session.snapshot()
	check(press("alpha_contact_G01"),"consented night contact is selectable")
	var preview := host.find_child("alpha_contact_preview_text",true,false) as Label
	check(preview != null and preview.text.contains("선금") and preview.text.contains("지원하지"),"read-only conditions disclose missing real advance/order")
	check(host.session.snapshot()==snapshot_before_preview,"preview never alters authoritative B2 commission state")
	if not press("alpha_next_day") or not press("alpha_prepare_day"):
		quit(1)
		return
	for day: int in [2,3]:
		if not press("alpha_open") or not press("alpha_close") or not press("alpha_settle") or not press("alpha_next_day") or not press("alpha_prepare_day"):
			quit(1)
			return
	if not press("alpha_open") or not enter() or not exit_customer() or not enter():
		quit(1)
		return
	check(host.session.alpha_view().active.actor_id=="G01","source tool must be offered by actual G01")
	var field := host.find_child("b2_price_input",true,false) as LineEdit
	if not check(field != null,"same price field on ordinary tool procurement"):
		quit(1)
		return
	field.text="60"
	if not press("b2_offer") or not press("b2_trade") or not press("alpha_ack_exit"):
		quit(1)
		return
	check(host.session.snapshot().items.TL04.owner_id=="player","visible trade acquired actual tool")
	check(press("b2_commission_reserve_TL04"),"counter-independent single-item inventory assignment")
	check(host.session.snapshot().items.TL04.reservation_id=="tool_for_g03","reservation locks physical stock")
	if not enter() or not exit_customer() or not enter():
		quit(1)
		return
	check(host.session.alpha_view().active.actor_id=="G03","authored pickup is same G03, not new NPC")
	check(press("b2_commission_deliver"),"pickup at same counter, no separate quest panel")
	check(host.session.snapshot().wallets.player.VKC==210 and host.session.snapshot().ledger.size()==2,"cash and ledger reflect real 60 purchase then 90 sale")
	check(host.session.snapshot().alpha_shop.commissions.entries.tool_for_g03.status=="fulfilled","one UI fulfillment only")
	var same_state: Dictionary=host.session.snapshot()
	var old_location: String=host._repo._root
	var old_slot: String=host._slot()
	host.queue_free()
	await process_frame
	var loaded: Control=Scene.instantiate()
	loaded.save_directory_override=old_location
	root.add_child(loaded)
	await process_frame
	check(not loaded._blocked and loaded.session != null and loaded.session.snapshot()==same_state and loaded._slot()==old_slot, "UI session cold resumes same fulfilled commission without duplication")
	loaded.queue_free()
	await process_frame
	print("ALPHA_B2_COMMISSION_HOST_CHECKS=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
