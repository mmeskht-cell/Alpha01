extends SceneTree
## B3-M6: one genuinely funded purchase and later resale on a randomized
## persisted shop calendar, then seven-day completion and A/B cold replay.
## No new actor, item, price, currency, contract, or story is authored here.
const Source = preload("res://src/content/alpha_b3_random_runtime_seed.gd")
const Planner = preload("res://src/domain/alpha_b3_visit_randomizer.gd")
const Interest = preload("res://src/domain/alpha_b3_market_interest.gd")
const Commission = preload("res://src/domain/alpha_commission.gd")
const Custody = preload("res://src/domain/alpha_service_custody.gd")
const Session = preload("res://src/domain/game_session.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
const BUYER: String = "alpha_b3_g09_radio_d2"
const ITEM: String = "R001"
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
	return ok

func done() -> void:
	print("ALPHA_B3_M6_REAL_TRADE_CHECKS=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

func fresh(src: Dictionary) -> RefCounted:
	var s := Session.new()
	if not s.initialize(src.defs, src.state, false, false, {}, src.alpha_profile):
		printerr("M6_INIT ", s.initialization_error())
		return null
	return s

func command(s: RefCounted, kind: String, p: Dictionary = {}) -> Dictionary:
	var rev: int = int(s.snapshot().revision)
	return {"action_id": "b3_m6_real_" + str(rev + 1),
		"expected_revision": rev, "type": kind, "payload": p}

func go(s: RefCounted, kind: String, p: Dictionary = {}) -> bool:
	var result: Dictionary = s.execute(command(s, kind, p))
	if not result.get("ok", false):
		printerr("M6_COMMAND ", kind, " ", result)
	return bool(result.get("ok", false))

func trade(visit_id: String, seller: String, buyer: String, amount: int, inventory: String, x: int, y: int) -> Dictionary:
	return {"visit_id": visit_id, "item_id": ITEM, "seller": seller,
		"buyer": buyer, "currency": "VKC", "amount": amount,
		"inventory": inventory, "x": x, "y": y, "rotated": false}

func ids(rows: Array) -> Array:
	var found: Array = []
	for row: Dictionary in rows:
		found.append(str(row.id))
	return found

func wallet_total(wallets: Dictionary, currency: String) -> int:
	var sum: int = 0
	for wallet: Dictionary in wallets.values():
		sum += int(wallet.get(currency, 0))
	return sum

## Select a fixed-seed witness from REAL authored rows, rather than assuming
## the original first customer or a prospective buyer will always be drawn.
## No session gets a free item or a speculative buyer from this selection.
func find_witness() -> int:
	var baseline: Dictionary = Source.content(101)
	if baseline.is_empty():
		return 0
	var profile: Dictionary = baseline.alpha_profile
	var d1: Array = profile.days[0]
	var d2: Array = profile.days[1]
	var flags1: Dictionary = {}
	var flags2: Dictionary = {}
	for row: Dictionary in d1:
		flags1[str(row.id)] = true
	for row: Dictionary in d2:
		var visit_id: String = str(row.id)
		var conditional_return: bool = Commission.is_return_visit(visit_id, str(profile.commission_profile_id)) or Custody.is_return_visit(visit_id, str(profile.service_profile_id))
		# Only the already-authored G09 buyer has become eligible because
		# R001 was actually purchased and displayed by the D1 player.
		flags2[visit_id] = not conditional_return and (not visit_id.begins_with("alpha_b3_") or visit_id == BUYER)
	for seed: int in range(101, 1101):
		var first: Dictionary = Planner.plan(d1, flags1,
			["alpha_marcus_intro", "alpha_ian_hygiene_offer_d1"], seed, 1)
		var second: Dictionary = Planner.plan(d2, flags2, [], seed, 2)
		if first.get("ok", false) and second.get("ok", false) and "visit_g01" in ids(first.visits) and BUYER in ids(second.visits):
			return seed
	return 0

func serve_day(s: RefCounted, day: int) -> bool:
	var traded: bool = false
	while int(s.alpha_view().remaining) > 0:
		if not (go(s, "alpha_next_customer") and go(s, "alpha_ack_entry")):
			return false
		var visit_id: String = str(s.alpha_view().active.id)
		if (day == 1 and visit_id == "visit_g01") or (day == 2 and visit_id == BUYER):
			var amount: int = 100 if day == 1 else 130
			var p: Dictionary = trade("visit_g01", "G01", "player", 100, "player_stock", 0, 0) if day == 1 else trade(BUYER, "player", "G09", 130, "G09_grid", 5, 4)
			if not (go(s, "alpha_price_offer", {"amount": amount}) and go(s, "alpha_trade", p) and go(s, "alpha_ack_exit")):
				return false
			traded = true
		else:
			if not (go(s, "alpha_finish_customer") and go(s, "alpha_ack_exit")):
				return false
	return check(traded, "one actual priced R001 transaction on D" + str(day))

func advance(s: RefCounted, is_final: bool = false) -> bool:
	if not (go(s, "alpha_close") and go(s, "alpha_settle") and go(s, "alpha_next_day")):
		return false
	return true if is_final else go(s, "alpha_prepare_day")

func _initialize() -> void:
	var seed: int = find_witness()
	if not check(seed >= 101, "a deterministic seeded schedule can admit genuine D1 purchase and D2 buyer"):
		done()
		return
	var src: Dictionary = Source.content(seed)
	var s: RefCounted = fresh(src)
	if not check(s != null, "M5 opt-in profile starts unchanged finite market"):
		done()
		return
	var initial: Dictionary = s.snapshot()
	check(initial.items.R001.owner_id == "G01"
		and int(initial.wallets.player.VKC) >= 100
		and int(initial.wallets.G09.VKC) >= 130
		and int(initial.visits[BUYER].prices.R001.VKC) == 130,
		"real G01 stock, player purchase funds, G09 resale budget and original quote")
	check(not Interest.eligible(initial, BUYER),
		"future buyer is not eligible until the real radio is owned and displayed")
	if not check(go(s, "alpha_open") and "visit_g01" in s.snapshot().alpha_shop.random_visits.plan,
		"actual persisted D1 random draw includes real seller"):
		done()
		return
	var d1_plan: Array = s.snapshot().alpha_shop.random_visits.plan.duplicate()
	if not check(serve_day(s, 1), "day one handles and settles real purchase"):
		done()
		return
	check(s.snapshot().alpha_shop.random_visits.plan == d1_plan
		and s.snapshot().ledger.size() == 1 and s.snapshot().items.R001.owner_id == "player",
		"serving the actual customer preserves the frozen plan and a single paid item")
	check(not Interest.eligible(s.snapshot(), BUYER),
		"acquired stock does not attract the D2 buyer before physical display")
	if not check(go(s, "alpha_display", {"item_id": ITEM, "x": 0, "y": 0, "rotated": false}),
		"real purchased radio can be placed on the physical shelf"):
		done()
		return
	check(Interest.eligible(s.snapshot(), BUYER),
		"genuine funded G09 buyer becomes eligible, without minted cash or stock")
	if not check(advance(s) and go(s, "alpha_open"), "D2 starts from paid D1 economic consequences"):
		done()
		return
	var d2_plan: Array = s.snapshot().alpha_shop.random_visits.plan.duplicate()
	if not check(BUYER in d2_plan and Interest.eligible(s.snapshot(), BUYER),
		"D2 persisted random draw includes eligible existing G09 buyer"):
		done()
		return
	if not check(serve_day(s, 2), "day two sells the actual same radio item"):
		done()
		return
	var sold: Dictionary = s.snapshot()
	check(sold.items.R001.owner_id == "G09" and sold.items.R001.inventory == "G09_grid"
		and sold.items.size() == initial.items.size() and sold.ledger.size() == 2,
		"same R001 leaves the real shelf and ledger records two settlements, never cloning")
	check(int(sold.wallets.player.VKC) == int(initial.wallets.player.VKC) + 30
		and int(sold.wallets.G01.VKC) == int(initial.wallets.G01.VKC) + 100
		and int(sold.wallets.G09.VKC) == int(initial.wallets.G09.VKC) - 130,
		"buyer pays 130 VKC for the earlier 100 VKC purchase; both actors' balances match")
	check(wallet_total(sold.wallets, "VKC") == wallet_total(initial.wallets, "VKC")
		and wallet_total(sold.wallets, "USD") == wallet_total(initial.wallets, "USD"),
		"real trading preserves finite global VKC and USD balances")
	var before_retry: Dictionary = s.snapshot()
	check(not s.execute(command(s, "alpha_trade", trade(BUYER, "player", "G09", 130, "G09_grid", 5, 4))).get("ok", false)
		and s.snapshot() == before_retry,
		"second sale after actual settlement cannot create another receipt or money")
	var store := Repo.new("user://zt_rebuild/b3_m6_real_" + str(Time.get_ticks_usec()))
	check(store.save_session(s, "m6_real").get("ok", false),
		"paid D2 randomized schedule fits existing A/B save")
	var cold: RefCounted = fresh(src)
	check(cold != null and store.load_session(cold, "m6_real").get("ok", false)
		and cold.snapshot() == s.snapshot() and cold.alpha_view() == s.alpha_view(),
		"mid-week cold restore keeps buyer history, money and frozen visit order")
	if not check(advance(s), "paid D2 can end and prepare next day"):
		done()
		return
	for day: int in range(3, 8):
		if not check(go(s, "alpha_open"), "D" + str(day) + " opens exactly once"):
			done()
			return
		var frozen: Array = s.snapshot().alpha_shop.random_visits.plan.duplicate()
		check(int(s.snapshot().alpha_shop.random_visits.day) == day
			and int(s.snapshot().alpha_shop.random_visits.target) >= 5
			and int(s.snapshot().alpha_shop.random_visits.target) <= 8,
			"real shop tracks the finite frozen plan, not a guaranteed 5–8 turnout")
		if day == 5:
			check("hygiene_buy" in frozen and "hygiene_sale" not in frozen,
				"unsolicited Ian pickup cannot appear; original D5 supply access stays protected")
		if not check(advance(s, day == 7), "D" + str(day) + " closes without phantom sales"):
			done()
			return
	var final_state: Dictionary = s.snapshot()
	check(final_state.alpha_shop.day == 7 and final_state.alpha_shop.phase == "COMPLETE"
		and final_state.wallets == sold.wallets
		and final_state.items == sold.items
		and final_state.ledger == sold.ledger,
		"seven days finish without post-trade asset creation or double settlement")
	check(store.save_session(s, "m6_real").get("ok", false),
		"seven-day paid economic replay fits A/B save")
	cold = fresh(src)
	check(cold != null and store.load_session(cold, "m6_real").get("ok", false)
		and cold.snapshot() == final_state and cold.alpha_view() == s.alpha_view(),
		"final cold replay preserves the exact actual two-trade seven-day history")
	done()
