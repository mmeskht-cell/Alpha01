extends SceneTree
const Session = preload("res://src/domain/game_session.gd")
const Fixture = preload("res://tests/fixtures/foundation_state.gd")
const Catalog = preload("res://src/content/catalog_loader.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
const Audit = preload("res://src/domain/calendar_identity_audit.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func fresh(cash: int = 500, extension: bool = false, days: int = 7) -> RefCounted:
	var seed: Dictionary = Fixture.make()
	seed.wallets.player = {"VKC": cash, "USD": 0}
	seed.wallets["marcus"] = {"VKC": 0, "USD": 0}
	seed.visits = {"buy_1": seed.visits.buy_1}
	var ids: Array = []
	for d: int in range(1, days + 1):
		ids.append("fixture_" + str(d))
	var stocks: Array = ["RAD01"]
	if days == 42:
		for i: int in range(2, 14):
			stocks.append("RAD%02d" % i)
	var profile: Dictionary = {"id": "demo_7" if days == 7 else "campaign_42", "content_version": "rad-pilot-1", "day_ids": ids, "medicine": {"stock_ids": stocks, "extension_ids": ["RAD01"] if extension else []}}
	var catalog: Dictionary = Catalog.load_file("res://data/catalog/foundation.json")
	var s := Session.new()
	return s if catalog.ok and s.initialize(catalog.definitions, seed, false, false, profile) else null

func cmd(s: RefCounted, kind: String, id: String, payload: Dictionary = {}) -> Dictionary:
	return {"action_id": id, "expected_revision": s.snapshot().revision, "type": kind, "payload": payload}

func act(s: RefCounted, kind: String, id: String, payload: Dictionary = {}) -> bool:
	return s.execute(cmd(s, kind, id, payload)).ok

func terms() -> Dictionary:
	return {"contract": "C1", "tranche": "RAD01"}

func m(s: RefCounted) -> Dictionary:
	return s.calendar_view().medicine

func day(s: RefCounted, d: int) -> void:
	check(act(s, "calendar_close", "c" + str(d)), "close " + str(d))
	check(act(s, "calendar_morning", "m" + str(d)), "morning " + str(d))

func _initialize() -> void:
	var s: RefCounted = fresh()
	var poor: RefCounted = fresh(180)
	var later: RefCounted = fresh(500, true)
	var extended: RefCounted = fresh(500, false, 42)
	check(s != null and poor != null and later != null and extended != null, "all seed profiles")
	if s == null or poor == null or later == null or extended == null:
		quit(1)
		return
	check(m(s).remaining_minutes == 2880 and m(s).personal_ids == ["INITIAL"], "initial")
	check(m(extended).contracts.size() == 1, "future contracts hidden")
	check(not act(s, "rad_use", "steal", {"id": "RAD01"}), "unowned medicine")
	check(not act(s, "rad_pay", "premature", terms()), "reservation required")
	check(act(s, "rad_reserve", "reserve", terms()) and s.snapshot().wallets.player.VKC == 500, "reserve no prepay")
	check(not act(s, "rad_reserve", "double", terms()), "no duplicate reservation")
	check(not act(s, "rad_extend", "extend_early", terms()), "extension not granted")
	day(s, 1)
	day(s, 2)
	check(not m(s).suppressed and m(s).personal_ids.size() == 1, "effect expires, no automatic use")
	check(act(s, "rad_use", "use1", {"id": "INITIAL"}) and m(s).effect_until == 7200, "D3 explicit dose")
	check(not act(s, "rad_use", "reuse", {"id": "INITIAL"}), "consumed identity")
	day(s, 3)
	check(act(s, "calendar_close", "c4"), "D4 close")
	var paid: Dictionary = s.snapshot()
	check(paid.wallets.player.VKC == 140 and paid.wallets.marcus.VKC == 300 and m(s).contracts.C1.tranches[0].status == "paid", "D4 overhead then exact transfer")
	check(m(s).personal_ids.is_empty(), "not yet delivered")
	check(s.execute({"action_id": "c4", "expected_revision": paid.revision - 1, "type": "calendar_close", "payload": {}}).ok and s.snapshot() == paid, "deadline receipt idempotent")
	check(act(s, "calendar_morning", "m4"), "D5 open")
	check(act(s, "calendar_close", "c5") and m(s).personal_ids == ["RAD01"], "D5 actual delivery")
	check(act(s, "calendar_morning", "m5"), "D6 open")
	check(act(s, "rad_use", "use2", {"id": "RAD01"}) and m(s).effect_until == 11520, "D6 use D9 effect")
	day(s, 6)
	day(s, 7)
	check(s.calendar_view().complete and m(s).remaining_minutes == 1440 and m(s).personal_ids.is_empty(), "D8 boundary 24h left")
	var final: Dictionary = s.snapshot()
	var identity:Dictionary=Audit.audit(Audit.begin(s),s)
	check(identity.ok and identity.medicine_doses.RAD01=="consumed" and not identity.items.has("RAD01") and s.snapshot()==final,"consumed dose typed separately")
	var reloaded: RefCounted = fresh()
	check(reloaded.restore(final), "full replay")
	var forged: Dictionary = final.duplicate(true)
	forged.calendar.medicine.stock.RAD01.status = "personal"
	check(not reloaded.restore(forged), "forged dose")
	forged = final.duplicate(true)
	forged.calendar.medicine.effect_until += 1
	check(not reloaded.restore(forged), "forged effect")
	forged = final.duplicate(true)
	forged.wallets.marcus.VKC -= 1
	check(not reloaded.restore(forged), "forged supplier wallet")
	check(not act(s, "rad_auto", "post", {"enabled": true}), "no post-demo mutation")
	check(act(poor, "rad_reserve", "reserve", terms()), "poor reserve")
	for d: int in range(1, 5):
		day(poor, d)
	check(m(poor).contracts.C1.tranches[0].status == "missed" and poor.snapshot().wallets.marcus.VKC == 0, "missed payment")
	day(poor, 5)
	check(m(poor).personal_ids == ["INITIAL"], "no free delivery")
	check(act(later, "rad_reserve", "reserve", terms()), "extension fixture reserve")
	check(act(later, "rad_auto", "auto", {"enabled": true}), "opt in auto")
	for d: int in range(1, 4):
		day(later, d)
	check(m(later).effect_until == 7200, "auto D3")
	check(act(later, "rad_extend", "extend", terms()), "allowed D4 extension")
	check(not act(later, "rad_extend", "again", terms()), "one extension")
	day(later, 4)
	check(m(later).contracts.C1.tranches[0].status == "reserved" and later.snapshot().wallets.marcus.VKC == 0, "no old deadline debit")
	day(later, 5)
	check(m(later).effect_until == 11520 and later.snapshot().wallets.marcus.VKC == 300, "D5 pay delivery then D6 auto")
	check(act(extended, "rad_decline", "decline", terms()) and not act(extended, "rad_reserve", "rereserve", terms()), "declined contract not renewed")
	check(not act(extended, "rad_reserve", "future", {"contract": "C2", "tranche": "RAD02"}), "future contract locked")
	var early: RefCounted = fresh()
	check(act(early, "rad_use", "early", {"id": "INITIAL"}) and m(early).effect_until == 4320, "early use no stacking")
	print("GATE2_A1B_MEDICINE_CHECKS=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
