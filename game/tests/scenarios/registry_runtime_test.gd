extends SceneTree
const Runtime = preload("res://src/application/foundation_runtime.gd")
const Legacy = preload("res://src/persistence/save_repository.gd")
const Probe = preload("res://tests/fixtures/checkpoint_campaign_probe.gd")
const Rules = preload("res://src/domain/value_rules.gd")
var checks: int = 0
var failures: int = 0
var rt: RefCounted
var serial: int = 0
var directory: String

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func cmd(kind: String, p: Dictionary = {}) -> Dictionary:
	serial += 1
	return {"action_id": "registry_runtime_" + str(serial), "expected_revision": rt.snapshot().revision, "type": kind, "payload": p}

func send(kind: String, p: Dictionary = {}) -> bool:
	var result: Dictionary = rt.submit(cmd(kind, p))
	return result.ok and result.get("persisted", false)

func put(path: String, value: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(value)
	f.close()

func _initialize() -> void:
	directory = "user://zt_rebuild/day_one/registry_runtime_" + str(Time.get_ticks_usec())
	var slot: String = "gate1_day_one_v3"
	rt = Runtime.new()
	var ready: bool = rt.initialize_day_one(directory) and send("accept_rad1_contract") and send("next_visit") and send("decline_visit") and send("begin_day_one")
	check(ready, "legacy real runtime setup")
	if not ready:
		quit(1)
		return
	var original: Dictionary = rt.snapshot()
	var a: String = directory.path_join(slot + ".a.json")
	var b: String = directory.path_join(slot + ".b.json")
	var ab: PackedByteArray = FileAccess.get_file_as_bytes(a)
	var bb: PackedByteArray = FileAccess.get_file_as_bytes(b)
	rt.shutdown()
	rt = Runtime.new()
	check(rt.initialize_day_one(directory, true) and not rt.persistence_view().load_failed and rt.snapshot() == original, "actual application migrates legacy exactly")
	# Exercise the previous production registry layout with the exact real
	# campaign snapshot and binding, not a made-up wallet or item fixture.
	var old_registry_path: String = directory.path_join(slot + ".registry.a.json")
	var old_registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(old_registry_path))
	old_registry.body.contract = "registry-ab-runtime-1"
	old_registry.body.erase("transition")
	old_registry.checksum = Rules.canonical(old_registry.body).sha256_text()
	var old_registry_data: String = Rules.canonical(old_registry)
	put(old_registry_path, old_registry_data)
	rt.shutdown()
	rt = Runtime.new()
	check(rt.initialize_day_one(directory, false) and not rt.persistence_view().load_failed and rt.snapshot() == original, "real production v1 registry reopened with exact slot binding")
	check(FileAccess.get_file_as_string(old_registry_path) == old_registry_data, "production v1 read does not rewrite old bytes")
	var next: Dictionary = cmd("day_one_next")
	var result: Dictionary = rt.submit(next)
	check(result.ok and result.persisted, "post-migration command saved")
	var after: Dictionary = rt.snapshot()
	var new_registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(slot + ".registry.b.json")))
	check(new_registry.body.contract == "registry-ab-runtime-2" and new_registry.body.transition.parent_revision == 1 and FileAccess.get_file_as_string(old_registry_path) == old_registry_data, "first subsequent commit upgrades adjacent generation, old source intact")
	check(rt.submit(next).persisted and rt.snapshot() == after, "duplicate command remains exactly once")
	rt.shutdown()
	rt = Runtime.new()
	check(rt.initialize_day_one(directory, false) and not rt.persistence_view().load_failed and rt.persistence_view().registry_storage and rt.snapshot() == after, "restart selects active registry even with old configuration")
	var old: RefCounted = Probe.session(false)
	var legacy := Legacy.new(directory)
	check(legacy.save_session(old, slot).get("error") == "registry_active" and legacy.load_session(old, slot).get("error") == "registry_active", "legacy repository refuses migrated slot")
	check(send("day_one_decline") and send("day_one_next") and send("day_one_decline") and send("day_one_close", {"confirm": true}), "same day-one rules through new backend")
	var closed: Dictionary = rt.snapshot()
	check(closed.wallets.player.VKC == 165 and closed.game_minutes == 600, "actual economy unchanged")
	check(FileAccess.get_file_as_bytes(a) == ab and FileAccess.get_file_as_bytes(b) == bb, "legacy originals remain unchanged")
	var prefix: String = directory.path_join(slot + ".registry.")
	var ra: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(prefix + "a.json"))
	var rb: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(prefix + "b.json"))
	var latest: Dictionary = ra if ra.body.storage_revision > rb.body.storage_revision else rb
	var newest: String = prefix + ("a.json" if ra.body.storage_revision > rb.body.storage_revision else "b.json")
	check(not latest.body.registry.body.partition.dormant.has("R001"), "closing boundary preserves unfinished visit through inclusive expiry")
	check(latest.body.registry.body.partition.tracking.is_empty(), "no automatic L2 activation")
	put(newest, "damaged")
	rt.shutdown()
	rt = Runtime.new()
	check(rt.initialize_day_one(directory, true) and not rt.persistence_view().load_failed and rt.snapshot().revision == closed.revision - 1, "actual runtime recovers earlier generation without legacy rollback")
	check(send("day_one_close", {"confirm": true}) and rt.snapshot().wallets.player.VKC == 165, "recovered generation can continue without double debit")
	check(send("day_one_next_morning"), "expired visit on next morning")
	ra = JSON.parse_string(FileAccess.get_file_as_string(prefix + "a.json"))
	rb = JSON.parse_string(FileAccess.get_file_as_string(prefix + "b.json"))
	latest = ra if ra.body.storage_revision > rb.body.storage_revision else rb
	check(latest.body.registry.body.partition.dormant.has("R001"), "real runtime stores eligible external family after visit expiry")
	var morning: Dictionary = rt.snapshot()
	check(rt.load_saved().ok and rt.snapshot() == morning, "dormant materialization exact on runtime load")
	rt.shutdown()
	put(a, "changed legacy")
	rt = Runtime.new()
	check(rt.initialize_day_one(directory, true) and rt.persistence_view().load_failed and not rt.submit(cmd("accept_rad1_contract")).ok, "modified frozen source blocks divergent migration")
	rt.shutdown()
	var restore_file := FileAccess.open(a, FileAccess.WRITE)
	restore_file.store_buffer(ab)
	restore_file.close()
	DirAccess.remove_absolute(prefix + "a.json")
	DirAccess.remove_absolute(prefix + "b.json")
	rt = Runtime.new()
	check(rt.initialize_day_one(directory, false) and rt.persistence_view().load_failed and rt.persistence_view().registry_storage, "activation marker prevents silent downgrade even with old configuration")
	check(FileAccess.get_file_as_bytes(a) == ab and FileAccess.get_file_as_bytes(b) == bb, "failure never overwrites frozen legacy generations")
	rt.shutdown()
	var dir := DirAccess.open(directory)
	for name: String in dir.get_files():
		dir.remove(name)
	DirAccess.remove_absolute(directory)
	print("REGISTRY_RUNTIME: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
