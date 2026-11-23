extends RefCounted
## B3 opt-in currency evidence projection. Currency "acceptance" is only a
## signed current-counter trade or broker quote, NOT a global exchange rate,
## citywide purchasing-power index or future contract promise.
## No persisted keys, wallet writes or invented currency thresholds.
const Fx = preload("res://src/domain/alpha_b3_fx.gd")

static func view(state: Dictionary) -> Dictionary:
	if not state.has("alpha_shop"):
		return {}
	var a: Dictionary = state.alpha_shop
	if str(a.profile.get("content_version", "")) != Fx.VERSION:
		return {}
	var out: Dictionary = {"trade": {}, "exchange": {}}
	if a.phase != "CUSTOMER_ACTIVE" or str(a.active).is_empty():
		return out

	# One active seller/buyer can evidence only their OWN bound terms.
	# Never expose a future visitor's quote or private counterparty wallet.
	if state.visits.has(a.active):
		var visit: Dictionary = state.visits[a.active]
		if not bool(visit.scope.get("completed", false)) and visit.prices.size() == 1:
			var item_id: String = str(visit.prices.keys()[0])
			var price: Dictionary = visit.prices[item_id]
			var vkc: int = int(price.get("VKC", 0))
			var usd: int = int(price.get("USD", 0))
			var currency: String = ""
			var amount: int = 0
			if vkc > 0 and usd == 0:
				currency = "VKC"
				amount = vkc
			elif usd > 0 and vkc == 0:
				currency = "USD"
				amount = usd
			if not currency.is_empty():
				out.trade = {"visit_id": str(a.active), "item_id": item_id,
					"currency": currency, "amount": amount,
					"direction": "pay" if str(visit.buyer) == "player" else "receive",
					"scope": "current_counter"}

	if a.has("fx"):
		var quote: Dictionary = Fx.view(state)
		if bool(quote.get("at_counter", false)):
			out.exchange = {"quote_id": str(quote.quote_id),
				"give_currency": str(quote.give_currency),
				"give_amount": int(quote.give_amount),
				"receive_currency": str(quote.receive_currency),
				"receive_amount": int(quote.receive_amount),
				"can_exchange": bool(quote.can_exchange),
				"settled": bool(quote.settled), "scope": "current_counter_once"}
	return out
