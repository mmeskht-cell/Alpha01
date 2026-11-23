extends SceneTree
## B3 currency access must follow visible, immutable source terms; no
## invented citywide VKC collapse, dealer wallet leak or minting.
const Source = preload("res://src/content/alpha_b3_fx_seed.gd")
const M2 = preload("res://src/content/alpha_b3_market_m2_seed.gd")
const Session = preload("res://src/domain/game_session.gd")
const Money = preload("res://src/domain/alpha_b3_currency_terms.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", reason)

func fresh(src: Dictionary) -> RefCounted:
	var s := Session.new()
	if not s.initialize(src.defs, src.state, false, false, {}, src.alpha_profile):
		printerr("CURRENCY_TERMS_INIT: ", s.initialization_error())
		return null
	return s

func go(s: RefCounted, kind: String, payload: Dictionary = {}) -> bool:
	var rev: int = int(s.snapshot().revision)
	var command: Dictionary = {"action_id": "currency_terms_" + str(rev + 1),
		"expected_revision": rev, "type": kind, "payload": payload}
	var result: Dictionary = s.execute(command)
	if not bool(result.get("ok", false)):
		printerr("CURRENCY_TERMS_STEP: ", kind, " ", result)
	return bool(result.get("ok", false))

func _finish() -> void:
	print("ALPHA_B3_CURRENCY_TERMS_CHECKS=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

func _initialize() -> void:
	var src: Dictionary = Source.content()
	var m2: Dictionary = M2.content()
	if src.is_empty() or m2.is_empty():
		check(false, "source profiles exist")
		_finish()
		return
	check(Money.view(src.state).is_empty(), "raw seed cannot leak a trade or quotation")
	var b2: RefCounted = fresh(m2)
	if b2 == null:
		check(false, "M2 profile still initializes")
		_finish()
		return
	check(not b2.alpha_view().has("currency_terms"),
		"M2 view has no added fields and its original contract is unchanged")

	var s: RefCounted = fresh(src)
	if s == null:
		check(false, "M3 profile initializes")
		_finish()
		return
	var before: Dictionary = s.snapshot()
	var initial: Dictionary = s.alpha_view().currency_terms
	check(initial.trade.is_empty() and initial.exchange.is_empty(),
		"do not expose future visitor rate before a customer is active")
	check(Money.view(before) == initial and s.snapshot() == before,
		"projection is read-only and replay-safe")
	check(go(s, "alpha_open"), "open day one")

	var found_trade: bool = false
	for n: int in range(10):
		if int(s.alpha_view().remaining) == 0:
			break
		if not go(s, "alpha_next_customer") or not go(s, "alpha_ack_entry"):
			break
		var current: Dictionary = s.snapshot()
		var visit_id: String = str(current.alpha_shop.active)
		var evidence: Dictionary = s.alpha_view().currency_terms
		check(evidence.exchange.is_empty(), "ordinary customers do not show broker quotes")
		if current.visits.has(visit_id) and current.visits[visit_id].prices.size() == 1:
			var price: Dictionary = current.visits[visit_id].prices.values()[0]
			var expected_currency: String = "VKC" if int(price.get("VKC", 0)) > 0 else "USD"
			check(not evidence.trade.is_empty() and evidence.trade.currency == expected_currency
				and not evidence.trade.has("amount")
				and evidence.trade.visit_id == visit_id,
				"current trade exposes the actual unit but never secret base price")
			var variant: Dictionary = current.duplicate(true)
			var item_id: String = str(variant.visits[visit_id].prices.keys()[0])
			var old: Dictionary = variant.visits[visit_id].prices[item_id]
			var shifted: Dictionary = {"VKC": 0, "USD": 2}
			if old.get("VKC", 0) == 0:
				shifted = {"VKC": 2, "USD": 0}
			variant.visits[visit_id].prices[item_id] = shifted
			var derived: Dictionary = Money.view(variant)
			check(derived.trade.currency != evidence.trade.currency
				and not derived.trade.has("amount"),
				"future source-bound USD-only terms can be displayed without a rate formula")
			check(s.snapshot() == current,
				"hypothetical unit projection never edits a live shop state")
			found_trade = true
		if not go(s, "alpha_finish_customer") or not go(s, "alpha_ack_exit"):
			break
		if found_trade:
			break
	check(found_trade, "at least one real current B3 trade tested")
	# Leave other visitors untouched. Date advancement is the same existing
	# early-close path; conditional buyers are not counted as guaranteed visits.
	for day: int in range(1, 8):
		if day > 1:
			check(go(s, "alpha_open"), "open later day")
		if day < 7:
			if not (go(s, "alpha_close") and go(s, "alpha_settle")
					and go(s, "alpha_next_day") and go(s, "alpha_prepare_day")):
				check(false, "advance unchanged clockless shop phases")
				_finish()
				return
	var idle: Dictionary = s.alpha_view().currency_terms
	check(idle.trade.is_empty() and idle.exchange.is_empty(),
		"D7 broker quote is not published until its actual visit")
	check(go(s, "alpha_next_customer") and go(s, "alpha_ack_entry"),
		"admit the funded D7 counterparty")
	var quote: Dictionary = s.alpha_view().currency_terms
	check(quote.trade.is_empty() and not quote.exchange.is_empty()
		and quote.exchange.give_currency == "VKC" and quote.exchange.give_amount == 30
		and quote.exchange.receive_currency == "USD" and quote.exchange.receive_amount == 1
		and quote.exchange.can_exchange and quote.exchange.scope == "current_counter_once",
		"quote belongs to this single broker and cannot imply a general market rate")
	var before_fx: Dictionary = s.snapshot()
	check(Money.view(before_fx) == quote and s.snapshot() == before_fx,
		"reading the dealer quote has no economic side effects")
	check(go(s, "alpha_fx_trade", {"quote_id": "alpha_broker_quote"}),
		"real two-wallet FX settlement still executes")
	var after_fx: Dictionary = s.snapshot()
	var settled: Dictionary = s.alpha_view().currency_terms
	check(settled.exchange.settled and not settled.exchange.can_exchange,
		"settled quotation is never presented as repeatable liquidity")
	check(after_fx.ledger == before_fx.ledger
		and after_fx.wallets.player.VKC == before_fx.wallets.player.VKC - 30
		and after_fx.wallets.player.USD == before_fx.wallets.player.USD + 1,
		"money moves only in real settled FX and never through evidence projection")
	_finish()
