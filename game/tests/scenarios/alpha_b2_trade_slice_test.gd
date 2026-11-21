extends SceneTree
const Seed = preload("res://src/content/alpha_b2_seed.gd")
const Session = preload("res://src/domain/game_session.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", name)

func fresh() -> RefCounted:
	var data: Dictionary = Seed.content()
	var session := Session.new()
	if data.is_empty() or not session.initialize(data.defs, data.state, false, false, {}, data.alpha_profile):
		printerr("B2 seed: ", session.initialization_error())
		return null
	return session

func cmd(s: RefCounted, name: String, p: Dictionary = {}) -> Dictionary:
	return {"action_id": "b2_" + str(s.snapshot().revision + 1), "expected_revision": s.snapshot().revision, "type": name, "payload": p}

func go(s: RefCounted, name: String, p: Dictionary = {}) -> bool:
	return bool(s.execute(cmd(s, name, p)).ok)

func deny(s: RefCounted, name: String, p: Dictionary = {}) -> bool:
	var before: Dictionary = s.snapshot()
	return not s.execute(cmd(s, name, p)).ok and before == s.snapshot()

func trade(visit: String, seller: String, buyer: String, inventory: String, amount: int, x: int, y: int) -> Dictionary:
	return {"visit_id":visit, "item_id":"R001", "seller":seller, "buyer":buyer, "currency":"VKC", "amount":amount, "inventory":inventory, "x":x, "y":y, "rotated":false}

func _initialize() -> void:
	var s: RefCounted = fresh()
	check(s != null, "B2 opt-in seed")
	if s == null:
		quit(1)
		return
	var start: Dictionary = s.snapshot()
	check(start.items.R001.owner_id == "G01" and start.wallets.player.VKC == 180, "existing finite objects and money")
	check(deny(s, "alpha_trade", trade("visit_g01","G01","player","player_stock",100,0,0)), "no trade without active visit")
	check(go(s, "alpha_open") and go(s, "alpha_next_customer") and go(s, "alpha_ack_entry"), "actual customer one")
	check(deny(s, "alpha_trade", trade("visit_g02_buy","player","G02","G02_grid",170,5,4)), "no future visit")
	check(deny(s, "alpha_trade", trade("visit_g01","G01","player","player_stock",99,0,0)), "fixed-price original terms protected")
	check(go(s, "alpha_trade", trade("visit_g01","G01","player","player_stock",100,0,0)), "actual purchase")
	var bought: Dictionary = s.snapshot()
	check(bought.wallets.player.VKC == 80 and bought.items.R001.owner_id == "player" and bought.ledger.size() == 1 and bought.alpha_shop.phase == "CUSTOMER_EXIT", "money and item ownership atomic")
	check(deny(s, "alpha_trade", trade("visit_g01","G01","player","player_stock",100,0,0)), "cannot trade twice with new ID")
	check(go(s, "alpha_ack_exit"), "customer one departs")
	var unlisted: RefCounted = fresh()
	check(unlisted != null and unlisted.restore(s.snapshot()), "separate saved pre-display branch")
	check(go(unlisted, "alpha_next_customer") and go(unlisted, "alpha_ack_entry"), "second customer without displayed stock")
	check(deny(unlisted, "alpha_trade", trade("visit_g02_buy","player","G02","G02_grid",170,5,4)), "cannot sell owned but unlisted stock")
	check(go(s, "alpha_display", {"item_id":"R001","x":0,"y":0,"rotated":false}), "physical placement on external shelf")
	check(s.snapshot().items.R001.inventory == "storefront_grid" and "R001" in s.snapshot().alpha_shop.displayed, "actual shelf identity")
	check(deny(s, "alpha_display", {"item_id":"R001","x":1,"y":0,"rotated":false}), "no double display")
	check(go(s, "alpha_next_customer") and go(s, "alpha_ack_entry"), "actual next customer")
	check(deny(s, "alpha_trade", trade("visit_g02_buy","player","G02","G02_grid",1,5,4)), "no arbitrary sale price")
	check(go(s, "alpha_trade", trade("visit_g02_buy","player","G02","G02_grid",170,5,4)), "actual displayed item sale")
	var sold: Dictionary = s.snapshot()
	check(sold.wallets.player.VKC == 250 and sold.wallets.G02.VKC == start.wallets.G02.VKC - 170 and sold.items.R001.owner_id == "G02", "real buyer budget and seller receipts")
	check(sold.ledger.size() == 2 and sold.alpha_shop.displayed.is_empty() and sold.items.R001.inventory == "G02_grid", "same ID physically transferred once")
	check(sold.items.R001.basis.VKC == 100, "purchase cost basis preserved after resale")
	check(deny(s, "alpha_trade", trade("visit_g02_buy","player","G02","G02_grid",170,5,4)), "second sale denied")
	check(go(s, "alpha_ack_exit") and go(s, "alpha_close") and go(s, "alpha_settle"), "closed after two transactions")
	check(s.snapshot().wallets.player.VKC == 250, "no fictional close bonuses")
	var store := Repo.new("user://zt_rebuild/b2_test_" + str(Time.get_ticks_usec()))
	check(store.save_session(s,"b2_slice").ok, "validated A/B save")
	var cold: RefCounted = fresh()
	check(cold != null and store.load_session(cold,"b2_slice").ok and cold.snapshot() == s.snapshot(), "full cold restore and replay")
	check(go(s, "alpha_next_day") and go(s, "alpha_prepare_day") and s.snapshot().game_minutes == 1440, "day-only business transition")
	print("ALPHA_B2_TRADE_SLICE_CHECKS=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
