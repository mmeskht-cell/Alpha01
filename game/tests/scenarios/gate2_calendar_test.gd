extends SceneTree
const Session = preload("res://src/domain/game_session.gd")
const Fixture = preload("res://tests/fixtures/foundation_state.gd")
const Catalog = preload("res://src/content/catalog_loader.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
var checks: int = 0
var failures: int = 0
var directory: String = "user://zt_rebuild/calendar_pilot_" + str(Time.get_ticks_usec())

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func fresh(days: int, cash: int = 1000, version: String = "synthetic-1") -> RefCounted:
	var seed: Dictionary = Fixture.make()
	seed.wallets.player.VKC = cash
	# Only a single actual visit in the synthetic profile; no production content.
	var first: Dictionary = seed.visits.buy_1
	seed.visits = {"buy_1": first}
	var ids: Array = []
	for day: int in range(1, days + 1):
		ids.append("fixture_" + str(day))
	var profile: Dictionary = {"id": "demo_7" if days == 7 else "campaign_42", "content_version": version, "day_ids": ids}
	var catalog: Dictionary = Catalog.load_file("res://data/catalog/foundation.json")
	var s := Session.new()
	return s if catalog.ok and s.initialize(catalog.definitions, seed, false, false, profile) else null

func command(s: RefCounted, kind: String, id: String, payload: Dictionary = {}) -> Dictionary:
	return {"action_id": id, "expected_revision": s.snapshot().revision, "type": kind, "payload": payload}

func _initialize() -> void:
	var s: RefCounted = fresh(7)
	var full: RefCounted = fresh(42)
	var poor: RefCounted = fresh(7, 5)
	check(s != null and full != null and poor != null, "both profiles initialize")
	if s == null or full == null or poor == null:
		quit(1)
		return
	var start: Dictionary = s.snapshot()
	check(s.calendar_view().day == 1 and not s.calendar_view().complete, "opening")
	check(not s.execute(command(s, "calendar_morning", "early")).ok and s.snapshot() == start, "cannot skip close")
	check(not s.execute(command(s, "advance_time", "jump", {"minutes": 240})).ok, "cannot bypass calendar")
	var buy: Dictionary = command(s, "trade", "buy_1", {"item_id": "parcel_001", "seller": "seller", "buyer": "player", "currency": "VKC", "amount": 50, "inventory": "player_grid", "x": 0, "y": 0, "rotated": false})
	check(s.execute(buy).ok and s.snapshot().wallets.player.VKC == 950, "existing trade authority")
	for day: int in range(1, 8):
		var close: Dictionary = command(s, "calendar_close", "close" + str(day))
		check(s.execute(close).ok and s.snapshot().game_minutes == (day - 1) * 1440 + 600, "close " + str(day))
		var closed: Dictionary = s.snapshot()
		check(s.execute(close).ok and s.snapshot() == closed, "same receipt no duplicate cost")
		check(not s.execute(command(s, "calendar_close", "extra" + str(day))).ok and s.snapshot() == closed, "second close denied")
		check(s.execute(command(s, "calendar_morning", "morning" + str(day))).ok and s.snapshot().game_minutes == day * 1440, "next morning " + str(day))
	var final: Dictionary = s.snapshot()
	check(s.calendar_view().complete and s.calendar_view().day == 7 and final.game_minutes == 10080 and final.wallets.player.VKC == 845, "demo boundary and seven fees")
	check(not s.execute(command(s, "calendar_close", "d8")).ok and s.snapshot() == final, "no day8")
	check(not full.restore(final), "different profile rejects save")
	var reopened: RefCounted = fresh(7)
	check(reopened != null and reopened.restore(final) and reopened.snapshot() == final, "fresh replay restore")
	var fake: Dictionary = final.duplicate(true)
	fake.wallets.player.VKC += 1
	check(not reopened.restore(fake) and reopened.snapshot() == final, "forged cash denied")
	fake = final.duplicate(true)
	fake.calendar.commands[0].payload.amount = 1
	check(not reopened.restore(fake), "forged journal denied")
	fake = final.duplicate(true)
	fake.calendar.debt = 1
	check(not reopened.restore(fake), "forged debt denied")
	var different: RefCounted = fresh(7, 1000, "synthetic-2")
	check(not different.restore(final), "different content binding")
	var repo := Repo.new(directory)
	check(repo.save_session(s, "calendar_demo_pilot").ok, "isolated existing repository save")
	var loaded: RefCounted = fresh(7)
	check(repo.load_session(loaded, "calendar_demo_pilot").ok and loaded.snapshot() == final, "actual disk restore")
	check(poor.execute(command(poor, "calendar_close", "poorclose")).ok and poor.snapshot().wallets.player.VKC == 0 and poor.calendar_view().overhead_debt == 10, "partial overhead no negative cash")
	check(poor.execute(command(poor, "calendar_morning", "poormorning")).ok and not poor.execute(command(poor, "calendar_pay_overhead", "poorpay")).ok, "unfunded debt stays")
	for day: int in range(1, 43):
		check(full.execute(command(full, "calendar_close", "c" + str(day))).ok, "full close " + str(day))
		check(full.execute(command(full, "calendar_morning", "m" + str(day))).ok, "full morning " + str(day))
	check(full.calendar_view().complete and full.snapshot().game_minutes == 60480 and full.snapshot().wallets.player.VKC == 370 and full.snapshot().receipt_archive.size() > 0, "same engine 42 days and archive")
	var full_reload: RefCounted = fresh(42)
	check(full_reload.restore(full.snapshot()), "full archived replay")
	print("GATE2_A1A_CALENDAR_CHECKS=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
