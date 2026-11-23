extends SceneTree
## B3-M7: four extra late-week customers are backed by existing wallets,
## historical quotes and the SAME already-owned item IDs. Missing inventory
## is an honest absent visitor, not an opportunity to fabricate a sale.
const Source = preload("res://src/content/alpha_b3_m7_interest_seed.gd")
const M5 = preload("res://src/content/alpha_b3_random_runtime_seed.gd")
const Interest = preload("res://src/domain/alpha_b3_market_interest.gd")
const Shop = preload("res://src/domain/alpha_shop_cycle.gd")
const Session = preload("res://src/domain/game_session.gd")
const Repo = preload("res://src/persistence/save_repository.gd")

const NEW_VISITS: Array = [
	"alpha_b3_g11_battery_d5", "alpha_b3_g08_watch_d6",
	"alpha_b3_g02_electronics_d7", "alpha_b3_g12_tool_d7"
]
const WATCH_BUYER: String = "alpha_b3_g08_watch_d6"
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
	return ok

func done() -> void:
	print("ALPHA_B3_M7_FINITE_INTEREST_CHECKS=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

func fresh(src: Dictionary) -> RefCounted:
	var s := Session.new()
	if not s.initialize(src.defs, src.state, false, false, {}, src.alpha_profile):
		printerr("M7_INIT ", s.initialization_error())
		return null
	return s

func command(s: RefCounted, kind: String, p: Dictionary = {}) -> Dictionary:
	var revision: int = int(s.snapshot().revision)
	return {"action_id": "b3_m7_" + str(revision + 1),
		"expected_revision": revision, "type": kind, "payload": p}

func go(s: RefCounted, kind: String, p: Dictionary = {}) -> bool:
	var r: Dictionary = s.execute(command(s, kind, p))
	if not r.get("ok", false):
		printerr("M7_COMMAND ", kind, " ", r)
	return bool(r.get("ok", false))

func names(rows: Array) -> Array:
	var list: Array = []
	for row: Dictionary in rows:
		list.append(str(row.id))
	return list

func summed(wallets: Dictionary, currency: String) -> int:
	var total: int = 0
	for actor: String in wallets:
		total += int(wallets[actor].get(currency, 0))
	return total

func advance(s: RefCounted, last: bool) -> bool:
	if not (go(s, "alpha_close") and go(s, "alpha_settle") and go(s, "alpha_next_day")):
		return false
	return true if last else go(s, "alpha_prepare_day")

func _initialize() -> void:
	var legacy: Dictionary = M5.content(101)
	var src: Dictionary = Source.content(101)
	if not check(not legacy.is_empty() and not src.is_empty(),
		"source add-on can be constructed without altering M5 economics"):
		done()
		return
	check(src.state.wallets == legacy.state.wallets and src.state.items == legacy.state.items
		and src.state.ledger == legacy.state.ledger and src.defs == legacy.defs,
		"four extra interests do not seed wallets, stock, money, ledger or object definitions")
	check(src.state.visits.size() == legacy.state.visits.size() + 4
		and src.alpha_profile.market_interest.version == 3
		and src.alpha_profile.market_interest.offers.size() == 12
		and src.alpha_profile.market_extension == Interest.M7_MARKER,
		"only four existing-actor interest rows are added under explicit new save binding")
	var expected_days: Array = [5, 7, 6, 6, 5, 5, 5]
	for day: int in range(7):
		check(src.alpha_profile.days[day].size() == int(expected_days[day]),
			"finite source has expected D" + str(day + 1) + " authored opportunities")
	for i: int in range(legacy.alpha_profile.market_interest.offers.size()):
		check(src.alpha_profile.market_interest.offers[i] == legacy.alpha_profile.market_interest.offers[i],
			"original eight M2/M5 market source offers are completely retained")
	for visit_id: String in NEW_VISITS:
		var row: Dictionary = src.state.visits.get(visit_id, {})
		if not check(not row.is_empty() and row.seller == "player" and not row.scope.completed,
			"new optional visit is a finite actual-player-sale offer " + visit_id):
			done()
			return
		var item_id: String = str(row.prices.keys()[0])
		check(legacy.state.items.has(item_id) and legacy.state.wallets.has(row.buyer)
			and not legacy.state.visits.has(visit_id),
			"new visitor uses preexisting buyer funds and physical item, not a new object")
		var matched: bool = false
		for offer: Dictionary in src.alpha_profile.market_interest.offers:
			if str(offer.visit_id) == visit_id:
				var source_visit: Dictionary = legacy.state.visits[offer.quote_source_visit_id]
				matched = source_visit.prices[offer.item_id] == row.prices[offer.item_id] and source_visit.buyer != row.buyer
				break
		check(matched, "new purchase price is an immutable old counter quote for a different buyer")
	check(Shop.profile_valid(src.alpha_profile, src.state)
		and Shop.profile_valid(legacy.alpha_profile, legacy.state),
		"both private addon and unchanged original seed pass authority checks")
	var forged: Dictionary = src.duplicate(true)
	forged.alpha_profile.market_interest.offers[8].actor_id = "fake_wallet"
	check(not Shop.profile_valid(forged.alpha_profile, forged.state),
		"an unauthored customer identity cannot pass strict extension profile binding")
	forged = src.duplicate(true)
	forged.state.visits[WATCH_BUYER].prices.WAT02.VKC = 1
	check(not Shop.profile_valid(forged.alpha_profile, forged.state),
		"changing a quote to invent purchasing power is not permitted")
	forged = src.duplicate(true)
	forged.alpha_profile.erase("market_extension")
	check(not Shop.profile_valid(forged.alpha_profile, forged.state),
		"addon row set cannot masquerade as an old M5 save")
	check(Source.content(0).is_empty(), "invalid RNG seed rejected for extension as for M5")

	# A completely missed market day must NOT attract supposedly funded
	# buyers when their goods are still physically owned by an NPC.
	var empty: RefCounted = fresh(src)
	if not check(empty != null, "extended source boots a real seeded GameSession"):
		done()
		return
	var original: Dictionary = empty.snapshot()
	for visit_id: String in NEW_VISITS:
		check(not Interest.eligible(original, visit_id),
			"unacquired or undisplayed physical stock cannot attract " + visit_id)
	for day: int in range(1, 8):
		if not check(go(empty, "alpha_open"), "no-trade source opens D" + str(day)):
			done()
			return
		var plan: Array = empty.snapshot().alpha_shop.random_visits.plan
		var extras: Array = []
		for id: String in NEW_VISITS:
			if id in plan:
				extras.append(id)
		check(extras.is_empty(),
			"empty inventory never creates four artificial optional buyers D" + str(day))
		if not check(advance(empty, day == 7), "no-trade source can complete D" + str(day)):
			done()
			return
	check(empty.snapshot().wallets == original.wallets
		and empty.snapshot().items == original.items
		and empty.snapshot().ledger == original.ledger,
		"seven-day no-sale path cannot create funds or stock")

	# An independent REAL trader branch: old D2 seller -> original item WAT02
	# -> physical shelf -> NEW D6 buyer with 140 VKC initial budget.
	var s: RefCounted = fresh(src)
	if not check(s != null, "paid M7 campaign initializes independently"):
		done()
		return
	var initial: Dictionary = s.snapshot()
	if not check(go(s, "alpha_open") and advance(s, false),
		"D1 no-trade permits a D2 funded physical watch purchase"):
		done()
		return
	if not check(go(s, "alpha_open") and "watch_a" in s.snapshot().alpha_shop.random_visits.plan,
		"real authored D2 watch seller is admitted by the seeded finite plan"):
		done()
		return
	var acquired: bool = false
	while int(s.alpha_view().remaining) > 0:
		if not (go(s, "alpha_next_customer") and go(s, "alpha_ack_entry")):
			check(false, "real D2 visitor admission")
			done()
			return
		var visit_id: String = str(s.alpha_view().active.id)
		if visit_id == "watch_a":
			if not (go(s, "alpha_price_offer", {"amount": 80})
				and go(s, "alpha_trade", {"visit_id": "watch_a",
					"item_id": "WAT02", "seller": "G04", "buyer": "player",
					"currency": "VKC", "amount": 80, "inventory": "player_stock",
					"x": 0, "y": 0, "rotated": false})
				and go(s, "alpha_ack_exit")):
				check(false, "existing D2 watch actually acquired for 80 VKC")
				done()
				return
			acquired = true
		elif not (go(s, "alpha_finish_customer") and go(s, "alpha_ack_exit")):
			check(false, "D2 other customer leaves")
			done()
			return
	if not check(acquired and s.snapshot().items.WAT02.owner_id == "player"
		and s.snapshot().ledger.size() == 1,
		"real money and ownership move exactly once for the original watch"):
		done()
		return
	check(not Interest.eligible(s.snapshot(), WATCH_BUYER),
		"customer-owned until display: merely buying stock does not promise a resale")
	if not check(go(s, "alpha_display", {"item_id": "WAT02", "x": 0, "y": 0, "rotated": false})
		and Interest.eligible(s.snapshot(), WATCH_BUYER),
		"actual stocked shelf and G08's existing budget enable bounded D6 interest"):
		done()
		return
	if not check(advance(s, false), "paid D2 settles before D3"):
		done()
		return
	for day: int in range(3, 6):
		if not check(go(s, "alpha_open") and advance(s, false),
			"D" + str(day) + " can close without accidentally selling reserved watch"):
			done()
			return
	if not check(go(s, "alpha_open") and WATCH_BUYER in s.snapshot().alpha_shop.random_visits.plan,
		"new D6 optional buyer is actually selected only after real earlier supply"):
		done()
		return
	var sold: bool = false
	while int(s.alpha_view().remaining) > 0:
		if not (go(s, "alpha_next_customer") and go(s, "alpha_ack_entry")):
			check(false, "D6 actual seeded visitor admission")
			done()
			return
		var current: String = str(s.alpha_view().active.id)
		if current == WATCH_BUYER:
			if not (go(s, "alpha_price_offer", {"amount": 140})
				and go(s, "alpha_trade", {"visit_id": WATCH_BUYER,
					"item_id": "WAT02", "seller": "player", "buyer": "G08",
					"currency": "VKC", "amount": 140, "inventory": "G08_grid",
					"x": 6, "y": 4, "rotated": false})
				and go(s, "alpha_ack_exit")):
				check(false, "real new D6 buyer pays original sourced 140 VKC price")
				done()
				return
			sold = true
		elif not (go(s, "alpha_finish_customer") and go(s, "alpha_ack_exit")):
			check(false, "D6 other visitor leaves")
			done()
			return
	var after: Dictionary = s.snapshot()
	if not check(sold and after.items.WAT02.owner_id == "G08"
		and after.items.WAT02.inventory == "G08_grid"
		and after.items.size() == initial.items.size() and after.ledger.size() == 2,
		"same physical watch changes owners, no duplicated stock or receipt"):
		done()
		return
	check(int(after.wallets.player.VKC) == int(initial.wallets.player.VKC) + 60
		and int(after.wallets.G04.VKC) == int(initial.wallets.G04.VKC) + 80
		and int(after.wallets.G08.VKC) == int(initial.wallets.G08.VKC) - 140,
		"old D2 acquisition 80 and new D6 resale 140 are actual currency transfers")
	check(summed(after.wallets, "VKC") == summed(initial.wallets, "VKC")
		and summed(after.wallets, "USD") == summed(initial.wallets, "USD"),
		"entire shop and all actor currency remains conserved")
	var before_duplicate: Dictionary = s.snapshot()
	check(not s.execute(command(s, "alpha_trade", {"visit_id": WATCH_BUYER,
			"item_id": "WAT02", "seller": "player", "buyer": "G08",
			"currency": "VKC", "amount": 140, "inventory": "G08_grid",
			"x": 6, "y": 4, "rotated": false})).get("ok", false)
		and s.snapshot() == before_duplicate,
		"paid resale cannot settle twice")
	var store := Repo.new("user://zt_rebuild/b3_m7_fin_" + str(Time.get_ticks_usec()))
	check(store.save_session(s, "m7_interest").get("ok", false),
		"paid M7 plan saved to an isolated A/B slot")
	var cold: RefCounted = fresh(src)
	check(cold != null and store.load_session(cold, "m7_interest").get("ok", false)
		and cold.snapshot() == s.snapshot(),
		"cold reload preserves new D6 buyer, both actual receipts and exact plan")
	if not check(advance(s, false) and go(s, "alpha_open") and advance(s, true),
		"paid campaign reaches D7 and finite completion"):
		done()
		return
	var complete: Dictionary = s.snapshot()
	check(complete.alpha_shop.phase == "COMPLETE" and complete.wallets == after.wallets
		and complete.items == after.items and complete.ledger == after.ledger,
		"no extra transfer or income appears during terminal close")
	check(store.save_session(s, "m7_interest").get("ok", false),
		"complete economic history saved as second A/B generation")
	cold = fresh(src)
	check(cold != null and store.load_session(cold, "m7_interest").get("ok", false)
		and cold.snapshot() == complete and cold.alpha_view() == s.alpha_view(),
		"seven-day cold restore retains same paid economic and visitor history")
	done()
