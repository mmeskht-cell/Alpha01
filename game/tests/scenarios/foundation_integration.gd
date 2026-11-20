extends SceneTree
const Runtime = preload("res://src/application/foundation_runtime.gd")
const Fixture = preload("res://tests/fixtures/foundation_state.gd")
var failures: int = 0
var checks: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	var directory: String = "user://zt_rebuild/integration_" + str(Time.get_ticks_usec())
	var runtime := Runtime.new()
	check(runtime.initialize(Fixture.make(), "test", directory), "runtime initializes")
	var buy := {"action_id": "buy", "expected_revision": 0, "type": "trade", "payload": {"item_id": "parcel_001", "seller": "seller", "buyer": "player", "currency": "VKC", "amount": 50, "inventory": "player_grid", "x": 0, "y": 0, "rotated": false}}
	var result := runtime.submit(buy)
	check(result.ok and result.persisted, "trade committed and persisted")
	var state := runtime.snapshot()
	runtime.localization.select_language("en")
	check(runtime.load_saved().ok and runtime.snapshot() == state and runtime.localization.current_locale() == "en", "same save in English preserves domain and setting")
	runtime.localization.select_language("ko")
	check(runtime.load_saved().ok and runtime.snapshot() == state, "same save in Korean")
	check(runtime.submit(buy).persisted and runtime.snapshot() == state, "reloaded duplicate does not trade twice")
	runtime.shutdown()
	var blocked_path: String = directory + "/blocker"
	var file := FileAccess.open(blocked_path, FileAccess.WRITE)
	file.store_string("not a directory")
	file.close()
	var blocked := Runtime.new()
	check(blocked.initialize(Fixture.make(), "test", blocked_path), "failure fixture initializes")
	result = blocked.submit(buy)
	check(result.ok and not result.persisted and result.has("save_error"), "save failure distinguished from committed memory")
	check(blocked.snapshot().items.parcel_001.owner_id == "player", "save failure does not misreport transaction rollback")
	var pending: Dictionary = blocked.snapshot()
	var tick := {"action_id": "tick_after_failure", "expected_revision": pending.revision, "type": "advance_time", "payload": {"minutes": 1}}
	check(blocked.persistence_view().save_pending and blocked.submit(tick).error == "save_pending" and blocked.snapshot() == pending, "application refuses further changes while save pending")
	check(blocked.load_saved().error == "save_pending" and blocked.snapshot() == pending, "load cannot silently discard committed memory")
	DirAccess.remove_absolute(blocked_path)
	check(blocked.retry_save().ok and not blocked.persistence_view().save_pending, "retry clears application block")
	check(blocked.submit(tick).ok and blocked.snapshot().revision == pending.revision + 1, "new command allowed after persisted retry")
	blocked.shutdown()
	var retry_dir := DirAccess.open(blocked_path)
	for name: String in retry_dir.get_files():
		retry_dir.remove(name)
	DirAccess.remove_absolute(blocked_path)
	var folder := DirAccess.open(directory)
	for name: String in folder.get_files():
		folder.remove(name)
	DirAccess.remove_absolute(directory)
	print("INTEGRATION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
