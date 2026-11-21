extends RefCounted
## Read-only causal projection. No secondary source of truth, RNG, persisted
## NPC memories, inferred identity, invisible owner or unearned world effects.
## Existing GameSession validates the journal; this layer also checks receipts
## so stale/forged inputs cannot become apparent facts in UI or visit gating.
const Rules = preload("res://src/domain/value_rules.gd")
const Receipt = preload("res://src/domain/receipt_primitives.gd")
const Clock = preload("res://src/domain/business_clock.gd")
const PUBLIC_EVENT_LIMIT: int = 12

static func _journal_receipt(s: Dictionary, event_id: String, kind: String, revision: int) -> bool:
	if not Rules.identifier(event_id) or revision < 1:
		return false
	var commands: Variant = s.get("calendar", {}).get("commands", [])
	if not commands is Array or revision > commands.size():
		return false
	var command: Variant = commands[revision - 1]
	if not command is Dictionary or command.get("action_id") != event_id or command.get("type") != kind or not command.get("payload") is Dictionary:
		return false
	return Receipt.matches_receipt(s, event_id, kind, command.payload, revision)

static func _traded(s: Dictionary, row: Dictionary) -> bool:
	var id: Variant = row.get("event_id")
	var visit: Variant = row.get("visit_id")
	var rev: Variant = row.get("revision")
	if not id is String or not visit is String or not Rules.identifier(visit) or not Rules.integer(rev, 1):
		return false
	if not row.get("from") is String or not row.get("to") is String or "player" not in [row.get("from"), row.get("to")]:
		return false
	if not _journal_receipt(s, id, "trade", int(rev)):
		return false
	var command: Dictionary = s.calendar.commands[int(rev) - 1]
	return command.payload.get("visit_id") == visit

## A purchase/sale must actually appear in the paid player ledger, with a
## matching authoritative journal receipt. A pending/declined offer is not one.
static func trade_for_visit(s: Dictionary, visit_id: String) -> Dictionary:
	if not Rules.identifier(visit_id):
		return {}
	for entry: Dictionary in s.get("ledger", []):
		if entry.get("visit_id") == visit_id and _traded(s, entry):
			return {"event_id":entry.event_id, "visit_id":visit_id, "revision":int(entry.revision), "day":Clock.day_index(int(entry.game_minutes))}
	return {}

## The player's firsthand relationship with the CURRENT visiting person.
## Never exposes NPC balances, unobserved conversations, external inventory,
## inferred familiarity, a future visitor, or an item identity conclusion.
static func customer_memory(s: Dictionary, actor: String) -> Dictionary:
	if not Rules.identifier(actor) or actor == "player" or not s.get("wallets", {}).has(actor):
		return {}
	var count: int = 0
	var last: Dictionary = {}
	for entry: Dictionary in s.get("ledger", []):
		if actor not in [entry.get("from"), entry.get("to")] or "player" not in [entry.get("from"), entry.get("to")] or not _traded(s, entry):
			continue
		count += 1
		if last.is_empty() or int(entry.revision) > int(last.revision):
			last = entry
	if count == 0:
		return {}
	return {"actor_id":actor, "trades":count, "last_day":Clock.day_index(int(last.game_minutes)),
		"last_direction":"customer_bought" if last.from == actor else "customer_sold",
		"last_receipt":last.event_id}

## All positive reactions must be traced to real paid trades or finished,
## paid service returns. External disruption exists regardless of the player.
static func actual_cause(s: Dictionary, event_id: String) -> Dictionary:
	if not Rules.identifier(event_id):
		return {}
	for entry: Dictionary in s.get("ledger", []):
		if entry.get("event_id") == event_id and _traded(s, entry):
			return {"kind":"trade", "event_id":event_id, "visit_id":entry.visit_id}
	var revision: int = Receipt.receipt_revision(s, event_id)
	if not _journal_receipt(s, event_id, "calendar_deliver_service", revision):
		return {}
	for job: Dictionary in s.get("calendar", {}).get("services", {}).get("jobs", {}).values():
		if job.get("return_action") == event_id and job.get("status") == "delivered" and job.get("paid") == job.get("terms", {}).get("fee"):
			return {"kind":"paid_service", "event_id":event_id}
	return {}

## Public event index is rebuilt from the real persisted event/receipt graph.
## It never persists a second narrative or leaks condition/organization scores.
static func public_events(s: Dictionary) -> Array:
	var result: Array = []
	var events: Dictionary = s.get("calendar", {}).get("reaction", {}).get("events", {})
	var ids: Array = events.keys()
	ids.sort()
	for event_id: String in ids:
		var row: Dictionary = events[event_id]
		var opening: String = str(row.get("opening_action", ""))
		var revision: int = Receipt.receipt_revision(s, opening)
		if not _journal_receipt(s, opening, "calendar_morning", revision):
			continue
		var delivered: bool = row.get("result") == "limited_service"
		var cause: Dictionary = actual_cause(s, str(row.get("cause", ""))) if delivered else {}
		# A broken receipt must never be shown as successful player aid.
		if delivered and cause.is_empty():
			continue
		if not delivered and not str(row.get("cause", "")).is_empty():
			continue
		var refs: Array = [str(row.get("external_event", ""))]
		if delivered:
			refs.append(cause.event_id)
		result.append({"event_id":event_id, "day":int(row.get("day", 0)),
			"external_event":str(row.get("external_event", "")),
			"response":"limited_service" if delivered else "interrupted",
			"player_contribution":delivered, "cause_refs":refs})
		if result.size() >= PUBLIC_EVENT_LIMIT:
			break
	return result
