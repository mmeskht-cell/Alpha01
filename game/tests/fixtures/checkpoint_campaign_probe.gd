extends RefCounted
## Test-only factory: independently reconstruct exact approved session mode.
const Session = preload("res://src/domain/game_session.gd")
const Catalog = preload("res://src/content/catalog_loader.gd")
const Opening = preload("res://src/domain/gate1_opening.gd")
const DayOne = preload("res://src/domain/day_one.gd")
const Documents = preload("res://src/content/packaged_documents.gd")
const Legacy = preload("res://src/persistence/save_repository.gd")
const Format = preload("res://src/persistence/checkpoint_format.gd")
const Repo = preload("res://src/persistence/checkpoint_repository.gd")
const V3 = preload("res://src/domain/snapshot_format.gd")

static func session(pilot: bool) -> RefCounted:
	var path: String = "res://data/campaign/gate1_day_one/composite_pilot_catalog.json" if pilot else "res://data/campaign/gate1_day_one/catalog.json"
	var definitions: Dictionary = Catalog.load_file(path)
	if not definitions.get("ok", false):
		return null
	var initial: Dictionary = Opening.seed(Documents.read_object("res://data/campaign/gate1_1/scenario.json"))
	if initial.is_empty():
		return null
	initial["day_one"] = DayOne.marker()
	var result := Session.new()
	return result if result.initialize(definitions.definitions, initial, pilot) else null

static func probe(directory: String, pilot: bool, expected: Dictionary) -> Dictionary:
	var slot: String = "gate1_composite_pilot_v3" if pilot else "gate1_day_one_v3"
	var before: Array = []
	for generation: String in ["a", "b"]:
		before.append(FileAccess.get_file_as_bytes(directory.path_join(slot + "." + generation + ".json")))
	var source: RefCounted = session(pilot)
	var legacy := Legacy.new(directory)
	if source == null or not legacy.load_session(source, slot).get("ok", false) or source.snapshot() != expected:
		return {"ok": false, "stage": "legacy_read"}
	var factory: Callable = func() -> RefCounted: return session(pilot)
	var repository := Repo.new(directory)
	var saved: Dictionary = repository.save(slot, source.snapshot(), [], expected, factory)
	var loaded: Dictionary = repository.load_state(slot, factory)
	var equal: bool = saved.get("ok", false) and loaded.get("ok", false) and loaded.state == expected
	var unchanged: bool = true
	for i: int in range(2):
		var generation: String = ["a", "b"][i]
		unchanged = unchanged and FileAccess.get_file_as_bytes(directory.path_join(slot + "." + generation + ".json")) == before[i]
	# Measure the same worst-case slot id, not different names or revisions.
	var v4_bytes: int = Format.encode("s".repeat(64), expected, [], expected).to_utf8_buffer().size()
	var result: Dictionary = {"ok": equal and unchanged, "exact": equal, "legacy_unchanged": unchanged, "legacy_bytes": V3.encoded_size(expected), "v4_bytes": v4_bytes, "revision": expected.revision, "pilot": pilot}
	DirAccess.remove_absolute(directory.path_join(slot + ".v4.a.json"))
	DirAccess.remove_absolute(directory.path_join(slot + ".v4.b.json"))
	return result
