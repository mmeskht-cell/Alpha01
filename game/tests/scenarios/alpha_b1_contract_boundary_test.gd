extends SceneTree
## Authored D1 offer -> D4 due/extension -> D5 delivery -> D6 factual news.
## The new profile uses real VKC transfers only, no minute-spending or mint.
const B1 = preload("res://src/content/alpha_b1_seed.gd")
const B2 = preload("res://src/content/alpha_b2_seed.gd")
const Session = preload("res://src/domain/game_session.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
const Story = preload("res://src/domain/alpha_story_projection.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", name)

func fresh(data: Dictionary) -> RefCounted:
	var s := Session.new()
	if data.is_empty() or not s.initialize(data.defs, data.state, false, false, {}, data.alpha_profile):
		printerr("ALPHA_CONTRACT_INIT ", s.initialization_error())
		return null
	return s

func cmd(s: RefCounted, kind: String, p: Dictionary = {}) -> Dictionary:
	return {"action_id": "contract_case_" + str(s.snapshot().revision + 1), "expected_revision": s.snapshot().revision, "type": kind, "payload": p}

func go(s: RefCounted, kind: String, p: Dictionary = {}) -> bool:
	var response: Dictionary = s.execute(cmd(s, kind, p))
	return bool(response.ok)

func deny(s: RefCounted, kind: String, p: Dictionary = {}) -> bool:
	var before: Dictionary = s.snapshot()
	var response: Dictionary = s.execute(cmd(s, kind, p))
	return not response.ok and s.snapshot() == before

func terms() -> Dictionary:
	return {"contract_id": "rad1_first"}

func next_visitor(s: RefCounted) -> String:
	if not go(s, "alpha_next_customer") or not go(s, "alpha_ack_entry"):
		return ""
	return str(s.alpha_view().active.get("actor_id", ""))

func depart(s: RefCounted) -> bool:
	return go(s, "alpha_finish_customer") and go(s, "alpha_ack_exit")

func short_day(s: RefCounted) -> bool:
	return go(s, "alpha_open") and go(s, "alpha_close") and go(s, "alpha_settle")

func prepare(s: RefCounted) -> bool:
	return go(s, "alpha_next_day") and go(s, "alpha_prepare_day")

func trade(s: RefCounted, visit_id: String, item_id: String, seller: String, buyer: String, amount: int) -> bool:
	var buying: bool = buyer == "player"
	var p: Dictionary = {"visit_id": visit_id, "item_id": item_id, "seller": seller, "buyer": buyer,
		"currency": "VKC", "amount": amount, "inventory": "player_stock" if buying else buyer + "_grid",
		"x": 0 if buying else 5, "y": 0 if buying else 4, "rotated": false}
	return go(s, "alpha_trade", p) and go(s, "alpha_ack_exit")

func run_missed() -> void:
	var declined: RefCounted = fresh(B1.content())
	check(declined != null, "B1 fresh contract profile")
	if declined == null:
		quit(1)
		return
	check(declined.alpha_view().contracts.is_empty(), "unmet contract hidden before Marcus visit")
	check(short_day(declined), "declined opportunity day one closing")
	var early: Dictionary = declined.snapshot()
	check(early.alpha_shop.contracts.rows.rad1_first.status == "missed" and early.wallets.player.VKC == 180, "missed supplier creates no debt")
	check(deny(declined, "alpha_contract_pay", terms()), "no payment without accepted contract")
	for day: int in range(2, 7):
		check(prepare(declined) and short_day(declined), "missed-only path D" + str(day))
	check(declined.snapshot().alpha_shop.contracts.facts.is_empty(), "no fictional defaulted news for unaccepted offer")

	var refused: RefCounted = fresh(B1.content())
	check(refused != null and go(refused,"alpha_open"), "explicit decline setup")
	if refused != null:
		for visit_index: int in range(int(refused.alpha_view().remaining)):
			var actor: String = next_visitor(refused)
			if actor == "marcus":
				check(go(refused,"alpha_contract_decline",terms()) and deny(refused,"alpha_contract_accept",terms()), "declined offer cannot be revived")
			check(depart(refused), "decline path departs " + actor)
		check(go(refused,"alpha_close") and go(refused,"alpha_settle"), "decline path settles once")
		check(refused.snapshot().alpha_shop.contracts.rows.rad1_first.status == "declined" and refused.snapshot().wallets.player.VKC == 180, "explicit refusal has no automatic debt")

func run_unpaid() -> void:
	var unpaid: RefCounted = fresh(B1.content())
	check(unpaid != null and go(unpaid, "alpha_open"), "unpaid branch opens")
	if unpaid == null:
		quit(1)
		return
	var reached_marcus: bool = false
	for visit_index: int in range(int(unpaid.alpha_view().remaining)):
		var actor: String = next_visitor(unpaid)
		if actor == "marcus":
			reached_marcus = true
			check(unpaid.alpha_view().contracts.rad1_first.status == "offered", "contract offered on actual named visit")
			check(deny(unpaid, "alpha_contract_accept", {"contract_id":"wrong"}), "forged ID rejected")
			check(go(unpaid, "alpha_contract_accept", terms()), "explicit contract acceptance")
			check(deny(unpaid, "alpha_contract_accept", terms()), "double acceptance denied")
		check(depart(unpaid), "counter departure " + actor)
	check(reached_marcus and go(unpaid,"alpha_close") and go(unpaid,"alpha_settle"), "D1 accepted contract closing")
	check(unpaid.snapshot().alpha_shop.contracts.rows.rad1_first.status == "reserved", "reservation survives Day1 close")
	for day: int in range(2, 5):
		check(prepare(unpaid) and go(unpaid,"alpha_open") and go(unpaid,"alpha_close"), "advance to D" + str(day))
		if day == 4:
			check(deny(unpaid,"alpha_contract_pay",terms()), "cannot pay 300 from 180 VKC")
		check(go(unpaid,"alpha_settle"), "settle day " + str(day))
	check(unpaid.snapshot().alpha_shop.contracts.rows.rad1_first.status == "defaulted", "D4 close defaults once")
	var before_story: Dictionary = unpaid.snapshot()
	check(Story.view(before_story).fact_key == "b2.story.s03.default" and unpaid.snapshot() == before_story, "S03 default notice follows real D4 settlement without mutating contract")
	check(unpaid.snapshot().receipt_archive.size() > 0, "alpha commands compact into archived receipts after 32")
	check(unpaid.snapshot().wallets.player.VKC == 180 and unpaid.snapshot().alpha_shop.contracts.settlements.is_empty(), "unpaid branch never mints or deducts money")
	check(prepare(unpaid) and short_day(unpaid) and prepare(unpaid), "D5 then D6 factual publication")
	check(Story.view(unpaid.snapshot()).fact_key.is_empty(), "S03 D4-D5 notice never impersonates D6 news")
	check(unpaid.snapshot().alpha_shop.contracts.facts.has("rad1_defaulted"), "D6 default news only from actual default")
	var before_archive_retry: Dictionary = unpaid.snapshot()
	check(unpaid.execute(before_archive_retry.alpha_shop.commands[0]).ok and unpaid.snapshot() == before_archive_retry, "archived alpha action idempotent replay")
	var default_fact: Dictionary = unpaid.snapshot().alpha_shop.contracts.facts.rad1_defaulted
	check(not default_fact.cause_action.is_empty() and default_fact.day == 6, "default news has one source event")
	var store := Repo.new("user://zt_rebuild/alpha_contract_case_" + str(Time.get_ticks_usec()))
	check(store.save_session(unpaid,"contract").ok, "A/B save dated default")
	var cold: RefCounted = fresh(B1.content())
	check(cold != null and store.load_session(cold,"contract").ok and cold.snapshot() == unpaid.snapshot(), "cold replay of contract and factual news")
	if cold != null:
		var forged: Dictionary = cold.snapshot()
		forged.alpha_shop.contracts.facts.rad1_defaulted.cause_action = "forged"
		check(not cold.restore(forged), "falsified news rejected by seed replay")

func run_extension() -> void:
	var extension: RefCounted = fresh(B1.content())
	check(extension != null and go(extension,"alpha_open"), "extension branch setup")
	if extension != null:
		for visit_index: int in range(int(extension.alpha_view().remaining)):
			var actor: String = next_visitor(extension)
			if actor == "marcus":
				check(go(extension,"alpha_contract_accept",terms()), "extension branch original acceptance")
			check(depart(extension), "extension branch D1 visit " + actor)
		check(go(extension,"alpha_close") and go(extension,"alpha_settle"), "extension D1 settled")
		for day: int in range(2, 5):
			check(prepare(extension) and go(extension,"alpha_open") and go(extension,"alpha_close"), "extension path D" + str(day))
			if day == 4:
				check(go(extension,"alpha_contract_extend",terms()), "D4 one authored extension to D5")
				check(deny(extension,"alpha_contract_extend",terms()), "no second extension")
			check(go(extension,"alpha_settle"), "extension date settlement")
		check(extension.snapshot().alpha_shop.contracts.rows.rad1_first.status == "reserved" and extension.snapshot().alpha_shop.contracts.rows.rad1_first.due_day == 5, "D4 accepted extension cannot auto-default")
		check(prepare(extension) and short_day(extension), "unpaid extended D5 closes")
		check(extension.snapshot().alpha_shop.contracts.rows.rad1_first.status == "defaulted" and extension.snapshot().wallets.player.VKC == 180, "extended deadline enforced without extra money")

func run_paid() -> void:
	var paid: RefCounted = fresh(B2.content())
	check(paid != null and go(paid,"alpha_open"), "B2 real-wallet payment branch")
	if paid == null:
		quit(1)
		return
	check(next_visitor(paid) == "G01" and Story.view(paid.snapshot()).speech_key == "b2.story.s01.g01" and trade(paid,"visit_g01","R001","G01","player",100), "S01 greeting bound to real G01 and R001")
	check(go(paid,"alpha_display",{"item_id":"R001","x":0,"y":0,"rotated":false}), "R001 physical listing")
	check(next_visitor(paid) == "G02" and trade(paid,"visit_g02_buy","R001","player","G02",170), "real G02 display purchase")
	check(next_visitor(paid) == "G03" and depart(paid), "unserved wholesale does not mint cash")
	check(next_visitor(paid) == "marcus" and go(paid,"alpha_contract_accept",terms()) and depart(paid), "named supplier explicit accepted offer")
	check(go(paid,"alpha_close") and go(paid,"alpha_settle") and paid.snapshot().wallets.player.VKC == 250, "D1 wallet 250 from two actual trades")
	check(prepare(paid) and go(paid,"alpha_open"), "paid path D2 opens")
	check(next_visitor(paid) == "G03" and depart(paid), "unsourced R001 resale skipped")
	check(next_visitor(paid) == "G04" and trade(paid,"watch_a","WAT02","G04","player",80), "actual watch purchase")
	check(go(paid,"alpha_display",{"item_id":"WAT02","x":0,"y":0,"rotated":false}), "watch must be displayed")
	check(next_visitor(paid) == "G05" and trade(paid,"watch_sale","WAT02","player","G05",140), "real watch sale funds contract")
	for visit_index: int in range(int(paid.alpha_view().remaining)):
		check(not next_visitor(paid).is_empty() and depart(paid), "remaining D2 visitor declines")
	check(go(paid,"alpha_close") and go(paid,"alpha_settle"), "D2 closes once")
	check(paid.snapshot().wallets.player.VKC == 310, "D1+D2 purchases and sales total 310 VKC")
	check(prepare(paid) and short_day(paid), "D3 skipped without bonus")
	check(prepare(paid) and go(paid,"alpha_open") and go(paid,"alpha_close"), "D4 exact close boundary")
	check(go(paid,"alpha_contract_pay",terms()), "real 300 VKC supplier transfer")
	var settled: Dictionary = paid.snapshot()
	check(settled.wallets.player.VKC == 10 and settled.wallets.marcus.VKC == 300 and settled.alpha_shop.contracts.settlements.size() == 1, "money conservation and exactly one payment")
	check(Story.view(settled).fact_key == "b2.story.s03.paid" and paid.snapshot() == settled, "S03 paid-but-not-delivered notice derives from actual 300 VKC transfer")
	check(deny(paid,"alpha_contract_pay",terms()) and deny(paid,"alpha_contract_extend",terms()), "no repeat payment or extension after paid")
	check(go(paid,"alpha_settle") and paid.snapshot().alpha_shop.contracts.rows.rad1_first.status == "paid", "paid status survives D4")
	check(prepare(paid) and short_day(paid), "D5 delivery settlement")
	check(paid.snapshot().alpha_shop.contracts.rows.rad1_first.status == "delivered" and paid.snapshot().alpha_shop.contracts.settlements.size() == 2, "authored D5 external supply event, no free item")
	check(Story.view(paid.snapshot()).fact_key.is_empty(), "S03 paid reservation notice disappears upon actual D5 delivery")
	check(not paid.snapshot().items.has("rad1_supply_1") and paid.snapshot().wallets.player.VKC == 10, "delivery is external service, not invented stock")
	check(prepare(paid) and paid.snapshot().alpha_shop.contracts.facts.has("rad1_delivered"), "D6 story fact published from actual D5 event")
	check(not paid.snapshot().alpha_shop.contracts.facts.has("rad1_defaulted"), "paid contract cannot emit default branch")
	check(paid.snapshot().game_minutes == 7200 and not paid.clock_view().has("hour"), "date bridge only, never exposed clock")

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or args[0] not in ["missed", "unpaid", "extension", "paid"]:
		printerr("ALPHA_B1_DATE_TEST_PART_REQUIRED")
		quit(2)
		return
	match args[0]:
		"missed": run_missed()
		"unpaid": run_unpaid()
		"extension": run_extension()
		"paid": run_paid()
	print("ALPHA_B1_DATED_CONTRACT_CHECKS part=", args[0], " checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
