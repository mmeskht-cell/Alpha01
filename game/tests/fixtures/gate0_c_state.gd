extends RefCounted
const Objects = preload("res://src/domain/object_schema.gd")

static func definitions() -> Dictionary:
	return preload("res://src/content/catalog_loader.gd").load_file("res://data/catalog/gate0_c.json").definitions

static func visit(id: String, seller: String, buyer: String, prices: Dictionary, special: bool = false) -> Dictionary:
	return {"scope": {"visit_id": id, "kind": "special_contract" if special else "ordinary", "purpose": "delivery" if special else ("purchase" if buyer == "player" else "sale"), "completed": false, "required_ids": prices.keys() if special else []}, "seller": seller, "buyer": buyer, "prices": prices.duplicate(true), "opens": 0, "expires": 60480, "allow_inspection": true}

static func make() -> Dictionary:
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign/gate0_c/acceptance_fixture.json"))
	var init: Dictionary = contract.initial
	var state: Dictionary = {"object_schema": 3, "revision": 0, "game_minutes": 0, "wallets": {"player": init.player_wallet, "seller": init.seller_wallet, "buyer": init.buyer_wallet}, "inventories": {"player_grid": {"owner_id": "player", "width": 10, "height": 6, "host_item": ""}, "seller_grid": {"owner_id": "seller", "width": 10, "height": 6, "host_item": ""}, "buyer_grid": {"owner_id": "buyer", "width": 10, "height": 6, "host_item": ""}}, "items": {}, "ledger": [], "receipts": {}, "receipt_archive": {}, "tombstones": {}, "object_events": [], "knowledge": {}, "visits": {}, "phase": "shop"}
	var root: Dictionary = Objects.fresh_item("sample_device", "seller", "seller_grid", 0, 0, "fixture_external_root")
	root.functional = false
	root.hidden_economy = 738
	state.items["X01"] = root
	for child: Dictionary in init.object_tree.children:
		var def_id: String = "sample_insert_" + child.id.right(1).to_lower()
		var item: Dictionary = Objects.fresh_item(def_id, "seller", "", -1, -1, "fixture_external_" + child.id)
		item.parent_id = "X01"
		item.functional = child.condition == "usable"
		item.restored = child.restored
		state.items[child.id] = item
	state.visits["purchase"] = visit("purchase", "seller", "player", {"X01": {"VKC": 70, "USD": 0}})
	return state

static func purchase() -> Dictionary:
	return {"action_id": "purchase", "expected_revision": 0, "type": "trade", "payload": {"item_id": "X01", "seller": "seller", "buyer": "player", "currency": "VKC", "amount": 70, "inventory": "player_grid", "x": 0, "y": 0, "rotated": false}}
