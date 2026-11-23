extends SceneTree
## Preserve randomized campaign seed across empty first-run and two A/B saves.
const Authority = preload("res://src/content/alpha_b3_seed_authority.gd")
const Source = preload("res://src/content/alpha_b3_random_runtime_seed.gd")
const Session = preload("res://src/domain/game_session.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
const SLOT: String = "b3_m5_authority"
var checks: int = 0
var failures: int = 0

func check(ok: bool, name: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", name)
	return ok

func fresh(seed: int) -> RefCounted:
	var src: Dictionary = Source.content(seed)
	var s := Session.new()
	if src.is_empty() or not s.initialize(src.defs, src.state, false, false, {}, src.alpha_profile):
		printerr("AUTHORITY_INIT ", s.initialization_error())
		return null
	return s

func done() -> void:
	print("ALPHA_B3_SEED_AUTHORITY_CHECKS=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

func _initialize() -> void:
	var folder: String = "user://zt_rebuild/m5_seed_authority_" + str(Time.get_ticks_usec())
	var repo := Repo.new(folder)
	var new_seed: Dictionary = Authority.select_seed(folder, SLOT)
	if not check(new_seed.get("ok", false) and new_seed.get("new", false)
			and int(new_seed.get("seed", 0)) > 0,
			"fresh installation chooses one positive seed, no file yet"):
		done()
		return
	var s: RefCounted = fresh(int(new_seed.seed))
	if not check(s != null, "valid M5 session binds selected seed"):
		done()
		return
	var initial: Dictionary = s.snapshot()
	check(repo.save_session(s, SLOT).get("ok", false),
		"new campaign persists its immutable initial seed before the first action")
	var existing: Dictionary = Authority.select_seed(folder, SLOT)
	check(existing.get("ok", false) and not existing.get("new", true)
		and existing.get("seed", -1) == new_seed.seed,
		"reboot reuses the saved original seed, never draws a second seed")
	var cold: RefCounted = fresh(int(existing.seed))
	check(cold != null and repo.load_session(cold, SLOT).get("ok", false)
		and cold.snapshot() == initial,
		"exact initial A generation validates by strict replay on cold load")
	var command: Dictionary = {"action_id": "m5_auth_open", "expected_revision": 0,
		"type": "alpha_open", "payload": {}}
	check(s.execute(command).get("ok", false), "real day one seeded opening")
	check(repo.save_session(s, SLOT).get("ok", false),
		"day-one plan stored in independent second B generation")
	var after_open: Dictionary = s.snapshot()
	check(Authority.select_seed(folder, SLOT).get("seed", 0) == new_seed.seed,
		"same seed persists across both A/B generations")
	var wrong: RefCounted = fresh(101 if int(new_seed.seed) != 101 else 197)
	check(wrong != null and not repo.load_session(wrong, SLOT).get("ok", false),
		"new unrelated campaign seed cannot load prior A/B save")
	cold = fresh(int(existing.seed))
	check(cold != null and repo.load_session(cold, SLOT).get("ok", false)
		and cold.snapshot() == after_open,
		"correct seed reconstructs exact cached visit plan and receipts")
	var file: String = folder.path_join(SLOT + ".a.json")
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f != null:
		f.store_string("{corrupt")
		f.close()
	var recovered: Dictionary = Authority.select_seed(folder, SLOT)
	check(recovered.get("ok", false) and recovered.get("seed", 0) == new_seed.seed,
		"valid B seed may be recovered despite corrupted A")
	cold = fresh(int(new_seed.seed))
	check(cold != null and repo.load_session(cold, SLOT).get("ok", false)
		and cold.snapshot() == after_open,
		"save repository A/B recovery keeps source economy and day plan")
	file = folder.path_join(SLOT + ".b.json")
	f = FileAccess.open(file, FileAccess.WRITE)
	if f != null:
		f.store_string("{corrupt")
		f.close()
	check(not Authority.select_seed(folder, SLOT).get("ok", false),
		"both corrupted saves fail closed; never reset to a new random campaign")
	done()
