extends SceneTree
const Runtime = preload("res://src/application/foundation_runtime.gd")
const Customer = preload("res://src/domain/customer_inspection.gd")
var rt: RefCounted
var directory: String
var checks: int = 0
var failures: int = 0
var serial: int = 0

func check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", name)

func fresh(policy: String) -> bool:
	serial += 1
	directory = "user://zt_rebuild/customer_inspection_previews/test_" + str(Time.get_ticks_usec()) + "_" + str(serial)
	rt = Runtime.new()
	return rt.initialize_customer_inspection_preview(directory, policy)

func dto() -> Dictionary:
	return rt.component_workshop_view()

func part(id: String) -> Dictionary:
	for row: Dictionary in dto().parts:
		if row.id == id:
			return row
	return {}

func command(kind: String, p: Dictionary, id: String) -> Dictionary:
	return {"action_id": id, "expected_revision": dto().revision, "type": kind, "payload": p}

func run(kind: String, p: Dictionary = {}) -> Dictionary:
	serial += 1
	return rt.submit(command(kind, p, "a_" + str(serial)))

func observe(id: String, key: String) -> Dictionary:
	return run("observe", {"actor": "player", "item_id": id, "key": key})

func purchase(x: int = 0) -> Dictionary:
	return run("trade", {"visit_id": Customer.VISIT, "item_id": Customer.ROOT, "seller": Customer.SELLER, "buyer": "player", "currency": "VKC", "amount": 80, "inventory": "player_grid", "x": x, "y": 0, "rotated": false})

func cleanup() -> void:
	rt.shutdown()
	for file: String in ["customer_inspection_v3.a.json", "customer_inspection_v3.b.json"]:
		var path: String = directory.path_join(file)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)

func _initialize() -> void:
	var ready: bool = fresh("cooperative")
	check(ready, "cooperative fixture")
	if not ready:
		quit(1)
		return
	var initial: Dictionary = rt.snapshot()
	check(dto().customer.status == "waiting" and part("D001_A").is_empty(), "no hidden board in closed DTO")
	check(not observe("D001_A", "component_texture").ok and rt.snapshot() == initial, "no internal access before consent")
	check(observe("D001", "component_function").ok and observe("D001_C", "component_texture").ok and dto().minute == 10, "optional whole function and exposed surfaces")
	check(not run("detach", {"actor": "player", "root_id": "D001", "child_id": "D001_C", "inventory": "player_grid", "x": 0, "y": 3, "rotated": false}).ok, "physical detach denied")
	var req: Dictionary = command("request_open_inspection", {}, "request")
	var before: Dictionary = rt.snapshot()
	check(rt.submit(req).ok and dto().customer.status == "open" and dto().minute == 15, "cooperative permission granted")
	check(rt.snapshot().items == initial.items and rt.snapshot().wallets == initial.wallets and rt.snapshot().object_events.is_empty(), "opening leaves all items and money unchanged")
	var opened: Dictionary = rt.snapshot()
	check(rt.submit(req).ok and rt.snapshot() == opened, "request replay is harmless")
	check(not run("request_open_inspection").ok and rt.snapshot() == opened, "no repeated consent requests")
	check(not part("D001_A").is_empty() and part("D001_A").observations.is_empty() and not part("D001_A").has("readings"), "new scope reveals no hidden readings")
	check(not observe("D001_A", "component_function").ok and rt.snapshot() == opened, "beyond granted scope denied")
	check(observe("D001_A", "component_texture").ok and observe("D001_A", "component_damage").ok, "selective internal readings")
	check(run("record_component_hypothesis", {"actor": "player", "item_id": "D001_A", "material_id": "coated_steel", "condition_id": "light_wear", "series_id": null}).ok, "manual part hypothesis")
	var knowledge: Dictionary = rt.snapshot().knowledge
	var hypothesis: Dictionary = part("D001_A").hypothesis
	check(rt.snapshot().items == initial.items and dto().minute == 25, "observations do not mutate parts")
	before = rt.snapshot()
	check(not purchase(6).ok and rt.snapshot() == before and dto().customer.status == "open", "failed placement preserves permission and state")
	var save: Dictionary = rt.snapshot()
	rt.shutdown()
	rt = Runtime.new()
	ready = rt.initialize_customer_inspection_preview(directory, "cooperative")
	check(ready and rt.load_saved().ok and rt.snapshot() == save and dto().customer.status == "open", "restore scoped visit")
	check(run("close_inspection").ok and dto().customer.status == "closed" and part("D001_A").is_empty(), "explicit close hides interior")
	check(dto().notes.size() == 1 and dto().notes[0].id == "D001_A" and dto().notes[0].observations.size() == 2 and dto().notes[0].hypothesis == hypothesis, "read-only notes preserve acquired facts and hypothesis")
	check(not dto().notes[0].has("regions") and not dto().notes[0].has("basis"), "notes do not grant tools or expose live item data")
	before = rt.snapshot()
	check(not observe("D001_A", "component_mark").ok and rt.snapshot() == before, "no new interior readings after close")
	check(purchase().ok and dto().customer.status == "bought" and dto().wallet.VKC == 20 and rt.snapshot().knowledge == knowledge, "atomic purchase keeps prior knowledge")
	check(not run("request_open_inspection").ok and not run("decline_component_visit").ok, "terminal visit not reusable")
	var acquired: Dictionary = rt.snapshot()
	var total: int = 0
	for id: String in Customer.IDS:
		total += int(acquired.items[id].basis.VKC)
	check(total == 80 and acquired.ledger.size() == 1 and acquired.items.D001_A.owner_id == "player", "normal family cost allocation")
	check(run("finish_component_visit").ok and dto().phase == "workshop" and dto().minute == 600, "owned evening transition")
	check(part("D001_A").hypothesis == hypothesis and part("D001_A").observations.size() == 2, "part appraisal survived ownership transfer")
	check(run("detach", {"actor": "player", "root_id": "D001", "child_id": "D001_A", "inventory": "player_grid", "x": 0, "y": 3, "rotated": false}).ok, "actual disassembly again permitted only after purchase")
	check(part("D001_A").hypothesis == hypothesis and part("D001_A").observations.size() == 2 and not observe("D001_A", "component_texture").ok, "knowledge retained and free review")
	cleanup()

	ready = fresh("reserved")
	check(ready, "refusal fixture")
	if not ready:
		quit(1)
		return
	initial = rt.snapshot()
	check(run("request_open_inspection").ok and dto().customer.status == "refused" and part("D001_A").is_empty() and dto().minute == 5, "refusal does not reveal interior")
	check(not observe("D001_A", "component_mark").ok and rt.snapshot().items == initial.items, "refusal cannot be bypassed")
	check(purchase().ok and dto().customer.status == "bought", "buy despite refusal")
	cleanup()

	ready = fresh("cooperative")
	check(ready, "decline fixture")
	if not ready:
		quit(1)
		return
	initial = rt.snapshot()
	check(run("request_open_inspection").ok and observe("D001_A", "component_mark").ok, "inspection before declining")
	check(run("decline_component_visit").ok and dto().customer.status == "declined" and part("D001_A").is_empty(), "decline revokes permission")
	check(not purchase().ok and not observe("D001_A", "component_texture").ok and rt.snapshot().items == initial.items and rt.snapshot().wallets == initial.wallets, "no transfer or changes on decline")
	check(run("finish_component_visit").ok and part("D001_A").is_empty() and rt.item_view("D001_A").is_empty(), "customer goods and generic read path remain inaccessible")
	cleanup()

	ready = fresh("cooperative")
	check(ready, "closing fixture")
	if not ready:
		quit(1)
		return
	check(run("request_open_inspection").ok, "opening before closing")
	check(run("advance_time", {"minutes": 240}).ok and run("advance_time", {"minutes": 240}).ok and run("advance_time", {"minutes": 114}).ok, "t599")
	before = rt.snapshot()
	check(not observe("D001_A", "component_texture").ok and rt.snapshot() == before, "too little time rejects unchanged")
	check(run("advance_time", {"minutes": 1}).ok and dto().customer.status == "closing" and part("D001_A").is_empty(), "close automatically revokes")
	check(not observe("D001_A", "component_texture").ok, "no inspections at closing")
	check(run("finish_component_visit").ok and dto().customer.status == "expired" and not purchase().ok, "expired customer cannot be traded")
	cleanup()

	ready = fresh("cooperative")
	check(ready, "no-consent purchase fixture")
	if ready:
		check(purchase().ok and dto().minute == 0 and rt.snapshot().knowledge.is_empty(), "all inspections optional")
		cleanup()
	ready = fresh("cooperative")
	check(ready, "direct purchase while open fixture")
	if ready:
		check(run("request_open_inspection").ok and observe("D001_A", "component_mark").ok, "grant active before purchase")
		check(purchase().ok and dto().customer.status == "bought" and not dto().customer.can_close and part("D001_A").is_empty(), "purchase automatically revokes customer scope")
		check(run("finish_component_visit").ok and part("D001_A").observations.size() == 1, "acquired evidence reappears in owned-workshop DTO")
		cleanup()

	ready = fresh("cooperative")
	check(ready, "exact closing decision fixture")
	if ready:
		check(run("advance_time", {"minutes": 240}).ok and run("advance_time", {"minutes": 240}).ok and run("advance_time", {"minutes": 115}).ok, "t595")
		before = rt.snapshot()
		check(not run("request_open_inspection").ok and rt.snapshot() == before, "request requires time for one new observation")
		check(run("advance_time", {"minutes": 5}).ok and purchase().ok, "final current trade allowed exactly at close")
		cleanup()
	print("CUSTOMER_INSPECTION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
