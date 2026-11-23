extends SceneTree
## A pre-authored narrative-linked commission is protected from RNG only
## after genuine counter acceptance. Unaccepted pickups never materialize.
const Source = preload("res://src/content/alpha_b3_random_runtime_seed.gd")
const Session = preload("res://src/domain/game_session.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
const Commission = preload("res://src/domain/alpha_commission.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
	return ok

func go(s: RefCounted, type: String, payload: Dictionary = {}) -> bool:
	var rev: int = int(s.snapshot().revision)
	var command: Dictionary = {"action_id": "m5_conditional_" + str(rev + 1),
		"expected_revision": rev, "type": type, "payload": payload}
	var out: Dictionary = s.execute(command)
	if not out.get("ok", false):
		printerr("M5_CONDITIONAL_COMMAND ", type, " ", out)
	return bool(out.get("ok", false))

func done() -> void:
	print("ALPHA_B3_CONDITIONAL_STORY_CHECKS=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

func _initialize() -> void:
	var src: Dictionary = Source.content(101)
	var s := Session.new()
	if not check(not src.is_empty()
			and s.initialize(src.defs, src.state, false, false, {}, src.alpha_profile),
			"source-bound seeded profile with real Ian commission"):
		done()
		return
	var start: Dictionary = s.snapshot()
	if not check(go(s, "alpha_open"), "day one opens with actual seeded visits"):
		done()
		return
	var plan: Array = s.snapshot().alpha_shop.random_visits.plan.duplicate()
	check("alpha_ian_hygiene_offer_d1" in plan
		and "alpha_marcus_intro" in plan,
		"story-linked D1 request and supply intro are authored protected meetings")
	var accepted: bool = false
	while int(s.alpha_view().remaining) > 0:
		if not (go(s, "alpha_next_customer") and go(s, "alpha_ack_entry")):
			check(false, "actual D1 visitor")
			done()
			return
		var visit_id: String = str(s.alpha_view().active.id)
		if visit_id == "alpha_ian_hygiene_offer_d1":
			check(go(s, "alpha_commission_accept", {"request_id": "hygiene_for_ian"}),
				"actual Ian counter encounter explicitly accepts existing order")
			accepted = true
		if not (go(s, "alpha_finish_customer") and go(s, "alpha_ack_exit")):
			check(false, "D1 customer exits")
			done()
			return
	if not check(accepted and s.snapshot().alpha_shop.commissions.entries.hygiene_for_ian.status == "accepted",
			"named order was actually accepted; no synthetic advance money or goods"):
		done()
		return
	check(s.snapshot().wallets == start.wallets and s.snapshot().items == start.items
		and s.snapshot().ledger == start.ledger,
		"accepting Ian order creates no fictional funds, items or sales")
	if not check(go(s,"alpha_close") and go(s,"alpha_settle") and go(s,"alpha_next_day")
			and go(s,"alpha_prepare_day"),"D1 proceeds with accepted D5 commitment"):
		done()
		return
	for day: int in range(2,5):
		if not (go(s,"alpha_open") and go(s,"alpha_close") and go(s,"alpha_settle")
				and go(s,"alpha_next_day") and go(s,"alpha_prepare_day")):
			check(false,"D"+str(day)+" early closure preserves accepted promise")
			done()
			return
	if not check(go(s,"alpha_open"),"D5 admits real conditional return"):
		done()
		return
	var recorded: Array = s.snapshot().alpha_shop.random_visits.plan
	check("hygiene_buy" in recorded and "hygiene_sale" in recorded,
		"accepted Ian pickup and prerequisite real HY05 acquisition both protected")
	check(int(s.snapshot().alpha_shop.day)==5
		and int(s.snapshot().alpha_shop.random_visits.day)==5,
		"accepted obligation stays on authored fifth day, not moved by RNG")
	check(s.alpha_view().pickup_pending == "hygiene_for_ian",
		"actual accepted due customer blocks early close until serviced or cancelled")
	var before_close: Dictionary = s.snapshot()
	var reject_close: Dictionary = s.execute({"action_id":"m5_conditional_blocked_close",
		"expected_revision":int(before_close.revision),"type":"alpha_close","payload":{}})
	check(not reject_close.get("ok",false) and s.snapshot()==before_close,
		"unserved real obligation cannot be silently skipped by closing")
	# Pure read-only cursor witness: the random plan, not source day array,
	# is the only valid basis for deciding if a pickup is still pending.
	var projected: Dictionary = before_close.duplicate(true)
	var altered: Array = projected.alpha_shop.random_visits.plan.duplicate()
	altered.erase("hygiene_sale")
	altered.insert(0,"hygiene_sale")
	projected.alpha_shop.random_visits.plan=altered
	projected.alpha_shop.cursor=1
	check(Commission.pending_pickup(projected).is_empty() and s.snapshot()==before_close,
		"pending pickup observes sealed randomized cursor, not obsolete authored row positions")
	check(s.snapshot().wallets == start.wallets and s.snapshot().items == start.items
		and s.snapshot().ledger == start.ledger,
		"future commissioned pickup cannot mint current funds or complete an unsold item")
	var db := Repo.new("user://zt_rebuild/b3_m5_conditional_"+str(Time.get_ticks_usec()))
	check(db.save_session(s,"conditional").get("ok", false),
		"accepted conditional daily plan has a valid A/B save")
	var cold := Session.new()
	check(cold.initialize(src.defs, src.state, false, false, {}, src.alpha_profile)
		and db.load_session(cold,"conditional").get("ok", false)
		and cold.snapshot()==s.snapshot(),
		"saved accepted story-linked return cold-replays without reroll")
	done()
