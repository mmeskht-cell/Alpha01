extends "res://tests/scenarios/alpha_b3_m7_finite_interest_test.gd"
const Week = preload("res://src/content/alpha_b3_week_candidate.gd")

func purchase(s: RefCounted, visit: String, item: String, seller: String, amount: int) -> bool:
	return go(s,"alpha_price_offer",{"amount":amount}) and go(s,"alpha_trade",{
		"visit_id":visit,"item_id":item,"seller":seller,"buyer":"player","currency":"VKC",
		"amount":amount,"inventory":"player_stock","x":0 if item=="R001" else 6,"y":0,"rotated":false})

func operate(s: RefCounted, route: String) -> bool:
	var view: Dictionary = s.alpha_view()
	var id: String = view.active.id
	if route == "market" and id == "visit_g01":
		return purchase(s,id,"R001","G01",100)
	if route in ["market","combined"] and view.day == 2 and id in ["radio_recovery","alpha_b3_g09_radio_d2"] and s.snapshot().items.R001.owner_id == "player":
		var buyer: String = view.active.actor_id
		return go(s,"alpha_price_offer",{"amount":130}) and go(s,"alpha_trade",{"visit_id":id,"item_id":"R001","seller":"player","buyer":buyer,"currency":"VKC","amount":130,"inventory":buyer+"_grid","x":6,"y":4,"rotated":false})
	if id == "visit_g01" and route in ["return","empty","cancel","combined","shortage"]:
		if not go(s,"alpha_exchange_contact",{"actor_id":"G01","accepted":true}):
			return false
		if route in ["return","combined","shortage"]:
			return purchase(s,id,"R001","G01",100)
	if id == "watch_a" and route in ["redeem","extend","forfeit","combined","shortage"]:
		return go(s,"week_pledge")
	if id == "tool_buy" and route == "shortage":
		if not go(s,"alpha_price_offer",{"amount":60}):
			return false
		var before: Dictionary = s.snapshot()
		var rejected: Dictionary = s.execute(command(s,"alpha_trade",{"visit_id":id,"item_id":"TL04","seller":"G01","buyer":"player","currency":"VKC","amount":60,"inventory":"player_stock","x":6,"y":0,"rotated":false}))
		if rejected.get("ok",false) or s.snapshot() != before:
			return false
		return go(s,"alpha_finish_customer")
	if id == "alpha_b3_g08_watch_d6" and route == "shortage":
		return go(s,"alpha_price_offer",{"amount":140}) and go(s,"alpha_trade",{"visit_id":id,"item_id":"WAT02","seller":"player","buyer":"G08","currency":"VKC","amount":140,"inventory":"G08_grid","x":6,"y":4,"rotated":false})
	if id == "tool_buy" and route in ["return","combined"]:
		return purchase(s,id,"TL04","G01",60)
	return go(s,"alpha_finish_customer")

func campaign(route: String) -> bool:
	var source: Dictionary = Week.content(101)
	var s: RefCounted = fresh(source)
	if s == null:
		return false
	var start: Dictionary = s.snapshot()
	var disk := Repo.new("user://zt_rebuild/week_candidate_test_" + route + str(Time.get_ticks_usec()))
	for day: int in range(1,8):
		if not go(s,"alpha_open"):
			return false
		var serve: bool = (day == 1 and route in ["return","empty","cancel","combined","shortage"]) or (day == 2 and route in ["redeem","extend","forfeit","combined","shortage"]) or (day == 4 and route in ["return","combined","shortage"])
		serve = serve or (route in ["market","combined"] and day in [1,2])
		serve = serve or (day == 6 and route == "shortage")
		while serve and int(s.alpha_view().remaining) > 0:
			if not (go(s,"alpha_next_customer") and go(s,"alpha_ack_entry") and operate(s,route) and go(s,"alpha_ack_exit")):
				return false
		if not go(s,"alpha_close"):
			return false
		if day == 4 and route == "extend" and not go(s,"week_extend"):
			return false
		if ((day == 4 and route in ["redeem","combined"]) or (day == 6 and route == "extend")) and not go(s,"week_redeem"):
			return false
		if not go(s,"alpha_settle"):
			return false
		if day == 1 and route in ["market","combined"] and not go(s,"alpha_display",{"item_id":"R001","x":0,"y":0,"rotated":false}):
			return false
		if day == 1 and route in ["return","empty","cancel","combined","shortage"]:
			var cmd: Dictionary = command(s,"alpha_salvage_dispatch",{"request_id":"tool_search"})
			if not s.execute(cmd).get("ok",false):
				return false
			var paid: Dictionary = s.snapshot()
			if not s.execute(cmd).get("ok",false) or s.snapshot() != paid:
				return false
			if route == "cancel" and not go(s,"alpha_salvage_cancel",{"request_id":"tool_search"}):
				return false
		if day == 4 and route == "shortage" and not go(s,"alpha_display",{"item_id":"WAT02","x":0,"y":0,"rotated":false}):
			return false
		if day == 3:
			var snapshot: Dictionary = s.snapshot()
			if route in ["return","empty"] and snapshot.alpha_shop.outbound.tool_search.status != "delayed":
				return false
			if not disk.save_session(s,"week").get("ok",false):
				return false
			s = fresh(source)
			if s == null or not disk.load_session(s,"week").get("ok",false) or s.snapshot() != snapshot:
				return false
		if not go(s,"alpha_next_day") or (day < 7 and not go(s,"alpha_prepare_day")):
			return false
	var end: Dictionary = s.snapshot()
	if end.alpha_shop.phase != "COMPLETE" or summed(start.wallets,"VKC") != summed(end.wallets,"VKC") or summed(start.wallets,"USD") != summed(end.wallets,"USD") or end.items.size() != start.items.size():
		return false
	match route:
		"shortage":
			return end.items.WAT02.owner_id == "G08" and end.items.TL04.owner_id == "G01" and end.alpha_shop.outbound.tool_search.status == "declined" and end.wallets.player.VKC == start.wallets.player.VKC - 10
		"combined":
			return end.alpha_shop.week_pawn.status == "redeemed" and end.alpha_shop.outbound.tool_search.status == "received" and end.items.WAT02.owner_id == "G04" and end.items.TL04.owner_id == "player" and end.wallets.player.VKC == start.wallets.player.VKC - 35
		"market":
			return end.ledger.size() == 2 and end.visits.week_tool_buy_d7.prices.TL04 == {"VKC":0,"USD":1} and end.visits.tool_buy.prices.TL04 == start.visits.tool_buy.prices.TL04 and end.wallets.player.VKC == start.wallets.player.VKC + 30
		"return":
			return end.alpha_shop.outbound.tool_search.status == "received" and end.items.TL04.owner_id == "player" and end.wallets.player.VKC == start.wallets.player.VKC - 170
		"cancel","empty":
			return end.alpha_shop.outbound.tool_search.status == ("cancelled" if route=="cancel" else "empty") and end.wallets.player.VKC == start.wallets.player.VKC - (0 if route=="cancel" else 10)
		"forfeit":
			return end.alpha_shop.week_pawn.status == "forfeited" and end.items.WAT02.owner_id == "player" and end.items.WAT02.basis.VKC == 40
		"extend","redeem":
			return end.alpha_shop.week_pawn.status == "redeemed" and end.items.WAT02.custodian_id == "G04" and end.wallets.player.VKC == start.wallets.player.VKC + 5
	return false

# Each seven-day route runs in its own Godot process. Never remove a
# route merely to meet the fixed-check budget: each owns a 45s timeout.
const ROUTES: Array = ["return","empty","cancel","redeem","extend","forfeit","market","combined","shortage"]

func done() -> void:
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	var route: String = str(argv[0]) if argv.size() == 1 else "invalid"
	print("ALPHA_B3_INTEGRATED_WEEK_PART ", route, ": ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)

func _initialize() -> void:
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	if argv.size() != 1 or str(argv[0]) not in ROUTES:
		check(false, "exactly one supported first-week route argument is required")
		done()
		return
	var route: String = str(argv[0])
	check(campaign(route), "integrated first week: " + route)
	done()
