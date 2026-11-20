extends RefCounted
## Fixed first-visit fixture; no mutable state outside GameSession.
const Rules = preload("res://src/domain/value_rules.gd")
const Appraisal = preload("res://src/domain/gate1_appraisal.gd")
const Receipt = preload("res://src/domain/receipt_primitives.gd")
const Deck = preload("res://src/domain/negotiation_deck.gd")
const ACTIONS: Array = ["make_offer", "confirm_purchase", "decline_visit"]
const Policy = preload("res://src/domain/negotiation_policy.gd")
const MAX_OFFERS: int = 3
const ASK: int = 125

static func empty() -> Dictionary:
	return {"offers": [], "terminal": null}

static func accepted(amount: int, evidence_id: Variant) -> bool:
	return Policy.accepts(amount, 110, 10, evidence_id == "R001.wear")

static func offer(state: Dictionary, p: Dictionary, id: String) -> String:
	if not Appraisal.active(state):
		return "offer_permission"
	var card: bool = Rules.keys(p, ["amount","argument"])
	var sequence: bool = Rules.keys(p,["amount","presented_ids"])
	if (not card and not sequence and not Rules.keys(p, ["amount", "evidence_id"])) or not Rules.integer(p.amount, 1):
		return "offer_shape"
	var evidence: Dictionary = state.campaign.get("appraisal", Appraisal.empty()).evidence
	var evidence_id: Variant = p.get("evidence_id")
	if card:
		if not Appraisal.argument_valid(state,p.argument,int(state.revision)+1,true):
			return "offer_argument"
		evidence_id = Appraisal.argument_evidence(p.argument)
	if sequence:
		var result: Dictionary = Deck.basis(state,p.presented_ids,int(state.revision)+1)
		if result.is_empty():
			return "offer_deck"
		evidence_id = result.evidence_id
	if evidence_id != null and (not Rules.identifier(evidence_id) or not evidence.has(evidence_id)):
		return "offer_evidence"
	var n: Dictionary = state.campaign.get("negotiation", empty())
	for row: Dictionary in n.offers:
		if row.amount == p.amount and row.evidence_id == evidence_id:
			return "offer_already_recorded"
	if n.offers.size() >= MAX_OFFERS:
		return "offer_limit"
	var row: Dictionary = {"action_id": id, "amount": int(p.amount), "evidence_id": evidence_id, "accepted": accepted(int(p.amount), evidence_id)}
	if card:
		row["argument"] = p.argument.duplicate(true)
	if sequence:
		row["presented_ids"] = p.presented_ids.duplicate()
	n.offers.append(row)
	state.campaign["negotiation"] = n
	return ""

## The authority alone calls _transfer after this preflight. No client-selected price.
static func prepare_purchase(state: Dictionary, p: Dictionary) -> String:
	if not Appraisal.active(state):
		return "purchase_permission"
	if not Rules.keys(p, ["offer_id", "inventory", "x", "y", "rotated"]) or not Rules.identifier(p.offer_id) or p.inventory != "player_stock" or not Rules.integer(p.x, 0, 9) or not Rules.integer(p.y, 0, 5) or not p.rotated is bool:
		return "purchase_shape"
	var n: Dictionary = state.campaign.get("negotiation", empty())
	if n.offers.is_empty():
		return "offer_required"
	var row: Dictionary = n.offers.back()
	if row.action_id != p.offer_id or not row.accepted:
		return "offer_not_accepted"
	state.visits.visit_g01.prices.R001["VKC"] = row.amount
	return ""

static func finish(state: Dictionary, kind: String, id: String) -> void:
	var n: Dictionary = state.campaign.get("negotiation", empty())
	n["terminal"] = {"kind": kind, "action_id": id}
	state.campaign["negotiation"] = n
	state.campaign.queue["active_visit_id"] = null

static func decline(state: Dictionary, p: Dictionary, id: String) -> String:
	if not p.is_empty() or not Appraisal.active(state):
		return "decline_permission"
	finish(state, "declined", id)
	return ""

static func valid(state: Dictionary, admitted: bool, admission_revision: int, commands: Dictionary) -> bool:
	var n: Variant = state.campaign.get("negotiation", empty())
	if not Rules.keys(n, ["offers", "terminal"]) or not n.offers is Array or n.offers.size() > MAX_OFFERS:
		return false
	if not admitted and n != empty():
		return false
	var offers: Array = commands.get("make_offer", [])
	var purchases: Array = commands.get("confirm_purchase", [])
	var declines: Array = commands.get("decline_visit", [])
	if offers.size() != n.offers.size() or purchases.size() + declines.size() > 1:
		return false
	var prior: int = admission_revision
	var used: Array = []
	var evidence: Dictionary = state.campaign.get("appraisal", Appraisal.empty()).evidence
	for row: Variant in n.offers:
		var card: bool = Rules.keys(row, ["action_id","amount","evidence_id","accepted","argument"])
		var sequence: bool = Rules.keys(row,["action_id","amount","evidence_id","accepted","presented_ids"])
		if (not card and not sequence and not Rules.keys(row, ["action_id", "amount", "evidence_id", "accepted"])) or not Rules.integer(row.amount, 1) or not row.accepted is bool or row.action_id not in offers:
			return false
		var revision: int = Receipt.receipt_revision(state, row.action_id)
		var payload: Dictionary = {"amount":row.amount,"evidence_id":row.evidence_id}
		if card:
			if not Appraisal.argument_valid(state,row.argument,revision,false) or row.evidence_id != Appraisal.argument_evidence(row.argument):
				return false
			# The referenced source was the latest hypothesis when the offer was made.
			var source_rev: int = Receipt.receipt_revision(state,row.argument.source_action)
			for h: String in commands.get("record_hypothesis",[]):
				var h_rev: int = Receipt.receipt_revision(state,h)
				if h_rev > source_rev and h_rev < revision:
					return false
			payload = {"amount":row.amount,"argument":row.argument}
		if sequence:
			var result: Dictionary = Deck.basis(state,row.presented_ids,revision)
			if result.is_empty() or result.evidence_id != row.evidence_id:
				return false
			payload = {"amount":row.amount,"presented_ids":row.presented_ids}
		if revision <= prior or not Receipt.matches_receipt(state, row.action_id, "make_offer", payload, revision):
			return false
		if row.evidence_id != null:
			if not Rules.identifier(row.evidence_id) or not evidence.has(row.evidence_id) or Receipt.receipt_revision(state, evidence[row.evidence_id].action_id) >= revision:
				return false
		if row.accepted != accepted(int(row.amount), row.evidence_id) or [row.amount, row.evidence_id] in used:
			return false
		used.append([row.amount, row.evidence_id])
		prior = revision
	if n.terminal == null:
		return purchases.is_empty() and declines.is_empty()
	if not Rules.keys(n.terminal, ["kind", "action_id"]) or n.terminal.kind not in ["purchased", "declined"]:
		return false
	var id: Variant = n.terminal.action_id
	var final_revision: int = Receipt.receipt_revision(state, id)
	if final_revision <= prior:
		return false
	for kind: String in ["inspect_radio", "record_hypothesis", "deck_action"]:
		for command_id: String in commands.get(kind, []):
			if Receipt.receipt_revision(state, command_id) >= final_revision:
				return false
	if n.terminal.kind == "declined":
		return id in declines and purchases.is_empty() and Receipt.matches_receipt(state, id, "decline_visit", {}, final_revision)
	if id not in purchases or not declines.is_empty() or n.offers.is_empty() or not n.offers.back().accepted or state.ledger.size() != 1:
		return false
	var radio: Dictionary = state.items.R001
	var row: Dictionary = n.offers.back()
	var entry: Dictionary = state.ledger[0]
	return entry.event_id == id and entry.revision == final_revision and entry.game_minutes == state.game_minutes and entry.root_ids == ["R001"] and entry.item_ids == ["R001"] and entry.amounts == {"VKC": row.amount, "USD": 0} and Receipt.matches_receipt(state, id, "confirm_purchase", {"offer_id": row.action_id, "inventory": radio.inventory, "x": radio.x, "y": radio.y, "rotated": radio.rotated}, final_revision)

static func view(state: Dictionary) -> Dictionary:
	var n: Dictionary = state.campaign.get("negotiation", empty())
	var rows: Array = []
	for row: Dictionary in n.offers:
		rows.append({"offer_id": row.action_id, "amount": row.amount, "evidence_id": row.evidence_id, "accepted": row.accepted, "response_key": "day1.g01.accept" if row.accepted else "day1.g01.reject", "evidence_response_key": "day1.g01.wear_response" if row.evidence_id == "R001.wear" else null})
		if row.has("argument"):
			rows.back()["argument"] = row.argument.duplicate(true)
		if row.has("presented_ids"):
			rows.back()["presented_ids"] = row.presented_ids.duplicate()
	var active: bool = Appraisal.active(state)
	return {"offers": rows, "remaining_offers": MAX_OFFERS - rows.size(), "can_offer": active and rows.size() < MAX_OFFERS, "can_confirm": active and not rows.is_empty() and rows.back().accepted, "can_decline": active, "outcome": null if n.terminal == null else n.terminal.kind}
