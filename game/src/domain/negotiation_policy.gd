extends RefCounted
## Private pure offer evaluation; no threshold or discount exposed to UI.
const Rules = preload("res://src/domain/value_rules.gd")

static func accepts(amount: Variant, floor_amount: Variant, supported_discount: Variant, qualified: bool) -> bool:
	if not Rules.integer(amount, 1) or not Rules.integer(floor_amount, 1) or not Rules.integer(supported_discount, 0, int(floor_amount) - 1):
		return false
	return int(amount) >= int(floor_amount) - (int(supported_discount) if qualified else 0)
