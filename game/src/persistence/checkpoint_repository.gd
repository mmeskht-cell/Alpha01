extends RefCounted
## Opt-in experimental A/B repository. Never reads/writes schema3 filenames.
## Same-directory temp + verified rename; no durability claim across power loss.
const Format = preload("res://src/persistence/checkpoint_format.gd")
const Rules = preload("res://src/domain/value_rules.gd")
var _root: String

func _init(root: String) -> void:
	_root = root

func _path(slot: String, generation: String) -> String:
	return _root.path_join(slot + ".v4." + generation + ".json")

func _read(path: String, slot: String, factory: Callable) -> Dictionary:
	if not FileAccess.file_exists(path):
		return Format.error("missing")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > Format.MAX_BYTES:
		return Format.error("save_io")
	return Format.decode(file.get_as_text(), slot, factory)

## Compare validated receipts across full/compact representations. Immutable
## domain history is also checked in lifecycle mode. This rules out divergent
## branches with higher revisions; it is not cryptographic authentication.
static func _identity(state: Dictionary, id: String) -> Array:
	if state.receipts.has(id):
		var row: Dictionary = state.receipts[id]
		var command: Dictionary = JSON.parse_string(row.fingerprint)
		return [row.fingerprint.sha256_text(), int(row.result.revision), command.type]
	if state.receipt_archive.has(id):
		return state.receipt_archive[id].slice(0, 3)
	return []

static func _prefix(previous: Dictionary, next: Dictionary) -> bool:
	if int(next.revision) < int(previous.revision) or next.has("lifecycle") != previous.has("lifecycle"):
		return false
	for table: Dictionary in [previous.receipts, previous.receipt_archive]:
		for id: String in table:
			if Rules.canonical(_identity(previous, id)) != Rules.canonical(_identity(next, id)):
				return false
	if previous.has("lifecycle"):
		if previous.lifecycle.seed_hash != next.lifecycle.seed_hash:
			return false
		for key: String in ["ledger", "object_events"]:
			if next[key].size() < previous[key].size() or Rules.canonical(next[key].slice(0, previous[key].size())) != Rules.canonical(previous[key]):
				return false
		if next.lifecycle.events.size() < previous.lifecycle.events.size() or Rules.canonical(next.lifecycle.events.slice(0, previous.lifecycle.events.size())) != Rules.canonical(previous.lifecycle.events):
			return false
		for key: String in ["knowledge", "tombstones"]:
			for id: String in previous[key]:
				if not next[key].has(id) or Rules.canonical(next[key][id]) != Rules.canonical(previous[key][id]):
					return false
	return true

func _select(slot: String, factory: Callable) -> Dictionary:
	if not Rules.identifier(slot):
		return Format.error("slot_id")
	var a: Dictionary = _read(_path(slot, "a"), slot, factory)
	var b: Dictionary = _read(_path(slot, "b"), slot, factory)
	for row: Dictionary in [a, b]:
		if row.get("error") in ["future_schema", "unsupported_schema", "content_version"]:
			return row
	var a_ok: bool = a.get("ok", false)
	var b_ok: bool = b.get("ok", false)
	if not a_ok and not b_ok:
		return Format.error("missing" if a.get("error") == "missing" and b.get("error") == "missing" else "no_valid_save")
	if a_ok and b_ok and a.state.revision == b.state.revision and a.state != b.state:
		return Format.error("revision_conflict")
	var choose_a: bool = a_ok and (not b_ok or a.state.revision >= b.state.revision)
	if a_ok and b_ok and not _prefix(b.state if choose_a else a.state, a.state if choose_a else b.state):
		return Format.error("history_conflict")
	var selected: Dictionary = a if choose_a else b
	selected["generation"] = "a" if choose_a else "b"
	selected["recovered"] = (not a_ok and a.get("error") != "missing") or (not b_ok and b.get("error") != "missing")
	return selected

func load_state(slot: String, factory: Callable) -> Dictionary:
	return _select(slot, factory)

## A checkpoint may be the complete validated legacy state. Rolling it forward
## changes only the envelope; legacy replay remains intact until a new domain
## validator exists. No deletion of ledger, receipts, protected facts or IDs.
func save(slot: String, checkpoint: Dictionary, journal: Array, expected: Dictionary, factory: Callable) -> Dictionary:
	if not Rules.identifier(slot):
		return Format.error("slot_id")
	var encoded: String = Format.encode(slot, checkpoint, journal, expected)
	if encoded.is_empty():
		return Format.error("save_size_or_journal")
	var checked: Dictionary = Format.decode(encoded, slot, factory)
	if not checked.get("ok", false) or checked.state != expected:
		return Format.error("candidate_invalid")
	var latest: Dictionary = _select(slot, factory)
	if not latest.get("ok", false) and latest.get("error") != "missing":
		return latest
	if latest.get("ok", false):
		if checked.state.revision < latest.state.revision:
			return Format.error("revision_regression")
		if checked.state.revision == latest.state.revision:
			return {"ok": true, "unchanged": true} if checked.state == latest.state else Format.error("revision_conflict")
		if not _prefix(latest.state, checked.state):
			return Format.error("history_conflict")
		if int(checkpoint.revision) == int(latest.state.revision) and checkpoint != latest.state:
			return Format.error("checkpoint_conflict")
	if DirAccess.make_dir_recursive_absolute(_root) != OK:
		return Format.error("save_directory")
	var generation: String = "b" if latest.get("generation") == "a" else "a"
	var destination: String = _path(slot, generation)
	var temporary: String = destination + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return Format.error("save_open")
	file.store_string(encoded)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return Format.error("save_write")
	var readback: Dictionary = _read(temporary, slot, factory)
	if not readback.get("ok", false) or readback.state != expected:
		return Format.error("save_verify")
	if DirAccess.rename_absolute(temporary, destination) != OK:
		return Format.error("save_rename")
	if FileAccess.get_file_as_bytes(destination) != encoded.to_utf8_buffer():
		return Format.error("save_final_verify")
	return {"ok": true, "generation": generation, "revision": expected.revision, "bytes": encoded.to_utf8_buffer().size()}
