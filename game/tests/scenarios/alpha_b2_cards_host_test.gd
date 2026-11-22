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
	check(host.find_child("b2_jump_b2_private_sheet",true,false)!=null and host.find_child("b2_jump_b2_price_sheet",true,false)!=null,"same counter exposes direct card/price navigation without moving money")
	var normal_art := host.find_child("b2_item_art",true,false) as TextureRect
	check(normal_art != null and normal_art.custom_minimum_size.y == 144.0,"native source image starts at readable nonzoom size")
	var scroller := host.find_child("alpha_card_scroll",true,false) as ScrollContainer
	var price_draft := host.find_child("b2_price_input",true,false) as LineEdit
	if scroller != null:
		scroller.scroll_vertical = 80
	if price_draft != null:
		price_draft.text = "93"
	await process_frame
	var retained_y: int = scroller.scroll_vertical if scroller != null else 0
	# The fixed host probe uses Godot headless: it has no mapped window, so a
	# nonzero real scroll offset is tested in the separate Xvfb window suite.
	check(scroller != null,"B2 headless host retains scroll container before a refresh")
	check(press("b2_zoom_toggle"),"source art zoom available without new appraisal command")
	await process_frame
	await process_frame
	var after_zoom := host.find_child("alpha_card_scroll",true,false) as ScrollContainer
	var after_draft := host.find_child("b2_price_input",true,false) as LineEdit
	check(after_zoom != null and abs(after_zoom.scroll_vertical-retained_y) <= 2 and after_draft != null and after_draft.text == "93","zoom refresh retains visit scroll and unsubmitted quote")
	var zoomed_art := host.find_child("b2_item_art",true,false) as TextureRect
	check(zoomed_art != null and zoomed_art.custom_minimum_size.y == 260.0,"actual same image rendered larger, not a fake inspection result")
	check(press("b2_zoom_toggle"),"unzoom restores original layout")
	check(host.session.alpha_view().appraisal.cards.is_empty(),"pure UI zoom leaves private evidence untouched")
	check(press("b2_inspect_wear_detail"),"inspect existing sample from UI")
	var after_inspection := host.find_child("b2_price_input",true,false) as LineEdit
	check(after_inspection != null and after_inspection.text == "93","inspection cannot clear an unsubmitted quote")
	var evidence_card := host.find_child("b2_card_wear_detail",true,false) as Button
	check(evidence_card!=null and evidence_card.text.contains("상점 측 협상 근거"),"verified wear meaning for purchase is explicitly labelled")
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
	# Independent original G01 alternative path; a public argument remains
	# known after the player unticks its card for the next rejected proposal.
	host = Scene.instantiate()
	host.save_directory_override = "user://zt_rebuild/b2_cards_memory_host_" + str(Time.get_ticks_usec())
	root.add_child(host)
	await process_frame
	check(host.session != null and not host._blocked,"new evidence memory counter boots with original source")
	check(press("intro_skip") and press("alpha_open") and press("alpha_next_customer") and press("alpha_ack_entry"),"G01 revisits isolated click path")
	var claim := host.find_child("b2_customer_claim",true,false) as Label
	var no_promise := host.find_child("b2_no_quality_promise",true,false) as Label
	check(claim!=null and claim.text.contains("고객 주장") and no_promise!=null and no_promise.text.contains("확약"),"customer self-report and absence of quality guarantee visible without new page")
	check(press("b2_guess_function_detail_inoperable"),"incorrect provisional function guess is an optional private counter action")
	check(host.session.alpha_view().appraisal.hypotheses[0].judgment=="inoperable" and host.session.alpha_view().npc_context.current_offer.is_empty(),"customer never hears guessed function state")
	check(press("b2_inspect_identity") and press("b2_inspect_wear_detail") and press("b2_card_wear_detail"),"one private observation and one disclosed wear choice")
	var first_quote := host.find_child("b2_price_input",true,false) as LineEdit
	if first_quote != null:
		first_quote.text = "94"
	check(press("b2_offer"),"first public evidence-bearing offer declined")
	check(press("b2_card_wear_detail"),"exclude old public evidence from NEXT offer only")
	var known_label := host.find_child("b2_card_wear_detail",true,false) as Button
	var still_private := host.find_child("b2_card_identity",true,false) as Button
	check(known_label != null and known_label.text.contains("공개 이력") and still_private != null and not still_private.text.contains("공개 이력"),"drawer distinguishes previously public and still-private facts")
	var second_quote := host.find_child("b2_price_input",true,false) as LineEdit
	if second_quote != null:
		second_quote.text = "95"
	check(press("b2_offer"),"second quote sends zero new disclosure")
	var speaker := host.find_child("alpha_speech",true,false) as Label
	check(speaker != null and speaker.text.contains("기억합니다") and speaker.text.contains("외관 마모"),"customer's natural rebuttal remembers actually disclosed wear")
	check(press("b2_statement_retract_wear_detail"),"player corrects public evidence on same card drawer")
	var after_withdraw: Dictionary = host.session.alpha_view().npc_context.current_offer
	var withdrawal_line := host.find_child("alpha_speech",true,false) as Label
	check(after_withdraw.known_slots==["wear_detail"] and after_withdraw.withdrawn_slots==["wear_detail"] and withdrawal_line!=null and withdrawal_line.text.contains("철회"),"customer remembers statement and recognizes retraction without secret inference")
	check(press("b2_statement_reaffirm_wear_detail"),"previous public fact explicitly reaffirmed on same drawer")
	check(host.session.alpha_view().npc_context.current_offer.active_slots==["wear_detail"] and host.session.snapshot().alpha_shop.appraisal.visits.visit_g01.statements.size()==2,"correction history is source-backed and no offer re-submitted")
	check(host.session.snapshot().wallets.player.VKC == 180 and host.session.snapshot().ledger.is_empty(),"rebuttal creates no fictional money or trade")
	host.queue_free()
	await process_frame
	print("ALPHA_B2_CARDS_HOST_CHECKS=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
