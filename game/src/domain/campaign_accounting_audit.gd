extends RefCounted
## Independent first-slice accounting cross-check. No replay and no UI exposure.
## Does not establish campaign world/permission validity by itself.
const Rules = preload("res://src/domain/value_rules.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const R = preload("res://src/domain/receipt_primitives.gd")
const Day = preload("res://src/domain/day_one.gd")
const Composite = preload("res://src/domain/campaign_composite_pilot.gd")
const Customer = preload("res://src/domain/customer_inspection.gd")

static func _has_kind(state: Dictionary, kind: String) -> bool:
	for table: Dictionary in [state.receipts, state.receipt_archive]:
		for id: String in table:
			if R.receipt_type(state, id) == kind:
				return true
	return false

static func _post(book: Dictionary, owner: String, values: Dictionary, sign: int) -> bool:
	if not book.has(owner) or not Objects.money(values, false):
		return false
	for currency: String in ["VKC", "USD"]:
		book[owner][currency] += sign * int(values[currency])
	return true

## Input shape must already be checked by the state validator. Seed supplied by
## fresh initialized content, not by an arbitrary balance from a save file.
static func reconcile(state: Dictionary, seed: Dictionary) -> bool:
	if not state.get("campaign") is Dictionary or state.campaign.id != "gate1_1" or not state.get("day_one") is Dictionary or seed.revision != 0:
		return false
	var book: Dictionary = seed.wallets.duplicate(true)
	if _has_kind(state, "begin_day_one"):
		book[Day.WHOLESALER] = {"VKC": Day.WHOLESALE_PRICE, "USD": 0}
	if _has_kind(state, Composite.OFFER):
		book[Customer.SELLER] = {"VKC": 0, "USD": 0}
	if state.visits.has(Day.RECOVERY):
		if not _has_kind(state, "day_one_next_morning"):
			return false
		book[Day.RECOVERY_BUYER] = {"VKC": 130, "USD": 0}
	var seen: Dictionary = {}
	for entry: Dictionary in state.ledger:
		if seen.has(entry.event_id) or R.receipt_revision(state, entry.event_id) != entry.revision or R.receipt_type(state, entry.event_id) not in ["trade", "deliver", "confirm_purchase"]:
			return false
		seen[entry.event_id] = true
		if not _post(book, entry.from, entry.amounts, -1) or not _post(book, entry.to, entry.amounts, 1):
			return false
	var expenses: Dictionary = {}
	for event: Dictionary in state.object_events:
		if event.type == "restore_item":
			if seen.has(event.event_id) or R.receipt_type(state, event.event_id) != "restore_item" or R.receipt_revision(state, event.event_id) != event.revision or not _post(book, "player", event.expenses, -1):
				return false
			seen[event.event_id] = true
			expenses[event.event_id] = event.expenses
	var settlements: Dictionary = {}
	for entry: Dictionary in state.day_one.settlements:
		if settlements.has(entry.id) or not Rules.integer(entry.amount):
			return false
		settlements[entry.id] = true
		var amount: Dictionary = {"VKC": entry.amount, "USD": 0}
		match entry.kind:
			"service_cost":
				# Same debit already posted by restore_item: never double-count.
				if expenses.get(entry.id) != amount or entry.amount != Day.SERVICE_COST:
					return false
			"overhead", "overhead_debt":
				if seen.has(entry.id) or R.receipt_type(state, entry.id) != ("day_one_close" if entry.kind == "overhead" else "day_one_pay_overhead") or entry.amount > Day.OVERHEAD or not _post(book, "player", amount, -1):
					return false
				seen[entry.id] = true
			"service_fee":
				if seen.has(entry.id) or R.receipt_type(state, entry.id) != "day_one_deliver_service" or entry.amount != Day.SERVICE_FEE or not _post(book, "G02", amount, -1) or not _post(book, "player", amount, 1):
					return false
				seen[entry.id] = true
			_: return false
	return book == state.wallets
