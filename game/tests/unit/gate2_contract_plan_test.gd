extends SceneTree
const Plan = preload("res://src/domain/gate2_contract_plan.gd")
var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	var loaded: Dictionary = Plan.load_candidate()
	check(loaded.ok, "candidate loads")
	if not loaded.ok:
		quit(1)
		return
	var p: Dictionary = loaded.plan
	check(loaded.summary.contracts == 7, "seven offers")
	check(loaded.summary.additional_doses == 13, "thirteen additional doses")
	check(loaded.summary.totals == {"VKC": 2190, "USD": 350}, "two-currency totals")
	check(loaded.summary.effect_remaining_at_end == 2880, "48 hours left at D43")
	var bad: Dictionary = p.duplicate(true)
	bad.duration = 4319
	check(not Plan.audit(bad).ok, "fixed 72h")
	bad = p.duplicate(true)
	bad.contracts[0].tranches[0].amount = 299
	check(not Plan.audit(bad).ok, "first terms immutable")
	bad = p.duplicate(true)
	bad.contracts[4].currency = "VKC"
	check(not Plan.audit(bad).ok, "USD switch")
	bad = p.duplicate(true)
	bad.contracts[1].tranches[0].id = p.contracts[0].tranches[0].id
	check(not Plan.audit(bad).ok, "duplicate tranche")
	bad = p.duplicate(true)
	bad.contracts[1].tranches[0].delivery_minute = 11520
	check(not Plan.audit(bad).ok, "delivery too late")
	bad = p.duplicate(true)
	bad.contracts[1].tranches[0].use_minute += 1440
	check(not Plan.audit(bad).ok, "coverage gap")
	bad = p.duplicate(true)
	bad.contracts[2].tranches.pop_back()
	check(not Plan.audit(bad).ok, "missing tranche")
	bad = p.duplicate(true)
	bad.contracts[1].tranches[0].amount = -1
	check(not Plan.audit(bad).ok, "negative amount")
	bad = p.duplicate(true)
	bad.contracts[1].tranches[0].amount = 330.5
	check(not Plan.audit(bad).ok, "fractional amount")
	bad = p.duplicate(true)
	bad.contracts[1].offer_minute = 0
	check(not Plan.audit(bad).ok, "nonmonotonic offer")
	bad = p.duplicate(true)
	bad.contracts[0].tranches[0].due_minute -= 1
	check(not Plan.audit(bad).ok, "due boundary")
	bad = p.duplicate(true)
	bad.contracts[0].tranches[0].amount = true
	check(not Plan.audit(bad).ok, "boolean price")
	check(not Plan.audit(null).ok, "invalid input")
	var before: String = JSON.stringify(p)
	check(Plan.audit(p).ok and JSON.stringify(p) == before, "read-only audit")
	print("GATE2_A0_PLAN_CHECKS=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
