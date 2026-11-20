extends SceneTree
const Session = preload("res://src/domain/game_session.gd")
const Fixture = preload("res://tests/fixtures/gate0_c_state.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const Repo = preload("res://src/persistence/checkpoint_repository.gd")
const Legacy = preload("res://src/persistence/save_repository.gd")
const Format = preload("res://src/persistence/checkpoint_format.gd")
var checks: int = 0
var failures: int = 0
var directory: String = "user://zt_rebuild/lifecycle_authority_" + str(Time.get_ticks_usec())

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func fresh() -> RefCounted:
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
	state["lifecycle"] = {"dormant": {"X01": family}}
	var session := Session.new()
	return session if session.initialize(Fixture.definitions(), state, false, true) else null

func cmd(s: RefCounted, kind: String, id: String, payload: Dictionary) -> Dictionary:
	return {"action_id": id, "expected_revision": s.snapshot().revision, "type": kind, "payload": payload}

func _initialize() -> void:
	var s: RefCounted = fresh()
	check(s != null, "same GameSession initializes 128 active + 4 dormant")
	if s == null:
		quit(1)
		return
	var seed: Dictionary = s.snapshot()
	var first: Dictionary = cmd(s, "world_sleep_family", "sleep0", {"root_id": "bulk_0"})
	check(not s.execute(first).ok and s.snapshot() == seed, "player cannot invoke world command")
	var wake_payload: Dictionary = {"root_id": "X01", "inventory": "seller_grid", "x": 0, "y": 0, "rotated": false}
	check(not s.execute_world(cmd(s, "world_wake_family", "full", wake_payload)).ok and s.snapshot() == seed, "capacity denial atomic")
	var repo := Repo.new(directory)
	check(repo.save("lifecycle", seed, [], seed, fresh).ok, "separate checkpoint initial save")
	check(not Legacy.new(directory).save_session(s, "legacy").ok, "v3 writer refuses new mode")
	var tail: Array = []
	for i: int in [0, 1, 2, 10, 11, 12]:
		var command: Dictionary = cmd(s, "world_sleep_family", "sleep" + str(i), {"root_id": "bulk_" + str(i)})
		check(s.execute_world(command).ok, "actual world lifecycle command " + str(i))
		tail.append(command)
	var before: Dictionary = s.snapshot()
	check(before.items.size() == 122 and before.lifecycle.dormant.size() == 7, "authority separates active and dormant")
	check(not s.execute_world(cmd(s, "world_wake_family", "overlap", wake_payload.merged({"x": 3}, true))).ok and s.snapshot() == before, "occupied placement rejected atomically")
	var wake: Dictionary = cmd(s, "world_wake_family", "wake", wake_payload)
	check(s.execute_world(wake).ok, "actual authority reentry")
	tail.append(wake)
	var after: Dictionary = s.snapshot()
	check(after.items.size() == 126 and after.lifecycle.dormant.size() == 6 and after.revision == 7 and after.wallets == seed.wallets, "exact revision, capacity and economy")
	check(s.execute_world(wake).ok and s.snapshot() == after and not s.execute(wake).ok, "world receipt idempotence without player permission")
	check(after.items.X01_A.provenance_id == seed.lifecycle.dormant.X01.X01_A.provenance_id, "same component identity")
	check(repo.save("lifecycle", seed, tail, after, fresh).ok, "bounded journal commits world commands")
	var reopened: RefCounted = fresh()
	var loaded: Dictionary = repo.load_state("lifecycle", fresh)
	check(loaded.get("ok", false) and reopened.restore(loaded.state) and reopened.snapshot() == after, "actual saved authority exact reload")
	var forged: Dictionary = after.duplicate(true)
	forged.wallets.player.VKC += 1
	check(not reopened.restore(forged) and reopened.snapshot() == after, "independent accounting rejects altered checkpoint")
	forged = after.duplicate(true)
	forged.lifecycle.events[0].command.payload.root_id = "bulk_3"
	check(not reopened.restore(forged), "world event bound to receipt")
	forged = after.duplicate(true)
	forged.lifecycle.dormant.bulk_0.bulk_0.provenance_id = "forged"
	check(not reopened.restore(forged), "dormant provenance bound to seed")
	forged = after.duplicate(true)
	forged.lifecycle.events.pop_back()
	check(not reopened.restore(forged), "missing lifecycle record rejected")
	forged = after.duplicate(true)
	forged.items.X01.functional = not forged.items.X01.functional
	check(not reopened.restore(forged), "unrecorded functional change rejected")
	forged = after.duplicate(true)
	forged.items.X01.field_versions.composition += 1
	check(not reopened.restore(forged), "unrecorded composition version rejected")
	forged = after.duplicate(true)
	forged.items.X01.basis.VKC = 1
	check(not reopened.restore(forged), "unrecorded cost basis rejected")
	forged = after.duplicate(true)
	forged.lifecycle.events.back().item_ids = ["X01"]
	check(not reopened.restore(forged), "incomplete historical family rejected")
	var tick: Dictionary = cmd(s, "advance_time", "wait", {"minutes": 1})
	check(s.execute(tick).ok and s.snapshot().lifecycle.dormant == after.lifecycle.dormant, "ordinary command shares same authority")
	check(repo.save("lifecycle", after, [tick], s.snapshot(), fresh).ok, "ordinary command after lifecycle commit")
	forged = s.snapshot()
	forged.game_minutes += 1
	check(not s.restore(forged), "clock cannot advance without a receipt")
	forged = s.snapshot()
	forged.lifecycle.waits.wait = 2
	check(not s.restore(forged), "clock witness must match exact receipt")
	var newest: String = directory.path_join("lifecycle.v4.a.json")
	var file := FileAccess.open(newest, FileAccess.WRITE)
	file.store_string("broken")
	file.close()
	var recovered: Dictionary = repo.load_state("lifecycle", fresh)
	check(recovered.get("recovered", false) and recovered.get("state") == after, "recover prior exact mixed authority generation")
	var dynamic: RefCounted = fresh()
	check(dynamic.execute_world(cmd(dynamic, "world_sleep_family", "free_cell", {"root_id": "bulk_0"})).ok, "free a cell for dynamic stock")
	var birth: Dictionary = cmd(dynamic, "world_spawn_stock", "birth", {"item_id": "new_stock", "def_id": "sample_consumable", "owner": "seller", "inventory": "seller_grid", "x": 0, "y": 0, "rotated": false, "functional": true})
	check(not dynamic.execute(birth).ok and dynamic.execute_world(birth).ok, "world-only dynamic stock birth")
	check(dynamic.execute_world(birth).ok and dynamic.snapshot().revision == 2, "birth retry preserves one identity")
	check(not dynamic.execute_world(cmd(dynamic, "world_spawn_stock", "duplicate", birth.payload)).ok, "no duplicate identity")
	var offer: Dictionary = cmd(dynamic, "world_open_visit", "offer", {"visit_id": "new_visit", "item_id": "new_stock", "seller": "seller", "buyer": "player", "price": {"VKC": 9, "USD": 0}, "opens": 10, "expires": 20, "allow_inspection": true})
	check(not dynamic.execute(offer).ok and dynamic.execute_world(offer).ok, "world-only dynamic visit")
	check(not dynamic.execute_world(cmd(dynamic, "world_sleep_family", "pending_sleep", {"root_id": "new_stock"})).ok, "pending dynamic visit protects item")
	var sale: Dictionary = cmd(dynamic, "trade", "sale", {"visit_id": "new_visit", "item_id": "new_stock", "seller": "seller", "buyer": "player", "currency": "VKC", "amount": 9, "inventory": "player_grid", "x": 0, "y": 0, "rotated": false})
	check(dynamic.execute(sale).ok, "ordinary trade on dynamic visit")
	var dynamic_state: Dictionary = dynamic.snapshot()
	check(dynamic_state.items.new_stock.owner_id == "player" and dynamic_state.items.new_stock.basis.VKC == 9 and dynamic_state.visits.new_visit.scope.completed, "dynamic stock cost and visit completion")
	check(repo.save("dynamic", dynamic_state, [], dynamic_state, fresh).ok and repo.load_state("dynamic", fresh).get("state") == dynamic_state, "dynamic birth and visit cold checkpoint roundtrip")
	forged = dynamic_state.duplicate(true)
	forged.visits.new_visit.expires += 1
	check(not dynamic.restore(forged), "dynamic visit cannot change historical terms")
	forged = dynamic_state.duplicate(true)
	forged.items.new_stock.provenance_id = "forged"
	check(not dynamic.restore(forged), "dynamic birth cannot change provenance")
	forged = dynamic_state.duplicate(true)
	forged.phase = "workshop"
	check(not dynamic.restore(forged), "unrecorded phase change rejected")
	forged = dynamic_state.duplicate(true)
	forged.items.new_stock.protected = true
	check(not dynamic.restore(forged), "unrecorded protection change rejected")
	print("ZT_LIFECYCLE_SAMPLE ", JSON.stringify({"active": after.items.size(), "dormant_roots": after.lifecycle.dormant.size(), "revision": after.revision, "bytes": Format.encode("s".repeat(64), seed, tail, after).to_utf8_buffer().size()}))
	var dir := DirAccess.open(directory)
	for name: String in dir.get_files():
		dir.remove(name)
	DirAccess.remove_absolute(directory)
	print("LIFECYCLE_AUTHORITY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
