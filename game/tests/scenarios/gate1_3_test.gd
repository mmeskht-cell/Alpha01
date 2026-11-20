extends SceneTree
const Runtime = preload("res://src/application/foundation_runtime.gd")
const DayOne = preload("res://src/domain/day_one.gd")
const Registry = preload("res://src/domain/dormant_registry.gd")
const Tracking = preload("res://src/domain/selective_tracking.gd")
const Accounting = preload("res://src/domain/campaign_accounting_audit.gd")
const Codec = preload("res://src/persistence/registry_pilot_format.gd")
const Probe = preload("res://tests/fixtures/checkpoint_campaign_probe.gd")
const Format = preload("res://src/domain/snapshot_format.gd")
const History = preload("res://src/domain/item_lineage.gd")
var rt: RefCounted
var serial: int = 0
var checks: int = 0
var failures: int = 0
var directory: String = ""

func check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", name)

func command(kind: String, p: Dictionary = {}) -> Dictionary:
	serial += 1
	return {"action_id": "day1_service_" + str(serial), "expected_revision": rt.counter_view().revision, "type": kind, "payload": p}

func send(kind: String, p: Dictionary = {}) -> Dictionary:
	return rt.submit(command(kind, p))

func reject(kind: String, p: Dictionary = {}) -> bool:
	var before: Dictionary = rt.snapshot()
	return not send(kind, p).ok and rt.snapshot() == before

func sale(visit: String, buyer: String, amount: int, grid: String) -> Dictionary:
	return {"visit_id": visit, "item_id": "R001", "seller": "player", "buyer": buyer, "currency": "VKC", "amount": amount, "inventory": grid, "x": 0, "y": 0, "rotated": false}

func fresh(price: int, route: String) -> bool:
	directory = "user://zt_rebuild/day_one/test_" + str(Time.get_ticks_usec()) + "_" + str(serial)
	rt = Runtime.new()
	if not rt.initialize_day_one(directory) or not send("accept_rad1_contract").ok or not send("next_visit").ok:
		return false
	if not send("inspect_radio", {"item_id": "R001", "tool_id": "wear_detail", "target": "visible_wear_detail"}).ok or not send("inspect_radio", {"item_id": "R001", "tool_id": "casing_detail", "target": "additional_casing_evidence"}).ok:
		return false
	var offer: Dictionary = command("make_offer", {"amount": price, "evidence_id": "R001.wear"})
	if not rt.submit(offer).ok or not send("confirm_purchase", {"offer_id": offer.action_id, "inventory": "player_stock", "x": 0, "y": 0, "rotated": false}).ok or not send("begin_day_one").ok:
		return false
	if route == "wholesale" and not send("trade", sale(DayOne.WHOLESALE, DayOne.WHOLESALER, 135, "wholesale_grid")).ok:
		return false
	if not send("day_one_next").ok:
		return false
	if route == "retail":
		if not send("move", {"actor": "player", "item_id": "R001", "inventory": "player_display", "x": 0, "y": 0, "rotated": false}).ok or not send("trade", sale(DayOne.RETAIL, "G02", 170, "g02_grid")).ok:
			return false
	elif not send("day_one_decline").ok:
		return false
	return send("day_one_next").ok

func cleanup() -> void:
	rt.shutdown()
	for name: String in ["gate1_day_one_v3.a.json", "gate1_day_one_v3.b.json"]:
		var path: String = directory.path_join(name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)

func _initialize() -> void:
	for route: String in ["retail", "wholesale", "hold"]:
		var ready: bool = fresh(100, route)
		check(ready, "route setup " + route)
		if not ready:
			quit(1)
			return
		var history_before: Dictionary = rt.snapshot()
		var history: Dictionary = rt.counter_view().item_history
		check(history.records.size() == (1 if route == "hold" else 2), "lineage contains actual transactions only " + route)
		check(history.records.back().direction == "purchase" and history.records.back().amounts.VKC == 100, "lineage purchase price " + route)
		check(rt.snapshot() == history_before, "lineage read has no state effect " + route)
		var cash: int = 250 if route == "retail" else (215 if route == "wholesale" else 80)
		check(rt.snapshot().wallets.player.VKC == cash and rt.snapshot().game_minutes == 15, "before independent service " + route)
		check(rt.snapshot().items.W001.owner_id == "G02" and reject("restore_item", {"actor": "player", "item_id": "W001"}), "no daytime repair")
		check(send("day_one_accept_service").ok and rt.snapshot().wallets.player.VKC == cash and rt.snapshot().items.W001.owner_id == "G02" and rt.snapshot().items.W001.custodian_id == "player" and rt.snapshot().items.W001.status == "custody_service", "custody without title transfer or fee")
		check(reject("day_one_accept_service") and reject("move", {"actor": "player", "item_id": "W001", "inventory": "player_display", "x": 0, "y": 0, "rotated": false}), "customer item protected")
		var close: Dictionary = command("day_one_close", {"confirm": true})
		check(rt.submit(close).ok and rt.snapshot().wallets.player.VKC == cash - 15 and rt.snapshot().game_minutes == 600, "overhead and close")
		var closed: Dictionary = rt.snapshot()
		check(rt.submit(close).ok and rt.snapshot() == closed and reject("day_one_close", {"confirm": true}), "closing exactly once")
		var repair: Dictionary = command("restore_item", {"actor": "player", "item_id": "W001"})
		check(rt.submit(repair).ok and rt.snapshot().wallets.player.VKC == cash - 25 and rt.snapshot().game_minutes == 600 and rt.snapshot().items.W001.basis == {"VKC": null, "USD": null}, "direct cost but no service income, time frozen")
		var completed: Dictionary = rt.snapshot()
		check(rt.submit(repair).ok and rt.snapshot() == completed and reject("restore_item", repair.payload) and reject("day_one_deliver_service"), "no repeated charge or same-day delivery")
		rt.shutdown()
		rt = Runtime.new()
		ready = rt.initialize_day_one(directory)
		check(ready and rt.load_saved().ok and rt.snapshot() == completed, "closed service save roundtrip")
		check(ready and rt.counter_view().item_history == history, "lineage survives save reload " + route)
		if not ready:
			quit(1)
			return
		check(send("day_one_next_morning").ok and rt.snapshot().game_minutes == 1440 and rt.snapshot().wallets.player.VKC == cash - 25 and reject("day_one_next_morning"), "14-hour explicit transition no automatic fee")
		var delivery: Dictionary = command("day_one_deliver_service")
		check(rt.submit(delivery).ok and rt.snapshot().wallets.player.VKC == cash + 5 and rt.snapshot().items.W001.owner_id == "G02" and rt.snapshot().items.W001.custodian_id == "G02", "actual return and fee")
		var delivered: Dictionary = rt.snapshot()
		check(rt.submit(delivery).ok and rt.snapshot() == delivered and reject("day_one_deliver_service"), "fee exactly once")
		if route == "hold":
			check(send("trade", sale(DayOne.RECOVERY, DayOne.RECOVERY_BUYER, 130, "day2_buyer_grid")).ok and rt.snapshot().wallets.player.VKC == 215 and reject("trade", sale(DayOne.RECOVERY, DayOne.RECOVERY_BUYER, 130, "day2_buyer_grid")), "finite D2 held-radio recovery")
		var authority: RefCounted = Probe.session(false)
		var initial: Dictionary = authority.snapshot()
		var actual: Dictionary = rt.snapshot()
		check(authority.restore(actual) and Accounting.reconcile(actual, initial), "independent accounting reconciliation " + route)
		var wrong: Dictionary = actual.duplicate(true)
		wrong.wallets.player.VKC += 1
		check(not Accounting.reconcile(wrong, initial), "forged balance refused " + route)
		var partition: Dictionary = Registry.begin(actual, authority)
		var archived: Dictionary = Registry.sleep_family(partition, "R001", authority)
		check(not archived.is_empty() and Registry.materialize(archived, authority) == actual, "actual sold same radio dormant " + route)
		if not archived.is_empty():
			var chosen: Dictionary = Tracking.promote(archived, "R001", "tracked", false, authority)
			var receipt: String = actual.ledger.back().event_id
			chosen = Tracking.retain_reference(chosen, "R001", receipt, authority)
			check(not chosen.is_empty() and Tracking.retain_reference(chosen, "R001", receipt, authority) == chosen, "real reference retained once " + route)
			var stopped: Dictionary = Tracking.suspend(chosen, "R001", authority)
			check(not stopped.is_empty() and stopped.tracking.R001.refs == [receipt], "tracking stop preserves actual reference " + route)
			var encoded: String = Codec.pack(stopped, authority, initial)
			var decoded: Dictionary = Codec.unpack(encoded, authority, initial)
			check(not encoded.is_empty() and decoded.get("state") == actual and decoded.get("partition") == stopped and History.public_history(decoded.state, "R001") == History.public_history(actual, "R001"), "partition and public ledger roundtrip " + route)
			print("ZT_REGISTRY_SAMPLE ", JSON.stringify({"route": route, "legacy_bytes": Format.encoded_size(actual), "pilot_bytes": encoded.to_utf8_buffer().size(), "revision": actual.revision}))
		cleanup()
	var ready: bool = fresh(180, "hold")
	check(ready, "cash-short service case")
	if ready:
		check(send("day_one_accept_service").ok and send("day_one_close", {"confirm": true}).ok and rt.snapshot().wallets.player.VKC == 0 and rt.counter_view().day_one.closing.debt == 15, "no negative cash, explicit fixed-cost debt")
		check(reject("restore_item", {"actor": "player", "item_id": "W001"}), "repair cannot spend unavailable money")
		check(send("day_one_next_morning").ok and reject("day_one_deliver_service"), "unfinished service cannot pay")
		check(send("day_one_cancel_service").ok and rt.snapshot().items.W001.custodian_id == "G02", "uncompleted service returned without fee")
		check(send("trade", sale(DayOne.RECOVERY, DayOne.RECOVERY_BUYER, 130, "day2_buyer_grid")).ok and send("day_one_pay_overhead").ok and rt.snapshot().wallets.player.VKC == 115 and rt.counter_view().day_one.closing.debt == 0, "recover stock and discharge debt once")
		cleanup()
	ready = fresh(100, "hold")
	check(ready, "refusal case")
	if ready:
		check(send("day_one_decline").ok and send("day_one_close", {"confirm": true}).ok and rt.snapshot().wallets.player.VKC == 65 and rt.snapshot().items.W001.custodian_id == "G02", "decline without fee/cost or custody")
		check(send("day_one_next_morning").ok and reject("day_one_deliver_service"), "no payment for refused work")
		cleanup()
	print("GATE1_3: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
