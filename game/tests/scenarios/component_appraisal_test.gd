extends SceneTree
const Runtime = preload("res://src/application/foundation_runtime.gd")
var rt: RefCounted
var failures: int = 0
var checks: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func send(kind: String, payload: Dictionary) -> Dictionary:
	var revision: int = rt.component_workshop_view().revision
	return rt.submit({"action_id": "p_" + str(revision), "expected_revision": revision, "type": kind, "payload": payload})

func part(id: String) -> Dictionary:
	for row: Dictionary in rt.component_workshop_view().parts:
		if row.id == id:
			return row
	return {}

func read(id: String, key: String) -> Dictionary:
	return send("observe", {"actor": "player", "item_id": id, "key": key})

func choose(id: String, material: String, condition: String, series: String = "series_early") -> Dictionary:
	return send("record_component_hypothesis", {"actor": "player", "item_id": id, "material_id": material, "condition_id": condition, "series_id": series})

func detach(root: String, child: String, x: int) -> Dictionary:
	return send("detach", {"actor": "player", "root_id": root, "child_id": child, "inventory": "player_grid", "x": x, "y": 3, "rotated": false})

func attach(root: String, child: String) -> Dictionary:
	return send("attach", {"actor": "player", "root_id": root, "child_id": child})

func observed(id: String, key: String) -> Dictionary:
	for record: Dictionary in part(id).observations:
		if record.observation_key == key:
			return record
	return {}

func _initialize() -> void:
	var directory: String = "user://zt_rebuild/component_previews/test_" + str(Time.get_ticks_usec())
	rt = Runtime.new()
	var ready: bool = rt.initialize_component_preview(directory)
	check(ready, "fixture initialization")
	if not ready:
		quit(1)
		return
	var initial: Dictionary = rt.snapshot()
	check(part("D001").whole_catalog_reference == 200 and part("D001_A").observations.is_empty() and not part("D001_A").can_inspect, "whole vs unopened part")
	check(not part("D001_A").has("readings") and not part("D001_A").has("functional"), "no raw hidden truth")
	check(not read("D001_A", "component_texture").ok and rt.snapshot() == initial, "hidden attached part inspection denied")
	check(read("D001", "component_texture").ok and read("D001", "component_function").ok, "shell and assembly separately observed")
	check(observed("D001", "component_texture").observed_value == "pore" and observed("D001", "component_function").current and observed("D001", "component_function").observed_value == "partial", "initial partial assembly and shell readings")
	check(detach("D001", "D001_A", 0).ok, "detach existing board")
	check(not observed("D001", "component_function").current and observed("D001", "component_texture").current, "assembly stale, shell evidence persists")
	check(part("D001").whole_catalog_reference == 200 and part("D001_A").can_inspect and part("D001_A").observations.is_empty(), "catalog reference independent of composition, no inherited shell readings")
	check(read("D001_A", "component_texture").ok and read("D001_A", "component_damage").ok and read("D001_A", "component_mark").ok, "part individual readings")
	check(observed("D001_A", "component_texture").observed_value == "cross" and observed("D001_A", "component_damage").observed_value == 18, "different raw readings")
	check(choose("D001_A", "light_alloy", "light_wear").ok and part("D001_A").component_estimate == 100, "wrong manual hypothesis allowed")
	check(choose("D001_A", "coated_steel", "light_wear", "series_late").ok and part("D001_A").component_estimate == 90, "manual corrected value")
	check(choose("D001", "molded_polymer", "visible_wear").ok and part("D001").component_estimate == 24, "shell-only value")
	var ids: Array = ["D001", "D001_A", "D001_B", "D001_C"]
	var value: Dictionary = rt.component_recovery_view(ids)
	check(value.subtotal == 114 and value.unknown_count == 2 and value.estimate == null, "partial recovery with unknowns")
	check(not rt.component_recovery_view(["D001", "D001"]).ok, "duplicate rejected")
	var board: Dictionary = part("D001_A")
	check(attach("D002", "D001_A").ok, "reattach to other owned shell")
	check(part("D001_A").parent_id == "D002" and part("D001_A").hypothesis == board.hypothesis and part("D001_A").observations == board.observations, "ID-local appraisal retained")
	check(detach("D002", "D001_A", 0).ok and not read("D001_A", "component_texture").ok, "no duplicate reading after reattachment")
	check(detach("D001", "D001_B", 3).ok and detach("D001", "D001_C", 5).ok, "other parts exposed")
	check(read("D001_B", "component_texture").ok and read("D001_B", "component_function").ok, "speaker readings")
	check(not observed("D001_B", "component_function").observed_value, "speaker independently faulty")
	check(send("restore_item", {"actor": "player", "item_id": "D001_B"}).ok, "existing abstract repair authority")
	check(not observed("D001_B", "component_function").current and observed("D001_B", "component_texture").current, "only affected field stale")
	check(choose("D001_B", "light_alloy", "visible_wear").ok and choose("D001_C", "light_alloy", "heavy_wear").ok, "remaining estimates")
	value = rt.component_recovery_view(ids)
	check(value.estimate == 169 and value.unknown_count == 0, "exclusive component sum, not plus whole")
	var saved: Dictionary = rt.snapshot()
	check(saved.game_minutes == 600 and saved.wallets.player.VKC == 95 and saved.items.D001_B.basis.VKC == 25, "frozen evening and repair-only cash/basis")
	var basis: int = 0
	for id: String in ids:
		basis += int(saved.items[id].basis.VKC)
	check(basis == 105 and saved.ledger.is_empty(), "no appraisal mutation of acquisition basis")
	rt.shutdown()
	rt = Runtime.new()
	ready = rt.initialize_component_preview(directory)
	check(ready, "reload initializer")
	if ready:
		check(rt.load_saved().ok and rt.snapshot() == saved and rt.component_recovery_view(ids).estimate == 169, "save restore")
		rt.shutdown()
	for filename: String in ["component_preview_v3.a.json", "component_preview_v3.b.json"]:
		var path: String = directory.path_join(filename)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	print("COMPONENT_APPRAISAL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
