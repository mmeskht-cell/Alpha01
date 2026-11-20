extends SceneTree
const Runtime = preload("res://src/application/foundation_runtime.gd")
const Slot = preload("res://src/presentation/appraisal_card_slot.gd")
var checks: int = 0
var failures: int = 0
var drops: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func command(rt: RefCounted, kind: String, id: String, p: Dictionary = {}) -> Dictionary:
	return {"action_id":id,"expected_revision":rt.snapshot().revision,"type":kind,"payload":p}

func place(rt: RefCounted, field: String, value: Variant, id: String) -> Dictionary:
	var h: Dictionary = rt.counter_view().appraisal.hypothesis
	h[field] = value
	h.item_id = "R001"
	h.card_slot = field
	return command(rt,"record_hypothesis",id,h)

func _initialize() -> void:
	var path: String = "user://zt_rebuild/p1_cards_" + str(Time.get_ticks_usec())
	var rt := Runtime.new()
	var ready: bool = rt.initialize_gate1_opening("gate1_1_v3",path)
	check(ready,"opening")
	if not ready:
		quit(1)
		return
	check(rt.submit(command(rt,"accept_rad1_contract","reserve")).ok and rt.submit(command(rt,"next_visit","admit")).ok,"visit")
	check(rt.counter_view().appraisal.card_dialogue.is_empty(),"no dialogue before placement")
	var c: Dictionary = place(rt,"model_id","selvar_r18s","guess")
	check(rt.submit(c).ok,"alternative candidate allowed")
	var view: Dictionary = rt.counter_view().appraisal
	check(view.card_dialogue.slot == "model_id" and view.card_dialogue.action_id == "guess" and view.evidence.is_empty(),"committed conjecture conversation")
	var state: Dictionary = rt.snapshot()
	check(rt.submit(c).ok and rt.snapshot() == state,"same receipt no repeat")
	check(not rt.submit(place(rt,"model_id","selvar_r18s","same")).ok and rt.snapshot() == state,"unchanged no new event")
	var bad: Dictionary = place(rt,"appearance_id","visible_wear","multi")
	bad.payload.model_id = "selvar_r18"
	check(not rt.submit(bad).ok and rt.snapshot() == state,"one slot per placement")
	check(rt.submit(place(rt,"appearance_id","visible_wear","wear")).ok and rt.counter_view().appraisal.reference.estimate == 192,"manual aggregate")
	check(rt.counter_view().appraisal.card_dialogue.slot == "appearance_id","per-slot dialogue")
	check(rt.submit(place(rt,"model_id","selvar_r18","normal")).ok and rt.counter_view().appraisal.reference.estimate == 160,"revise no truth check")
	check(rt.submit(place(rt,"model_id",null,"clear")).ok and rt.counter_view().appraisal.card_dialogue.speaker_key == "appraisal.card_clear","clear dialogue")
	check(rt.snapshot().game_minutes == 0 and rt.snapshot().wallets == state.wallets and rt.snapshot().items == state.items and rt.snapshot().ledger.is_empty(),"free, no economy mutation")
	# Reverse the conventional order; all fields can be placed before model.
	check(rt.submit(place(rt,"batch_id","series_early","batch_first")).ok,"batch before model")
	check(rt.submit(place(rt,"material_id","light_alloy","material_second")).ok,"material before model")
	check(rt.submit(place(rt,"model_id","selvar_r18","model_last")).ok and rt.counter_view().appraisal.reference.estimate == 172,"independent aggregate")
	check(rt.submit(command(rt,"inspect_radio","observe_wear",{"item_id":"R001","tool_id":"wear_detail","target":"visible_wear_detail"})).ok,"actual evidence")
	var association: Dictionary = rt.counter_view().appraisal.hypothesis
	association.item_id = "R001"
	association.link_slot = "appearance_id"
	association.card_links = {"appearance_id":["R001.wear"]}
	var linked: Dictionary = command(rt,"record_hypothesis","link",association)
	var before_link: Dictionary = rt.snapshot()
	check(rt.submit(linked).ok and rt.counter_view().appraisal.card_links == association.card_links and rt.counter_view().appraisal.card_dialogue.is_empty(),"link is not a new card response")
	var after_link: Dictionary = rt.snapshot()
	check(after_link.game_minutes == before_link.game_minutes and rt.submit(linked).ok and rt.snapshot() == after_link,"link free and idempotent")
	var invented: Dictionary = association.duplicate(true)
	invented.card_links.appearance_id.append("fake")
	check(not rt.submit(command(rt,"record_hypothesis","fake_link",invented)).ok and rt.snapshot() == after_link,"no fabricated evidence")
	var changed: Dictionary = rt.counter_view().appraisal.hypothesis
	changed.item_id = "R001"
	changed.card_slot = "model_id"
	changed.model_id = "selvar_r18s"
	changed.card_links = association.card_links.duplicate(true)
	check(rt.submit(command(rt,"record_hypothesis","linked_revision",changed)).ok and rt.counter_view().appraisal.card_links == association.card_links,"other slot revision preserves links")
	check(rt.submit(command(rt,"make_offer","offer",{"amount":100,"evidence_id":"R001.wear"})).ok and rt.counter_view().appraisal.card_dialogue.is_empty(),"newer offer takes precedence")
	changed = rt.counter_view().appraisal.hypothesis
	changed.item_id = "R001"
	changed.card_slot = "model_id"
	changed.model_id = "selvar_r18"
	changed.card_links = association.card_links.duplicate(true)
	check(rt.submit(command(rt,"record_hypothesis","after_offer",changed)).ok and rt.counter_view().appraisal.card_dialogue.action_id == "after_offer","later assessment conversation takes precedence")
	var candidates: Array = rt.counter_view().appraisal.argument_candidates
	var argument: Dictionary = {}
	for candidate: Dictionary in candidates:
		if candidate.argument.slot == "appearance_id":
			argument = candidate.argument
	check(not argument.is_empty(),"public prepared appearance card")
	var forged: Dictionary = argument.duplicate(true)
	forged.source_payload.appearance_id = "heavy_wear"
	var before_offer: Dictionary = rt.snapshot()
	check(not rt.submit(command(rt,"make_offer","forged_argument",{"amount":101,"argument":forged})).ok and rt.snapshot() == before_offer,"forged source refused")
	check(not rt.submit(command(rt,"make_offer","repeat_argument",{"amount":100,"argument":argument})).ok and rt.snapshot() == before_offer,"same price and evidence duplicate across presentation routes")
	var offer: Dictionary = command(rt,"make_offer","argument_offer",{"amount":101,"argument":argument})
	check(rt.submit(offer).ok and rt.counter_view().negotiation.offers.back().accepted and rt.counter_view().negotiation.offers.back().argument == argument,"prepared card uses known wear evidence")
	var frozen: Dictionary = rt.snapshot()
	check(rt.submit(offer).ok and rt.snapshot() == frozen,"offer receipt idempotent")
	changed = rt.counter_view().appraisal.hypothesis
	changed.item_id = "R001"
	changed.card_slot = "appearance_id"
	changed.appearance_id = "heavy_wear"
	changed.card_links = association.card_links.duplicate(true)
	check(rt.submit(command(rt,"record_hypothesis","revise_after_argument",changed)).ok and rt.counter_view().negotiation.offers.back().argument == argument,"historical proposal pinned despite later revision")
	var before_stale: Dictionary = rt.snapshot()
	check(not rt.submit(command(rt,"make_offer","stale_argument",{"amount":102,"argument":argument})).ok and rt.snapshot() == before_stale,"stale argument refused")
	var deck_arg: Dictionary = {}
	for candidate: Dictionary in rt.counter_view().appraisal.argument_candidates:
		if candidate.argument.slot == "model_id":
			deck_arg = candidate.argument
	var prepare: Dictionary = command(rt,"deck_action","prep_model",{"op":"prepare","slot":"model_id","argument":deck_arg})
	var before_deck: Dictionary = rt.snapshot()
	check(rt.submit(prepare).ok and rt.counter_view().negotiation_deck.ready.size() == 1,"prepare persistent card")
	var prepared: Dictionary = rt.snapshot()
	check(rt.submit(prepare).ok and rt.snapshot() == prepared,"prepare idempotent")
	# Unrelated changes preserve prepared model semantics; present with new receipt proof.
	changed = rt.counter_view().appraisal.hypothesis
	changed.item_id = "R001"
	changed.card_slot = "batch_id"
	changed.batch_id = "series_late"
	changed.card_links = association.card_links.duplicate(true)
	check(rt.submit(command(rt,"record_hypothesis","unrelated_batch",changed)).ok and rt.counter_view().negotiation_deck.ready[0].current,"unrelated slot preserves prepared card")
	var current_model: Dictionary = {}
	for candidate: Dictionary in rt.counter_view().appraisal.argument_candidates:
		if candidate.argument.slot == "model_id":
			current_model = candidate.argument
	var before_proof: Dictionary = rt.snapshot()
	check(not rt.submit(command(rt,"deck_action","missing_proof",{"op":"present","slot":"model_id","argument":deck_arg})).ok and rt.snapshot() == before_proof,"new presentation requires current source proof")
	var present: Dictionary = command(rt,"deck_action","speak_model",{"op":"present","slot":"model_id","argument":deck_arg,"current_argument":current_model})
	check(rt.submit(present).ok and rt.counter_view().negotiation_deck.ready.is_empty() and rt.counter_view().negotiation_deck.presented.size() == 1,"sequential presentation")
	check(rt.snapshot().game_minutes == before_deck.game_minutes and rt.counter_view().negotiation.remaining_offers == 1,"presentation costs no time or offer")
	check(not rt.submit(command(rt,"deck_action","repeat_model",prepare.payload)).ok,"no repeated semantic presentation")
	changed = rt.counter_view().appraisal.hypothesis
	changed.item_id = "R001"
	changed.card_slot = "appearance_id"
	changed.appearance_id = "visible_wear"
	changed.card_links = association.card_links.duplicate(true)
	check(rt.submit(command(rt,"record_hypothesis","reinspect_claim",changed)).ok,"continue appraisal after presentation")
	var wear_arg: Dictionary = {}
	for candidate: Dictionary in rt.counter_view().appraisal.argument_candidates:
		if candidate.argument.slot == "appearance_id":
			wear_arg = candidate.argument
	check(rt.submit(command(rt,"deck_action","prep_wear",{"op":"prepare","slot":"appearance_id","argument":wear_arg})).ok,"prepare second card")
	check(rt.submit(command(rt,"deck_action","speak_wear",{"op":"present","slot":"appearance_id","argument":wear_arg})).ok,"present second card")
	check(rt.counter_view().negotiation_deck.latest_reply.claim_key == "appraisal.deck_customer_claim" and rt.counter_view().negotiation_deck.latest_reply.claim_status == "unconfirmed","customer statement is unverified claim, no new observation")
	check(rt.submit(command(rt,"make_offer","deck_offer",{"amount":102,"presented_ids":["speak_model","speak_wear"]})).ok and rt.counter_view().negotiation.offers.back().accepted,"presented cards support one manual offer")
	# New hypothesis ensures the existing localized latest dialogue assertion remains applicable.
	changed = rt.counter_view().appraisal.hypothesis
	changed.item_id = "R001"
	changed.card_slot = "batch_id"
	changed.batch_id = "series_early"
	changed.card_links = association.card_links.duplicate(true)
	check(rt.submit(command(rt,"record_hypothesis","after_deck_offer",changed)).ok,"continue after accepted offer")
	var slot := Slot.new()
	slot.field = "model_id"
	slot.revision = int(rt.snapshot().revision)
	slot.card_placed.connect(func(f: String,v: Variant,rev: int) -> void: drops.append([f,v,rev]))
	var data: Dictionary = {"kind":"appraisal_hypothesis","attribute_id":"model_id","attribute_value":"selvar_r18","revision":slot.revision}
	check(slot._can_drop_data(Vector2.ZERO,data),"matching destination")
	var wrong: Dictionary = data.duplicate(true)
	wrong.attribute_id = "batch_id"
	check(not slot._can_drop_data(Vector2.ZERO,wrong),"wrong slot")
	wrong = data.duplicate(true)
	wrong.revision -= 1
	check(not slot._can_drop_data(Vector2.ZERO,wrong),"stale drag")
	slot._drop_data(Vector2.ZERO,wrong)
	check(drops.is_empty(),"bad drop no event")
	slot._drop_data(Vector2.ZERO,data)
	check(drops.size() == 1 and drops[0][0] == "model_id","valid drop emits once")
	slot.disabled = true
	check(not slot._can_drop_data(Vector2.ZERO,data),"locked destination")
	slot.free()
	var last: Dictionary = rt.counter_view().appraisal.card_dialogue
	for locale: String in ["ko","en"]:
		check(rt.localization.select_language(locale) and not rt.localization.text(last.speaker_key,{"value":rt.localization.text(last.label_key)}).is_empty() and not rt.localization.text(last.response_key).is_empty(),"localized "+locale)
	var saved: Dictionary = rt.snapshot()
	rt.shutdown()
	var loaded := Runtime.new()
	check(loaded.initialize_gate1_opening("gate1_1_v3",path) and loaded.load_saved().ok and loaded.snapshot() == saved and loaded.counter_view().appraisal.card_dialogue == last,"persisted latest dialogue")
	loaded.shutdown()
	print("GATE2_P1_CARD_CHECKS=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
