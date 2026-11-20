extends SceneTree
const Session = preload("res://src/domain/game_session.gd")
const Catalog = preload("res://src/content/catalog_loader.gd")
const Component = preload("res://src/domain/component_appraisal.gd")
const Format = preload("res://src/domain/snapshot_format.gd")
var s: RefCounted
var checks: int = 0
var failures: int = 0

func check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", name)

func command(kind: String, payload: Dictionary, id: String) -> Dictionary:
	return {"action_id": id, "expected_revision": s.snapshot().revision, "type": kind, "payload": payload}

func read(item: String, key: String, id: String) -> Dictionary:
	return s.execute(command("observe", {"actor": "player", "item_id": item, "key": key}, id))

func guess(item: String, material: String, id: String) -> Dictionary:
	return command("record_component_hypothesis", {"actor": "player", "item_id": item, "material_id": material, "condition_id": "visible_wear", "series_id": null}, id)

func _initialize() -> void:
	var catalog: Dictionary = Catalog.load_file("res://data/catalog/component_preview.json")
	s = Session.new()
	var ready: bool = catalog.ok and s.initialize(catalog.definitions, Component.seed())
	check(ready, "isolated fixture")
	if not ready:
		quit(1)
		return
	var before: Dictionary = s.snapshot()
	check(not read("D001_A", "component_damage", "hidden").ok and s.snapshot() == before, "hidden board requires detachment")
	check(read("D001_C", "component_texture", "antenna").ok and read("D001_B", "component_damage", "speaker").ok, "exposed attached regions")
	before = s.snapshot()
	check(not read("D001_B", "component_texture", "unsupported").ok and not read("D001_C", "component_function", "hidden_function").ok and s.snapshot() == before, "unsupported instrument and attached function refused")
	check(read("D001", "component_damage", "shell").ok and read("D001", "component_panel_damage", "display").ok and read("D001", "component_controls_damage", "controls").ok, "three independent regions")
	check(s.snapshot().knowledge.shell.observed_value == 43 and s.snapshot().knowledge.display.observed_value == 12 and s.snapshot().knowledge.controls.observed_value == 68, "region readings independent")
	check(not read("D001_C", "component_panel_damage", "forged_region").ok, "scope cannot be reassigned to wrong definition")
	var first_function: Dictionary = command("observe", {"actor": "player", "item_id": "D001", "key": "component_function"}, "first_function")
	check(s.execute(first_function).ok, "whole functional diagnosis")
	check(s.execute(command("detach", {"actor": "player", "root_id": "D001", "child_id": "D001_A", "inventory": "player_grid", "x": 0, "y": 3, "rotated": false}, "detach_board")).ok, "actual detachment")
	var observed: Dictionary = s.snapshot()
	check(read("D001", "component_function", "second_function").ok, "new functional revision")
	var compacted: Dictionary = s.snapshot()
	check(not compacted.knowledge.has("first_function") and compacted.knowledge.has("second_function") and compacted.receipt_archive.first_function[3] == ["second_function", "D001:component_function"], "newest functional evidence replaces stale detail")
	check(compacted.knowledge.display == observed.knowledge.display and compacted.knowledge.shell == observed.knowledge.shell, "unrelated observations unchanged")
	check(s.execute(first_function).ok and s.snapshot() == compacted, "superseded command exact replay, no mutation")
	check(read("D001", "component_panel_texture", "late_panel").ok, "later independent region for archive validation")
	var old_guess: Dictionary = guess("D001", "molded_polymer", "old_guess")
	check(s.execute(old_guess).ok, "first hypothesis")
	check(s.execute(guess("D001", "coated_steel", "middle_guess")).ok, "second hypothesis")
	check(s.execute(guess("D001", "light_alloy", "latest_guess")).ok, "third hypothesis")
	compacted = s.snapshot()
	check(compacted.component_hypotheses.size() == 1 and compacted.component_hypotheses.has("latest_guess"), "latest only")
	check(compacted.receipt_archive.old_guess[3] == ["latest_guess", "D001"] and compacted.receipt_archive.middle_guess[3] == ["latest_guess", "D001"], "direct rather than chained archive references")
	check(s.execute(old_guess).ok and s.snapshot() == compacted, "old guess replay is harmless")
	var tampered: Dictionary = old_guess.duplicate(true)
	tampered.payload.material_id = "coated_steel"
	check(not s.execute(tampered).ok and s.snapshot() == compacted, "action ID cannot be reused for different payload")
	var corrupted: Dictionary = compacted.duplicate(true)
	corrupted.receipt_archive.first_function[3][0] = "late_panel"
	check(not s.restore(corrupted) and s.snapshot() == compacted, "mismatched retention target refused")
	corrupted = compacted.duplicate(true)
	corrupted.receipt_archive.old_guess[3][0] = "middle_guess"
	check(not s.restore(corrupted) and s.snapshot() == compacted, "chained archive reference refused")
	check(s.restore(compacted) and s.snapshot() == compacted, "snapshot roundtrip with retention links")
	check(compacted.receipts.size() + compacted.receipt_archive.size() == compacted.revision and compacted.game_minutes == 600 and compacted.wallets.player.VKC == 100 and compacted.ledger.is_empty(), "receipt and economic conservation")
	check(Format.fits(compacted), "schema3 capacity check")
	var capacity: Dictionary = Format.capacity(compacted)
	check(capacity.bytes == Format.encoded_size(compacted) and capacity.remaining_bytes + capacity.bytes == Format.MAX_BYTES and capacity.fits and not capacity.warning, "exact capacity projection")
	var detached_book: Dictionary = Component.book()
	detached_book.materials[0].delta = 999
	check(Component.book().materials[0].delta == 0, "public reference cache is detached")
	print("COMPONENT_RETENTION_REGIONS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
