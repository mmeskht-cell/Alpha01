extends SceneTree
## One bounded engineering workload, not a simulated story or player campaign.
## Existing generic fixture, 1 new atomic stock and 1 purchase per day.
const Session = preload("res://src/domain/game_session.gd")
const Fixture = preload("res://tests/fixtures/gate0_c_state.gd")
const Format = preload("res://src/persistence/checkpoint_format.gd")
const Repo = preload("res://src/persistence/checkpoint_repository.gd")
const Legacy = preload("res://src/domain/snapshot_format.gd")
var checks: int = 0
var failures: int = 0
var directory: String = "user://zt_rebuild/capacity_" + str(Time.get_ticks_usec())
var session: RefCounted
var serial: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func fresh() -> RefCounted:
	var initial: Dictionary = Fixture.make()
	initial.visits.purchase.expires = 0
	var s := Session.new()
	return s if s.initialize(Fixture.definitions(), initial, false, true) else null

func issue(kind: String, p: Dictionary, world: bool = false) -> bool:
	serial += 1
	var command: Dictionary = {"action_id": "capacity_" + str(serial), "expected_revision": session.snapshot().revision, "type": kind, "payload": p}
	var result: Dictionary = session.execute_world(command) if world else session.execute(command)
	if not result.ok:
		printerr("Capacity command rejected: ", kind, " ", result)
	return result.ok

func measure(day: int, repo: RefCounted) -> bool:
	var snapshot: Dictionary = session.snapshot()
	var slot: String = "budget"
	var bytes: int = Format.encode("s".repeat(64), snapshot, [], snapshot).to_utf8_buffer().size()
	var start: int = Time.get_ticks_usec()
	var saved: Dictionary = repo.save(slot, snapshot, [], snapshot, fresh)
	var save_us: int = Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	var loaded: Dictionary = repo.load_state(slot, fresh)
	var load_us: int = Time.get_ticks_usec() - start
	var ok: bool = bytes > 0 and bytes <= Format.MAX_BYTES and saved.get("ok", false) and loaded.get("ok", false) and loaded.get("state") == snapshot and snapshot.game_minutes == day * 1440 and snapshot.ledger.size() == day and snapshot.wallets.player.VKC == 180 - day and snapshot.receipt_archive.size() > 0
	print("ZT_CAPACITY_SAMPLE ", JSON.stringify({"days": day, "revision": snapshot.revision, "active": snapshot.items.size(), "dormant_roots": snapshot.lifecycle.dormant.size(), "visits": snapshot.visits.size(), "archived_receipts": snapshot.receipt_archive.size(), "v4_bytes": bytes, "schema3_guard_bytes": Legacy.encoded_size(snapshot), "save_us": save_us, "load_us": load_us, "ok": ok}))
	return ok

func _initialize() -> void:
	session = fresh()
	check(session != null, "fresh generic technical authority")
	if session == null:
		quit(1)
		return
	var repo := Repo.new(directory)
	var start: int = Time.get_ticks_usec()
	for day: int in range(42):
		var id: String = "day_stock_" + str(day)
		var visit: String = "day_visit_" + str(day)
		var minute: int = day * 1440
		@warning_ignore("integer_division")
		var cell_y: int = day / 10
		var ok: bool = issue("world_spawn_stock", {"item_id": id, "def_id": "sample_consumable", "owner": "seller", "inventory": "seller_grid", "x": 9, "y": 5, "rotated": false, "functional": true}, true)
		ok = ok and issue("world_open_visit", {"visit_id": visit, "item_id": id, "seller": "seller", "buyer": "player", "price": {"VKC": 1, "USD": 0}, "opens": minute, "expires": minute + 60, "allow_inspection": true}, true)
		ok = ok and issue("trade", {"visit_id": visit, "item_id": id, "seller": "seller", "buyer": "player", "currency": "VKC", "amount": 1, "inventory": "player_grid", "x": day % 10, "y": cell_y, "rotated": false})
		for block: int in range(6):
			ok = ok and issue("advance_time", {"minutes": 240})
		if not ok:
			check(false, "fixed workload command day " + str(day + 1))
			break
		if day == 6 or day == 41:
			check(measure(day + 1, repo), "actual saved checkpoint and exact cold reload day " + str(day + 1))
	check(session.snapshot().revision == 378, "all 378 bounded technical commands complete")
	print("ZT_CAPACITY_ELAPSED_US ", Time.get_ticks_usec() - start)
	var dir := DirAccess.open(directory)
	if dir != null:
		for name: String in dir.get_files():
			dir.remove(name)
		DirAccess.remove_absolute(directory)
	print("CAMPAIGN_CAPACITY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
