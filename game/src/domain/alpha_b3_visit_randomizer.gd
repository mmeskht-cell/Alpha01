extends RefCounted
## B3-M5 opt-in, source-bound NONSTORY visitor planner.
## This pure function does not seed people, items, cash, contracts, or save data.
## Caller MUST first authorize the candidate identities and their economic
## eligibility, and save the campaign seed in a versioned initial profile
## before connecting this planner to any player-facing New Game path.
const Rules = preload("res://src/domain/value_rules.gd")
const BASE_MIN: int = 5
const BASE_MAX: int = 8

static func _score(seed: int, day: int, label: String) -> int:
	var text: String = str(seed) + ":" + str(day) + ":" + label
	return text.sha256_text().substr(0, 8).hex_to_int()

static func plan(rows: Array, eligible: Dictionary, locked_ids: Array, seed: int, day: int) -> Dictionary:
	if not Rules.integer(seed, 1, Rules.LIMIT) or not Rules.integer(day, 1, 42):
		return {"ok": false, "error": "b3_random_seed_or_day"}
	if rows.size() > 128:
		return {"ok": false, "error": "b3_random_pool_limit"}
	var source_ids: Dictionary = {}
	var actors: Dictionary = {}
	for row: Variant in rows:
		if not Rules.keys(row, ["id", "actor_id", "kind", "purpose_key", "contact_offer"]) or not Rules.identifier(row.id) or not Rules.identifier(row.actor_id):
			return {"ok": false, "error": "b3_random_source_shape"}
		if source_ids.has(row.id) or actors.has(row.actor_id):
			return {"ok": false, "error": "b3_random_duplicate_source"}
		if not eligible.has(row.id) or not eligible[row.id] is bool:
			return {"ok": false, "error": "b3_random_eligibility_missing"}
		source_ids[row.id] = row.duplicate(true)
		actors[row.actor_id] = true

	var protected: Dictionary = {}
	for id: Variant in locked_ids:
		if not Rules.identifier(id) or protected.has(id) or not source_ids.has(id):
			return {"ok": false, "error": "b3_random_protected_identity"}
		# A required story/contract visit is a separate authored obligation.
		# The randomizer must NEVER silently drop it because of a false gate.
		if not bool(eligible[id]):
			return {"ok": false, "error": "b3_random_protected_unavailable"}
		protected[id] = true
	if protected.size() > BASE_MAX:
		return {"ok": false, "error": "b3_random_protected_overflow"}

	var selected: Array = []
	var optional: Array = []
	# Required events retain their written relative ordering.
	for row: Variant in rows:
		var id: String = str(row.id)
		if protected.has(id):
			selected.append(row.duplicate(true))
		elif bool(eligible[id]):
			optional.append({"row": row.duplicate(true), "rank": _score(seed, day, id)})
	optional.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.rank) == int(b.rank):
			return str(a.row.id) < str(b.row.id)
		return int(a.rank) < int(b.rank)
	)
	var target: int = BASE_MIN + int(_score(seed, day, "daily_capacity") % (BASE_MAX - BASE_MIN + 1))
	target = maxi(target, selected.size())
	for entry: Dictionary in optional:
		if selected.size() >= target:
			break
		selected.append(entry.row.duplicate(true))
	# Randomize nonstory order WITHIN authored story/appointment boundaries.
	# A mandatory end-of-day introduction must not jump to first position
	# merely because it was locked against omission.
	var chosen: Dictionary = {}
	for row: Dictionary in selected:
		chosen[row.id] = true
	var finalized: Array = []
	var segment: Array = []
	for row: Dictionary in rows:
		if protected.has(row.id):
			segment.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var left: int = _score(seed, day, str(a.id))
				var right: int = _score(seed, day, str(b.id))
				if left != right:
					return left < right
				return str(a.id) < str(b.id)
			)
			finalized.append_array(segment)
			segment = []
			finalized.append(row.duplicate(true))
		elif chosen.has(row.id):
			segment.append(row.duplicate(true))
	segment.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left: int = _score(seed, day, str(a.id))
		var right: int = _score(seed, day, str(b.id))
		if left != right:
			return left < right
		return str(a.id) < str(b.id)
	)
	finalized.append_array(segment)

	return {"ok": true, "day": day, "target": target, "visits": finalized,
		"actual": finalized.size(), "shortfall": maxi(0, target - finalized.size()),
		"available": protected.size() + optional.size(),
		"locked": protected.size()}
