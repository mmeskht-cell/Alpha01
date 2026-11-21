extends SceneTree
## B2 Q06: actual named Ian and regular G03 incoming commissions share
## one GameSession/Commission authority, real D4/D5 stock, wallet, ledger,
## provenance, replay and cold A/B save. Separate profile/slot from G03 pilot.
const Seed = preload("res://src/content/alpha_b2_named_commission_seed.gd")
const Legacy = preload("res://src/content/alpha_b2_commission_seed.gd")
const Commission = preload("res://src/domain/alpha_commission.gd")
const Session = preload("res://src/domain/game_session.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
const Rules = preload("res://src/domain/value_rules.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
	return ok

func fresh() -> RefCounted:
	var data: Dictionary = Seed.content()
	var s := Session.new()
	if data.is_empty() or not s.initialize(data.defs,data.state,false,false,{},data.alpha_profile):
		printerr("B2_NAMED_INITIALIZATION: ",s.initialization_error())
		return null
	return s

func cmd(s: RefCounted, action: String, p: Dictionary = {}) -> Dictionary:
	return {"action_id":"b2_named_"+str(s.snapshot().revision+1),
		"expected_revision":s.snapshot().revision,"type":action,"payload":p}

func go(s: RefCounted, action: String, p: Dictionary = {}) -> bool:
	var result: Dictionary = s.execute(cmd(s,action,p))
	if not result.ok:
		printerr("B2_NAMED_ACTION: ",action," ",result)
	return result.ok

func deny(s: RefCounted, action: String, p: Dictionary = {}) -> bool:
	var before: Dictionary = s.snapshot()
	return not s.execute(cmd(s,action,p)).ok and s.snapshot() == before

func visitor(s: RefCounted, actor_id: String) -> bool:
	return go(s,"alpha_next_customer") and go(s,"alpha_ack_entry") and str(s.alpha_view().active.get("actor_id","")) == actor_id

func leave(s: RefCounted) -> bool:
	return go(s,"alpha_finish_customer") and go(s,"alpha_ack_exit")

func day_end(s: RefCounted) -> bool:
	return go(s,"alpha_close") and go(s,"alpha_settle") and go(s,"alpha_next_day") and go(s,"alpha_prepare_day")

func purchase(s: RefCounted, visit_id: String, item_id: String, seller_id: String, amount: int) -> bool:
	var payload := {"visit_id":visit_id,"item_id":item_id,"seller":seller_id,"buyer":"player",
		"currency":"VKC","amount":amount,"inventory":"player_stock","x":0,"y":0,"rotated":false}
	return go(s,"alpha_price_offer",{"amount":amount}) and go(s,"alpha_trade",payload) and go(s,"alpha_ack_exit")

func _initialize() -> void:
	var source: Dictionary = Seed.content()
	var original: Dictionary = Legacy.content()
	check(not source.is_empty() and not original.is_empty(), "both profiles have real original source inventory")
	if source.is_empty() or original.is_empty():
		quit(1)
		return
	check(source.alpha_profile.content_version != original.alpha_profile.content_version and source.alpha_profile.commission_profile_id != original.alpha_profile.commission_profile_id, "strict opt-in independent profile")
	check(original.alpha_profile.commission_profile_id == "b2_commission_pilot_1" and Commission.config().requests.size() == 1, "released G03 contract config remains unchanged")
	check(source.state.visits.hygiene_sale == original.state.visits.hygiene_sale and source.state.items.HY05 == original.state.items.HY05, "reuses identical D5 named buyer visit and existing physical hygiene goods")
	check(source.state.wallets == original.state.wallets and source.state.ledger == original.state.ledger and source.state.items == original.state.items, "no minted money or stock")
	check(source.alpha_profile.days[0].size() <= 10 and source.alpha_profile.days[4].size() <= 10, "finite named request and actual return slots")
	var s: RefCounted = fresh()
	if not check(s != null,"named/regular parity game session initializes"):
		quit(1)
		return
	var start: Dictionary = s.snapshot()
	check(start.wallets.player.VKC == 180 and start.wallets.ian.VKC == 115 and start.items.HY05.owner_id == "G05", "Ian's finite original 115 VKC includes existing D6 service budget; HY05 belongs to G05")
	check(deny(s,"alpha_commission_accept",{"request_id":"hygiene_for_ian"}), "named acceptance forbidden without named encounter")
	check(go(s,"alpha_open"),"D1 original counter opens")
	for actor: String in ["G01","G02","G03","marcus","ian"]:
		if not check(visitor(s,actor),"actual D1 actor "+actor):
			quit(1)
			return
		var visit: Dictionary = s.alpha_view().active
		if actor == "G03" or actor == "ian":
			check(str(visit.kind) == ("named" if actor == "ian" else "regular"), "same counter preserves actor category "+actor)
			var request_id: String = "hygiene_for_ian" if actor == "ian" else "tool_for_g03"
			var offered: bool = false
			for e: Dictionary in s.alpha_view().commissions.entries:
				if e.request_id == request_id and e.can_accept and e.actor_id == actor:
					offered = true
			check(offered,"real incoming offer bound to "+actor)
			check(go(s,"alpha_commission_accept",{"request_id":request_id}),"same commission accept command "+actor)
			check(deny(s,"alpha_commission_accept",{"request_id":request_id}),"duplicate acceptance blocked "+actor)
		if actor == "G03":
			check(deny(s,"alpha_commission_accept",{"request_id":"hygiene_for_ian"}),"G03 cannot impersonate Ian's actual offer")
		if not check(leave(s),"customer leaves real D1 counter "+actor):
			quit(1)
			return
	check(s.snapshot().wallets == start.wallets and s.snapshot().ledger == start.ledger,"both accepted offers have zero cash and item effects")
	check(s.snapshot().alpha_shop.commissions.entries.tool_for_g03.status == "accepted" and s.snapshot().alpha_shop.commissions.entries.hygiene_for_ian.status == "accepted","two distinct obligations, one source of truth")
	check(deny(s,"alpha_commission_reserve",{"request_id":"hygiene_for_ian","item_id":"HY05"}),"cannot reserve still-G05-owned hygiene goods")
	var db := Repo.new("user://zt_rebuild/b2_named_parity_"+str(Time.get_ticks_usec()))
	check(db.save_session(s,"named").ok,"cold save both accepted obligations")
	var resumed: RefCounted = fresh()
	check(resumed != null and db.load_session(resumed,"named").ok and resumed.snapshot() == s.snapshot(),"both accepted obligations survive A/B cold restore")
	if not check(day_end(s),"D1 settle into D2 without fake funds"):
		quit(1)
		return
	for day: int in [2,3]:
		if not check(go(s,"alpha_open") and day_end(s),"D%d no phantom procurement"%day):
			quit(1)
			return
	check(go(s,"alpha_open"),"D4 open with both obligations")
	if not check(visitor(s,"G12") and leave(s),"D4 first ordinary visitor"):
		quit(1)
		return
	if not check(visitor(s,"G01") and purchase(s,"tool_buy","TL04","G01",60),"real TL04 60 VKC purchase from existing G01"):
		quit(1)
		return
	check(go(s,"alpha_commission_reserve",{"request_id":"tool_for_g03","item_id":"TL04"}),"G03 item reservation uses original B2 path")
	check(deny(s,"alpha_commission_reserve",{"request_id":"hygiene_for_ian","item_id":"TL04"}),"Ian's order cannot seize G03 reserved/wrong product")
	if not check(visitor(s,"G04") and leave(s) and visitor(s,"G03"),"G03 real D4 return after regular buyer"):
		quit(1)
		return
	check(deny(s,"alpha_commission_deliver",{"request_id":"hygiene_for_ian"}),"Ian's D5 obligation cannot be delivered to G03")
	check(go(s,"alpha_commission_deliver",{"request_id":"tool_for_g03"}) and go(s,"alpha_ack_exit"),"G03 receives TL04 by same atomic transfer")
	check(s.snapshot().items.TL04.owner_id == "G03" and s.snapshot().items.TL04.basis.VKC == 60 and s.snapshot().ledger.size() == 2, "real first handover and original 60 basis")
	check(s.snapshot().wallets.player.VKC == 210 and s.snapshot().alpha_shop.commissions.entries.hygiene_for_ian.status == "accepted", "paid G03 does not secretly settle named obligation")
	if not check(day_end(s),"D4 closes while named D5 request remains pending"):
		quit(1)
		return
	check(go(s,"alpha_open"),"D5 named delivery day opens")
	if not check(visitor(s,"G05") and purchase(s,"hygiene_buy","HY05","G05",60),"actual HY05 purchased for 60 VKC from original G05"):
		quit(1)
		return
	check(s.snapshot().wallets.player.VKC == 150 and s.snapshot().items.HY05.owner_id == "player", "D5 acquisition cost and actual stock conserved")
	check(go(s,"alpha_commission_reserve",{"request_id":"hygiene_for_ian","item_id":"HY05"}),"named request reserves only physically owned HY05")
	check(deny(s,"alpha_display",{"item_id":"HY05","x":0,"y":0,"rotated":false}),"reserved named request stock cannot be listed")
	if not check(visitor(s,"ian"),"original named buyer physically revisits D5"):
		quit(1)
		return
	check(s.alpha_view().active.kind == "named" and s.alpha_view().commissions.entries[1].can_deliver,"Ian named visit uses same ready->handover controls")
	check(deny(s,"alpha_trade",{"visit_id":"hygiene_sale","item_id":"HY05","seller":"player","buyer":"ian","currency":"VKC","amount":90,"inventory":"ian_grid","x":5,"y":4,"rotated":false}),"named commission cannot bypass atomic reserved delivery")
	var delivery: Dictionary = cmd(s,"alpha_commission_deliver",{"request_id":"hygiene_for_ian"})
	check(s.execute(delivery).ok,"named delivery command settled via same GameSession authority")
	var final: Dictionary = s.snapshot()
	check(final.alpha_shop.commissions.entries.hygiene_for_ian.status == "fulfilled" and final.alpha_shop.commissions.entries.tool_for_g03.status == "fulfilled", "regular and named both fulfilled")
	check(final.items.HY05.owner_id == "ian" and final.items.HY05.inventory == "ian_grid" and final.items.HY05.basis.VKC == 60 and final.items.HY05.reservation_id.is_empty(), "real HY05 with preserved 60 VKC basis and released reservation")
	check(final.wallets.player.VKC == 240 and final.wallets.ian.VKC == 25 and final.ledger.size() == 4, "two real purchases plus two real sales, finite wallets")
	check(final.ledger[3].visit_id == "hygiene_sale" and final.ledger[3].amounts.VKC == 90 and final.alpha_shop.commissions.settlements.size() == 2, "named handover retained original visit and exactly one new receipt")
	check(s.execute(delivery).ok and s.snapshot() == final, "same named action id replay is idempotent")
	check(deny(s,"alpha_commission_deliver",{"request_id":"hygiene_for_ian"}),"new duplicate named delivery command rejected")
	check(db.save_session(s,"named").ok,"cold saved both fulfilled obligations")
	var cold: RefCounted = fresh()
	check(cold != null and db.load_session(cold,"named").ok and cold.snapshot() == final, "named+regular settlement A/B cold replay exact")
	var tamper: Dictionary = final.duplicate(true)
	tamper.alpha_shop.commissions.settlements[1].price.VKC = 999
	check(not s.restore(tamper) and s.snapshot() == final, "forged named delivery receipt rejected")
	check(go(s,"alpha_ack_exit") and go(s,"alpha_close") and go(s,"alpha_settle") and go(s,"alpha_next_day") and go(s,"alpha_prepare_day"),"D6 begins with only original authored history")
	check(s.alpha_view().news.size() >= 1, "existing clinic supply news source follows actual hygiene_sale ledger, not synthetic quest reward")
	print("ALPHA_B2_NAMED_PARITY_CHECKS=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
