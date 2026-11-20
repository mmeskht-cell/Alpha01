extends RefCounted
## Isolated storage-generation CAS for registry pilot. Never writes v3/v4 slots.
## Single writer only. Separate storage revision allows metadata-only updates.
const Rules = preload("res://src/domain/value_rules.gd")
const Codec = preload("res://src/persistence/registry_pilot_format.gd")
const Checkpoint = preload("res://src/persistence/checkpoint_format.gd")
const CheckpointRepo = preload("res://src/persistence/checkpoint_repository.gd")
const Registry = preload("res://src/domain/dormant_registry.gd")
const Tracking = preload("res://src/domain/selective_tracking.gd")
const Max = preload("res://src/domain/snapshot_format.gd")
const CONTRACT: String = "registry-ab-pilot-1"
var _root: String
var _binding: String

func _init(root: String, binding: String = "") -> void:
	_root = root
	_binding = binding

func _contract() -> String:
	return CONTRACT if _binding.is_empty() else "registry-ab-runtime-1"

func _contract_v2() -> String:
	return _contract().trim_suffix("-1") + "-2"

## New generations persist the bounded transition proof alongside the same
## complete detached partition. Old v1 saves remain readable; no file rewrite
## happens during read. The first v2 commit may descend from a valid v1 record.
func _transition_shape(value: Variant, storage_revision: int) -> bool:
	if value == null:
		return storage_revision == 1
	if not Rules.keys(value, ["parent_revision", "parent_digest", "journal"]) or not Rules.integer(value.parent_revision, 1) or value.parent_revision != storage_revision - 1 or not value.parent_digest is String or value.parent_digest.length() != 64 or not value.journal is Array or value.journal.size() > Checkpoint.MAX_JOURNAL:
		return false
	for character: String in value.parent_digest:
		if character not in "0123456789abcdef":
			return false
	for command: Variant in value.journal:
		if not Rules.keys(command, ["action_id", "expected_revision", "type", "payload"]) or not Rules.identifier(command.action_id) or not Rules.integer(command.expected_revision) or not command.type is String or not command.payload is Dictionary or Rules.canonical(command).to_utf8_buffer().size() > Checkpoint.MAX_COMMAND_BYTES:
			return false
	return true

func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code}

func _path(slot: String, generation: String) -> String:
	return _root.path_join(slot + ".registry." + generation + ".json")

func _read(path: String, slot: String, factory: Callable) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _error("missing")
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > Max.MAX_BYTES:
		return _error("save_io")
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK or not Rules.keys(json.data, ["body", "checksum"]):
		return _error("save_shape")
	var env: Dictionary = Rules.normalized(json.data)
	var b: Variant = env.body
	if not b is Dictionary or not b.get("contract") is String:
		return _error("save_shape")
	if b.contract not in [_contract(), _contract_v2()]:
		return _error("unsupported_contract")
	var modern: bool = b.contract == _contract_v2()
	var fields: Array = ["contract", "slot", "storage_revision", "registry"]
	if modern:
		fields.append("transition")
	if not _binding.is_empty():
		fields.append("binding")
		if b.get("binding") != _binding:
			return _error("binding_mismatch")
	if not Rules.keys(b, fields) or b.slot != slot or not Rules.integer(b.storage_revision, 1) or not b.registry is Dictionary or env.checksum != Rules.canonical(b).sha256_text():
		return _error("checksum_or_shape")
	if modern and not _transition_shape(b.transition, int(b.storage_revision)):
		return _error("transition_shape")
	var authority: RefCounted = factory.call()
	if authority == null:
		return _error("authority_unavailable")
	var decoded: Dictionary = Codec.unpack(Rules.canonical(b.registry), authority, authority.snapshot())
	if decoded.is_empty():
		return _error("invalid_registry")
	return {"ok": true, "storage_revision": b.storage_revision, "state": decoded.state, "partition": decoded.partition, "modern": modern, "transition": b.get("transition"), "digest": Rules.canonical(b).sha256_text()}

func load_state(slot: String, factory: Callable) -> Dictionary:
	if not Rules.identifier(slot):
		return _error("slot_id")
	var a: Dictionary = _read(_path(slot, "a"), slot, factory)
	var b: Dictionary = _read(_path(slot, "b"), slot, factory)
	for row: Dictionary in [a, b]:
		if row.get("error") in ["unsupported_contract", "binding_mismatch"]:
			return row
	var av: bool = a.get("ok", false)
	var bv: bool = b.get("ok", false)
	if not av and not bv:
		return _error("missing" if a.get("error") == "missing" and b.get("error") == "missing" else "no_valid_save")
	if av and bv and a.storage_revision == b.storage_revision and a.partition != b.partition:
		return _error("storage_conflict")
	var use_a: bool = av and (not bv or a.storage_revision >= b.storage_revision)
	var r: Dictionary = a if use_a else b
	if av and bv and a.storage_revision != b.storage_revision:
		var prior: Dictionary = b if use_a else a
		if not _pair_valid(prior, r, slot, factory):
			return _error("history_conflict")
	r["generation"] = "a" if use_a else "b"
	r["recovered"] = (not av and a.get("error") != "missing") or (not bv and b.get("error") != "missing")
	return r

## Both generations are independently decoded before this check. A single
## valid survivor remains recoverable; two valid but divergent saves fail closed.
## For old v1 pairs, retain backward compatibility using identity prefix and
## retention; for v2, replay the exact bounded journal from the older state.
func _pair_valid(prior: Dictionary, later: Dictionary, slot: String, factory: Callable) -> bool:
	if not CheckpointRepo._prefix(prior.state, later.state) or not _retention(prior.partition, later.partition, later.state):
		return false
	if prior.modern and not later.modern:
		return false
	if not later.modern:
		return true
	var link: Variant = later.transition
	if not link is Dictionary or link.parent_revision != prior.storage_revision or link.parent_digest != prior.digest:
		return false
	var proof: String = Checkpoint.encode(slot, prior.state, link.journal, later.state)
	var decoded: Dictionary = Checkpoint.decode(proof, slot, factory)
	return decoded.get("ok", false) and decoded.state == later.state

## Track retention cannot be bypassed by replacing the whole partition.
func _retention(previous: Dictionary, candidate: Dictionary, full: Dictionary) -> bool:
	for id: String in previous.tracking:
		var old: Dictionary = previous.tracking[id]
		if not candidate.tracking.has(id):
			return false
		var new: Dictionary = candidate.tracking[id]
		if old.pinned and (not new.pinned or not new.enabled or old.tier != new.tier):
			return false
		if old.enabled and not new.enabled and not Tracking.can_suspend(full, id):
			return false
		for reference: String in old.refs:
			if reference not in new.refs:
				return false
	return true

## First import is explicit and requires validated source. Later writes compare
## storage revision and prove gameplay continuity through the existing authority.
## Retained metadata is monotonic; actual selection permission remains caller's
## responsibility. No production migration or in-place replacement.
func save(slot: String, partition: Dictionary, expected_storage_revision: int, journal: Array, factory: Callable) -> Dictionary:
	if not Rules.identifier(slot) or expected_storage_revision < 0:
		return _error("slot_or_revision")
	var authority: RefCounted = factory.call()
	if authority == null:
		return _error("authority_unavailable")
	var packed: String = Codec.pack(partition, authority, authority.snapshot())
	if packed.is_empty():
		return _error("candidate_invalid")
	var decoded: Dictionary = Codec.unpack(packed, authority, authority.snapshot())
	if decoded.is_empty():
		return _error("candidate_invalid")
	var latest: Dictionary = load_state(slot, factory)
	if not latest.get("ok", false) and latest.get("error") != "missing":
		return latest
	if latest.get("ok", false):
		if latest.storage_revision != expected_storage_revision:
			return _error("stale_storage")
		var proof: String = Checkpoint.encode(slot, latest.state, journal, decoded.state)
		var verified: Dictionary = Checkpoint.decode(proof, slot, factory)
		if not verified.get("ok", false) or verified.state != decoded.state or not _retention(latest.partition, partition, decoded.state):
			return _error("continuity_or_retention")
		if latest.partition == partition:
			return {"ok": true, "unchanged": true, "storage_revision": expected_storage_revision}
	elif expected_storage_revision != 0 or not journal.is_empty():
		return _error("initial_import")
	var next: int = expected_storage_revision + 1
	var transition: Variant = null
	if latest.get("ok", false):
		transition = {"parent_revision": latest.storage_revision, "parent_digest": latest.digest, "journal": Rules.normalized(journal)}
	var body: Dictionary = {"contract": _contract_v2(), "slot": slot, "storage_revision": next, "registry": JSON.parse_string(packed), "transition": transition}
	if not _binding.is_empty():
		body["binding"] = _binding
	var encoded: String = Rules.canonical({"body": body, "checksum": Rules.canonical(body).sha256_text()})
	if encoded.to_utf8_buffer().size() > Max.MAX_BYTES:
		return _error("save_size")
	if DirAccess.make_dir_recursive_absolute(_root) != OK:
		return _error("save_directory")
	var gen: String = "b" if latest.get("generation") == "a" else "a"
	var destination: String = _path(slot, gen)
	var tmp: String = destination + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return _error("save_open")
	f.store_string(encoded)
	f.flush()
	var err: Error = f.get_error()
	f.close()
	if err != OK:
		return _error("save_write")
	var reread: Dictionary = _read(tmp, slot, factory)
	if not reread.get("ok", false) or reread.partition != partition or reread.storage_revision != next or (latest.get("ok", false) and not _pair_valid(latest, reread, slot, factory)):
		return _error("save_verify")
	if DirAccess.rename_absolute(tmp, destination) != OK:
		return _error("save_rename")
	if FileAccess.get_file_as_bytes(destination) != encoded.to_utf8_buffer():
		return _error("save_final_verify")
	return {"ok": true, "generation": gen, "storage_revision": next, "revision": decoded.state.revision}
