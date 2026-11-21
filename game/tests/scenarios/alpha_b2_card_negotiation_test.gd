extends SceneTree
## True Godot command/replay test of private observations, optional disclosure,
## explicit customer offer acceptance and original wallet/ledger transfer.
const Seed = preload("res://src/content/alpha_b2_cards_seed.gd")
const Session = preload("res://src/domain/game_session.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", name)

func fresh() -> RefCounted:
	var data: Dictionary = Seed.content()
	var s := Session.new()
	if data.is_empty() or not s.initialize(data.defs,data.state,false,false,{},data.alpha_profile):
		printerr("B2 cards initialization: ",s.initialization_error())
		return null
	return s

func cmd(s: RefCounted, action: String, payload: Dictionary = {}) -> Dictionary:
	return {"action_id":"b2_cards_"+strade_payload(s.snapshot().revision + 1),
		"expected_revision":s.snapshot().revision,"type":action,"payload":payload}

func go(s: RefCounted, action: String, payload: Dictionary = {}) -> bool:
	var result: Dictionary = s.execute(cmd(s,action,payload))
	if not result.ok:
		printerr("B2_CARDS_COMMAND_FAILED action=",action," response=",result)
	return bool(result.ok)

func deny(s: RefCounted, action: String, payload: Dictionary = {}) -> bool:
	var before: Dictionary = s.snapshot()
	var result: Dictionary = s.execute(cmd(s,action,payload))
	return not result.ok and before == s.snapshot()

func trade_payload(visit: String, seller: String, buyer: String, amount: int, destination: String, x: int = 0, y: int = 0) -> Dictionary:
	return {"visit_id":visit,"item_id":"R001","seller":seller,"buyer":buyer,
		"currency":"VKC","amount":amount,"inventory":destination,"x":x,"y":y,"rotated":false}

func _initialize() -> void:
	var s: RefCounted = fresh()
	check(s != null, "independent B2 data-only card profile")
	if s == null:
		quit(1)
		return
	var start: Dictionary = s.snapshot()
	check(start.wallets.player.VKC == 180 and not start.alpha_shop.appraisal.has("price_limit"), "original money, no private threshold visible")
	check(deny(s,"alpha_inspect",{"slot":"wear_detail"}) and deny(s,"alpha_price_offer",{"amount":100}), "cannot inspect or negotiate without a real visit")
	check(go(s,"alpha_open") and go(s,"alpha_next_customer") and go(s,"alpha_ack_entry"), "actual first counter visitor")
	check(deny(s,"alpha_trade",trade_payload("visit_g01","G01","player",100,"player_stock")), "cannot settle before accepted offer")
	check(deny(s,"alpha_inspect",{"slot":"forged_tool"}), "unprovided tool cannot manufacture observations")
	check(go(s,"alpha_inspect",{"slot":"wear_detail"}), "original provenance-bound wear observation")
	var view: Dictionary = s.alpha_view().appraisal
	check(view.cards.size() == 1 and view.cards[0].value == "43" and not view.cards[0].selected, "private fact visible only to player")
	check(deny(s,"alpha_inspect",{"slot":"wear_detail"}) and deny(s,"alpha_card_toggle",{"slot":"material_detail","selected":true}), "duplicate observation and forged disclosure rejected")
	check(go(s,"alpha_price_offer",{"amount":95}), "unsubstantiated low offer may be made")
	var rejected: Dictionary = s.snapshot()
	check(rejected.alpha_shop.appraisal.visits.visit_g01.offers[0].response == "declined" and rejected.visits.visit_g01.prices.R001.VKC == 100, "no automatic card price or economy change on refusal")
	check(go(s,"alpha_card_toggle",{"slot":"wear_detail","selected":true}), "deliberate disclosure rather than automatic publication")
	check(s.alpha_view().appraisal.cards[0].selected, "selected drawer distinct from private facts")
	check(go(s,"alpha_price_offer",{"amount":95}), "evidence-bearing second offer accepted")
	var accepted: Dictionary = s.snapshot()
	check(accepted.alpha_shop.appraisal.visits.visit_g01.accepted.amount == 95 and accepted.visits.visit_g01.prices.R001.VKC == 95, "agreed price bound to visit, no payment before confirmation")
	check(accepted.wallets == start.wallets and accepted.ledger.is_empty(), "offer is not transfer")
	check(accepted.alpha_shop.appraisal.visits.visit_g01.offers[0].revealed.is_empty() and accepted.alpha_shop.appraisal.visits.visit_g01.offers[1].revealed.size() == 1, "undisclosed fact not leaked retroactively")
	check(deny(s,"alpha_price_offer",{"amount":94}) and deny(s,"alpha_card_toggle",{"slot":"wear_detail","selected":false}), "no new offer or revision after accepted")
	check(deny(s,"alpha_trade",trade_payload("visit_g01","G01","player",100,"player_stock")), "stale pre-negotiation price rejected")
	var store := Repo.new("user://zt_rebuild/b2_cards_test_"+strade_payload(Time.get_ticks_usec()))
	check(store.save_session(s,"cards").ok, "cold-save accepted price before actual transfer")
	var cold: RefCounted = fresh()
	check(cold != null and store.load_session(cold,"cards").ok and cold.snapshot() == s.snapshot(), "full seed replay of undisclosed and disclosed cards")
	var tamper: Dictionary = s.snapshot()
	tamper.alpha_shop.appraisal.visits.visit_g01.offers[1].amount = 1
	check(not s.restore(tamper), "tampered offer and receipt replay rejected")
	check(go(s,"alpha_trade",trade_payload("visit_g01","G01","player",95,"player_stock")), "actual paid purchase at proposed price")
	check(s.snapshot().wallets.player.VKC == 85 and s.snapshot().items.R001.owner_id == "player" and s.snapshot().items.R001.basis.VKC == 95 and s.snapshot().ledger.size() == 1, "85 VKC cash and 95 actual acquisition basis")
	check(deny(s,"alpha_trade",trade_payload("visit_g01","G01","player",95,"player_stock")) and go(s,"alpha_ack_exit"), "double purchase denied and first customer leaves")
	check(go(s,"alpha_display",{"item_id":"R001","x":0,"y":0,"rotated":false}) and go(s,"alpha_next_customer") and go(s,"alpha_ack_entry"), "physical shelf item presented to buyer")
	check(s.alpha_view().appraisal.cards.is_empty(), "previous seller's disclosed cards not silently placed in new buyer drawer")
	check(go(s,"alpha_inspect",{"slot":"function_detail"}), "same item next visit has separate verified inspection")
	check(s.alpha_view().appraisal.cards[0].value == "serviceable", "sample function reading derived from existing original specimen")
	check(go(s,"alpha_price_offer",{"amount":201}), "unfunded buyer proposal does not create money")
	check(s.snapshot().alpha_shop.appraisal.visits.visit_g02_buy.offers[0].response == "declined" and s.snapshot().wallets.G02.VKC == 200, "buyer money boundary preserved")
	check(go(s,"alpha_price_offer",{"amount":175}), "higher sale price can be proposed even without card")
	check(s.snapshot().alpha_shop.appraisal.visits.visit_g02_buy.offers[1].response == "declined", "different customer rejects unsupported premium")
	check(go(s,"alpha_card_toggle",{"slot":"function_detail","selected":true}) and go(s,"alpha_price_offer",{"amount":175}), "buyer considers explicitly shown functional evidence")
	check(s.snapshot().alpha_shop.appraisal.visits.visit_g02_buy.accepted.amount == 175 and s.snapshot().wallets.player.VKC == 85, "buyer agreement does not mint money")
	check(go(s,"alpha_trade",trade_payload("visit_g02_buy","player","G02",175,"G02_grid",5,4)), "actual 175 VKC shelf sale")
	var sold: Dictionary = s.snapshot()
	check(sold.wallets.player.VKC == 260 and sold.wallets.G02.VKC == start.wallets.G02.VKC - 175 and sold.items.R001.owner_id == "G02", "real finite buyer funds and ownership")
	check(sold.items.R001.basis.VKC == 95 and sold.ledger.size() == 2 and sold.alpha_shop.displayed.is_empty(), "same root ID sold with preserved basis, no duplicate stock")
	check(sold.ledger[0].amounts.VKC == 95 and sold.ledger[1].amounts.VKC == 175, "ledger records exact different negotiated amounts")
	check(store.save_session(s,"cards").ok, "save full cross-visitor negotiation history")
	var reopened: RefCounted = fresh()
	check(reopened != null and store.load_session(reopened,"cards").ok and reopened.snapshot() == sold, "cold restore under archive and ownership changes")
	check(deny(s,"alpha_price_offer",{"amount":1}) and deny(s,"alpha_trade",trade_payload("visit_g02_buy","player","G02",175,"G02_grid",5,4)), "completed visit cannot renegotiate or resell")
	check(go(s,"alpha_ack_exit") and go(s,"alpha_next_customer") and go(s,"alpha_ack_entry"), "next D1 customer uses same counter")
	check(go(s,"alpha_finish_customer") and go(s,"alpha_ack_exit"),"no physical radio stock for wholesale, safe exit")
	check(go(s,"alpha_next_customer") and go(s,"alpha_ack_entry"),"D1 named supplier also same customer route")
	check(go(s,"alpha_finish_customer") and go(s,"alpha_ack_exit"),"contract supplier can leave without altering real item ownership")
	check(go(s,"alpha_close") and go(s,"alpha_settle") and go(s,"alpha_next_day") and go(s,"alpha_prepare_day"),"D2 opens with carried ID history")
	check(go(s,"alpha_open") and go(s,"alpha_next_customer") and go(s,"alpha_ack_entry"),"D2 unserved resale visitor")
	check(go(s,"alpha_finish_customer") and go(s,"alpha_ack_exit"),"no artificial resale stock")
	check(go(s,"alpha_next_customer") and go(s,"alpha_ack_entry"),"watch seller uses same appraisal engine")
	check(s.alpha_view().appraisal.def_id=="fictional_watch_p2","same interface on a distinct definition")
	check(go(s,"alpha_inspect",{"slot":"identity"}),"unconfigured sample still supports safe visible identity")
	check(s.alpha_view().appraisal.cards[0].value=="fictional_watch_p2","no fabricated wear or function evidence for unrelated object")
	check(deny(s,"alpha_inspect",{"slot":"wear_detail"}),"unavailable WAT02 specimen cannot be invented from another object's data")
	check(go(s,"alpha_price_offer",{"amount":80}),"free optional inspection and exact authored buy offer")
	check(s.snapshot().alpha_shop.appraisal.visits.watch_a.offers[0].revealed.is_empty(),"unselected personal identity fact stays private")
	check(go(s,"alpha_trade",{"visit_id":"watch_a","item_id":"WAT02","seller":"G04","buyer":"player",
		"currency":"VKC","amount":80,"inventory":"player_stock","x":0,"y":0,"rotated":false}),"same original transaction ledger on second product family")
	check(s.snapshot().wallets.player.VKC==180 and s.snapshot().items.WAT02.basis.VKC==80,"watch price and cost basis preserved, no free bonus")
	check(s.snapshot().receipt_archive.size() > 0, "B2 card/offer actions correctly survive 32-receipt history compaction")
	var snapshot_before_retry: Dictionary = s.snapshot()
	check(s.execute(snapshot_before_retry.alpha_shop.commands[0]).ok and s.snapshot() == snapshot_before_retry, "archived B2 action retry causes no duplicate profit")
	print("ALPHA_B2_CARD_NEGOTIATION_CHECKS=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
