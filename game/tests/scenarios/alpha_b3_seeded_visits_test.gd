extends SceneTree
## B3-M5 pure planner checks. No new NPC wallets/goods/trades are created.
## These are authored candidate slots, NOT claimed actual funded visits.
const Source = preload("res://src/content/alpha_b3_fx_seed.gd")
const Randomizer = preload("res://src/domain/alpha_b3_visit_randomizer.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func _finish() -> void:
	print("ALPHA_B3_SEEDED_VISIT_CHECKS=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

func _initialize() -> void:
	var source: Dictionary = Source.content()
	if source.is_empty():
		check(false, "unchanged actual M3 source can be fetched")
		_finish()
		return
	var copy: Dictionary = source.duplicate(true)
	var day_two: Array = []
	var day_two_flags: Dictionary = {}
	var day_two_fixed: Array = []
	for day: int in range(1, 8):
		var rows: Array = source.alpha_profile.days[day - 1]
		var availability: Dictionary = {}
		var fixed: Array = []
		var ids: Dictionary = {}
		for row: Dictionary in rows:
			# The source is a trusted candidate fixture for this planner test.
			# Runtime buyers still require real ownership, inventory and funds.
			availability[row.id] = true
			ids[row.id] = row.duplicate(true)
			if str(row.kind) == "named" or str(row.purpose_key).contains("return"):
				fixed.append(str(row.id))
		var p: Dictionary = Randomizer.plan(rows, availability, fixed, 101, day)
		var repeated: Dictionary = Randomizer.plan(rows, availability, fixed, 101, day)
		check(p.get("ok", false) and p == repeated,
			"same campaign seed and source replay the same day " + str(day))
		if not p.get("ok", false):
			_finish()
			return
		check(int(p.target) >= 5 and int(p.target) <= 8
			and int(p.actual) <= int(p.target) and int(p.actual) == p.visits.size(),
			"soft 5-8 capacity without phantom arrivals on day " + str(day))
		var used: Dictionary = {}
		for row: Dictionary in p.visits:
			check(ids.has(row.id) and ids[row.id] == row and not used.has(row.id),
				"all selected visitors are unique existing source identities")
			used[row.id] = true
		for id: String in fixed:
			check(used.has(id), "named/return visit protected on day " + str(day))
		var blocked: Dictionary = availability.duplicate(true)
		for row: Dictionary in rows:
			if row.id not in fixed:
				blocked[row.id] = false
		var underfilled: Dictionary = Randomizer.plan(rows, blocked, fixed, 101, day)
		check(underfilled.ok and int(underfilled.actual) == fixed.size()
			and int(underfilled.shortfall) > 0,
			"missing eligible customers cause honest underfill, never visitor minting")
		if day == 2:
			day_two = rows
			day_two_flags = availability
			day_two_fixed = fixed
	check(source == copy, "planner never mutates source wallets, items, offers or calendar")
	check(not day_two.is_empty(), "real source includes multiple D2 potential visits")
	var baseline: Dictionary = Randomizer.plan(day_two, day_two_flags, day_two_fixed, 101, 2)
	var different: bool = false
	for seed: int in range(102, 145):
		var altered: Dictionary = Randomizer.plan(day_two, day_two_flags, day_two_fixed, seed, 2)
		if altered.get("ok", false) and altered.visits != baseline.visits:
			different = true
			break
	check(different, "different new campaign seeds can change nonstory selection/order")
	check(not Randomizer.plan(day_two, day_two_flags, day_two_fixed, 0, 2).get("ok", false)
		and not Randomizer.plan(day_two, day_two_flags, day_two_fixed, 101, 0).get("ok", false),
		"invalid or missing campaign seed/day is rejected")
	var malformed: Array = day_two.duplicate(true)
	malformed.append(day_two[0].duplicate(true))
	check(not Randomizer.plan(malformed, day_two_flags, day_two_fixed, 101, 2).get("ok", false),
		"duplicate actor/visitor cannot be used to inflate attendance")
	var no_flags: Dictionary = day_two_flags.duplicate(true)
	no_flags.erase(day_two[0].id)
	check(not Randomizer.plan(day_two, no_flags, day_two_fixed, 101, 2).get("ok", false),
		"source-only candidates require an explicit trust/eligibility decision")
	check(not Randomizer.plan(day_two, day_two_flags, ["unwritten_story_event"], 101, 2).get("ok", false),
		"planner does not invent a missing scripted/story customer")
	if not day_two_fixed.is_empty():
		var cannot_fulfill: Dictionary = day_two_flags.duplicate(true)
		cannot_fulfill[day_two_fixed[0]] = false
		check(not Randomizer.plan(day_two, cannot_fulfill, day_two_fixed, 101, 2).get("ok", false),
			"mandatory story/contract visits are never silently rolled away")
	_finish()
