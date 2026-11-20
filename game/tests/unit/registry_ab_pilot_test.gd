extends SceneTree
const Repo = preload("res://src/persistence/registry_pilot_repository.gd")
const Legacy = preload("res://src/persistence/save_repository.gd")
const Registry = preload("res://src/domain/dormant_registry.gd")
const Tracking = preload("res://src/domain/selective_tracking.gd")
const Fixture = preload("res://tests/fixtures/gate0_c_state.gd")
const Session = preload("res://src/domain/game_session.gd")
const Rules = preload("res://src/domain/value_rules.gd")
var checks: int = 0
var failures: int = 0
var directory: String = "user://zt_rebuild/registry_ab_" + str(Time.get_ticks_usec())

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func fresh() -> RefCounted:
	var state: Dictionary = Fixture.make()
	state.game_minutes = 10
	state.visits.purchase.expires = 5
	var s := Session.new()
	return s if s.initialize(Fixture.definitions(), state) else null

func put(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(content)
	f.close()

func _initialize() -> void:
	var authority: RefCounted = fresh()
	if authority == null:
		quit(1)
		return
	var full: Dictionary = authority.snapshot()
	var legacy := Legacy.new(directory)
	var repo := Repo.new(directory)
	check(legacy.save_session(authority, "slot").ok, "legacy generation")
	var original: PackedByteArray = FileAccess.get_file_as_bytes(directory.path_join("slot.a.json"))
	var p: Dictionary = Registry.begin(full, authority)
	var archived: Dictionary = Registry.sleep_family(p, "X01", authority)
	var tracked: Dictionary = Tracking.promote(archived, "X01_A", "narrative", true, authority)
	check(repo.save("slot", tracked, 0, [], fresh).get("storage_revision") == 1, "initial isolated import")
	# Simulate an existing v1 on disk without modifying the validated partition.
	var first_path: String = directory.path_join("slot.registry.a.json")
	var old_format: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(first_path))
	old_format.body.contract = Repo.CONTRACT
	old_format.body.erase("transition")
	old_format.checksum = Rules.canonical(old_format.body).sha256_text()
	put(first_path, Rules.canonical(old_format))
	var old_bytes: String = FileAccess.get_file_as_string(first_path)
	var loaded: Dictionary = repo.load_state("slot", fresh)
	check(loaded.get("state") == full and loaded.get("partition") == tracked and not loaded.modern, "existing v1 source exact and readable")
	check(FileAccess.get_file_as_string(first_path) == old_bytes, "read never rewrites v1 file")
	var wake: Dictionary = Registry.wake_family(tracked, "X01", authority)
	check(repo.save("slot", wake, 1, [], fresh).get("storage_revision") == 2, "metadata-only new generation")
	check(FileAccess.get_file_as_string(first_path) == old_bytes and repo.load_state("slot", fresh).get("modern", false), "mixed v1/v2 pair exact, original retained")
	check(repo.save("slot", tracked, 1, [], fresh).get("error") == "stale_storage", "stale metadata CAS denied")
	check(repo.save("slot", p, 2, [], fresh).get("error") == "continuity_or_retention", "pinned item record cannot be stripped")
	var command: Dictionary = {"action_id": "tick_new", "expected_revision": 0, "type": "advance_time", "payload": {"minutes": 1}}
	check(authority.execute(command).ok, "actual next command")
	var next: Dictionary = wake.duplicate(true)
	next.state = authority.snapshot()
	check(repo.save("slot", next, 2, [], fresh).get("error") == "continuity_or_retention", "missing command proof rejected")
	check(repo.save("slot", next, 2, [command], fresh).get("storage_revision") == 3, "actual authority transition via bounded proof")
	check(repo.load_state("slot", fresh).partition == next, "reloaded authority and metadata exact")
	var newest: String = directory.path_join("slot.registry.a.json")
	var bytes: String = FileAccess.get_file_as_string(newest)
	var changed: Dictionary = JSON.parse_string(bytes)
	changed.body.transition.parent_digest = "0".repeat(64)
	changed.checksum = Rules.canonical(changed.body).sha256_text()
	put(newest, Rules.canonical(changed))
	check(repo.load_state("slot", fresh).get("error") == "history_conflict", "independently valid state with wrong parent link denied")
	changed = JSON.parse_string(bytes)
	changed.body.transition.journal[0].payload.minutes = 2
	changed.checksum = Rules.canonical(changed.body).sha256_text()
	put(newest, Rules.canonical(changed))
	check(repo.load_state("slot", fresh).get("error") == "history_conflict", "resealed journal cannot contradict state")
	put(newest, bytes)
	put(newest + ".tmp", "interrupted")
	check(repo.load_state("slot", fresh).get("storage_revision") == 3, "interrupted temp ignored")
	put(newest, "broken")
	var recovered: Dictionary = repo.load_state("slot", fresh)
	check(recovered.get("recovered", false) and recovered.get("partition") == wake, "recover prior independent state+metadata")
	check(repo.save("slot", next, 2, [command], fresh).get("storage_revision") == 3, "repair damaged generation with actual proof")
	var unknown: Dictionary = JSON.parse_string(bytes)
	unknown.body.contract = "future"
	unknown.checksum = Rules.canonical(unknown.body).sha256_text()
	put(newest, Rules.canonical(unknown))
	check(repo.load_state("slot", fresh).get("error") == "unsupported_contract" and repo.save("slot", next, 3, [], fresh).get("error") == "unsupported_contract", "unknown format not silently overwritten")
	check(FileAccess.get_file_as_bytes(directory.path_join("slot.a.json")) == original, "original legacy unchanged")
	var dir := DirAccess.open(directory)
	for name: String in dir.get_files():
		dir.remove(name)
	DirAccess.remove_absolute(directory)
	print("REGISTRY_AB_PILOT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
