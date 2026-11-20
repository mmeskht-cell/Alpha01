extends SceneTree
const Session = preload("res://src/domain/game_session.gd")
const Fixture = preload("res://tests/fixtures/foundation_state.gd")
const Context = preload("res://tests/fixtures/gate0_c_state.gd")
const Catalog = preload("res://src/content/catalog_loader.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func fresh(variant: String = "") -> RefCounted:
	var state: Dictionary = Fixture.make()
	state.visits = {}
	var days: Array = []
	var schedule: Dictionary = {}
	for i: int in range(7):
		var day: String = "d" + str(i + 1)
		days.append(day)
		schedule[day] = []
	for id: String in ["first", "alternate", "later", "missed"]:
		var sale: bool = id == "later"
		var v: Dictionary = Context.visit(id, "player" if sale else "seller", "seller" if sale else "player", {"parcel_001": {"VKC": 60 if sale else 50, "USD": 0}})
		v.opens = 1440 if id == "later" or id == "missed" else 0
		v.expires = v.opens + 600
		state.visits[id] = v
	schedule.d1 = ["first", "alternate"]
	schedule.d2 = ["later", "missed"]
	if variant == "duplicate":
		schedule.d2.append("first")
	if variant == "missing":
		schedule.d2.pop_back()
	if variant == "wrong_day":
		schedule.d1.append(schedule.d2.pop_back())
	var profile: Dictionary = {"id":"demo_7", "content_version":"queue-1", "day_ids":days, "visit_days":schedule}
	var cat: Dictionary = Catalog.load_file("res://data/catalog/foundation.json")
	var s := Session.new()
	return s if cat.ok and s.initialize(cat.definitions, state, false, false, profile) else null

func cmd(s: RefCounted, kind: String, id: String, p: Dictionary = {}) -> Dictionary:
	return {"action_id":id, "expected_revision":s.snapshot().revision, "type":kind, "payload":p}

func trade(visit: String, sale: bool = false) -> Dictionary:
	return {"visit_id":visit, "item_id":"parcel_001", "seller":"player" if sale else "seller", "buyer":"seller" if sale else "player", "currency":"VKC", "amount":60 if sale else 50, "inventory":"seller_grid" if sale else "player_grid", "x":0, "y":0, "rotated":false}

func reject(s: RefCounted, kind: String, id: String, p: Dictionary = {}) -> bool:
	var before: Dictionary = s.snapshot()
	return not s.execute(cmd(s, kind, id, p)).ok and s.snapshot() == before

func _initialize() -> void:
	var s: RefCounted = fresh()
	check(s != null, "valid profile")
	if s == null:
		quit(1)
		return
	for name: String in ["duplicate", "missing", "wrong_day"]:
		check(fresh(name) == null, "invalid schedule " + name)
	var inspect: Dictionary = {"actor":"player", "item_id":"parcel_001", "key":"functional"}
	check(s.calendar_view().visits.remaining == 2 and s.calendar_view().visits.terms.is_empty(), "only count before admission")
	check(reject(s, "trade", "early_trade", trade("first")), "queued trade denied")
	check(reject(s, "observe", "early_observe", inspect) and s.knowledge_view("parcel_001").is_empty(), "queued inspection denied")
	var admit: Dictionary = cmd(s, "calendar_next_visit", "admit")
	check(s.execute(admit).ok and s.calendar_view().visits.active == "first", "admit first")
	var admitted: Dictionary = s.snapshot()
	check(s.execute(admit).ok and s.snapshot() == admitted, "idempotent admission")
	check(reject(s, "calendar_next_visit", "skip"), "cannot skip active")
	check(reject(s, "trade", "wrong_trade", trade("alternate")), "inactive offer denied")
	check(not s.knowledge_view("parcel_001").is_empty(), "active external read")
	check(reject(s, "calendar_decline_visit", "wrong_decline", {"visit_id":"alternate"}), "cannot decline other")
	check(s.execute(cmd(s, "calendar_decline_visit", "decline", {"visit_id":"first"})).ok, "decline first")
	check(s.calendar_view().visits.outcomes.first == "declined" and s.snapshot().ledger.is_empty() and not s.snapshot().visits.first.scope.completed, "decline is not sale")
	check(s.knowledge_view("parcel_001").is_empty(), "decline revokes access")
	check(s.execute(cmd(s, "calendar_next_visit", "admit2")).ok and s.calendar_view().visits.active == "alternate", "second in order")
	check(reject(s, "trade", "declined_trade", trade("first")), "declined offer cannot be reused")
	check(s.execute(cmd(s, "trade", "purchase", trade("alternate"))).ok and s.snapshot().wallets.player.VKC == 130, "real purchase")
	check(s.calendar_view().visits.outcomes.alternate == "traded" and s.snapshot().items.parcel_001.owner_id == "player", "transfer closes active")
	check(reject(s, "calendar_next_visit", "empty_day"), "no regeneration")
	check(reject(s, "trade", "future", trade("later", true)), "future blocked")
	check(s.execute(cmd(s, "calendar_close", "close1")).ok and s.snapshot().wallets.player.VKC == 115, "close overhead")
	check(reject(s, "calendar_next_visit", "night"), "night admission denied")
	check(s.execute(cmd(s, "calendar_morning", "morning1")).ok and s.calendar_view().visits.remaining == 2, "day2 fixed schedule")
	check(s.execute(cmd(s, "calendar_next_visit", "admit3")).ok and s.calendar_view().visits.active == "later", "day2 first")
	check(s.execute(cmd(s, "trade", "sale", trade("later", true))).ok and s.snapshot().wallets.player.VKC == 175, "same item actual resale")
	check(s.execute(cmd(s, "calendar_next_visit", "admit4")).ok, "admit last")
	check(s.execute(cmd(s, "calendar_close", "close2")).ok and s.snapshot().wallets.player.VKC == 160, "close active")
	check(s.calendar_view().visits.active == "" and s.calendar_view().visits.outcomes.missed == "missed" and not s.snapshot().visits.missed.scope.completed, "unserved opportunity expires without transfer")
	check(s.snapshot().ledger.size() == 2, "two real ledger rows")
	var saved: Dictionary = s.snapshot()
	var reopened: RefCounted = fresh()
	check(reopened != null and reopened.restore(saved) and reopened.snapshot() == saved, "cold replay")
	var fake: Dictionary = saved.duplicate(true)
	fake.calendar.queue.outcomes.first = "traded"
	check(not reopened.restore(fake) and reopened.snapshot() == saved, "forged outcome denied")
	fake = saved.duplicate(true)
	fake.calendar.queue.active = "first"
	check(not reopened.restore(fake), "forged admission denied")
	var repo := Repo.new("user://zt_rebuild/queue_" + str(Time.get_ticks_usec()))
	check(repo.save_session(s,"queue").ok, "disk save")
	var loaded: RefCounted = fresh()
	check(repo.load_session(loaded,"queue").ok and loaded.snapshot() == saved, "disk restore")
	for day: int in range(2, 8):
		check(s.execute(cmd(s,"calendar_morning","morning" + str(day))).ok, "morning " + str(day))
		if day < 7:
			check(s.execute(cmd(s,"calendar_close","close" + str(day+1))).ok, "close " + str(day+1))
	check(s.calendar_view().complete and s.calendar_view().visits.remaining == 0 and reject(s,"calendar_next_visit","d8"), "demo no day8 visit")
	print("GATE2_A1C1_VISIT_CHECKS=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
