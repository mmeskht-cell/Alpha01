extends SceneTree
const Runtime = preload("res://src/application/foundation_runtime.gd")
const CheckpointProbe = preload("res://tests/fixtures/checkpoint_campaign_probe.gd")
const Customer = preload("res://src/domain/customer_inspection.gd")
var rt: RefCounted
var serial: int = 0
var checks: int = 0
var failures: int = 0
var directory: String = ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func send(kind: String, p: Dictionary = {}) -> bool:
	serial += 1
	var result: Dictionary = rt.submit({"action_id": "pilot_" + str(serial), "expected_revision": rt.counter_view().revision, "type": kind, "payload": p})
	return result.ok and result.get("persisted", false)

func reject(kind: String, p: Dictionary = {}) -> bool:
	var before: Dictionary = rt.snapshot()
	return not send(kind, p) and rt.snapshot() == before

func observe(id: String, key: String) -> Dictionary:
	return {"actor": "player", "item_id": id, "key": key}

func _initialize() -> void:
	directory = "user://zt_rebuild/composite_pilots/test_" + str(Time.get_ticks_usec())
	rt = Runtime.new()
	var ready: bool = rt.initialize_composite_pilot(directory)
	ready = ready and send("accept_rad1_contract") and send("next_visit") and send("decline_visit") and send("begin_day_one") and send("day_one_next") and send("day_one_decline") and send("day_one_next") and send("day_one_decline")
	check(ready, "main day-one session reaches optional test customer")
	if not ready:
		quit(1)
		return
	check(rt.counter_view().composite_pilot.can_offer and send("day_one_composite_offer"), "admit single pilot visit")
	var initial: Dictionary = rt.snapshot()
	check(initial.wallets.player.VKC == 180 and initial.items.size() == 6, "same wallet and inventory authority without injected money")
	check(reject("observe", observe("D001_A", "component_texture")) and reject("day_one_close", {"confirm": true}), "hidden part and premature closing denied")
	check(send("day_one_composite_request") and rt.snapshot().game_minutes == 5 and rt.snapshot().items == initial.items, "consent changes no item")
	check(send("observe", observe("D001_A", "component_texture")) and rt.snapshot().game_minutes == 10, "scoped sampled observation")
	check(reject("observe", observe("D001_A", "component_function")) and reject("day_one_composite_request"), "scope and one request enforced")
	check(send("day_one_composite_close") and reject("observe", observe("D001_A", "component_damage")), "close revokes new inspection")
	check(not rt.counter_view().composite_pilot.workshop.notes.is_empty(), "retained known note after closing")
	var trade: Dictionary = {"visit_id": Customer.VISIT, "item_id": Customer.ROOT, "seller": Customer.SELLER, "buyer": "player", "currency": "VKC", "amount": 80, "inventory": "player_stock", "x": 6, "y": 0, "rotated": false}
	check(send("trade", trade) and reject("trade", trade), "same-session atomic one-time purchase")
	var basis: int = 0
	for id: String in Customer.IDS:
		basis += int(rt.snapshot().items[id].basis.VKC)
	check(basis == 80 and rt.snapshot().wallets.player.VKC == 100 and rt.snapshot().ledger.size() == 1, "conserved family cost and shared ledger")
	var detach: Dictionary = {"actor": "player", "root_id": "D001", "child_id": "D001_B", "inventory": "player_stock", "x": 3, "y": 3, "rotated": false}
	check(reject("detach", detach) and send("day_one_close", {"confirm": true}), "evening-only physical change")
	check(send("detach", detach) and send("observe", observe("D001_B", "component_function")), "owned workshop uses same sampled record")
	check(send("restore_item", {"actor": "player", "item_id": "D001_B"}) and reject("restore_item", {"actor": "player", "item_id": "D001_B"}), "one cost and no repeated restoration")
	check(send("observe", observe("D001_B", "component_function")) and send("attach", {"actor": "player", "root_id": "D001", "child_id": "D001_B"}), "reappraisal and composition preserved")
	var saved: Dictionary = rt.snapshot()
	check(saved.wallets.player.VKC == 80 and saved.game_minutes == 600 and saved.items.D001_B.parent_id == "D001" and saved.knowledge.size() == 3, "evening same session conservation")
	check(rt.save_capacity_view().fits and rt.load_saved().ok and rt.snapshot() == saved, "A/B exact roundtrip")
	var converted: Dictionary = CheckpointProbe.probe(directory, true, saved)
	check(converted.get("ok", false), "actual composite campaign v3 to isolated v4 exact readback and unchanged originals")
	print("ZT_CAMPAIGN_CHECKPOINT ", JSON.stringify(converted))
	var a_path: String = directory.path_join("gate1_composite_pilot_v3.a.json")
	var b_path: String = directory.path_join("gate1_composite_pilot_v3.b.json")
	var a_bytes: PackedByteArray = FileAccess.get_file_as_bytes(a_path)
	var b_bytes: PackedByteArray = FileAccess.get_file_as_bytes(b_path)
	rt.shutdown()
	rt = Runtime.new()
	check(rt.initialize_composite_pilot(directory, true) and not rt.persistence_view().load_failed and rt.snapshot() == saved, "actual composite legacy migration preserves all historical data")
	check(send("day_one_next_morning") and rt.snapshot().game_minutes == 1440 and rt.snapshot().items.D001_B.parent_id == "D001", "next morning retains purchased family through new registry")
	var morning: Dictionary = rt.snapshot()
	rt.shutdown()
	rt = Runtime.new()
	check(rt.initialize_composite_pilot(directory, false) and not rt.persistence_view().load_failed and rt.snapshot() == morning, "actual composite cold reload uses migrated authority")
	check(FileAccess.get_file_as_bytes(a_path) == a_bytes and FileAccess.get_file_as_bytes(b_path) == b_bytes, "frozen composite legacy source unchanged")
	rt.shutdown()
	var dir := DirAccess.open(directory)
	for name: String in dir.get_files():
		dir.remove(name)
	DirAccess.remove_absolute(directory)
	print("CAMPAIGN_COMPOSITE_PILOT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
