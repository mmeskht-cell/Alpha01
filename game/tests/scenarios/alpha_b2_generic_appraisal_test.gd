extends SceneTree
## B2 T03: four existing, genuinely owned catalogue items use one generic
## inspection command/drawer/offer, with current functional state only after
## inspection. No invented wear, seals, batches or additional store stock.
const Seed = preload("res://src/content/alpha_b2_cards_seed.gd")
const Session = preload("res://src/domain/game_session.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
	return ok

func fresh(item_override: String = "", field: String = "", value: Variant = null) -> RefCounted:
	var source: Dictionary = Seed.content()
	if source.is_empty():
		return null
	if not item_override.is_empty():
		source.state.items[item_override][field] = value
	var s := Session.new()
	if not s.initialize(source.defs,source.state,false,false,{},source.alpha_profile):
		printerr("B2_GENERIC_APPRAISAL_INIT: ",s.initialization_error())
		return null
	return s

func command(s: RefCounted, action: String, payload: Dictionary = {}) -> Dictionary:
	return {"action_id":"b2_appraisal_"+str(s.snapshot().revision+1),"expected_revision":s.snapshot().revision,"type":action,"payload":payload}

func go(s: RefCounted, action: String, payload: Dictionary = {}) -> bool:
	var result: Dictionary = s.execute(command(s,action,payload))
	if not result.ok:
		printerr("B2_GENERIC_ACTION ",action," ",result)
	return result.ok

func deny(s: RefCounted, action: String, payload: Dictionary = {}) -> bool:
	var previous: Dictionary = s.snapshot()
	return not s.execute(command(s,action,payload)).ok and s.snapshot() == previous

func tools_contain(options: Array, slot: String) -> bool:
	for tool: Dictionary in options:
		if tool.id == slot:
			return true
	return false

func visit_case(s: RefCounted, visit_id: String, item_id: String, kind: String, slot: String, expected: String) -> void:
	var view: Dictionary = s.alpha_view()
	check(view.active.id == visit_id and view.appraisal.item_id == item_id and view.appraisal.def_id == kind,"correct original visit/item/definition "+visit_id)
	check(tools_contain(view.appraisal.tools,slot),"data-only tool is available for real "+kind)
	check(deny(s,"alpha_inspect",{"slot":"forged_condition"}),"unconfigured tool cannot reveal private fields "+kind)
	var previous: Dictionary = s.snapshot()
	if not check(go(s,"alpha_inspect",{"slot":slot}),"real condition observed on "+item_id):
		return
	view = s.alpha_view()
	check(view.appraisal.cards.size() == 1 and view.appraisal.cards[0].value == expected and view.appraisal.cards[0].kind == "fact","inspection reads actual authorized item state "+item_id)
	check(view.npc_context.current_offer.is_empty() and view.appraisal.cards[0].selected == false,"observed condition remains private "+item_id)
	check(s.snapshot().items[item_id] == previous.items[item_id] and s.snapshot().wallets == previous.wallets and s.snapshot().ledger == previous.ledger,"investigation does not modify item/title/currency "+item_id)
	check(deny(s,"alpha_inspect",{"slot":slot}),"same condition cannot be farmed repeatedly "+item_id)
	check(go(s,"alpha_card_toggle",{"slot":slot,"selected":true}),"player voluntarily shares inspected evidence "+item_id)
	check(go(s,"alpha_price_offer",{"amount":1}),"same one-offer authority handles "+kind)
	view = s.alpha_view()
	check(view.npc_context.current_offer.response == "declined" and view.npc_context.current_offer.public_slots == [slot] and view.npc_context.current_offer.known_slots == [slot],"opponent hears only explicitly shared evidence "+item_id)
	check(view.appraisal.cards[0].ever_disclosed and s.snapshot().items[item_id] == previous.items[item_id] and s.snapshot().wallets == previous.wallets and s.snapshot().ledger == previous.ledger,"declined evidence offer creates no money, stock or free transaction "+item_id)

func traverse(s: RefCounted, cases: Dictionary, last_day: int) -> bool:
	for day: int in range(1,last_day+1):
		if not go(s,"alpha_open"):
			return false
		var rows: Array = s.snapshot().alpha_shop.profile.days[day-1]
		for row: Dictionary in rows:
			if not go(s,"alpha_next_customer") or not go(s,"alpha_ack_entry"):
				return false
			var visit_id: String = str(row.id)
			if cases.has(visit_id):
				var sample: Dictionary = cases[visit_id]
				visit_case(s,visit_id,str(sample.item),str(sample.def_id),str(sample.slot),str(sample.expected))
			if not go(s,"alpha_finish_customer") or not go(s,"alpha_ack_exit"):
				return false
		if not go(s,"alpha_close") or not go(s,"alpha_settle"):
			return false
		if day < last_day and (not go(s,"alpha_next_day") or not go(s,"alpha_prepare_day")):
			return false
	return true

func _initialize() -> void:
	var source: Dictionary = Seed.content()
	if not check(not source.is_empty(),"B2 source is not replaced"):
		quit(1)
		return
	var sample_ids: Array = ["WAT02","BAT02","TL04","HY05"]
	check(source.state.items.size() > sample_ids.size(),"four cases use existing real stock; no item injection")
	var actual_provenance: Dictionary = {"WAT02":"p2_watch_a","BAT02":"demo_BAT02","TL04":"demo_TL04","HY05":"demo_HY05"}
	for item_id: String in sample_ids:
		check(source.state.items[item_id].provenance_id == actual_provenance[item_id] and source.state.items[item_id].functional,"appraisal manifest bound to original real seed "+item_id)
	var s: RefCounted = fresh()
	if not check(s != null,"multi-item inspection source accepted without new UI or store wallets"):
		quit(1)
		return
	var before: Dictionary = s.snapshot()
	var cases: Dictionary = {
		"watch_a":{"item":"WAT02","def_id":"fictional_watch_p2","slot":"function_detail","expected":"serviceable"},
		"battery_buy":{"item":"BAT02","def_id":"battery","slot":"condition_detail","expected":"serviceable"},
		"tool_buy":{"item":"TL04","def_id":"demo_tool","slot":"condition_detail","expected":"serviceable"},
		"hygiene_buy":{"item":"HY05","def_id":"demo_hygiene","slot":"condition_detail","expected":"serviceable"}
	}
	check(traverse(s,cases,5),"all four original item categories inspected in their actual dated visits")
	var after: Dictionary = s.snapshot()
	check(after.items == before.items and after.wallets == before.wallets and after.ledger == before.ledger,"five days of rejected appraisal offers never create economy or items")
	check(after.alpha_shop.appraisal.visits.has("watch_a") and after.alpha_shop.appraisal.visits.has("battery_buy") and after.alpha_shop.appraisal.visits.has("tool_buy") and after.alpha_shop.appraisal.visits.has("hygiene_buy"),"all evidence/offer receipts live under original visits")
	var db := Repo.new("user://zt_rebuild/b2_generic_appraisal_"+str(Time.get_ticks_usec()))
	check(db.save_session(s,"generic").ok,"save four item categories in one campaign history")
	var loaded: RefCounted = fresh()
	check(loaded != null and db.load_session(loaded,"generic").ok and loaded.snapshot() == after,"cold replay preserves all item evidence without money changes")
	var tampered: Dictionary = after.duplicate(true)
	tampered.alpha_shop.appraisal.visits.battery_buy.observed.condition_detail.value = "inoperable"
	check(not s.restore(tampered) and s.snapshot() == after,"forged state reading cannot survive deterministic command replay")
	var damaged: RefCounted = fresh("BAT02","functional",false)
	if check(damaged != null,"functional condition test starts from otherwise unchanged authored item"):
		check(traverse(damaged,{"battery_buy":{"item":"BAT02","def_id":"battery","slot":"condition_detail","expected":"inoperable"}},2),"same tool sees current defective item state rather than fixed optimistic specimen")
	var wrong_origin: RefCounted = fresh("BAT02","provenance_id","unrelated_source")
	if check(wrong_origin != null,"unrelated provenance remains a valid isolated test seed"):
		check(go(wrong_origin,"alpha_open"),"provenance negative visit starts")
		for row: Dictionary in wrong_origin.snapshot().alpha_shop.profile.days[0]:
			check(go(wrong_origin,"alpha_next_customer") and go(wrong_origin,"alpha_ack_entry") and go(wrong_origin,"alpha_finish_customer") and go(wrong_origin,"alpha_ack_exit"),"D1 unrelated no-leak visit")
		check(go(wrong_origin,"alpha_close") and go(wrong_origin,"alpha_settle") and go(wrong_origin,"alpha_next_day") and go(wrong_origin,"alpha_prepare_day") and go(wrong_origin,"alpha_open"),"D2 provenance negative starts")
		for row: Dictionary in wrong_origin.snapshot().alpha_shop.profile.days[1]:
			check(go(wrong_origin,"alpha_next_customer") and go(wrong_origin,"alpha_ack_entry"),"D2 real visitor")
			if row.id == "battery_buy":
				check(not tools_contain(wrong_origin.alpha_view().appraisal.tools,"condition_detail"),"mismatched item provenance forbids configurable condition inspection")
				check(deny(wrong_origin,"alpha_inspect",{"slot":"condition_detail"}),"forged provenance cannot expose actual function truth")
				break
			check(go(wrong_origin,"alpha_finish_customer") and go(wrong_origin,"alpha_ack_exit"),"continue to actual battery buyer")
	print("ALPHA_B2_GENERIC_APPRAISAL_CHECKS=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
