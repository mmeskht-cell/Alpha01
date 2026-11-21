extends SceneTree
## B2 authoring: one real physical tool, existing G03's finite funded wallet,
## actual Day4 return, reservation conflict, one transfer, A/B save and replay.
const Seed = preload("res://src/content/alpha_b2_commission_seed.gd")
const Session = preload("res://src/domain/game_session.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
const REQUEST: String = "tool_for_g03"
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
	return ok

func fresh() -> RefCounted:
	var data: Dictionary = Seed.content()
	var s := Session.new()
	if data.is_empty() or not s.initialize(data.defs,data.state,false,false,{},data.alpha_profile):
		printerr("B2_COMMISSION_INIT: ",s.initialization_error())
		return null
	return s

func command(s: RefCounted, kind: String, p: Dictionary = {}) -> Dictionary:
	return {"action_id":"b2_commission_"+str(s.snapshot().revision+1),
		"expected_revision":s.snapshot().revision,"type":kind,"payload":p}

func go(s: RefCounted, kind: String, p: Dictionary = {}) -> bool:
	var result: Dictionary = s.execute(command(s,kind,p))
	if not result.ok:
		printerr("B2_COMMISSION_ACTION_FAIL ",kind," ",p," : ",result)
	return bool(result.ok)

func deny(s: RefCounted, kind: String, p: Dictionary = {}) -> bool:
	var before: Dictionary = s.snapshot()
	var result: Dictionary = s.execute(command(s,kind,p))
	return not result.ok and before == s.snapshot()

func next_actor(s: RefCounted) -> String:
	if not go(s,"alpha_next_customer") or not go(s,"alpha_ack_entry"):
		return ""
	return str(s.alpha_view().active.get("actor_id",""))

func leave(s: RefCounted) -> bool:
	return go(s,"alpha_finish_customer") and go(s,"alpha_ack_exit")

func next_day(s: RefCounted) -> bool:
	return go(s,"alpha_close") and go(s,"alpha_settle") and go(s,"alpha_next_day") and go(s,"alpha_prepare_day")

func skip_today(s: RefCounted) -> bool:
	return go(s,"alpha_open") and next_day(s)

func buy_tool(s: RefCounted) -> bool:
	if not go(s,"alpha_price_offer",{"amount":60}):
		return false
	var p: Dictionary = {"visit_id":"tool_buy","item_id":"TL04","seller":"G01","buyer":"player",
		"currency":"VKC","amount":60,"inventory":"player_stock","x":0,"y":0,"rotated":false}
	return go(s,"alpha_trade",p) and go(s,"alpha_ack_exit")

func start_g03(s: RefCounted) -> bool:
	if not go(s,"alpha_open"):
		return false
	for actor: String in ["G01","G02"]:
		if next_actor(s) != actor or not leave(s):
			return false
	return next_actor(s) == "G03"

func to_day4(s: RefCounted) -> bool:
	if not leave(s) or not next_day(s):
		return false
	if not skip_today(s) or not skip_today(s):
		return false
	return go(s,"alpha_open")

func happy() -> void:
	var s: RefCounted = fresh()
	if not check(s != null,"commission profile uses existing actor and real item"):
		return
	var initial: Dictionary = s.snapshot()
	check(initial.wallets.player.VKC == 180 and initial.wallets.G03.VKC >= 90, "no new cash: original seeded wallets")
	check(initial.items.TL04.owner_id == "G01" and initial.items.TL04.inventory == "G01_grid", "target physically held by actual Day4 seller")
	check(initial.alpha_shop.profile.days[3].size() <= 10, "authored return respects finite daily visitor capacity")
	check(deny(s,"alpha_commission_accept",{"request_id":REQUEST}),"cannot accept without real counter meeting")
	if not check(start_g03(s),"D1 existing G03 customer offers on same counter"):
		return
	check(s.alpha_view().commissions.entries[0].status=="offered","actual request appears only on authorized visit")
	check(deny(s,"alpha_commission_accept",{"request_id":"forged"}),"forged request refused")
	check(go(s,"alpha_commission_accept",{"request_id":REQUEST}),"explicit acceptance without advance payment")
	check(deny(s,"alpha_commission_accept",{"request_id":REQUEST}),"no double acceptance")
	check(s.snapshot().wallets == initial.wallets and s.snapshot().ledger.is_empty(), "acceptance neither moves cash nor mints inventory")
	check(deny(s,"alpha_commission_reserve",{"request_id":REQUEST,"item_id":"TL04"}),"cannot reserve customer's not-yet-purchased tool")
	if not check(to_day4(s),"D2/D3 skip and D4 start preserve contract"):
		return
	if not check(next_actor(s)=="G12" and leave(s),"D4 existing first customer"):
		return
	if not check(next_actor(s)=="G01" and buy_tool(s),"real tool bought for 60 VKC from original G01 visit"):
		return
	check(s.snapshot().wallets.player.VKC == 120 and s.snapshot().items.TL04.owner_id == "player", "no phantom tool or free money")
	check(deny(s,"alpha_commission_reserve",{"request_id":REQUEST,"item_id":"R001"}),"cannot reserve another SKU or nonexistent owned object")
	check(go(s,"alpha_commission_reserve",{"request_id":REQUEST,"item_id":"TL04"}),"single physical tool reserved after actual inspection")
	check(s.snapshot().items.TL04.reservation_id == REQUEST and s.alpha_view().commissions.entries[0].status=="ready", "ownership intact; order is READY")
	check(deny(s,"alpha_commission_reserve",{"request_id":REQUEST,"item_id":"TL04"}),"cannot duplicate reservation")
	check(deny(s,"alpha_display",{"item_id":"TL04","x":0,"y":0,"rotated":false}),"reserved item cannot be placed on normal public shelf")
	check(deny(s,"alpha_commission_deliver",{"request_id":REQUEST}),"no remote delivery before G03's actual revisit")
	if not check(next_actor(s)=="G04","normal buyer remains in visit schedule"):
		return
	check(deny(s,"alpha_trade",{"visit_id":"tool_sale","item_id":"TL04","seller":"player","buyer":"G04","currency":"VKC","amount":95,"inventory":"G04_grid","x":5,"y":4,"rotated":false}),"ordinary resale cannot bypass reservation")
	if not check(leave(s) and next_actor(s)=="G03","same commissioned customer returns in D4 authored slot"):
		return
	check(s.alpha_view().commissions.entries[0].can_deliver,"same counter shows prepared delivery")
	check(deny(s,"alpha_commission_deliver",{"request_id":REQUEST,"actor_id":"G04"}),"forged recipient payload rejected")
	check(deny(s,"alpha_commission_deliver",{"request_id":"different"}),"wrong request rejected")
	var before: Dictionary = s.snapshot()
	var final_command: Dictionary = command(s,"alpha_commission_deliver",{"request_id":REQUEST})
	var paid: Dictionary = s.execute(final_command)
	check(paid.ok,"one atomic actual transfer and settlement")
	if not paid.ok:
		printerr("B2_COMMISSION_DELIVER_DIAGNOSTIC ",paid)
		return
	var after: Dictionary = s.snapshot()
	check(after.alpha_shop.commissions.entries[REQUEST].status=="fulfilled" and after.alpha_shop.commissions.settlements.size()==1,"FULFILLED once with exact action")
	check(after.items.TL04.owner_id=="G03" and after.items.TL04.custodian_id=="G03" and after.items.TL04.reservation_id.is_empty(),"reserved tool actually delivered")
	check(after.items.TL04.basis.VKC == 60 and after.ledger.size()==2 and after.ledger[1].amounts.VKC==90, "acquisition basis and real price recorded")
	check(after.wallets.player.VKC == 210 and after.wallets.G03.VKC == initial.wallets.G03.VKC - 90,"actual player/buyer wallets conserved")
	check(after.alpha_shop.phase=="CUSTOMER_EXIT" and after.visits.alpha_commission_g03_d4.scope.completed, "pickup visit completed after delivery")
	check(deny(s,"alpha_commission_deliver",{"request_id":REQUEST}),"repeated new delivery cannot pay again")
	check(s.execute(final_command).ok and s.snapshot()==after,"same action id replays idempotently without settlement")
	var save := Repo.new("user://zt_rebuild/b2_commission_happy_"+str(Time.get_ticks_usec()))
	check(save.save_session(s,"commission").ok,"A/B persisted real fulfilment")
	var reloaded: RefCounted = fresh()
	var loaded: Dictionary = save.load_session(reloaded,"commission") if reloaded != null else {}
	check(loaded.get("ok",false) and reloaded.snapshot()==after,"seed replay accepts exact cold restore")
	var forged: Dictionary = after.duplicate(true)
	forged.alpha_shop.commissions.settlements[0].price.VKC=999
	check(not s.restore(forged),"forged payout rejected by canonical replay")
	check(s.snapshot()==after,"tamper rejection keeps authentic state")
	check(after.receipt_archive.size()>0,"long transaction path exercised 32-receipt archival")

func declined() -> void:
	var s: RefCounted = fresh()
	if not check(s != null and start_g03(s),"ordinary G03 can refuse"):
		return
	check(go(s,"alpha_commission_decline",{"request_id":REQUEST}),"explicit refusal has no obligation")
	check(s.snapshot().wallets.player.VKC==180 and s.snapshot().alpha_shop.commissions.entries[REQUEST].status=="declined","decline changes status, not wallet")
	if not check(to_day4(s),"refused path reaches D4"):
		return
	check(s.alpha_view().remaining==3,"refused pickup does not create ghost fourth visitor")
	for actor: String in ["G12","G01","G04"]:
		check(next_actor(s)==actor and leave(s),"D4 legitimate original visitor "+actor)
	check(s.alpha_view().remaining==0 and deny(s,"alpha_next_customer"),"unaccepted G03 return never becomes an actual visit")
	check(go(s,"alpha_close") and go(s,"alpha_settle"),"declined contract closes without a debt")
	check(s.snapshot().alpha_shop.commissions.settlements.is_empty() and s.snapshot().wallets.G03.VKC>=90,"no fake commission earnings")

func expired() -> void:
	var s: RefCounted = fresh()
	if not check(s != null and start_g03(s) and go(s,"alpha_commission_accept",{"request_id":REQUEST}),"expired path explicit acceptance"):
		return
	if not check(to_day4(s),"accepted but unfinished request reaches D4"):
		return
	if not check(next_actor(s)=="G12" and leave(s) and next_actor(s)=="G01" and buy_tool(s),"actually sourced tool before contract deadline"):
		return
	check(go(s,"alpha_commission_reserve",{"request_id":REQUEST,"item_id":"TL04"}),"hold existing item without issuing refund or fee")
	check(go(s,"alpha_close") and go(s,"alpha_settle"),"early D4 close forfeits scheduled pickup once")
	var after: Dictionary=s.snapshot()
	check(after.alpha_shop.commissions.entries[REQUEST].status=="expired" and after.items.TL04.reservation_id.is_empty(),"deadline releases real reservation")
	check(after.wallets.player.VKC == 120 and after.items.TL04.owner_id=="player" and after.alpha_shop.commissions.settlements.is_empty(),"expiry neither invents money nor confiscates owned stock")
	check(go(s,"alpha_display",{"item_id":"TL04","x":0,"y":0,"rotated":false}),"unreserved item returns to usable stock after expiry")
	check(deny(s,"alpha_commission_deliver",{"request_id":REQUEST}),"no delivery after expiry")
	var db := Repo.new("user://zt_rebuild/b2_commission_expiry_"+str(Time.get_ticks_usec()))
	check(db.save_session(s,"commission").ok,"expired reservation persists safely")
	var cold: RefCounted=fresh()
	check(cold != null and db.load_session(cold,"commission").ok and cold.snapshot()==s.snapshot(),"expiry and physical release cold restore")

func bypass() -> void:
	var s: RefCounted=fresh()
	if not check(s != null and start_g03(s) and go(s,"alpha_commission_accept",{"request_id":REQUEST}),"bypass setup"):
		return
	if not check(to_day4(s) and next_actor(s)=="G12" and leave(s) and next_actor(s)=="G01" and buy_tool(s),"real stock acquired before pickup"):
		return
	check(go(s,"alpha_display",{"item_id":"TL04","x":0,"y":0,"rotated":false}),"actual player stock can be displayed before binding")
	if not check(next_actor(s)=="G04" and leave(s) and next_actor(s)=="G03","G03 returns even when player forgot reservation"):
		return
	check(s.alpha_view().appraisal.is_empty(),"returning customer cannot use unrelated ordinary appraisal/bargaining")
	check(deny(s,"alpha_price_offer",{"amount":90}),"return visit blocks unofficial price offers")
	check(deny(s,"alpha_trade",{"visit_id":"alpha_commission_g03_d4","item_id":"TL04","seller":"player",
		"buyer":"G03","currency":"VKC","amount":90,"inventory":"G03_grid","x":0,"y":0,"rotated":false}),"ordinary retail command cannot bypass accepted obligation")
	check(deny(s,"alpha_commission_deliver",{"request_id":REQUEST}),"no forged delivery without physical reservation")
	check(s.snapshot().ledger.size()==1 and s.snapshot().wallets.player.VKC==120,"both sales remain uncommitted, no phantom payout")
	check(leave(s) and go(s,"alpha_close") and go(s,"alpha_settle"),"unfinished pickup resolves at real deadline")
	check(s.snapshot().alpha_shop.commissions.entries[REQUEST].status=="expired" and s.snapshot().items.TL04.owner_id=="player","unsatisfied buyer may not seize ordinary listed stock")


func _initialize() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=1 or args[0] not in ["happy","declined","expired","bypass"]:
		printerr("ALPHA_B2_COMMISSION_PART_REQUIRED")
		quit(2)
		return
	match args[0]:
		"happy": happy()
		"declined": declined()
		"expired": expired()
		"bypass": bypass()
	print("ALPHA_B2_COMMISSION_CHECKS part=",args[0]," checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
