extends SceneTree
const Directory = preload("res://src/domain/campaign_identity_directory.gd")
const Fixture = preload("res://tests/fixtures/gate0_c_state.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const Rules = preload("res://src/domain/value_rules.gd")
const Format = preload("res://src/domain/snapshot_format.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	var defs: Dictionary = Fixture.definitions()
	var state: Dictionary = Fixture.make()
	state.game_minutes = 10
	state.visits.purchase.expires = 5
	var family: Dictionary = state.items.duplicate(true)
	state.items.clear()
	state.inventories.seller_grid.height = 10
	state.inventories.buyer_grid.height = 10
	for i: int in range(128):
		var id: String = "bulk_" + str(i)
		var grid: String = "seller_grid" if i < 100 else "buyer_grid"
		var owner: String = "seller" if i < 100 else "buyer"
		var cell: int = i % 100
		@warning_ignore("integer_division")
		state.items[id] = Objects.fresh_item("sample_consumable", owner, grid, cell % 10, cell / 10, "sample_" + id)
	var p: Dictionary = {"state": state, "dormant": {"X01": family}, "tracking": {}}
	var result: Dictionary = Directory.audit(p, defs)
	check(result.ok and result.active_count == 128 and result.dormant_count == 4 and result.index.size() == 132, "128 active + 4 separate dormant IDs")
	check(result.get("index", {}).get("X01_A") == "dormant", "attached dormant identity resolves")
	check(Directory.wake_candidate(p, defs, "X01", "seller_grid", 0, 0, false).is_empty(), "active cap prevents reentry")
	# Release a 3x2 rectangle from the seller's occupied grid.
	var reduced: Dictionary = p
	for i: int in [0, 1, 2, 10, 11, 12]:
		reduced = Directory.sleep_candidate(reduced, defs, "bulk_" + str(i))
		if reduced.is_empty():
			break
	check(not reduced.is_empty(), "separate dormant capacity without deleting identity")
	if reduced.is_empty():
		quit(1)
		return
	check(Directory.audit(reduced, defs).active_count == 122, "true active count falls")
	check(Directory.wake_candidate(reduced, defs, "X01", "buyer_grid", 0, 0, false).is_empty(), "reentry cannot change custody")
	check(Directory.wake_candidate(reduced, defs, "X01", "seller_grid", 3, 0, false).is_empty(), "occupied reentry rejected")
	var awake: Dictionary = Directory.wake_candidate(reduced, defs, "X01", "seller_grid", 0, 0, false)
	check(not awake.is_empty() and Directory.audit(awake, defs).active_count == 126 and Directory.audit(awake, defs).dormant_count == 6, "family reenters same identity, independent active geometry")
	if awake.is_empty():
		quit(1)
		return
	for id: String in family:
		var row: Dictionary = awake.state.items[id]
		check(row.provenance_id == family[id].provenance_id and row.basis == family[id].basis and row.parent_id == family[id].parent_id and row.functional == family[id].functional, "immutable identity/cost/condition " + id)
	check(p.state.items.size() == 128 and p.dormant.X01 == family, "source partition unchanged")
	var bad: Dictionary = p.duplicate(true)
	bad.dormant.X01.X01_A.protected = true
	check(not Directory.audit(bad, defs).ok, "protected dormant child rejected")
	bad = p.duplicate(true)
	bad.dormant.X01.X01_A.parent_id = ""
	check(not Directory.audit(bad, defs).ok, "half family rejected")
	bad = p.duplicate(true)
	bad.state.items.X01_A = family.X01_A
	check(not Directory.audit(bad, defs).ok, "duplicate identity rejected")
	bad = p.duplicate(true)
	bad.state.visits.purchase.expires = 600
	check(Directory.audit(bad, defs).get("error") == "visit_reference", "pending visit requires active identity")
	bad = p.duplicate(true)
	bad.state.ledger.append({"item_ids": ["X01_A"], "root_ids": ["X01"]})
	check(Directory.audit(bad, defs).ok, "historical reference resolves dormant family")
	bad.state.ledger[0].item_ids.append("missing")
	check(Directory.audit(bad, defs).get("error") == "ledger_reference", "unresolved historical identity rejected")
	var bytes: int = Rules.canonical(p).to_utf8_buffer().size()
	check(bytes < Format.MAX_BYTES, "representative directory fits raw byte budget")
	print("ZT_IDENTITY_SAMPLE ", JSON.stringify({"active": 128, "dormant": 4, "total": 132, "raw_bytes": bytes}))
	print("CAMPAIGN_IDENTITY_DIRECTORY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
