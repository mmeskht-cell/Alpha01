extends SceneTree
## Opt-in B3-M5 production session integration: one committed daily roll,
## immutable seeded profile, replay, A/B save, and legacy M3 isolation.
const Source = preload("res://src/content/alpha_b3_random_runtime_seed.gd")
const Legacy = preload("res://src/content/alpha_b3_fx_seed.gd")
const Session = preload("res://src/domain/game_session.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, reason: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", reason)
	return ok

func fresh(data: Dictionary) -> RefCounted:
	var s := Session.new()
	if not s.initialize(data.defs, data.state, false, false, {}, data.alpha_profile):
		printerr("M5_RANDOM_INIT ", s.initialization_error())
		return null
	return s

func go(s: RefCounted, action: String, payload: Dictionary = {}) -> bool:
	var command: Dictionary = {"action_id": "m5_runtime_" + str(s.snapshot().revision + 1),
		"expected_revision": s.snapshot().revision, "type": action, "payload": payload}
	var result: Dictionary = s.execute(command)
	if not result.get("ok", false):
		printerr("M5_RANDOM_COMMAND ", action, " ", result)
	return result.get("ok", false)

func done() -> void:
	print("ALPHA_B3_RANDOM_RUNTIME_CHECKS=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

func _initialize() -> void:
	var original: Dictionary = Legacy.content()
	var source: Dictionary = Source.content(101)
	var alternative: Dictionary = Source.content(197)
	if not check(not source.is_empty() and not alternative.is_empty() and not original.is_empty(),
			"new seeded profiles use existing exact M3 items/visits/actors"):
		done()
		return
	check(source.state == original.state and source.defs == original.defs
		and source.alpha_profile.days == original.alpha_profile.days,
		"no actor, object, amount, visit or authored story event created or changed")
	check(source.alpha_profile.visit_random.seed == 101
		and alternative.alpha_profile.visit_random.seed == 197
		and not Source.content(0).has("alpha_profile"),
		"seed variation is explicit and invalid seed rejected")
	var high_seed: RefCounted = fresh(Source.content(1000000000))
	check(high_seed != null and Source.content(1000000001).is_empty(), "maximum canonical JSON-safe campaign seed and one-above rejected")
	var s: RefCounted = fresh(source)
	var replay: RefCounted = fresh(source)
	var legacy: RefCounted = fresh(original)
	if not check(s != null and replay != null and legacy != null,
			"both new and legacy models initialize"):
		done()
		return
	var initial: Dictionary = s.snapshot()
	check(initial.alpha_shop.random_visits.plan == []
		and initial.alpha_shop.random_visits.day == 0
		and not legacy.snapshot().alpha_shop.has("random_visits"),
		"original M3 save shape untouched, new plan only in opt-in save")

	if not check(go(s, "alpha_open") and go(replay, "alpha_open"),
			"one replayable plan drawn at original shop opening"):
		done()
		return
	var day_one: Dictionary = s.snapshot()
	var frozen: Array = day_one.alpha_shop.random_visits.plan.duplicate()
	check(frozen == replay.snapshot().alpha_shop.random_visits.plan
		and frozen.size() <= 8 and frozen.size() <= day_one.alpha_shop.random_visits.target,
		"same seed and source yield identical finite visitor sequence")
	check("alpha_marcus_intro" in frozen and "alpha_ian_hygiene_offer_d1" in frozen,
		"authored first-day supplier intro and story-linked Ian order offer cannot be rerolled")
	check(day_one.items == initial.items and day_one.wallets == initial.wallets
		and day_one.ledger == initial.ledger,
		"opening changes no money/stock/owner, only shop phase and plan")
	check(s.alpha_view().remaining <= frozen.size(),
		"the UI can only advertise the fixed real plan")
	var store := Repo.new("user://zt_rebuild/b3_m5_random_" + str(Time.get_ticks_usec()))
	check(store.save_session(s,"b3_m5_runtime").get("ok",false),
		"new seed-bound plan persisted to A/B save")
	var cold: RefCounted = fresh(source)
	check(cold != null and store.load_session(cold,"b3_m5_runtime").get("ok",false)
		and cold.snapshot() == day_one and cold.alpha_view() == s.alpha_view(),
		"cold restore reproduces exact day-one visit plan without reroll")
	var wrong_seed: RefCounted = fresh(alternative)
	check(wrong_seed != null and not wrong_seed.restore(day_one),
		"wrong campaign seed cannot load this plan")
	check(not legacy.restore(day_one),
		"legacy M3 cannot ingest new random plan")
	var forged: Dictionary = day_one.duplicate(true)
	forged.alpha_shop.random_visits.plan = ["alpha_forged_visitor"]
	check(not s.restore(forged) and s.snapshot() == day_one,
		"forged saved plan rejected by canonical replay")
	forged = day_one.duplicate(true)
	forged.alpha_shop.random_visits.target = 99
	check(not s.restore(forged) and s.snapshot() == day_one,
		"forged visitor count rejected instead of trust in mutable save fields")
	var ids: Dictionary = {}
	var shown: Array = []
	while int(s.alpha_view().remaining) > 0:
		if not (go(s,"alpha_next_customer") and go(s,"alpha_ack_entry")):
			check(false, "actual source customer admission")
			done()
			return
		var row: Dictionary = s.alpha_view().active
		check(row.id in frozen and not ids.has(row.id),
			"each real admitted visit comes once from the recorded plan")
		ids[row.id] = true
		shown.append(str(row.id))
		if not (go(s,"alpha_finish_customer") and go(s,"alpha_ack_exit")):
			check(false, "actual customer departure")
			done()
			return
	check(s.snapshot().alpha_shop.random_visits.plan == frozen
		and s.alpha_view().remaining == 0,
		"daily roll is never reshuffled by customer actions")
	if not check(go(s,"alpha_close") and go(s,"alpha_settle")
			and go(s,"alpha_next_day") and go(s,"alpha_prepare_day"),
			"existing shop closing, settlement and next-day authority retained"):
		done()
		return
	check(s.snapshot().alpha_shop.random_visits.plan.is_empty()
		and s.snapshot().alpha_shop.random_visits.day == 0,
		"next-day preparation clears only the prior frozen plan")
	if not check(go(s,"alpha_open"),"new day draws a fresh, state-eligible seeded plan"):
		done()
		return
	check(s.snapshot().alpha_shop.random_visits.day == 2
		and s.snapshot().alpha_shop.random_visits.plan.size() <= 8,
		"day two plan persisted under correct world day")
	check(s.snapshot().items == initial.items
		and s.snapshot().ledger == initial.ledger,
		"refusing all nonstory trades creates no phantom goods or income")
	check(store.save_session(s,"b3_m5_runtime").get("ok",false),
		"second A/B generation preserves day transition")
	cold = fresh(source)
	check(cold != null and store.load_session(cold,"b3_m5_runtime").get("ok",false)
		and cold.snapshot() == s.snapshot(),
		"cold restore keeps unchanged same-seed second-day sequence")
	# Bounded full seven-day calendar A/B branch: intentionally exercise
	# early-close/no-sale on later days. Do not fabricate attendance or paid
	# trades solely to satisfy a soft visit target.
	var meaningful_shortfall: bool = false
	for day: int in range(2,8):
		if day > 2 and not check(go(s,"alpha_open"),"day "+str(day)+" starts once"):
			done()
			return
		var selection: Dictionary = s.snapshot().alpha_shop.random_visits
		check(int(selection.day)==day
			and selection.plan.size()<=8
			and int(selection.target)>=5 and int(selection.target)<=8,
			"each of seven days uses a persisted bounded plan, day "+str(day))
		if day == 5:
			check("hygiene_buy" in selection.plan and "hygiene_sale" not in selection.plan,
				"Day5 real HY05 acquisition remains accessible; declined Ian order creates no phantom pickup")
		if int(selection.shortfall)>0:
			meaningful_shortfall = true
		if not check(go(s,"alpha_close") and go(s,"alpha_settle") and go(s,"alpha_next_day"),
			"normal early-close/settlement without artificial customer visits day "+str(day)):
			done()
			return
		if day<7 and not check(go(s,"alpha_prepare_day"),"next real day remains available"):
			done()
			return
	check(meaningful_shortfall,
		"source shortage is reported instead of making up nonexistent D5-D7 customers")
	var complete: Dictionary = s.snapshot()
	check(complete.alpha_shop.phase=="COMPLETE" and complete.alpha_shop.day==7
		and complete.items==initial.items and complete.wallets==initial.wallets
		and complete.ledger==initial.ledger,
		"seven-day no-trade branch has finite completion and exact money/item conservation")
	check(store.save_session(s,"b3_m5_runtime").get("ok",false),
		"seven-day result fits existing A/B storage without schema change")
	cold = fresh(source)
	check(cold != null and store.load_session(cold,"b3_m5_runtime").get("ok",false)
		and cold.snapshot()==complete and cold.alpha_view()==s.alpha_view(),
		"cold restore of full seven-day seeded history is identical")
	done()
