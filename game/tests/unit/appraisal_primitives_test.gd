extends SceneTree
const Appraisal = preload("res://src/domain/appraisal_primitives.gd")
var checks: int = 0
var failures: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

const Clock = preload("res://src/domain/business_clock.gd")
const Policy = preload("res://src/domain/negotiation_policy.gd")
const Radio = preload("res://src/domain/gate1_appraisal.gd")

func _initialize() -> void:
	check(Clock.day_index(1440) == 2 and Clock.clock_text(1440) == "08:00", "absolute day two boundary")
	check(Clock.clock_text(1020) == "01:00", "clock wraps midnight")
	check(Clock.inspection_at(2030, 10, true).end_minute == 2040, "second day exact close")
	check(Clock.inspection_at(2031, 10, true).error == "inspection_time_short", "second day overrun")
	check(Clock.inspection_at(2040, 5, false).minutes == 0, "second day known review")
	check(not Clock.inspection_at(600, 5, true, "workshop").ok and not Clock.inspection_at(60480, 5, true).ok, "phase and campaign boundary")
	check(Policy.accepts(100, 110, 10, true) and not Policy.accepts(100, 110, 10, false), "existing fixture terms")
	check(Policy.accepts(195, 210, 15, true) and not Policy.accepts(194, 210, 15, true), "alternative private policy")
	check(not Policy.accepts(100, 10, 10, true) and not Policy.accepts(true, 100, 0, false), "invalid policy or offer")
	check(Radio.reading_for({"items": {"R001": {"functional": false}}}, "function_detail").value == "serviceable", "legacy observed reading not live truth")
	check(Appraisal.reference_preview(null, null) == {"ok": true, "base_reference": null, "estimate": null, "partial": true}, "no automatic model")
	check(Appraisal.reference_preview(200, null).estimate == null, "no automatic condition")
	check(Appraisal.reference_preview(200, 80).estimate == 160, "manual wear selection")
	check(Appraisal.reference_preview(240, 80).estimate == 192, "alternative model remains possible")
	check(Appraisal.reference_preview(200, 100).estimate == 200, "alternative wear selection not judged")
	check(Appraisal.reference_preview(200, 60).estimate == 120, "other plausible hypothesis")
	check(Appraisal.reference_preview(201, 50).estimate == 101, "half-up currency convention")
	check(Appraisal.reference_preview(200, 0).estimate == 0, "zero factor")
	check(not Appraisal.reference_preview(-1, 80).ok, "negative base")
	check(not Appraisal.reference_preview(200, 80.5).ok, "fractional modifier")
	check(not Appraisal.reference_preview(200, true).ok, "boolean modifier")
	check(not Appraisal.reference_preview(200, 501).ok, "modifier bounded")
	check(not Appraisal.reference_preview(1000000000, 500).ok, "reference cap")
	check(Appraisal.reference_preview(200, 80).partial, "partial reference, not actual market value")
	check(Appraisal.inspection_preview(0, 5, true) == {"ok": true, "minutes": 5, "end_minute": 5}, "first new evidence")
	check(Appraisal.inspection_preview(5, 10, true).end_minute == 15, "second new evidence")
	check(Appraisal.inspection_preview(15, 5, false).end_minute == 15, "known evidence free")
	check(Appraisal.inspection_preview(590, 10, true).end_minute == 600, "exact closing boundary")
	check(Appraisal.inspection_preview(591, 10, true).error == "inspection_time_short", "oversized action refused")
	check(Appraisal.inspection_preview(600, 5, true).error == "business_closed", "no new inspection at closing")
	check(Appraisal.inspection_preview(600, 5, false).minutes == 0, "known evidence review at closing")
	check(not Appraisal.inspection_preview(10, 0, true).ok, "novel paid action requires duration")
	check(not Appraisal.inspection_preview(601, 5, false).ok, "not business time")
	check(not Appraisal.inspection_preview(0, -1, true).ok, "negative duration refused")
	check(not Appraisal.inspection_preview(0, 5, "true").ok, "invalid knowledge flag")
	check(Appraisal.selected_value([{"id": "known", "delta": 5}], "known", "delta") == 5 and Appraisal.selected_value([{"id": "known"}], "unknown", "delta") == null, "shared public lookup")
	print("APPRAISAL_PRIMITIVES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
