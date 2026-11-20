extends SceneTree
const Lineage = preload("res://src/domain/item_lineage.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func entry(minute: int, buyer: String, seller: String, roots: Array, ids: Array) -> Dictionary:
	return {"game_minutes": minute, "from": buyer, "to": seller, "root_ids": roots, "item_ids": ids, "amounts": {"VKC": 100, "USD": 0}, "private": "hidden"}

func _initialize() -> void:
	var state: Dictionary = {"ledger": [], "items": {"R": {"owner_id": "unknown"}}, "private": "secret"}
	check(Lineage.public_history(state, "R").records.is_empty(), "no inferred past")
	state.ledger.append(entry(5, "player", "A", ["R"], ["R", "C"]))
	state.ledger.append(entry(10, "B", "player", ["R"], ["R", "C"]))
	state.ledger.append(entry(15, "B", "A", ["R"], ["R", "C"]))
	state.ledger.append(entry(20, "player", "A", ["OTHER"], ["OTHER"]))
	var before: Dictionary = state.duplicate(true)
	var history: Dictionary = Lineage.public_history(state, "R")
	check(history.records.size() == 2, "only matching player transactions")
	check(history.records[0].direction == "sale" and history.records[1].direction == "purchase", "newest first with correct cash direction")
	check(history.records[0].amounts.VKC == 100 and history.records[0].minute == 10, "public amount and time")
	check(not history.records[0].has("private") and not history.records[0].has("from") and not history.records[0].has("to"), "no raw hidden data")
	check(Lineage.public_history(state, "C").records[0].amounts == null, "child never inherits root price")
	check(Lineage.public_history(state, "missing").records.is_empty(), "unrelated item not disclosed")
	history.records[0].amounts.VKC = 99
	check(state == before and Lineage.public_history(state, "R").records[0].amounts.VKC == 100, "detached read")
	state.ledger.append(entry(30, "player", "A", ["R", "OTHER"], ["R", "C", "OTHER"]))
	check(Lineage.public_history(state, "R").records[0].amounts == null, "multi-root total never attributed")
	for i: int in range(20):
		state.ledger.append(entry(40 + i, "player", "A", ["R"], ["R"]))
	check(Lineage.public_history(state, "R").records.size() == 12 and Lineage.public_history(state, "R").omitted == 11, "bounded display not deletion")
	check(state.ledger.size() == 25, "full underlying ledger preserved")
	print("ITEM_LINEAGE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
