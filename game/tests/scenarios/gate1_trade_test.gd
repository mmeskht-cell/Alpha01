extends SceneTree
const Runtime = preload("res://src/application/foundation_runtime.gd")
const Appraisal = preload("res://src/domain/gate1_appraisal.gd")
const Negotiation = preload("res://src/domain/gate1_negotiation.gd")
var checks: int = 0
var failures: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func cmd(rt: RefCounted, id: String, kind: String, payload: Dictionary = {}) -> Dictionary:
	return {"action_id": id, "expected_revision": rt.counter_view().revision, "type": kind, "payload": payload}

func send(rt: RefCounted, id: String, kind: String, payload: Dictionary = {}) -> Dictionary:
	return rt.submit(cmd(rt, id, kind, payload))

func open_case(root: String, suffix: String) -> RefCounted:
	var rt := Runtime.new()
	if not rt.initialize_gate1_opening("gate1_1_v3", root.path_join(suffix)):
		return null
	if not send(rt, "admit", "next_visit").ok:
		rt.shutdown()
		return null
	return rt

func placement(offer_id: String, x: int = 0) -> Dictionary:
	return {"offer_id": offer_id, "inventory": "player_stock", "x": x, "y": 0, "rotated": false}

func _initialize() -> void:
	var root: String = "user://zt_rebuild/gate1_trade_" + str(Time.get_ticks_usec())
	var rt := open_case(root, "normal")
	check(rt != null, "normal setup")
	if rt == null:
		quit(1)
		return
	check(send(rt, "reserve", "accept_rad1_contract").ok, "protected reservation independent")
	var before: Dictionary = rt.snapshot()
	check(not send(rt, "no_offer", "confirm_purchase", placement("fake")).ok and rt.snapshot() == before, "purchase needs accepted offer")
	check(not send(rt, "fake_evidence", "make_offer", {"amount": 100, "evidence_id": "R001.wear"}).ok and rt.snapshot() == before, "unobserved evidence rejected")
	check(send(rt, "guess", "record_hypothesis", {"item_id": "R001", "model_id": "selvar_r18", "appearance_id": "visible_wear"}).ok, "reference chosen")
	check(send(rt, "unsupported", "make_offer", {"amount": 100, "evidence_id": null}).ok and not rt.counter_view().negotiation.can_confirm, "hypothesis alone cannot discount")
	check(send(rt, "wear", "inspect_radio", {"item_id": "R001", "tool_id": "wear_detail", "target": "visible_wear_detail"}).ok, "wear evidence")
	check(send(rt, "casing", "inspect_radio", {"item_id": "R001", "tool_id": "casing_detail", "target": "additional_casing_evidence"}).ok, "casing evidence")
	var offer: Dictionary = cmd(rt, "offer", "make_offer", {"amount": 100, "evidence_id": "R001.wear"})
	check(rt.submit(offer).ok and rt.counter_view().negotiation.can_confirm, "100 accepted with wear")
	before = rt.snapshot()
	check(before.game_minutes == 15 and before.wallets.player.VKC == 180 and before.items.R001.owner_id == "G01" and before.ledger.is_empty(), "acceptance is not settlement")
	check(rt.submit(offer).ok and rt.snapshot() == before, "offer replay")
	check(not send(rt, "offer_again", "make_offer", offer.payload).ok and rt.snapshot() == before, "same terms do not create benefit")
	check(not send(rt, "old", "confirm_purchase", placement("unsupported")).ok and rt.snapshot() == before, "old offer cannot settle")
	check(not send(rt, "bad_placement", "confirm_purchase", placement("offer", 9)).ok and rt.snapshot() == before, "out-of-grid atomic rejection")
	check(not rt.submit({"action_id": "stale", "type": "confirm_purchase", "expected_revision": before.revision - 1, "payload": placement("offer")}).ok and rt.snapshot() == before, "stale confirmation rejected")
	check(not send(rt, "injection", "trade", {}).ok and rt.snapshot() == before, "generic trade not available")
	var accepted_state: Dictionary = before.duplicate(true)
	var purchase: Dictionary = cmd(rt, "buy", "confirm_purchase", placement("offer"))
	var result: Dictionary = rt.submit(purchase)
	check(result.ok and result.get("persisted", false), "purchase commits and saves")
	var bought: Dictionary = rt.snapshot()
	check(bought.game_minutes == 15 and bought.wallets.player == {"VKC": 80, "USD": 0} and bought.wallets.G01.VKC == 100, "t15 and cash")
	check(bought.items.R001.owner_id == "player" and bought.items.R001.custodian_id == "player" and bought.items.R001.basis == {"VKC": 100, "USD": 0}, "ID, ownership and basis")
	check(bought.ledger.size() == 1 and bought.visits.visit_g01.scope.completed, "ledger and completed scope")
	check(rt.counter_view().customer == null and rt.counter_view().negotiation.outcome == "purchased" and not rt.counter_view().can_call_next, "visit depleted")
	var slip: Dictionary = rt.counter_view().acquired_appraisal
	check(slip.item_id == "R001" and slip.tools.is_empty() and slip.evidence.size() == 2 and slip.reference.estimate == 160 and slip.function_status == "unknown", "acquired read-only appraisal preserves known facts and hypotheses")
	check(rt.submit(purchase).ok and rt.snapshot() == bought, "purchase replay")
	check(not send(rt, "next", "next_visit").ok and rt.snapshot() == bought, "G02 remains deferred")
	rt.shutdown()
	rt = Runtime.new()
	var ready: bool = rt.initialize_gate1_opening("gate1_1_v3", root.path_join("normal"))
	check(ready, "restore setup")
	if ready:
		check(rt.load_saved().ok and rt.snapshot() == bought, "purchase restore")
		check(rt.submit(purchase).ok and rt.snapshot() == bought, "replay after restore")
		rt.shutdown()
	# Corrupt only this test's latest generation. Recovery must retain the accepted previous state.
	var latest_path: String = ""
	for filename: String in ["gate1_1_v3.a.json", "gate1_1_v3.b.json"]:
		var candidate: String = root.path_join("normal").path_join(filename)
		var envelope: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate))
		if envelope is Dictionary and envelope.get("revision") == bought.revision:
			latest_path = candidate
	check(not latest_path.is_empty(), "locate test generation")
	if not latest_path.is_empty():
		var damage := FileAccess.open(latest_path, FileAccess.WRITE)
		if damage != null:
			damage.store_string("{")
			damage.close()
		rt = Runtime.new()
		ready = rt.initialize_gate1_opening("gate1_1_v3", root.path_join("normal"))
		check(ready, "damage recovery setup")
		if ready:
			var recovered: Dictionary = rt.load_saved()
			check(recovered.ok and recovered.get("recovered", false) and rt.snapshot() == accepted_state, "fallback to earlier accepted offer")
			check(rt.submit(purchase).ok and rt.snapshot() == bought, "reconfirm once after fallback")
			rt.shutdown()
	rt = open_case(root, "decline")
	check(rt != null, "decline setup")
	if rt != null:
		check(send(rt, "wear", "inspect_radio", {"item_id": "R001", "tool_id": "wear_detail", "target": "visible_wear_detail"}).ok, "decline after paid inspection")
		check(send(rt, "decline", "decline_visit").ok, "declined")
		before = rt.snapshot()
		check(before.game_minutes == 5 and before.wallets.player.VKC == 180 and before.items.R001.owner_id == "G01" and before.ledger.is_empty(), "decline preserves legitimate time and funds")
		check(rt.counter_view().negotiation.outcome == "declined" and not send(rt, "again", "next_visit").ok and rt.snapshot() == before, "declined visit cannot regenerate")
		check(rt.counter_view().acquired_appraisal.is_empty(), "no acquired appraisal on decline")
		rt.shutdown()
	rt = open_case(root, "funds")
	check(rt != null, "funds setup")
	if rt != null:
		check(send(rt, "high", "make_offer", {"amount": 181, "evidence_id": null}).ok, "accepted over-budget offer")
		before = rt.snapshot()
		check(not send(rt, "poor", "confirm_purchase", placement("high")).ok and rt.snapshot() == before, "insufficient funds atomic")
		check(send(rt, "normal", "make_offer", {"amount": 125, "evidence_id": null}).ok, "unappraised asking price")
		check(send(rt, "buy", "confirm_purchase", placement("normal")).ok and rt.snapshot().game_minutes == 0 and rt.snapshot().wallets.player.VKC == 55, "unappraised purchase allowed")
		rt.shutdown()
	rt = open_case(root, "limit")
	check(rt != null, "offer limit setup")
	if rt != null:
		for index: int in range(3):
			check(send(rt, "low_" + str(index), "make_offer", {"amount": 50 + index, "evidence_id": null}).ok, "material offer")
		before = rt.snapshot()
		check(not send(rt, "fourth", "make_offer", {"amount": 100, "evidence_id": null}).ok and rt.snapshot() == before, "bounded material offers")
		check(send(rt, "decline", "decline_visit").ok, "decline remains available")
		rt.shutdown()
	rt = open_case(root, "boundary")
	check(rt != null, "boundary setup")
	if rt != null:
		# Detached rule fixture, not a valid persisted campaign state or an end-to-end clock test.
		var boundary: Dictionary = rt.snapshot()
		boundary["game_minutes"] = 591
		var unchanged: Dictionary = boundary.duplicate(true)
		var casing: Dictionary = {"item_id": "R001", "tool_id": "casing_detail", "target": "additional_casing_evidence"}
		check(Appraisal.apply(boundary, "inspect_radio", casing, "too_long") == "inspection_time_short" and boundary == unchanged, "oversize preflight unchanged")
		boundary["game_minutes"] = 590
		check(Appraisal.apply(boundary, "inspect_radio", casing, "exact") == "" and boundary.game_minutes == 600, "exact closing preflight")
		unchanged = boundary.duplicate(true)
		check(Appraisal.apply(boundary, "inspect_radio", {"item_id": "R001", "tool_id": "wear_detail", "target": "visible_wear_detail"}, "late") == "business_closed" and boundary == unchanged, "no new inspection at closing")
		check(Negotiation.offer(boundary, {"amount": 125, "evidence_id": null}, "last_offer") == "" and boundary.game_minutes == 600, "final offer free at closing")
		check(Negotiation.prepare_purchase(boundary, placement("last_offer")) == "" and boundary.game_minutes == 600, "final purchase preflight at closing")
		rt.shutdown()
	for suffix: String in ["normal", "decline", "funds", "limit", "boundary"]:
		var directory: String = root.path_join(suffix)
		for name: String in ["gate1_1_v3.a.json", "gate1_1_v3.b.json"]:
			var file: String = directory.path_join(name)
			if FileAccess.file_exists(file):
				DirAccess.remove_absolute(file)
		DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute(root)
	print("GATE1_TRADE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
