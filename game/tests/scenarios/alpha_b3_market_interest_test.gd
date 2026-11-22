extends SceneTree
## B3-M1 first real stock-dependent buyer. No virtual buyer, funds,
## fabricated restock, scripted story or automatic profitable settlement.
const Seed = preload("res://src/content/alpha_b3_market_seed.gd")
const B2 = preload("res://src/content/alpha_b2_service_multi_seed.gd")
const Market = preload("res://src/domain/alpha_b3_market_interest.gd")
const Capacity = preload("res://src/domain/alpha_b3_visit_capacity.gd")
const Session = preload("res://src/domain/game_session.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
const BUYER_VISIT: String = "alpha_b3_g09_radio_d2"
var checks: int=0
var failures: int=0

func check(ok: bool, why: String) -> bool:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",why)
	return ok

func fresh() -> RefCounted:
	var src: Dictionary=Seed.content()
	var s:=Session.new()
	if src.is_empty() or not s.initialize(src.defs,src.state,false,false,{},src.alpha_profile):
		printerr("B3_MARKET_BOOT ",s.initialization_error())
		return null
	return s

func command(s: RefCounted, kind: String, payload: Dictionary = {}) -> Dictionary:
	return {"action_id":"b3_market_"+str(s.snapshot().revision+1),
		"expected_revision":s.snapshot().revision,"type":kind,"payload":payload}

func go(s: RefCounted, kind: String, payload: Dictionary = {}) -> bool:
	var r: Dictionary=s.execute(command(s,kind,payload))
	if not bool(r.get("ok",false)):
		printerr("B3_COMMAND_FAIL ",kind," ",r)
	return bool(r.get("ok",false))

func denied(s: RefCounted, kind: String, payload: Dictionary = {}) -> bool:
	var prior: Dictionary=s.snapshot()
	return not bool(s.execute(command(s,kind,payload)).get("ok",false)) and s.snapshot()==prior

func trade(id: String, seller: String, buyer: String, amount: int, grid: String, x: int, y: int) -> Dictionary:
	return {"visit_id":id,"item_id":"R001","seller":seller,"buyer":buyer,
		"currency":"VKC","amount":amount,"inventory":grid,"x":x,"y":y,"rotated":false}

func _initialize() -> void:
	var base: Dictionary=B2.content()
	var src: Dictionary=Seed.content()
	if not check(not src.is_empty() and not base.is_empty(),"B3 opt-in seed extends exact published B2 multi service"):
		quit(1)
		return
	var old_count: int=base.state.visits.size()
	check(src.state.wallets==base.state.wallets and src.state.items==base.state.items
		and src.state.ledger==base.state.ledger and src.state.visits.size()==old_count+1,
		"one real prospective buyer visit added, no money/item/ledger changes")
	check(src.state.visits[BUYER_VISIT].prices.R001==base.state.visits.radio_recovery.prices.R001
		and int(src.state.wallets.G09.VKC)==130 and src.state.visits[BUYER_VISIT].buyer=="G09",
		"existing D2 original radio quote and already funded actor G09, not newly minted quote")
	var capacity: Dictionary=Capacity.audit(src)
	check(capacity.get("ok",false) and not capacity.ready
		and capacity.total_authored==27 and capacity.total_guaranteed==20
		and capacity.total_conditional==7
		and capacity.days[1].authored==7 and capacity.days[1].conditional==2,
		"new D2 buyer is conditional, never falsely counted as a guaranteed seventh visitor")
	var forged: Dictionary=src.duplicate(true)
	forged.state.visits[BUYER_VISIT].prices.R001.VKC=1
	check(not Capacity.audit(forged).get("ok",false),
		"cannot forge a cheap standalone future quote against the source visit")

	var s: RefCounted=fresh()
	if not check(s!=null,"B3 separate GameSession and content-binding initialize"):
		quit(1)
		return
	var starting: Dictionary=s.snapshot()
	check(not Market.eligible(starting,BUYER_VISIT)
		and starting.items.R001.owner_id=="G01",
		"future buyer cannot enter before actual acquisition/display of seller's item")
	check(denied(s,"alpha_trade",trade(BUYER_VISIT,"player","G09",130,"G09_grid",5,4)),
		"no early sale, no optional buyer materialization without admission")
	if not check(go(s,"alpha_open") and go(s,"alpha_next_customer") and go(s,"alpha_ack_entry"),
			"start same original B2 counter with G01"):
		quit(1)
		return
	if not check(go(s,"alpha_price_offer",{"amount":100})
			and go(s,"alpha_trade",trade("visit_g01","G01","player",100,"player_stock",0,0))
			and go(s,"alpha_ack_exit"),
			"real D1 G01 sale settled with original paid stock"):
		quit(1)
		return
	check(not Market.eligible(s.snapshot(),BUYER_VISIT),"owned radio not yet on market shelf")
	if not check(go(s,"alpha_display",{"item_id":"R001","x":0,"y":0,"rotated":false}),
			"real R001 displayed at physical inventory cell"):
		quit(1)
		return
	check(Market.eligible(s.snapshot(),BUYER_VISIT)
		and s.snapshot().items.R001.inventory=="storefront_grid",
		"actual player shelf and already funded G09 enable prospective buyer")
	var empty_wallet: Dictionary=s.snapshot()
	empty_wallet.wallets.G09.VKC=0
	check(not Market.eligible(empty_wallet,BUYER_VISIT),
		"unfunded buyer cannot visit; the market does not grant currency")
	check(go(s,"alpha_close") and go(s,"alpha_settle") and go(s,"alpha_next_day")
		and go(s,"alpha_prepare_day") and go(s,"alpha_open"),
		"day boundary preserves genuine item display and conditional quote")
	var reached: bool=false
	var original_quote: int=int(starting.visits[BUYER_VISIT].prices.R001.VKC)
	for i in range(10):
		if not go(s,"alpha_next_customer"):
			break
		var id: String=str(s.alpha_view().active.id)
		if not go(s,"alpha_ack_entry"):
			break
		if id==BUYER_VISIT:
			reached=true
			check(s.alpha_view().active.actor_id=="G09" and original_quote==130,
				"only the actual funded G09 enters after earlier dated customers")
			check(denied(s,"alpha_trade",trade(BUYER_VISIT,"player","G09",1,"G09_grid",5,4)),
				"arbitrary invented sale price rejected before explicit agreement")
			if not go(s,"alpha_price_offer",{"amount":130}):
				break
			if not go(s,"alpha_trade",trade(BUYER_VISIT,"player","G09",130,"G09_grid",5,4)):
				break
			var after: Dictionary=s.snapshot()
			check(after.items.R001.owner_id=="G09" and after.items.R001.inventory=="G09_grid"
				and after.wallets.player.VKC==210 and after.wallets.G09.VKC==0
				and after.ledger.size()==2 and not Market.eligible(after,BUYER_VISIT),
				"one real item to G09, 130 VKC transferred once, no duplicate listing")
			var before_retry: Dictionary=after.duplicate(true)
			check(denied(s,"alpha_trade",trade(BUYER_VISIT,"player","G09",130,"G09_grid",5,4))
				and s.snapshot()==before_retry,
				"sale is single-settlement and cannot be replayed as a new transaction")
			break
		if not go(s,"alpha_finish_customer") or not go(s,"alpha_ack_exit"):
			break
	check(reached,"real D2 market buyer is actually admitted when store has the good")
	var saved: Dictionary=s.snapshot()
	var repo:=Repo.new("user://zt_rebuild/b3_market_m1_"+str(Time.get_ticks_usec()))
	check(repo.save_session(s,"b3_market_m1").get("ok",false),"B3 isolated A/B generation saved")
	var cold: RefCounted=fresh()
	check(cold!=null and repo.load_session(cold,"b3_market_m1").get("ok",false)
		and cold.snapshot()==saved,
		"B3 A/B cold replay recovers same R001, actual currency and G09 buyer")
	var old_seed: Dictionary=B2.content()
	var legacy:=Session.new()
	check(legacy.initialize(old_seed.defs,old_seed.state,false,false,{},old_seed.alpha_profile)
		and not legacy.restore(saved),
		"B2 profile refuses to import new B3 market commands or economic state")

	var no_goods: RefCounted=fresh()
	if check(no_goods!=null,"independent no-stock refusal path"):
		check(go(no_goods,"alpha_open") and go(no_goods,"alpha_close") and go(no_goods,"alpha_settle")
			and go(no_goods,"alpha_next_day") and go(no_goods,"alpha_prepare_day")
			and go(no_goods,"alpha_open"),"skip Day1 without phantom radio purchase")
		check(not Market.eligible(no_goods.snapshot(),BUYER_VISIT)
			and no_goods.snapshot().items.R001.owner_id=="G01"
			and no_goods.snapshot().wallets==starting.wallets,
			"player without R001 cannot attract market buyer or receive cash")
		var seen: Array=[]
		for i in range(10):
			if int(no_goods.alpha_view().remaining)==0:
				break
			if not go(no_goods,"alpha_next_customer"):
				break
			var id: String=str(no_goods.alpha_view().active.id)
			seen.append(id)
			if not (go(no_goods,"alpha_ack_entry")
					and go(no_goods,"alpha_finish_customer")
					and go(no_goods,"alpha_ack_exit")):
				break
		check(BUYER_VISIT not in seen and no_goods.snapshot().wallets==starting.wallets
			and no_goods.snapshot().ledger.is_empty(),
			"conditional buyer excluded from real admission and economic ledger without stock")
	print("ALPHA_B3_MARKET_INTEREST_CHECKS=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
