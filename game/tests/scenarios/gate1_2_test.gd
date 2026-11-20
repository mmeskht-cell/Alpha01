extends SceneTree
const Session = preload("res://src/domain/game_session.gd")
const Catalog = preload("res://src/content/catalog_loader.gd")
const Opening = preload("res://src/domain/gate1_opening.gd")
const DayOne = preload("res://src/domain/day_one.gd")
var s: RefCounted
var checks: int = 0
var failures: int = 0
var serial: int = 0

func check(v: bool, label: String) -> void:
	checks += 1
	if not v:
		failures += 1
		printerr("FAIL: ", label)

func command(kind: String, p: Dictionary = {}) -> Dictionary:
	serial += 1
	return {"action_id": "day1_" + str(serial), "expected_revision": s.snapshot().revision, "type": kind, "payload": p}

func send(kind: String, p: Dictionary = {}) -> Dictionary:
	return s.execute(command(kind, p))

func reject(kind: String, p: Dictionary = {}) -> bool:
	var before: Dictionary = s.snapshot()
	return not send(kind, p).ok and s.snapshot() == before

func fresh(buy: bool = true) -> bool:
	var catalog: Dictionary = Catalog.load_file("res://data/campaign/gate1_day_one/catalog.json")
	var initial: Dictionary = Opening.seed(JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign/gate1_1/scenario.json")))
	initial["day_one"] = DayOne.marker()
	s = Session.new()
	if not catalog.ok or not s.initialize(catalog.definitions, initial):
		return false
	if not send("accept_rad1_contract").ok or not send("next_visit").ok:
		return false
	if buy:
		if not send("inspect_radio", {"item_id": "R001", "tool_id": "wear_detail", "target": "visible_wear_detail"}).ok or not send("inspect_radio", {"item_id": "R001", "tool_id": "casing_detail", "target": "additional_casing_evidence"}).ok:
			return false
		var offer: Dictionary = command("make_offer", {"amount": 100, "evidence_id": "R001.wear"})
		if not s.execute(offer).ok or not send("confirm_purchase", {"offer_id": offer.action_id, "inventory": "player_stock", "x": 0, "y": 0, "rotated": false}).ok:
			return false
	elif not send("decline_visit").ok:
		return false
	return send("begin_day_one").ok

func sale(wholesale: bool) -> Dictionary:
	return {"visit_id": DayOne.WHOLESALE if wholesale else DayOne.RETAIL, "item_id": "R001", "seller": "player", "buyer": DayOne.WHOLESALER if wholesale else "G02", "currency": "VKC", "amount": DayOne.WHOLESALE_PRICE if wholesale else DayOne.RETAIL_PRICE, "inventory": "wholesale_grid" if wholesale else "g02_grid", "x": 0, "y": 0, "rotated": false}

func _initialize() -> void:
	var ready: bool = fresh()
	check(ready, "opening carried into continuation")
	if not ready:
		quit(1)
		return
	check(s.snapshot().wallets.player.VKC == 80 and s.snapshot().game_minutes == 15, "normal opening unchanged")
	check(reject("trade", sale(false)) and reject("advance_time", {"minutes": 1}), "no uncalled retail or paid waiting")
	check(send("day_one_next").ok and reject("day_one_next"), "finite retail visit")
	check(reject("trade", sale(false)), "retail requires display")
	var move: Dictionary = {"item_id": "R001", "actor": "player", "inventory": "player_display", "x": 5, "y": 0, "rotated": false}
	check(reject("move", move), "display geometry atomic")
	move.x = 0
	check(send("move", move).ok and s.snapshot().wallets.player.VKC == 80, "move title and cost unchanged")
	check(reject("move", move), "identical placement not charged revision")
	move.rotated = true
	check(send("move", move).ok and s.snapshot().items.R001.rotated and s.snapshot().game_minutes == 15, "in-place rotation no time or cost")
	move.rotated = false
	check(send("move", move).ok, "return to original orientation")
	var forged: Dictionary = sale(false)
	forged.amount = 171
	check(reject("trade", forged) and reject("trade", sale(true)), "fixed quote and active visit scope")
	var cmd: Dictionary = command("trade", sale(false))
	check(s.execute(cmd).ok, "retail transaction")
	var sold: Dictionary = s.snapshot()
	check(sold.wallets.player.VKC == 250 and sold.wallets.G02.VKC == 30 and sold.items.R001.owner_id == "G02" and sold.game_minutes == 15, "retail actual cash and identity")
	check(sold.ledger.size() == 2 and s.counter_view().day_one.ledger[1].margin == 70, "realized margin")
	check(s.execute(cmd).ok and s.snapshot() == sold and reject("trade", sale(false)), "idempotent sale and finite demand")
	var corrupt: Dictionary = sold.duplicate(true)
	corrupt.wallets.player.VKC += 1
	check(not s.restore(corrupt) and s.snapshot() == sold, "replay rejects unexplained money")
	check(s.restore(sold), "continuation restore")
	corrupt = sold.duplicate(true)
	corrupt.ledger[1].game_minutes = 0
	check(not s.restore(corrupt) and s.snapshot() == sold, "replay checks actual sale minute")
	corrupt = sold.duplicate(true)
	corrupt.day_one.base.inventories.player_display.width = 5
	check(not s.restore(corrupt), "opening checkpoint grid dimensions pinned")
	corrupt = sold.duplicate(true)
	corrupt.day_one.base.items.R001.protected = true
	check(not s.restore(corrupt), "opening checkpoint protection pinned")
	ready = fresh()
	check(ready, "wholesale fixture")
	if ready:
		check(send("trade", sale(true)).ok and s.snapshot().wallets.player.VKC == 215 and s.counter_view().day_one.ledger[1].margin == 35, "finite wholesale")
		check(send("day_one_next").ok and reject("trade", sale(false)) and send("day_one_decline").ok, "retail not regenerated after wholesale")
	ready = fresh()
	check(ready, "hold fixture")
	if ready:
		check(send("day_one_next").ok and send("day_one_decline").ok and s.snapshot().wallets.player.VKC == 80 and s.snapshot().items.R001.owner_id == "player", "hold stock")
	ready = fresh(false)
	check(ready, "declined opening fixture")
	if ready:
		check(send("day_one_next").ok and reject("trade", sale(false)) and send("day_one_decline").ok and s.snapshot().wallets.player.VKC == 180, "independent finite inquiry")
	print("GATE1_2: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
