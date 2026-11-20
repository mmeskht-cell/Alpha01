extends SceneTree
const Profile = preload("res://src/domain/inspection_profile.gd")
const Appraisal = preload("res://src/domain/gate1_appraisal.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	var book: Dictionary = Profile.legacy_book()
	check(not book.is_empty() and Appraisal.tools().size() == 6, "legacy six tools")
	check(Appraisal.tools().keys() == ["wear_detail", "casing_detail", "material_detail", "batch_detail", "function_detail", "display_damage_detail"], "stable legacy order")
	check(Appraisal.tools().wear_detail == {"target": "visible_wear_detail", "minutes": 5, "evidence_id": "R001.wear", "text_key": "day1.radio.wear"}, "legacy contract retained")
	check(Profile.legacy_reading(book, "R001", "portable_radio", "bootstrap_R001", "batch_detail") == {"kind": "batch_code", "value": "K-7"}, "legacy reading")
	check(Profile.legacy_reading(book, "R001", "portable_radio", "different", "batch_detail").is_empty(), "wrong provenance rejected")
	check(Profile.legacy_reading(book, "R002", "portable_radio", "bootstrap_R001", "batch_detail").is_empty(), "no reading inherited by another instance")
	var exposed: Dictionary = Profile.tools_for(book, "portable_radio")
	check(not exposed.wear_detail.has("value") and not exposed.wear_detail.has("readings"), "no hidden specimen reading in tool DTO")
	var alternate: Dictionary = {"version": 1, "profiles": {"sample_clock": {"tools": [{"id": "dial", "target": "face", "minutes": 3, "evidence_id": "clock.dial", "text_key": "sample.dial", "reading_kind": "damage_index"}]}}, "specimens": {"A": {"def_id": "sample_clock", "provenance": "fixture_a", "readings": {"dial": 9}}, "B": {"def_id": "sample_clock", "provenance": "fixture_b", "readings": {"dial": 71}}}}
	var parsed: Dictionary = Profile.parse(alternate)
	check(not parsed.is_empty() and Profile.tools_for(parsed, "sample_clock").dial.minutes == 3, "alternate fictional definition works without new code")
	check(Profile.legacy_reading(parsed, "A", "sample_clock", "fixture_a", "dial").value == 9 and Profile.legacy_reading(parsed, "B", "sample_clock", "fixture_b", "dial").value == 71, "same definition separate samples")
	var malformed: Dictionary = alternate.duplicate(true)
	malformed.profiles.sample_clock.tools.append(malformed.profiles.sample_clock.tools[0].duplicate(true))
	check(Profile.parse(malformed).is_empty(), "duplicate tool rejected")
	malformed = alternate.duplicate(true)
	malformed.specimens.B.readings.dial = 101
	check(Profile.parse(malformed).is_empty(), "out-of-range damage rejected")
	malformed = alternate.duplicate(true)
	malformed.profiles.sample_clock.tools[0].minutes = -1
	check(Profile.parse(malformed).is_empty(), "negative tool cost rejected")
	malformed = alternate.duplicate(true)
	malformed.specimens.A.readings.injected = "hidden"
	check(Profile.parse(malformed).is_empty(), "extra reading rejected")
	book.profiles.portable_radio.tools.clear()
	check(Appraisal.tools().size() == 6, "content cache detached")
	check(Profile.region_spec([{"id": "face", "label_key": "face.label", "tools": {"meter": "face_damage"}}], "face_damage").tool_key == "meter", "shared regional lookup")
	check(Profile.region_spec([], "missing").is_empty(), "unavailable observation denied")
	check(Profile.preview(2037, 3, false).end_minute == 2040 and not Profile.preview(2038, 3, false).ok, "absolute tool budget")
	print("INSPECTION_PROFILE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
