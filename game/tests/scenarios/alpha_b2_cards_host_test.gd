extends SceneTree
## The same visual host supports inspecting, selecting and proposing
## before the original one-time GameSession trade. No new dialogue screen.
const Scene = preload("res://scenes/app/alpha_b2_cards.tscn")
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
	if not check(button != null and button.is_visible_in_tree() and not button.disabled,"visible card control "+id):
		return false
	button.pressed.emit()
	return true

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	host = Scene.instantiate()
	host.save_directory_override = "user://zt_rebuild/b2_cards_host_"+str(Time.get_ticks_usec())
	root.add_child(host)
	await process_frame
	if not check(host.session != null and not host._blocked and host.b2_interactive_mode,"isolated interactive scene boots"):
		quit(1)
		return
	check(press("intro_skip") and press("alpha_open") and press("alpha_next_customer") and press("alpha_ack_entry"),"first one-counter visit")
	check(host.find_child("b2_current_item",true,false) != null,"visible real item without extra screen")
	check(press("b2_inspect_wear_detail"),"inspect existing sample from UI")
	check(press("b2_card_wear_detail"),"choose one optional public fact")
	var amount := host.find_child("b2_price_input",true,false) as LineEdit
	check(amount != null,"single offer amount field")
	if amount != null:
		amount.text = "95"
	check(press("b2_offer"),"send price and selected cards in one interaction")
	check(host.session.alpha_view().appraisal.accepted.get("amount",0) == 95,"customer agrees to evidence-bearing demo offer")
	check(press("b2_trade") and press("alpha_ack_exit") and press("b2_display_R001"),"real purchase then shelf display")
	check(press("alpha_next_customer") and press("alpha_ack_entry"),"same counter buyer")
	check(press("b2_inspect_function_detail") and press("b2_card_function_detail"),"buyer can see separate factual card")
	amount = host.find_child("b2_price_input",true,false) as LineEdit
	if amount != null:
		amount.text = "175"
	check(press("b2_offer") and press("b2_trade"),"buyer accepts proposed price then pays")
	check(host.session.snapshot().wallets.player.VKC == 260 and host.session.snapshot().ledger.size() == 2,"real two-way settlement from UI")
	host.queue_free()
	await process_frame
	print("ALPHA_B2_CARDS_HOST_CHECKS=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
