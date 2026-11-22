extends SceneTree
## B2 service commission: actual W001 stays owned by G02 throughout. Only
## custody, permitted restoration, fee and physical original-grid return move.
const Seed = preload("res://src/content/alpha_b2_service_seed.gd")
const RecoverySeed = preload("res://src/content/alpha_b2_service_recovery_seed.gd")
const MultiSeed = preload("res://src/content/alpha_b2_service_multi_seed.gd")
const Named = preload("res://src/content/alpha_b2_named_commission_seed.gd")
const Session = preload("res://src/domain/game_session.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
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
		printerr("B2_SERVICE_INIT: ",s.initialization_error() if not data.is_empty() else "source")
		return null
	return s

func recovery_fresh() -> RefCounted:
	var data: Dictionary = RecoverySeed.content()
	var s := Session.new()
	if data.is_empty() or not s.initialize(data.defs,data.state,false,false,{},data.alpha_profile):
		printerr("B2_RECOVERY_INIT: ",s.initialization_error() if not data.is_empty() else "source")
		return null
	return s

func multi_fresh() -> RefCounted:
	var data: Dictionary = MultiSeed.content()
	var s := Session.new()
	if data.is_empty() or not s.initialize(data.defs,data.state,false,false,{},data.alpha_profile):
		printerr("B2_MULTI_INIT: ",s.initialization_error() if not data.is_empty() else "source")
		return null
	return s

func command(s: RefCounted, kind: String, payload: Dictionary={}) -> Dictionary:
	return {"action_id":"b2_service_"+str(s.snapshot().revision+1),"expected_revision":s.snapshot().revision,"type":kind,"payload":payload}

func go(s: RefCounted, kind: String, payload: Dictionary={}) -> bool:
	var r: Dictionary=s.execute(command(s,kind,payload))
	if not r.ok:
		printerr("B2_SERVICE_COMMAND ",kind," ",r," validation=",s._validation_error)
	return r.ok

func deny(s: RefCounted, kind: String, payload: Dictionary={}) -> bool:
	var before: Dictionary=s.snapshot()
	return not s.execute(command(s,kind,payload)).ok and s.snapshot()==before

func active(s: RefCounted, actor: String) -> bool:
	return go(s,"alpha_next_customer") and go(s,"alpha_ack_entry") and s.alpha_view().active.actor_id==actor

func leave(s: RefCounted) -> bool:
	return go(s,"alpha_finish_customer") and go(s,"alpha_ack_exit")

func g02_offer(s: RefCounted) -> bool:
	return go(s,"alpha_open") and active(s,"G01") and leave(s) and active(s,"G02")

func evening(s: RefCounted) -> bool:
	return leave(s) and go(s,"alpha_close") and go(s,"alpha_settle")

func day2(s: RefCounted) -> bool:
	return go(s,"alpha_next_day") and go(s,"alpha_prepare_day") and go(s,"alpha_open")

func g02_return(s: RefCounted) -> bool:
	for actor: String in ["G03","G04","G05","G06","G07"]:
		if not active(s,actor) or not leave(s):
			return false
	return active(s,"G02")

func happy() -> void:
	var source: Dictionary=Seed.content()
	var legacy: Dictionary=Named.content()
	check(not source.is_empty() and not legacy.is_empty(),"isolated source and frozen named seed exist")
	if source.is_empty() or legacy.is_empty():
		return
	check(source.state.items.W001==legacy.state.items.W001 and source.state.wallets==legacy.state.wallets and source.state.visits==legacy.state.visits,"original owner, funds, visits and physical item all unchanged")
	check(source.alpha_profile.content_version != legacy.alpha_profile.content_version and source.alpha_profile.service_profile_id=="b2_service_custody_pilot_1","source-only opt-in service profile")
	var s: RefCounted=fresh()
	if not check(s!=null,"valid independent service session"):
		return
	var initial: Dictionary=s.snapshot()
	check(initial.items.W001.owner_id=="G02" and not initial.items.W001.functional and initial.items.W001.custodian_id=="G02","broken item really belongs to G02")
	check(deny(s,"alpha_service_accept",{"job_id":"service_w001"}),"cannot accept remote service outside customer visit")
	check(deny(s,"alpha_service_repair",{"job_id":"service_w001","item_id":"W001"}),"no fabricated workshop repair before custody")
	if not check(g02_offer(s),"D1 actual G02 customer enters shared shop"):
		return
	check(s.alpha_view().services.entries[0].can_accept,"same counter explicitly offers G02 service")
	check(deny(s,"alpha_service_accept",{"job_id":"forged"}),"fake job ID denied")
	check(go(s,"alpha_service_accept",{"job_id":"service_w001"}),"G02 grants custody with explicit consent")
	var accepted: Dictionary=s.snapshot()
	check(accepted.items.W001.owner_id=="G02" and accepted.items.W001.custodian_id=="player" and accepted.items.W001.status=="custody_service" and accepted.items.W001.inventory=="service_grid" and accepted.items.W001.service_permission,"customer ownership preserved, only lawful custody moved")
	check(accepted.wallets==initial.wallets and accepted.ledger==initial.ledger and accepted.items.size()==initial.items.size(),"acceptance mints no stock or money")
	check(deny(s,"alpha_service_accept",{"job_id":"service_w001"}),"no duplicate service consent")
	check(deny(s,"alpha_display",{"item_id":"W001","x":0,"y":0,"rotated":false}),"custody cannot be displayed for resale")
	check(deny(s,"alpha_service_repair",{"job_id":"service_w001","item_id":"W001"}),"not allowed to repair during customer interaction")
	if not check(evening(s),"D1 end places repair in real evening work phase"):
		return
	check(s.alpha_view().services.entries[0].can_repair,"actual owned-repair workflow exposes evening action")
	check(deny(s,"alpha_service_repair",{"job_id":"service_w001","item_id":"R001"}),"cannot restore someone else's item under service permission")
	if not check(go(s,"alpha_service_repair",{"job_id":"service_w001","item_id":"W001"}),"existing restore primitive repairs actual W001 with work cost"):
		return
	var repaired: Dictionary=s.snapshot()
	check(repaired.wallets.player.VKC==initial.wallets.player.VKC-10 and repaired.items.W001.owner_id=="G02","workshop charges existing 10 VKC cost but never transfers ownership")
	check(repaired.items.W001.functional and repaired.items.W001.restored and repaired.items.W001.status=="custody_service","actual restored physical object remains in customer custody")
	check(repaired.items.W001.basis==initial.items.W001.basis and repaired.object_events.size()==initial.object_events.size()+1,"customer-owned basis unchanged; real restore object event recorded")
	check(deny(s,"alpha_service_repair",{"job_id":"service_w001","item_id":"W001"}),"no repeated work cost on completed service")
	var db:=Repo.new("user://zt_rebuild/b2_custody_"+str(Time.get_ticks_usec()))
	check(db.save_session(s,"custody").ok,"custody plus finished repair survives A/B save")
	var cold: RefCounted=fresh()
	check(cold != null and db.load_session(cold,"custody").ok and cold.snapshot()==repaired,"cold replay proves customer title intact")
	if not check(day2(s),"day 2 service visit scheduled only after acceptance"):
		return
	check(s.alpha_view().remaining==6,"original five day2 customers plus real G02 service pickup")
	if not check(g02_return(s),"D2 G02 appears only in its actual return slot"):
		return
	check(s.alpha_view().services.entries[0].can_deliver,"only completed repair can be collected for a fee")
	check(deny(s,"alpha_service_deliver",{"job_id":"forged"}),"no invoice impersonation")
	var pay: Dictionary=command(s,"alpha_service_deliver",{"job_id":"service_w001"})
	check(s.execute(pay).ok,"real G02 payment and physical return atomic")
	var after: Dictionary=s.snapshot()
	check(after.items.W001.owner_id=="G02" and after.items.W001.custodian_id=="G02" and after.items.W001.status=="stock" and not after.items.W001.service_permission and after.items.W001.inventory==initial.items.W001.inventory,"physical return to original customer grid; owner never changed")
	check(after.items.W001.functional and after.wallets.player.VKC==initial.wallets.player.VKC+20 and after.wallets.G02.VKC==initial.wallets.G02.VKC-30,"paid 30 minus 10 work cost, finite customer budget")
	check(after.ledger==initial.ledger and after.alpha_shop.services.settlements.size()==1 and after.alpha_shop.services.jobs.service_w001.status=="delivered","service fee is not forged ordinary purchase/sale ledger")
	check(s.execute(pay).ok and s.snapshot()==after,"same action ID is idempotent")
	check(deny(s,"alpha_service_deliver",{"job_id":"service_w001"}),"new duplicate collection rejected")
	check(db.save_session(s,"custody").ok,"cold save exact repaired returned state")
	var restored: RefCounted=fresh()
	check(restored != null and db.load_session(restored,"custody").ok and restored.snapshot()==after,"cold replay after real return/payment")
	var tamper: Dictionary=after.duplicate(true)
	tamper.alpha_shop.services.settlements[0].paid.VKC=9000
	check(not s.restore(tamper) and s.snapshot()==after,"forged fee receipt rejected by replay")

func declined() -> void:
	var s: RefCounted=fresh()
	if not check(s!=null and g02_offer(s),"G02 can refuse service"):
		return
	var before: Dictionary=s.snapshot()
	check(go(s,"alpha_service_decline",{"job_id":"service_w001"}),"customer refuses custody")
	check(s.snapshot().items.W001==before.items.W001 and s.snapshot().wallets==before.wallets,"decline leaves object/title/funds unchanged")
	if not check(evening(s) and day2(s),"D2 after refusal"):
		return
	check(s.alpha_view().remaining==5,"refused service does not spawn phantom G02 D2 return")
	for actor: String in ["G03","G04","G05","G06","G07"]:
		check(active(s,actor) and leave(s),"original D2 visitor "+actor)
	check(deny(s,"alpha_next_customer"),"no service phantom return")
	check(s.snapshot().alpha_shop.services.settlements.is_empty(),"no fee after refusal")

func unpaid() -> void:
	var s: RefCounted=fresh()
	if not check(s!=null and g02_offer(s) and go(s,"alpha_service_accept",{"job_id":"service_w001"}) and evening(s) and day2(s) and g02_return(s),"real D2 return of unworked customer item"):
		return
	var original: Dictionary=s.snapshot()
	check(deny(s,"alpha_service_deliver",{"job_id":"service_w001"}),"cannot charge for work not done")
	check(go(s,"alpha_service_return_unpaid",{"job_id":"service_w001"}),"customer retrieves unrepaired item without fee")
	var after: Dictionary=s.snapshot()
	check(after.items.W001.owner_id=="G02" and after.items.W001.custodian_id=="G02" and not after.items.W001.functional and after.items.W001.inventory=="G02_grid","unrepaired W001 physically returned to rightful owner")
	check(after.wallets==original.wallets and after.alpha_shop.services.settlements[0].paid.VKC==0,"unpaid return does not mint compensation")
	check(deny(s,"alpha_service_deliver",{"job_id":"service_w001"}),"cannot later collect fee without live custody")

func overdue() -> void:
	var s: RefCounted=fresh()
	if not check(s!=null and g02_offer(s) and go(s,"alpha_service_accept",{"job_id":"service_w001"}) and evening(s) and day2(s),"source custody accepted and D2 opened"):
		return
	check(go(s,"alpha_close") and go(s,"alpha_settle"),"uncollected service reaches due-day close")
	var state: Dictionary=s.snapshot()
	check(state.alpha_shop.services.jobs.service_w001.status=="overdue_custody" and state.items.W001.owner_id=="G02" and state.items.W001.custodian_id=="player","missed pickup preserves actual owed customer property instead of teleporting it")
	check(state.alpha_shop.services.settlements.is_empty() and state.wallets.player.VKC==180,"no fake fee or automatic loss")
	check(deny(s,"alpha_display",{"item_id":"W001","x":0,"y":0,"rotated":false}),"overdue custody never becomes shop inventory")

func recovery() -> void:
	var source: Dictionary = RecoverySeed.content()
	var old: Dictionary = Seed.content()
	if not check(not source.is_empty() and not old.is_empty(),"separate recovery pilot source exists"):
		return
	check(source.state == old.state and source.alpha_profile.days[0] == old.alpha_profile.days[0] and source.alpha_profile.days[1] == old.alpha_profile.days[1],"v2 preserves initial funds, item and first two days")
	var s: RefCounted = recovery_fresh()
	if not check(s != null,"v2 service source initializes independently"):
		return
	if not check(g02_offer(s) and go(s,"alpha_service_accept",{"job_id":"service_w001"}) and evening(s),"D1 original consent still required"):
		return
	check(go(s,"alpha_service_repair",{"job_id":"service_w001","item_id":"W001"}),"D1 actual restoration for later recovery")
	if not check(day2(s),"D2 opened with original pickup opportunity"):
		return
	check(s.alpha_view().remaining == 6,"D2 preserved original five plus G02 pickup")
	check(go(s,"alpha_close") and go(s,"alpha_settle"),"D2 missed pickup stays in actual service custody")
	var overdue: Dictionary = s.snapshot()
	check(overdue.alpha_shop.services.jobs.service_w001.status == "overdue_custody" and overdue.items.W001.custodian_id == "player" and overdue.items.W001.owner_id == "G02" and overdue.wallets.player.VKC == 170,"missed pickup preserves customer title and actual repair cost")
	check(overdue.alpha_shop.services.settlements.is_empty(),"no unearned fee for missed appointment")
	var db := Repo.new("user://zt_rebuild/b2_recovery_"+str(Time.get_ticks_usec()))
	check(db.save_session(s,"recovery").ok,"overdue property persisted")
	var cold: RefCounted = recovery_fresh()
	check(cold != null and db.load_session(cold,"recovery").ok and cold.snapshot() == overdue,"overdue title and expenses cold replay")
	if not check(go(s,"alpha_next_day") and go(s,"alpha_prepare_day") and go(s,"alpha_open"),"D3 opens after due date"):
		return
	check(s.alpha_view().remaining == source.alpha_profile.days[2].size(),"D3 has exactly one conditional finite recovery visit")
	var found: bool = false
	for i: int in range(source.alpha_profile.days[2].size()):
		if not go(s,"alpha_next_customer") or not go(s,"alpha_ack_entry"):
			return
		if s.alpha_view().active.actor_id == "G02":
			found = true
			break
		if not leave(s):
			return
	if not check(found,"real G02 reappears in D3 slot"):
		return
	check(s.alpha_view().services.entries[0].can_deliver,"D3 paid pickup is authorized for previously repaired W001")
	check(deny(s,"alpha_service_deliver",{"job_id":"forged"}),"forged recovery invoice rejected")
	check(go(s,"alpha_service_deliver",{"job_id":"service_w001"}),"D3 paid return executes same actual object and wallet transfer")
	var after: Dictionary = s.snapshot()
	check(after.items.W001.owner_id == "G02" and after.items.W001.custodian_id == "G02" and after.items.W001.inventory == "G02_grid" and after.items.W001.functional,"returned original physical W001 and ownership")
	check(after.wallets.player.VKC == 200 and after.alpha_shop.services.settlements.size() == 1 and after.ledger.is_empty(),"late fee charged once; no counterfeit retail ledger")
	check(deny(s,"alpha_service_deliver",{"job_id":"service_w001"}),"late return cannot charge twice")
	check(db.save_session(s,"recovery").ok,"late return saved")
	var after_cold: RefCounted = recovery_fresh()
	check(after_cold != null and db.load_session(after_cold,"recovery").ok and after_cold.snapshot() == after,"late return cold replay exact")
	var tamper: Dictionary = after.duplicate(true)
	tamper.alpha_shop.services.settlements[0].paid.VKC = 300
	check(not s.restore(tamper) and s.snapshot() == after,"tampered late fee rejected")

## Two different civilian owners keep independent titles, work-cost events,
## custody slots, real fee wallets and appointments in ONE save/authority.
func service_entry(view: Dictionary, job_id: String) -> Dictionary:
	for entry: Dictionary in view.services.entries:
		if entry.job_id == job_id:
			return entry
	return {}

func multi() -> void:
	var source: Dictionary = MultiSeed.content()
	var original: Dictionary = RecoverySeed.content()
	if not check(not source.is_empty() and not original.is_empty(),"multi profile reuses prior recovery source"):
		return
	check(source.state == original.state and source.state.items.W002S.owner_id == "G04" and source.state.items.W001.owner_id == "G02" and source.state.wallets == original.state.wallets,"two real customer items and existing finite wallets, no mint")
	check(source.alpha_profile.days[0] == original.alpha_profile.days[0] and source.alpha_profile.days[1] == original.alpha_profile.days[1],"old first two day appointments unchanged")
	var s: RefCounted = multi_fresh()
	if not check(s != null,"two-customer authority initializes with a separate slot"):
		return
	var before: Dictionary = s.snapshot()
	if not check(g02_offer(s) and go(s,"alpha_service_accept",{"job_id":"service_w001"}) and evening(s),"D1 G02 gives explicit custody"):
		return
	check(go(s,"alpha_service_repair",{"job_id":"service_w001","item_id":"W001"}),"G02 actual ten VKC restoration in D1 evening")
	if not check(day2(s) and active(s,"G03") and leave(s) and active(s,"G04"),"D2 G04 visits ordinary counter while G02 equipment stays held"):
		return
	var g04_offer: Dictionary = s.alpha_view()
	check(not service_entry(g04_offer,"service_w002s").is_empty() and service_entry(g04_offer,"service_w002s").can_accept,"G04 own W002S service is proposed on existing actual D2 visit")
	check(deny(s,"alpha_service_accept",{"job_id":"service_w001"}),"cannot accept G02 job under G04 authority")
	check(go(s,"alpha_service_accept",{"job_id":"service_w002s"}),"second customer consents to distinct physical custody")
	var held: Dictionary = s.snapshot()
	check(held.items.W001.owner_id == "G02" and held.items.W002S.owner_id == "G04" and held.items.W001.custodian_id == "player" and held.items.W002S.custodian_id == "player","both objects kept customer-owned in real custody")
	check(held.items.W001.inventory == "service_grid" and held.items.W002S.inventory == "service_grid" and held.items.W001.y == 0 and held.items.W002S.y == 1,"two separate existing grid rows, not overlapping virtual slots")
	check(held.wallets.player.VKC == 170 and held.ledger.is_empty(),"two custody acceptances provide no phantom fee")
	check(deny(s,"alpha_display",{"item_id":"W002S","x":0,"y":0,"rotated":false}),"second customer's entrusted equipment cannot be listed")
	if not check(leave(s) and go(s,"alpha_close") and go(s,"alpha_settle"),"D2 missed G02 collection while G04 stays in custody"):
		return
	check(s.snapshot().alpha_shop.services.jobs.service_w001.status == "overdue_custody" and s.snapshot().alpha_shop.services.jobs.service_w002s.status == "accepted","independent late-vs-current service statuses")
	check(go(s,"alpha_service_repair",{"job_id":"service_w002s","item_id":"W002S"}),"G04 real D2 evening restoration costs another ten VKC")
	var repaired: Dictionary = s.snapshot()
	check(repaired.wallets.player.VKC == 160 and repaired.items.W001.functional and repaired.items.W002S.functional and repaired.items.W001.owner_id == "G02" and repaired.items.W002S.owner_id == "G04","two actual restoration charges, same physical goods")
	check(repaired.object_events.size() == before.object_events.size()+2,"two separate real restoration events")
	var db := Repo.new("user://zt_rebuild/b2_multi_custody_"+str(Time.get_ticks_usec()))
	check(db.save_session(s,"multi").ok,"two live customer-owned service items cold-saved")
	var cold: RefCounted = multi_fresh()
	check(cold != null and db.load_session(cold,"multi").ok and cold.snapshot() == repaired,"both owner/custodian/statuses and expenses cold replay")
	if not check(go(s,"alpha_next_day") and go(s,"alpha_prepare_day") and go(s,"alpha_open"),"D3 opens after original two bounded appointment dates"):
		return
	check(s.alpha_view().remaining == source.alpha_profile.days[2].size(),"two appointments count as real finite D3 visits")
	for actor: String in ["G08","G09","G10","G11","G02","G04"]:
		if not check(active(s,actor),"D3 real visitor "+actor):
			return
		if actor in ["G02","G04"]:
			var job_id: String = "service_w001" if actor == "G02" else "service_w002s"
			var item_id: String = "W001" if actor == "G02" else "W002S"
			check(not service_entry(s.alpha_view(),job_id).is_empty() and service_entry(s.alpha_view(),job_id).can_deliver and not service_entry(s.alpha_view(),"service_w002s" if actor == "G02" else "service_w001").can_deliver,"actual "+actor+" may collect only their own restored item")
			check(deny(s,"alpha_service_deliver",{"job_id":"forged"}),"fake multi-customer invoice rejected")
			check(go(s,"alpha_service_deliver",{"job_id":job_id}),"named original object "+item_id+" returned to "+actor+" and paid once")
			check(s.snapshot().items[item_id].owner_id == actor and s.snapshot().items[item_id].custodian_id == actor and s.snapshot().items[item_id].inventory == actor+"_grid","physical title and original grid restored for "+actor)
			check(deny(s,"alpha_service_deliver",{"job_id":job_id}),"duplicate fee denied for "+actor)
			if not go(s,"alpha_ack_exit"):
				return
		elif not leave(s):
			return
	var after: Dictionary = s.snapshot()
	check(after.wallets.player.VKC == 230 and after.alpha_shop.services.settlements.size() == 2 and after.ledger.is_empty(),"two real fees 30+40 minus two ten-cost jobs, no virtual retail entries")
	check(after.wallets.G02.VKC == before.wallets.G02.VKC-30 and after.wallets.G04.VKC == before.wallets.G04.VKC-40,"each customer's finite actual cash debited only for own repair")
	check(after.items.size() == before.items.size() and after.alpha_shop.services.jobs.service_w001.status == "delivered" and after.alpha_shop.services.jobs.service_w002s.status == "delivered","no equipment duplication, independent settlements complete")
	check(db.save_session(s,"multi").ok,"two-job settlement save committed")
	var delivered: RefCounted = multi_fresh()
	check(delivered != null and db.load_session(delivered,"multi").ok and delivered.snapshot() == after,"full two-fee snapshot cold replay exact")
	var tamper: Dictionary = after.duplicate(true)
	tamper.alpha_shop.services.settlements[1].paid.VKC = 400
	check(not s.restore(tamper) and s.snapshot() == after,"cross-customer forged fee cannot replay")
	# Separate refusal branch: neither rejected job may steal a future
	# appointment slot, manufacture a customer or create a service fee.
	var declined_multi: RefCounted = multi_fresh()
	if not check(declined_multi != null and g02_offer(declined_multi),"independent refusal sequence enters G02 D1"):
		return
	check(go(declined_multi,"alpha_service_decline",{"job_id":"service_w001"}) and evening(declined_multi) and day2(declined_multi),"G02 declined; D2 still opens")
	if not check(active(declined_multi,"G03") and leave(declined_multi) and active(declined_multi,"G04"),"G04 original D2 visit available without G02 appointment"):
		return
	check(go(declined_multi,"alpha_service_decline",{"job_id":"service_w002s"}) and leave(declined_multi) and go(declined_multi,"alpha_close") and go(declined_multi,"alpha_settle"),"second refusal creates no held item")
	check(go(declined_multi,"alpha_next_day") and go(declined_multi,"alpha_prepare_day") and go(declined_multi,"alpha_open"),"D3 after both declines")
	var untouched_multi: Dictionary = declined_multi.snapshot()
	check(declined_multi.alpha_view().remaining == 4 and untouched_multi.wallets.player.VKC == 180,"both unaccepted return appointments excluded from finite D3 capacity")
	check(untouched_multi.items.W001.custodian_id == "G02" and untouched_multi.items.W002S.custodian_id == "G04" and untouched_multi.alpha_shop.services.settlements.is_empty(),"declining both jobs preserves titles and zero fees")

func _initialize() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=1 or args[0] not in ["happy","declined","unpaid","overdue","recovery","multi"]:
		quit(2)
		return
	match args[0]:
		"happy": happy()
		"declined": declined()
		"unpaid": unpaid()
		"overdue": overdue()
		"recovery": recovery()
		"multi": multi()
	print("ALPHA_B2_SERVICE_CHECKS part=",args[0]," checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
