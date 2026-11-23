extends RefCounted
## WAT02 proposed first-week agreement. Payment/custody mutate only the
## GameSession candidate; normal validation and deterministic replay follow.
const Merchant = preload("res://src/domain/calendar_merchant_contracts.gd")
const Grid = preload("res://src/domain/grid_primitives.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const ACTIONS = ["week_pledge","week_redeem","week_extend"]
const PRINCIPAL = {"VKC":40,"USD":0}
const REPAYMENT = {"VKC":45,"USD":0}

static func placement(s: Dictionary, defs: Dictionary, target: String) -> Dictionary:
	var rows: Array = []
	for id: String in s.items:
		var other: Dictionary = s.items[id]
		if other.inventory != target or id == "WAT02" or not other.parent_id.is_empty():
			continue
		var size: Array = Objects.footprint(s, defs, id)
		rows.append({"item_id":id,"width":size[0],"height":size[1],"x":other.x,"y":other.y,"rotated":other.rotated})
	var shape: Array = Objects.footprint(s, defs, "WAT02")
	var grid: Dictionary = s.inventories[target]
	return Grid.first_fit(grid.width,grid.height,rows,{"item_id":"WAT02","width":shape[0],"height":shape[1],"rotated":false})

static func apply(s: Dictionary, defs: Dictionary, command: Dictionary) -> String:
	var a: Dictionary = s.alpha_shop
	if not a.has("week_pawn") or not command.payload.is_empty():
		return "week_pawn_terms"
	var pawn: Dictionary = a.week_pawn
	var item: Dictionary = s.items.WAT02
	var kind: String = command.type
	if kind == "week_extend":
		if pawn.status != "pledged" or pawn.due != 4 or a.day != 4 or a.phase != "CLOSE_SETTLE":
			return "week_pawn_extension"
		pawn.due = 6
		pawn.events.append({"action":command.action_id,"kind":"extension","day":a.day})
		return ""
	var accepting: bool = kind == "week_pledge"
	var payer: String = "player" if accepting else "G04"
	var receiver: String = "G04" if accepting else "player"
	var target: String = "player_stock" if accepting else "G04_grid"
	var amount: Dictionary = PRINCIPAL if accepting else REPAYMENT
	if accepting:
		if pawn.status != "available" or a.active != "watch_a" or a.phase != "CUSTOMER_ACTIVE" or not Merchant._good_family(s,defs,"WAT02","G04"):
			return "week_pawn_permission"
	elif kind != "week_redeem" or pawn.status != "pledged" or a.phase != "CLOSE_SETTLE" or a.day != pawn.due:
		return "week_pawn_due"
	if not Merchant._funds(s,payer,receiver,amount):
		return "week_pawn_funds"
	var fit: Dictionary = placement(s,defs,target)
	if not fit.get("ok",false):
		return "week_pawn_space"
	for id: String in Objects.family(s,"WAT02"):
		var member: Dictionary = s.items[id]
		if not accepting and (member.owner_id != "G04" or member.custodian_id != "player" or member.status != "custody_pawn"):
			return "week_pawn_custody"
		member.custodian_id = "player" if accepting else "G04"
		member.status = "custody_pawn" if accepting else "stock"
		member.version += 1
	item.inventory = target
	item.x = fit.x
	item.y = fit.y
	item.rotated = fit.rotated
	Merchant._send(s,payer,receiver,amount)
	pawn.status = "pledged" if accepting else "redeemed"
	pawn.events.append({"action":command.action_id,"day":a.day,"kind":kind,"payer":payer,"payee":receiver,"amount":amount.duplicate(),"item_id":"WAT02"})
	if accepting:
		a.outcomes[a.active] = "pawned"
		a.phase = "CUSTOMER_EXIT"
	return ""

static func expire(s: Dictionary, defs: Dictionary, action: String) -> void:
	var a: Dictionary = s.alpha_shop
	if not a.has("week_pawn") or a.week_pawn.status != "pledged" or a.day != a.week_pawn.due:
		return
	var weights: Dictionary = {}
	for id: String in Objects.family(s,"WAT02"):
		weights[id] = defs[s.items[id].def_id].weight
	var costs: Dictionary = preload("res://src/domain/item_primitives.gd").allocate_cost(PRINCIPAL.VKC,weights)
	for id: String in weights:
		var item: Dictionary = s.items[id]
		item.owner_id = "player"
		item.status = "stock"
		item.basis = {"VKC":costs[id],"USD":0}
		item.version += 1
	a.week_pawn.status = "forfeited"
	a.week_pawn.events.append({"action":action,"day":a.day,"kind":"forfeited","item_id":"WAT02"})
