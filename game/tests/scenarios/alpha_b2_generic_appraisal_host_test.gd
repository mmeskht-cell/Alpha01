extends SceneTree
## B2 T03: bounded shared Korean counter UI for original watch and battery,
## stock on D2. UI invokes the same source-bound
## alpha_inspect / alpha_card_toggle / alpha_price_offer domain commands.
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
	if not check(button != null and button.is_visible_in_tree() and not button.disabled,"visible single-counter action "+id):
		return false
	button.pressed.emit()
	return true

func _initialize() -> void:
	run.call_deferred()

func sample(visit_id: String, item_id: String, expected_item_label: String, slot: String) -> void:
	var view: Dictionary = host.session.alpha_view()
	check(view.active.id == visit_id and view.appraisal.item_id == item_id,"correct original visiting customer "+visit_id)
	var item_heading := host.find_child("b2_current_item",true,false) as Label
	var art := host.find_child("b2_item_art",true,false) as TextureRect
	check(item_heading != null and item_heading.text.contains(expected_item_label),"same visible customer-facing item name "+visit_id)
	check(art != null and art.texture != null,"same original art surface for "+visit_id)
	check(press("b2_inspect_" + slot),"same inspection button found for "+item_id)
	var card := host.find_child("b2_card_" + slot,true,false) as Button
	check(card != null and card.text.contains("사용 가능") and not card.text.contains("공개 이력"),"actual condition rendered in Korean but initially private "+item_id)
	check(press("b2_card_" + slot),"optional card selected in shared drawer "+item_id)
	var proposed := host.find_child("b2_price_input",true,false) as LineEdit
	check(proposed != null,"single amount input still available "+item_id)
	if proposed != null:
		proposed.text = "1"
	check(press("b2_offer"),"ordinary price submitted without a per-product page "+item_id)
	var public: Dictionary = host.session.alpha_view().npc_context.current_offer
	check(public.public_slots == [slot] and public.response == "declined","only chosen source-grounded fact reached counterparty "+item_id)
	var old: Dictionary = host.session.snapshot()
	check(old.ledger.is_empty() and old.wallets.player.VKC == 180,"ordinary card offer cannot mint money "+item_id)

func run() -> void:
	host = Scene.instantiate()
	host.save_directory_override = "user://zt_rebuild/b2_generic_inspection_host_"+str(Time.get_ticks_usec())
	root.add_child(host)
	await process_frame
	if not check(host.session != null and not host._blocked,"data-driven two-category counter boots"):
		quit(1)
		return
	var cases: Dictionary = {
		"watch_a":{"item":"WAT02","name":"손목시계","slot":"function_detail"},
		"battery_buy":{"item":"BAT02","name":"건전지","slot":"condition_detail"}
	}
	check(press("intro_skip"),"intro leaves initial seed intact")
	for day: int in range(1,3):
		if not press("alpha_open"):
			quit(1)
			return
		var rows: Array = host.session.snapshot().alpha_shop.profile.days[day-1]
		for row: Dictionary in rows:
			if not press("alpha_next_customer") or not press("alpha_ack_entry"):
				quit(1)
				return
			if cases.has(str(row.id)):
				var sample_row: Dictionary = cases[str(row.id)]
				sample(str(row.id),str(sample_row.item),str(sample_row.name),str(sample_row.slot))
			if not press("alpha_finish_customer") or not press("alpha_ack_exit"):
				quit(1)
				return
		if not press("alpha_close") or not press("alpha_settle"):
			quit(1)
			return
		if day < 2:
			if not press("alpha_next_day") or not press("alpha_prepare_day"):
				quit(1)
				return
	check(host.session.snapshot().ledger.is_empty() and host.session.snapshot().wallets.player.VKC == 180,"two-day UI traversal never sells a virtual item")
	host.queue_free()
	await process_frame
	print("ALPHA_B2_GENERIC_APPRAISAL_HOST_CHECKS=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
