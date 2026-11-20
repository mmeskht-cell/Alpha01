extends SceneTree
const Runtime = preload("res://src/application/foundation_runtime.gd")
var checks: int = 0
var failures: int = 0
var runtime: RefCounted

func check(value: bool, name: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", name)

func send(id: String, kind: String, p: Dictionary = {}) -> Dictionary:
	return runtime.submit({"action_id": id, "expected_revision": runtime.counter_view().revision, "type": kind, "payload": p})

func inspect(id: String, tool: String, target: String) -> Dictionary:
	return send(id, "inspect_radio", {"item_id": "R001", "tool_id": tool, "target": target})

func select_cards(id: String, material: Variant, batch: Variant) -> Dictionary:
	return send(id, "record_hypothesis", {"item_id": "R001", "model_id": "selvar_r18", "appearance_id": "visible_wear", "material_id": material, "batch_id": batch})

func _initialize() -> void:
	var root: String = "user://zt_rebuild/material_" + str(Time.get_ticks_usec())
	runtime = Runtime.new()
	var ready: bool = runtime.initialize_gate1_opening("gate1_1_v3", root)
	check(ready, "initialize")
	if not ready:
		quit(1)
		return
	check(send("admit", "next_visit").ok, "admission")
	var app: Dictionary = runtime.counter_view().appraisal
	check(app.tools.size() == 6 and app.evidence.is_empty() and app.hypothesis.material_id == null and app.hypothesis.batch_id == null, "unread tools and unset hypotheses")
	check(app.catalog.material_candidates.size() == 3 and app.catalog.batch_candidates.size() == 3, "public swatches and batch handbook")
	check(select_cards("guess", "coated_steel", "series_early").ok and runtime.counter_view().appraisal.reference.estimate == 152, "wrong hypothesis allowed, estimate not truth")
	check(runtime.snapshot().game_minutes == 0 and runtime.counter_view().appraisal.evidence.is_empty(), "hypothesis is free, never evidence")
	check(inspect("material", "material_detail", "shell_material_sample").ok, "material sample")
	app = runtime.counter_view().appraisal
	check(app.evidence[0].reading == {"kind": "texture", "value": "parallel"} and app.hypothesis.material_id == "coated_steel", "raw texture only")
	var before: Dictionary = runtime.snapshot()
	check(not inspect("repeat", "material_detail", "shell_material_sample").ok and runtime.snapshot() == before, "no repeat charge")
	check(inspect("batch", "batch_detail", "batch_stamp_sample").ok, "batch sample")
	app = runtime.counter_view().appraisal
	check(app.evidence[1].reading == {"kind": "batch_code", "value": "K-7"} and app.hypothesis.batch_id == "series_early", "raw code, no auto-correction")
	check(select_cards("interpret", "light_alloy", "series_late").ok and runtime.counter_view().appraisal.reference.estimate == 172, "interpret once, material then condition")
	check(inspect("wear", "wear_detail", "visible_wear_detail").ok, "damage meter")
	app = runtime.counter_view().appraisal
	check(app.evidence[0].reading == {"kind": "damage_index", "value": 43}, "meter reading")
	check(runtime.snapshot().game_minutes == 15 and app.function_status == "unknown", "optional reading times and no power test")
	before = runtime.snapshot()
	check(not select_cards("bad", "fake", "series_late").ok and runtime.snapshot() == before, "forged attribute rejected")
	check(select_cards("clear", null, null).ok and runtime.counter_view().appraisal.reference.estimate == 160, "clear independent material and batch")
	var previously: Dictionary = runtime.snapshot()
	check(not inspect("wrong_region", "wear_detail", "display_damage_sample").ok and runtime.snapshot() == previously, "incorrect tool-target command rejected")
	check(inspect("window", "display_damage_detail", "display_damage_sample").ok, "display-specific damage observation")
	app = runtime.counter_view().appraisal
	check(app.evidence.back().reading == {"kind": "damage_index", "value": 12} and app.reference.estimate == 160, "local reading separate, no double modifier")
	check(app.function_status == "unknown", "localized observation does not identify function")
	check(inspect("test_function", "function_detail", "whole_function_sample").ok, "optional customer function test")
	app = runtime.counter_view().appraisal
	check(app.function_status == "serviceable" and app.reference.estimate == 160 and runtime.snapshot().game_minutes == 25, "function exposed only after test, original formula unchanged")
	var tested: Dictionary = runtime.snapshot()
	check(not inspect("repeat_function", "function_detail", "whole_function_sample").ok and runtime.snapshot() == tested, "repeat functional reading is free")
	var saved: Dictionary = runtime.snapshot()
	runtime.shutdown()
	runtime = Runtime.new()
	ready = runtime.initialize_gate1_opening("gate1_1_v3", root)
	check(ready, "restore setup")
	if ready:
		check(runtime.load_saved().ok and runtime.snapshot() == saved, "schema3 extended hypothesis and evidence restore")
		runtime.shutdown()
	for filename: String in ["gate1_1_v3.a.json", "gate1_1_v3.b.json"]:
		var path: String = root.path_join(filename)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(root)
	print("GATE1_MATERIAL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
