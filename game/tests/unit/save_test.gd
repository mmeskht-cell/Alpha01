extends SceneTree
const Catalog = preload("res://src/content/catalog_loader.gd")
const Session = preload("res://src/domain/game_session.gd")
const Fixture = preload("res://tests/fixtures/foundation_state.gd")
const Repository = preload("res://src/persistence/save_repository.gd")
const Rules = preload("res://src/domain/value_rules.gd")
var failures: int = 0
var checks: int = 0
var save_test_dir: String = "user://zt_rebuild/test_saves_" + str(Time.get_ticks_usec())

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)

func put(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _initialize() -> void:
	var catalog := Catalog.load_file("res://data/catalog/foundation.json")
	var session := Session.new()
	session.initialize(catalog.definitions, Fixture.make())
	var repo := Repository.new(save_test_dir)
	check(repo.save_session(session, "slot").ok, "first generation write")
	var original := session.snapshot()
	var first_path: String = save_test_dir.path_join("slot.a.json")
	var first_bytes: PackedByteArray = FileAccess.get_file_as_bytes(first_path)
	check(repo._matches_bytes(first_path, first_bytes), "exact persisted bytes verified")
	var altered: PackedByteArray = first_bytes.duplicate()
	altered[altered.size() - 1] = 0
	check(not repo._matches_bytes(first_path, altered), "same length difference refused")
	check(not repo._matches_bytes(first_path, PackedByteArray()) and not repo._matches_bytes(save_test_dir.path_join("missing"), first_bytes), "missing or truncated rejected")
	var command := {"action_id": "tick", "expected_revision": 0, "type": "advance_time", "payload": {"minutes": 1}}
	check(session.execute(command).ok, "mutation")
	check(repo.save_session(session, "slot").ok, "second generation write")
	var current := session.snapshot()
	var restored := Session.new()
	restored.initialize(catalog.definitions, Fixture.make())
	check(repo.load_session(restored, "slot").ok and restored.snapshot() == current, "exact round trip")
	check(typeof(restored.snapshot().revision) == TYPE_INT, "integer restoration")
	check(restored.execute(command).ok and restored.snapshot() == current, "duplicate survives reload")
	check(repo.save_session(restored, "slot").get("unchanged", false), "same revision no rewrite")
	put(save_test_dir.path_join("slot.b.json.tmp"), "incomplete")
	check(repo.load_session(restored, "slot").ok and restored.snapshot() == current, "unfinished temporary ignored")
	put(save_test_dir.path_join("slot.b.json"), "corrupted")
	var recovered := repo.load_session(restored, "slot")
	check(recovered.ok and recovered.recovered and restored.snapshot() == original, "corruption fallback")
	check(restored.execute(command).ok and repo.save_session(restored, "slot").ok, "repair damaged generation")
	var bad: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_test_dir.path_join("slot.b.json")))
	bad.payload += " "
	put(save_test_dir.path_join("slot.b.json"), JSON.stringify(bad))
	check(repo.load_session(restored, "slot").ok and restored.snapshot() == original, "checksum fallback")
	bad = JSON.parse_string(FileAccess.get_file_as_string(save_test_dir.path_join("slot.a.json")))
	bad.schema_version = 99
	put(save_test_dir.path_join("slot.b.json"), JSON.stringify(bad))
	var before := restored.snapshot()
	check(repo.load_session(restored, "slot").error == "future_schema" and restored.snapshot() == before, "future version refused, no silent fallback")
	check(repo.save_session(restored, "slot").error == "future_schema", "future save never overwritten")
	put(save_test_dir.path_join("slot.b.json"), "corrupted")
	put(save_test_dir.path_join("slot.a.json"), "corrupted")
	check(repo.load_session(restored, "slot").error == "no_valid_save" and restored.snapshot() == before, "both corrupt no mutation")
	check(repo.save_session(restored, "slot").error == "no_valid_save" and FileAccess.get_file_as_string(save_test_dir.path_join("slot.a.json")) == "corrupted" and FileAccess.get_file_as_string(save_test_dir.path_join("slot.b.json")) == "corrupted", "both corrupt files preserved")
	check(repo.load_session(restored, "../escape").error == "slot_id", "path traversal rejected")
	check(repo.save_session(session, "fresh").ok, "new slot")
	check(repo.save_session(restored, "fresh").error == "revision_regression", "older revision refused")
	# Overwriting the older generation exercises Linux rename replacement.
	var next := {"action_id": "tick2", "expected_revision": 1, "type": "advance_time", "payload": {"minutes": 1}}
	session.execute(next)
	check(repo.save_session(session, "fresh").ok, "second write")
	next.action_id = "tick3"
	next.expected_revision = 2
	session.execute(next)
	check(repo.save_session(session, "fresh").ok and repo.load_session(restored, "fresh").ok and restored.snapshot() == session.snapshot(), "third write replaces older generation")
	var directory := DirAccess.open(save_test_dir)
	for name: String in directory.get_files():
		directory.remove(name)
	DirAccess.remove_absolute(save_test_dir)
	print("SAVE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
