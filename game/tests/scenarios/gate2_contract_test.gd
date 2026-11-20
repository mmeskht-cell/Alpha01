extends SceneTree
const Session = preload("res://src/domain/game_session.gd")
const Fixture = preload("res://tests/fixtures/foundation_state.gd")
const Context = preload("res://tests/fixtures/gate0_c_state.gd")
const Catalog = preload("res://src/content/catalog_loader.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
const Audit = preload("res://src/domain/calendar_identity_audit.gd")
var checks: int = 0
var failures: int = 0
const P: Dictionary = {"contract_id":"supply_order"}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func fresh(cash: int = 400, mode: String = "", length: int = 7) -> RefCounted:
	var seed: Dictionary = Fixture.make()
	seed.wallets.player = {"VKC":cash,"USD":7}
	seed.wallets.seller.VKC = 100
	var v: Dictionary = Context.visit("clinic_sale","player","seller",{"parcel_002":{"VKC":60,"USD":0}})
	v.opens = 5760
	v.expires = 6360
	seed.visits = {"clinic_sale":v}
	var days: Array = []
	var schedule: Dictionary = {}
	for i: int in range(length):
		var d: String = "d" + str(i+1)
		days.append(d)
		schedule[d] = []
	schedule.d5 = ["clinic_sale"]
	var t: Dictionary = {"supplier":"seller","supply_id":"external_supply_1","offer_day":1,"due_day":4,"delivery_day":5,"extension_day":5,"price":{"VKC":300,"USD":0},"label_key":"fixture.supply"}
	if mode == "no_extension":
		t.extension_day = 0
	if mode == "bad_deadline":
		t.delivery_day = 3
	var contracts: Dictionary = {"supply_order":t}
	if mode == "duplicate_supply":
		contracts["other"] = t.duplicate(true)
	var facts: Dictionary = {
		"confirmed_supply":{"day":6,"source":"contract","source_id":"supply_order","outcome":"delivered","text_key":"fixture.supply_delivered"},
		"missed_supply":{"day":6,"source":"contract","source_id":"supply_order","outcome":"defaulted","text_key":"fixture.supply_default"},
		"confirmed_sale":{"day":6,"source":"trade","source_id":"clinic_sale","outcome":"traded","text_key":"fixture.clinic_supply"}}
	if mode == "bad_fact":
		facts.confirmed_sale.day = 5
	var profile: Dictionary = {"id":"demo_7" if length == 7 else "campaign_42","content_version":"obligation-1","day_ids":days,"visit_days":schedule,"contracts":contracts,"story_rules":facts}
	var catalog: Dictionary = Catalog.load_file("res://data/catalog/foundation.json")
	var s := Session.new()
	return s if catalog.ok and s.initialize(catalog.definitions,seed,false,false,profile) else null

func cmd(s: RefCounted, kind: String, id: String, payload: Dictionary = {}) -> Dictionary:
	return {"action_id":id,"expected_revision":s.snapshot().revision,"type":kind,"payload":payload}

func act(s: RefCounted,kind: String,id: String,payload: Dictionary = {}) -> bool:
	return s.execute(cmd(s,kind,id,payload)).ok

func reject(s: RefCounted,kind: String,id: String,payload: Dictionary = {}) -> bool:
	var before: Dictionary = s.snapshot()
	return not act(s,kind,id,payload) and s.snapshot() == before

func close(s: RefCounted,d: int) -> bool:
	return act(s,"calendar_close","c"+str(d))

func morning(s: RefCounted,d: int) -> bool:
	return act(s,"calendar_morning","m"+str(d))

func days(s: RefCounted,first: int,last: int) -> bool:
	for d: int in range(first,last+1):
		if not close(s,d) or not morning(s,d):
			return false
	return true

func status(s: RefCounted) -> String:
	return s.calendar_view().obligations.contracts.supply_order.status

func sell(s: RefCounted) -> bool:
	return act(s,"calendar_next_visit","clinic_call") and act(s,"trade","clinic_trade",{"visit_id":"clinic_sale","item_id":"parcel_002","seller":"player","buyer":"seller","currency":"VKC","amount":60,"inventory":"seller_grid","x":2,"y":0,"rotated":false})

func _initialize() -> void:
	var s: RefCounted = fresh()
	check(s != null,"valid contract profile")
	if s == null:
		quit(1)
		return
	for mode: String in ["bad_deadline","duplicate_supply","bad_fact"]:
		check(fresh(400,mode) == null,"reject "+mode)
	check(s.calendar_view().medicine.is_empty(),"no medicine mode")
	check(reject(s,"calendar_pay_contract","early",P),"unreserved payment")
	var reserve: Dictionary = cmd(s,"calendar_accept_contract","accept",P)
	check(s.execute(reserve).ok and status(s) == "reserved" and s.snapshot().wallets.player.VKC == 400,"reserve without payment")
	var after_accept: Dictionary = s.snapshot()
	var identity:Dictionary=Audit.audit(Audit.begin(s),s)
	check(identity.ok and identity.contract_supplies.external_supply_1=="reserved" and not identity.items.has("external_supply_1"),"typed contract resource")
	check(s.execute(reserve).ok and s.snapshot() == after_accept,"idempotent acceptance")
	check(reject(s,"calendar_accept_contract","duplicate",P),"one reservation")
	check(reject(s,"calendar_extend_contract","early_ext",P),"extension only due day")
	check(days(s,1,3) and s.snapshot().wallets.player.VKC == 355 and status(s) == "reserved","ordinary days only overhead")
	check(close(s,4) and status(s) == "paid" and s.snapshot().wallets.player.VKC == 40 and s.snapshot().wallets.seller.VKC == 400,"deadline after overhead actual payment")
	check(s.snapshot().calendar.contracts.supplies.external_supply_1.status == "paid","reserved supply not delivered yet")
	check(morning(s,4) and sell(s),"real separate sale")
	check(close(s,5) and status(s) == "delivered" and s.snapshot().wallets.player.VKC == 85,"delivery zero extra charge")
	check(s.snapshot().items.size() == 2 and s.snapshot().calendar.contracts.settlements.size() == 2,"external supply not personal stock")
	check(s.calendar_view().obligations.facts.is_empty(),"no premature fact")
	check(morning(s,5),"day6 morning")
	var view: Dictionary = s.calendar_view().obligations
	check(view.facts.has("confirmed_supply") and view.facts.confirmed_supply.cause_action == "c5" and view.facts.has("confirmed_sale") and view.facts.confirmed_sale.cause_action == "clinic_trade" and not view.facts.has("missed_supply"),"actual causal facts")
	check(reject(s,"calendar_pay_contract","repay",P),"no repeat payment")
	var saved: Dictionary = s.snapshot()
	identity=Audit.audit(Audit.begin(s),s)
	check(identity.ok and identity.contract_supplies.external_supply_1=="delivered" and s.snapshot()==saved,"delivered supply history separate")
	var restored: RefCounted = fresh()
	check(restored.restore(saved) and restored.snapshot() == saved,"cold replay")
	var fake: Dictionary = saved.duplicate(true)
	fake.calendar.contracts.facts.confirmed_supply.cause_action = "invented"
	check(not restored.restore(fake) and restored.snapshot() == saved,"forged fact")
	fake = saved.duplicate(true)
	fake.calendar.contracts.supplies.external_supply_1.status = "available"
	check(not restored.restore(fake),"forged supply")
	var repo := Repo.new("user://zt_rebuild/contracts_"+str(Time.get_ticks_usec()))
	check(repo.save_session(s,"contracts").ok,"disk save")
	var loaded: RefCounted = fresh()
	check(repo.load_session(loaded,"contracts").ok and loaded.snapshot() == saved,"disk restore")
	check(days(s,6,7) and s.calendar_view().complete and reject(s,"calendar_extend_contract","d8",P),"demo boundary")
	var poor: RefCounted = fresh(180)
	check(act(poor,"calendar_accept_contract","accept",P) and days(poor,1,4) and status(poor) == "defaulted","unfunded deadline")
	check(poor.snapshot().wallets.player.VKC == 120 and poor.snapshot().calendar.contracts.supplies.external_supply_1.status == "available","default no debit releases supply")
	check(days(poor,5,5) and poor.calendar_view().obligations.facts.has("missed_supply") and not poor.calendar_view().obligations.facts.has("confirmed_supply"),"failure fact not treatment")
	var ext: RefCounted = fresh(350)
	check(act(ext,"calendar_accept_contract","accept",P) and days(ext,1,3),"extension setup")
	check(act(ext,"calendar_extend_contract","extend",P) and reject(ext,"calendar_extend_contract","second",P),"once only")
	check(close(ext,4) and status(ext) == "reserved" and ext.snapshot().wallets.player.VKC == 290,"no premature collection")
	check(morning(ext,4) and sell(ext) and close(ext,5) and status(ext) == "delivered" and ext.snapshot().wallets.player.VKC == 35,"same-day extended payment then delivery")
	check(ext.snapshot().calendar.contracts.settlements[0].kind == "payment" and ext.snapshot().calendar.contracts.settlements[1].kind == "delivery" and ext.snapshot().calendar.contracts.settlements[0].minute == 6360,"ordered real settlement")
	var denied: RefCounted = fresh(350,"no_extension")
	check(act(denied,"calendar_accept_contract","accept",P) and days(denied,1,3) and reject(denied,"calendar_extend_contract","denied",P) and close(denied,4) and status(denied) == "defaulted","unapproved extension denied")
	var declined: RefCounted = fresh()
	check(act(declined,"calendar_decline_contract","decline",P) and days(declined,1,5) and status(declined) == "declined" and declined.snapshot().calendar.contracts.settlements.is_empty(),"decline never pays")
	var missed: RefCounted = fresh()
	check(days(missed,1,5) and status(missed) == "missed" and missed.snapshot().calendar.contracts.settlements.is_empty(),"ignored offer no automatic purchase")
	var prepaid: RefCounted = fresh()
	check(act(prepaid,"calendar_accept_contract","accept",P) and act(prepaid,"calendar_pay_contract","prepay",P) and days(prepaid,1,5) and status(prepaid) == "delivered" and prepaid.snapshot().calendar.contracts.settlements.size() == 2,"explicit early payment no duplicate")
	var full: RefCounted = fresh(400,"",42)
	check(full != null and act(full,"calendar_accept_contract","accept",P) and days(full,1,42) and full.calendar_view().complete and full.snapshot().calendar.contracts.settlements.size() == 2,"42-day same finite contract no recurrence")
	print("GATE2_A1C3_CONTRACT_CHECKS=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
