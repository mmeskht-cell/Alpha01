extends SceneTree
## B2 service commission: actual W001 stays owned by G02 throughout. Only
## custody, permitted restoration, fee and physical original-grid return move.
const Seed = preload("res://src/content/alpha_b2_service_seed.gd")
const Named = preload("res://src/content/alpha_b2_named_commission_seed.gd")
const Session = preload("res://src/domain/game_session.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
const Rules = preload("res://src/domain/value_rules.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const Component = preload("res://src/domain/component_appraisal.gd")
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
		printerr("B2_SERVICE_VALIDATION_GUARD=",s._validation_error)
		var diagnostic: Dictionary = s.snapshot()
		var action: Dictionary = command(s,"alpha_service_repair",{"job_id":"service_w001","item_id":"W001"})
		var failed: String = s._apply_alpha(diagnostic,action)
		if failed.is_empty():
			diagnostic.revision += 1
			diagnostic.receipts[action.action_id] = {"fingerprint":Rules.canonical(action),"result":{"ok":true,"revision":diagnostic.revision}}
			diagnostic.alpha_shop.commands.append(Rules.normalized(action))
			var evt: Dictionary = diagnostic.object_events.back()
			var rt: String = s._receipt_type(diagnostic,evt.event_id)
			printerr("B2_SERVICE_HISTORY_DETAIL type=",evt.type," receipt_type=",rt," event_revision=",evt.revision,
				" receipt_revision=",s._receipt_revision(diagnostic,evt.event_id),
				" events=",diagnostic.object_events.size()," ids=",s._ids_valid(diagnostic,evt.item_ids),
				" money_basis=",Objects.money(evt.basis)," money_expense=",Objects.money(evt.expenses,false),
				" component=",Component.valid_hypotheses(diagnostic)," history=",s._history_valid(diagnostic),
				" evt=",evt)
		else:
			printerr("B2_SERVICE_DIAG_APPLY_FAILED=",failed)
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

func _initialize() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=1 or args[0] not in ["happy","declined","unpaid","overdue"]:
		quit(2)
		return
	match args[0]:
		"happy": happy()
		"declined": declined()
		"unpaid": unpaid()
		"overdue": overdue()
	print("ALPHA_B2_SERVICE_CHECKS part=",args[0]," checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
