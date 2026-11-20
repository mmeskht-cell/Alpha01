extends RefCounted
## Synthetic fixture, not campaign initialization or balance.
const Objects = preload("res://src/domain/object_schema.gd")
const Context = preload("res://tests/fixtures/gate0_c_state.gd")

static func make() -> Dictionary:
	var raw: Dictionary = {
		"revision": 0, "game_minutes": 0,
		"wallets": {"player": {"VKC": 180, "USD": 7}, "seller": {"VKC": 20, "USD": 3}},
		"inventories": {"player_grid": {"owner_id": "player", "width": 4, "height": 3}, "seller_grid": {"owner_id": "seller", "width": 4, "height": 3}},
		"items": {
			"parcel_001": {"def_id": "fixture_parcel", "owner_id": "seller", "custodian_id": "seller", "status": "stock", "inventory": "seller_grid", "x": 0, "y": 0, "rotated": false, "version": 0},
			"parcel_002": {"def_id": "fixture_parcel", "owner_id": "player", "custodian_id": "player", "status": "stock", "inventory": "player_grid", "x": 0, "y": 2, "rotated": false, "version": 0}},
		"ledger": [], "receipts": {}}

	var state: Dictionary = Objects.prepare_initial(raw)
	state.visits["buy_1"] = Context.visit("buy_1", "seller", "player", {"parcel_001": {"VKC": 50, "USD": 0}})
	state.visits["buy"] = Context.visit("buy", "seller", "player", {"parcel_001": {"VKC": 50, "USD": 0}})
	state.visits["poor"] = Context.visit("poor", "seller", "player", {"parcel_001": {"VKC": 500, "USD": 0}})
	state.visits["usd_1"] = Context.visit("usd_1", "player", "seller", {"parcel_001": {"VKC": 0, "USD": 2}})
	for index: int in range(160):
		var id: String = "trade_%d" % index
		state.visits[id] = Context.visit(id, "seller" if index % 2 == 0 else "player", "player" if index % 2 == 0 else "seller", {"parcel_001": {"VKC": 1, "USD": 0}})
	return state
