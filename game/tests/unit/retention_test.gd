extends SceneTree
const Session = preload("res://src/domain/game_session.gd")
const Catalog = preload("res://src/content/catalog_loader.gd")
const Fixture = preload("res://tests/fixtures/foundation_state.gd")
const Saves = preload("res://src/persistence/save_repository.gd")
const Format = preload("res://src/domain/snapshot_format.gd")
const Rules = preload("res://src/domain/value_rules.gd")
var failures: int = 0
var checks: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func archive_fixture(count: int) -> Dictionary:
	var fixture: Dictionary = Fixture.make()
	fixture.receipt_archive = {}
	fixture.revision = count
	for index: int in range(count):
		fixture.receipt_archive[("a".repeat(52) + "%012d" % index)] = ["a".repeat(64), index + 1, "move"]
	return fixture

func _initialize() -> void:
	var definitions: Dictionary = Catalog.load_file("res://data/catalog/foundation.json").definitions
	var session := Session.new()
	session.initialize(definitions, Fixture.make())
	var commands: Array = []
	var all_ok: bool = true
	var legacy: Dictionary
	for index: int in range(160):
		var buying: bool = index % 2 == 0
		var command := {"action_id": "trade_%d" % index, "expected_revision": index, "type": "trade", "payload": {"item_id": "parcel_001", "seller": "seller" if buying else "player", "buyer": "player" if buying else "seller", "currency": "VKC", "amount": 1, "inventory": "player_grid" if buying else "seller_grid", "x": 0, "y": 0, "rotated": false}}
		commands.append(command)
		all_ok = session.execute(command).ok and all_ok
		if index == 127:
			legacy = session.snapshot()
	check(all_ok and session.snapshot().revision == 160, "cross former 128 limit")
	var state: Dictionary = session.snapshot()
	check(state.receipts.size() == 32 and state.receipt_archive.size() == 128 and state.ledger.size() == 160, "bounded recent receipts, complete archive and ledger")
	check(state.wallets == Fixture.make().wallets and state.items.parcel_001.owner_id == "seller", "trade funds and ownership conserved")
	check(session.execute(commands[0]) == {"ok": true, "revision": 1} and session.snapshot() == state, "archived retry returns original result")
	var reused: Dictionary = commands[0].duplicate(true)
	reused.expected_revision = 160
	check(session.execute(reused).error == "action_id_reused" and session.snapshot() == state, "old ID cannot be recycled at current revision")
	var dir: String = "user://zt_rebuild/retention_" + str(Time.get_ticks_usec())
	var saves := Saves.new(dir)
	check(saves.save_session(session, "test").ok, "compacted state saves")
	var restored := Session.new()
	restored.initialize(definitions, Fixture.make())
	check(saves.load_session(restored, "test").ok and restored.snapshot() == state, "archive and ledger roundtrip")
	check(restored.execute(commands[0]).revision == 1 and restored.snapshot() == state, "archived duplicate after reload")
	# Build an actual v1 envelope from the first 128 known requests.
	legacy.erase("receipt_archive")
	legacy.receipts = {}
	for index: int in range(128):
		legacy.receipts[commands[index].action_id] = {"fingerprint": Rules.canonical(commands[index]), "result": {"ok": true, "revision": index + 1}}
	for key: String in ["object_schema", "tombstones", "object_events", "visits", "phase", "knowledge"]:
		legacy.erase(key)
	for item: Dictionary in legacy.items.values():
		for key: String in item.keys():
			if key not in ["def_id", "owner_id", "custodian_id", "status", "inventory", "x", "y", "rotated", "version"]:
				item.erase(key)
	for grid: Dictionary in legacy.inventories.values():
		grid.erase("host_item")
	for index: int in range(legacy.ledger.size()):
		var entry: Dictionary = legacy.ledger[index]
		legacy.ledger[index] = {"event_id": entry.event_id, "revision": entry.revision, "game_minutes": entry.game_minutes, "item_id": entry.root_ids[0], "from": entry.from, "to": entry.to, "currency": "VKC", "amount": 1}
	var envelope: Dictionary = JSON.parse_string(Format.encode(legacy, "old"))
	envelope.schema_version = 1
	var file := FileAccess.open(dir.path_join("old.a.json"), FileAccess.WRITE)
	var original_file: String = JSON.stringify(envelope)
	file.store_string(original_file)
	file.close()
	check(saves.load_session(restored, "old").error == "unsupported_schema", "v1 explicitly refused")
	check(FileAccess.get_file_as_string(dir.path_join("old.a.json")) == original_file, "v1 original not overwritten")
	check(saves.save_session(session, "old").error == "unsupported_schema", "v1 not overwritten by current save")
	envelope.schema_version = 2
	file = FileAccess.open(dir.path_join("old.a.json"), FileAccess.WRITE)
	original_file = JSON.stringify(envelope)
	file.store_string(original_file)
	file.close()
	check(saves.load_session(restored, "old").error == "unsupported_schema" and saves.save_session(session, "old").error == "unsupported_schema" and FileAccess.get_file_as_string(dir.path_join("old.a.json")) == original_file, "v2 load and overwrite refused")
	check(saves.save_session(session, "new").ok and JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("new.a.json"))).schema_version == 3, "new slot uses v3")
	var invalid := state.duplicate(true)
	invalid.receipt_archive.erase("trade_0")
	check(not session.validate(invalid), "missing archive receipt rejected")
	invalid = state.duplicate(true)
	invalid.receipt_archive.trade_0[1] = 2
	check(not session.validate(invalid), "duplicate archived revision rejected")
	# The current restore contract rejects oversized states before installing them.
	var large: Dictionary = archive_fixture(7000)
	var encoded_bytes: int = Format.encode(large, "test").to_utf8_buffer().size()
	check(session.validate(large), "oversize synthetic archive structurally valid")
	check(encoded_bytes > Format.MAX_BYTES and not Format.fits(large), "UTF8 encoded envelope exceeds fixed 1MiB")
	var original_state: Dictionary = restored.snapshot()
	var previous_file: String = FileAccess.get_file_as_string(dir.path_join("test.a.json"))
	check(not restored.restore(large) and restored.snapshot() == original_state, "oversize direct restore rejected atomically")
	# Find the largest fitting synthetic archive. Its next receipt exceeds the bound.
	var low: int = 0
	var high: int = 7000
	while low + 1 < high:
		var mid: int = (low + high) / 2
		if Format.fits(archive_fixture(mid)):
			low = mid
		else:
			high = mid
	var near: Dictionary = archive_fixture(low)
	var near_ready: bool = Format.fits(near) and not Format.fits(archive_fixture(low + 1)) and restored.restore(near)
	check(near_ready, "maximum fitting archive fixture restores")
	if near_ready:
		var before: Dictionary = restored.snapshot()
		var capacity_result: Dictionary = restored.execute({"action_id": "b".repeat(64), "expected_revision": low, "type": "advance_time", "payload": {"minutes": 1}})
		check(capacity_result.get("error", "") == "save_capacity" and restored.snapshot() == before, "capacity failure before any state mutation")
	else:
		check(false, "capacity failure cannot be evaluated without fitting archive")
	check(FileAccess.get_file_as_string(dir.path_join("test.a.json")) == previous_file, "rejected operations preserve good generation")
	check(saves.load_session(restored, "test").ok and restored.snapshot() == state, "previous valid save still loads")
	var bad := FileAccess.open(dir.path_join("test.b.json"), FileAccess.WRITE)
	bad.store_string("x".repeat(Format.MAX_BYTES + 1))
	bad.close()
	check(saves.load_session(restored, "test").ok and restored.snapshot() == state, "oversized disk generation falls back")
	print("RETENTION: %d checks, %d failures; 160-trade save=%d bytes, oversize fixture=%d bytes" % [checks, failures, previous_file.to_utf8_buffer().size(), encoded_bytes])
	var folder := DirAccess.open(dir)
	for name: String in folder.get_files():
		folder.remove(name)
	DirAccess.remove_absolute(dir)
	quit(0 if failures == 0 else 1)
