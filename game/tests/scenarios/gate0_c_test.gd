extends SceneTree
const Session = preload("res://src/domain/game_session.gd")
const Fixture = preload("res://tests/fixtures/gate0_c_state.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const Rules = preload("res://src/domain/value_rules.gd")
const Format = preload("res://src/domain/snapshot_format.gd")
const Saves = preload("res://src/persistence/save_repository.gd")
var checks: Dictionary = {}
var failures: Dictionary = {}
var case_id: String = "C02"

func check(condition: bool, label: String) -> void:
	checks[case_id] = checks.get(case_id, 0) + 1
	if not condition:
		failures[case_id] = failures.get(case_id, 0) + 1
		printerr("FAIL ", case_id, ": ", label)

func session(initial: Dictionary = {}) -> RefCounted:
	var result := Session.new()
	check(result.initialize(Fixture.definitions(), Fixture.make() if initial.is_empty() else initial), "initial state valid")
	return result

func command(s: RefCounted, kind: String, payload: Dictionary, id: String = "") -> Dictionary:
	return {"action_id": id if not id.is_empty() else "c_" + str(s.snapshot().revision), "expected_revision": s.snapshot().revision, "type": kind, "payload": payload}

func run(s: RefCounted, kind: String, payload: Dictionary, id: String = "") -> Dictionary:
	return s.execute(command(s, kind, payload, id))

func reject(s: RefCounted, kind: String, payload: Dictionary, label: String) -> void:
	var before: Dictionary = s.snapshot()
	check(not run(s, kind, payload).ok and s.snapshot() == before, label)

func detached(s: RefCounted, id: String, x: int, y: int) -> Dictionary:
	return run(s, "detach", {"actor": "player", "root_id": "X01", "child_id": id, "inventory": "player_grid", "x": x, "y": y, "rotated": false})

func workshop(s: RefCounted) -> void:
	# Trusted phase fixture; no player command can set phase/rights/visits.
	var snapshot: Dictionary = s.snapshot()
	snapshot.phase = "workshop"
	check(s.restore(snapshot), "workshop context")

func _initialize() -> void:
	var s: RefCounted = session()
	check(s.snapshot().items.size() == 4, "all child IDs exist before purchase")
	check(s.execute(Fixture.purchase()).ok, "purchase succeeds")
	check(s.snapshot().wallets.player.VKC == 110 and s.snapshot().wallets.seller.VKC == 70, "70 VKC transferred")
	check(s.snapshot().items.X01.basis.VKC == 20 and s.snapshot().items.X01_A.basis.VKC == 30 and s.snapshot().items.X01_B.basis.VKC == 10 and s.snapshot().items.X01_C.basis.VKC == 10, "exact weighted allocation")
	var day_options:Dictionary=s.composition_options("X01","player_grid")
	check(not day_options.is_empty() and not day_options.enabled and day_options.slots[0].detach.is_empty(),"day composition options read only")
	workshop(s)
	var original:Dictionary=s.snapshot()
	var preview_options:Dictionary=s.composition_options("X01","player_grid")
	check(preview_options.enabled and preview_options.slots.size()==3 and not preview_options.slots[0].detach.is_empty() and s.snapshot()==original,"composition preview has valid placement and no mutation")
	var candidate:RefCounted=session()
	check(candidate.restore(original),"composition preview independent fixture")
	var removal:Dictionary=preview_options.slots[0].detach
	check(run(candidate,"detach",removal).ok,"preview accepted by real authority")
	var after_removal:Dictionary=candidate.snapshot()
	var reattach:Dictionary=candidate.composition_options("X01","player_grid")
	check(reattach.slots[0].item_id=="" and reattach.slots[0].attach.size()==1 and candidate.snapshot()==after_removal,"empty slot allows matching detached part only")
	check(run(candidate,"attach",reattach.slots[0].attach[0]).ok and Objects.basis(candidate.snapshot(),candidate.snapshot().items.keys()).basis.VKC==70,"preview reattach preserves cost")
	check(detached(s, "X01_A", 4, 0).ok and detached(s, "X01_B", 5, 0).ok, "recover two existing IDs")
	var recovered: Dictionary = s.snapshot()
	check(recovered.items.size() == 4 and recovered.items.X01_A.parent_id == "" and recovered.items.X01_B.parent_id == "" and recovered.items.X01_C.parent_id == "X01", "identity and parent preservation")
	check(Objects.basis(recovered, recovered.items.keys()).basis.VKC == 70, "basis conserved")
	var copy: RefCounted = session()
	check(copy.restore(recovered), "isolated reattach fixture")
	check(run(copy, "attach", {"actor": "player", "root_id": "X01", "child_id": "X01_A"}).ok and Objects.basis(copy.snapshot(), copy.snapshot().items.keys()).basis.VKC == 70, "reattach preserves IDs and costs")
	_replacement_calendar()
	_civilian_cycle()
	case_id = "C03"
	reject(copy, "attach", {"actor": "player", "root_id": "X01", "child_id": "X01_A"}, "attached child cannot attach twice")
	reject(copy, "attach", {"actor": "player", "root_id": "X01", "child_id": "X01"}, "cycle rejected")
	reject(s, "move", {"actor": "player", "item_id": "X01_A", "inventory": "player_grid", "x": 5, "y": 0, "rotated": false}, "collision no mutation")
	reject(s, "move", {"actor": "player", "item_id": "X01", "inventory": "player_grid", "x": 9, "y": 5, "rotated": false}, "out of bounds no mutation")
	var invalid: Dictionary = s.snapshot()
	invalid.items.X01.parent_id = "X01_C"
	check(not s.restore(invalid) and s.snapshot() == recovered, "cyclic save rejected")
	case_id = "C04"
	var all_player: bool = true
	for item: Dictionary in recovered.items.values():
		all_player = all_player and item.owner_id == "player" and item.custodian_id == "player"
	check(all_player, "whole-tree ownership transferred")
	var locked: RefCounted = session()
	var locked_state: Dictionary = recovered.duplicate(true)
	locked_state.items.X01_C.protected = true
	check(locked.restore(locked_state), "protected child fixture")
	reject(locked, "discard", {"actor": "player", "item_id": "X01", "confirmed_ids": ["X01", "X01_C"]}, "protected descendant blocks disposal")
	reject(locked, "detach", {"actor": "player", "root_id": "X01", "child_id": "X01_C", "inventory": "player_grid", "x": 6, "y": 0, "rotated": false}, "protected descendant blocks composition")
	case_id = "C06"
	var preview: Dictionary = s.discard_preview("X01")
	check(preview.ok and preview.item_ids == ["X01", "X01_C"] and preview.basis.VKC == 30 and s.snapshot() == recovered, "read-only exact discard preview")
	reject(s, "discard", {"actor": "player", "item_id": "X01", "confirmed_ids": ["X01"]}, "missing child confirmation rejected")
	var discard: Dictionary = command(s, "discard", {"actor": "player", "item_id": "X01", "confirmed_ids": preview.item_ids}, "discard")
	var result: Dictionary = s.execute(discard)
	check(result.ok, "discard commits")
	var final_state: Dictionary = s.snapshot()
	check(final_state.items.keys().size() == 2 and final_state.items.has("X01_A") and final_state.items.has("X01_B") and final_state.tombstones.has("X01") and final_state.tombstones.has("X01_C"), "active and terminal IDs")
	check(final_state.wallets == recovered.wallets and Objects.basis(final_state, final_state.items.keys()).basis.VKC == 40 and final_state.object_events.back().basis.VKC == 30, "cash unchanged, 40 retained plus 30 loss")
	check(s.execute(discard) == result and s.snapshot() == final_state, "discard retry no second loss")
	reject(s, "discard", discard.payload, "new ID cannot discard terminal object")
	invalid = final_state.duplicate(true)
	invalid.items.X01 = recovered.items.X01
	check(not s.restore(invalid), "tombstone resurrection refused")
	case_id = "C01"
	var single_state: Dictionary = Fixture.make()
	single_state.items = {}
	single_state.visits = {}
	single_state.game_minutes = 15
	single_state.wallets.buyer.USD = 9
	single_state.items["S01"] = Objects.fresh_item("sample_consumable", "seller", "seller_grid", 0, 0, "fixture_single")
	single_state.visits["single_buy"] = Fixture.visit("single_buy", "seller", "player", {"S01": {"VKC": 80, "USD": 0}})
	single_state.visits["single_sell"] = Fixture.visit("single_sell", "player", "buyer", {"S01": {"VKC": 0, "USD": 2}})
	single_state.visits["single_return"] = Fixture.visit("single_return", "buyer", "player", {"S01": {"VKC": 70, "USD": 0}})
	var single: RefCounted = session(single_state)
	var buy: Dictionary = {"item_id": "S01", "seller": "seller", "buyer": "player", "currency": "VKC", "amount": 80, "inventory": "player_grid", "x": 9, "y": 5, "rotated": true, "visit_id": "single_buy"}
	check(run(single, "trade", buy).ok and single.snapshot().wallets.player.VKC == 100 and single.snapshot().game_minutes == 15, "80 VKC/t15 foundation contract, 10x6 far corner")
	check(run(single, "move", {"actor": "player", "item_id": "S01", "inventory": "player_grid", "x": 8, "y": 5, "rotated": false}).ok, "single rotation/move")
	var sale: Dictionary = {"item_id": "S01", "seller": "player", "buyer": "buyer", "currency": "USD", "amount": 2, "inventory": "buyer_grid", "x": 0, "y": 0, "rotated": false, "visit_id": "single_sell"}
	check(run(single, "trade", sale).ok and single.snapshot().wallets.player.USD == 2 and single.snapshot().wallets.buyer.USD == 7 and single.snapshot().wallets.player.VKC == 100, "separate currency sale")
	check(single.snapshot().ledger.back().basis.VKC == 80 and single.snapshot().ledger.back().basis.USD == 0, "sale recognizes whole original basis separately from proceeds")
	case_id = "C03"
	var unmatched_state: Dictionary = recovered.duplicate(true)
	unmatched_state.items["junk"] = Objects.fresh_item("sample_consumable", "player", "player_grid", 6, 0, "fixture_junk")
	var unmatched: RefCounted = session()
	check(unmatched.restore(unmatched_state), "unmatched fixture")
	reject(unmatched, "attach", {"actor": "player", "root_id": "X01", "child_id": "junk"}, "fictional compatibility tag refused")
	var crowded_state: Dictionary = recovered.duplicate(true)
	crowded_state.items.X01.x = 7
	crowded_state.items.X01.y = 5
	var crowded: RefCounted = session()
	check(crowded.restore(crowded_state), "small profile fits bottom row")
	reject(crowded, "attach", {"actor": "player", "root_id": "X01", "child_id": "X01_B"}, "composition footprint growth insufficient space")
	invalid = recovered.duplicate(true)
	invalid.items.X01_C.inventory = "player_grid"
	check(not s.restore(invalid), "attached child cannot have second placement")
	case_id = "C04"
	var reserved_state: Dictionary = recovered.duplicate(true)
	reserved_state.items.X01_A.reservation_id = "reserved_contract"
	reserved_state.items.X01_A.status = "reserved"
	var reserved: RefCounted = session()
	check(reserved.restore(reserved_state), "reservation fixture")
	reject(reserved, "move", {"actor": "player", "item_id": "X01_A", "inventory": "player_grid", "x": 7, "y": 0, "rotated": false}, "reserved item move refused")
	reject(reserved, "discard", {"actor": "player", "item_id": "X01_A", "confirmed_ids": ["X01_A"]}, "reserved disposal refused")
	var custody_state: Dictionary = recovered.duplicate(true)
	for id: String in ["X01", "X01_C"]:
		custody_state.items[id].owner_id = "seller"
		custody_state.items[id].status = "custody_pawn"
	var custody: RefCounted = session()
	check(custody.restore(custody_state), "separate owner/custodian fixture")
	reject(custody, "discard", {"actor": "player", "item_id": "X01", "confirmed_ids": ["X01", "X01_C"]}, "custody-only disposal refused")
	reject(custody, "detach", {"actor": "player", "root_id": "X01", "child_id": "X01_C", "inventory": "player_grid", "x": 7, "y": 0, "rotated": false}, "custody-only composition refused")
	case_id = "C05"
	var deadline: Dictionary = Fixture.make()
	deadline.visits.purchase.expires = 5
	deadline.game_minutes = 5
	var expired_observation: RefCounted = session(deadline)
	reject(expired_observation, "observe", {"actor": "player", "item_id": "X01", "key": "functional"}, "new observation cannot finish beyond visit")
	deadline.game_minutes = 4
	var last_observation: RefCounted = session(deadline)
	check(run(last_observation, "observe", {"actor": "player", "item_id": "X01", "key": "functional"}).ok and last_observation.snapshot().game_minutes == 5, "exact visit end allowed")
	check(last_observation.knowledge_view("X01").observations.size() == 1, "known evidence review at visit end")
	deadline.visits.purchase.expires = 600
	deadline.game_minutes = 600
	var closed_observation: RefCounted = session(deadline)
	reject(closed_observation, "observe", {"actor": "player", "item_id": "X01", "key": "functional"}, "closing permits trade not new observation")
	check(closed_observation.execute({"action_id": "last_sale", "expected_revision": 0, "type": "trade", "payload": Fixture.purchase().payload.merged({"visit_id": "purchase"})}).ok, "closing transaction remains available")
	var protected_observation: Dictionary = Fixture.make()
	protected_observation.items.X01.protected = true
	var protected_session: RefCounted = session(protected_observation)
	reject(protected_session, "observe", {"actor": "player", "item_id": "X01_A", "key": "functional"}, "protected ancestor blocks new observation")
	var denied_observation: Dictionary = Fixture.make()
	denied_observation.visits.purchase.allow_inspection = false
	var denied_session: RefCounted = session(denied_observation)
	reject(denied_session, "observe", {"actor": "player", "item_id": "X01", "key": "functional"}, "no visit consent")
	var knowledge: RefCounted = session()
	check(knowledge.knowledge_view("X01").quality == "unknown", "hidden broken truth remains unknown")
	var secret_test: Dictionary = knowledge.knowledge_view("X01")
	check(not secret_test.has("functional") and not secret_test.has("hidden_economy") and not secret_test.has("basis") and secret_test.observations.is_empty(), "public DTO whitelist")
	check(knowledge.knowledge_view("X01", "seller").is_empty(), "unauthorized observer denied")
	reject(knowledge, "observe", {"actor": "player", "item_id": "X01", "key": "hidden_economy"}, "private observation key refused")
	reject(knowledge, "observe", {"actor": "player", "item_id": "X01", "key": "functional", "observed_value": true}, "client cannot inject evidence")
	for id: String in ["X01_A", "X01_B", "X01_C"]:
		for field: String in ["functional", "restored", "complete"]:
			check(run(knowledge, "observe", {"actor": "player", "item_id": id, "key": field}).ok, "authority observation " + id + "/" + field)
	check(knowledge.knowledge_view("X01_A").quality == "serviceable" and knowledge.knowledge_view("X01_B").quality == "refurbished" and knowledge.knowledge_view("X01_C").quality == "inoperable", "three quality labels from observations only")
	var before_view: Dictionary = knowledge.snapshot()
	knowledge.knowledge_view("X01_A")
	check(knowledge.snapshot() == before_view, "free evidence reread")
	reject(knowledge, "observe", {"actor": "player", "item_id": "X01_A", "key": "functional"}, "duplicate evidence does not charge time")
	var restoration_state: Dictionary = Fixture.make()
	restoration_state.wallets.player.USD = 3
	var restoration: RefCounted = session(restoration_state)
	check(restoration.execute(Fixture.purchase()).ok, "restoration stock purchase")
	for field: String in ["functional", "restored", "complete"]:
		check(run(restoration, "observe", {"actor": "player", "item_id": "X01", "key": field}).ok, "root observation")
	workshop(restoration)
	check(run(restoration, "restore_item", {"actor": "player", "item_id": "X01"}).ok, "restore current function with historical flag")
	check(restoration.snapshot().wallets.player.VKC == 105 and restoration.snapshot().wallets.player.USD == 1 and restoration.snapshot().items.X01.basis == {"VKC": 25, "USD": 2}, "direct expense once in two currencies")
	var view: Dictionary = restoration.knowledge_view("X01")
	check(view.quality == "unknown" and view.observations.size() == 3, "changed observations stale, history retained")
	var current_count: int = 0
	for record: Dictionary in view.observations:
		if record.current:
			current_count += 1
	check(current_count == 1, "unrelated composition evidence remains current")
	reject(restoration, "restore_item", {"actor": "player", "item_id": "X01"}, "no infinite repeat restoration")
	var recurrence: Dictionary = restoration.snapshot()
	recurrence.items.X01.functional = false
	recurrence.items.X01.version += 1
	recurrence.items.X01.field_versions.functional += 1
	recurrence.phase = "shop"
	check(restoration.restore(recurrence), "trusted synthetic recurrence fixture")
	check(run(restoration, "observe", {"actor": "player", "item_id": "X01", "key": "functional"}).ok and restoration.knowledge_view("X01").quality == "inoperable" and restoration.snapshot().items.X01.restored, "recurrence takes precedence over restoration history")
	case_id = "C07"
	var box_state: Dictionary = recovered.duplicate(true)
	box_state.items["BOX"] = Objects.fresh_item("sample_box", "player", "player_grid", 0, 3, "fixture_box")
	box_state.inventories["box_inside"] = {"owner_id": "player", "width": 3, "height": 2, "host_item": "BOX"}
	box_state.items.X01_A.inventory = "box_inside"
	box_state.items.X01_A.x = 0
	box_state.items.X01_A.y = 0
	var protected_dest: Dictionary = box_state.duplicate(true)
	protected_dest.items.BOX.protected = true
	var locked_box: RefCounted = session()
	check(locked_box.restore(protected_dest), "protected destination fixture")
	reject(locked_box, "move", {"actor": "player", "item_id": "X01_B", "inventory": "box_inside", "x": 1, "y": 0, "rotated": false}, "protected destination rejects free-cell insertion")
	reject(locked_box, "detach", {"actor": "player", "root_id": "X01", "child_id": "X01_C", "inventory": "box_inside", "x": 1, "y": 0, "rotated": false}, "protected destination rejects detachment")
	protected_dest.items.BOX.protected = false
	protected_dest.items.BOX.status = "reserved"
	protected_dest.items.BOX.reservation_id = "reserved_box"
	check(locked_box.restore(protected_dest), "reserved destination fixture")
	reject(locked_box, "move", {"actor": "player", "item_id": "X01_B", "inventory": "box_inside", "x": 1, "y": 0, "rotated": false}, "reserved destination rejects insertion")
	var incoming: Dictionary = Fixture.make()
	incoming.items["BOX"] = Objects.fresh_item("sample_box", "player", "player_grid", 0, 3, "fixture_box")
	incoming.items.BOX.protected = true
	incoming.inventories["box_inside"] = {"owner_id": "player", "width": 3, "height": 2, "host_item": "BOX"}
	var incoming_session: RefCounted = session(incoming)
	var purchase_into: Dictionary = Fixture.purchase().payload.duplicate(true)
	purchase_into.inventory = "box_inside"
	purchase_into["visit_id"] = "purchase"
	reject(incoming_session, "trade", purchase_into, "protected destination rejects purchase without cash or title transfer")
	incoming.items.BOX.protected = false
	check(incoming_session.restore(incoming) and run(incoming_session, "trade", purchase_into).ok, "unlocked destination permits full-family purchase")
	var box: RefCounted = session()
	check(box.restore(box_state), "atomic box with separately placed content")
	var content_before: Dictionary = box.snapshot().items.X01_A
	check(run(box, "move", {"actor": "player", "item_id": "BOX", "inventory": "player_grid", "x": 8, "y": 3, "rotated": true}).ok and box.snapshot().items.X01_A == content_before, "box move preserves contained identity/location/cost")
	reject(box, "move", {"actor": "player", "item_id": "BOX", "inventory": "box_inside", "x": 0, "y": 0, "rotated": false}, "container nesting refused")
	reject(box, "move", {"actor": "player", "item_id": "X01_B", "inventory": "box_inside", "x": 0, "y": 0, "rotated": false}, "interior collision refused")
	reject(box, "discard", {"actor": "player", "item_id": "BOX", "confirmed_ids": ["BOX"]}, "filled box disposal refused")
	var box_sale: Dictionary = box.snapshot()
	box_sale.phase = "shop"
	box_sale.visits["box_sale"] = Fixture.visit("box_sale", "player", "buyer", {"BOX": {"VKC": 5, "USD": 0}})
	check(box.restore(box_sale), "stored box sale context")
	reject(box, "trade", {"visit_id": "box_sale", "item_id": "BOX", "seller": "player", "buyer": "buyer", "currency": "VKC", "amount": 5, "inventory": "buyer_grid", "x": 0, "y": 0, "rotated": false}, "filled box sale refused")
	case_id = "C08"
	reject(single, "trade", sale, "same visit cannot settle twice")
	var rebuy: Dictionary = buy.duplicate(true)
	rebuy.visit_id = "single_return"
	rebuy.seller = "buyer"
	rebuy.amount = 70
	check(run(single, "trade", rebuy).ok and single.snapshot().items.S01.owner_id == "player" and single.snapshot().items.S01.basis.VKC == 70, "later stored visit can trade same object, new basis")
	var multi_state: Dictionary = recovered.duplicate(true)
	multi_state.phase = "shop"
	multi_state.wallets.buyer.USD = 4
	multi_state.visits["delivery"] = Fixture.visit("delivery", "player", "buyer", {"X01_A": {"VKC": 50, "USD": 0}, "X01_B": {"VKC": 10, "USD": 2}}, true)
	multi_state.visits["ordinary"] = Fixture.visit("ordinary", "player", "buyer", {"X01_A": {"VKC": 50, "USD": 0}, "X01_B": {"VKC": 10, "USD": 0}})
	var multi: RefCounted = session()
	check(multi.restore(multi_state), "stored multi-ID contract")
	var places: Array = [{"item_id": "X01_A", "inventory": "buyer_grid", "x": 0, "y": 0, "rotated": false}, {"item_id": "X01_B", "inventory": "buyer_grid", "x": 1, "y": 0, "rotated": false}]
	reject(multi, "deliver", {"visit_id": "ordinary", "placements": places}, "ordinary visit cannot use multi delivery")
	var collision: Array = places.duplicate(true)
	collision[1].x = 0
	reject(multi, "deliver", {"visit_id": "delivery", "placements": collision}, "multi-delivery collision rolls back all cash/ownership/context")
	reject(multi, "deliver", {"visit_id": "delivery", "placements": [places[0], places[0]]}, "duplicate contract IDs refused")
	check(run(multi, "deliver", {"visit_id": "delivery", "placements": places}).ok and multi.snapshot().items.X01_A.owner_id == "buyer" and multi.snapshot().items.X01_B.owner_id == "buyer", "multi-ID atomic delivery")
	check(multi.snapshot().wallets.player.VKC == 170 and multi.snapshot().wallets.player.USD == 2 and multi.snapshot().wallets.buyer.VKC == 140 and multi.snapshot().wallets.buyer.USD == 2, "multi-currency contract accounting")
	reject(multi, "deliver", {"visit_id": "delivery", "placements": places}, "completed special contract cannot repeat")
	case_id = "C04"
	var service_state: Dictionary = Fixture.make()
	service_state.wallets.player.USD = 3
	service_state.phase = "workshop"
	for id: String in service_state.items:
		service_state.items[id].custodian_id = "player"
		service_state.items[id].status = "custody_service"
	service_state.items.X01.inventory = "player_grid"
	var service: RefCounted = session(service_state)
	reject(service, "restore_item", {"actor": "player", "item_id": "X01"}, "service without explicit permission refused")
	service_state.items.X01.service_permission = true
	check(service.restore(service_state), "explicit service authorization fixture")
	var customer_basis: Dictionary = service.snapshot().items.X01.basis.duplicate(true)
	check(run(service, "restore_item", {"actor": "player", "item_id": "X01"}).ok and service.snapshot().items.X01.owner_id == "seller" and service.snapshot().items.X01.basis == customer_basis, "service restores without taking ownership or adding cost to customer inventory")
	check(service.snapshot().wallets.player.VKC == 175 and service.snapshot().wallets.player.USD == 1 and service.snapshot().object_events.back().expenses == {"VKC": 5, "USD": 2}, "service expense recorded separately")
	reject(service, "discard", {"actor": "player", "item_id": "X01", "confirmed_ids": ["X01", "X01_A", "X01_B", "X01_C"]}, "service permission cannot authorize disposal")
	case_id = "C07"
	check(run(box, "move", {"actor": "player", "item_id": "X01_A", "inventory": "player_grid", "x": 6, "y": 0, "rotated": false}).ok, "empty box by moving original content")
	check(run(box, "trade", {"visit_id": "box_sale", "item_id": "BOX", "seller": "player", "buyer": "buyer", "currency": "VKC", "amount": 5, "inventory": "buyer_grid", "x": 0, "y": 0, "rotated": false}).ok and box.snapshot().inventories.box_inside.owner_id == "buyer", "empty box sale updates interior custody")
	var composite_box_state: Dictionary = recovered.duplicate(true)
	composite_box_state.items["BOX"] = Objects.fresh_item("sample_box", "player", "player_grid", 0, 3, "fixture_composite_box")
	composite_box_state.inventories["box_inside"] = {"owner_id": "player", "width": 3, "height": 2, "host_item": "BOX"}
	composite_box_state.items.X01.inventory = "box_inside"
	var composite_box: RefCounted = session()
	check(composite_box.restore(composite_box_state), "composite root inside atomic box, child inherits parent")
	check(run(composite_box, "move", {"actor": "player", "item_id": "BOX", "inventory": "player_grid", "x": 8, "y": 3, "rotated": false}).ok and composite_box.snapshot().items.X01_C.parent_id == "X01", "box moves composite and attached child without duplicate placement")
	case_id = "C08"
	var ordinary: RefCounted = session()
	check(ordinary.restore(multi_state), "ordinary alternative offers fixture")
	check(run(ordinary, "trade", {"visit_id": "ordinary", "item_id": "X01_A", "seller": "player", "buyer": "buyer", "currency": "VKC", "amount": 50, "inventory": "buyer_grid", "x": 0, "y": 0, "rotated": false}).ok, "one chosen ordinary offer")
	reject(ordinary, "trade", {"visit_id": "ordinary", "item_id": "X01_B", "seller": "player", "buyer": "buyer", "currency": "VKC", "amount": 10, "inventory": "buyer_grid", "x": 1, "y": 0, "rotated": false}, "second independent object in same visit refused")
	var expired_state: Dictionary = multi_state.duplicate(true)
	expired_state.visits.delivery.expires = 0
	expired_state.game_minutes = 1
	var expired: RefCounted = session()
	check(expired.restore(expired_state), "expired context fixture")
	reject(expired, "deliver", {"visit_id": "delivery", "placements": places}, "expired delivery cannot settle")
	var wrong_purpose: Dictionary = multi_state.duplicate(true)
	wrong_purpose.visits.ordinary.scope.purpose = "purchase"
	check(not ordinary.restore(wrong_purpose), "purpose incompatible with stored buyer/seller rejected")
	case_id = "C05"
	var altered_evidence: Dictionary = knowledge.snapshot()
	var evidence_id: String = altered_evidence.knowledge.keys()[0]
	altered_evidence.knowledge[evidence_id].item_id = "X01_B"
	check(not knowledge.restore(altered_evidence), "evidence tied to originating request identity")
	# Archive exactly an existing legitimate request in a detached schema3 fixture.
	# Avoid a redundant long campaign to hit the receipt threshold.
	var archived_state: Dictionary = knowledge.snapshot()
	var old: Dictionary = archived_state.receipts[evidence_id]
	archived_state.receipt_archive[evidence_id] = [old.fingerprint.sha256_text(), old.result.revision, "observe"]
	archived_state.receipts.erase(evidence_id)
	check(knowledge.restore(archived_state), "valid archived observation preserves save compatibility")
	var moved_fact: Dictionary = archived_state.duplicate(true)
	moved_fact.knowledge[evidence_id].item_id = "X01_B"
	check(not knowledge.restore(moved_fact) and knowledge.snapshot() == archived_state, "archived observation cannot move between item IDs")
	var wrong_field: Dictionary = archived_state.duplicate(true)
	wrong_field.knowledge[evidence_id].observation_key = "restored"
	wrong_field.knowledge[evidence_id].dependent_field_versions = {"restored": 0}
	wrong_field.knowledge[evidence_id].observed_value = false
	check(not knowledge.restore(wrong_field) and knowledge.snapshot() == archived_state, "archived observation cannot change key")
	var hidden: Dictionary = archived_state.duplicate(true)
	hidden.knowledge[evidence_id].visibility = "private"
	check(not knowledge.restore(hidden) and knowledge.snapshot() == archived_state, "archived observation cannot change visibility")
	case_id = "C06"
	var deleted_history: Dictionary = final_state.duplicate(true)
	deleted_history.object_events.remove_at(0)
	check(not s.restore(deleted_history), "receipt cannot outlive omitted composition event")
	case_id = "C09"
	var dir: String = "user://zt_rebuild/gate0c_" + str(Time.get_ticks_usec())
	var repo := Saves.new(dir)
	check(repo.save_session(s, "core").ok, "v3 tombstones/ledger save")
	check(run(s, "advance_time", {"minutes": 1}).ok and repo.save_session(s, "core").ok, "second generation")
	var reload: RefCounted = session()
	check(repo.load_session(reload, "core").ok and reload.snapshot() == s.snapshot(), "complete v3 roundtrip")
	var exact: Dictionary = reload.snapshot()
	check(reload.execute(discard) == result and reload.snapshot() == exact, "old discard receipt survives reload")
	var changed: Dictionary = discard.duplicate(true)
	changed.payload.confirmed_ids = ["X01"]
	check(reload.execute(changed).error == "action_id_reused" and reload.snapshot() == exact, "changed payload refused after load")
	var file := FileAccess.open(dir.path_join("core.b.json"), FileAccess.WRITE)
	file.store_string("broken")
	file.close()
	check(repo.load_session(reload, "core").ok and reload.snapshot() == final_state, "A/B corruption fallback preserves terminal IDs")
	for index: int in range(34):
		check(run(reload, "advance_time", {"minutes": 1}, "archive_tick_%d" % index).ok, "fixed archive boundary tick")
	check(reload.snapshot().receipt_archive.has("discard"), "new disposition receipt compacted")
	check(repo.save_session(reload, "archive").ok and repo.load_session(reload, "archive").ok and reload.execute(discard) == result, "archived disposition survives reload and retry")
	check(repo.save_session(multi, "contract").ok and repo.load_session(reload, "contract").ok and reload.snapshot() == multi.snapshot(), "multi-currency multi-ID ledger/context roundtrip")
	check(repo.save_session(restoration, "knowledge").ok and repo.load_session(reload, "knowledge").ok and reload.knowledge_view("X01") == restoration.knowledge_view("X01"), "current/stale knowledge and restoration roundtrip")
	var runtime := preload("res://src/application/foundation_runtime.gd").new()
	check(runtime.initialize(Fixture.make(), "app", dir, "res://data/catalog/gate0_c.json"), "application uses versioned composite catalog")
	var submitted: Dictionary = runtime.submit(Fixture.purchase())
	check(submitted.ok and submitted.persisted and runtime.snapshot().items.X01_A.owner_id == "player", "actual application composite purchase and persistence")
	check(runtime.item_view("X01").quality == "unknown" and not runtime.item_view("X01").has("hidden_economy"), "application presentation boundary hides truth")
	runtime.shutdown()
	var folder := DirAccess.open(dir)
	for name: String in folder.get_files():
		folder.remove(name)
	DirAccess.remove_absolute(dir)
	case_id = "C04"
	var spoof: RefCounted = session()
	reject(spoof, "move", {"actor": "seller", "item_id": "X01", "inventory": "seller_grid", "x": 5, "y": 0, "rotated": false}, "client cannot impersonate NPC custodian")
	check(not spoof.discard_preview("X01", "seller").ok, "preview cannot impersonate other owner")
	case_id = "C08"
	var unrelated: Dictionary = Fixture.make()
	unrelated.visits.purchase.buyer = "buyer"
	unrelated.visits.purchase.scope.kind = "special_contract"
	unrelated.visits.purchase.scope.purpose = "delivery"
	unrelated.visits.purchase.scope.required_ids = ["X01"]
	check(not spoof.restore(unrelated), "player cannot authorize unrelated NPC-to-NPC contract")
	case_id = "C10"
	var sizes: Dictionary = {"active_with_children": Rules.canonical(recovered.items).to_utf8_buffer().size(), "attached_child": Rules.canonical(recovered.items.X01_C).to_utf8_buffer().size(), "ledger": Rules.canonical(final_state.ledger).to_utf8_buffer().size(), "tombstones": Rules.canonical(final_state.tombstones).to_utf8_buffer().size(), "full_envelope": Format.encode(final_state, "measure").to_utf8_buffer().size()}
	check(sizes.full_envelope < Format.MAX_BYTES and Format.MAX_BYTES == 1048576, "measured fixture below unchanged ceiling")
	check(final_state.items.size() + final_state.tombstones.size() == 4 and final_state.ledger.size() == 1, "active/terminal/history references preserve original IDs")
	print("C10_BYTES ", JSON.stringify(sizes))
	for key: String in checks:
		print("%s: %d checks, %d failures" % [key, checks[key], failures.get(key, 0)])
	quit(0 if failures.is_empty() else 1)

func _replacement_calendar()->void:
	var seed:Dictionary=Fixture.make()
	seed.items["SPARE_A"]=Objects.fresh_item("sample_insert_a","player","player_grid",6,2,"fixture_spare_a")
	seed.items.SPARE_A.basis={"VKC":15,"USD":0}
	var profile:Dictionary={"id":"demo_7","content_version":"abstract_replacement_1","day_ids":["d1","d2","d3","d4","d5","d6","d7"]}
	var s:=Session.new()
	if not s.initialize(Fixture.definitions(),seed,false,false,profile):
		check(false,"isolated replacement calendar initialize "+s.initialization_error())
		return
	var purchase:Dictionary=Fixture.purchase()
	check(s.execute(purchase).ok,"replacement calendar root purchased")
	check(run(s,"calendar_close",{}).ok,"replacement calendar evening")
	var before:Dictionary=s.snapshot()
	var options:Dictionary=s.composition_options("X01","player_grid")
	if not options.enabled or options.slots[0].replace.is_empty():
		check(false,"eligible replacement projected")
		return
	var p:Dictionary=options.slots[0].replace[0]
	check(p.old_child_id=="X01_A" and p.child_id=="SPARE_A" and p.x==6 and p.y==2 and s.snapshot()==before,"replacement preview bound to identities and final grid")
	var bad:Dictionary=p.duplicate(true)
	bad.x=0
	bad.y=0
	reject(s,"replace_component",bad,"overlap rejected atomically")
	bad=p.duplicate(true)
	bad.child_id="X01_B"
	reject(s,"replace_component",bad,"incompatible child rejected atomically")
	var cmd:Dictionary=command(s,"replace_component",p,"replace_probe")
	if not s.execute(cmd).ok:
		check(false,"replacement authority commit")
		return
	var after:Dictionary=s.snapshot()
	check(after.items.X01_A.parent_id=="" and after.items.X01_A.inventory=="player_grid" and after.items.X01_A.x==6 and after.items.SPARE_A.parent_id=="X01" and after.items.SPARE_A.inventory=="","exchange swaps relationships atomically")
	check(after.revision==before.revision+1 and after.object_events.size()==before.object_events.size()+1 and after.items.X01.field_versions.composition==before.items.X01.field_versions.composition+1,"single revision event and composition invalidation")
	check(after.wallets==before.wallets and after.game_minutes==before.game_minutes and Objects.basis(after,after.items.keys()).basis==Objects.basis(before,before.items.keys()).basis,"wallet time and basis conserved")
	check(s.execute(cmd).ok and s.snapshot()==after,"duplicate exchange receipt cannot repeat")
	for id:String in ["X01","X01_A","SPARE_A"]:
		var history:Dictionary=s.calendar_item_history(id)
		check(not history.work_records.is_empty() and history.work_records[0].kind=="replace_component","receipt-bound replacement history "+id)
	var reopened:=Session.new()
	check(reopened.initialize(Fixture.definitions(),seed,false,false,profile) and reopened.restore(after) and reopened.snapshot()==after,"calendar replacement replay exact")

# Isolated representative fictional civilian receiver: no new production
# scenario, currency, economic tuning, or saved schema field.
func _civilian_cycle()->void:
	var defs:Dictionary=Fixture.definitions()
	for id:String in ["sample_device","sample_insert_a","sample_insert_b","sample_insert_c"]:
		defs[id].category="civilian_electronics"
	var seed:Dictionary=Fixture.make()
	seed.wallets.player.USD=3
	seed.items["SPARE_C"]=Objects.fresh_item("sample_insert_c","seller","seller_grid",6,2,"civilian_spare_c")
	seed.visits["buy_spare"]=Fixture.visit("buy_spare","seller","player",{"SPARE_C":{"VKC":15,"USD":0}})
	seed.visits["resell_device"]=Fixture.visit("resell_device","player","buyer",{"X01":{"VKC":150,"USD":0}})
	seed.visits.resell_device.opens=1440
	var profile:Dictionary={"id":"demo_7","content_version":"civilian_assessment_fixture_1","day_ids":["d1","d2","d3","d4","d5","d6","d7"]}
	var s:=Session.new()
	if not s.initialize(defs,seed,false,false,profile):
		check(false,"civilian test profile initialize "+s.initialization_error())
		return
	check(s.execute(Fixture.purchase()).ok,"civilian damaged unit purchase")
	check(run(s,"trade",{"visit_id":"buy_spare","item_id":"SPARE_C","seller":"seller","buyer":"player","currency":"VKC","amount":15,"inventory":"player_grid","x":6,"y":2,"rotated":false}).ok,"civilian spare purchased")
	var unseen:Dictionary=s.inventory_appraisal("X01")
	check(unseen.quality=="unknown" and unseen.tests[0].fact.is_empty() and unseen.basis.VKC==70,"unknown remains hidden; actual acquired family basis")
	check(run(s,"observe",{"actor":"player","item_id":"X01","key":"functional"}).ok and run(s,"observe",{"actor":"player","item_id":"X01_C","key":"functional"}).ok,"paid-in-time whole and component inspection")
	var observed:Dictionary=s.inventory_appraisal("X01")
	check(observed.tests[0].fact.current and not observed.tests[0].fact.observed_value and s.snapshot().game_minutes==2,"known function failure and exact observation time")
	check(run(s,"calendar_close",{}).ok,"civilian close")
	var evening:Dictionary=s.snapshot()
	reject(s,"restore_item",{"actor":"player","item_id":"X01"},"faulty component prevents free functional restoration")
	var options:Dictionary=s.composition_options("X01","player_grid")
	if not options.enabled or options.slots[2].replace.is_empty():
		check(false,"civilian compatible exchange available")
		return
	check(run(s,"replace_component",options.slots[2].replace[0]).ok,"civilian exchange")
	var exchanged:Dictionary=s.inventory_appraisal("X01")
	check(not exchanged.tests[0].fact.current and exchanged.basis.VKC==75,"old whole test stale; family cost excludes old part")
	check(s.inventory_appraisal("X01_C").tests[0].fact.current and not s.inventory_appraisal("X01_C").tests[0].fact.observed_value,"removed part known defect persists")
	check(s.inventory_appraisal("SPARE_C").tests[0].fact.is_empty(),"new part condition not leaked")
	check(run(s,"restore_item",{"actor":"player","item_id":"X01"}).ok,"actual paid restoration after replacement")
	check(s.snapshot().wallets.player.VKC==evening.wallets.player.VKC-5 and s.snapshot().wallets.player.USD==1 and s.inventory_appraisal("X01").basis.VKC==80,"restoration cost added only to family")
	check(run(s,"calendar_morning",{}).ok,"civilian next morning")
	for key:String in ["functional","complete","restored"]:
		check(run(s,"observe",{"actor":"player","item_id":"X01","key":key}).ok,"fresh whole assessment "+key)
	var restored:Dictionary=s.inventory_appraisal("X01")
	check(restored.quality=="refurbished" and restored.tests[0].fact.observed_value and restored.tests[0].fact.current,"current evidence confirms restored unit")
	check(run(s,"trade",{"visit_id":"resell_device","item_id":"X01","seller":"player","buyer":"buyer","currency":"VKC","amount":150,"inventory":"buyer_grid","x":0,"y":0,"rotated":false}).ok,"authored isolated resale")
	var final:Dictionary=s.snapshot()
	check(final.wallets.player.VKC==225 and final.wallets.player.USD==1 and final.items.X01_C.owner_id=="player" and final.items.SPARE_C.owner_id=="buyer","cash, residual stock and ownership exact")
	check(final.ledger.back().basis.VKC==80 and final.ledger.back().basis.USD==2 and final.ledger.back().amounts.VKC==150,"resale records actual family basis and settlement")
	check(s.inventory_appraisal("X01").is_empty() and not s.calendar_item_history("X01").records.is_empty(),"sold condition not accessible; history remains")
	var reopened:=Session.new()
	check(reopened.initialize(defs,seed,false,false,profile) and reopened.restore(final) and reopened.snapshot()==final,"full civilian cycle replay exact")
