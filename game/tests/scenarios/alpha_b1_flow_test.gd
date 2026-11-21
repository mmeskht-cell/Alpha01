extends SceneTree
const Seed = preload("res://src/content/alpha_b1_seed.gd")
const Session = preload("res://src/domain/game_session.gd")
const Alpha = preload("res://src/domain/alpha_shop_cycle.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
const Legacy = preload("res://src/content/demo7_seed.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", name)

func fresh() -> RefCounted:
	var data: Dictionary = Seed.content()
	var s := Session.new()
	if data.is_empty() or not s.initialize(data.defs, data.state, false, false, {}, data.alpha_profile):
		printerr("B1 init ", s.initialization_error())
		return null
	return s

func command(s: RefCounted, kind: String, payload: Dictionary = {}) -> Dictionary:
	return {"action_id": "test_b1_" + str(s.snapshot().revision + 1), "expected_revision": s.snapshot().revision, "type": kind, "payload": payload}

func go(s: RefCounted, kind: String, payload: Dictionary = {}) -> bool:
	return bool(s.execute(command(s, kind, payload)).ok)

func reject(s: RefCounted, kind: String, payload: Dictionary = {}) -> bool:
	var old: Dictionary = s.snapshot()
	return not s.execute(command(s, kind, payload)).ok and old == s.snapshot()

func _initialize() -> void:
	var s: RefCounted = fresh()
	check(s != null, "B1 profile initialized")
	if s == null:
		quit(1)
		return
	var start: Dictionary = s.snapshot()
	var first: Dictionary = Alpha.view(start)
	check(first.day == 1 and first.phase == "DAY_PREP" and first.remaining > 0, "clockless day prep")
	check(reject(s, "advance_time", {"minutes": 1}) and reject(s, "calendar_close") and reject(s, "trade"), "legacy commands isolated")
	check(reject(s, "alpha_next_customer") and not Alpha.can_contact(start.alpha_shop, "G01"), "closed entry and contacts")
	check(go(s, "alpha_open") and go(s, "alpha_next_customer"), "counter enter")
	check(Alpha.view(s.snapshot()).active.actor_id == "G01", "existing real actor selected")
	check(reject(s, "alpha_close") and reject(s, "alpha_exchange_contact", {"actor_id":"G01","accepted":true}), "no closing active visitor or pre-dialogue exchange")
	check(go(s, "alpha_ack_entry") and reject(s, "alpha_exchange_contact", {"actor_id":"G01","accepted":false}), "NPC consent and player acceptance required")
	check(go(s, "alpha_exchange_contact", {"actor_id":"G01","accepted":true}), "contact exchange after actual dialogue")
	check(reject(s, "alpha_exchange_contact", {"actor_id":"G01","accepted":true}) and reject(s, "alpha_exchange_contact", {"actor_id":"marcus","accepted":true}), "no duplicate or forged contact")
	check(go(s, "alpha_finish_customer"), "visitor leaves")
	check(reject(s, "alpha_close"), "exit animation must finish first")
	check(go(s, "alpha_ack_exit"), "counter returns idle")
	check(Alpha.view(s.snapshot()).active.is_empty(), "no ghost customer")
	check(reject(s, "alpha_request_salvage", {"actor_id":"G01"}), "no B3 outgoing orders in business hours")
	check(go(s, "alpha_close") and go(s, "alpha_settle"), "early close and single settlement")
	var evening: Dictionary = s.snapshot()
	check(evening.alpha_shop.phase == "EVENING_WORK" and evening.alpha_shop.settled_days == [1], "evening date only")
	check(evening.wallets == start.wallets and evening.items == start.items and evening.ledger == start.ledger and evening.game_minutes == start.game_minutes, "no fake cash items ledger or minutes")
	check(Alpha.can_contact(evening.alpha_shop, "G01") and not Alpha.can_contact(evening.alpha_shop, "marcus"), "contact authority only after consent and settlement")
	check(reject(s, "alpha_settle") and reject(s, "alpha_request_salvage", {"actor_id":"G01"}), "no duplicate settlement or unimplemented order")
	var saved: Dictionary = s.snapshot()
	var root_path: String = "user://zt_rebuild/alpha_b1_test_" + str(Time.get_ticks_usec())
	var repo := Repo.new(root_path)
	check(repo.save_session(s, "alpha_b1_test").ok, "A/B generation saved")
	var recovered: RefCounted = fresh()
	check(recovered != null and repo.load_session(recovered, "alpha_b1_test").ok and recovered.snapshot() == saved, "cold save reload")
	var tampered: Dictionary = saved.duplicate(true)
	tampered.alpha_shop.contacts.G01.exchange_event_id = "forged"
	check(not recovered.restore(tampered) and recovered.snapshot() == saved, "contact replay tamper rejected")
	check(not s.restore(Legacy.fresh().snapshot()), "legacy save cannot cross alpha profile")
	var legacy: RefCounted = Legacy.fresh()
	check(legacy != null and not legacy.restore(saved), "alpha save cannot cross legacy profile")
	check(go(s, "alpha_next_day") and s.snapshot().alpha_shop.phase == "NEXT_DAY", "day boundary")
	check(go(s, "alpha_prepare_day") and s.snapshot().alpha_shop.day == 2 and go(s, "alpha_open"), "second day ready")
	check(s.snapshot().game_minutes == 1440 and s.snapshot().wallets == start.wallets and not s.clock_view().has("minute"), "date-only bridge without exposed clock or economy migration")
	check(repo.save_session(s, "alpha_b1_test").ok, "second generation saved")
	var cold: RefCounted = fresh()
	check(repo.load_session(cold, "alpha_b1_test").ok and cold.snapshot() == s.snapshot(), "second day cold restore")
	var old_command: Dictionary = command(s, "alpha_close")
	check(s.execute(old_command).ok, "close day 2")
	var after: Dictionary = s.snapshot()
	check(s.execute(old_command).ok and after == s.snapshot(), "same receipt replay idempotent")
	check(reject(s, "alpha_close") and reject(s, "alpha_next_customer"), "no duplicated date settle or late visit")
	print("ALPHA_B1_FLOW_CHECKS=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
