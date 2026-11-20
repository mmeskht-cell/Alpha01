extends SceneTree
const Format = preload("res://src/persistence/checkpoint_format.gd")
const Repo = preload("res://src/persistence/checkpoint_repository.gd")
const LegacyRepo = preload("res://src/persistence/save_repository.gd")
const Legacy = preload("res://src/domain/snapshot_format.gd")
const Rules = preload("res://src/domain/value_rules.gd")
const Catalog = preload("res://src/content/catalog_loader.gd")
const Session = preload("res://src/domain/game_session.gd")
const Fixture = preload("res://tests/fixtures/foundation_state.gd")
var checks: int = 0
var failures: int = 0
var defs: Dictionary
var directory: String = "user://zt_rebuild/checkpoint_tests_" + str(Time.get_ticks_usec())

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func fresh() -> RefCounted:
	var s := Session.new()
	return s if s.initialize(defs, Fixture.make()) else null

func tick(id: String, revision: int, minutes: int = 1) -> Dictionary:
	return {"action_id": id, "expected_revision": revision, "type": "advance_time", "payload": {"minutes": minutes}}

func put(path: String, data: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(data)
	file.close()

func reseal(row: Dictionary) -> String:
	row.checksum = Rules.canonical(row.body).sha256_text()
	return Rules.canonical(row)

func _initialize() -> void:
	var catalog: Dictionary = Catalog.load_file("res://data/catalog/foundation.json")
	defs = catalog.definitions
	var source: RefCounted = fresh()
	var legacy := LegacyRepo.new(directory)
	var repo := Repo.new(directory)
	check(legacy.save_session(source, "slot").ok, "legacy first generation")
	var checkpoint: Dictionary = source.snapshot()
	var commands: Array = [tick("first", 0), tick("second", 1)]
	for command: Dictionary in commands:
		check(source.execute(command).ok, "actual authority mutation")
	var final: Dictionary = source.snapshot()
	check(legacy.save_session(source, "slot").ok, "legacy latest generation")
	var a_path: String = directory.path_join("slot.a.json")
	var b_path: String = directory.path_join("slot.b.json")
	var a_bytes: PackedByteArray = FileAccess.get_file_as_bytes(a_path)
	var b_bytes: PackedByteArray = FileAccess.get_file_as_bytes(b_path)
	var old: RefCounted = fresh()
	check(legacy.load_session(old, "slot").ok and old.snapshot() == final, "validated legacy source")
	var encoded: String = Format.encode("slot", checkpoint, commands, final)
	check(Format.decode(encoded, "slot", fresh).get("state") == final, "checkpoint tail exact replay")
	check(Format.decode(encoded, "other", fresh).get("error") == "checksum_or_shape", "slot binding")
	var envelope: Dictionary = JSON.parse_string(encoded)
	envelope.body.journal[0].payload.minutes = 2
	check(not Format.decode(Rules.canonical(envelope), "slot", fresh).ok, "body checksum rejects mutation")
	check(Format.decode(reseal(envelope), "slot", fresh).get("error") == "terminal_mismatch", "valid command with changed outcome rejected")
	envelope = JSON.parse_string(encoded)
	envelope.body.journal[1] = envelope.body.journal[0].duplicate(true)
	check(Format.decode(reseal(envelope), "slot", fresh).get("error") == "journal_command", "duplicate or reordered tail rejected")
	envelope = JSON.parse_string(encoded)
	envelope.body.checkpoint.wallets.player.VKC = -1
	check(Format.decode(reseal(envelope), "slot", fresh).get("error") == "checkpoint_invalid", "invalid checkpoint denied")
	check(repo.save("slot", old.snapshot(), [], final, fresh).ok, "legacy import into separate v4 generation")
	check(FileAccess.get_file_as_bytes(a_path) == a_bytes and FileAccess.get_file_as_bytes(b_path) == b_bytes, "original legacy bytes preserved")
	var recent: Dictionary = tick("third", 2)
	check(source.execute(recent).ok, "next actual command")
	var next: Dictionary = source.snapshot()
	check(repo.save("slot", final, [recent], next, fresh).ok and repo.load_state("slot", fresh).state == next, "second independent generation and replay")
	var third: RefCounted = fresh()
	check(third.restore(repo.load_state("slot", fresh).state) and third.execute(recent).ok and third.snapshot() == next, "idempotence on restored state")
	check(repo.save("slot", final, [], final, fresh).get("error") == "revision_regression", "stale write rejected")
	var branch: RefCounted = fresh()
	branch.restore(final)
	branch.execute(tick("alternate", 2, 2))
	check(repo.save("slot", final, [tick("alternate", 2, 2)], branch.snapshot(), fresh).get("error") == "revision_conflict", "same revision conflicting branch rejected")
	check(branch.execute(tick("alternate_next", 3)).ok, "independently valid newer fork")
	var divergent: Dictionary = branch.snapshot()
	check(repo.save("slot", divergent, [], divergent, fresh).get("error") == "history_conflict", "higher revision cannot replace receipt history")
	var v4b: String = directory.path_join("slot.v4.b.json")
	var valid_b: String = FileAccess.get_file_as_string(v4b)
	put(v4b + ".tmp", "interrupted")
	check(repo.load_state("slot", fresh).state == next, "unfinished temporary ignored")
	put(v4b, "corrupt")
	var recovery: Dictionary = repo.load_state("slot", fresh)
	check(recovery.get("recovered", false) and recovery.state == final, "fallback to prior generation")
	check(repo.save("slot", final, [recent], next, fresh).ok, "repair damaged generation")
	envelope = JSON.parse_string(valid_b)
	envelope.body.schema_version = 99
	put(v4b, reseal(envelope))
	check(repo.load_state("slot", fresh).get("error") == "future_schema" and repo.save("slot", next, [], next, fresh).get("error") == "future_schema", "future format not overwritten")
	put(v4b, valid_b)
	var v4a: String = directory.path_join("slot.v4.a.json")
	var valid_a: String = FileAccess.get_file_as_string(v4a)
	put(v4a, Format.encode("slot", divergent, [], divergent))
	check(repo.load_state("slot", fresh).get("error") == "history_conflict", "two valid divergent generations must fail closed")
	put(v4a, valid_a)
	check(source.execute(tick("fourth", 3)).ok, "rollover mutation")
	var rolled: Dictionary = source.snapshot()
	check(repo.save("slot", rolled, [], rolled, fresh).ok and repo.load_state("slot", fresh).state == rolled, "roll forward checkpoint without journal deletion of receipts")
	var oversize: Array = []
	oversize.resize(17)
	check(Format.encode("slot", rolled, oversize, rolled).is_empty(), "bounded journal refused")
	var huge: Dictionary = rolled.duplicate(true)
	huge["padding"] = "x".repeat(Format.MAX_BYTES)
	check(Format.encode("slot", huge, [], huge).is_empty(), "oversize envelope refused")
	check(FileAccess.get_file_as_bytes(a_path) == a_bytes and FileAccess.get_file_as_bytes(b_path) == b_bytes, "legacy still byte-identical after recovery and rollover")
	print("ZT_CHECKPOINT_SAMPLE ", JSON.stringify({"legacy_bytes": Legacy.encoded_size(rolled), "v4_checkpoint_bytes": Format.encode("s".repeat(64), rolled, [], rolled).to_utf8_buffer().size(), "v4_tail_bytes": Format.encode("s".repeat(64), final, [recent], next).to_utf8_buffer().size(), "revision": rolled.revision}))
	var dir := DirAccess.open(directory)
	for name: String in dir.get_files():
		dir.remove(name)
	DirAccess.remove_absolute(directory)
	print("CHECKPOINT_PILOT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
