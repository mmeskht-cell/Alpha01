extends RefCounted
## A bounded, independent resale fixture for the owned composite workbench.
## No campaign money, items, inventory or customer consent state is introduced.
const Rules = preload("res://src/domain/value_rules.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const Component = preload("res://src/domain/component_appraisal.gd")
const ROOT: String = "D001"
const BUYER: String = "component_fixture_buyer"
const VISIT: String = "component_resale"
const PRICE: int = 200
const ACTION: String = "open_component_sale"

static func marker() -> Dictionary:
	return {"base": null, "open_action": null, "sale_command": null}

static func can_open(state: Dictionary, defs: Dictionary) -> bool:
	if state.phase != "workshop" or state.game_minutes != 600 or not Component.eligible(state, ROOT) or not Objects.complete(state, defs, ROOT):
		return false
	for fact: Dictionary in state.knowledge.values():
		if fact.item_id == ROOT and fact.observation_key == "component_function" and fact.observed_value is String and fact.observed_value == "serviceable" and Component.fact_current(fact, state.items[ROOT]):
			return Component.assembly_status(state, defs, ROOT) == "serviceable"
	return false

static func allowed(state: Dictionary, kind: String) -> bool:
	if state.component_market.base == null:
		return kind in [ACTION, "move", "attach", "detach", "restore_item", "observe", "record_component_hypothesis"]
	return kind == "trade" and state.component_market.sale_command == null

static func open(state: Dictionary, defs: Dictionary, p: Dictionary, action_id: String) -> String:
	if not p.is_empty() or state.component_market != marker() or not can_open(state, defs):
		return "component_market_unavailable"
	var prefix: Dictionary = state.duplicate(true)
	prefix.erase("component_market")
	state.component_market.base = prefix
	state.component_market.open_action = action_id
	state.phase = "shop"
	state.game_minutes = 1440
	state.wallets[BUYER] = {"VKC": PRICE, "USD": 0}
	state.inventories["component_buyer_grid"] = {"owner_id": BUYER, "width": 6, "height": 4, "host_item": ""}
	state.visits[VISIT] = {"scope": {"visit_id": VISIT, "kind": "ordinary", "purpose": "sale", "completed": false, "required_ids": []}, "seller": "player", "buyer": BUYER, "prices": {ROOT: {"VKC": PRICE, "USD": 0}}, "opens": 1440, "expires": 1440, "allow_inspection": false}
	return ""

static func payload() -> Dictionary:
	return {"visit_id": VISIT, "item_id": ROOT, "seller": "player", "buyer": BUYER, "currency": "VKC", "amount": PRICE, "inventory": "component_buyer_grid", "x": 0, "y": 0, "rotated": false}

static func view(state: Dictionary, defs: Dictionary) -> Dictionary:
	if not state.has("component_market"):
		return {}
	if state.component_market.base == null:
		return {"started": false, "can_open": can_open(state, defs), "revision": state.revision, "price": PRICE}
	var sold: bool = state.component_market.sale_command != null
	var margin: Variant = null
	if sold:
		var entry: Dictionary = state.ledger.back()
		margin = int(entry.amounts.VKC) - int(entry.basis.VKC) if entry.basis.VKC != null else null
	return {"started": true, "sold": sold, "revision": state.revision, "minute": state.game_minutes, "wallet": state.wallets.player.duplicate(true), "price": PRICE, "payload": payload() if not sold else {}, "margin": margin}
