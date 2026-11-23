extends "res://tests/scenarios/alpha_b3_m7_finite_interest_test.gd"
## Independent SceneTree entry point; parent supplies only command/save helpers.
func _initialize() -> void:
	var src: Dictionary = Source.content(101)
	var session: RefCounted = fresh(src)
	if not check(session != null, "initialize finite seven-day source"):
		done()
		return
	var initial: Dictionary = session.snapshot()
	var repository := Repo.new("user://zt_rebuild/b3_week_" + str(Time.get_ticks_usec()))
	for day: int in range(1, 8):
		if not check(go(session, "alpha_open"), "open day " + str(day)):
			done()
			return
		var observation: Dictionary = session.alpha_view().attendance
		check(observation.arrived == 0 and observation.source == src.alpha_profile.days[day-1].size(), "opening is not attendance")
		check(observation.protected_now <= observation.planned and observation.planned <= observation.eligible_now and observation.planned <= observation.target, "opening bounds")
		var arrived: int = 0
		if day % 2 and int(session.alpha_view().remaining) > 0:
			if not (go(session,"alpha_next_customer") and go(session,"alpha_ack_entry") and go(session,"alpha_finish_customer") and go(session,"alpha_ack_exit")):
				check(false, "first customer can leave without trade")
				done()
				return
			arrived = 1
		if not (go(session,"alpha_close") and go(session,"alpha_settle")):
			check(false, "early close")
			done()
			return
		check(session.alpha_view().attendance.arrived == arrived, "skipped slots are not arrivals")
		check(session.alpha_view().local_trade_flow == {"bought":0,"sold":0,"VKC":0,"USD":0}, "unserved visits create no market turnover")
		var before: Dictionary = session.snapshot()
		for kind: String in ["alpha_salvage_dispatch","alpha_salvage_cancel","merchant_pawn_accept"]:
			var result: Dictionary = session.execute(command(session, kind, {"request_id":"unsigned"} if kind != "merchant_pawn_accept" else {"contract_id":"alpha_pawn"}))
			check(not result.get("ok", false) and before == session.snapshot(), "unsigned contract is atomic")
		if not check(repository.save_session(session,"week").get("ok", false), "save evening"):
			done()
			return
		var cold: RefCounted = fresh(src)
		if not check(cold != null and repository.load_session(cold,"week").get("ok", false) and cold.snapshot() == before, "restore exact evening"):
			done()
			return
		# No outbound campaign contract has been authored: the old M7 slot
		# remains structurally unchanged, and a forged stored request fails
		# authoritative GameSession replay instead of being silently accepted.
		check(not before.alpha_shop.has("outbound"), "M7 legacy slot has no invented outbound state")
		var forged: Dictionary = before.duplicate(true)
		forged.alpha_shop["outbound"] = {"unsigned": {"status":"dispatched"}}
		check(not cold.validate(forged), "unsourced outbound row is rejected by authoritative replay")
		session = cold
		if not (go(session,"alpha_next_day") and (day == 7 or go(session,"alpha_prepare_day"))):
			check(false, "advance after lost opportunities")
			done()
			return
	var final_state: Dictionary = session.snapshot()
	check(final_state.alpha_shop.phase == "COMPLETE" and final_state.wallets == initial.wallets and final_state.items == initial.items and final_state.ledger == initial.ledger, "no automatic replenishment or payment")
	done()
