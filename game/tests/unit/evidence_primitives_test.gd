extends SceneTree
const Evidence = preload("res://src/domain/evidence_primitives.gd")
const Observation = preload("res://src/domain/observation_record.gd")
const Rules = preload("res://src/domain/value_rules.gd")
var checks: int = 0
var failures: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	var record: Dictionary = {"evidence_id": "R001.wear", "item_id": "R001", "observation_key": "appearance_wear", "observed_value": "visible", "source_type": "visual", "visibility": "player", "observed_at": 5, "dependent_field_versions": {"appearance": 1}, "private_truth": "must_not_leak", "source_ref": "internal_ref"}
	var versions: Dictionary = {"appearance": 1, "function": 4}
	var before: Dictionary = record.duplicate(true)
	var view: Dictionary = Evidence.public_view(record, versions, "R001")
	check(not view.is_empty() and view.current and not view.is_claim, "known observation")
	check(view.size() == 8 and not view.has("private_truth") and not view.has("source_ref"), "strict whitelist excludes private data")
	check(record == before, "read only")
	check(Evidence.is_current({"appearance": 1}, {"appearance": 1, "function": 5}), "unrelated field change")
	check(not Evidence.is_current({"appearance": 1}, {"appearance": 2}), "dependent field change")
	check(not Evidence.is_current({"appearance": 1}, {}), "missing field is stale")
	check(Evidence.is_current({}, versions), "independent recorded fact")
	check(not Evidence.is_current({"appearance": -1}, versions), "invalid dependency")
	check(not Evidence.is_current({"appearance": 1}, {"appearance": true}), "invalid current version")
	check(Evidence.eligible_ground(record, versions, "R001", ["appearance_wear"]), "relevant fact")
	check(not Evidence.eligible_ground(record, versions, "R001", ["function_fault"]), "appearance is not function proof")
	check(not Evidence.eligible_ground(record, {"appearance": 2}, "R001", ["appearance_wear"]), "stale fact not usable")
	check(not Evidence.public_view(record, {"appearance": 2}, "R001").current, "stale history remains visible")
	check(Evidence.public_view(record, versions, "OTHER").is_empty(), "wrong item")
	var bad: Dictionary = record.duplicate(true)
	bad.visibility = "private"
	check(Evidence.public_view(bad, versions, "R001").is_empty(), "private observation never exposed")
	bad = record.duplicate(true)
	bad.source_type = "customer"
	check(Evidence.public_view(bad, versions, "R001").is_claim, "customer claim stays claim")
	check(not Evidence.eligible_ground(bad, versions, "R001", ["appearance_wear"]), "claim not fact")
	bad = record.duplicate(true)
	bad.observed_value = {"private": true}
	check(Evidence.public_view(bad, versions, "R001").is_empty(), "unapproved nested data refused")
	bad = record.duplicate(true)
	bad.dependent_field_versions = {"appearance": -1}
	check(Evidence.public_view(bad, versions, "R001").is_empty(), "malformed dependency refused")
	bad = record.duplicate(true)
	bad.observed_at = 60481
	check(Evidence.public_view(bad, versions, "R001").is_empty(), "invalid campaign time")
	var dep: Dictionary = {"functional": 0}
	var sample: Dictionary = Observation.capture("sample", "X01", "functional", "record", 5, true, dep)
	dep.functional = 9
	check(sample.dependent_field_versions.functional == 0, "sample not aliased to later dependency edits")
	check(Observation.capture("sample", "X01", "functional", "record", 5, {"hidden": true}, {}).is_empty(), "nested truth not captured")
	check(Observation.capture("sample", "X01", "functional", "customer", 5, true, {}).is_empty(), "claim cannot be captured as observed fact")
	var request: Dictionary = {"action_id": "sample", "expected_revision": 0, "type": "observe", "payload": {"actor": "player", "item_id": "X01", "key": "functional"}}
	var fingerprint: String = Rules.canonical(request)
	var history: Dictionary = {"game_minutes": 5, "receipts": {"sample": {"fingerprint": fingerprint, "result": {"ok": true, "revision": 1}}}, "receipt_archive": {}}
	check(Observation.bound(history, "sample", sample, "record"), "full request binds observed item")
	history.receipts.clear()
	history.receipt_archive["sample"] = [fingerprint.sha256_text(), 1, "observe"]
	check(Observation.bound(history, "sample", sample, "record"), "compressed request binds same observed item")
	var forged: Dictionary = sample.duplicate(true)
	forged.item_id = "X02"
	check(not Observation.bound(history, "sample", forged, "record"), "archive rejects different item")
	forged = sample.duplicate(true)
	forged.observation_key = "restored"
	check(not Observation.bound(history, "sample", forged, "record"), "archive rejects different observed field")
	forged = sample.duplicate(true)
	forged.visibility = "private"
	check(not Observation.bound(history, "sample", forged, "record"), "invalid private player record refused")
	check(not Observation.bound(history, "sample", sample, "instrument"), "source kind cannot change")
	print("EVIDENCE_PRIMITIVES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
