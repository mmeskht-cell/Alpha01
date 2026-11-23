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
		if day == 1:
			var named_original: Array = []
			var named_planned: Array = []
			for source_row: Dictionary in rows:
				if source_row.id in fixed:
					named_original.append(str(source_row.id))
			for actual_row: Dictionary in p.visits:
				if actual_row.id in fixed:
					named_planned.append(str(actual_row.id))
			check(named_original == named_planned
				and "alpha_marcus_intro" in named_planned,
				"protected named story/contract visits retain their authored relative order")
		if day == 2:
			day_two = rows
			day_two_flags = availability
			day_two_fixed = fixed
	var story_rows: Array = source.alpha_profile.days[4]
	var story_flags: Dictionary = {}
	var story_expected: int = -1
	for i: int in range(story_rows.size()):
		story_flags[story_rows[i].id] = true
		if story_rows[i].id == "hygiene_sale":
			story_expected = i
	var story_draw: Dictionary = Randomizer.plan(story_rows, story_flags, ["hygiene_sale"], 101, 5)
	var story_position: int = -1
	for i: int in range(story_draw.get("visits", []).size()):
		if story_draw.visits[i].id == "hygiene_sale":
			story_position = i
	check(story_draw.get("ok", false) and story_expected >= 0
		and story_position == story_expected,
		"narrative-linked economic visit retains authored Day5 position")
	# An unusually obligation-heavy day may exceed the default 5–8
	# target: the shop must not cancel accepted commitments to satisfy RNG.
	# Pure fixture uses only nine DISTINCT existing authored identities.
	var overload_rows: Array = []
	var overload_actors: Dictionary = {}
	for day_rows: Array in source.alpha_profile.days:
		for row: Dictionary in day_rows:
			if not overload_actors.has(row.actor_id) and overload_rows.size()<9:
				overload_rows.append(row.duplicate(true))
				overload_actors[row.actor_id] = true
	var overload_allowed: Dictionary = {}
	var overload_mandatory: Array = []
	for row: Dictionary in overload_rows:
		overload_allowed[row.id] = true
		overload_mandatory.append(str(row.id))
	var extra: Dictionary = Randomizer.plan(overload_rows, overload_allowed, overload_mandatory, 101, 1)
	check(overload_rows.size()==9 and extra.get("ok", false) and int(extra.get("target", 0))==9
		and extra.get("visits", []).size()==9,
		"nine pre-accepted appointments override soft 5–8 attendance without cancellation")
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
