extends SceneTree
const Runtime = preload("res://src/application/foundation_runtime.gd")
var checks: int = 0
var failures: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func request(id: String, revision: int, kind: String, payload: Dictionary = {}) -> Dictionary:
	return {"action_id": id, "expected_revision": revision, "type": kind, "payload": payload}

func inspect(id: String, revision: int, tool: String, target: String) -> Dictionary:
	return request(id, revision, "inspect_radio", {"item_id": "R001", "tool_id": tool, "target": target})

func hypothesis(id: String, revision: int, model: Variant, appearance: Variant) -> Dictionary:
	return request(id, revision, "record_hypothesis", {"item_id": "R001", "model_id": model, "appearance_id": appearance})

func _initialize() -> void:
	var directory: String = "user://zt_rebuild/gate1_appraisal_" + str(Time.get_ticks_usec())
	var runtime := Runtime.new()
	var ready: bool = runtime.initialize_gate1_opening("gate1_1_v3", directory)
	check(ready, "campaign setup")
	if not ready:
		quit(1)
		return
	var initial: Dictionary = runtime.snapshot()
	check(runtime.counter_view().appraisal.is_empty(), "no appraisal before admission")
	check(not runtime.submit(inspect("early", 0, "wear_detail", "visible_wear_detail")).ok and runtime.snapshot() == initial, "no inspection outside visit")
	check(not runtime.submit(hypothesis("early_h", 0, "selvar_r18", "visible_wear")).ok and runtime.snapshot() == initial, "no hypothesis outside visit")
	check(runtime.submit(request("reserve", 0, "accept_rad1_contract")).ok, "reserve contract")
	check(runtime.submit(request("admit", 1, "next_visit")).ok, "admit first visitor")
	var admitted: Dictionary = runtime.snapshot()
	var dto: Dictionary = runtime.counter_view().appraisal
	check(not dto.is_empty() and dto.item_id == "R001" and dto.function_status == "unknown", "public terminal-free visible description")
	check(dto.hypothesis.model_id == null and dto.hypothesis.appearance_id == null and dto.reference.estimate == null and dto.evidence.is_empty(), "no automatic appraisal")
	check(dto.catalog.model_candidates.size() == 2 and dto.catalog.appearance_candidates.size() == 3 and dto.catalog.currency == "VKC", "public reference choices")
	check(dto.tools[0].minutes + dto.tools[1].minutes == 15, "separate tool time preview")
	check(runtime.counter_view().appraisal == dto and runtime.snapshot() == admitted, "free repeated reading")
	dto.catalog.model_candidates[0]["reference_amount"] = 1
	check(runtime.counter_view().appraisal.catalog.model_candidates[0].reference_amount == 200 and runtime.snapshot() == admitted, "detached public reference")
	check(not runtime.submit(inspect("wrong_target", 2, "wear_detail", "additional_casing_evidence")).ok and runtime.snapshot() == admitted, "wrong target rejected")
	check(not runtime.submit(inspect("unknown_tool", 2, "fake", "visible_wear_detail")).ok and runtime.snapshot() == admitted, "unknown tool rejected")
	check(not runtime.submit(hypothesis("fake_model", 2, "answer_key", "visible_wear")).ok and runtime.snapshot() == admitted, "unlisted model rejected")
	check(not runtime.submit(request("spoof", 2, "inspect_radio", {"item_id": "R001", "tool_id": "wear_detail", "target": "visible_wear_detail", "text_key": "fake"})).ok and runtime.snapshot() == admitted, "client cannot inject evidence")
	check(runtime.submit(hypothesis("guess", 2, "selvar_r18s", "visible_wear")).ok, "alternative hypothesis accepted without inspection")
	dto = runtime.counter_view().appraisal
	check(dto.reference.estimate == 192 and dto.reference.partial and dto.function_status == "unknown" and dto.evidence.is_empty(), "guess is not evidence or correctness")
	check(runtime.snapshot().game_minutes == 0, "free hypothesis")
	var first: Dictionary = inspect("wear", 3, "wear_detail", "visible_wear_detail")
	check(runtime.submit(first).ok, "first authorized observation")
	var first_state: Dictionary = runtime.snapshot()
	dto = runtime.counter_view().appraisal
	check(first_state.game_minutes == 5 and dto.evidence.size() == 1 and dto.evidence[0].evidence_id == "R001.wear" and dto.evidence[0].observed_at == 5, "first evidence at t5")
	check(dto.reference.estimate == 192 and dto.hypothesis.model_id == "selvar_r18s", "evidence does not choose or correct model")
	check(runtime.submit(first).ok and runtime.snapshot() == first_state, "exact repeat is idempotent")
	check(not runtime.submit(inspect("wear_again", 4, "wear_detail", "visible_wear_detail")).ok and runtime.snapshot() == first_state, "new ID cannot reacquire evidence")
	check(not runtime.submit(inspect("stale", 3, "casing_detail", "additional_casing_evidence")).ok and runtime.snapshot() == first_state, "stale revision")
	check(runtime.submit(inspect("casing", 4, "casing_detail", "additional_casing_evidence")).ok, "second authorized observation")
	dto = runtime.counter_view().appraisal
	check(runtime.snapshot().game_minutes == 15 and dto.evidence.size() == 2 and dto.reference.estimate == 192, "t15, separate evidence, no repeated discount")
	check(dto.function_status == "unknown" and not dto.has("functional") and not dto.has("correct_model"), "no hidden truth")
	check(runtime.submit(hypothesis("normal", 5, "selvar_r18", "visible_wear")).ok, "manual reference revision")
	dto = runtime.counter_view().appraisal
	check(dto.reference.estimate == 160 and dto.reference.partial, "normal 160 manual preview")
	check(runtime.snapshot().game_minutes == 15, "manual comparison remains free")
	check(runtime.submit(hypothesis("clear", 6, null, null)).ok and runtime.counter_view().appraisal.reference.estimate == null, "clear both hypotheses")
	check(runtime.submit(hypothesis("model_only", 7, "selvar_r18", null)).ok and runtime.counter_view().appraisal.reference.estimate == null, "partial model selection")
	check(runtime.submit(hypothesis("normal_again", 8, "selvar_r18", "visible_wear")).ok, "restore selected attributes")
	var before_repeat: Dictionary = runtime.snapshot()
	check(not runtime.submit(hypothesis("same", 9, "selvar_r18", "visible_wear")).ok and runtime.snapshot() == before_repeat, "unchanged hypothesis no receipt")
	check(before_repeat.wallets == admitted.wallets and before_repeat.items == admitted.items and before_repeat.ledger.is_empty(), "no payment, ownership or ledger mutation")
	check(runtime.localization.select_language("en") and runtime.localization.text("day1.radio.wear") == "Visible wear on the casing." and runtime.snapshot() == before_repeat, "English presentation does not change facts")
	check(runtime.localization.select_language("ko") and runtime.localization.text("day1.radio.wear") == "외관에 마모 흔적이 있습니다." and runtime.snapshot() == before_repeat, "Korean presentation does not change facts")
	# Compact the first evidence and opening receipts; no new observations or time consumed.
	for index: int in range(35):
		var model: String = "selvar_r18s" if index % 2 == 0 else "selvar_r18"
		var revision: int = runtime.snapshot().revision
		if not runtime.submit(hypothesis("edit_" + str(index), revision, model, "visible_wear")).ok:
			break
	var compacted: Dictionary = runtime.snapshot()
	check(compacted.revision == 44 and compacted.receipts.size() == 32 and compacted.receipt_archive.has("wear"), "receipt compaction retained")
	check(compacted.game_minutes == 15 and runtime.counter_view().appraisal.evidence.size() == 2, "facts retained after edits")
	check(runtime.submit(first).ok and runtime.snapshot() == compacted, "archived evidence replay unchanged")
	var saved_view: Dictionary = runtime.counter_view()
	runtime.shutdown()
	var restored := Runtime.new()
	ready = restored.initialize_gate1_opening("gate1_1_v3", directory)
	check(ready, "restore initializer")
	if ready:
		check(restored.load_saved().ok and restored.snapshot() == compacted and restored.counter_view() == saved_view, "schema3 appraisal roundtrip")
		check(restored.submit(first).ok and restored.snapshot() == compacted, "archived replay after restore")
		restored.shutdown()
	for name: String in ["gate1_1_v3.a.json", "gate1_1_v3.b.json"]:
		var file: String = directory.path_join(name)
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(directory)
	print("GATE1_APPRAISAL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
