extends SceneTree
const Catalog = preload("res://src/content/catalog_loader.gd")
const Session = preload("res://src/domain/game_session.gd")
const Fixture = preload("res://tests/fixtures/foundation_state.gd")
const Rules = preload("res://src/domain/value_rules.gd")
var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	var catalog := Catalog.load_file("res://data/catalog/foundation.json")
	check(catalog.ok, "catalog loads")
	var invalid := JSON.parse_string(FileAccess.get_file_as_string("res://data/catalog/foundation.json")) as Dictionary
	invalid.definitions.append(invalid.definitions[0].duplicate(true))
	check(not Catalog.parse(JSON.stringify(invalid)).ok, "duplicate definitions rejected")
	invalid.definitions.resize(1)
	invalid.definitions[0].width = 1.5
	check(not Catalog.parse(JSON.stringify(invalid)).ok, "fractional footprint rejected")
	check(not Catalog.parse("{").ok, "invalid JSON rejected")
	var session := Session.new()
	check(session.initialize(catalog.definitions, Fixture.make()), "valid initial state")
	var initial := session.snapshot()
	initial.wallets.player.VKC = 999
	check(session.snapshot().wallets.player.VKC == 180, "read copy cannot mutate authority")
	check(session.clock_view() == {"day": 1, "date": "2032-11-01", "hour": 8, "minute": 0}, "campaign epoch")
	var command := {"action_id": "buy_1", "expected_revision": 0, "type": "trade", "payload": {"item_id": "parcel_001", "seller": "seller", "buyer": "player", "currency": "VKC", "amount": 50, "inventory": "player_grid", "x": 0, "y": 0, "rotated": false}}
	var result := session.execute(command)
	check(result.ok, "trade commits")
	var state := session.snapshot()
	check(state.wallets.player.VKC == 130 and state.wallets.seller.VKC == 70, "VKC transfer conserves sum")
	check(state.wallets.player.USD == 7 and state.wallets.seller.USD == 3, "USD unchanged by VKC trade")
	check(state.items.parcel_001.owner_id == "player" and state.items.size() == 2 and state.ledger.size() == 1, "ownership and item count conserved")
	check(session.execute(command) == result and session.snapshot() == state, "duplicate no mutation")
	var changed := command.duplicate(true)
	changed.payload.amount = 1
	check(session.execute(changed).error == "action_id_reused" and session.snapshot() == state, "ID payload collision rejected")
	changed.action_id = "stale"
	check(session.execute(changed).error == "stale_revision", "stale revision rejected")
	var move := {"action_id": "move_1", "expected_revision": 1, "type": "move", "payload": {"item_id": "parcel_001", "actor": "player", "inventory": "player_grid", "x": 0, "y": 2, "rotated": false}}
	check(not session.execute(move).ok and session.snapshot() == state, "overlap rejected atomically")
	move.payload.x = 3
	move.payload.y = 0
	check(not session.execute(move).ok and session.snapshot() == state, "bounds rejected")
	move.payload.rotated = true
	check(session.execute(move).ok, "rotation and movement")
	var clock := {"action_id": "clock_1", "expected_revision": 2, "type": "advance_time", "payload": {"minutes": 240}}
	check(session.execute(clock).ok and session.clock_view().hour == 12, "clock advances once")
	state = session.snapshot()
	var usd := {"action_id": "usd_1", "expected_revision": 3, "type": "trade", "payload": {"item_id": "parcel_001", "seller": "player", "buyer": "seller", "currency": "USD", "amount": 2, "inventory": "seller_grid", "x": 0, "y": 0, "rotated": false}}
	check(session.execute(usd).ok, "USD trade")
	check(session.snapshot().wallets.player.USD == 9 and session.snapshot().wallets.seller.USD == 1 and session.snapshot().wallets.player.VKC == 130, "USD conserved independently")
	state = session.snapshot()
	var poor := command.duplicate(true)
	poor.action_id = "poor"
	poor.expected_revision = 4
	poor.payload.amount = 500
	check(session.execute(poor).error == "insufficient_funds" and session.snapshot() == state, "insufficient funds no mutation")
	var invalid_state := state.duplicate(true)
	invalid_state.wallets.player.VKC = -1
	check(not session.restore(invalid_state) and session.snapshot() == state, "invalid restore no mutation")
	invalid_state = state.duplicate(true)
	invalid_state.items.parcel_001.def_id = "missing"
	check(not session.validate(invalid_state), "missing definition rejected")
	invalid_state = state.duplicate(true)
	invalid_state.game_minutes = 1440
	check(session.restore(invalid_state) and session.clock_view().day == 2 and session.clock_view().date == "2032-11-02", "date rollover")
	check(Rules.canonical(JSON.parse_string(Rules.canonical(state))) == Rules.canonical(state), "JSON integer normalization")
	print("FOUNDATION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
