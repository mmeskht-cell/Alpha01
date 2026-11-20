extends SceneTree
const Session = preload("res://src/domain/game_session.gd")
const Fixture = preload("res://tests/fixtures/gate0_c_state.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
const Audit = preload("res://src/domain/calendar_identity_audit.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func fresh(mode: String = "", reaction:bool=false, official:bool=false, local_public:bool=true) -> RefCounted:
	var seed: Dictionary = Fixture.make()
	seed.visits = {}
	seed.wallets.player = {"VKC":180, "USD":7}
	seed.wallets.seller = {"VKC":30, "USD":3}
	seed.inventories["service_grid"] = {"owner_id":"player", "width":10, "height":6, "host_item":""}
	seed.items.X01.basis = {"VKC":12,"USD":0}
	var days: Array = []
	var schedule: Dictionary = {}
	for i: int in range(7):
		var day: String = "d" + str(i+1)
		days.append(day)
		schedule[day] = []
	schedule.d1 = ["offer"]
	schedule.d2 = ["pickup"]
	schedule.d3 = ["retry"]
	var t: Dictionary = {"offer_id":"offer", "return_ids":["pickup","retry"], "item_id":"X01", "customer":"seller", "fee":{"VKC":30,"USD":0}, "placement":{"inventory":"service_grid","x":0,"y":0,"rotated":false}}
	if mode == "bad_day":
		t.return_ids = ["retry","pickup"]
	if mode == "poor":
		seed.wallets.player = {"VKC":15,"USD":7}
	if mode == "fee_short":
		seed.items["sale_item"] = Objects.fresh_item("sample_consumable","player","player_grid",0,0,"fixture_sale")
		seed.visits["sale_before"] = Fixture.visit("sale_before","player","seller",{"sale_item":{"VKC":25,"USD":0}})
		seed.visits.sale_before.opens = 1440
		seed.visits.sale_before.expires = 2040
		schedule.d2.push_front("sale_before")
	if mode == "collision":
		seed.items["blocker"] = Objects.fresh_item("sample_consumable","player","service_grid",0,0,"fixture_blocker")
	var profile: Dictionary = {"id":"demo_7","content_version":"service-1","day_ids":days,"visit_days":schedule,"services":{"job":t}}
	if reaction:
		seed.wallets.seller.VKC=60
		seed.items["followup_item"]=Objects.fresh_item("sample_consumable","player","player_grid",0,0,"fixture_followup")
		seed.visits["followup"]=Fixture.visit("followup","player","seller",{"followup_item":{"VKC":20,"USD":0}})
		seed.visits.followup.opens=2880
		seed.visits.followup.expires=3480
		schedule.d3.append("followup")
		profile["reaction_rules"]={"market_d3":{"day":3,"service_id":"job","opportunity_id":"followup","local_public":local_public,"organization_id":"merchant_network" if official else ""}}
	var s := Session.new()
	return s if s.initialize(Fixture.definitions(), seed, false, false, profile) else null

func cmd(s: RefCounted, kind: String, id: String, p: Dictionary = {}) -> Dictionary:
	return {"action_id":id,"expected_revision":s.snapshot().revision,"type":kind,"payload":p}

func act(s: RefCounted, kind: String, id: String, p: Dictionary = {}) -> bool:
	return s.execute(cmd(s,kind,id,p)).ok

func reject(s: RefCounted, kind: String, id: String, p: Dictionary = {}) -> bool:
	var before: Dictionary = s.snapshot()
	return not act(s,kind,id,p) and s.snapshot() == before

func begin(s: RefCounted) -> bool:
	return act(s,"calendar_next_visit","call") and act(s,"calendar_accept_service","accept",{"visit_id":"offer","job_id":"job"})

func night(s: RefCounted) -> bool:
	return act(s,"calendar_close","close1")

func work(s: RefCounted) -> bool:
	return act(s,"restore_item","repair",{"actor":"player","item_id":"X01"})

func morning(s: RefCounted) -> bool:
	return act(s,"calendar_morning","morning1")

func _initialize() -> void:
	var s: RefCounted = fresh()
	check(s != null, "service profile")
	if s == null:
		quit(1)
		return
	check(fresh("bad_day") == null, "ordered later pickup days")
	check(not Audit.begin(s).is_empty() and Audit.sleep(Audit.begin(s),"X01",s).is_empty(),"offered service protected before custody")
	var accept: Dictionary = {"visit_id":"offer","job_id":"job"}
	var pickup: Dictionary = {"visit_id":"pickup","job_id":"job"}
	check(s.calendar_view().services.is_empty() and s.calendar_view().visits.terms.is_empty(), "future terms hidden")
	check(reject(s,"calendar_accept_service","early",accept), "no early accept")
	check(act(s,"calendar_next_visit","call") and s.calendar_view().visits.terms.kind == "service_offer", "offer admitted")
	check(reject(s,"calendar_accept_service","wrong",{"visit_id":"offer","job_id":"bad"}), "wrong job")
	var request: Dictionary = cmd(s,"calendar_accept_service","accept",accept)
	check(s.execute(request).ok, "accept custody")
	var accepted: Dictionary = s.snapshot()
	check(not Audit.begin(s).is_empty() and Audit.sleep(Audit.begin(s),"X01",s).is_empty(),"accepted service cannot sleep")
	check(s.execute(request).ok and s.snapshot() == accepted, "duplicate accept")
	check(s.calendar_view().visits.outcomes.offer == "service_accepted" and s.calendar_view().services.job.status == "accepted", "visit closes, job accepted")
	check(accepted.wallets.player.VKC == 180 and accepted.ledger.is_empty(), "no fee or sale at acceptance")
	for id: String in Objects.family(accepted,"X01"):
		check(accepted.items[id].owner_id == "seller" and accepted.items[id].custodian_id == "player" and accepted.items[id].status == "custody_service", "same family custody " + id)
	check(reject(s,"restore_item","daywork",{"actor":"player","item_id":"X01"}), "no daytime work")
	check(night(s), "night")
	check(reject(s,"detach","takepart",{"actor":"player","root_id":"X01","child_id":"X02","inventory":"player_grid","x":0,"y":0,"rotated":false}), "no disposition on custody")
	check(work(s), "actual existing restoration")
	var worked: Dictionary = s.snapshot()
	check(worked.wallets.player == {"VKC":160,"USD":5} and worked.items.X01.basis == {"VKC":12,"USD":0}, "cost not inventory basis")
	check(worked.object_events.size() == 1 and worked.object_events[0].type == "restore_item" and s.calendar_view().services.job.status == "complete", "actual work event")
	var public_work: Dictionary = s.calendar_item_history("X01")
	check(public_work.records.is_empty() and public_work.work_records.size()==1 and public_work.work_records[0].expense=={"VKC":5,"USD":2}, "custody service work is not purchase or sale")
	check(s.calendar_history_index().items.size()==1 and s.snapshot()==worked,"service work appears without authority mutation")
	check(reject(s,"restore_item","again",{"actor":"player","item_id":"X01"}), "no repeated work")
	check(reject(s,"calendar_deliver_service","nightpay",pickup), "no early fee")
	check(morning(s) and act(s,"calendar_next_visit","pickupcall"), "day2 pickup")
	var delivery: Dictionary = cmd(s,"calendar_deliver_service","pay",pickup)
	check(s.execute(delivery).ok, "paid actual return")
	var final: Dictionary = s.snapshot()
	var returned:Dictionary=Audit.sleep(Audit.begin(s),"X01",s)
	check(not returned.is_empty() and Audit.audit(returned,s).items.X01_A=="dormant" and s.snapshot()==final,"returned family partition preserves history")
	check(final.wallets.player == {"VKC":190,"USD":5} and final.wallets.seller.VKC == 0 and final.ledger.is_empty(), "fee not sales ledger")
	check(s.calendar_item_history("X01")==public_work,"historical work retained after return; no sale invented")
	check(final.items.X01.inventory == "seller_grid" and final.items.X01.functional and final.items.X01.basis == {"VKC":12,"USD":0}, "same item restored and returned")
	for id: String in Objects.family(final,"X01"):
		check(final.items[id].owner_id == "seller" and final.items[id].custodian_id == "seller" and final.items[id].status == "stock" and not final.items[id].service_permission, "family returned " + id)
	check(s.execute(delivery).ok and s.snapshot() == final, "no duplicate payment")
	check(s.calendar_view().services.job.status == "delivered" and s.calendar_view().visits.outcomes.pickup == "service_delivered", "settlement state")
	var restored: RefCounted = fresh()
	check(restored.restore(final), "cold exact replay")
	var fake: Dictionary = final.duplicate(true)
	fake.calendar.services.jobs.job.paid.VKC += 1
	check(not restored.restore(fake) and restored.snapshot() == final, "tampered fee")
	fake = final.duplicate(true)
	fake.items.X01.custodian_id = "player"
	check(not restored.restore(fake), "tampered custody")
	var repo := Repo.new("user://zt_rebuild/service_" + str(Time.get_ticks_usec()))
	check(repo.save_session(s,"service").ok, "disk save")
	var loaded: RefCounted = fresh()
	check(repo.load_session(loaded,"service").ok and loaded.snapshot() == final, "disk load")
	check(act(s,"calendar_close","close2") and act(s,"calendar_morning","morning2") and s.calendar_view().visits.remaining == 0, "fulfilled retry suppressed")
	check(reject(s,"calendar_next_visit","dup_pickup"), "no same job again")
	var cancelled: RefCounted = fresh()
	check(begin(cancelled) and night(cancelled) and morning(cancelled) and act(cancelled,"calendar_next_visit","returncall"), "unworked return setup")
	check(reject(cancelled,"calendar_deliver_service","unearned",pickup), "unearned fee denied")
	check(act(cancelled,"calendar_return_unpaid","cancel",pickup) and cancelled.calendar_view().services.job.status == "cancelled" and cancelled.snapshot().wallets.player.VKC == 165, "return unfinished no fee")
	var poor: RefCounted = fresh("poor")
	check(begin(poor) and night(poor) and reject(poor,"restore_item","unfunded",{"actor":"player","item_id":"X01"}), "insufficient work cash unchanged")
	var blocked: RefCounted = fresh("collision")
	check(act(blocked,"calendar_next_visit","blockcall") and reject(blocked,"calendar_accept_service","blocked",accept), "grid collision atomic")
	var declined: RefCounted = fresh()
	check(act(declined,"calendar_next_visit","dcall") and act(declined,"calendar_decline_visit","decline",{"visit_id":"offer"}) and night(declined) and morning(declined) and declined.calendar_view().visits.remaining == 0, "declined service no pickup")
	var retry: RefCounted = fresh()
	check(begin(retry) and night(retry) and work(retry) and morning(retry) and act(retry,"calendar_close","close2") and act(retry,"calendar_morning","morning2"), "missed pickup retains job")
	check(act(retry,"calendar_next_visit","retrycall") and act(retry,"calendar_deliver_service","retryfee",{"visit_id":"retry","job_id":"job"}), "later real pickup")
	var short: RefCounted = fresh("fee_short")
	check(begin(short) and night(short) and work(short) and morning(short) and act(short,"calendar_next_visit","sale_call"), "fee-short setup")
	check(act(short,"trade","sale",{"visit_id":"sale_before","item_id":"sale_item","seller":"player","buyer":"seller","currency":"VKC","amount":25,"inventory":"seller_grid","x":8,"y":0,"rotated":false}), "customer spends actual money")
	check(act(short,"calendar_next_visit","pick_call") and reject(short,"calendar_deliver_service","no_money",pickup), "insufficient customer funds")
	check(act(short,"calendar_return_unpaid","waive",pickup) and short.calendar_view().services.job.status == "returned_unpaid" and short.snapshot().wallets.player.VKC == 185, "explicit unpaid return")
	_reaction_tests()
	print("GATE2_A1C2_SERVICE_CHECKS=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

func reaction_fixture()->RefCounted:
	return fresh("",true)

func _reaction_day2(s:RefCounted,fulfilled:bool)->bool:
	if not begin(s) or not night(s):
		return false
	if fulfilled and not work(s):
		return false
	if not morning(s) or not act(s,"calendar_next_visit","pickupcall"):
		return false
	return act(s,"calendar_deliver_service" if fulfilled else "calendar_return_unpaid","settlement",{"visit_id":"pickup","job_id":"job"})

func _reaction_tests()->void:
	var good:RefCounted=reaction_fixture()
	var bad:RefCounted=reaction_fixture()
	var official:RefCounted=fresh("",true,true,false)
	check(good!=null and bad!=null and official!=null,"P4 seed profiles")
	if good==null or bad==null or official==null:
		return
	for s:RefCounted in [good,bad,official]:
		check(s.calendar_view().world_news.news.is_empty() and s.snapshot().calendar.reaction.local==0,"no future public event")
	check(_reaction_day2(good,true) and _reaction_day2(bad,false) and _reaction_day2(official,true),"actual settlement and neutral cancellation paths")
	check(good.snapshot().calendar.reaction.local==0 and good.calendar_view().world_news.news.is_empty(),"not immediate score at settlement")
	for s:RefCounted in [good,bad,official]:
		check(act(s,"calendar_close","close2") and act(s,"calendar_morning","day3"),"same independent day3 event")
	var g:Dictionary=good.snapshot()
	var b:Dictionary=bad.snapshot()
	var o:Dictionary=official.snapshot()
	check(g.calendar.reaction.local==1 and g.calendar.reaction.organizations.is_empty() and g.calendar.reaction.contacts.seller==["settlement"],"private customer memory not automatic organization score")
	check(o.calendar.reaction.local==0 and o.calendar.reaction.organizations.merchant_network==1,"independent explicit official and local evaluation")
	check(b.calendar.reaction.local==0 and b.calendar.reaction.contacts.is_empty() and b.calendar.reaction.links.is_empty(),"cancellation no unearned penalty or link")
	check(g.calendar.reaction.events.market_d3.external_event==b.calendar.reaction.events.market_d3.external_event and g.calendar.reaction.market=="limited_service" and b.calendar.reaction.market=="interrupted","same external event different actual world state")
	check(good.calendar_view().visits.remaining==1 and bad.calendar_view().visits.remaining==0,"actual conditional appointment")
	check(reject(bad,"calendar_next_visit","no_link"),"no unearned opportunity")
	var n:Dictionary=good.calendar_view().world_news
	check(n.news.size()==1 and n.news[0].cause_refs==["market_disruption","settlement"] and bad.calendar_view().world_news.news[0].cause_refs==["market_disruption"] and n.news[0].ko!=n.news[0].en,"public report causal bilingual")
	check(not n.has("local") and not n.has("links") and not n.has("organizations") and good.snapshot()==g,"no private tier or mutation")
	var cold:RefCounted=reaction_fixture()
	check(cold.restore(g) and cold.snapshot()==g,"reaction exact replay")
	var forged:Dictionary=g.duplicate(true)
	forged.calendar.reaction.local=20
	check(not cold.restore(forged) and cold.snapshot()==g,"forged evaluation denied")
	check(act(good,"calendar_next_visit","followup_call") and good.calendar_view().visits.active=="followup","actual new customer opportunity")
	check(act(good,"trade","followup_sale",{"visit_id":"followup","item_id":"followup_item","seller":"player","buyer":"seller","currency":"VKC","amount":20,"inventory":"seller_grid","x":8,"y":0,"rotated":false}),"actual finite trade settles")
	var done:Dictionary=good.snapshot()
	check(done.wallets.player.VKC==g.wallets.player.VKC+20 and done.items.followup_item.owner_id=="seller" and done.calendar.reaction==g.calendar.reaction,"normal trade no automatic score")
	check(good.calendar_view().visits.remaining==0 and reject(good,"calendar_next_visit","again_followup"),"one finite opportunity")
	check(act(good,"calendar_close","close3") and act(good,"calendar_morning","day4") and good.snapshot().calendar.reaction==done.calendar.reaction,"no daily duplicate")
	var repo:=Repo.new("user://zt_rebuild/p4_"+str(Time.get_ticks_usec()))
	check(repo.save_session(good,"reaction").ok and repo.load_session(cold,"reaction").ok and cold.snapshot()==good.snapshot(),"disk save and replay")
