extends RefCounted
## Pure validation of proposed transaction scope. Not a customer or contract authority.
## All context must come from the validated session, never an untrusted UI payload.
const Rules = preload("res://src/domain/value_rules.gd")
const PURPOSES: Array = ["purchase", "sale", "service", "order", "delivery"]
const MAX_CONTRACT_ITEMS: int = 128

static func validate_scope(context: Variant, purpose: Variant, item_ids: Variant) -> Dictionary:
	if not Rules.keys(context, ["visit_id", "kind", "purpose", "completed", "required_ids"]):
		return {"ok": false, "error": "visit_shape"}
	if not Rules.identifier(context.visit_id) or not context.kind is String or not context.purpose is String or not context.completed is bool:
		return {"ok": false, "error": "visit_context"}
	if context.kind not in ["ordinary", "special_contract"] or context.purpose not in PURPOSES or not purpose is String or purpose != context.purpose:
		return {"ok": false, "error": "visit_purpose"}
	if context.completed:
		return {"ok": false, "error": "visit_completed"}
	if not item_ids is Array or item_ids.is_empty() or item_ids.size() > MAX_CONTRACT_ITEMS:
		return {"ok": false, "error": "visit_items"}
	if not context.required_ids is Array:
		return {"ok": false, "error": "visit_required_ids"}
	var offered: Dictionary = {}
	for item_id: Variant in item_ids:
		if not Rules.identifier(item_id) or offered.has(item_id):
			return {"ok": false, "error": "visit_item_id"}
		offered[item_id] = true
	if context.kind == "ordinary":
		if not context.required_ids.is_empty() or item_ids.size() != 1:
			return {"ok": false, "error": "ordinary_single_item"}
		return {"ok": true}
	# Fixed-ID fulfilled contract fixture only. Dynamic matching remains a later caller concern.
	if purpose != "delivery" or context.required_ids.is_empty() or context.required_ids.size() != item_ids.size():
		return {"ok": false, "error": "contract_scope"}
	var required: Dictionary = {}
	for item_id: Variant in context.required_ids:
		if not Rules.identifier(item_id) or required.has(item_id) or not offered.has(item_id):
			return {"ok": false, "error": "contract_items"}
		required[item_id] = true
	return {"ok": true}

## Timing only; callers separately enforce completion, purpose and current visit.
## Inclusive end permits the final transaction at closing.
static func in_window(visit: Variant, minute: int, phase: String) -> bool:
	return visit is Dictionary and phase == "shop" and Rules.integer(visit.get("opens"), 0, 60480) and Rules.integer(visit.get("expires"), int(visit.opens), 60480) and minute >= int(visit.opens) and minute <= int(visit.expires)

static func purchase_open(state: Dictionary, visit_id: String, root_id: String, seller: String, require_consent: bool) -> bool:
	var v: Dictionary = state.get("visits", {}).get(visit_id, {})
	if not in_window(v, int(state.game_minutes), state.phase):
		return false
	return v.scope.visit_id == visit_id and v.scope.kind == "ordinary" and v.scope.purpose == "purchase" and not v.scope.completed and v.seller == seller and seller != "player" and v.buyer == "player" and v.prices.has(root_id) and (not require_consent or v.allow_inspection)
