extends SceneTree
const Runtime = preload("res://src/application/foundation_runtime.gd")
const Session = preload("res://src/domain/game_session.gd")
const Catalog = preload("res://src/content/catalog_loader.gd")
const Fixture = preload("res://tests/fixtures/foundation_state.gd")
var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)

func command(id: String, revision: int, kind: String, payload: Dictionary = {}) -> Dictionary:
	return {"action_id": id, "expected_revision": revision, "type": kind, "payload": payload}

func _initialize() -> void:
	var directory: String = "user://zt_rebuild/gate1_opening_" + str(Time.get_ticks_usec())
	var runtime := Runtime.new()
	check(not runtime.initialize_gate1_opening("foundation", directory), "dedicated slot only")
	var ready: bool = runtime.initialize_gate1_opening("gate1_1_v3", directory)
	check(ready, "campaign setup")
	if not ready:
		quit(1)
		return
	var initial: Dictionary = runtime.snapshot()
	var dto: Dictionary = runtime.counter_view()
	check(initial.object_schema == 3 and initial.phase == "shop", "schema3 shop")
	check(dto.wallet == {"VKC": 180, "USD": 0} and dto.minute == 0 and dto.day == 1, "initial public wallet and clock")
	check(dto.personal_rad1_doses == 1 and dto.rad1_effect_until_minute == 2880, "initial RAD-1")
	check(dto.contract.amount == 300 and dto.contract.due_minute == 4920 and dto.contract.delivery_minute == 6360, "contract public terms")
	check(dto.contract.status == "offered" and dto.customer == null and dto.remaining_visits == 3, "initial offer and ordered queue")
	check(initial.items.R001.owner_id == "G01" and initial.items.R001.inventory == "g01_grid" and initial.inventories.player_stock.width == 10 and initial.inventories.player_stock.height == 6, "customer owns radio; player grid ready")
	dto.wallet["VKC"] = 1
	check(runtime.snapshot() == initial, "DTO detached")
	check(not runtime.submit(command("spoof_contract", 0, "accept_rad1_contract", {"amount": 1})).ok and runtime.snapshot() == initial, "client cannot alter contract")
	var reserve: Dictionary = command("reserve", 0, "accept_rad1_contract")
	var result: Dictionary = runtime.submit(reserve)
	check(result.ok and result.get("persisted", false), "contract committed and persisted")
	var reserved: Dictionary = runtime.snapshot()
	check(reserved.campaign.reserved_supply == 1 and runtime.counter_view().contract.status == "reserved", "exactly one supply reserved")
	check(reserved.wallets == initial.wallets and reserved.game_minutes == 0 and reserved.ledger.is_empty(), "reservation is free")
	check(runtime.submit(reserve).ok and runtime.snapshot() == reserved, "replay does not reserve again")
	check(not runtime.submit(command("reserve_again", 1, "accept_rad1_contract")).ok and runtime.snapshot() == reserved, "different ID cannot reserve again")
	check(not runtime.submit(command("stale_admit", 0, "next_visit")).ok and runtime.snapshot() == reserved, "stale admission rejected")
	var admit: Dictionary = command("admit", 1, "next_visit")
	result = runtime.submit(admit)
	check(result.ok and result.get("persisted", false), "first customer admitted and persisted")
	var active: Dictionary = runtime.snapshot()
	dto = runtime.counter_view()
	check(active.game_minutes == 0 and active.wallets == initial.wallets and active.items == initial.items, "admission is free and does not transfer")
	check(dto.customer.visit_id == "visit_g01" and dto.customer.ask == 125 and dto.remaining_visits == 2 and not dto.can_call_next, "only first public offer")
	check(not dto.has("items") and not dto.customer.has("functional") and not dto.customer.has("hidden_economy") and not dto.contract.has("external_supply"), "no hidden truth or full registry")
	check(runtime.submit(admit).ok and runtime.snapshot() == active, "admission replay unchanged")
	check(not runtime.submit(command("g02", 2, "next_visit")).ok and runtime.snapshot() == active, "next gate customer cannot activate")
	check(not runtime.submit(command("clock", 2, "advance_time", {"minutes": 5})).ok and runtime.snapshot() == active, "generic time bypass blocked")
	check(not runtime.submit(command("purchase", 2, "trade", {"visit_id": "visit_g01", "item_id": "R001", "seller": "G01", "buyer": "player", "currency": "VKC", "amount": 125, "inventory": "player_stock", "x": 0, "y": 0, "rotated": false})).ok and runtime.snapshot() == active, "generic trade blocked pending negotiation integration")
	check(runtime.item_view("R001").is_empty(), "generic inspection not granted")
	runtime.shutdown()
	var restored := Runtime.new()
	ready = restored.initialize_gate1_opening("gate1_1_v3", directory)
	check(ready, "existing slot setup for restore")
	if ready:
		check(restored.load_saved().ok and restored.snapshot() == active, "schema3 state roundtrip")
		check(restored.submit(admit).ok and restored.snapshot() == active, "replay after restoration")
		restored.shutdown()
	var foundation := Session.new()
	check(foundation.initialize(Catalog.load_file("res://data/catalog/foundation.json").definitions, Fixture.make()), "legacy foundation fixture remains valid")
	check(not foundation.execute(command("injected", 0, "accept_rad1_contract")).ok, "opening unavailable in foundation")
	for name: String in ["gate1_1_v3.a.json", "gate1_1_v3.b.json"]:
		var file: String = directory.path_join(name)
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(directory)
	print("GATE1_OPENING: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
