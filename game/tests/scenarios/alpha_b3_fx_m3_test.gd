extends SceneTree
## Real two-wallet FX, inherited 30 VKC / 1 USD quote, no invented exchange
## revenue, one settlement per quote, and M2/B2 save isolation.
const Source=preload("res://src/content/alpha_b3_fx_seed.gd")
const M2=preload("res://src/content/alpha_b3_market_m2_seed.gd")
const B2=preload("res://src/content/alpha_b2_service_multi_seed.gd")
const Fx=preload("res://src/domain/alpha_b3_fx.gd")
const Capacity=preload("res://src/domain/alpha_b3_visit_capacity.gd")
const Session=preload("res://src/domain/game_session.gd")
const Repo=preload("res://src/persistence/save_repository.gd")
var checks: int=0
var failures: int=0

func check(ok: bool, why: String) -> bool:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",why)
	return ok

func fresh(source: Dictionary) -> RefCounted:
	var s:=Session.new()
	if source.is_empty() or not s.initialize(source.defs,source.state,false,false,{},source.alpha_profile):
		printerr("B3_FX_INIT_ERROR ",s.initialization_error())
		return null
	return s

func command(s: RefCounted, action: String, payload: Dictionary={}) -> Dictionary:
	return {"action_id":"b3_fx_m3_"+str(s.snapshot().revision+1),
		"expected_revision":s.snapshot().revision,"type":action,"payload":payload}

func go(s: RefCounted, action: String, payload: Dictionary={}) -> bool:
	var r: Dictionary=s.execute(command(s,action,payload))
	if not r.get("ok",false):
		printerr("B3_FX_COMMAND_FAILED ",action," ",r)
	return r.get("ok",false)

func denied(s: RefCounted, action: String, payload: Dictionary={}) -> bool:
	var before: Dictionary=s.snapshot()
	var r: Dictionary=s.execute(command(s,action,payload))
	return not r.get("ok",false) and s.snapshot()==before

func _initialize() -> void:
	var src: Dictionary=Source.content()
	var m2: Dictionary=M2.content()
	var b2: Dictionary=B2.content()
	if not check(not src.is_empty() and not m2.is_empty() and not b2.is_empty(),
			"B3 FX extends exact existing M2/B2 source without replacing them"):
		quit(1)
		return
	check(src.state.items==m2.state.items and src.state.ledger==m2.state.ledger
		and src.state.visits==m2.state.visits and src.state.wallets.size()==m2.state.wallets.size()+1,
		"FX adds a single real broker wallet and no goods/stock/visit-transaction mint")
	check(src.state.wallets.alpha_broker=={"VKC":100,"USD":5}
		and src.state.inventories.alpha_broker_grid.owner_id=="alpha_broker"
		and src.state.wallets.player==m2.state.wallets.player,
		"broker seeded with exact existing alpha42 fixture balances")
	var q: Dictionary=Fx.config()
	check(q.give_amount==30 and q.receive_amount==1 and q.counterparty=="alpha_broker"
		and q.source_profile=="alpha42_mechanics",
		"pre-existing broker quote not a new speculative currency rate")
	var review: Dictionary=Capacity.audit(src)
	check(review.get("ok",false) and review.total_authored==35
		and review.total_guaranteed==21 and review.total_conditional==14
		and review.days[6].authored==3 and review.days[6].guaranteed==1
		and not review.ready,
		"D7 broker is a substantive funded visit, not completion of B3 daily quotas")
	var invalid: Dictionary=src.duplicate(true)
	invalid.alpha_profile.fx_profile.give_amount=1
	check(not Fx.profile_valid(invalid.alpha_profile,invalid.state)
		and fresh(invalid)==null,
		"quote substitution fails original rate/data and session validation")
	invalid=src.duplicate(true)
	invalid.state.wallets.alpha_broker.USD=0
	check(not Fx.profile_valid(invalid.alpha_profile,invalid.state)
		and fresh(invalid)==null,
		"broker with no real foreign-currency liquidity cannot issue quote")

	var s: RefCounted=fresh(src)
	if not check(s!=null,"isolated B3-FX session creates with real actor/quote binding"):
		quit(1)
		return
	var baseline: Dictionary=s.snapshot()
	check(denied(s,"alpha_fx_trade",{"quote_id":"alpha_broker_quote"}),
		"early FX is rejected, even if player has money")
	for day: int in range(1,8):
		if not check(go(s,"alpha_open"),"open day "+str(day)):
			quit(1)
			return
		if day<7:
			if not check(go(s,"alpha_close") and go(s,"alpha_settle")
					and go(s,"alpha_next_day") and go(s,"alpha_prepare_day"),
					"advance real clockless day "+str(day)):
				quit(1)
				return
	var v: Dictionary=s.alpha_view()
	check(v.day==7 and v.phase=="OPEN_IDLE" and v.remaining==1
		and v.fx.get("settled",true)==false,
		"only one actual funded FX visit survives unowned market offers on D7")
	if not check(go(s,"alpha_next_customer") and s.alpha_view().active.id=="alpha_b3_fx_broker_d7"
		and go(s,"alpha_ack_entry"),"real broker at the same physical counter on D7"):
		quit(1)
		return
	v=s.alpha_view()
	check(v.fx.can_exchange and v.fx.funded
		and v.fx.give_amount==30 and v.fx.receive_amount==1,
		"UI exposes exact affordable VKC/USD quote when broker present")
	check(denied(s,"alpha_fx_trade",{"quote_id":"alpha_wrong_quote"})
		and denied(s,"alpha_fx_trade",{"quote_id":"alpha_broker_quote","amount":1}),
		"caller cannot change source quote or invent exchange amount")
	var first: Dictionary=command(s,"alpha_fx_trade",{"quote_id":"alpha_broker_quote"})
	var completed: Dictionary=s.execute(first)
	check(bool(completed.get("ok",false)),"one authorized real FX settlement succeeds")
	var after: Dictionary=s.snapshot()
	check(after.wallets.player.VKC==150 and after.wallets.player.USD==1
		and after.wallets.alpha_broker.VKC==130 and after.wallets.alpha_broker.USD==4,
		"paired cash balances conserve VKC and USD separately")
	check(after.ledger==baseline.ledger and after.items==baseline.items
		and after.alpha_shop.fx.settlements.size()==1
		and after.alpha_shop.fx.settlements.alpha_broker_quote.event_id==first.action_id,
		"no fake item ledger entry and exactly one cited FX settlement")
	check(s.execute(first)==completed and s.snapshot()==after,
		"same action ID is idempotent and cannot repay exchange again")
	check(denied(s,"alpha_fx_trade",{"quote_id":"alpha_broker_quote"})
		and not s.alpha_view().fx.can_exchange and s.alpha_view().fx.settled,
		"new action ID cannot double-settle same source quote")
	var saved: Dictionary=s.snapshot()
	var store:=Repo.new("user://zt_rebuild/b3_fx_m3_"+str(Time.get_ticks_usec()))
	check(store.save_session(s,"b3_fx_m3").get("ok",false),"new B3 FX isolated A/B save accepted")
	var cold: RefCounted=fresh(src)
	check(cold!=null and store.load_session(cold,"b3_fx_m3").get("ok",false)
		and cold.snapshot()==saved,"cold restore replays both wallets and settlement receipt exactly")
	var old: RefCounted=fresh(m2)
	check(old!=null and not old.restore(saved),"M2 version rejects new broker money and FX save")
	old=fresh(b2)
	check(old!=null and not old.restore(saved),"B2 profile cannot load new B3 FX save")

	check(go(s,"alpha_finish_customer") and go(s,"alpha_ack_exit")
		and go(s,"alpha_close") and go(s,"alpha_settle")
		and go(s,"alpha_next_day") and s.snapshot().alpha_shop.phase=="COMPLETE",
		"real seven-day B3 FX trade reaches settled completed shop without new clocks")
	print("ALPHA_B3_FX_M3_CHECKS=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
