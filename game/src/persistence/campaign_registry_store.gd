extends RefCounted
## Runtime adapter for the existing day-one authority. No live L2 promotion.
## One writer; v3 generations are a frozen read-only migration source.
const Rules = preload("res://src/domain/value_rules.gd")
const Legacy = preload("res://src/persistence/save_repository.gd")
const Repo = preload("res://src/persistence/registry_pilot_repository.gd")
const Registry = preload("res://src/domain/dormant_registry.gd")
const ObjectSchema = preload("res://src/domain/object_schema.gd")
var _root: String
var _slot: String
var _factory: Callable
var _repo: RefCounted
var _binding: String
var _legacy_anchor: String
var _revision: int = 0
var _last: Dictionary = {}
var _pending: Dictionary = {}

func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code}

func _anchor() -> String:
	var hashes: Array = []
	for gen: String in ["a", "b"]:
		var path: String = _root.path_join(_slot + "." + gen + ".json")
		hashes.append(FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing")
	return Rules.canonical(hashes).sha256_text()

func _marker() -> String:
	return _root.path_join(_slot + ".registry.active")

func _write_marker() -> bool:
	if FileAccess.file_exists(_marker()):
		return FileAccess.get_file_as_string(_marker()) == _binding
	var f := FileAccess.open(_marker() + ".tmp", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(_binding)
	f.flush()
	var err: Error = f.get_error()
	f.close()
	return err == OK and FileAccess.get_file_as_string(_marker() + ".tmp") == _binding and DirAccess.rename_absolute(_marker() + ".tmp", _marker()) == OK and FileAccess.get_file_as_string(_marker()) == _binding

func _partition(full: Dictionary, session: RefCounted) -> Dictionary:
	var p: Dictionary = Registry.begin(full, session)
	if p.is_empty():
		return {}
	# Storage-only partition at evening or next day; the authority still sees
	# the full materialized state. No economic change or narrative promotion.
	if full.game_minutes >= 600:
		var roots: Array = full.items.keys()
		roots.sort()
		for id: String in roots:
			if full.items[id].parent_id.is_empty() and Registry.open_family(full, id):
				var next: Dictionary = Registry.sleep_family(p, id, session)
				if next.is_empty():
					return {}
				p = next
	return p

func _adopt(session: RefCounted, result: Dictionary) -> Dictionary:
	if not result.get("ok", false):
		return result
	if not result.partition.tracking.is_empty():
		return _error("tracking_not_enabled")
	if not session.restore(result.state):
		return _error("restore_rejected")
	_revision = int(result.storage_revision)
	_last = result.state.duplicate(true)
	_pending.clear()
	return {"ok": true, "revision": _last.revision, "recovered": result.get("recovered", false)}

func open(session: RefCounted, root: String, slot: String, factory: Callable, content_binding: String) -> Dictionary:
	_root = root
	_slot = slot
	_factory = factory
	_legacy_anchor = _anchor()
	_binding = Rules.canonical({"content": content_binding, "source": _legacy_anchor, "mode": "day-one-runtime-1"}).sha256_text()
	_repo = Repo.new(root, _binding)
	if FileAccess.file_exists(_marker()) and FileAccess.get_file_as_string(_marker()) != _binding:
		return _error("migration_binding")
	var latest: Dictionary = _repo.load_state(_slot, _factory)
	if latest.get("ok", false):
		if not _write_marker():
			return _error("migration_marker")
		return _adopt(session, latest)
	if latest.get("error") != "missing" or FileAccess.file_exists(_marker()):
		return _error("registry_missing" if latest.get("error") == "missing" else str(latest.error))
	var source: RefCounted = _factory.call()
	if source == null:
		return _error("authority_unavailable")
	var has_old: bool = FileAccess.file_exists(root.path_join(slot + ".a.json")) or FileAccess.file_exists(root.path_join(slot + ".b.json"))
	if has_old:
		var legacy := Legacy.new(root)
		var read: Dictionary = legacy.load_session(source, slot)
		if not read.ok:
			return read
	var p: Dictionary = _partition(source.snapshot(), source)
	var committed: Dictionary = _repo.save(slot, p, 0, [], _factory)
	if not committed.ok or _anchor() != _legacy_anchor:
		return _error("migration_import")
	var reread: Dictionary = _repo.load_state(slot, _factory)
	if not reread.get("ok", false) or reread.state != source.snapshot() or not _write_marker():
		return _error("migration_verify")
	return _adopt(session, reread)

func load_session(session: RefCounted, slot: String) -> Dictionary:
	if slot != _slot or _repo == null or _anchor() != _legacy_anchor or not FileAccess.file_exists(_marker()) or FileAccess.get_file_as_string(_marker()) != _binding:
		return _error("migration_binding")
	return _adopt(session, _repo.load_state(slot, _factory))

func remember(command: Dictionary) -> void:
	_pending = Rules.normalized(command)

func save_session(session: RefCounted, slot: String) -> Dictionary:
	if slot != _slot or _repo == null or _anchor() != _legacy_anchor or FileAccess.get_file_as_string(_marker()) != _binding:
		return _error("migration_binding")
	var full: Dictionary = session.snapshot()
	var p: Dictionary = _partition(full, session)
	if p.is_empty():
		return _error("registry_partition")
	var tail: Array = []
	if full != _last:
		if _pending.is_empty() or full.revision != _last.revision + 1:
			return _error("command_continuity")
		tail.append(_pending)
	var disk: Dictionary = _repo.load_state(slot, _factory)
	if not disk.get("ok", false):
		return disk
	# Retry after rename succeeded but caller observed a write/readback failure.
	if disk.storage_revision == _revision + 1 and disk.partition == p and not tail.is_empty():
		_revision = int(disk.storage_revision)
		_last = full
		_pending.clear()
		return {"ok": true, "revision": full.revision, "recovered_write": true}
	if disk.storage_revision != _revision or disk.state != _last:
		return _error("stale_storage")
	var saved: Dictionary = _repo.save(slot, p, _revision, tail, _factory)
	if saved.ok:
		_revision = int(saved.storage_revision)
		_last = full
		_pending.clear()
	return saved
