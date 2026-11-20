extends RefCounted
## Pure scenario permission/route decision. No mutation, no command execution or save.
## Existing slice policies remain isolated until campaign data contracts are implemented.
const Opening = preload("res://src/domain/gate1_opening.gd")
const DayOne = preload("res://src/domain/day_one.gd")
const ComponentMarket = preload("res://src/domain/component_market.gd")
const CustomerInspection = preload("res://src/domain/customer_inspection.gd")

static func choose(state: Dictionary, kind: String, payload: Dictionary, campaign_mode: bool, day_one_mode: bool, component_market_mode: bool) -> Dictionary:
	var continuation: bool = day_one_mode and (state.day_one.base != null or kind == "begin_day_one")
	if campaign_mode and not continuation and kind not in Opening.ACTIONS:
		return {"ok": false, "error": "opening_command_unavailable"}
	if not campaign_mode and (kind in Opening.ACTIONS or kind in DayOne.ACTIONS):
		return {"ok": false, "error": "campaign_required"}
	if component_market_mode:
		if not ComponentMarket.allowed(state, kind):
			return {"ok": false, "error": "component_market_permission"}
	elif kind == ComponentMarket.ACTION:
		return {"ok": false, "error": "component_market_required"}
	var gate: String = CustomerInspection.command_gate(state, kind, payload)
	if not gate.is_empty():
		return {"ok": false, "error": gate}
	var route: String = "common"
	if continuation:
		route = "day_one"
	elif component_market_mode and kind in [ComponentMarket.ACTION, "trade"]:
		route = "component_market"
	return {"ok": true, "route": route}
