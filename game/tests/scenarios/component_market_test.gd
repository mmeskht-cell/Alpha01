extends SceneTree
const Session = preload("res://src/domain/game_session.gd")
const Catalog = preload("res://src/content/catalog_loader.gd")
const Component = preload("res://src/domain/component_appraisal.gd")
const Market = preload("res://src/domain/component_market.gd")
var s: RefCounted
var serial: int = 0
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func command(kind: String, p: Dictionary = {}) -> Dictionary:
	serial += 1
	return {"action_id": "resale_" + str(serial), "expected_revision": s.snapshot().revision, "type": kind, "payload": p}

func run(kind: String, p: Dictionary = {}) -> Dictionary:
	return s.execute(command(kind, p))

func reject(kind: String, p: Dictionary = {}) -> bool:
	var before: Dictionary = s.snapshot()
	return not run(kind, p).ok and s.snapshot() == before

func _initialize() -> void:
	var catalog: Dictionary = Catalog.load_file("res://data/catalog/component_preview.json")
	var initial: Dictionary = Component.seed()
	initial["component_market"] = Market.marker()
	s = Session.new()
	var ready: bool = catalog.ok and s.initialize(catalog.definitions, initial)
	check(ready, "independent owned-stock resale fixture")
	if not ready:
		quit(1)
		return
	check(reject("open_component_sale") and reject("trade", Market.payload()), "no sale before restoration and current inspection")
	for step: Array in [["D001_B", 3], ["D001_C", 5]]:
		check(run("detach", {"actor": "player", "root_id": "D001", "child_id": step[0], "inventory": "player_grid", "x": step[1], "y": 3, "rotated": false}).ok, "abstract component detachment")
		check(run("restore_item", {"actor": "player", "item_id": step[0]}).ok, "abstract repair, existing basis path")
		check(run("attach", {"actor": "player", "root_id": "D001", "child_id": step[0]}).ok, "reattach identical component")
	check(s.snapshot().game_minutes == 600 and s.snapshot().wallets.player.VKC == 90, "evening frozen and 10 expense")
	check(reject("open_component_sale"), "no unexamined condition shortcut")
	check(run("observe", {"actor": "player", "item_id": "D001", "key": "component_function"}).ok and s.component_market_view().can_open, "fresh serviceable diagnosis")
	var start: Dictionary = command("open_component_sale")
	check(s.execute(start).ok and s.snapshot().game_minutes == 1440 and s.snapshot().wallets.player.VKC == 90, "finite next-morning quote, no advance income")
	var opened: Dictionary = s.snapshot()
	check(s.execute(start).ok and s.snapshot() == opened and reject("open_component_sale"), "opening exactly once")
	var forged: Dictionary = Market.payload()
	forged.amount = 201
	check(reject("trade", forged), "fixed fixture price")
	check(s.restore(opened), "restore open market checkpoint")
	var sold_cmd: Dictionary = command("trade", Market.payload())
	check(s.execute(sold_cmd).ok, "existing atomic transfer")
	var sold: Dictionary = s.snapshot()
	check(sold.wallets.player.VKC == 290 and sold.wallets[Market.BUYER].VKC == 0, "cash and buyer budget")
	check(sold.ledger.size() == 1 and sold.ledger[0].basis.VKC == 110 and s.component_market_view().margin == 90, "full original basis plus repairs; realized margin")
	for id: String in ["D001", "D001_A", "D001_B", "D001_C"]:
		check(sold.items[id].owner_id == Market.BUYER, "same transferred ID " + id)
	check(sold.items.D002.owner_id == "player" and s.execute(sold_cmd).ok and s.snapshot() == sold and reject("trade", Market.payload()), "unrelated shell retained; one sale")
	var bad: Dictionary = sold.duplicate(true)
	bad.wallets.player.VKC += 1
	check(not s.restore(bad) and s.snapshot() == sold and s.restore(sold), "sale checkpoint rejects unexplained cash")
	print("COMPONENT_MARKET: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
