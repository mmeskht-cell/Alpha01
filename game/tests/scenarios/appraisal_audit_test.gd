extends SceneTree
const Session = preload("res://src/domain/game_session.gd")
const Catalog = preload("res://src/content/catalog_loader.gd")
const Component = preload("res://src/domain/component_appraisal.gd")
const Customer = preload("res://src/domain/customer_inspection.gd")
var s: RefCounted
var serial: int = 0
var failures: int = 0
var checks: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func send(kind: String, payload: Dictionary = {}) -> Dictionary:
	serial += 1
	return s.execute({"action_id": "audit_" + str(serial), "expected_revision": s.snapshot().revision, "type": kind, "payload": payload})

func read(id: String, key: String = "component_function") -> Dictionary:
	return send("observe", {"actor": "player", "item_id": id, "key": key})

func part(id: String) -> Dictionary:
	for row: Dictionary in s.component_workshop_view().parts:
		if row.id == id:
			return row
	return {}

func diagnosis(id: String) -> Dictionary:
	for fact: Dictionary in part(id).get("observations", []):
		if fact.observation_key == "component_function":
			return fact
	return {}

func detach(id: String, x: int) -> Dictionary:
	return send("detach", {"actor": "player", "root_id": "D001", "child_id": id, "inventory": "player_grid", "x": x, "y": 3, "rotated": false})

func attach(id: String) -> Dictionary:
	return send("attach", {"actor": "player", "root_id": "D001", "child_id": id})

func repair(id: String) -> Dictionary:
	return send("restore_item", {"actor": "player", "item_id": id})

func _initialize() -> void:
	var catalog: Dictionary = Catalog.load_file("res://data/catalog/component_preview.json")
	s = Session.new()
	var ready: bool = catalog.ok and s.initialize(catalog.definitions, Customer.seed(Component.seed(), "cooperative"))
	check(ready, "fixture initialized")
	if not ready:
		quit(1)
		return
	check(read("D001").ok and diagnosis("D001").observed_value == "partial", "new three-tier assembly reading")
	var initial_read: Dictionary = s.snapshot()
	var legacy: Dictionary = initial_read.duplicate(true)
	legacy.knowledge.audit_1.observed_value = false
	legacy.items.D001.functional = false
	legacy.items.D002.functional = false
	legacy.customer_inspection.erase("waits")
	check(s.restore(legacy) and not diagnosis("D001").current, "legacy binary reading retained as stale, old preview accepted")
	check(read("D001").ok and diagnosis("D001").observed_value == "partial", "legacy rechecked without silently changing prior observation")
	check(s.restore(initial_read), "return to new source fixture")
	check(send("advance_time", {"minutes": 7}).ok and send("request_open_inspection").ok and read("D001_A", "component_texture").ok, "timed visit and permitted interior")
	check(send("close_inspection").ok and part("D001_A").is_empty() and s.component_workshop_view().notes.size() == 1, "permitted notes retain facts after revocation")
	var valid: Dictionary = s.snapshot()
	var bad: Dictionary = valid.duplicate(true)
	bad.game_minutes += 1
	check(not s.restore(bad) and s.snapshot() == valid, "unexplained elapsed time refused")
	bad = valid.duplicate(true)
	bad.customer_inspection.waits.audit_3 = 8
	check(not s.restore(bad), "incorrect or extra wait metadata refused")
	bad = valid.duplicate(true)
	bad.wallets.player.VKC += 1
	check(not s.restore(bad), "unexplained funds refused")
	check(send("trade", {"visit_id": Customer.VISIT, "item_id": Customer.ROOT, "seller": Customer.SELLER, "buyer": "player", "currency": "VKC", "amount": Customer.ASK, "inventory": "player_grid", "x": 0, "y": 0, "rotated": false}).ok, "purchase")
	valid = s.snapshot()
	bad = valid.duplicate(true)
	bad.items.D001_A.basis.VKC += 1
	check(not s.restore(bad) and s.snapshot() == valid, "incorrect part allocation refused")
	bad = valid.duplicate(true)
	bad.ledger[0].game_minutes -= 1
	check(not s.restore(bad), "incorrect transaction minute refused")
	check(send("finish_component_visit").ok, "evening")
	check(detach("D001_B", 3).ok and not diagnosis("D001").current and repair("D001_B").ok and attach("D001_B").ok, "secondary abstract repair")
	check(read("D001").ok and diagnosis("D001").observed_value == "partial", "second secondary fault remains")
	check(detach("D001_C", 5).ok and repair("D001_C").ok and attach("D001_C").ok, "second secondary abstract repair")
	check(not diagnosis("D001").current and read("D001").ok and diagnosis("D001").observed_value == "serviceable", "complete repair becomes serviceable")
	check(s.snapshot().wallets.player.VKC == 10, "purchase plus two repair expenses")
	check(detach("D001_A", 0).ok and part("D001").whole_catalog_reference == 200, "public catalogue price independent of missing essential")
	check(read("D001").ok and diagnosis("D001").observed_value == "inoperable", "missing essential diagnosed after read")
	valid = s.snapshot()
	bad = valid.duplicate(true)
	bad.items.D001_B.functional = false
	check(not s.restore(bad) and s.snapshot() == valid, "inconsistent restored flag rejected")
	check(s.restore(valid), "final snapshot validates")
	print("APPRAISAL_AUDIT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
