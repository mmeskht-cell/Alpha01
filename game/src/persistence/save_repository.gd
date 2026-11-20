extends RefCounted
## Two generations. Payload checksum detects accidental corruption, not malicious edits.
const Rules = preload("res://src/domain/value_rules.gd")
const SnapshotFormat = preload("res://src/domain/snapshot_format.gd")
const SCHEMA_VERSION: int = SnapshotFormat.SCHEMA_VERSION
const CONTENT_VERSION: String = "0.1.0"
const MAX_BYTES: int = SnapshotFormat.MAX_BYTES
var _root: String

func _init(root: String = "user://zt_rebuild/saves") -> void:
	_root = root

func _migration_active(slot: String) -> bool:
	return FileAccess.file_exists(_root.path_join(slot + ".registry.active"))

func save_session(session: RefCounted, slot: String) -> Dictionary:
	if not Rules.identifier(slot):
		return _error("slot_id")
	if _migration_active(slot):
		return _error("registry_active")
	if DirAccess.make_dir_recursive_absolute(_root) != OK:
		return _error("save_directory")
	var candidate: Dictionary = session.snapshot()
	if candidate.has("lifecycle") or candidate.get("calendar",{}).has("dormant"):
		return _error("lifecycle_requires_checkpoint")
	if not session.validate(candidate):
		return _error("save_state")
	var a: Dictionary = _read(slot, "a", session)
	var b: Dictionary = _read(slot, "b", session)
	if a.get("error") == "future_schema" or b.get("error") == "future_schema":
		return _error("future_schema")
	if a.get("error") == "unsupported_schema" or b.get("error") == "unsupported_schema":
		return _error("unsupported_schema")
	if a.get("error") == "content_version" or b.get("error") == "content_version":
		return _error("content_version")
	if a.get("ok", false) and b.get("ok", false) and a.state.revision == b.state.revision and Rules.canonical(a.state) != Rules.canonical(b.state):
		return _error("revision_conflict")
	var latest: Dictionary = _latest(a, b)
	# Never replace the only remaining forensic copies if neither generation is valid.
	if not latest.get("ok", false) and (a.get("error") != "missing" or b.get("error") != "missing"):
		return _error("no_valid_save")
	if latest.get("ok", false):
		if candidate.revision < latest.state.revision:
			return _error("revision_regression")
		if candidate.revision == latest.state.revision:
			if Rules.canonical(candidate) != Rules.canonical(latest.state):
				return _error("revision_conflict")
			return {"ok": true, "revision": candidate.revision, "unchanged": true}
	var generation: String = "a"
	if a.get("ok", false) and (not b.get("ok", false) or a.state.revision >= b.state.revision):
		generation = "b"
	var payload: String = Rules.canonical(candidate)
	var encoded: String = SnapshotFormat.encode(candidate, slot)
	if encoded.to_utf8_buffer().size() > MAX_BYTES:
		return _error("save_size")
	var destination: String = _path(slot, generation)
	var temporary: String = destination + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _error("save_open")
	file.store_string(encoded)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return _error("save_write")
	var checked: Dictionary = _read_path(temporary, slot, session)
	if not checked.ok or Rules.canonical(checked.state) != payload:
		return _error("save_verify")
	if DirAccess.rename_absolute(temporary, destination) != OK:
		return _error("save_rename")
	# The temporary generation was read, parsed, checksummed and validated above.
	# After rename, full byte equality to the encoded validated state proves that
	# the destination is identical. Do not replay the same state a second time.
	if not _matches_bytes(destination, encoded.to_utf8_buffer()):
		return _error("save_final_verify")
	return {"ok": true, "revision": candidate.revision, "generation": generation}

func load_session(session: RefCounted, slot: String) -> Dictionary:
	if not Rules.identifier(slot):
		return _error("slot_id")
	if _migration_active(slot):
		return _error("registry_active")
	var a: Dictionary = _read(slot, "a", session)
	var b: Dictionary = _read(slot, "b", session)
	for record: Dictionary in [a, b]:
		if record.get("error") in ["future_schema", "content_version", "unsupported_schema"]:
			return record
	var latest: Dictionary = _latest(a, b)
	if not latest.get("ok", false):
		return _error("no_valid_save")
	if a.get("ok", false) and b.get("ok", false) and a.state.revision == b.state.revision and Rules.canonical(a.state) != Rules.canonical(b.state):
		return _error("revision_conflict")
	if not session.restore(latest.state):
		return _error("restore_rejected")
	return {"ok": true, "revision": latest.state.revision, "recovered": (a.get("error", "") != "missing" and not a.get("ok", false)) or (b.get("error", "") != "missing" and not b.get("ok", false))}

func _read(slot: String, generation: String, session: RefCounted) -> Dictionary:
	return _read_path(_path(slot, generation), slot, session)

func _read_path(path: String, slot: String, session: RefCounted) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _error("missing")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return _error("save_io")
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return _error("save_json")
	var envelope: Variant = json.data
	if not envelope is Dictionary or not Rules.integer(envelope.get("schema_version"), 1):
		return _error("save_shape")
	if envelope.schema_version > SCHEMA_VERSION:
		return _error("future_schema")
	if not Rules.keys(envelope, ["schema_version", "content_version", "slot_id", "revision", "payload", "checksum"]):
		return _error("save_shape")
	if envelope.content_version != CONTENT_VERSION:
		return _error("content_version")
	if envelope.slot_id != slot or not Rules.integer(envelope.revision) or not envelope.payload is String or not envelope.checksum is String:
		return _error("save_shape")
	if envelope.payload.sha256_text() != envelope.checksum:
		return _error("checksum")
	if envelope.schema_version < SCHEMA_VERSION:
		return _error("unsupported_schema")
	if json.parse(envelope.payload) != OK or not json.data is Dictionary:
		return _error("payload_json")
	var state: Dictionary = Rules.normalized(json.data)
	if state.has("lifecycle") or (state.get("calendar") is Dictionary and state.calendar.has("dormant")):
		return _error("unsupported_schema")
	if not session.validate(state) or state.revision != envelope.revision:
		return _error("save_state")
	return {"ok": true, "state": state}

## No across-action cache. Re-read final disk bytes, including size; invalid or
## unreadable file fails closed. Only used immediately after validated temp rename.
func _matches_bytes(path: String, expected: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or expected.size() > MAX_BYTES or file.get_length() != expected.size():
		return false
	return file.get_buffer(expected.size()) == expected

func _latest(a: Dictionary, b: Dictionary) -> Dictionary:
	if a.get("ok", false) and b.get("ok", false):
		return a if a.state.revision >= b.state.revision else b
	return a if a.get("ok", false) else b

func _path(slot: String, generation: String) -> String:
	return _root.path_join(slot + "." + generation + ".json")

func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code}
